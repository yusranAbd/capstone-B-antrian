import { ForbiddenException } from '@nestjs/common';

import {
  ModeReservasi,
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
    jadwalPraktik: { findFirst: jest.fn().mockResolvedValue({ id: 'sesi-aktif' }) },
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
          modeReservasi: ModeReservasi.ANTREAN_HARIAN,
        },
      },
    });
    tx.loket.findMany.mockResolvedValue([
      { id: loketId, kode: 'L-1', nama: 'Loket Satu' },
      { id: loketKeduaId, kode: 'L-2', nama: 'Loket Dua' },
    ]);
    tx.tiketAntrean.findMany
      .mockResolvedValue([]).mockResolvedValueOnce([
        {
          id: tiketMenungguId,
          nomorUrut: 9,
          status: StatusTiket.MENUNGGU,
          versi: 3,
          urutanMasukAntrean: 11,
          masukAntreanPada: new Date('2026-10-12T03:01:00.000Z'),
        },
      ])
      .mockResolvedValue([]).mockResolvedValueOnce([
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

  it.each(['2026-10-12T05:00:00Z', '2026-10-12T03:45:00Z'])(
    'mode HIBRIDA: snapshot memprioritaskan appointment dengan akhir slot %s', async (akhirSlot) => {
    tx.penugasanPetugas.findFirst.mockResolvedValue({
      loket: {
        id: loketId, kode: 'L-1', nama: 'Loket Satu', layananId,
        layanan: { id: layananId, kode: 'POLI', nama: 'Poli Hibrida',
          prefixAntrean: 'A', modeReservasi: ModeReservasi.HIBRIDA },
      },
    });
    const walk = {
      id: tiketMenungguId, nomorUrut: 9, status: StatusTiket.MENUNGGU,
      versi: 3, urutanMasukAntrean: 1,
      masukAntreanPada: new Date('2026-10-12T02:00:00Z'),
      checkInPada: new Date('2026-10-12T02:00:00Z'),
      tanggalAntrean: new Date('2026-10-12T00:00:00Z'), janjiTemu: null,
      layananId,
    };
    const janji = {
      ...walk, id: '00000000-0000-4000-8000-000000000066', nomorUrut: 10,
      urutanMasukAntrean: 2,
      checkInPada: new Date('2026-10-12T03:30:00Z'),
      janjiTemu: {
        slotPraktik: { aktif: true,
          mulaiPada: new Date('2026-10-12T03:00:00Z'),
          selesaiPada: new Date(akhirSlot),
          jadwalPraktik: { aktif: true, loketId, tanggal: new Date('2026-10-12T00:00:00Z'),
            mulaiPada: new Date('2026-10-12T02:00:00Z'), selesaiPada: new Date('2026-10-12T06:00:00Z'),
            loket: { aktif: true, layananId },
            dokterLayanan: { aktif: true, layananId, layanan: { aktif: true }, dokter: { aktif: true } } },
        },
      },
    };
    tx.tiketAntrean.findMany.mockReset()
      .mockResolvedValue([]).mockResolvedValueOnce([walk, janji])
      .mockResolvedValue([]).mockResolvedValueOnce([]);
    const hasil = await service.snapshotAntrean(petugasId, loketId);
    expect(hasil.menunggu.tiket.map((t) => t.tiketId)).toEqual([janji.id, walk.id]);
    expect(hasil.menunggu.tiket[0]).toMatchObject({
      jenisAntrean: 'JANJI_TEMU', layakDipanggil: true,
    });
    expect(hasil.menunggu.tiket[1]).toMatchObject({
      jenisAntrean: 'WALK_IN', layakDipanggil: true,
    });
    expect(tx.tiketAntrean.findMany.mock.calls[0][0]).not.toHaveProperty('take');
  });

  it('snapshot memakai audit REQUEUE terbaru tanpa membocorkannya dalam respons', async () => {
    tx.penugasanPetugas.findFirst.mockResolvedValue({ loket: {
      id: loketId, kode: 'L-1', nama: 'Loket Satu', layananId,
      layanan: { id: layananId, kode: 'POLI', nama: 'Poli Hibrida',
        prefixAntrean: 'A', modeReservasi: ModeReservasi.HIBRIDA },
    } });
    const ulang = { id: tiketMenungguId, nomorUrut: 9, status: StatusTiket.MENUNGGU,
      versi: 6, urutanMasukAntrean: 9, masukAntreanPada: new Date('2026-10-12T03:50:00Z'),
      checkInPada: new Date('2026-10-12T02:00:00Z'),
      tanggalAntrean: new Date('2026-10-12T00:00:00Z'), janjiTemu: null,
      layananId,
      peristiwaAntrean: [{ terjadiPada: new Date('2026-10-12T03:50:00Z') }] };
    const menunggu = { ...ulang, id: tiketAktifId, nomorUrut: 10, versi: 3,
      urutanMasukAntrean: 2, checkInPada: new Date('2026-10-12T03:30:00Z'), peristiwaAntrean: [] };
    tx.tiketAntrean.findMany.mockReset().mockResolvedValue([]).mockResolvedValueOnce([ulang, menunggu]).mockResolvedValue([]).mockResolvedValueOnce([]);
    const hasil = await service.snapshotAntrean(petugasId, loketId);
    expect(hasil.menunggu.tiket.map((tiket) => tiket.tiketId)).toEqual([menunggu.id, ulang.id]);
    expect(tx.tiketAntrean.findMany).toHaveBeenCalledWith(expect.objectContaining({
      select: expect.objectContaining({ peristiwaAntrean: {
        where: { tipe: 'REQUEUE' }, orderBy: { terjadiPada: 'desc' },
        take: 1, select: { terjadiPada: true },
      } }),
    }));
    expect(JSON.stringify(hasil)).not.toContain('peristiwaAntrean');
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
    const hasil = await service.snapshotAntrean(petugasId, loketId);
    const panggilan = tx.tiketAntrean.findMany.mock.calls[0][0] as {
      take: number;
      orderBy: unknown;
    };
    expect(panggilan.take).toBe(100);
    expect(panggilan.orderBy).toEqual([
      { urutanMasukAntrean: 'asc' },
      { id: 'asc' },
    ]);
    expect(tx.tiketAntrean.count).toHaveBeenCalledTimes(2);
    expect(hasil.menunggu.tiket.every((tiket) => tiket.jenisAntrean === undefined)).toBe(true);
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
    expect(tx.tiketAntrean.findMany).toHaveBeenCalledTimes(4);
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
