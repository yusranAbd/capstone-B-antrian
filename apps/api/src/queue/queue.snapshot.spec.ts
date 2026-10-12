import { ForbiddenException } from '@nestjs/common';

import {
  PeranPengguna,
  Prisma,
  StatusTiket,
} from '../generated/prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { QueueService } from './queue.service';

const petugasId = '00000000-0000-4000-8000-000000000011';
const loketId = '00000000-0000-4000-8000-000000000022';
const loketKeduaId = '00000000-0000-4000-8000-000000000023';
const layananId = '00000000-0000-4000-8000-000000000033';
const tiketMenungguId = '00000000-0000-4000-8000-000000000044';
const tiketAktifId = '00000000-0000-4000-8000-000000000055';

function buatTx() {
  return {
    pengguna: { findUnique: jest.fn() },
    penugasanPetugas: { findFirst: jest.fn() },
    loket: { findMany: jest.fn() },
    tiketAntrean: { findMany: jest.fn(), count: jest.fn() },
  };
}

describe('QueueService - REST Snapshot', () => {
  let tx: ReturnType<typeof buatTx>;
  let transaksi: jest.Mock;
  let service: QueueService;
  let timezoneAwal: string | undefined;

  beforeAll(() => {
    timezoneAwal = process.env.SERVICE_TIME_ZONE;
    process.env.SERVICE_TIME_ZONE = 'Asia/Jakarta';
    jest.useFakeTimers().setSystemTime(new Date('2026-10-12T04:00:00.000Z'));
  });

  afterAll(() => {
    jest.useRealTimers();
    if (timezoneAwal === undefined) delete process.env.SERVICE_TIME_ZONE;
    else process.env.SERVICE_TIME_ZONE = timezoneAwal;
  });

  beforeEach(() => {
    tx = buatTx();
    tx.pengguna.findUnique.mockResolvedValue({
      id: petugasId,
      aktif: true,
      peran: PeranPengguna.PETUGAS,
    });
    tx.penugasanPetugas.findFirst.mockResolvedValue({
      loket: {
        id: loketId,
        kode: 'L-1',
        nama: 'Loket Satu',
        layananId,
        layanan: {
          id: layananId,
          kode: 'ADM',
          nama: 'Administrasi',
          prefixAntrean: 'A',
        },
      },
    });
    tx.loket.findMany.mockResolvedValue([
      { id: loketId, kode: 'L-1', nama: 'Loket Satu' },
      { id: loketKeduaId, kode: 'L-2', nama: 'Loket Dua' },
    ]);
    tx.tiketAntrean.findMany
      .mockResolvedValueOnce([
        {
          id: tiketMenungguId,
          nomorUrut: 9,
          status: StatusTiket.MENUNGGU,
          versi: 3,
          urutanMasukAntrean: 11,
          masukAntreanPada: new Date('2026-10-12T03:01:00.000Z'),
        },
      ])
      .mockResolvedValueOnce([
        {
          id: tiketAktifId,
          loketId: loketKeduaId,
          nomorUrut: 2,
          status: StatusTiket.DILAYANI,
          versi: 5,
          urutanMasukAntrean: 2,
          dipanggilPada: new Date('2026-10-12T03:00:00.000Z'),
          pelayananDimulaiPada: new Date('2026-10-12T03:05:00.000Z'),
        },
      ]);
    tx.tiketAntrean.count.mockResolvedValue(120);
    transaksi = jest.fn(async (callback: (t: typeof tx) => Promise<unknown>) =>
      callback(tx),
    );
    service = new QueueService(
      { $transaction: transaksi } as unknown as PrismaService,
    );
  });

  it('mengembalikan FIFO, total, dan tiket aktif lintas loket satu layanan', async () => {
    const hasil = await service.snapshotAntrean(petugasId, loketId);
    expect(hasil).toMatchObject({
      versiSkema: 1,
      tanggalPelayanan: '2026-10-12',
      layanan: { id: layananId, kode: 'ADM', nama: 'Administrasi' },
      loketPeminta: { id: loketId, kode: 'L-1' },
      menunggu: {
        total: 120,
        ditampilkan: 1,
        tiket: [
          {
            tiketId: tiketMenungguId,
            nomorAntrean: 'A-009',
            urutanMasukAntrean: 11,
            versi: 3,
          },
        ],
      },
    });
    expect(hasil.loket[0]?.tiketAktif).toEqual([]);
    expect(hasil.loket[1]?.tiketAktif[0]).toMatchObject({
      tiketId: tiketAktifId,
      nomorAntrean: 'A-002',
      status: StatusTiket.DILAYANI,
      versi: 5,
    });
    expect(new Date(hasil.diperolehPada).getTime()).not.toBeNaN();
  });

  it('membatasi daftar FIFO menjadi 100 dan menghitung total secara terpisah', async () => {
    await service.snapshotAntrean(petugasId, loketId);
    const panggilan = tx.tiketAntrean.findMany.mock.calls[0][0] as {
      take: number;
      orderBy: unknown;
    };
    expect(panggilan.take).toBe(100);
    expect(panggilan.orderBy).toEqual([
      { urutanMasukAntrean: 'asc' },
      { id: 'asc' },
    ]);
    expect(tx.tiketAntrean.count).toHaveBeenCalledTimes(1);
  });

  it('membaca tanggal pelayanan lokal, bukan tanggal UTC server', async () => {
    await service.snapshotAntrean(petugasId, loketId);
    expect(tx.tiketAntrean.count).toHaveBeenCalledWith({
      where: {
        layananId,
        tanggalAntrean: new Date('2026-10-12T00:00:00.000Z'),
        status: StatusTiket.MENUNGGU,
        urutanMasukAntrean: { not: null },
      },
    });
  });

  it('menjamin semua query dilakukan dalam satu RepeatableRead transaction', async () => {
    await service.snapshotAntrean(petugasId, loketId);
    expect(transaksi).toHaveBeenCalledWith(expect.any(Function), {
      isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead,
    });
    expect(tx.loket.findMany).toHaveBeenCalledTimes(1);
    expect(tx.tiketAntrean.findMany).toHaveBeenCalledTimes(2);
  });

  it('menolak identitas yang bukan PETUGAS aktif tanpa membaca antrean', async () => {
    tx.pengguna.findUnique.mockResolvedValue({
      id: petugasId,
      aktif: false,
      peran: PeranPengguna.PETUGAS,
    });
    await expect(service.snapshotAntrean(petugasId, loketId)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
    expect(tx.tiketAntrean.findMany).not.toHaveBeenCalled();
  });

  it('menolak ADMIN dan USER pada snapshot petugas', async () => {
    for (const peran of [PeranPengguna.ADMIN, PeranPengguna.USER]) {
      tx.pengguna.findUnique.mockResolvedValue({ id: petugasId, aktif: true, peran });
      await expect(service.snapshotAntrean(petugasId, loketId)).rejects.toBeInstanceOf(
        ForbiddenException,
      );
    }
    expect(tx.tiketAntrean.findMany).not.toHaveBeenCalled();
  });

  it('menolak loket tanpa penugasan aktif dengan filter tanggal dan identitas', async () => {
    tx.penugasanPetugas.findFirst.mockResolvedValue(null);
    await expect(service.snapshotAntrean(petugasId, loketId)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
    expect(tx.penugasanPetugas.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          petugasId,
          loketId,
          aktif: true,
          tanggalMulai: { lte: new Date('2026-10-12T00:00:00.000Z') },
        }),
      }),
    );
    expect(tx.tiketAntrean.findMany).not.toHaveBeenCalled();
  });

  it('tidak membocorkan data pribadi, hash QR, atau detail sesi', async () => {
    const hasil = await service.snapshotAntrean(petugasId, loketId);
    const payload = JSON.stringify(hasil);
    for (const field of ['email', 'kataSandiHash', 'tokenQrHash', 'tokenRefreshHash', 'penggunaId']) {
      expect(payload).not.toContain(field);
    }
  });

  it('meneruskan kegagalan database tanpa mengirim respons snapshot parsial', async () => {
    tx.tiketAntrean.count.mockRejectedValue(new Error('database terputus'));
    await expect(service.snapshotAntrean(petugasId, loketId)).rejects.toThrow(
      'database terputus',
    );
  });
});
