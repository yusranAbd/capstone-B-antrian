import { createHash } from 'node:crypto';

import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  GoneException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';

import { HariLayanan, Prisma, StatusTiket } from '../generated/prisma/client';

import { PrismaService } from '../prisma/prisma.service';
import { ProsesCheckInDto } from './dto/proses-check-in.dto';
import { VerifikasiBuktiReservasiDto } from './dto/verifikasi-bukti-reservasi.dto';
import {
  alasanPenerimaanHospital,
  PILIH_JANJI_TEMU_HOSPITAL,
} from '../hospital/hospital-context';

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

  /**
   * Pembacaan bukti reservasi QBR1 untuk loket petugas yang ditugaskan.
   * TIDAK menerbitkan SQ1, mengubah status tiket, ataupun melakukan check-in.
   */
  async verifikasiBuktiReservasi(dto: VerifikasiBuktiReservasiDto, petugasId: string) {
    const match = /^QBR1\.(TK[A-F0-9]{24})$/.exec(dto.qrPayload ?? '');
    if (!match ||
        !/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(dto.loketId ?? '')) {
      throw new BadRequestException('Format QR bukti reservasi atau loket tidak valid');
    }

    const waktu = this.dapatkanWaktuPelayanan(new Date());
    const tiket = await this.prisma.tiketAntrean.findUnique({
      where: { kodeTiket: match[1] },
      select: {
        id: true,
        layananId: true,
        tanggalAntrean: true,
        nomorUrut: true,
        status: true,
        layanan: {
          select: { id: true, nama: true, prefixAntrean: true, aktif: true },
        },
      },
    });
    if (!tiket) throw new NotFoundException('Bukti reservasi tidak ditemukan');

    // Petugas hanya dapat memverifikasi bukti untuk layanan di loket aktif
    // yang sedang ditugaskan kepadanya. Identitas pasien tidak dikembalikan.
    const penugasan = await this.prisma.penugasanPetugas.findFirst({
      where: {
        petugasId,
        loketId: dto.loketId,
        aktif: true,
        tanggalMulai: { lte: waktu.tanggalDb },
        OR: [
          { tanggalSelesai: null },
          { tanggalSelesai: { gte: waktu.tanggalDb } },
        ],
      },
      select: {
        loket: {
          select: {
            aktif: true,
            layananId: true,
            layanan: { select: { aktif: true } },
          },
        },
      },
    });
    if (!penugasan ||
        !penugasan.loket.aktif ||
        !penugasan.loket.layanan.aktif ||
        penugasan.loket.layananId !== tiket.layananId) {
      throw new ForbiddenException('Tidak berwenang memverifikasi tiket untuk layanan ini');
    }

    const tanggal = tiket.tanggalAntrean.toISOString().slice(0, 10);
    const dapatDiverifikasi = tiket.status === StatusTiket.DIPESAN &&
      tiket.layanan.aktif && tanggal >= waktu.tanggal;
    const hariPelayanan = tanggal === waktu.tanggal;
    return {
      jenis: 'BUKTI_RESERVASI',
      tiketId: tiket.id,
      nomorAntrean: `${tiket.layanan.prefixAntrean.trim()}-${String(tiket.nomorUrut).padStart(3, '0')}`,
      layanan: { id: tiket.layanan.id, nama: tiket.layanan.nama },
      tanggalPelayanan: tanggal,
      status: tiket.status,
      buktiBerlaku: dapatDiverifikasi,
      hariPelayanan,
      // Ini bukan keputusan final boleh-check-in. Jam operasional,
      // ruang janji temu, status, dan atomic check-in tetap diperiksa
      // oleh alur SQ1 yang sudah ada.
      checkInDilakukan: false,
      pesan: !dapatDiverifikasi
        ? 'Reservasi tidak aktif atau tanggal pelayanan sudah berlalu'
        : hariPelayanan
          ? 'Bukti sesuai tanggal pelayanan. Check-in tetap memerlukan QR aktif SQ1'
          : 'Bukti reservasi terverifikasi. Check-in baru dapat dilakukan pada hari pelayanan',
    };
  }

  // ==========================================
  // PROSES CHECK-IN BERBASIS QR
  // ==========================================

  async proses(dto: ProsesCheckInDto, petugasId: string) {
    const sekarang = new Date();

    try {
      return await this.prisma.$transaction(
        (tx) => this.prosesDalamTransaksi(tx, dto, petugasId, sekarang),
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

  /** Internal composition; legacy endpoint never enables receipt lookup. */
  async prosesDalamTransaksi(
    tx: Prisma.TransactionClient,
    dto: ProsesCheckInDto,
    petugasId: string,
    sekarang: Date,
    lanjutkan = false,
  ) {
    const waktuLokal = this.dapatkanWaktuPelayanan(sekarang);
    const hash = createHash('sha256')
      .update(dto.qrPayload, 'utf8')
      .digest('hex');
    const pilihanTiket = {
      id: true,
      layananId: true,
      tanggalAntrean: true,
      nomorUrut: true,
      status: true,
      versi: true,
      checkInPada: true,
      loketId: true,
      urutanMasukAntrean: true,
      qrKedaluwarsaPada: true,
      janjiTemu: PILIH_JANJI_TEMU_HOSPITAL,
      layanan: {
        select: {
          aktif: true,
          prefixAntrean: true,
          modeReservasi: true,
        },
      },
    } as const;

    // 1. Temukan tiket berdasarkan hash QR.
    let tiket = await tx.tiketAntrean.findUnique({
      where: {
        tokenQrHash: hash,
      },
      select: pilihanTiket,
    });

    let batasQr = tiket?.qrKedaluwarsaPada ?? null;
    if (!tiket && lanjutkan) {
      const bukti = await tx.peristiwaAntrean.findFirst({
        where: {
          tipe: 'CHECK_IN',
          dataTambahan: { path: ['buktiQrHash'], equals: hash },
        },
        select: { tiketAntreanId: true, dataTambahan: true },
      });
      if (bukti) {
        const meta = bukti.dataTambahan as Record<string, unknown> | null;
        const expiry =
          typeof meta?.qrBerlakuHingga === 'string'
            ? new Date(meta.qrBerlakuHingga)
            : null;
        batasQr = expiry && Number.isFinite(expiry.getTime()) ? expiry : null;
        tiket = await tx.tiketAntrean.findUnique({
          where: { id: bukti.tiketAntreanId },
          select: pilihanTiket,
        });
        if (
          tiket &&
          ![StatusTiket.CHECK_IN, StatusTiket.MENUNGGU].includes(
            tiket.status as 'CHECK_IN' | 'MENUNGGU',
          )
        ) {
          throw new ConflictException(
            'Tiket sudah diproses dan tidak dapat check-in ulang',
          );
        }
      }
    }
    if (!tiket) {
      throw new BadRequestException('QR tidak valid atau sudah digunakan');
    }

    // 2. Pastikan status tiket masih DIPESAN.
    if (
      tiket.status !== StatusTiket.DIPESAN &&
      !(
        lanjutkan &&
        (tiket.status === StatusTiket.CHECK_IN ||
          tiket.status === StatusTiket.MENUNGGU)
      )
    ) {
      throw new ConflictException('Tiket sudah diproses sebelumnya');
    }

    // 3. Pastikan token belum kedaluwarsa.
    if (!batasQr || batasQr <= sekarang) {
      throw new GoneException('QR sudah kedaluwarsa. Silakan terbitkan ulang');
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

    const alasan = alasanPenerimaanHospital(
      {
        ...tiket,
        modeReservasi: tiket.layanan.modeReservasi,
      },
      dto.loketId,
      sekarang,
    );
    if (alasan === 'RUANG_BERBEDA') {
      throw new ForbiddenException(
        'Appointment harus check-in pada ruang sesi dokter',
      );
    }
    if (alasan)
      throw new BadRequestException(`Konteks Hospital tidak valid: ${alasan}`);

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
      throw new BadRequestException('Check-in berada di luar jam pelayanan');
    }

    if (tiket.status !== StatusTiket.DIPESAN) {
      if (
        !tiket.checkInPada ||
        (tiket.status === StatusTiket.MENUNGGU &&
          tiket.urutanMasukAntrean === null)
      ) {
        throw new ConflictException(
          'Status tiket tidak konsisten. Hubungi pengelola.',
        );
      }
      if (tiket.janjiTemu && tiket.loketId !== dto.loketId) {
        throw new ForbiddenException(
          'Gunakan ruang check-in appointment yang sesuai',
        );
      }
      return {
        tiketId: tiket.id,
        layananId: tiket.layananId,
        nomorAntrean: `${tiket.layanan.prefixAntrean.trim()}-${String(tiket.nomorUrut).padStart(3, '0')}`,
        status: tiket.status,
        checkInPada: tiket.checkInPada.toISOString(),
        loketId: dto.loketId,
        petugasId,
      };
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
          buktiQrHash: hash,
          qrBerlakuHingga: batasQr.toISOString(),
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
