import { randomBytes } from 'node:crypto';
import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import {
  HariLayanan,
  ModeReservasi,
  Prisma,
  StatusTiket,
} from '../generated/prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CreateJanjiTemuDto } from './dto/create-janji-temu.dto';

type Transaksi = Prisma.TransactionClient;

// Data pasien lain serta tokenQrHash tidak pernah dikirim dalam respons.
const detailJanji = {
  tiket: {
    select: {
      id: true,
      penggunaId: true,
      layananId: true,
      tanggalAntrean: true,
      nomorUrut: true,
      kodeTiket: true,
      status: true,
      dibuatPada: true,
      layanan: { select: { id: true, kode: true, nama: true, prefixAntrean: true } },
    },
  },
  slotPraktik: {
    select: {
      id: true,
      mulaiPada: true,
      selesaiPada: true,
      jadwalPraktik: {
        select: {
          id: true,
          tanggal: true,
          loket: { select: { id: true, nama: true, lokasi: true } },
          dokterLayanan: {
            select: {
              dokter: { select: { id: true, nama: true, spesialisasi: true } },
              layanan: { select: { id: true, kode: true, nama: true } },
            },
          },
        },
      },
    },
  },
} as const;

@Injectable()
export class JanjiTemuService {
  constructor(private readonly prisma: PrismaService) {}

  async create(dto: CreateJanjiTemuDto, penggunaId: string) {
    // Baca referensi tidak tepercaya hanya untuk mengetahui lock jadwal.
    // Semua kondisi dibaca ulang di dalam transaksi setelah lock.
    const awal = await this.prisma.slotPraktik.findUnique({
      where: { id: dto.slotPraktikId },
      select: { jadwalPraktikId: true },
    });
    if (!awal) throw new NotFoundException('Slot konsultasi tidak ditemukan');

    const hasil = await this.denganPercobaan(async () =>
      this.prisma.$transaction(async (tx) => {
        // Urutan sama dengan mutasi SlotPraktikService H2.3: jadwal dahulu, slot kemudian.
        await this.kunciJadwal(tx, awal.jadwalPraktikId);
        await this.kunciSlot(tx, dto.slotPraktikId);
        const slot = await tx.slotPraktik.findUnique({
          where: { id: dto.slotPraktikId },
          include: {
            jadwalPraktik: {
              include: {
                dokterLayanan: { include: { dokter: true, layanan: true } },
                loket: true,
              },
            },
          },
        });
        if (!slot) throw new NotFoundException('Slot konsultasi tidak ditemukan');
        const jadwal = slot.jadwalPraktik;
        const pasangan = jadwal.dokterLayanan;
        const layanan = pasangan.layanan;
        if (
          !slot.aktif || !jadwal.aktif || !pasangan.aktif || !pasangan.dokter.aktif ||
          !layanan.aktif || !jadwal.loket.aktif || jadwal.loket.layananId !== layanan.id
        ) {
          throw new BadRequestException('Slot, dokter, poliklinik, atau ruang tidak aktif');
        }
        if (
          layanan.modeReservasi !== ModeReservasi.JANJI_TEMU_DOKTER &&
          layanan.modeReservasi !== ModeReservasi.HIBRIDA
        ) {
          throw new BadRequestException('Layanan belum menerima janji temu dokter');
        }
        if (slot.mulaiPada.getTime() <= Date.now()) {
          throw new BadRequestException('Slot konsultasi sudah dimulai atau berlalu');
        }
        if (
          slot.mulaiPada.getTime() < jadwal.mulaiPada.getTime() ||
          slot.selesaiPada.getTime() > jadwal.selesaiPada.getTime() ||
          slot.selesaiPada.getTime() <= slot.mulaiPada.getTime()
        ) {
          throw new BadRequestException('Waktu slot tidak sesuai jadwal praktik');
        }

        // Relasi historis yang sudah dibatalkan tidak lagi menempati kapasitas.
        const terisi = await tx.janjiTemu.count({
          where: {
            slotPraktikId: slot.id,
            tiket: { is: { status: { not: StatusTiket.DIBATALKAN } } },
          },
        });
        if (terisi >= slot.kapasitas) {
          throw new ConflictException('Kapasitas slot konsultasi sudah penuh');
        }

        const tanggal = jadwal.tanggal;
        // Counter ini berbagi mekanisme dan format nomor permanen dengan reservasi harian.
        // Upsert merupakan lock per layanan/tanggal agar pencegahan reservasi ganda
        // tetap aman meskipun pengguna memilih dua slot berbeda secara bersamaan.
        const counter = await tx.urutanAntreanHarian.upsert({
          where: { layananId_tanggal: { layananId: layanan.id, tanggal } },
          create: { layananId: layanan.id, tanggal, nomorTerakhir: 1 },
          update: { nomorTerakhir: { increment: 1 } },
        });

        // Pada mode HIBRIDA, booking dan walk-in berbagi batas kapasitas
        // harian poliklinik. Periksa sesudah counter terkunci agar transaksi
        // serializable menolak/meretry interleaving booking bersamaan.
        if (layanan.modeReservasi === ModeReservasi.HIBRIDA) {
          const hari = [
            HariLayanan.MINGGU, HariLayanan.SENIN,
            HariLayanan.SELASA, HariLayanan.RABU,
            HariLayanan.KAMIS, HariLayanan.JUMAT, HariLayanan.SABTU,
          ];
          const jadwalHarian = await tx.jadwalLayanan.findUnique({
            where: {
              layananId_hari: {
                layananId: layanan.id,
                hari: hari[tanggal.getUTCDay()],
              },
            },
            select: { aktif: true, kapasitasHarian: true },
          });
          if (!jadwalHarian?.aktif) {
            throw new BadRequestException('Jadwal layanan poliklinik tidak aktif');
          }
          const jumlahTiket = await tx.tiketAntrean.count({
            where: {
              layananId: layanan.id,
              tanggalAntrean: tanggal,
              status: { not: StatusTiket.DIBATALKAN },
            },
          });
          if (jumlahTiket >= jadwalHarian.kapasitasHarian) {
            throw new ConflictException('Kapasitas harian poliklinik sudah penuh');
          }
        }

        const sudahPunya = await tx.tiketAntrean.findFirst({
          where: {
            penggunaId,
            layananId: layanan.id,
            tanggalAntrean: tanggal,
            status: { not: StatusTiket.DIBATALKAN },
          },
          select: { id: true },
        });
        if (sudahPunya) {
          throw new ConflictException('Sudah ada reservasi aktif untuk poliklinik dan tanggal ini');
        }

        const tiket = await tx.tiketAntrean.create({
          data: {
            penggunaId,
            layananId: layanan.id,
            tanggalAntrean: tanggal,
            nomorUrut: counter.nomorTerakhir,
            kodeTiket: `TK${randomBytes(12).toString('hex').toUpperCase()}`,
            status: StatusTiket.DIPESAN,
          },
          select: { id: true },
        });
        const janji = await tx.janjiTemu.create({
          data: { tiketId: tiket.id, slotPraktikId: slot.id },
          select: { id: true },
        });
        await tx.peristiwaAntrean.create({
          data: {
            tiketAntreanId: tiket.id,
            aktorId: penggunaId,
            tipe: 'APPOINTMENT_BOOK',
            statusSebelum: null,
            statusSesudah: StatusTiket.DIPESAN,
            dataTambahan: { slotPraktikId: slot.id, metode: 'APPOINTMENT_BOOK' },
          },
        });
        return janji.id;
      }, {
        isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
        maxWait: 10000,
        timeout: 15000,
      }),
    );
    return this.findOne(hasil, penggunaId);
  }

  findAll(penggunaId: string) {
    return this.prisma.janjiTemu.findMany({
      where: { tiket: { is: { penggunaId } } },
      include: detailJanji,
      orderBy: [{ dibuatPada: 'desc' }, { id: 'asc' }],
    }).then((data) => data.map((item) => this.formatJanji(item)));
  }

  async findOne(id: string, penggunaId: string) {
    const janji = await this.prisma.janjiTemu.findFirst({
      where: { id, tiket: { is: { penggunaId } } },
      include: detailJanji,
    });
    if (!janji) throw new NotFoundException('Janji temu tidak ditemukan');
    return this.formatJanji(janji);
  }

  async batalkan(id: string, penggunaId: string) {
    const awal = await this.prisma.janjiTemu.findFirst({
      where: { id, tiket: { is: { penggunaId } } },
      select: { slotPraktik: { select: { jadwalPraktikId: true } }, slotPraktikId: true },
    });
    if (!awal) throw new NotFoundException('Janji temu tidak ditemukan');

    await this.denganPercobaan(() => this.prisma.$transaction(async (tx) => {
      await this.kunciJadwal(tx, awal.slotPraktik.jadwalPraktikId);
      await this.kunciSlot(tx, awal.slotPraktikId);
      const janji = await tx.janjiTemu.findFirst({
        where: { id, tiket: { is: { penggunaId } } },
        select: { tiketId: true, tiket: { select: { status: true } } },
      });
      if (!janji) throw new NotFoundException('Janji temu tidak ditemukan');
      if (janji.tiket.status !== StatusTiket.DIPESAN) {
        throw new ConflictException('Hanya janji temu berstatus DIPESAN yang dapat dibatalkan');
      }
      const hasil = await tx.tiketAntrean.updateMany({
        where: { id: janji.tiketId, penggunaId, status: StatusTiket.DIPESAN },
        data: { status: StatusTiket.DIBATALKAN, versi: { increment: 1 } },
      });
      if (hasil.count !== 1) {
        throw new ConflictException('Status tiket sudah berubah; pembatalan ditolak');
      }
      await tx.peristiwaAntrean.create({
        data: {
          tiketAntreanId: janji.tiketId,
          aktorId: penggunaId,
          tipe: 'APPOINTMENT_CANCEL',
          statusSebelum: StatusTiket.DIPESAN,
          statusSesudah: StatusTiket.DIBATALKAN,
          dataTambahan: { slotPraktikId: awal.slotPraktikId, metode: 'APPOINTMENT_CANCEL' },
        },
      });
    }, {
      isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
      maxWait: 10000,
      timeout: 15000,
    }));
    return this.findOne(id, penggunaId);
  }

  private formatJanji<T extends {
    tiket: { nomorUrut: number; tanggalAntrean: Date; layanan: { prefixAntrean: string } };
  }>(janji: T) {
    return {
      ...janji,
      nomorAntrean: `${janji.tiket.layanan.prefixAntrean.trim()}-${String(janji.tiket.nomorUrut).padStart(3, '0')}`,
      tanggalPelayanan: janji.tiket.tanggalAntrean.toISOString().slice(0, 10),
    };
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

  private async denganPercobaan<T>(operasi: () => Promise<T>): Promise<T> {
    const maksimal = 5;
    for (let percobaan = 0; percobaan < maksimal; percobaan++) {
      try {
        return await operasi();
      } catch (error: unknown) {
        if (error instanceof Prisma.PrismaClientKnownRequestError) {
          if ((error.code === 'P2034' || error.code === 'P2002') && percobaan < maksimal - 1) {
            continue;
          }
          if (error.code === 'P2034' || error.code === 'P2002') {
            throw new ConflictException('Pemesanan bersamaan, silakan coba lagi');
          }
          if (error.code === 'P2003' || error.code === 'P2025') {
            throw new BadRequestException('Relasi slot, tiket, atau pengguna tidak valid');
          }
        }
        throw error;
      }
    }
    throw new ConflictException('Pemesanan belum dapat diproses');
  }
}
