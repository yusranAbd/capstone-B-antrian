import {
  ConflictException,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';

import { PeranPengguna, StatusTiket } from '../generated/prisma/client';
import type { PrismaService } from '../prisma/prisma.service';
import { QueueService } from './queue.service';

// 01G-D.3-D: Unit Test khusus REQUEUE. Tidak mengubah tes modul yang lama.
describe('QueueService - REQUEUE', () => {
  const petugasId = '69bd8820-b911-4ce7-90c8-7107faf7ad11';
  const tiketId = 'baba7817-1751-43aa-965a-5c176cad39ca';
  const layananId = '5102b997-6ef6-47dd-ac1f-5d0f25aa4535';
  const loketId = '4b601c0f-7908-44f0-8ea9-fe1407426488';
  const tanggalDb = new Date('2026-10-12T00:00:00.000Z');
  const dipanggilPada = new Date('2026-10-12T02:58:00.000Z');
  const waktuUji = new Date('2026-10-12T03:00:00.000Z');

  let service: QueueService;
  let transaksi: {
    pengguna: { findUnique: jest.Mock };
    tiketAntrean: { findUnique: jest.Mock; updateMany: jest.Mock };
    penugasanPetugas: { findFirst: jest.Mock };
    jadwalLayanan: { findUnique: jest.Mock };
    urutanAntreanHarian: { findUnique: jest.Mock; update: jest.Mock };
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
          tanggalAntrean: tanggalDb,
          loketId,
          nomorUrut: 1,
          status: StatusTiket.DILEWATI,
          versi: 4,
          urutanMasukAntrean: 1,
          dipanggilPada,
          layanan: { aktif: true, prefixAntrean: 'A' },
        }),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      penugasanPetugas: {
        findFirst: jest.fn().mockResolvedValue({
          id: 'penugasan-requeue-uji',
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
      urutanAntreanHarian: {
        findUnique: jest.fn().mockResolvedValue({ id: 'counter-requeue-uji' }),
        update: jest.fn().mockResolvedValue({ urutanMasukTerakhir: 3 }),
      },
      peristiwaAntrean: {
        create: jest.fn().mockResolvedValue({ id: 'audit-requeue-uji' }),
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

  it('REQUEUE mengembalikan DILEWATI ke MENUNGGU di akhir FIFO dan menjaga nomor tiket', async () => {
    const hasil = await service.antreUlang(tiketId, petugasId, loketId);
    expect(hasil).toMatchObject({
      tiketId,
      layananId,
      nomorAntrean: 'A-001',
      status: StatusTiket.MENUNGGU,
      loketId: null,
      loketSebelumnya: loketId,
      urutanMasukSebelumnya: 1,
      urutanMasukAntrean: 3,
      masukAntreanPada: waktuUji.toISOString(),
      dipanggilPada: null,
      versi: 5,
    });
  });

  it('update atomik memeriksa versi dan mengganti posisi FIFO tanpa mengubah nomor tiket', async () => {
    await service.antreUlang(tiketId, petugasId, loketId);
    expect(transaksi.tiketAntrean.updateMany).toHaveBeenCalledWith({
      where: {
        id: tiketId,
        layananId,
        tanggalAntrean: tanggalDb,
        loketId,
        status: StatusTiket.DILEWATI,
        versi: 4,
        urutanMasukAntrean: 1,
      },
      data: {
        status: StatusTiket.MENUNGGU,
        urutanMasukAntrean: 3,
        masukAntreanPada: waktuUji,
        loketId: null,
        dipanggilPada: null,
        versi: { increment: 1 },
      },
    });
  });

  it('counter harian layanan di-increment secara atomik, tanpa membuat counter baru', async () => {
    await service.antreUlang(tiketId, petugasId, loketId);
    expect(transaksi.urutanAntreanHarian.findUnique).toHaveBeenCalledWith({
      where: { layananId_tanggal: { layananId, tanggal: tanggalDb } },
      select: { id: true },
    });
    expect(transaksi.urutanAntreanHarian.update).toHaveBeenCalledWith({
      where: { layananId_tanggal: { layananId, tanggal: tanggalDb } },
      data: { urutanMasukTerakhir: { increment: 1 } },
      select: { urutanMasukTerakhir: true },
    });
  });

  it('mencatat audit REQUEUE dengan urutan FIFO lama dan baru', async () => {
    await service.antreUlang(tiketId, petugasId, loketId);
    expect(transaksi.peristiwaAntrean.create).toHaveBeenCalledWith({
      data: {
        tiketAntreanId: tiketId,
        aktorId: petugasId,
        tipe: 'REQUEUE',
        statusSebelum: StatusTiket.DILEWATI,
        statusSesudah: StatusTiket.MENUNGGU,
        dataTambahan: {
          metode: 'QUEUE_REQUEUE',
          loketSebelumnya: loketId,
          kodeLoketSebelumnya: 'LKT-A1',
          penugasanId: 'penugasan-requeue-uji',
          urutanMasukSebelumnya: 1,
          urutanMasukSesudah: 3,
        },
      },
    });
    expect(prisma.$transaction).toHaveBeenCalledTimes(1);
  });

  it('menolak REQUEUE jika tiket masih MENUNGGU', async () => {
    transaksi.tiketAntrean.findUnique.mockResolvedValue({ status: StatusTiket.MENUNGGU });
    await expect(service.antreUlang(tiketId, petugasId, loketId)).rejects.toThrow(ConflictException);
    expect(transaksi.urutanAntreanHarian.update).not.toHaveBeenCalled();
  });

  it('menolak REQUEUE untuk tiket yang tidak ditemukan', async () => {
    transaksi.tiketAntrean.findUnique.mockResolvedValue(null);
    await expect(service.antreUlang(tiketId, petugasId, loketId)).rejects.toThrow(NotFoundException);
  });

  it('menolak REQUEUE dari akun USER', async () => {
    transaksi.pengguna.findUnique.mockResolvedValue({ id: petugasId, peran: PeranPengguna.USER, aktif: true });
    await expect(service.antreUlang(tiketId, petugasId, loketId)).rejects.toThrow(ForbiddenException);
  });

  it('menolak REQUEUE dari PETUGAS nonaktif', async () => {
    transaksi.pengguna.findUnique.mockResolvedValue({ id: petugasId, peran: PeranPengguna.PETUGAS, aktif: false });
    await expect(service.antreUlang(tiketId, petugasId, loketId)).rejects.toThrow(ForbiddenException);
  });

  it('menolak REQUEUE untuk tiket dari loket berbeda', async () => {
    await expect(service.antreUlang(tiketId, petugasId, '1d1c0bb3-ae2d-4e01-9078-4311b134ca9a')).rejects.toThrow(ForbiddenException);
  });

  it('menolak REQUEUE jika penugasan petugas tidak aktif', async () => {
    transaksi.penugasanPetugas.findFirst.mockResolvedValue(null);
    await expect(service.antreUlang(tiketId, petugasId, loketId)).rejects.toThrow(ForbiddenException);
  });

  it('menolak REQUEUE jika jadwal layanan tidak aktif', async () => {
    transaksi.jadwalLayanan.findUnique.mockResolvedValue({ aktif: false });
    await expect(service.antreUlang(tiketId, petugasId, loketId)).rejects.toThrow(ConflictException);
  });

  it('menolak REQUEUE bila tiket tidak memiliki waktu CALL sebelumnya atau urutan FIFO', async () => {
    const tiket = await transaksi.tiketAntrean.findUnique();
    transaksi.tiketAntrean.findUnique.mockResolvedValue({ ...tiket, dipanggilPada: null });
    await expect(service.antreUlang(tiketId, petugasId, loketId)).rejects.toThrow(ConflictException);
    transaksi.tiketAntrean.findUnique.mockResolvedValue({ ...tiket, urutanMasukAntrean: null });
    await expect(service.antreUlang(tiketId, petugasId, loketId)).rejects.toThrow(ConflictException);
  });

  it('konflik versi tidak menghasilkan audit REQUEUE', async () => {
    transaksi.tiketAntrean.updateMany.mockResolvedValue({ count: 0 });
    await expect(service.antreUlang(tiketId, petugasId, loketId)).rejects.toThrow(ConflictException);
    expect(transaksi.peristiwaAntrean.create).not.toHaveBeenCalled();
  });

  it('meneruskan kegagalan audit agar transaksi database asli melakukan rollback', async () => {
    transaksi.peristiwaAntrean.create.mockRejectedValue(new Error('Audit REQUEUE gagal'));
    await expect(service.antreUlang(tiketId, petugasId, loketId)).rejects.toThrow('Audit REQUEUE gagal');
    expect(transaksi.tiketAntrean.updateMany).toHaveBeenCalledTimes(1);
  });
});
