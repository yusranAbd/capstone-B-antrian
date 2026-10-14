import { randomBytes } from 'node:crypto';

import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';

import { HariLayanan, ModeReservasi, Prisma, StatusTiket } from '../generated/prisma/client';

import { PrismaService } from '../prisma/prisma.service';
import { CreateReservasiDto } from './dto/create-reservasi.dto';

const daftarHari: HariLayanan[] = [
  HariLayanan.MINGGU,
  HariLayanan.SENIN,
  HariLayanan.SELASA,
  HariLayanan.RABU,
  HariLayanan.KAMIS,
  HariLayanan.JUMAT,
  HariLayanan.SABTU,
];

// Jangan mengembalikan tokenQrHash ke pengguna.
const pilihTiket = {
  id: true,
  penggunaId: true,
  layananId: true,
  tanggalAntrean: true,
  nomorUrut: true,
  kodeTiket: true,
  status: true,
  dibuatPada: true,
  layanan: {
    select: {
      id: true,
      kode: true,
      nama: true,
      prefixAntrean: true,
    },
  },
} as const;

@Injectable()
export class ReservasiService {
  constructor(private readonly prisma: PrismaService) {}

  // ==========================================
  // CREATE RESERVASI
  // ==========================================

  async create(dto: CreateReservasiDto, penggunaId: string) {
    const tanggal = this.parseTanggal(dto.tanggalAntrean);

    const hari = daftarHari[tanggal.getUTCDay()];

    const maksimalPercobaan = 5;

    for (let percobaan = 0; percobaan < maksimalPercobaan; percobaan++) {
      try {
        return await this.prisma.$transaction(
          async (tx) => {
            // 1. Validasi layanan.
            const layanan = await tx.layanan.findUnique({
              where: {
                id: dto.layananId,
              },
              select: {
                id: true,
                aktif: true,
                modeReservasi: true,
              },
            });

            if (!layanan) {
              throw new NotFoundException('Layanan tidak ditemukan');
            }

            if (!layanan.aktif) {
              throw new BadRequestException('Layanan sedang tidak aktif');
            }

            // Jalur reservasi harian tidak boleh menerbitkan tiket langsung
            // untuk layanan yang mensyaratkan pemilihan slot dokter.
            if (layanan.modeReservasi === ModeReservasi.JANJI_TEMU_DOKTER) {
              throw new BadRequestException('Gunakan API janji temu untuk layanan dokter');
            }

            // 2. Periksa jadwal pada hari tersebut.
            const jadwal = await tx.jadwalLayanan.findUnique({
              where: {
                layananId_hari: {
                  layananId: dto.layananId,
                  hari,
                },
              },
              select: {
                aktif: true,
                kapasitasHarian: true,
              },
            });

            if (!jadwal || !jadwal.aktif) {
              throw new BadRequestException(
                'Tidak ada jadwal pelayanan aktif pada hari tersebut',
              );
            }

            // 3. Alokasikan nomor secara atomik.
            // Increment mengunci baris counter
            // sampai transaksi selesai.
            const counter = await tx.urutanAntreanHarian.upsert({
              where: {
                layananId_tanggal: {
                  layananId: dto.layananId,
                  tanggal,
                },
              },
              create: {
                layananId: dto.layananId,
                tanggal,
                nomorTerakhir: 1,
              },
              update: {
                nomorTerakhir: {
                  increment: 1,
                },
              },
            });

            // 4. Cegah reservasi ganda.
            const reservasiLama = await tx.tiketAntrean.findFirst({
              where: {
                penggunaId,
                layananId: dto.layananId,
                tanggalAntrean: tanggal,
                status: {
                  not: StatusTiket.DIBATALKAN,
                },
              },
              select: {
                id: true,
              },
            });

            if (reservasiLama) {
              throw new ConflictException(
                'Pengguna sudah memiliki reservasi untuk layanan dan tanggal tersebut',
              );
            }

            // 5. Validasi kapasitas harian.
            const jumlahReservasi = await tx.tiketAntrean.count({
              where: {
                layananId: dto.layananId,
                tanggalAntrean: tanggal,
                status: {
                  not: StatusTiket.DIBATALKAN,
                },
              },
            });

            if (jumlahReservasi >= jadwal.kapasitasHarian) {
              throw new ConflictException(
                'Kapasitas reservasi harian sudah penuh',
              );
            }

            // 6. Buat tiket reservasi.
            // Kode sepanjang 26 karakter,
            // sesuai batas VarChar(30).
            const kodeTiket = `TK${randomBytes(12)
              .toString('hex')
              .toUpperCase()}`;

            return tx.tiketAntrean.create({
              data: {
                pengguna: {
                  connect: {
                    id: penggunaId,
                  },
                },
                layanan: {
                  connect: {
                    id: dto.layananId,
                  },
                },
                tanggalAntrean: tanggal,
                nomorUrut: counter.nomorTerakhir,
                kodeTiket,
                status: StatusTiket.DIPESAN,
              },
              select: pilihTiket,
            });
          },
          {
            isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
            maxWait: 10000,
            timeout: 15000,
          },
        );
      } catch (error: unknown) {
        const kode =
          error instanceof Prisma.PrismaClientKnownRequestError
            ? error.code
            : null;

        // Konkurensi / unique collision:
        // ulang seluruh transaksi.
        if (
          (kode === 'P2034' || kode === 'P2002') &&
          percobaan < maksimalPercobaan - 1
        ) {
          continue;
        }

        if (kode === 'P2034' || kode === 'P2002') {
          throw new ConflictException(
            'Reservasi sedang diproses bersamaan. Silakan mencoba lagi',
          );
        }

        if (kode === 'P2003' || kode === 'P2025') {
          throw new BadRequestException(
            'Relasi pengguna atau layanan tidak valid',
          );
        }

        throw error;
      }
    }

    throw new ConflictException('Reservasi belum dapat diproses');
  }

  // ==========================================
  // READ RESERVASI MILIK PENGGUNA
  // ==========================================

  findAll(penggunaId: string) {
    return this.prisma.tiketAntrean.findMany({
      where: {
        penggunaId,
      },
      select: pilihTiket,
      orderBy: [{ tanggalAntrean: 'desc' }, { nomorUrut: 'asc' }],
    });
  }

  async findOne(id: string, penggunaId: string) {
    const tiket = await this.prisma.tiketAntrean.findFirst({
      where: {
        id,
        penggunaId,
      },
      select: pilihTiket,
    });

    if (!tiket) {
      throw new NotFoundException('Reservasi tidak ditemukan');
    }

    return tiket;
  }

  // ==========================================
  // VALIDASI TANGGAL
  // ==========================================

  private parseTanggal(value: string): Date {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
      throw new BadRequestException(
        'Tanggal harus menggunakan format YYYY-MM-DD',
      );
    }

    const tanggal = new Date(`${value}T00:00:00.000Z`);

    if (
      Number.isNaN(tanggal.getTime()) ||
      tanggal.toISOString().slice(0, 10) !== value
    ) {
      throw new BadRequestException('Tanggal reservasi tidak valid');
    }

    if (value < this.tanggalHariIniLokal()) {
      throw new BadRequestException(
        'Tidak dapat membuat reservasi pada tanggal yang sudah lewat',
      );
    }

    return tanggal;
  }

  private tanggalHariIniLokal(): string {
    const zonaWaktu = process.env.SERVICE_TIME_ZONE ?? 'Asia/Jakarta';

    const formatter = new Intl.DateTimeFormat('en-US', {
      timeZone: zonaWaktu,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    });

    const bagian = formatter.formatToParts(new Date());

    const ambil = (tipe: string): string =>
      bagian.find((item) => item.type === tipe)?.value ?? '';

    return [ambil('year'), ambil('month'), ambil('day')].join('-');
  }
}
