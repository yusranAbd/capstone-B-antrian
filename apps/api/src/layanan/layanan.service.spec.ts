import { ConflictException, NotFoundException } from '@nestjs/common';
import { Test } from '@nestjs/testing';

import {
  ModeReservasi,
  PeranPengguna,
  Prisma,
} from '../generated/prisma/client';

import { PrismaService } from '../prisma/prisma.service';
import { LayananService } from './layanan.service';

// ============================================
// DATA PENGUJIAN
// ============================================

const layananUji = {
  id: 'f0bad26a-9cda-4eae-970d-4236e0524899',
  kode: 'ADM2',
  nama: 'Administrasi Tambahan',
  deskripsi: 'Layanan untuk pengujian.',
  prefixAntrean: 'B',
  durasiDasarMenit: 20,
  aktif: true,
  dibuatPada: new Date('2026-10-08T05:52:33.466Z'),
  diperbaruiPada: new Date('2026-10-08T05:52:33.466Z'),
};

const layananNonaktif = {
  ...layananUji,
  aktif: false,
};

// ============================================
// MOCK PRISMA
// ============================================

const buatPrismaMock = () => ({
  layanan: {
    create: jest.fn(),
    findMany: jest.fn(),
    findFirst: jest.fn(),
    findUnique: jest.fn(),
    update: jest.fn(),
  },
});

// ============================================
// HELPER ERROR PRISMA
// ============================================

function buatErrorPrisma(kode: string): Prisma.PrismaClientKnownRequestError {
  return new Prisma.PrismaClientKnownRequestError('Simulasi kesalahan Prisma', {
    code: kode,
    clientVersion: '7.10.0',
  });
}

// ============================================
// LAYANAN SERVICE TEST
// ============================================

describe('LayananService', () => {
  let service: LayananService;
  let prismaMock: ReturnType<typeof buatPrismaMock>;

  beforeEach(async () => {
    prismaMock = buatPrismaMock();

    const moduleRef = await Test.createTestingModule({
      providers: [
        LayananService,
        {
          provide: PrismaService,
          useValue: prismaMock,
        },
      ],
    }).compile();

    service = moduleRef.get<LayananService>(LayananService);
  });

  // ==========================================
  // 1. CREATE LAYANAN
  // ==========================================

  describe('Create Layanan', () => {
    it('berhasil membuat layanan baru', async () => {
      prismaMock.layanan.create.mockResolvedValue(layananUji);

      const hasil = await service.create({
        kode: 'ADM2',
        nama: 'Administrasi Tambahan',
        deskripsi: 'Layanan untuk pengujian.',
        prefixAntrean: 'B',
        durasiDasarMenit: 20,
      });

      expect(hasil).toEqual(layananUji);

      expect(prismaMock.layanan.create).toHaveBeenCalledWith({
        data: {
          kode: 'ADM2',
          nama: 'Administrasi Tambahan',
          deskripsi: 'Layanan untuk pengujian.',
          prefixAntrean: 'B',
          durasiDasarMenit: 20,
          modeReservasi: ModeReservasi.ANTREAN_HARIAN,
          aktif: true,
        },
      });
    });

    it.each([ModeReservasi.JANJI_TEMU_DOKTER, ModeReservasi.HIBRIDA])(
      'membuat poli dengan mode %s sesuai permintaan ADMIN',
      async (modeReservasi) => {
        prismaMock.layanan.create.mockResolvedValue({
          ...layananUji,
          modeReservasi,
        });
        await service.create({
          kode: 'HOSP',
          nama: 'Poli Hospital',
          prefixAntrean: 'H',
          durasiDasarMenit: 15,
          modeReservasi,
        });
        expect(prismaMock.layanan.create).toHaveBeenCalledWith({
          data: expect.objectContaining({ modeReservasi }),
        });
      },
    );

    it('menolak kode layanan yang sudah digunakan', async () => {
      prismaMock.layanan.create.mockRejectedValue(buatErrorPrisma('P2002'));

      await expect(
        service.create({
          kode: 'ADM2',
          nama: 'Layanan Duplikat',
          prefixAntrean: 'C',
          durasiDasarMenit: 15,
        }),
      ).rejects.toThrow(ConflictException);
    });
  });

  // ==========================================
  // 2. READ ALL LAYANAN
  // ==========================================

  describe('Read All Layanan', () => {
    it('ADMIN dapat melihat layanan aktif dan nonaktif', async () => {
      prismaMock.layanan.findMany.mockResolvedValue([
        layananUji,
        layananNonaktif,
      ]);

      const hasil = await service.findAll(PeranPengguna.ADMIN);

      expect(hasil).toHaveLength(2);

      expect(prismaMock.layanan.findMany).toHaveBeenCalledWith({
        where: undefined,
        orderBy: {
          kode: 'asc',
        },
      });
    });

    it('USER hanya dapat melihat layanan aktif', async () => {
      prismaMock.layanan.findMany.mockResolvedValue([layananUji]);

      const hasil = await service.findAll(PeranPengguna.USER);

      expect(hasil).toHaveLength(1);

      expect(prismaMock.layanan.findMany).toHaveBeenCalledWith({
        where: {
          aktif: true,
        },
        orderBy: {
          kode: 'asc',
        },
      });
    });

    it('PETUGAS hanya dapat melihat layanan aktif', async () => {
      prismaMock.layanan.findMany.mockResolvedValue([layananUji]);

      await service.findAll(PeranPengguna.PETUGAS);

      expect(prismaMock.layanan.findMany).toHaveBeenCalledWith({
        where: {
          aktif: true,
        },
        orderBy: {
          kode: 'asc',
        },
      });
    });
  });

  // ==========================================
  // 3. READ ONE LAYANAN
  // ==========================================

  describe('Read One Layanan', () => {
    it('ADMIN dapat melihat layanan nonaktif', async () => {
      prismaMock.layanan.findFirst.mockResolvedValue(layananNonaktif);

      const hasil = await service.findOne(layananUji.id, PeranPengguna.ADMIN);

      expect(hasil.aktif).toBe(false);

      expect(prismaMock.layanan.findFirst).toHaveBeenCalledWith({
        where: {
          id: layananUji.id,
        },
      });
    });

    it('USER hanya dapat mengambil layanan aktif', async () => {
      prismaMock.layanan.findFirst.mockResolvedValue(layananUji);

      const hasil = await service.findOne(layananUji.id, PeranPengguna.USER);

      expect(hasil).toEqual(layananUji);

      expect(prismaMock.layanan.findFirst).toHaveBeenCalledWith({
        where: {
          id: layananUji.id,
          aktif: true,
        },
      });
    });

    it('menolak layanan yang tidak ditemukan', async () => {
      prismaMock.layanan.findFirst.mockResolvedValue(null);

      await expect(
        service.findOne(layananUji.id, PeranPengguna.USER),
      ).rejects.toThrow(NotFoundException);
    });
  });

  // ==========================================
  // 4. UPDATE LAYANAN
  // ==========================================

  describe('Update Layanan', () => {
    it('berhasil memperbarui data layanan', async () => {
      prismaMock.layanan.findUnique.mockResolvedValue({
        id: layananUji.id,
      });

      const layananDiperbarui = {
        ...layananUji,
        nama: 'Layanan Administrasi Khusus',
        durasiDasarMenit: 25,
      };

      prismaMock.layanan.update.mockResolvedValue(layananDiperbarui);

      const hasil = await service.update(layananUji.id, {
        nama: 'Layanan Administrasi Khusus',
        durasiDasarMenit: 25,
      });

      expect(hasil.nama).toBe('Layanan Administrasi Khusus');

      expect(hasil.durasiDasarMenit).toBe(25);

      expect(prismaMock.layanan.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: {
            id: layananUji.id,
          },
          data: expect.objectContaining({
            nama: 'Layanan Administrasi Khusus',
            durasiDasarMenit: 25,
          }),
        }),
      );
    });

    it('menolak update jika layanan tidak ditemukan', async () => {
      prismaMock.layanan.findUnique.mockResolvedValue(null);

      await expect(
        service.update(layananUji.id, {
          nama: 'Layanan Baru',
        }),
      ).rejects.toThrow(NotFoundException);

      expect(prismaMock.layanan.update).not.toHaveBeenCalled();
    });

    it('menolak perubahan ke kode layanan duplikat', async () => {
      prismaMock.layanan.findUnique.mockResolvedValue({
        id: layananUji.id,
      });

      prismaMock.layanan.update.mockRejectedValue(buatErrorPrisma('P2002'));

      await expect(
        service.update(layananUji.id, {
          kode: 'ADM',
        }),
      ).rejects.toThrow(ConflictException);
    });
  });

  // ==========================================
  // 5. SOFT DELETE
  // ==========================================

  describe('Soft Delete Layanan', () => {
    it('berhasil menonaktifkan layanan tanpa menghapus data', async () => {
      prismaMock.layanan.findUnique.mockResolvedValue({
        id: layananUji.id,
      });

      prismaMock.layanan.update.mockResolvedValue(layananNonaktif);

      const hasil = await service.remove(layananUji.id);

      expect(hasil.aktif).toBe(false);

      expect(prismaMock.layanan.update).toHaveBeenCalledWith({
        where: {
          id: layananUji.id,
        },
        data: {
          aktif: false,
        },
      });
    });

    it('menolak soft delete untuk layanan tidak ditemukan', async () => {
      prismaMock.layanan.findUnique.mockResolvedValue(null);

      await expect(service.remove(layananUji.id)).rejects.toThrow(
        NotFoundException,
      );

      expect(prismaMock.layanan.update).not.toHaveBeenCalled();
    });
  });
});
