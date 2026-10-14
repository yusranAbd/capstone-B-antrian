import { createHash } from 'node:crypto';

import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  GoneException,
  Injectable,
} from '@nestjs/common';

import { HariLayanan, Prisma, StatusTiket } from '../generated/prisma/client';

import { PrismaService } from '../prisma/prisma.service';
import { ProsesCheckInDto } from './dto/proses-check-in.dto';
import { alasanPenerimaanHospital, PILIH_JANJI_TEMU_HOSPITAL } from '../hospital/hospital-context';

const DAFTAR_HARI: HariLayanan[] = [
  HariLayanan.MINGGU,
  HariLayanan.SENIN,
  HariLayanan.SELASA,
  HariLayanan.RABU,
  HariLayanan.KAMIS,
  HariLayanan.JUMAT,
  HariLayanan.SABTU,
];

@Injectable()
export class CheckInService {
  constructor(private readonly prisma: PrismaService) {}

  // ==========================================
  // PROSES CHECK-IN BERBASIS QR
  // ==========================================

  async proses(dto: ProsesCheckInDto, petugasId: string) {
    const sekarang = new Date();

    const waktuLokal = this.dapatkanWaktuPelayanan(sekarang);

    const hash = createHash('sha256')
      .update(dto.qrPayload, 'utf8')
      .digest('hex');

    try {
      return await this.prisma.$transaction(
        async (tx) => {
          // 1. Temukan tiket berdasarkan hash QR.
          const tiket = await tx.tiketAntrean.findUnique({
            where: {
              tokenQrHash: hash,
            },
            select: {
              id: true,
              layananId: true,
              tanggalAntrean: true,
              nomorUrut: true,
              status: true,
              versi: true,
              qrKedaluwarsaPada: true,
              janjiTemu: PILIH_JANJI_TEMU_HOSPITAL,
              layanan: {
                select: {
                  aktif: true,
                  prefixAntrean: true,
                  modeReservasi: true,
                },
              },
            },
          });

          if (!tiket) {
            throw new BadRequestException(
              'QR tidak valid atau sudah digunakan',
            );
          }

          // 2. Pastikan status tiket masih DIPESAN.
          if (tiket.status !== StatusTiket.DIPESAN) {
            throw new ConflictException('Tiket sudah diproses sebelumnya');
          }

          // 3. Pastikan token belum kedaluwarsa.
          if (!tiket.qrKedaluwarsaPada || tiket.qrKedaluwarsaPada <= sekarang) {
            throw new GoneException(
              'QR sudah kedaluwarsa. Silakan terbitkan ulang',
            );
          }

          // 4. Check-in hanya pada tanggal
          // pelayanan yang sama.
          const tanggalTiket = tiket.tanggalAntrean.toISOString().slice(0, 10);

          if (tanggalTiket !== waktuLokal.tanggal) {
            throw new BadRequestException(
              'Check-in hanya dapat dilakukan pada tanggal pelayanan',
            );
          }

          if (!tiket.layanan.aktif) {
            throw new BadRequestException('Layanan sedang tidak aktif');
          }

          // 5. Validasi penugasan petugas.
          // Loket harus sesuai dengan layanan
          // pada tiket dan penugasan aktif.
          const penugasan = await tx.penugasanPetugas.findFirst({
            where: {
              petugasId,
              loketId: dto.loketId,
              aktif: true,
              tanggalMulai: {
                lte: waktuLokal.tanggalDb,
              },
              OR: [
                {
                  tanggalSelesai: null,
                },
                {
                  tanggalSelesai: {
                    gte: waktuLokal.tanggalDb,
                  },
                },
              ],
            },
            select: {
              id: true,
              loket: {
                select: {
                  aktif: true,
                  layananId: true,
                  layanan: {
                    select: {
                      aktif: true,
                    },
                  },
                },
              },
            },
          });

          if (
            !penugasan ||
            !penugasan.loket.aktif ||
            !penugasan.loket.layanan.aktif ||
            penugasan.loket.layananId !== tiket.layananId
          ) {
            throw new ForbiddenException(
              'Petugas tidak memiliki penugasan aktif pada loket layanan ini',
            );
          }

          const alasan = alasanPenerimaanHospital({
            ...tiket, modeReservasi: tiket.layanan.modeReservasi,
          }, dto.loketId, sekarang);
          if (alasan === 'RUANG_BERBEDA') {
            throw new ForbiddenException('Appointment harus check-in pada ruang sesi dokter');
          }
          if (alasan) throw new BadRequestException(`Konteks Hospital tidak valid: ${alasan}`);

          // 6. Validasi jadwal operasional.
          const jadwal = await tx.jadwalLayanan.findUnique({
            where: {
              layananId_hari: {
                layananId: tiket.layananId,
                hari: waktuLokal.hari,
              },
            },
            select: {
              aktif: true,
              jamBuka: true,
              jamTutup: true,
            },
          });

          if (!jadwal || !jadwal.aktif) {
            throw new BadRequestException(
              'Tidak ada jadwal pelayanan aktif hari ini',
            );
          }

          // PostgreSQL TIME direpresentasikan
          // Prisma sebagai Date.
          const jamBuka = jadwal.jamBuka.toISOString().slice(11, 19);

          const jamTutup = jadwal.jamTutup.toISOString().slice(11, 19);

          if (waktuLokal.jam < jamBuka || waktuLokal.jam >= jamTutup) {
            throw new BadRequestException(
              'Check-in berada di luar jam pelayanan',
            );
          }

          // 7. Update bersyarat/atomik.
          // Hanya satu request dapat mengubah
          // tiket DIPESAN dengan token dan
          // versi yang cocok.
          const hasil = await tx.tiketAntrean.updateMany({
            where: {
              id: tiket.id,
              status: StatusTiket.DIPESAN,
              versi: tiket.versi,
              tokenQrHash: hash,
              qrKedaluwarsaPada: {
                gt: sekarang,
              },
              checkInPada: null,
            },
            data: {
              status: StatusTiket.CHECK_IN,
              checkInPada: sekarang,
              loketId: dto.loketId,

              // Token langsung dikonsumsi.
              tokenQrHash: null,
              qrKedaluwarsaPada: null,

              versi: {
                increment: 1,
              },
            },
          });

          if (hasil.count !== 1) {
            throw new ConflictException(
              'QR sudah digunakan atau tiket sedang diproses',
            );
          }

          // 8. Audit trail dalam transaksi
          // yang sama dengan perubahan status.
          await tx.peristiwaAntrean.create({
            data: {
              tiketAntreanId: tiket.id,
              aktorId: petugasId,
              tipe: 'CHECK_IN',
              statusSebelum: StatusTiket.DIPESAN,
              statusSesudah: StatusTiket.CHECK_IN,
              dataTambahan: {
                metode: 'QR_CHECK_IN',
                loketId: dto.loketId,
                penugasanId: penugasan.id,
              },
            },
          });

          // 9. Respons tanpa token/hash QR.
          return {
            tiketId: tiket.id,
            layananId: tiket.layananId,
            nomorAntrean:
              `${tiket.layanan.prefixAntrean.trim()}-` +
              String(tiket.nomorUrut).padStart(3, '0'),
            status: StatusTiket.CHECK_IN,
            checkInPada: sekarang.toISOString(),
            loketId: dto.loketId,
            petugasId,
          };
        },
        {
          isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
          maxWait: 10000,
          timeout: 15000,
        },
      );
    } catch (error: unknown) {
      // Konflik serialisasi dari transaksi
      // bersamaan dikembalikan sebagai 409.
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2034'
      ) {
        throw new ConflictException(
          'Tiket sedang diproses. Periksa status sebelum mencoba kembali',
        );
      }

      throw error;
    }
  }

  // ==========================================
  // WAKTU DAN TANGGAL PELAYANAN
  // ==========================================

  private dapatkanWaktuPelayanan(sekarang: Date): {
    tanggal: string;
    tanggalDb: Date;
    hari: HariLayanan;
    jam: string;
  } {
    const zonaWaktu = process.env.SERVICE_TIME_ZONE ?? 'Asia/Jakarta';

    const formatter = new Intl.DateTimeFormat('en-GB', {
      timeZone: zonaWaktu,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hourCycle: 'h23',
    });

    const bagian = formatter.formatToParts(sekarang);

    const ambil = (tipe: string): string =>
      bagian.find((item) => item.type === tipe)?.value ?? '';

    const tanggal = [ambil('year'), ambil('month'), ambil('day')].join('-');

    const jam = [ambil('hour'), ambil('minute'), ambil('second')].join(':');

    // Representasi PostgreSQL DATE
    // tanpa pergeseran hari oleh timezone.
    const tanggalDb = new Date(`${tanggal}T00:00:00.000Z`);

    const hari = DAFTAR_HARI[tanggalDb.getUTCDay()];

    return {
      tanggal,
      tanggalDb,
      hari,
      jam,
    };
  }
}
