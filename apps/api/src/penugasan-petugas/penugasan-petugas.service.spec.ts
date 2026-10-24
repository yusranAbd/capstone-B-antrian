import {
  BadRequestException,
  ConflictException,
  NotFoundException,
} from '@nestjs/common';
import { Test } from '@nestjs/testing';

import { PeranPengguna, Prisma } from '../generated/prisma/client';

import { PrismaService } from '../prisma/prisma.service';
import { PenugasanPetugasService } from './penugasan-petugas.service';

// ==========================================
// DATA PENGUJIAN
// ==========================================

const petugasId = '3d70dbda-357e-49f1-8a6b-9f11e5353c81';

const petugasLainId = 'ec8a387e-f186-4324-8c6a-faec174ce55c';

const loketId = '10cd449d-8347-40c4-b1d4-de399db1e33b';

const penugasanId = 'a4c29d62-85d7-4498-97a6-c5a1f572beb5';

const tanggalMulai = new Date('2026-10-12T00:00:00.000Z');

const tanggalSelesai = new Date('2026-10-16T00:00:00.000Z');

const petugasUji = {
  id: petugasId,
  nama: 'Petugas Administrasi 1',
  email: 'petugas1@test.local',
  peran: PeranPengguna.PETUGAS,
  aktif: true,
};

const loketUji = {
  id: loketId,
  aktif: true,
  layanan: {
    aktif: true,
  },
};

const penugasanUji = {
  id: penugasanId,
  petugasId,
  loketId,
  tanggalMulai,
  tanggalSelesai,
  aktif: true,
  dibuatPada: new Date('2026-10-09T08:42:55.846Z'),
};

const dataCreate = {
  petugasId,
  loketId,
  tanggalMulai: '2026-10-12',
  tanggalSelesai: '2026-10-16',
};

// ==========================================
// MOCK PRISMA
// ==========================================

const buatPrismaMock = () => {
  const mock = {
    $queryRaw: jest.fn(),
    $transaction: jest.fn(),
    pengguna: {
      findUnique: jest.fn(),
    },

    loket: {
      findUnique: jest.fn(),
    },

    penugasanPetugas: {
      create: jest.fn(),
      findMany: jest.fn(),
      findFirst: jest.fn(),
      findUnique: jest.fn(),
      update: jest.fn(),
    },
  };
  mock.$transaction.mockImplementation(
    (callback: (tx: typeof mock) => unknown) => callback(mock),
  );
  return mock;
};

// ==========================================
// HELPER ERROR PRISMA
// ==========================================

function buatErrorPrisma(kode: string): Prisma.PrismaClientKnownRequestError {
  return new Prisma.PrismaClientKnownRequestError(
    'Simulasi kesalahan database',
    {
      code: kode,
      clientVersion: '7.10.0',
    },
  );
}

// ==========================================
// UNIT TEST PENUGASAN PETUGAS
// ==========================================

describe('PenugasanPetugasService', () => {
  let service: PenugasanPetugasService;
  let prismaMock: ReturnType<typeof buatPrismaMock>;

  beforeEach(async () => {
    prismaMock = buatPrismaMock();

    const moduleRef = await Test.createTestingModule({
      providers: [
        PenugasanPetugasService,
        {
          provide: PrismaService,
          useValue: prismaMock,
        },
      ],
    }).compile();

    service = moduleRef.get<PenugasanPetugasService>(PenugasanPetugasService);

    // Konfigurasi default untuk skenario valid.
    // Setiap test boleh mengubah respons mock.

    prismaMock.pengguna.findUnique.mockResolvedValue(petugasUji);

    prismaMock.loket.findUnique.mockResolvedValue(loketUji);

    prismaMock.penugasanPetugas.findFirst.mockResolvedValue(null);

    prismaMock.penugasanPetugas.findUnique.mockResolvedValue(penugasanUji);

    prismaMock.penugasanPetugas.create.mockResolvedValue(penugasanUji);

    prismaMock.penugasanPetugas.update.mockResolvedValue(penugasanUji);

    prismaMock.penugasanPetugas.findMany.mockResolvedValue([penugasanUji]);
  });

  // ========================================
  // 1. CREATE PENUGASAN - 12 TEST
  // ========================================

  describe('Create Penugasan', () => {
    it('berhasil membuat penugasan valid', async () => {
      const hasil = await service.create(dataCreate);

      expect(hasil).toEqual(penugasanUji);

      expect(prismaMock.pengguna.findUnique).toHaveBeenCalledWith({
        where: { id: petugasId },
        select: {
          id: true,
          peran: true,
          aktif: true,
        },
      });

      expect(prismaMock.loket.findUnique).toHaveBeenCalledWith({
        where: { id: loketId },
        select: {
          id: true,
          aktif: true,
          layanan: {
            select: { aktif: true },
          },
        },
      });

      expect(prismaMock.penugasanPetugas.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: {
            tanggalMulai,
            tanggalSelesai,
            aktif: true,
            petugas: {
              connect: { id: petugasId },
            },
            loket: {
              connect: { id: loketId },
            },
          },
        }),
      );
    });

    it('berhasil membuat penugasan tanpa tanggal selesai', async () => {
      prismaMock.penugasanPetugas.create.mockResolvedValue({
        ...penugasanUji,
        tanggalSelesai: null,
      });

      const hasil = await service.create({
        petugasId,
        loketId,
        tanggalMulai: '2026-10-12',
      });

      expect(hasil.tanggalSelesai).toBeNull();

      expect(prismaMock.penugasanPetugas.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            tanggalSelesai: null,
          }),
        }),
      );
    });

    it('menolak tanggal kalender tidak valid', async () => {
      await expect(
        service.create({
          ...dataCreate,
          tanggalMulai: '2026-02-30',
        }),
      ).rejects.toThrow(BadRequestException);

      expect(prismaMock.penugasanPetugas.create).not.toHaveBeenCalled();
    });

    it('menolak tanggal selesai sebelum tanggal mulai', async () => {
      await expect(
        service.create({
          ...dataCreate,
          tanggalMulai: '2026-10-20',
          tanggalSelesai: '2026-10-16',
        }),
      ).rejects.toThrow(BadRequestException);
    });

    it('menolak akun PETUGAS nonaktif sebelum menyimpan penugasan', async () => {
      prismaMock.pengguna.findUnique.mockResolvedValue({
        ...petugasUji,
        aktif: false,
      });
      await expect(service.create(dataCreate)).rejects.toThrow(
        'Akun PETUGAS harus aktif',
      );
      expect(prismaMock.penugasanPetugas.create).not.toHaveBeenCalled();
    });

    it('menolak jika pengguna petugas tidak ditemukan', async () => {
      prismaMock.pengguna.findUnique.mockResolvedValue(null);

      await expect(service.create(dataCreate)).rejects.toThrow(
        NotFoundException,
      );

      expect(prismaMock.penugasanPetugas.create).not.toHaveBeenCalled();
    });

    it('menolak pengguna yang bukan PETUGAS', async () => {
      prismaMock.pengguna.findUnique.mockResolvedValue({
        id: petugasId,
        peran: PeranPengguna.USER,
      });

      await expect(service.create(dataCreate)).rejects.toThrow(
        BadRequestException,
      );
    });

    it('menolak jika loket tidak ditemukan', async () => {
      prismaMock.loket.findUnique.mockResolvedValue(null);

      await expect(service.create(dataCreate)).rejects.toThrow(
        NotFoundException,
      );
    });

    it('menolak penugasan pada loket nonaktif', async () => {
      prismaMock.loket.findUnique.mockResolvedValue({
        ...loketUji,
        aktif: false,
      });

      await expect(service.create(dataCreate)).rejects.toThrow(
        BadRequestException,
      );
    });

    it('menolak jika layanan induk nonaktif', async () => {
      prismaMock.loket.findUnique.mockResolvedValue({
        ...loketUji,
        layanan: {
          aktif: false,
        },
      });

      await expect(service.create(dataCreate)).rejects.toThrow(
        BadRequestException,
      );
    });

    it('menolak periode penugasan yang bertabrakan', async () => {
      prismaMock.penugasanPetugas.findFirst.mockResolvedValue({
        id: '00000000-0000-4000-8000-000000000001',
      });

      await expect(service.create(dataCreate)).rejects.toThrow(
        ConflictException,
      );

      expect(prismaMock.penugasanPetugas.findFirst).toHaveBeenCalledWith({
        where: {
          petugasId,
          aktif: true,
          tanggalMulai: {
            lte: tanggalSelesai,
          },
          OR: [
            { tanggalSelesai: null },
            {
              tanggalSelesai: {
                gte: tanggalMulai,
              },
            },
          ],
        },
        select: {
          id: true,
        },
      });

      expect(prismaMock.penugasanPetugas.create).not.toHaveBeenCalled();
    });

    it('menangani konflik unique database', async () => {
      prismaMock.penugasanPetugas.create.mockRejectedValue(
        buatErrorPrisma('P2002'),
      );

      await expect(service.create(dataCreate)).rejects.toThrow(
        ConflictException,
      );
    });

    it('menangani kesalahan foreign key database', async () => {
      prismaMock.penugasanPetugas.create.mockRejectedValue(
        buatErrorPrisma('P2003'),
      );

      await expect(service.create(dataCreate)).rejects.toThrow(
        BadRequestException,
      );
    });
  });

  // ========================================
  // 2. READ ALL DAN READ ONE - 5 TEST
  // ========================================

  describe('Read Penugasan', () => {
    it('ADMIN dapat melihat seluruh penugasan', async () => {
      const hasil = await service.findAll(PeranPengguna.ADMIN, petugasId);

      expect(hasil).toHaveLength(1);

      expect(prismaMock.penugasanPetugas.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: {},
        }),
      );
    });

    it('PETUGAS hanya melihat penugasannya sendiri', async () => {
      await service.findAll(PeranPengguna.PETUGAS, petugasId);

      expect(prismaMock.penugasanPetugas.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: {
            petugasId,
          },
        }),
      );
    });

    it('ADMIN dapat melihat detail penugasan', async () => {
      prismaMock.penugasanPetugas.findFirst.mockResolvedValue(penugasanUji);

      const hasil = await service.findOne(
        penugasanId,
        PeranPengguna.ADMIN,
        petugasLainId,
      );

      expect(hasil.id).toBe(penugasanId);

      expect(prismaMock.penugasanPetugas.findFirst).toHaveBeenCalledWith(
        expect.objectContaining({
          where: {
            id: penugasanId,
          },
        }),
      );
    });

    it('PETUGAS hanya dapat membuka detail miliknya', async () => {
      prismaMock.penugasanPetugas.findFirst.mockResolvedValue(penugasanUji);

      const hasil = await service.findOne(
        penugasanId,
        PeranPengguna.PETUGAS,
        petugasId,
      );

      expect(hasil.petugasId).toBe(petugasId);

      expect(prismaMock.penugasanPetugas.findFirst).toHaveBeenCalledWith(
        expect.objectContaining({
          where: {
            id: penugasanId,
            petugasId,
          },
        }),
      );
    });

    it('menolak detail penugasan yang tidak ditemukan', async () => {
      prismaMock.penugasanPetugas.findFirst.mockResolvedValue(null);

      await expect(
        service.findOne(penugasanId, PeranPengguna.PETUGAS, petugasId),
      ).rejects.toThrow(NotFoundException);
    });
  });

  // ========================================
  // 3. UPDATE PENUGASAN - 9 TEST
  // ========================================

  describe('Update Penugasan', () => {
    it('berhasil memperpanjang tanggal penugasan', async () => {
      const tanggalBaru = new Date('2026-10-20T00:00:00.000Z');

      prismaMock.penugasanPetugas.update.mockResolvedValue({
        ...penugasanUji,
        tanggalSelesai: tanggalBaru,
      });

      const hasil = await service.update(penugasanId, {
        tanggalSelesai: '2026-10-20',
      });

      expect(hasil.tanggalSelesai).toEqual(tanggalBaru);

      expect(prismaMock.penugasanPetugas.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: {
            id: penugasanId,
          },
          data: expect.objectContaining({
            tanggalSelesai: tanggalBaru,
          }),
        }),
      );
    });

    it('berhasil menghapus batas tanggal selesai', async () => {
      prismaMock.penugasanPetugas.update.mockResolvedValue({
        ...penugasanUji,
        tanggalSelesai: null,
      });

      const hasil = await service.update(penugasanId, {
        tanggalSelesai: null,
      });

      expect(hasil.tanggalSelesai).toBeNull();

      expect(prismaMock.penugasanPetugas.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            tanggalSelesai: null,
          }),
        }),
      );
    });

    it('menolak perubahan rentang tanggal tidak valid', async () => {
      await expect(
        service.update(penugasanId, {
          tanggalMulai: '2026-10-25',
          tanggalSelesai: '2026-10-20',
        }),
      ).rejects.toThrow(BadRequestException);

      expect(prismaMock.penugasanPetugas.update).not.toHaveBeenCalled();
    });

    it('menolak update jika penugasan tidak ditemukan', async () => {
      prismaMock.penugasanPetugas.findUnique.mockResolvedValue(null);

      await expect(
        service.update(penugasanId, {
          tanggalSelesai: '2026-10-20',
        }),
      ).rejects.toThrow(NotFoundException);
    });

    it('menolak benturan dengan penugasan lain', async () => {
      prismaMock.penugasanPetugas.findFirst.mockResolvedValue({
        id: '00000000-0000-4000-8000-000000000002',
      });

      await expect(
        service.update(penugasanId, {
          tanggalSelesai: '2026-10-20',
        }),
      ).rejects.toThrow(ConflictException);

      expect(prismaMock.penugasanPetugas.findFirst).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({
            petugasId,
            aktif: true,
            id: {
              not: penugasanId,
            },
          }),
        }),
      );
    });

    it('penugasan nonaktif dapat diubah tanpa validasi konflik', async () => {
      prismaMock.penugasanPetugas.findUnique.mockResolvedValue({
        ...penugasanUji,
        aktif: false,
      });

      prismaMock.penugasanPetugas.update.mockResolvedValue({
        ...penugasanUji,
        aktif: false,
        tanggalSelesai: new Date('2026-10-20T00:00:00.000Z'),
      });

      const hasil = await service.update(penugasanId, {
        tanggalSelesai: '2026-10-20',
      });

      expect(hasil.aktif).toBe(false);

      expect(prismaMock.penugasanPetugas.findFirst).not.toHaveBeenCalled();

      expect(prismaMock.penugasanPetugas.update).toHaveBeenCalled();
    });

    it('menolak reaktivasi jika loket nonaktif', async () => {
      prismaMock.penugasanPetugas.findUnique.mockResolvedValue({
        ...penugasanUji,
        aktif: false,
      });

      prismaMock.loket.findUnique.mockResolvedValue({
        ...loketUji,
        aktif: false,
      });

      await expect(
        service.update(penugasanId, {
          aktif: true,
        }),
      ).rejects.toThrow(BadRequestException);

      expect(prismaMock.penugasanPetugas.update).not.toHaveBeenCalled();
    });

    it('menolak pemindahan kepada pengguna bukan PETUGAS', async () => {
      prismaMock.pengguna.findUnique.mockResolvedValue({
        id: petugasLainId,
        peran: PeranPengguna.USER,
      });

      await expect(
        service.update(penugasanId, {
          petugasId: petugasLainId,
        }),
      ).rejects.toThrow(BadRequestException);
    });

    it('mengubah error P2025 menjadi NotFoundException', async () => {
      prismaMock.penugasanPetugas.update.mockRejectedValue(
        buatErrorPrisma('P2025'),
      );

      await expect(
        service.update(penugasanId, {
          tanggalSelesai: '2026-10-20',
        }),
      ).rejects.toThrow(NotFoundException);
    });
  });

  // ========================================
  // 4. SOFT DELETE - 2 TEST
  // ========================================

  describe('Soft Delete Penugasan', () => {
    it('berhasil menonaktifkan tanpa menghapus data', async () => {
      prismaMock.penugasanPetugas.update.mockResolvedValue({
        ...penugasanUji,
        aktif: false,
      });

      const hasil = await service.remove(penugasanId);

      expect(hasil.aktif).toBe(false);

      expect(prismaMock.penugasanPetugas.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: {
            id: penugasanId,
          },
          data: {
            aktif: false,
          },
        }),
      );
    });

    it('menolak soft delete jika penugasan tidak ditemukan', async () => {
      prismaMock.penugasanPetugas.update.mockRejectedValue(
        buatErrorPrisma('P2025'),
      );

      await expect(service.remove(penugasanId)).rejects.toThrow(
        NotFoundException,
      );
    });
  });
});
