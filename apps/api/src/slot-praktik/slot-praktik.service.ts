import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PeranPengguna, Prisma } from '../generated/prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CariSlotPraktikDto } from './dto/cari-slot-praktik.dto';
import { CreateSlotPraktikDto, POLA_WAKTU_OFFSET } from './dto/create-slot-praktik.dto';
import { UpdateSlotPraktikDto } from './dto/update-slot-praktik.dto';

type Transaksi = Prisma.TransactionClient;

type Rentang = { mulai: Date; selesai: Date };

// Relasi ditampilkan untuk keperluan Flutter; identitas pasien tidak pernah diikutkan.
const rincianSlot = {
  jadwalPraktik: {
    select: {
      id: true,
      tanggal: true,
      mulaiPada: true,
      selesaiPada: true,
      aktif: true,
      dokterLayanan: {
        select: {
          aktif: true,
          dokter: { select: { id: true, nama: true, spesialisasi: true, aktif: true } },
          layanan: { select: { id: true, kode: true, nama: true, aktif: true } },
        },
      },
      loket: { select: { id: true, nama: true, aktif: true } },
    },
  },
  _count: { select: { janjiTemu: true } },
} as const;

// Untuk USER/PETUGAS hanya sesi aktif dengan seluruh rantai relasi aktif.
const jadwalTerlihat = {
  aktif: true,
  loket: { is: { aktif: true } },
  dokterLayanan: {
    is: {
      aktif: true,
      dokter: { is: { aktif: true } },
      layanan: { is: { aktif: true } },
    },
  },
} as const;

@Injectable()
export class SlotPraktikService {
  constructor(private readonly prisma: PrismaService) {}

  async create(dto: CreateSlotPraktikDto) {
    const rentang = this.parseRentang(dto.mulaiPada, dto.selesaiPada);
    this.pastikanKapasitas(dto.kapasitas);
    try {
      return await this.prisma.$transaction(async (tx) => {
        // Nama kunci HARUS sama dengan JadwalPraktikService H2.2 untuk
        // menserialkan CREATE slot vs PATCH/DELETE jadwal yang sama.
        await this.kunciJadwal(tx, dto.jadwalPraktikId);
        await this.pastikanJadwalAktif(tx, dto.jadwalPraktikId, rentang);
        await this.pastikanTidakTumpangTindih(tx, dto.jadwalPraktikId, rentang);
        const slot = await tx.slotPraktik.create({
          data: {
            jadwalPraktikId: dto.jadwalPraktikId,
            mulaiPada: rentang.mulai,
            selesaiPada: rentang.selesai,
            kapasitas: dto.kapasitas,
          },
          include: rincianSlot,
        });
        return this.denganKetersediaan(slot);
      });
    } catch (error: unknown) {
      this.handleDatabaseError(error);
    }
  }

  findAll(peran: PeranPengguna, query: CariSlotPraktikDto) {
    const where: Prisma.SlotPraktikWhereInput = {
      jadwalPraktikId: query.jadwalPraktikId,
      ...(peran === PeranPengguna.ADMIN ? {} : { aktif: true, jadwalPraktik: { is: jadwalTerlihat } }),
    };
    return this.prisma.slotPraktik.findMany({
      where,
      include: rincianSlot,
      orderBy: [{ mulaiPada: 'asc' }, { id: 'asc' }],
    }).then((slots) => slots.map((slot) => this.denganKetersediaan(slot)));
  }

  async findOne(id: string, peran: PeranPengguna) {
    const slot = await this.prisma.slotPraktik.findFirst({
      where: {
        id,
        ...(peran === PeranPengguna.ADMIN ? {} : { aktif: true, jadwalPraktik: { is: jadwalTerlihat } }),
      },
      include: rincianSlot,
    });
    if (!slot) throw new NotFoundException('Slot konsultasi tidak ditemukan');
    return this.denganKetersediaan(slot);
  }

  async update(id: string, dto: UpdateSlotPraktikDto) {
    if (Object.keys(dto).length === 0) {
      throw new BadRequestException('Perubahan slot tidak boleh kosong');
    }
    // Baca jadwalId untuk menentukan lock. Semua mutasi slot dikoordinasikan per-jadwal.
    const pre = await this.prisma.slotPraktik.findUnique({
      where: { id },
      select: { jadwalPraktikId: true },
    });
    if (!pre) throw new NotFoundException('Slot konsultasi tidak ditemukan');
    try {
      return await this.prisma.$transaction(async (tx) => {
        await this.kunciJadwal(tx, pre.jadwalPraktikId);
        // H2.4 HARUS mengambil kunci slot yang sama sebelum booking/ubah booking.
        await this.kunciSlot(tx, id);
        const existing = await tx.slotPraktik.findUnique({
          where: { id },
          include: { _count: { select: { janjiTemu: true } } },
        });
        if (!existing) throw new NotFoundException('Slot konsultasi tidak ditemukan');
        const jumlahJanji = existing._count.janjiTemu;
        const ubahWaktu = dto.mulaiPada !== undefined || dto.selesaiPada !== undefined;
        if (jumlahJanji > 0 && (ubahWaktu || dto.aktif === false)) {
          throw new ConflictException('Slot yang memiliki janji temu tidak boleh digeser atau dinonaktifkan');
        }
        const kapasitas = dto.kapasitas ?? existing.kapasitas;
        this.pastikanKapasitas(kapasitas);
        if (kapasitas < jumlahJanji) {
          throw new ConflictException('Kapasitas tidak boleh kurang dari jumlah janji temu');
        }
        const rentang = this.parseRentang(
          dto.mulaiPada ?? existing.mulaiPada.toISOString(),
          dto.selesaiPada ?? existing.selesaiPada.toISOString(),
        );
        if (ubahWaktu || dto.aktif === true) {
          await this.pastikanJadwalAktif(tx, existing.jadwalPraktikId, rentang);
          if (dto.aktif ?? existing.aktif) {
            await this.pastikanTidakTumpangTindih(tx, existing.jadwalPraktikId, rentang, id);
          }
        }
        const slot = await tx.slotPraktik.update({
          where: { id },
          data: {
            mulaiPada: dto.mulaiPada === undefined ? undefined : rentang.mulai,
            selesaiPada: dto.selesaiPada === undefined ? undefined : rentang.selesai,
            kapasitas: dto.kapasitas,
            aktif: dto.aktif,
          },
          include: rincianSlot,
        });
        return this.denganKetersediaan(slot);
      });
    } catch (error: unknown) {
      this.handleDatabaseError(error);
    }
  }

  async remove(id: string) {
    const pre = await this.prisma.slotPraktik.findUnique({
      where: { id }, select: { jadwalPraktikId: true },
    });
    if (!pre) throw new NotFoundException('Slot konsultasi tidak ditemukan');
    try {
      return await this.prisma.$transaction(async (tx) => {
        await this.kunciJadwal(tx, pre.jadwalPraktikId);
        await this.kunciSlot(tx, id);
        const existing = await tx.slotPraktik.findUnique({
          where: { id }, include: { _count: { select: { janjiTemu: true } } },
        });
        if (!existing) throw new NotFoundException('Slot konsultasi tidak ditemukan');
        if (existing._count.janjiTemu > 0) {
          throw new ConflictException('Slot yang memiliki janji temu tidak boleh dinonaktifkan');
        }
        const slot = await tx.slotPraktik.update({
          where: { id }, data: { aktif: false }, include: rincianSlot,
        });
        return this.denganKetersediaan(slot);
      });
    } catch (error: unknown) {
      this.handleDatabaseError(error);
    }
  }

  private parseRentang(mulaiPada: string, selesaiPada: string): Rentang {
    const pola = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?(?:Z|[+-](?:0\d|1[0-4]):[0-5]\d)$/;
    if (!pola.test(mulaiPada) || !pola.test(selesaiPada) ||
        !POLA_WAKTU_OFFSET.test(mulaiPada) || !POLA_WAKTU_OFFSET.test(selesaiPada)) {
      throw new BadRequestException('Waktu harus ISO 8601 lengkap dengan zona waktu');
    }
    const mulai = new Date(mulaiPada);
    const selesai = new Date(selesaiPada);
    if (!Number.isFinite(mulai.getTime()) || !Number.isFinite(selesai.getTime()) ||
        selesai.getTime() <= mulai.getTime()) {
      throw new BadRequestException('Waktu selesai harus setelah waktu mulai');
    }
    if ([mulai, selesai].some((waktu) => waktu.getUTCSeconds() !== 0 || waktu.getUTCMilliseconds() !== 0)) {
      throw new BadRequestException('Waktu harus tepat pada menit penuh');
    }
    return { mulai, selesai };
  }

  private pastikanKapasitas(kapasitas: number) {
    if (!Number.isInteger(kapasitas) || kapasitas < 1) {
      throw new BadRequestException('Kapasitas harus berupa bilangan bulat minimal satu');
    }
  }

  private async pastikanJadwalAktif(tx: Transaksi, jadwalId: string, rentang: Rentang) {
    const jadwal = await tx.jadwalPraktik.findUnique({
      where: { id: jadwalId },
      include: {
        dokterLayanan: { include: { dokter: { select: { aktif: true } }, layanan: { select: { aktif: true } } } },
        loket: { select: { aktif: true } },
      },
    });
    if (!jadwal) throw new NotFoundException('Jadwal praktik tidak ditemukan');
    if (!jadwal.aktif || !jadwal.dokterLayanan.aktif || !jadwal.dokterLayanan.dokter.aktif ||
        !jadwal.dokterLayanan.layanan.aktif || !jadwal.loket.aktif) {
      throw new BadRequestException('Jadwal, dokter, poliklinik, relasi, serta ruang harus aktif');
    }
    if (rentang.mulai.getTime() < jadwal.mulaiPada.getTime() ||
        rentang.selesai.getTime() > jadwal.selesaiPada.getTime()) {
      throw new BadRequestException('Slot harus berada dalam waktu jadwal praktik');
    }
  }

  private async pastikanTidakTumpangTindih(
    tx: Transaksi, jadwalId: string, rentang: Rentang, kecualiId?: string,
  ) {
    const conflict = await tx.slotPraktik.findFirst({
      where: {
        jadwalPraktikId: jadwalId,
        aktif: true,
        ...(kecualiId ? { id: { not: kecualiId } } : {}),
        mulaiPada: { lt: rentang.selesai },
        selesaiPada: { gt: rentang.mulai },
      },
      select: { id: true },
    });
    if (conflict) throw new ConflictException('Slot konsultasi pada jadwal ini bertumpang tindih');
  }

  private async kunciJadwal(tx: Transaksi, jadwalId: string) {
    await tx.$queryRaw<{ ok: number }[]>`
      SELECT 1::int AS "ok"
      FROM pg_advisory_xact_lock(hashtextextended(${`queueb:jadwal:jadwal:${jadwalId}`}, 0))
    `;
  }

  private async kunciSlot(tx: Transaksi, slotId: string) {
    await tx.$queryRaw<{ ok: number }[]>`
      SELECT 1::int AS "ok"
      FROM pg_advisory_xact_lock(hashtextextended(${`queueb:slot:${slotId}`}, 0))
    `;
  }

  private denganKetersediaan<T extends {
    kapasitas: number;
    aktif: boolean;
    mulaiPada: Date;
    jadwalPraktik: {
      aktif: boolean;
      dokterLayanan: { aktif: boolean; dokter: { aktif: boolean }; layanan: { aktif: boolean } };
      loket: { aktif: boolean };
    };
    _count: { janjiTemu: number };
  }>(slot: T) {
    const jumlahJanjiTemu = slot._count.janjiTemu;
    const sisaKapasitas = Math.max(0, slot.kapasitas - jumlahJanjiTemu);
    const tersedia = slot.aktif && slot.jadwalPraktik.aktif &&
      slot.jadwalPraktik.dokterLayanan.aktif && slot.jadwalPraktik.dokterLayanan.dokter.aktif &&
      slot.jadwalPraktik.dokterLayanan.layanan.aktif && slot.jadwalPraktik.loket.aktif &&
      slot.mulaiPada.getTime() > Date.now() && sisaKapasitas > 0;
    const { _count, ...data } = slot;
    return { ...data, jumlahJanjiTemu, sisaKapasitas, tersedia };
  }

  private handleDatabaseError(error: unknown): never {
    if (error instanceof Prisma.PrismaClientKnownRequestError) {
      if (error.code === 'P2002') {
        throw new ConflictException('Slot dengan waktu mulai tersebut sudah ada');
      }
      if (error.code === 'P2025') {
        throw new NotFoundException('Slot konsultasi tidak ditemukan');
      }
      if (error.code === 'P2003') {
        throw new BadRequestException('Relasi jadwal praktik tidak valid');
      }
      if (error.code === 'P2034') {
        throw new ConflictException('Konflik transaksi; coba kembali');
      }
    }
    throw error;
  }
}
