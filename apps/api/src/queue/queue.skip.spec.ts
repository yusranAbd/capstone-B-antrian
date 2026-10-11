import {
  ConflictException,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';

import { PeranPengguna, StatusTiket } from '../generated/prisma/client';
import type { PrismaService } from '../prisma/prisma.service';
import { QueueService } from './queue.service';

// 01G-D.3-C: Unit Test khusus SKIP, tidak mengubah test CALL/RECALL.
describe('QueueService - SKIP', () => {
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
          id: 'penugasan-skip-uji',
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
        create: jest.fn().mockResolvedValue({ id: 'audit-skip-uji' }),
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

  it('SKIP mengubah DIPANGGIL menjadi DILEWATI dan menjaga nomor tiket', async () => {
    const hasil = await service.lewatiAntrean(tiketId, petugasId, loketId);

    expect(hasil).toMatchObject({
      tiketId,
      layananId,
      loketId,
      kodeLoket: 'LKT-A1',
      nomorAntrean: 'A-001',
      status: StatusTiket.DILEWATI,
      urutanMasukAntrean: 1,
      dipanggilPada: dipanggilPada.toISOString(),
      dilewatiPada: waktuUji.toISOString(),
      versi: 5,
    });
  });

  it('update atomik memeriksa status, versi, loket dan tanggal pelayanan', async () => {
    await service.lewatiAntrean(tiketId, petugasId, loketId);

    expect(transaksi.tiketAntrean.updateMany).toHaveBeenCalledWith({
      where: {
        id: tiketId,
        layananId,
        loketId,
        tanggalAntrean: new Date('2026-10-12T00:00:00.000Z'),
        status: StatusTiket.DIPANGGIL,
        versi: 4,
      },
      data: {
        status: StatusTiket.DILEWATI,
        versi: { increment: 1 },
      },
    });
  });

  it('menyimpan audit SKIP dengan status sebelum, sesudah dan metadata loket', async () => {
    await service.lewatiAntrean(tiketId, petugasId, loketId);

    expect(transaksi.peristiwaAntrean.create).toHaveBeenCalledWith({
      data: {
        tiketAntreanId: tiketId,
        aktorId: petugasId,
        tipe: 'SKIP',
        statusSebelum: StatusTiket.DIPANGGIL,
        statusSesudah: StatusTiket.DILEWATI,
        dataTambahan: {
          metode: 'QUEUE_SKIP',
          loketId,
          kodeLoket: 'LKT-A1',
          penugasanId: 'penugasan-skip-uji',
          urutanMasukAntrean: 1,
        },
      },
    });
    expect(prisma.$transaction).toHaveBeenCalledTimes(1);
  });

  it('menolak SKIP saat tiket masih MENUNGGU', async () => {
    transaksi.tiketAntrean.findUnique.mockResolvedValue({
      status: StatusTiket.MENUNGGU,
    });

    await expect(service.lewatiAntrean(tiketId, petugasId, loketId))
      .rejects.toThrow(ConflictException);
    expect(transaksi.tiketAntrean.updateMany).not.toHaveBeenCalled();
  });

  it('menolak SKIP pada tiket yang tidak ditemukan', async () => {
    transaksi.tiketAntrean.findUnique.mockResolvedValue(null);

    await expect(service.lewatiAntrean(tiketId, petugasId, loketId))
      .rejects.toThrow(NotFoundException);
  });

  it('menolak SKIP oleh pengguna berperan USER', async () => {
    transaksi.pengguna.findUnique.mockResolvedValue({
      id: petugasId,
      peran: PeranPengguna.USER,
      aktif: true,
    });

    await expect(service.lewatiAntrean(tiketId, petugasId, loketId))
      .rejects.toThrow(ForbiddenException);
  });

  it('menolak SKIP oleh PETUGAS nonaktif', async () => {
    transaksi.pengguna.findUnique.mockResolvedValue({
      id: petugasId,
      peran: PeranPengguna.PETUGAS,
      aktif: false,
    });

    await expect(service.lewatiAntrean(tiketId, petugasId, loketId))
      .rejects.toThrow(ForbiddenException);
  });

  it('menolak SKIP bila tiket bukan milik loket yang diminta', async () => {
    await expect(
      service.lewatiAntrean(tiketId, petugasId, '1d1c0bb3-ae2d-4e01-9078-4311b134ca9a'),
    ).rejects.toThrow(ForbiddenException);
    expect(transaksi.tiketAntrean.updateMany).not.toHaveBeenCalled();
  });

  it('menolak SKIP jika tidak ada penugasan petugas aktif', async () => {
    transaksi.penugasanPetugas.findFirst.mockResolvedValue(null);

    await expect(service.lewatiAntrean(tiketId, petugasId, loketId))
      .rejects.toThrow(ForbiddenException);
    expect(transaksi.tiketAntrean.updateMany).not.toHaveBeenCalled();
  });

  it('menolak SKIP jika jadwal layanan tidak aktif', async () => {
    transaksi.jadwalLayanan.findUnique.mockResolvedValue({ aktif: false });

    await expect(service.lewatiAntrean(tiketId, petugasId, loketId))
      .rejects.toThrow(ConflictException);
    expect(transaksi.tiketAntrean.updateMany).not.toHaveBeenCalled();
  });

  it('menolak SKIP jika tanggal tiket bukan hari pelayanan', async () => {
    const tiket = await transaksi.tiketAntrean.findUnique();
    transaksi.tiketAntrean.findUnique.mockResolvedValue({
      ...tiket,
      tanggalAntrean: new Date('2026-10-13T00:00:00.000Z'),
    });

    await expect(service.lewatiAntrean(tiketId, petugasId, loketId))
      .rejects.toThrow(ConflictException);
  });

  it('menolak SKIP bila tiket tidak memiliki waktu CALL pertama', async () => {
    const tiket = await transaksi.tiketAntrean.findUnique();
    transaksi.tiketAntrean.findUnique.mockResolvedValue({
      ...tiket,
      dipanggilPada: null,
    });

    await expect(service.lewatiAntrean(tiketId, petugasId, loketId))
      .rejects.toThrow(ConflictException);
  });

  it('konflik versi tidak menghasilkan catatan audit SKIP', async () => {
    transaksi.tiketAntrean.updateMany.mockResolvedValue({ count: 0 });

    await expect(service.lewatiAntrean(tiketId, petugasId, loketId))
      .rejects.toThrow(ConflictException);
    expect(transaksi.peristiwaAntrean.create).not.toHaveBeenCalled();
  });

  it('meneruskan kegagalan audit untuk rollback pada transaksi database asli', async () => {
    transaksi.peristiwaAntrean.create.mockRejectedValue(
      new Error('Audit SKIP gagal'),
    );

    await expect(service.lewatiAntrean(tiketId, petugasId, loketId))
      .rejects.toThrow('Audit SKIP gagal');
    expect(transaksi.tiketAntrean.updateMany).toHaveBeenCalledTimes(1);
  });
});
