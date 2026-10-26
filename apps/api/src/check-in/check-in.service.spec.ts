import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  GoneException,
} from '@nestjs/common';

import { createHash } from 'node:crypto';

import { ModeReservasi, Prisma, StatusTiket } from '../generated/prisma/client';
import { buatKonteksJanjiUji } from '../../test/helpers/hospital-context.fixture';

import { PrismaService } from '../prisma/prisma.service';
import { CheckInService } from './check-in.service';

const SEKARANG = new Date('2026-10-10T02:30:00.000Z');

const tiketId = '1a33984d-d5f1-4fdb-b888-545a2c5be9c8';

const layananId = '1bfa9aa4-6c27-4e67-b938-b0fb53f485cf';

const petugasId = '3d70dbda-357e-49f1-8a6b-9f11e5353c81';

const loketId = '10cd449d-8347-40c4-b1d4-de399db1e33b';

const penugasanId = '00000000-0000-4000-8000-000000000099';

const qrPayload = `SQ1.${'A'.repeat(43)}`;

const tokenQrHash = createHash('sha256')
  .update(qrPayload, 'utf8')
  .digest('hex');

const dto = {
  qrPayload,
  loketId,
};

const tiketUji = {
  id: tiketId,
  layananId,
  tanggalAntrean: new Date('2026-10-10T00:00:00.000Z'),
  nomorUrut: 1,
  status: StatusTiket.DIPESAN,
  versi: 1,
  qrKedaluwarsaPada: new Date('2026-10-10T03:00:00.000Z'),
  layanan: {
    aktif: true,
    prefixAntrean: 'A',
  },
};

const penugasanUji = {
  id: penugasanId,
  loket: {
    aktif: true,
    layananId,
    layanan: {
      aktif: true,
    },
  },
};

const jadwalUji = {
  aktif: true,
  jamBuka: new Date('1970-01-01T08:00:00.000Z'),
  jamTutup: new Date('1970-01-01T14:00:00.000Z'),
};

const buatTxMock = () => ({
  tiketAntrean: {
    findUnique: jest.fn(),
    updateMany: jest.fn(),
  },
  penugasanPetugas: {
    findFirst: jest.fn(),
  },
  jadwalLayanan: {
    findUnique: jest.fn(),
  },
  peristiwaAntrean: {
    create: jest.fn(),
  },
});

const buatPrismaMock = () => ({
  $transaction: jest.fn(),
});

function errorPrisma(code: string): Prisma.PrismaClientKnownRequestError {
  return new Prisma.PrismaClientKnownRequestError('Simulasi konflik database', {
    code,
    clientVersion: '7.10.0',
  });
}

describe('CheckInService', () => {
  let service: CheckInService;
  let prismaMock: ReturnType<typeof buatPrismaMock>;
  let txMock: ReturnType<typeof buatTxMock>;
  let zonaWaktuSebelumnya: string | undefined;

  beforeAll(() => {
    zonaWaktuSebelumnya = process.env.SERVICE_TIME_ZONE;

    process.env.SERVICE_TIME_ZONE = 'Asia/Jakarta';
  });

  afterAll(() => {
    if (zonaWaktuSebelumnya === undefined) {
      delete process.env.SERVICE_TIME_ZONE;
    } else {
      process.env.SERVICE_TIME_ZONE = zonaWaktuSebelumnya;
    }
  });

  beforeEach(() => {
    jest.useFakeTimers();
    jest.setSystemTime(SEKARANG);

    txMock = buatTxMock();
    prismaMock = buatPrismaMock();

    txMock.tiketAntrean.findUnique.mockResolvedValue(tiketUji);

    txMock.penugasanPetugas.findFirst.mockResolvedValue(penugasanUji);

    txMock.jadwalLayanan.findUnique.mockResolvedValue(jadwalUji);

    txMock.tiketAntrean.updateMany.mockResolvedValue({
      count: 1,
    });

    txMock.peristiwaAntrean.create.mockResolvedValue({
      id: 'audit-1',
    });

    prismaMock.$transaction.mockImplementation(
      async (callback: (tx: typeof txMock) => Promise<unknown>) =>
        callback(txMock),
    );

    service = new CheckInService(prismaMock as unknown as PrismaService);
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  describe('Penerimaan appointment Hospital', () => {
    it('slot yang sudah berakhir tetap dapat CHECK_IN selama sesi relevan', async () => {
      txMock.tiketAntrean.findUnique.mockResolvedValue({ ...tiketUji,
        layanan: { ...tiketUji.layanan, modeReservasi: ModeReservasi.JANJI_TEMU_DOKTER },
        janjiTemu: buatKonteksJanjiUji(layananId, loketId, '2026-10-10') });
      await expect(service.proses(dto, petugasId)).resolves.toMatchObject({ status: StatusTiket.CHECK_IN });
    });
    it.each(['ruang', 'layanan', 'dokter', 'slot', 'tanggal', 'sesi', 'tanpa-janji'] as const)(
      'menolak CHECK_IN dengan konteks %s tidak valid tanpa mengonsumsi QR', async (kasus) => {
        const janji = buatKonteksJanjiUji(layananId, loketId, '2026-10-10');
        if (kasus === 'ruang') janji.slotPraktik.jadwalPraktik.loketId = 'ruang-lain';
        if (kasus === 'layanan') janji.slotPraktik.jadwalPraktik.dokterLayanan.layananId = 'poli-lain';
        if (kasus === 'dokter') janji.slotPraktik.jadwalPraktik.dokterLayanan.dokter.aktif = false;
        if (kasus === 'slot') janji.slotPraktik.aktif = false;
        if (kasus === 'tanggal') janji.slotPraktik.jadwalPraktik.tanggal = new Date('2026-10-11T00:00:00Z');
        if (kasus === 'sesi') janji.slotPraktik.jadwalPraktik.selesaiPada = new Date('2026-10-10T02:25:00Z');
        txMock.tiketAntrean.findUnique.mockResolvedValue({ ...tiketUji,
          layanan: { ...tiketUji.layanan, modeReservasi: ModeReservasi.JANJI_TEMU_DOKTER },
          janjiTemu: kasus === 'tanpa-janji' ? null : janji });
        await expect(service.proses(dto, petugasId)).rejects.toBeInstanceOf(
          kasus === 'ruang' ? ForbiddenException : BadRequestException,
        );
        expect(txMock.tiketAntrean.updateMany).not.toHaveBeenCalled();
        expect(txMock.peristiwaAntrean.create).not.toHaveBeenCalled();
      },
    );
  });

  describe('Check-In Berhasil', () => {
    it('mengubah tiket DIPESAN menjadi CHECK_IN', async () => {
      const hasil = await service.proses(dto, petugasId);

      expect(hasil).toMatchObject({
        tiketId,
        layananId,
        nomorAntrean: 'A-001',
        status: StatusTiket.CHECK_IN,
        loketId,
        petugasId,
      });

      expect(hasil.checkInPada).toBe(SEKARANG.toISOString());

      expect(prismaMock.$transaction).toHaveBeenCalledWith(
        expect.any(Function),
        {
          isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
          maxWait: 10000,
          timeout: 15000,
        },
      );
    });

    it('mencari tiket berdasarkan SHA-256 hash QR', async () => {
      await service.proses(dto, petugasId);

      expect(txMock.tiketAntrean.findUnique).toHaveBeenCalledWith(
        expect.objectContaining({
          where: {
            tokenQrHash,
          },
        }),
      );
    });

    it('memvalidasi penugasan petugas dan rentang tanggal', async () => {
      await service.proses(dto, petugasId);

      expect(txMock.penugasanPetugas.findFirst).toHaveBeenCalledWith(
        expect.objectContaining({
          where: {
            petugasId,
            loketId,
            aktif: true,
            tanggalMulai: {
              lte: new Date('2026-10-10T00:00:00.000Z'),
            },
            OR: [
              {
                tanggalSelesai: null,
              },
              {
                tanggalSelesai: {
                  gte: new Date('2026-10-10T00:00:00.000Z'),
                },
              },
            ],
          },
        }),
      );
    });

    it('mencatat audit setelah perubahan tiket berhasil', async () => {
      await service.proses(dto, petugasId);

      expect(txMock.tiketAntrean.updateMany).toHaveBeenCalledWith({
        where: {
          id: tiketId,
          status: StatusTiket.DIPESAN,
          versi: 1,
          tokenQrHash,
          qrKedaluwarsaPada: {
            gt: SEKARANG,
          },
          checkInPada: null,
        },
        data: {
          status: StatusTiket.CHECK_IN,
          checkInPada: SEKARANG,
          loketId,
          tokenQrHash: null,
          qrKedaluwarsaPada: null,
          versi: {
            increment: 1,
          },
        },
      });

      expect(txMock.peristiwaAntrean.create).toHaveBeenCalledWith({
        data: {
          tiketAntreanId: tiketId,
          aktorId: petugasId,
          tipe: 'CHECK_IN',
          statusSebelum: StatusTiket.DIPESAN,
          statusSesudah: StatusTiket.CHECK_IN,
          dataTambahan: {
            metode: 'QR_CHECK_IN',
            buktiQrHash: tokenQrHash,
            qrBerlakuHingga: tiketUji.qrKedaluwarsaPada.toISOString(),
            loketId,
            penugasanId,
          },
        },
      });

      expect(txMock.peristiwaAntrean.create).toHaveBeenCalledTimes(1);
    });
  });

  describe('Validasi Token dan Tiket', () => {
    it('menolak token QR yang tidak ditemukan', async () => {
      txMock.tiketAntrean.findUnique.mockResolvedValue(null);

      await expect(service.proses(dto, petugasId)).rejects.toThrow(
        BadRequestException,
      );

      expect(txMock.tiketAntrean.updateMany).not.toHaveBeenCalled();
    });

    it('menolak tiket yang sudah CHECK_IN', async () => {
      txMock.tiketAntrean.findUnique.mockResolvedValue({
        ...tiketUji,
        status: StatusTiket.CHECK_IN,
      });

      await expect(service.proses(dto, petugasId)).rejects.toThrow(
        ConflictException,
      );
    });

    it('menolak QR yang sudah kedaluwarsa', async () => {
      txMock.tiketAntrean.findUnique.mockResolvedValue({
        ...tiketUji,
        qrKedaluwarsaPada: new Date('2026-10-10T02:00:00.000Z'),
      });

      await expect(service.proses(dto, petugasId)).rejects.toThrow(
        GoneException,
      );
    });

    it('menolak QR tanpa waktu kedaluwarsa', async () => {
      txMock.tiketAntrean.findUnique.mockResolvedValue({
        ...tiketUji,
        qrKedaluwarsaPada: null,
      });

      await expect(service.proses(dto, petugasId)).rejects.toThrow(
        GoneException,
      );
    });

    it('menolak tanggal tiket yang tidak sama dengan hari pelayanan', async () => {
      txMock.tiketAntrean.findUnique.mockResolvedValue({
        ...tiketUji,
        tanggalAntrean: new Date('2026-10-12T00:00:00.000Z'),
      });

      await expect(service.proses(dto, petugasId)).rejects.toThrow(
        BadRequestException,
      );
    });

    it('menolak layanan yang tidak aktif', async () => {
      txMock.tiketAntrean.findUnique.mockResolvedValue({
        ...tiketUji,
        layanan: {
          aktif: false,
          prefixAntrean: 'A',
        },
      });

      await expect(service.proses(dto, petugasId)).rejects.toThrow(
        BadRequestException,
      );
    });
  });

  describe('Validasi Penugasan Petugas', () => {
    it('menolak petugas tanpa penugasan aktif', async () => {
      txMock.penugasanPetugas.findFirst.mockResolvedValue(null);

      await expect(service.proses(dto, petugasId)).rejects.toThrow(
        ForbiddenException,
      );

      expect(txMock.tiketAntrean.updateMany).not.toHaveBeenCalled();
    });

    it('menolak loket tidak aktif', async () => {
      txMock.penugasanPetugas.findFirst.mockResolvedValue({
        ...penugasanUji,
        loket: {
          ...penugasanUji.loket,
          aktif: false,
        },
      });

      await expect(service.proses(dto, petugasId)).rejects.toThrow(
        ForbiddenException,
      );
    });

    it('menolak loket dari layanan berbeda', async () => {
      txMock.penugasanPetugas.findFirst.mockResolvedValue({
        ...penugasanUji,
        loket: {
          ...penugasanUji.loket,
          layananId: '00000000-0000-4000-8000-000000000003',
        },
      });

      await expect(service.proses(dto, petugasId)).rejects.toThrow(
        ForbiddenException,
      );
    });

    it('menolak layanan pada loket yang tidak aktif', async () => {
      txMock.penugasanPetugas.findFirst.mockResolvedValue({
        ...penugasanUji,
        loket: {
          ...penugasanUji.loket,
          layanan: {
            aktif: false,
          },
        },
      });

      await expect(service.proses(dto, petugasId)).rejects.toThrow(
        ForbiddenException,
      );
    });
  });

  describe('Validasi Jadwal Pelayanan', () => {
    it('menolak hari tanpa jadwal pelayanan', async () => {
      txMock.jadwalLayanan.findUnique.mockResolvedValue(null);

      await expect(service.proses(dto, petugasId)).rejects.toThrow(
        BadRequestException,
      );
    });

    it('menolak jadwal pelayanan nonaktif', async () => {
      txMock.jadwalLayanan.findUnique.mockResolvedValue({
        ...jadwalUji,
        aktif: false,
      });

      await expect(service.proses(dto, petugasId)).rejects.toThrow(
        BadRequestException,
      );
    });

    it('menolak check-in di luar jam pelayanan', async () => {
      txMock.jadwalLayanan.findUnique.mockResolvedValue({
        aktif: true,
        jamBuka: new Date('1970-01-01T10:00:00.000Z'),
        jamTutup: new Date('1970-01-01T14:00:00.000Z'),
      });

      // Waktu lokal mock adalah 09:30 WIB.
      await expect(service.proses(dto, petugasId)).rejects.toThrow(
        BadRequestException,
      );
    });
  });

  describe('Transaksi dan Error Handling', () => {
    it('menolak perubahan ketika versi tiket sudah berubah', async () => {
      txMock.tiketAntrean.updateMany.mockResolvedValue({
        count: 0,
      });

      await expect(service.proses(dto, petugasId)).rejects.toThrow(
        ConflictException,
      );

      expect(txMock.peristiwaAntrean.create).not.toHaveBeenCalled();
    });

    it('mengubah konflik transaksi P2034 menjadi ConflictException', async () => {
      prismaMock.$transaction.mockRejectedValueOnce(errorPrisma('P2034'));

      await expect(service.proses(dto, petugasId)).rejects.toThrow(
        ConflictException,
      );
    });

    it('meneruskan error database yang tidak dikenali', async () => {
      prismaMock.$transaction.mockRejectedValueOnce(
        new Error('Gangguan database'),
      );

      await expect(service.proses(dto, petugasId)).rejects.toThrow(
        'Gangguan database',
      );
    });

    it('meneruskan kegagalan penyimpanan audit', async () => {
      txMock.peristiwaAntrean.create.mockRejectedValue(
        new Error('Audit gagal disimpan'),
      );

      await expect(service.proses(dto, petugasId)).rejects.toThrow(
        'Audit gagal disimpan',
      );
    });
  });
});
