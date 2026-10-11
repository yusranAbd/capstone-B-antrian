import {
  ConflictException,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';

import { PeranPengguna, StatusTiket } from '../generated/prisma/client';
import type { PrismaService } from '../prisma/prisma.service';
import { QueueService } from './queue.service';

// Test khusus RECALL tanpa menyentuh 50 test QueueService yang sudah ada.
// Jalankan dari apps/api: npm run test -- queue.recall.spec.ts

describe('QueueService - RECALL', () => {
  const petugasId = '69bd8820-b911-4ce7-90c8-7107faf7ad11';
  const tiketId = 'baba7817-1751-43aa-965a-5c176cad39ca';
  const layananId = '5102b997-6ef6-47dd-ac1f-5d0f25aa4535';
  const loketId = '4b601c0f-7908-44f0-8ea9-fe1407426488';
  const dipanggilPada = new Date('2026-10-12T02:58:00.000Z');
  const waktuUji = new Date('2026-10-12T03:00:00.000Z');

  let service: QueueService;
  let transaksi: {
    pengguna: { findUnique: jest.Mock };
    tiketAntrean: { findUnique: jest.Mock; updateMany: jest.Mock };
    penugasanPetugas: { findFirst: jest.Mock };
    jadwalLayanan: { findUnique: jest.Mock };
    peristiwaAntrean: { create: jest.Mock };
  };
  let prisma: { $transaction: jest.Mock };

  beforeEach(() => {
    jest.useFakeTimers().setSystemTime(waktuUji);

    transaksi = {
      pengguna: {
        findUnique: jest.fn().mockResolvedValue({
          id: petugasId,
          peran: PeranPengguna.PETUGAS,
          aktif: true,
        }),
      },
      tiketAntrean: {
        findUnique: jest.fn().mockResolvedValue({
          id: tiketId,
          layananId,
          tanggalAntrean: new Date('2026-10-12T00:00:00.000Z'),
          loketId,
          nomorUrut: 1,
          status: StatusTiket.DIPANGGIL,
          versi: 4,
          urutanMasukAntrean: 1,
          dipanggilPada,
          layanan: { aktif: true, prefixAntrean: 'A' },
        }),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      penugasanPetugas: {
        findFirst: jest.fn().mockResolvedValue({
          id: 'penugasan-recall-uji',
          loket: {
            kode: 'LKT-A1',
            aktif: true,
            layananId,
            layanan: { aktif: true },
          },
        }),
      },
      jadwalLayanan: {
        findUnique: jest.fn().mockResolvedValue({ aktif: true }),
      },
      peristiwaAntrean: {
        create: jest.fn().mockResolvedValue({ id: 'audit-recall-uji' }),
      },
    };

    prisma = {
      $transaction: jest.fn(
        async (callback: (tx: typeof transaksi) => Promise<unknown>) =>
          callback(transaksi),
      ),
    };

    service = new QueueService(prisma as unknown as PrismaService);
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('RECALL mempertahankan DIPANGGIL dan mengembalikan nomor yang sama', async () => {
    const hasil = await service.panggilUlang(tiketId, petugasId, loketId);

    expect(hasil).toMatchObject({
      tiketId,
      layananId,
      loketId,
      nomorAntrean: 'A-001',
      status: StatusTiket.DIPANGGIL,
      urutanMasukAntrean: 1,
      dipanggilPada: dipanggilPada.toISOString(),
      dipanggilUlangPada: waktuUji.toISOString(),
      versi: 5,
    });
  });

  it('update bersyarat memakai versi dan tidak mengubah nomor tiket', async () => {
    await service.panggilUlang(tiketId, petugasId, loketId);
    expect(transaksi.tiketAntrean.updateMany).toHaveBeenCalledWith({
      where: expect.objectContaining({
        id: tiketId,
        versi: 4,
        loketId,
        status: StatusTiket.DIPANGGIL,
      }),
      data: {
        status: StatusTiket.DIPANGGIL,
        versi: { increment: 1 },
      },
    });
  });

  it('audit RECALL tercatat dengan status DIPANGGIL sebelum dan sesudah', async () => {
    await service.panggilUlang(tiketId, petugasId, loketId);
    expect(transaksi.peristiwaAntrean.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        tiketAntreanId: tiketId,
        aktorId: petugasId,
        tipe: 'RECALL',
        statusSebelum: StatusTiket.DIPANGGIL,
        statusSesudah: StatusTiket.DIPANGGIL,
      }),
    });
  });

  it('menolak RECALL untuk tiket MENUNGGU', async () => {
    transaksi.tiketAntrean.findUnique.mockResolvedValue({
      status: StatusTiket.MENUNGGU,
    });
    await expect(service.panggilUlang(tiketId, petugasId, loketId))
      .rejects.toThrow(ConflictException);
  });

  it('menolak pemanggilan dari USER', async () => {
    transaksi.pengguna.findUnique.mockResolvedValue({
      id: petugasId,
      peran: PeranPengguna.USER,
      aktif: true,
    });
    await expect(service.panggilUlang(tiketId, petugasId, loketId))
      .rejects.toThrow(ForbiddenException);
  });

  it('menolak RECALL tiket yang tidak ditemukan', async () => {
    transaksi.tiketAntrean.findUnique.mockResolvedValue(null);
    await expect(service.panggilUlang(tiketId, petugasId, loketId))
      .rejects.toThrow(NotFoundException);
  });

  it('menolak perubahan jika versi tiket sudah berubah', async () => {
    transaksi.tiketAntrean.updateMany.mockResolvedValue({ count: 0 });
    await expect(service.panggilUlang(tiketId, petugasId, loketId))
      .rejects.toThrow(ConflictException);
    expect(transaksi.peristiwaAntrean.create).not.toHaveBeenCalled();
  });

  it('meneruskan kegagalan audit agar transaksi asli membatalkan update', async () => {
    transaksi.peristiwaAntrean.create.mockRejectedValue(
      new Error('Audit RECALL gagal'),
    );
    await expect(service.panggilUlang(tiketId, petugasId, loketId))
      .rejects.toThrow('Audit RECALL gagal');
  });
});
