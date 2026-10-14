import {
  ConflictException,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';

import { ModeReservasi, PeranPengguna, Prisma, StatusTiket } from '../generated/prisma/client';

import { PrismaService } from '../prisma/prisma.service';
import { QueueService } from './queue.service';

// ==========================================
// DATA PENGUJIAN
// ==========================================

const SEKARANG = new Date('2026-10-10T02:30:00.000Z');

const TANGGAL_PELAYANAN = new Date('2026-10-10T00:00:00.000Z');

const tiketId = '1a33984d-d5f1-4fdb-b888-545a2c5be9c8';

const layananId = '1bfa9aa4-6c27-4e67-b938-b0fb53f485cf';

const petugasId = '3d70dbda-357e-49f1-8a6b-9f11e5353c81';

const loketId = '10cd449d-8347-40c4-b1d4-de399db1e33b';

const penugasanId = '00000000-0000-4000-8000-000000000099';

const tiketUji = {
  id: tiketId,
  layananId,
  tanggalAntrean: TANGGAL_PELAYANAN,
  nomorUrut: 1,
  status: StatusTiket.CHECK_IN,
  versi: 2,
  checkInPada: SEKARANG,
  urutanMasukAntrean: null,
  layanan: {
    aktif: true,
    prefixAntrean: 'A',
  },
};

const petugasUji = {
  id: petugasId,
  peran: PeranPengguna.PETUGAS,
  aktif: true,
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

const counterUji = {
  id: '00000000-0000-4000-8000-000000000088',
};

// ==========================================
// MOCK PRISMA TRANSACTION
// ==========================================

const buatTxMock = () => ({
  pengguna: {
    findUnique: jest.fn(),
  },
  tiketAntrean: {
    findUnique: jest.fn(),
    findFirst: jest.fn(),
    findMany: jest.fn(),
    updateMany: jest.fn(),
  },
  penugasanPetugas: {
    findFirst: jest.fn(),
  },
  jadwalLayanan: {
    findUnique: jest.fn(),
  },
  urutanAntreanHarian: {
    findUnique: jest.fn(),
    update: jest.fn(),
  },
  peristiwaAntrean: {
    create: jest.fn(),
  },
});

const buatPrismaMock = () => ({
  $transaction: jest.fn(),
  pengguna: {
    findUnique: jest.fn(),
  },
  penugasanPetugas: {
    findFirst: jest.fn(),
  },
  tiketAntrean: {
    findMany: jest.fn(),
  },
});

function buatKonflikTransaksi() {
  return new Prisma.PrismaClientKnownRequestError(
    'Simulasi konflik serialisasi',
    {
      code: 'P2034',
      clientVersion: '7.10.0',
    },
  );
}

describe('QueueService', () => {
  let service: QueueService;
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

    // Mock operasi transaksi.
    txMock.pengguna.findUnique.mockResolvedValue(petugasUji);

    txMock.tiketAntrean.findUnique.mockResolvedValue(tiketUji);

    txMock.penugasanPetugas.findFirst.mockResolvedValue(penugasanUji);

    txMock.jadwalLayanan.findUnique.mockResolvedValue({
      aktif: true,
    });

    txMock.urutanAntreanHarian.findUnique.mockResolvedValue(counterUji);

    txMock.urutanAntreanHarian.update.mockResolvedValue({
      urutanMasukTerakhir: 1,
    });

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

    // Mock pembacaan FIFO di luar transaksi.
    prismaMock.pengguna.findUnique.mockResolvedValue(petugasUji);

    prismaMock.penugasanPetugas.findFirst.mockResolvedValue(penugasanUji);

    prismaMock.tiketAntrean.findMany.mockResolvedValue([]);

    service = new QueueService(prismaMock as unknown as PrismaService);
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  // ========================================
  // A. MASUK ANTREAN
  // ========================================

  describe('Masuk Antrean', () => {
    it('mengubah CHECK_IN menjadi MENUNGGU', async () => {
      const hasil = await service.masukAntrean(tiketId, petugasId, loketId);

      expect(hasil).toEqual({
        tiketId,
        layananId,
        nomorAntrean: 'A-001',
        status: StatusTiket.MENUNGGU,
        urutanMasukAntrean: 1,
        masukAntreanPada: SEKARANG.toISOString(),
      });
    });

    it('menambah counter FIFO berdasarkan layanan dan tanggal', async () => {
      await service.masukAntrean(tiketId, petugasId, loketId);

      expect(txMock.urutanAntreanHarian.findUnique).toHaveBeenCalledWith({
        where: {
          layananId_tanggal: {
            layananId,
            tanggal: TANGGAL_PELAYANAN,
          },
        },
        select: {
          id: true,
        },
      });

      expect(txMock.urutanAntreanHarian.update).toHaveBeenCalledWith({
        where: {
          layananId_tanggal: {
            layananId,
            tanggal: TANGGAL_PELAYANAN,
          },
        },
        data: {
          urutanMasukTerakhir: {
            increment: 1,
          },
        },
        select: {
          urutanMasukTerakhir: true,
        },
      });
    });

    it('menggunakan status dan versi untuk perubahan atomik', async () => {
      await service.masukAntrean(tiketId, petugasId, loketId);

      expect(txMock.tiketAntrean.updateMany).toHaveBeenCalledWith({
        where: {
          id: tiketId,
          versi: 2,
          status: StatusTiket.CHECK_IN,
          checkInPada: {
            not: null,
          },
          urutanMasukAntrean: null,
        },
        data: {
          status: StatusTiket.MENUNGGU,
          urutanMasukAntrean: 1,
          masukAntreanPada: SEKARANG,
          versi: {
            increment: 1,
          },
        },
      });
    });

    it('mempertahankan nomor tiket asli', async () => {
      const hasil = await service.masukAntrean(tiketId, petugasId, loketId);

      expect(hasil.nomorAntrean).toBe('A-001');

      const argumen = txMock.tiketAntrean.updateMany.mock.calls[0][0] as {
        data: Record<string, unknown>;
      };

      expect(argumen.data).not.toHaveProperty('nomorUrut');

      expect(argumen.data).not.toHaveProperty('kodeTiket');
    });

    it('mencatat audit ENQUEUE dalam transaksi', async () => {
      await service.masukAntrean(tiketId, petugasId, loketId);

      expect(txMock.peristiwaAntrean.create).toHaveBeenCalledWith({
        data: {
          tiketAntreanId: tiketId,
          aktorId: petugasId,
          tipe: 'ENQUEUE',
          statusSebelum: StatusTiket.CHECK_IN,
          statusSesudah: StatusTiket.MENUNGGU,
          dataTambahan: {
            metode: 'QUEUE_ENQUEUE',
            loketId,
            penugasanId,
            urutanMasukAntrean: 1,
          },
        },
      });
    });

    it('menggunakan transaksi Serializable', async () => {
      await service.masukAntrean(tiketId, petugasId, loketId);

      expect(prismaMock.$transaction).toHaveBeenCalledWith(
        expect.any(Function),
        {
          isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
          maxWait: 10000,
          timeout: 15000,
        },
      );
    });

    it('menghasilkan urutan FIFO yang meningkat', async () => {
      txMock.urutanAntreanHarian.update
        .mockResolvedValueOnce({
          urutanMasukTerakhir: 1,
        })
        .mockResolvedValueOnce({
          urutanMasukTerakhir: 2,
        });

      const tiketKedua = {
        ...tiketUji,
        id: '00000000-0000-4000-8000-000000000002',
        nomorUrut: 2,
      };

      txMock.tiketAntrean.findUnique
        .mockResolvedValueOnce(tiketUji)
        .mockResolvedValueOnce(tiketKedua);

      const pertama = await service.masukAntrean(tiketId, petugasId, loketId);

      const kedua = await service.masukAntrean(
        tiketKedua.id,
        petugasId,
        loketId,
      );

      expect(pertama.urutanMasukAntrean).toBe(1);
      expect(kedua.urutanMasukAntrean).toBe(2);

      expect(pertama.nomorAntrean).toBe('A-001');
      expect(kedua.nomorAntrean).toBe('A-002');
    });
  });

  // ========================================
  // B. VALIDASI PETUGAS
  // ========================================

  describe('Validasi PETUGAS', () => {
    it('menolak pengguna yang tidak ditemukan', async () => {
      txMock.pengguna.findUnique.mockResolvedValue(null);

      await expect(
        service.masukAntrean(tiketId, petugasId, loketId),
      ).rejects.toThrow(ForbiddenException);
    });

    it('menolak role USER', async () => {
      txMock.pengguna.findUnique.mockResolvedValue({
        ...petugasUji,
        peran: PeranPengguna.USER,
      });

      await expect(
        service.masukAntrean(tiketId, petugasId, loketId),
      ).rejects.toThrow(ForbiddenException);
    });

    it('menolak PETUGAS nonaktif', async () => {
      txMock.pengguna.findUnique.mockResolvedValue({
        ...petugasUji,
        aktif: false,
      });

      await expect(
        service.masukAntrean(tiketId, petugasId, loketId),
      ).rejects.toThrow(ForbiddenException);
    });

    it('menolak petugas tanpa penugasan', async () => {
      txMock.penugasanPetugas.findFirst.mockResolvedValue(null);

      await expect(
        service.masukAntrean(tiketId, petugasId, loketId),
      ).rejects.toThrow(ForbiddenException);
    });

    it('menolak loket nonaktif', async () => {
      txMock.penugasanPetugas.findFirst.mockResolvedValue({
        ...penugasanUji,
        loket: {
          ...penugasanUji.loket,
          aktif: false,
        },
      });

      await expect(
        service.masukAntrean(tiketId, petugasId, loketId),
      ).rejects.toThrow(ForbiddenException);
    });

    it('menolak loket dari layanan berbeda', async () => {
      txMock.penugasanPetugas.findFirst.mockResolvedValue({
        ...penugasanUji,
        loket: {
          ...penugasanUji.loket,
          layananId: '00000000-0000-4000-8000-000000000003',
        },
      });

      await expect(
        service.masukAntrean(tiketId, petugasId, loketId),
      ).rejects.toThrow(ForbiddenException);
    });
  });

  // ========================================
  // C. VALIDASI TIKET DAN LAYANAN
  // ========================================

  describe('Validasi Tiket', () => {
    it('menolak tiket yang tidak ditemukan', async () => {
      txMock.tiketAntrean.findUnique.mockResolvedValue(null);

      await expect(
        service.masukAntrean(tiketId, petugasId, loketId),
      ).rejects.toThrow(NotFoundException);
    });

    it.each([StatusTiket.DIPESAN, StatusTiket.MENUNGGU, StatusTiket.SELESAI])(
      'menolak tiket berstatus %s',
      async (status) => {
        txMock.tiketAntrean.findUnique.mockResolvedValue({
          ...tiketUji,
          status,
        });

        await expect(
          service.masukAntrean(tiketId, petugasId, loketId),
        ).rejects.toThrow(ConflictException);
      },
    );

    it('menolak tiket tanpa waktu check-in', async () => {
      txMock.tiketAntrean.findUnique.mockResolvedValue({
        ...tiketUji,
        checkInPada: null,
      });

      await expect(
        service.masukAntrean(tiketId, petugasId, loketId),
      ).rejects.toThrow(ConflictException);
    });

    it('menolak tiket yang sudah memiliki FIFO', async () => {
      txMock.tiketAntrean.findUnique.mockResolvedValue({
        ...tiketUji,
        urutanMasukAntrean: 1,
      });

      await expect(
        service.masukAntrean(tiketId, petugasId, loketId),
      ).rejects.toThrow(ConflictException);
    });

    it('menolak layanan nonaktif', async () => {
      txMock.tiketAntrean.findUnique.mockResolvedValue({
        ...tiketUji,
        layanan: {
          aktif: false,
          prefixAntrean: 'A',
        },
      });

      await expect(
        service.masukAntrean(tiketId, petugasId, loketId),
      ).rejects.toThrow(ConflictException);
    });

    it('menolak tiket pada tanggal berbeda', async () => {
      txMock.tiketAntrean.findUnique.mockResolvedValue({
        ...tiketUji,
        tanggalAntrean: new Date('2026-10-12T00:00:00.000Z'),
      });

      await expect(
        service.masukAntrean(tiketId, petugasId, loketId),
      ).rejects.toThrow(ConflictException);
    });

    it('menolak jadwal layanan nonaktif', async () => {
      txMock.jadwalLayanan.findUnique.mockResolvedValue({
        aktif: false,
      });

      await expect(
        service.masukAntrean(tiketId, petugasId, loketId),
      ).rejects.toThrow(ConflictException);
    });

    it('menolak counter harian yang tidak ditemukan', async () => {
      txMock.urutanAntreanHarian.findUnique.mockResolvedValue(null);

      await expect(
        service.masukAntrean(tiketId, petugasId, loketId),
      ).rejects.toThrow(ConflictException);
    });
  });

  // ========================================
  // D. KONKURENSI DAN ERROR
  // ========================================

  describe('Transaksi dan Error Handling', () => {
    it('menolak perubahan tiket yang sudah diproses', async () => {
      txMock.tiketAntrean.updateMany.mockResolvedValue({
        count: 0,
      });

      await expect(
        service.masukAntrean(tiketId, petugasId, loketId),
      ).rejects.toThrow(ConflictException);

      expect(txMock.peristiwaAntrean.create).not.toHaveBeenCalled();
    });

    it('mengulang transaksi ketika menerima P2034', async () => {
      prismaMock.$transaction.mockRejectedValueOnce(buatKonflikTransaksi());

      const hasil = await service.masukAntrean(tiketId, petugasId, loketId);

      expect(hasil.status).toBe(StatusTiket.MENUNGGU);

      expect(prismaMock.$transaction).toHaveBeenCalledTimes(2);
    });

    it('berhenti setelah tiga konflik P2034', async () => {
      prismaMock.$transaction
        .mockRejectedValueOnce(buatKonflikTransaksi())
        .mockRejectedValueOnce(buatKonflikTransaksi())
        .mockRejectedValueOnce(buatKonflikTransaksi());

      await expect(
        service.masukAntrean(tiketId, petugasId, loketId),
      ).rejects.toThrow(ConflictException);

      expect(prismaMock.$transaction).toHaveBeenCalledTimes(3);
    });

    it('meneruskan kegagalan pencatatan audit', async () => {
      txMock.peristiwaAntrean.create.mockRejectedValue(
        new Error('Audit gagal disimpan'),
      );

      await expect(
        service.masukAntrean(tiketId, petugasId, loketId),
      ).rejects.toThrow('Audit gagal disimpan');
    });
  });

  // ========================================
  // E. PEMBACAAN FIFO
  // ========================================

  describe('Daftar Antrean FIFO', () => {
    it('membaca antrean MENUNGGU menurut urutan masuk', async () => {
      prismaMock.tiketAntrean.findMany.mockResolvedValue([
        {
          id: 'tiket-b',
          nomorUrut: 2,
          status: StatusTiket.MENUNGGU,
          urutanMasukAntrean: 1,
          masukAntreanPada: SEKARANG,
          layanan: {
            prefixAntrean: 'A',
          },
        },
        {
          id: 'tiket-a',
          nomorUrut: 1,
          status: StatusTiket.MENUNGGU,
          urutanMasukAntrean: 3,
          masukAntreanPada: SEKARANG,
          layanan: {
            prefixAntrean: 'A',
          },
        },
      ]);

      const hasil = await service.daftarMenunggu(petugasId, loketId);

      // A-002 boleh berada sebelum A-001
      // setelah terjadi requeue.
      expect(hasil.map((item) => item.nomorAntrean)).toEqual([
        'A-002',
        'A-001',
      ]);

      expect(prismaMock.tiketAntrean.findMany).toHaveBeenCalledWith({
        where: {
          layananId,
          tanggalAntrean: TANGGAL_PELAYANAN,
          status: StatusTiket.MENUNGGU,
          urutanMasukAntrean: {
            not: null,
          },
        },
        select: {
          id: true,
          nomorUrut: true,
          status: true,
          urutanMasukAntrean: true,
          masukAntreanPada: true,
          layanan: {
            select: {
              prefixAntrean: true,
            },
          },
        },
        orderBy: [
          {
            urutanMasukAntrean: 'asc',
          },
          {
            id: 'asc',
          },
        ],
        take: 100,
      });
    });

    it('menolak pembacaan FIFO oleh USER', async () => {
      prismaMock.pengguna.findUnique.mockResolvedValue({
        ...petugasUji,
        peran: PeranPengguna.USER,
      });

      await expect(service.daftarMenunggu(petugasId, loketId)).rejects.toThrow(
        ForbiddenException,
      );

      expect(prismaMock.tiketAntrean.findMany).not.toHaveBeenCalled();
    });

    it('menolak petugas tanpa penugasan aktif', async () => {
      prismaMock.penugasanPetugas.findFirst.mockResolvedValue(null);

      await expect(service.daftarMenunggu(petugasId, loketId)).rejects.toThrow(
        ForbiddenException,
      );

      expect(prismaMock.tiketAntrean.findMany).not.toHaveBeenCalled();
    });
  });

  // ========================================
  // H3.3 - HOSPITAL SELECTOR (MODE HIBRIDA)
  // ========================================
  describe('Hospital Queue Selector H3.3', () => {
    const slot = (mulai: string, selesai: string, ruang = loketId) => ({
      slotPraktik: {
        aktif: true,
        mulaiPada: new Date(mulai),
        selesaiPada: new Date(selesai),
        jadwalPraktik: { aktif: true, loketId: ruang, tanggal: TANGGAL_PELAYANAN,
          mulaiPada: new Date('2026-10-10T00:00:00Z'), selesaiPada: new Date('2026-10-10T06:00:00Z'),
          dokterLayanan: { aktif: true, dokter: { aktif: true } } },
      },
    });
    const tiketWalk = {
      id: '00000000-0000-4000-8000-000000000111',
      nomorUrut: 1,
      status: StatusTiket.MENUNGGU,
      versi: 3,
      loketId: null,
      urutanMasukAntrean: 1,
      masukAntreanPada: SEKARANG,
      checkInPada: new Date('2026-10-10T01:00:00Z'),
      tanggalAntrean: TANGGAL_PELAYANAN,
      janjiTemu: null,
    };
    const tiketJanji = {
      ...tiketWalk,
      id: tiketId,
      nomorUrut: 2,
      urutanMasukAntrean: 2,
      checkInPada: new Date('2026-10-10T02:10:00Z'),
      janjiTemu: slot('2026-10-10T02:00:00Z', '2026-10-10T03:00:00Z'),
    };
    function pakaiModeHibrida() {
      txMock.penugasanPetugas.findFirst.mockResolvedValue({
        id: penugasanId,
        loket: {
          id: loketId, kode: 'LKT-A1', aktif: true, layananId,
          layanan: { aktif: true, prefixAntrean: 'A', modeReservasi: ModeReservasi.HIBRIDA },
        },
      });
      prismaMock.penugasanPetugas.findFirst.mockResolvedValue({
        loket: { aktif: true, layananId,
          layanan: { aktif: true, prefixAntrean: 'A', modeReservasi: ModeReservasi.HIBRIDA } },
      });
      txMock.tiketAntrean.findFirst.mockResolvedValue(null);
    }
    it('CALL mengutamakan janji valid meski walk-in check-in lebih awal', async () => {
      pakaiModeHibrida();
      txMock.tiketAntrean.findMany.mockResolvedValue([tiketWalk, tiketJanji]);
      const hasil = await service.panggilBerikutnya(petugasId, loketId);
      expect(hasil.tiketId).toBe(tiketId);
      expect(txMock.tiketAntrean.updateMany).toHaveBeenCalledWith(expect.objectContaining({
        where: expect.objectContaining({ id: tiketId }),
      }));
      expect(txMock.peristiwaAntrean.create).toHaveBeenCalledTimes(1);
    });
    it('CALL mengutamakan walk-in ketika slot belum dibuka', async () => {
      pakaiModeHibrida();
      txMock.tiketAntrean.findMany.mockResolvedValue([
        tiketWalk,
        { ...tiketJanji, janjiTemu: slot('2026-10-10T03:00:00Z','2026-10-10T04:00:00Z') },
      ]);
      const hasil = await service.panggilBerikutnya(petugasId, loketId);
      expect(hasil.tiketId).toBe(tiketWalk.id);
    });
    it('CALL dan GET menunggu tetap memprioritaskan pasien setelah slot selesai', async () => {
      pakaiModeHibrida();
      const lama = { ...tiketJanji, janjiTemu: slot('2026-10-10T01:00:00Z', '2026-10-10T02:00:00Z') };
      const kandidat = [tiketWalk, lama];
      txMock.tiketAntrean.findMany.mockResolvedValue(kandidat);
      prismaMock.tiketAntrean.findMany.mockResolvedValue(kandidat);
      const daftar = await service.daftarMenunggu(petugasId, loketId);
      const hasil = await service.panggilBerikutnya(petugasId, loketId);
      expect(daftar[0]).toMatchObject({ tiketId: lama.id, layakDipanggil: true });
      expect(hasil.tiketId).toBe(daftar[0]?.tiketId);
    });
    it('CALL menolak janji yang dijadwalkan pada ruang lain', async () => {
      pakaiModeHibrida();
      txMock.tiketAntrean.findMany.mockResolvedValue([
        { ...tiketJanji, janjiTemu: slot('2026-10-10T02:00:00Z', '2026-10-10T03:00:00Z', 'loket-lain') },
      ]);
      await expect(service.panggilBerikutnya(petugasId, loketId)).rejects.toThrow(NotFoundException);
      expect(txMock.tiketAntrean.updateMany).not.toHaveBeenCalled();
    });
    it('GET menunggu menggunakan urutan prioritas yang sama dengan CALL', async () => {
      pakaiModeHibrida();
      prismaMock.tiketAntrean.findMany.mockResolvedValue([tiketWalk, tiketJanji]);
      const hasil = await service.daftarMenunggu(petugasId, loketId);
      expect(hasil.map((item) => item.tiketId)).toEqual([tiketId, tiketWalk.id]);
      expect(hasil[0]).toMatchObject({ jenisAntrean: 'JANJI_TEMU', layakDipanggil: true });
    });
    it('CALL dan GET menunggu membaca audit REQUEUE terbaru dan tidak memakai check-in lama', async () => {
      pakaiModeHibrida();
      const ulang = { ...tiketJanji, checkInPada: new Date('2026-10-10T01:00:00Z'),
        urutanMasukAntrean: 9,
        peristiwaAntrean: [{ terjadiPada: new Date('2026-10-10T02:25:00Z') }] };
      const menunggu = { ...tiketJanji, id: '00000000-0000-4000-8000-000000000222',
        nomorUrut: 3, urutanMasukAntrean: 3, peristiwaAntrean: [] };
      txMock.tiketAntrean.findMany.mockResolvedValue([ulang, menunggu]);
      prismaMock.tiketAntrean.findMany.mockResolvedValue([ulang, menunggu]);
      const daftar = await service.daftarMenunggu(petugasId, loketId);
      const hasil = await service.panggilBerikutnya(petugasId, loketId);
      expect(daftar.map((item) => item.tiketId)).toEqual([menunggu.id, ulang.id]);
      expect(hasil.tiketId).toBe(menunggu.id);
      const audit = { where: { tipe: 'REQUEUE' }, orderBy: { terjadiPada: 'desc' },
        take: 1, select: { terjadiPada: true } };
      for (const mock of [txMock.tiketAntrean.findMany, prismaMock.tiketAntrean.findMany]) {
        expect(mock).toHaveBeenCalledWith(expect.objectContaining({
          select: expect.objectContaining({ peristiwaAntrean: audit }),
        }));
      }
      expect(JSON.stringify(daftar)).not.toContain('peristiwaAntrean');
    });
    it('mode HIBRIDA tidak membatasi query kandidat menjadi 100 sebelum sorting', async () => {
      pakaiModeHibrida();
      prismaMock.tiketAntrean.findMany.mockResolvedValue([tiketWalk]);
      await service.daftarMenunggu(petugasId, loketId);
      expect(prismaMock.tiketAntrean.findMany.mock.calls[0][0]).not.toHaveProperty('take');
    });
  });

  // ==========================================
  // F. PEMANGGILAN ANTREAN (CALL)
  // ==========================================

  describe('Panggil Berikutnya (CALL)', () => {
    const tiketMenunggu = {
      ...tiketUji,
      status: StatusTiket.MENUNGGU,
      versi: 5,
      loketId: null,
      urutanMasukAntrean: 1,
    };

    beforeEach(() => {
      // Lengkapi data penugasan untuk CALL.
      txMock.penugasanPetugas.findFirst.mockResolvedValue({
        id: penugasanId,
        loket: {
          id: loketId,
          kode: 'LKT-A1',
          aktif: true,
          layananId,
          layanan: {
            aktif: true,
            prefixAntrean: 'A',
            modeReservasi: ModeReservasi.ANTREAN_HARIAN,
          },
        },
      });

      // Query pertama: loket belum memiliki
      // tiket DIPANGGIL atau DILAYANI.
      //
      // Query kedua: tiket FIFO berikutnya.
      txMock.tiketAntrean.findFirst
        .mockResolvedValueOnce(null)
        .mockResolvedValueOnce(tiketMenunggu);
    });

    // --------------------------------------
    // A. CALL BERHASIL
    // --------------------------------------

    it('mengubah MENUNGGU menjadi DIPANGGIL', async () => {
      const hasil = await service.panggilBerikutnya(petugasId, loketId);

      expect(hasil).toEqual({
        tiketId,
        layananId,
        loketId,
        kodeLoket: 'LKT-A1',
        nomorAntrean: 'A-001',
        status: StatusTiket.DIPANGGIL,
        urutanMasukAntrean: 1,
        dipanggilPada: SEKARANG.toISOString(),
        versi: 6,
      });
    });

    it('memilih tiket MENUNGGU dengan FIFO terkecil', async () => {
      await service.panggilBerikutnya(petugasId, loketId);

      expect(txMock.tiketAntrean.findFirst).toHaveBeenNthCalledWith(2, {
        where: {
          layananId,
          tanggalAntrean: TANGGAL_PELAYANAN,
          status: StatusTiket.MENUNGGU,
          urutanMasukAntrean: {
            not: null,
          },
        },
        orderBy: [
          {
            urutanMasukAntrean: 'asc',
          },
          {
            id: 'asc',
          },
        ],
        select: {
          id: true,
          nomorUrut: true,
          status: true,
          versi: true,
          loketId: true,
          urutanMasukAntrean: true,
        },
      });
    });

    it('memperbarui status, loket, waktu dan versi secara bersyarat', async () => {
      await service.panggilBerikutnya(petugasId, loketId);

      expect(txMock.tiketAntrean.updateMany).toHaveBeenCalledWith({
        where: {
          id: tiketId,
          layananId,
          tanggalAntrean: TANGGAL_PELAYANAN,
          status: StatusTiket.MENUNGGU,
          versi: 5,
          urutanMasukAntrean: 1,
        },
        data: {
          status: StatusTiket.DIPANGGIL,
          loketId,
          dipanggilPada: SEKARANG,
          versi: {
            increment: 1,
          },
        },
      });
    });

    it('tidak mengubah nomor urut maupun kode tiket', async () => {
      const hasil = await service.panggilBerikutnya(petugasId, loketId);

      expect(hasil.nomorAntrean).toBe('A-001');

      const argumen = txMock.tiketAntrean.updateMany.mock.calls[0]?.[0] as
        | {
            data: Record<string, unknown>;
          }
        | undefined;

      expect(argumen?.data).not.toHaveProperty('nomorUrut');

      expect(argumen?.data).not.toHaveProperty('kodeTiket');

      expect(argumen?.data).not.toHaveProperty('urutanMasukAntrean');
    });

    it('mencatat audit CALL dalam transaksi', async () => {
      await service.panggilBerikutnya(petugasId, loketId);

      expect(txMock.peristiwaAntrean.create).toHaveBeenCalledWith({
        data: {
          tiketAntreanId: tiketId,
          aktorId: petugasId,
          tipe: 'CALL',
          statusSebelum: StatusTiket.MENUNGGU,
          statusSesudah: StatusTiket.DIPANGGIL,
          dataTambahan: {
            metode: 'QUEUE_CALL',
            loketId,
            kodeLoket: 'LKT-A1',
            penugasanId,
            loketSebelumnya: null,
            urutanMasukAntrean: 1,
          },
        },
      });
    });

    it('menggunakan transaksi Serializable', async () => {
      await service.panggilBerikutnya(petugasId, loketId);

      expect(prismaMock.$transaction).toHaveBeenCalledWith(
        expect.any(Function),
        {
          isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
          maxWait: 10000,
          timeout: 15000,
        },
      );
    });

    // --------------------------------------
    // B. LOKET DAN ANTREAN
    // --------------------------------------

    it('menolak CALL ketika loket masih memiliki tiket aktif', async () => {
      txMock.tiketAntrean.findFirst.mockReset().mockResolvedValueOnce({
        id: 'tiket-aktif',
      });

      await expect(
        service.panggilBerikutnya(petugasId, loketId),
      ).rejects.toThrow(ConflictException);

      expect(txMock.tiketAntrean.findFirst).toHaveBeenCalledTimes(1);

      expect(txMock.tiketAntrean.updateMany).not.toHaveBeenCalled();

      expect(txMock.peristiwaAntrean.create).not.toHaveBeenCalled();
    });

    it('menghasilkan 404 jika tidak ada tiket MENUNGGU', async () => {
      txMock.tiketAntrean.findFirst
        .mockReset()
        .mockResolvedValueOnce(null)
        .mockResolvedValueOnce(null);

      await expect(
        service.panggilBerikutnya(petugasId, loketId),
      ).rejects.toThrow(NotFoundException);

      expect(txMock.tiketAntrean.updateMany).not.toHaveBeenCalled();
    });

    // --------------------------------------
    // C. VALIDASI PETUGAS
    // --------------------------------------

    it('menolak PETUGAS yang tidak ditemukan', async () => {
      txMock.pengguna.findUnique.mockResolvedValue(null);

      await expect(
        service.panggilBerikutnya(petugasId, loketId),
      ).rejects.toThrow(ForbiddenException);
    });

    it.each([PeranPengguna.USER, PeranPengguna.ADMIN])(
      'menolak CALL dari role %s',
      async (peran) => {
        txMock.pengguna.findUnique.mockResolvedValue({
          ...petugasUji,
          peran,
        });

        await expect(
          service.panggilBerikutnya(petugasId, loketId),
        ).rejects.toThrow(ForbiddenException);
      },
    );

    it('menolak PETUGAS nonaktif', async () => {
      txMock.pengguna.findUnique.mockResolvedValue({
        ...petugasUji,
        aktif: false,
      });

      await expect(
        service.panggilBerikutnya(petugasId, loketId),
      ).rejects.toThrow(ForbiddenException);
    });

    it('menolak petugas tanpa penugasan aktif', async () => {
      txMock.penugasanPetugas.findFirst.mockResolvedValue(null);

      await expect(
        service.panggilBerikutnya(petugasId, loketId),
      ).rejects.toThrow(ForbiddenException);
    });

    it('menolak loket nonaktif', async () => {
      txMock.penugasanPetugas.findFirst.mockResolvedValue({
        id: penugasanId,
        loket: {
          id: loketId,
          kode: 'LKT-A1',
          aktif: false,
          layananId,
          layanan: {
            aktif: true,
            prefixAntrean: 'A',
          },
        },
      });

      await expect(
        service.panggilBerikutnya(petugasId, loketId),
      ).rejects.toThrow(ForbiddenException);
    });

    it('menolak layanan nonaktif', async () => {
      txMock.penugasanPetugas.findFirst.mockResolvedValue({
        id: penugasanId,
        loket: {
          id: loketId,
          kode: 'LKT-A1',
          aktif: true,
          layananId,
          layanan: {
            aktif: false,
            prefixAntrean: 'A',
          },
        },
      });

      await expect(
        service.panggilBerikutnya(petugasId, loketId),
      ).rejects.toThrow(ForbiddenException);
    });

    it('menolak jadwal layanan nonaktif', async () => {
      txMock.jadwalLayanan.findUnique.mockResolvedValue({
        aktif: false,
      });

      await expect(
        service.panggilBerikutnya(petugasId, loketId),
      ).rejects.toThrow(ConflictException);
    });

    // --------------------------------------
    // D. KONKURENSI DAN KESALAHAN AUDIT
    // --------------------------------------

    it('menolak ketika tiket telah diubah request lain', async () => {
      txMock.tiketAntrean.updateMany.mockResolvedValue({
        count: 0,
      });

      await expect(
        service.panggilBerikutnya(petugasId, loketId),
      ).rejects.toThrow(ConflictException);

      expect(txMock.peristiwaAntrean.create).not.toHaveBeenCalled();
    });

    it('melakukan retry ketika terjadi konflik P2034', async () => {
      prismaMock.$transaction.mockRejectedValueOnce(buatKonflikTransaksi());

      const hasil = await service.panggilBerikutnya(petugasId, loketId);

      expect(hasil.status).toBe(StatusTiket.DIPANGGIL);

      expect(prismaMock.$transaction).toHaveBeenCalledTimes(2);
    });

    it('menolak setelah tiga konflik P2034', async () => {
      prismaMock.$transaction
        .mockRejectedValueOnce(buatKonflikTransaksi())
        .mockRejectedValueOnce(buatKonflikTransaksi())
        .mockRejectedValueOnce(buatKonflikTransaksi());

      await expect(
        service.panggilBerikutnya(petugasId, loketId),
      ).rejects.toThrow(ConflictException);

      expect(prismaMock.$transaction).toHaveBeenCalledTimes(3);
    });

    it('meneruskan error jika audit CALL gagal', async () => {
      txMock.peristiwaAntrean.create.mockRejectedValue(
        new Error('Audit CALL gagal disimpan'),
      );

      await expect(
        service.panggilBerikutnya(petugasId, loketId),
      ).rejects.toThrow('Audit CALL gagal disimpan');
    });
  });
});
