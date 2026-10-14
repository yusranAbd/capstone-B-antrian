import {
  BadRequestException,
  ConflictException,
  NotFoundException,
} from '@nestjs/common';
import { Test } from '@nestjs/testing';

import { HariLayanan, Prisma, StatusTiket } from '../generated/prisma/client';

import { PrismaService } from '../prisma/prisma.service';
import { ReservasiService } from './reservasi.service';

// ==========================================
// DATA PENGUJIAN
// ==========================================

const penggunaId = 'ec8a387e-f186-4324-8c6a-faec174ce55c';

const penggunaLainId = '00000000-0000-4000-8000-000000000002';

const layananId = '1bfa9aa4-6c27-4e67-b938-b0fb53f485cf';

const tiketId = '1a33984d-d5f1-4fdb-b888-545a2c5be9c8';

// Gunakan tanggal masa depan agar test
// tidak bergantung pada tanggal tertentu.
const tanggalAntrean = (() => {
  const tanggal = new Date();
  tanggal.setUTCDate(tanggal.getUTCDate() + 30);
  return tanggal.toISOString().slice(0, 10);
})();

const tanggal = new Date(`${tanggalAntrean}T00:00:00.000Z`);

const daftarHari: HariLayanan[] = [
  HariLayanan.MINGGU,
  HariLayanan.SENIN,
  HariLayanan.SELASA,
  HariLayanan.RABU,
  HariLayanan.KAMIS,
  HariLayanan.JUMAT,
  HariLayanan.SABTU,
];

const hari = daftarHari[tanggal.getUTCDay()];

const createDto = {
  layananId,
  tanggalAntrean,
};

const layananUji = {
  id: layananId,
  aktif: true,
};

const jadwalUji = {
  aktif: true,
  kapasitasHarian: 100,
};

const counterUji = {
  nomorTerakhir: 1,
};

const tiketUji = {
  id: tiketId,
  penggunaId,
  layananId,
  tanggalAntrean: tanggal,
  nomorUrut: 1,
  kodeTiket: 'TK604CF19B8EBD8AFB1E1FC88D',
  status: StatusTiket.DIPESAN,
  dibuatPada: new Date(),
  layanan: {
    id: layananId,
    kode: 'ADM',
    nama: 'Layanan Administrasi Umum',
    prefixAntrean: 'A',
  },
};

// ==========================================
// MOCK TRANSAKSI PRISMA
// ==========================================

function buatTransactionMock() {
  return {
    layanan: {
      findUnique: jest.fn(),
    },
    jadwalLayanan: {
      findUnique: jest.fn(),
    },
    urutanAntreanHarian: {
      upsert: jest.fn(),
    },
    tiketAntrean: {
      findFirst: jest.fn(),
      count: jest.fn(),
      create: jest.fn(),
    },
  };
}

function buatPrismaMock() {
  return {
    $transaction: jest.fn(),
    tiketAntrean: {
      findMany: jest.fn(),
      findFirst: jest.fn(),
    },
  };
}

function errorPrisma(code: string): Prisma.PrismaClientKnownRequestError {
  return new Prisma.PrismaClientKnownRequestError('Simulasi kesalahan Prisma', {
    code,
    clientVersion: '7.10.0',
  });
}

// ==========================================
// UNIT TEST RESERVASI SERVICE
// ==========================================

describe('ReservasiService', () => {
  let service: ReservasiService;

  let prismaMock: ReturnType<typeof buatPrismaMock>;
  let txMock: ReturnType<typeof buatTransactionMock>;

  beforeEach(async () => {
    prismaMock = buatPrismaMock();
    txMock = buatTransactionMock();

    // Jalankan callback transaction menggunakan
    // Prisma Transaction Mock.
    prismaMock.$transaction.mockImplementation(
      async (callback: (tx: typeof txMock) => Promise<unknown>) =>
        callback(txMock),
    );

    // Default: data valid dan kapasitas tersedia.
    txMock.layanan.findUnique.mockResolvedValue(layananUji);

    txMock.jadwalLayanan.findUnique.mockResolvedValue(jadwalUji);

    txMock.urutanAntreanHarian.upsert.mockResolvedValue(counterUji);

    txMock.tiketAntrean.findFirst.mockResolvedValue(null);

    txMock.tiketAntrean.count.mockResolvedValue(0);

    txMock.tiketAntrean.create.mockResolvedValue(tiketUji);

    prismaMock.tiketAntrean.findMany.mockResolvedValue([tiketUji]);

    prismaMock.tiketAntrean.findFirst.mockResolvedValue(tiketUji);

    const moduleRef = await Test.createTestingModule({
      providers: [
        ReservasiService,
        {
          provide: PrismaService,
          useValue: prismaMock,
        },
      ],
    }).compile();

    service = moduleRef.get<ReservasiService>(ReservasiService);
  });

  // ========================================
  // A. CREATE RESERVASI - 3 TEST
  // ========================================

  describe('Create Reservasi', () => {
    it('berhasil membuat tiket menggunakan transaksi Serializable', async () => {
      const hasil = await service.create(createDto, penggunaId);

      expect(hasil).toEqual(tiketUji);

      expect(prismaMock.$transaction).toHaveBeenCalledWith(
        expect.any(Function),
        {
          isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
          maxWait: 10000,
          timeout: 15000,
        },
      );

      expect(txMock.layanan.findUnique).toHaveBeenCalledWith({
        where: {
          id: layananId,
        },
        select: {
          id: true,
          aktif: true,
          modeReservasi: true,
        },
      });

      expect(txMock.jadwalLayanan.findUnique).toHaveBeenCalledWith({
        where: {
          layananId_hari: {
            layananId,
            hari,
          },
        },
        select: {
          aktif: true,
          kapasitasHarian: true,
        },
      });

      expect(txMock.tiketAntrean.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: {
            pengguna: {
              connect: {
                id: penggunaId,
              },
            },
            layanan: {
              connect: {
                id: layananId,
              },
            },
            tanggalAntrean: tanggal,
            nomorUrut: 1,
            kodeTiket: expect.stringMatching(/^TK[A-F0-9]{24}$/) as string,
            status: StatusTiket.DIPESAN,
          },
        }),
      );
    });

    it('menggunakan nomor terakhir dari counter harian', async () => {
      txMock.urutanAntreanHarian.upsert.mockResolvedValue({
        nomorTerakhir: 7,
      });

      txMock.tiketAntrean.create.mockResolvedValue({
        ...tiketUji,
        nomorUrut: 7,
      });

      const hasil = await service.create(createDto, penggunaId);

      expect(hasil.nomorUrut).toBe(7);

      expect(txMock.urutanAntreanHarian.upsert).toHaveBeenCalledWith({
        where: {
          layananId_tanggal: {
            layananId,
            tanggal,
          },
        },
        create: {
          layananId,
          tanggal,
          nomorTerakhir: 1,
        },
        update: {
          nomorTerakhir: {
            increment: 1,
          },
        },
      });

      expect(txMock.tiketAntrean.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            nomorUrut: 7,
          }),
        }),
      );
    });

    it('mengizinkan reservasi pada slot terakhir yang tersedia', async () => {
      txMock.jadwalLayanan.findUnique.mockResolvedValue({
        aktif: true,
        kapasitasHarian: 3,
      });

      txMock.tiketAntrean.count.mockResolvedValue(2);

      const hasil = await service.create(createDto, penggunaId);

      expect(hasil.status).toBe(StatusTiket.DIPESAN);

      expect(txMock.tiketAntrean.create).toHaveBeenCalledTimes(1);
    });
  });

  // ========================================
  // B. VALIDASI BISNIS - 9 TEST
  // ========================================

  describe('Validasi Reservasi', () => {
    it('menolak format tanggal tidak valid', async () => {
      await expect(
        service.create(
          {
            layananId,
            tanggalAntrean: '12/10/2099',
          },
          penggunaId,
        ),
      ).rejects.toThrow(BadRequestException);

      expect(prismaMock.$transaction).not.toHaveBeenCalled();
    });

    it('menolak tanggal kalender yang tidak ada', async () => {
      await expect(
        service.create(
          {
            layananId,
            tanggalAntrean: '2099-02-30',
          },
          penggunaId,
        ),
      ).rejects.toThrow(BadRequestException);
    });

    it('menolak tanggal reservasi yang sudah lewat', async () => {
      await expect(
        service.create(
          {
            layananId,
            tanggalAntrean: '2020-01-01',
          },
          penggunaId,
        ),
      ).rejects.toThrow(BadRequestException);

      expect(prismaMock.$transaction).not.toHaveBeenCalled();
    });

    it('menolak layanan yang tidak ditemukan', async () => {
      txMock.layanan.findUnique.mockResolvedValue(null);

      await expect(service.create(createDto, penggunaId)).rejects.toThrow(
        NotFoundException,
      );

      expect(txMock.tiketAntrean.create).not.toHaveBeenCalled();
    });

    it('menolak layanan yang tidak aktif', async () => {
      txMock.layanan.findUnique.mockResolvedValue({
        id: layananId,
        aktif: false,
      });

      await expect(service.create(createDto, penggunaId)).rejects.toThrow(
        BadRequestException,
      );

      expect(txMock.tiketAntrean.create).not.toHaveBeenCalled();
    });

    it('menolak hari tanpa jadwal pelayanan', async () => {
      txMock.jadwalLayanan.findUnique.mockResolvedValue(null);

      await expect(service.create(createDto, penggunaId)).rejects.toThrow(
        BadRequestException,
      );

      expect(txMock.urutanAntreanHarian.upsert).not.toHaveBeenCalled();
    });

    it('menolak jadwal pelayanan nonaktif', async () => {
      txMock.jadwalLayanan.findUnique.mockResolvedValue({
        aktif: false,
        kapasitasHarian: 100,
      });

      await expect(service.create(createDto, penggunaId)).rejects.toThrow(
        BadRequestException,
      );

      expect(txMock.tiketAntrean.create).not.toHaveBeenCalled();
    });

    it('menolak reservasi duplikat milik pengguna yang sama', async () => {
      txMock.tiketAntrean.findFirst.mockResolvedValue({
        id: tiketId,
      });

      await expect(service.create(createDto, penggunaId)).rejects.toThrow(
        ConflictException,
      );

      expect(txMock.tiketAntrean.findFirst).toHaveBeenCalledWith({
        where: {
          penggunaId,
          layananId,
          tanggalAntrean: tanggal,
          status: {
            not: StatusTiket.DIBATALKAN,
          },
        },
        select: {
          id: true,
        },
      });

      expect(txMock.tiketAntrean.create).not.toHaveBeenCalled();
    });

    it('menolak reservasi saat kapasitas harian penuh', async () => {
      txMock.jadwalLayanan.findUnique.mockResolvedValue({
        aktif: true,
        kapasitasHarian: 2,
      });

      txMock.tiketAntrean.count.mockResolvedValue(2);

      await expect(service.create(createDto, penggunaId)).rejects.toThrow(
        ConflictException,
      );

      expect(txMock.tiketAntrean.count).toHaveBeenCalledWith({
        where: {
          layananId,
          tanggalAntrean: tanggal,
          status: {
            not: StatusTiket.DIBATALKAN,
          },
        },
      });

      expect(txMock.tiketAntrean.create).not.toHaveBeenCalled();
    });
  });

  // ========================================
  // C. TRANSAKSI DAN RETRY - 7 TEST
  // ========================================

  describe('Transaksi dan Error Handling', () => {
    it('mengulang transaksi setelah konflik P2034', async () => {
      prismaMock.$transaction.mockRejectedValueOnce(errorPrisma('P2034'));

      const hasil = await service.create(createDto, penggunaId);

      expect(hasil).toEqual(tiketUji);

      expect(prismaMock.$transaction).toHaveBeenCalledTimes(2);
    });

    it('mengulang transaksi setelah unique collision P2002', async () => {
      prismaMock.$transaction.mockRejectedValueOnce(errorPrisma('P2002'));

      const hasil = await service.create(createDto, penggunaId);

      expect(hasil.status).toBe(StatusTiket.DIPESAN);

      expect(prismaMock.$transaction).toHaveBeenCalledTimes(2);
    });

    it('mengembalikan Conflict setelah lima percobaan P2034', async () => {
      prismaMock.$transaction.mockRejectedValue(errorPrisma('P2034'));

      await expect(service.create(createDto, penggunaId)).rejects.toThrow(
        ConflictException,
      );

      expect(prismaMock.$transaction).toHaveBeenCalledTimes(5);
    });

    it('mengembalikan Conflict setelah lima percobaan P2002', async () => {
      prismaMock.$transaction.mockRejectedValue(errorPrisma('P2002'));

      await expect(service.create(createDto, penggunaId)).rejects.toThrow(
        ConflictException,
      );

      expect(prismaMock.$transaction).toHaveBeenCalledTimes(5);
    });

    it('mengubah P2003 menjadi BadRequestException', async () => {
      prismaMock.$transaction.mockRejectedValueOnce(errorPrisma('P2003'));

      await expect(service.create(createDto, penggunaId)).rejects.toThrow(
        BadRequestException,
      );

      expect(prismaMock.$transaction).toHaveBeenCalledTimes(1);
    });

    it('mengubah P2025 menjadi BadRequestException', async () => {
      prismaMock.$transaction.mockRejectedValueOnce(errorPrisma('P2025'));

      await expect(service.create(createDto, penggunaId)).rejects.toThrow(
        BadRequestException,
      );
    });

    it('meneruskan kesalahan yang tidak dikenali', async () => {
      prismaMock.$transaction.mockRejectedValueOnce(
        new Error('Gangguan database'),
      );

      await expect(service.create(createDto, penggunaId)).rejects.toThrow(
        'Gangguan database',
      );

      expect(prismaMock.$transaction).toHaveBeenCalledTimes(1);
    });
  });

  // ========================================
  // D. READ RESERVASI - 5 TEST
  // ========================================

  describe('Read Reservasi', () => {
    it('menampilkan hanya reservasi milik pengguna', async () => {
      const hasil = await service.findAll(penggunaId);

      expect(hasil).toEqual([tiketUji]);

      expect(prismaMock.tiketAntrean.findMany).toHaveBeenCalledWith({
        where: {
          penggunaId,
        },
        select: expect.any(Object),
        orderBy: [{ tanggalAntrean: 'desc' }, { nomorUrut: 'asc' }],
      });
    });

    it('mengembalikan daftar kosong jika belum ada reservasi', async () => {
      prismaMock.tiketAntrean.findMany.mockResolvedValue([]);

      const hasil = await service.findAll(penggunaId);

      expect(hasil).toEqual([]);
    });

    it('berhasil mengambil detail reservasi milik sendiri', async () => {
      const hasil = await service.findOne(tiketId, penggunaId);

      expect(hasil).toEqual(tiketUji);

      expect(prismaMock.tiketAntrean.findFirst).toHaveBeenCalledWith({
        where: {
          id: tiketId,
          penggunaId,
        },
        select: expect.any(Object),
      });
    });

    it('menolak reservasi yang tidak ditemukan', async () => {
      prismaMock.tiketAntrean.findFirst.mockResolvedValue(null);

      await expect(service.findOne(tiketId, penggunaId)).rejects.toThrow(
        NotFoundException,
      );
    });

    it('memastikan detail dicari berdasarkan identitas pemilik', async () => {
      prismaMock.tiketAntrean.findFirst.mockResolvedValue(null);

      await expect(service.findOne(tiketId, penggunaLainId)).rejects.toThrow(
        NotFoundException,
      );

      expect(prismaMock.tiketAntrean.findFirst).toHaveBeenCalledWith({
        where: {
          id: tiketId,
          penggunaId: penggunaLainId,
        },
        select: expect.any(Object),
      });
    });
  });
});
