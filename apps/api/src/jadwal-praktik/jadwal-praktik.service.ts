import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  HariLayanan,
  PeranPengguna,
  Prisma,
} from '../generated/prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CariJadwalPraktikDto } from './dto/cari-jadwal-praktik.dto';
import { CreateJadwalPraktikDto, POLA_TANGGAL } from './dto/create-jadwal-praktik.dto';
import { UpdateJadwalPraktikDto } from './dto/update-jadwal-praktik.dto';

type Transaksi = Prisma.TransactionClient;

type JadwalInput = {
  dokterLayananId: string;
  loketId: string;
  tanggal: string;
  mulaiPada: string;
  selesaiPada: string;
};

const detailJadwal = {
  dokterLayanan: {
    include: {
      dokter: { select: { id: true, kode: true, nama: true, spesialisasi: true, aktif: true } },
      layanan: { select: { id: true, kode: true, nama: true, aktif: true } },
    },
  },
  loket: { select: { id: true, kode: true, nama: true, layananId: true, aktif: true } },
} as const;

const hariBerurutan: HariLayanan[] = [
  HariLayanan.MINGGU,
  HariLayanan.SENIN,
  HariLayanan.SELASA,
  HariLayanan.RABU,
  HariLayanan.KAMIS,
  HariLayanan.JUMAT,
  HariLayanan.SABTU,
];

@Injectable()
export class JadwalPraktikService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  async create(dto: CreateJadwalPraktikDto) {
    const waktu = this.parseWaktu(dto);
    try {
      return await this.prisma.$transaction(async (tx) => {
        const pasangan = await this.pastikanRelasiAktif(tx, dto.dokterLayananId, dto.loketId);
        await this.kunciSumberDaya(tx, [
          `dokter:${pasangan.dokterId}`,
          `ruang:${dto.loketId}`,
        ]);
        await this.validasiOperasional(tx, pasangan.layananId, waktu);
        await this.pastikanTidakBentrok(tx, pasangan.dokterId, dto.loketId, waktu);
        return tx.jadwalPraktik.create({
          data: {
            dokterLayananId: dto.dokterLayananId,
            loketId: dto.loketId,
            tanggal: waktu.tanggal,
            mulaiPada: waktu.mulai,
            selesaiPada: waktu.selesai,
            aktif: true,
          },
          include: detailJadwal,
        });
      });
    } catch (error: unknown) {
      this.handleDatabaseError(error);
    }
  }

  findAll(peran: PeranPengguna, query: CariJadwalPraktikDto = {}) {
    const admin = peran === PeranPengguna.ADMIN;
    const where: Prisma.JadwalPraktikWhereInput = {
      ...(query.tanggal ? { tanggal: this.parseTanggal(query.tanggal) } : {}),
      ...(!admin
        ? {
            aktif: true,
            loket: { is: { aktif: true } },
          }
        : {}),
      ...((query.dokterId || query.layananId || !admin)
        ? {
            dokterLayanan: {
              is: {
                ...(query.dokterId ? { dokterId: query.dokterId } : {}),
                ...(query.layananId ? { layananId: query.layananId } : {}),
                ...(!admin
                  ? {
                      aktif: true,
                      dokter: { is: { aktif: true } },
                      layanan: { is: { aktif: true } },
                    }
                  : {}),
              },
            },
          }
        : {}),
    };
    return this.prisma.jadwalPraktik.findMany({
      where,
      include: detailJadwal,
      orderBy: [{ tanggal: 'asc' }, { mulaiPada: 'asc' }, { id: 'asc' }],
    });
  }

  async findOne(id: string, peran: PeranPengguna) {
    const admin = peran === PeranPengguna.ADMIN;
    const jadwal = await this.prisma.jadwalPraktik.findFirst({
      where: {
        id,
        ...(!admin
          ? {
              aktif: true,
              loket: { is: { aktif: true } },
              dokterLayanan: {
                is: {
                  aktif: true,
                  dokter: { is: { aktif: true } },
                  layanan: { is: { aktif: true } },
                },
              },
            }
          : {}),
      },
      include: detailJadwal,
    });
    if (!jadwal) throw new NotFoundException('Jadwal praktik tidak ditemukan');
    return jadwal;
  }

  async update(id: string, dto: UpdateJadwalPraktikDto) {
    if (Object.keys(dto).length === 0) {
      throw new BadRequestException('Perubahan jadwal tidak boleh kosong');
    }
    try {
      return await this.prisma.$transaction(async (tx) => {
        // Serialisasi perubahan pada jadwal yang sama sebelum membaca nilainya.
        await this.kunciSumberDaya(tx, [`jadwal:${id}`]);
        const existing = await tx.jadwalPraktik.findUnique({
          where: { id },
          include: { slotPraktik: { select: { id: true }, take: 1 } },
        });
        if (!existing) throw new NotFoundException('Jadwal praktik tidak ditemukan');

        const mengubahJadwal = [
          dto.dokterLayananId,
          dto.loketId,
          dto.tanggal,
          dto.mulaiPada,
          dto.selesaiPada,
        ].some((nilai) => nilai !== undefined);
        if (existing.slotPraktik.length > 0 && (mengubahJadwal || dto.aktif === false)) {
          throw new ConflictException('Jadwal yang memiliki slot tidak boleh diubah atau dinonaktifkan');
        }

        const gabungan: JadwalInput = {
          dokterLayananId: dto.dokterLayananId ?? existing.dokterLayananId,
          loketId: dto.loketId ?? existing.loketId,
          tanggal: dto.tanggal ?? existing.tanggal.toISOString().slice(0, 10),
          mulaiPada: dto.mulaiPada ?? existing.mulaiPada.toISOString(),
          selesaiPada: dto.selesaiPada ?? existing.selesaiPada.toISOString(),
        };

        // Menonaktifkan jadwal lama tidak perlu memvalidasi layanan yang mungkin sudah nonaktif.
        if (mengubahJadwal || dto.aktif === true) {
          const waktu = this.parseWaktu(gabungan);
          const pasangan = await this.pastikanRelasiAktif(tx, gabungan.dokterLayananId, gabungan.loketId);
          await this.kunciSumberDaya(tx, [
            `dokter:${pasangan.dokterId}`,
            `ruang:${gabungan.loketId}`,
          ]);
          await this.validasiOperasional(tx, pasangan.layananId, waktu);
          // Jadwal yang tetap nonaktif tidak menghalangi jadwal aktif lainnya.
          if (dto.aktif ?? existing.aktif) {
            await this.pastikanTidakBentrok(tx, pasangan.dokterId, gabungan.loketId, waktu, id);
          }
        }
        return tx.jadwalPraktik.update({
          where: { id },
          data: {
            dokterLayananId: dto.dokterLayananId,
            loketId: dto.loketId,
            tanggal: dto.tanggal === undefined ? undefined : this.parseTanggal(dto.tanggal),
            mulaiPada: dto.mulaiPada === undefined ? undefined : new Date(dto.mulaiPada),
            selesaiPada: dto.selesaiPada === undefined ? undefined : new Date(dto.selesaiPada),
            aktif: dto.aktif,
          },
          include: detailJadwal,
        });
      });
    } catch (error: unknown) {
      this.handleDatabaseError(error);
    }
  }

  async remove(id: string) {
    try {
      return await this.prisma.$transaction(async (tx) => {
        await this.kunciSumberDaya(tx, [`jadwal:${id}`]);
        const jadwal = await tx.jadwalPraktik.findUnique({
          where: { id },
          include: { slotPraktik: { select: { id: true }, take: 1 } },
        });
        if (!jadwal) throw new NotFoundException('Jadwal praktik tidak ditemukan');
        if (jadwal.slotPraktik.length > 0) {
          throw new ConflictException('Jadwal yang memiliki slot tidak boleh dinonaktifkan');
        }
        return tx.jadwalPraktik.update({
          where: { id },
          data: { aktif: false },
          include: detailJadwal,
        });
      });
    } catch (error: unknown) {
      this.handleDatabaseError(error);
    }
  }

  private parseTanggal(tanggal: string): Date {
    if (!POLA_TANGGAL.test(tanggal)) {
      throw new BadRequestException('tanggal harus YYYY-MM-DD');
    }
    const parsed = new Date(`${tanggal}T00:00:00.000Z`);
    if (!Number.isFinite(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== tanggal) {
      throw new BadRequestException('Tanggal kalender tidak valid');
    }
    return parsed;
  }

  private parseWaktu(input: JadwalInput) {
    const tanggal = this.parseTanggal(input.tanggal);
    const validOffset = /(?:Z|[+-](?:0\d|1[0-4]):[0-5]\d)$/;
    if (!validOffset.test(input.mulaiPada) || !validOffset.test(input.selesaiPada)) {
      throw new BadRequestException('Waktu harus berformat ISO 8601 dengan offset zona waktu');
    }
    const mulai = new Date(input.mulaiPada);
    const selesai = new Date(input.selesaiPada);
    if (!Number.isFinite(mulai.getTime()) || !Number.isFinite(selesai.getTime()) || selesai.getTime() <= mulai.getTime()) {
      throw new BadRequestException('Jam selesai harus lebih akhir daripada jam mulai');
    }
    if ([mulai, selesai].some((waktu) => waktu.getUTCSeconds() !== 0 || waktu.getUTCMilliseconds() !== 0)) {
      throw new BadRequestException('Waktu praktik harus tepat pada menit penuh');
    }
    const mulaiLokal = this.bagianLokal(mulai);
    const selesaiLokal = this.bagianLokal(selesai);
    if (mulaiLokal.tanggal !== input.tanggal || selesaiLokal.tanggal !== input.tanggal) {
      throw new BadRequestException('Waktu praktik harus berada pada tanggal lokal yang dipilih');
    }
    return { tanggal, mulai, selesai, mulaiLokal, selesaiLokal };
  }

  private bagianLokal(waktu: Date) {
    const zona = this.config.get<string>('SERVICE_TIME_ZONE') ?? 'Asia/Jakarta';
    const bagian = new Intl.DateTimeFormat('en-GB', {
      timeZone: zona,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      hourCycle: 'h23',
    }).formatToParts(waktu);
    const ambil = (jenis: string) => bagian.find((item) => item.type === jenis)?.value ?? '';
    const tanggal = `${ambil('year')}-${ambil('month')}-${ambil('day')}`;
    const menit = Number(ambil('hour')) * 60 + Number(ambil('minute'));
    return { tanggal, menit };
  }

  private async pastikanRelasiAktif(tx: Transaksi, dokterLayananId: string, loketId: string) {
    const pasangan = await tx.dokterLayanan.findUnique({
      where: { id: dokterLayananId },
      include: { dokter: { select: { aktif: true } }, layanan: { select: { aktif: true } } },
    });
    if (!pasangan) throw new NotFoundException('Relasi dokter dengan poliklinik tidak ditemukan');
    if (!pasangan.aktif || !pasangan.dokter.aktif || !pasangan.layanan.aktif) {
      throw new BadRequestException('Dokter, relasi, dan poliklinik harus aktif');
    }
    const loket = await tx.loket.findUnique({
      where: { id: loketId },
      select: { id: true, layananId: true, aktif: true },
    });
    if (!loket) throw new NotFoundException('Loket/ruang tidak ditemukan');
    if (!loket.aktif || loket.layananId !== pasangan.layananId) {
      throw new BadRequestException('Ruang harus aktif dan berasal dari poliklinik yang sama');
    }
    return { dokterId: pasangan.dokterId, layananId: pasangan.layananId };
  }

  private async validasiOperasional(tx: Transaksi, layananId: string, waktu: ReturnType<JadwalPraktikService['parseWaktu']>) {
    const hari = hariBerurutan[waktu.tanggal.getUTCDay()];
    const jadwal = await tx.jadwalLayanan.findUnique({
      where: { layananId_hari: { layananId, hari } },
      select: { aktif: true, jamBuka: true, jamTutup: true },
    });
    if (!jadwal || !jadwal.aktif) {
      throw new BadRequestException('Poliklinik tidak memiliki jadwal layanan aktif pada hari tersebut');
    }
    const waktuBuka = jadwal.jamBuka.toISOString().slice(11, 16);
    const waktuTutup = jadwal.jamTutup.toISOString().slice(11, 16);
    const keMenit = (nilai: string) => Number(nilai.slice(0, 2)) * 60 + Number(nilai.slice(3, 5));
    if (waktu.mulaiLokal.menit < keMenit(waktuBuka) || waktu.selesaiLokal.menit > keMenit(waktuTutup)) {
      throw new BadRequestException('Waktu praktik berada di luar jam operasional poliklinik');
    }
  }

  private async kunciSumberDaya(tx: Transaksi, kunci: string[]) {
    // Kunci per dokter/ruang untuk mencegah race condition antarpembuatan/perubahan jadwal.
    // Urutan tetap mengurangi risiko deadlock saat dua resource harus dikunci.
    for (const nilai of [...new Set(kunci)].sort()) {
      await tx.$queryRaw<{ ok: number }[]>`
        SELECT 1::int AS "ok"
        FROM pg_advisory_xact_lock(hashtextextended(${`queueb:jadwal:${nilai}`}, 0))
      `;
    }
  }

  private async pastikanTidakBentrok(
    tx: Transaksi,
    dokterId: string,
    loketId: string,
    waktu: ReturnType<JadwalPraktikService['parseWaktu']>,
    kecualiId?: string,
  ) {
    const bentrok = await tx.jadwalPraktik.findFirst({
      where: {
        aktif: true,
        ...(kecualiId ? { id: { not: kecualiId } } : {}),
        mulaiPada: { lt: waktu.selesai },
        selesaiPada: { gt: waktu.mulai },
        OR: [
          { loketId },
          { dokterLayanan: { is: { dokterId } } },
        ],
      },
      select: { id: true },
    });
    if (bentrok) {
      throw new ConflictException('Dokter atau ruang memiliki jadwal praktik yang bertabrakan');
    }
  }

  private handleDatabaseError(error: unknown): never {
    if (error instanceof Prisma.PrismaClientKnownRequestError) {
      if (error.code === 'P2002') {
        throw new ConflictException('Jadwal dengan waktu mulai tersebut sudah ada');
      }
      if (error.code === 'P2025') {
        throw new NotFoundException('Jadwal praktik tidak ditemukan');
      }
      if (error.code === 'P2003') {
        throw new BadRequestException('Relasi dokter atau ruang tidak valid');
      }
      if (error.code === 'P2034') {
        throw new ConflictException('Terjadi konflik transaksi, silakan coba kembali');
      }
    }
    throw error;
  }
}
