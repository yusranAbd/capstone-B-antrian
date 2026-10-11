import {
  ConflictException,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';

import { PeranPengguna, Prisma, StatusTiket } from '../generated/prisma/client';
import type { PrismaService } from '../prisma/prisma.service';
import { QueueService } from './queue.service';

// 01G-D.3-E: Pengujian unit START Pelayanan tanpa mengubah tes sebelumnya.
describe('QueueService - START Pelayanan', () => {
  const petugasId = '69bd8820-b911-4ce7-90c8-7107faf7ad11';
  const tiketId = 'baba7817-1751-43aa-965a-5c176cad39ca';
  const layananId = '5102b997-6ef6-47dd-ac1f-5d0f25aa4535';
  const loketId = '4b601c0f-7908-44f0-8ea9-fe1407426488';
  const tanggalDb = new Date('2026-10-12T00:00:00.000Z');
  const dipanggilPada = new Date('2026-10-12T02:58:00.000Z');
  const waktuUji = new Date('2026-10-12T03:00:00.000Z');
  const penugasanId = '00000000-0000-4000-8000-000000000088';

  const tiketAwal = () => ({
    id: tiketId,
    layananId,
    tanggalAntrean: tanggalDb,
    loketId,
    nomorUrut: 1,
    status: StatusTiket.DIPANGGIL,
    versi: 4,
    urutanMasukAntrean: 1,
    dipanggilPada,
    pelayananDimulaiPada: null,
    pelayananSelesaiPada: null,
    layanan: { aktif: true, prefixAntrean: 'A' },
  });

  let service: QueueService;
  let tx: {
    pengguna: { findUnique: jest.Mock };
    tiketAntrean: { findUnique: jest.Mock; updateMany: jest.Mock };
    penugasanPetugas: { findFirst: jest.Mock };
    jadwalLayanan: { findUnique: jest.Mock };
    peristiwaAntrean: { create: jest.Mock };
  };
  let prisma: { $transaction: jest.Mock };
  let zonaWaktuAwal: string | undefined;

  beforeAll(() => {
    zonaWaktuAwal = process.env.SERVICE_TIME_ZONE;
    process.env.SERVICE_TIME_ZONE = 'Asia/Jakarta';
  });

  afterAll(() => {
    if (zonaWaktuAwal === undefined) {
      delete process.env.SERVICE_TIME_ZONE;
    } else {
      process.env.SERVICE_TIME_ZONE = zonaWaktuAwal;
    }
  });

  beforeEach(() => {
    jest.useFakeTimers().setSystemTime(waktuUji);

    tx = {
      pengguna: {
        findUnique: jest.fn().mockResolvedValue({
          id: petugasId,
          peran: PeranPengguna.PETUGAS,
          aktif: true,
        }),
      },
      tiketAntrean: {
        findUnique: jest.fn().mockResolvedValue(tiketAwal()),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      penugasanPetugas: {
        findFirst: jest.fn().mockResolvedValue({
          id: penugasanId,
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
        create: jest.fn().mockResolvedValue({ id: 'audit-start-uji' }),
      },
    };

    prisma = {
      $transaction: jest.fn(
        async (callback: (transaksi: typeof tx) => Promise<unknown>) =>
          callback(tx),
      ),
    };

    service = new QueueService(prisma as unknown as PrismaService);
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('START mengubah DIPANGGIL menjadi DILAYANI dengan waktu mulai pelayanan', async () => {
    const hasil = await service.mulaiPelayanan(tiketId, petugasId, loketId);

    expect(hasil).toEqual({
      tiketId,
      layananId,
      loketId,
      kodeLoket: 'LKT-A1',
      nomorAntrean: 'A-001',
      status: StatusTiket.DILAYANI,
      urutanMasukAntrean: 1,
      dipanggilPada: dipanggilPada.toISOString(),
      pelayananDimulaiPada: waktuUji.toISOString(),
      versi: 5,
    });
  });

  it('memperbarui status, waktu dan versi dengan kondisi atomik', async () => {
    await service.mulaiPelayanan(tiketId, petugasId, loketId);

    expect(tx.tiketAntrean.updateMany).toHaveBeenCalledWith({
      where: {
        id: tiketId,
        layananId,
        loketId,
        tanggalAntrean: tanggalDb,
        status: StatusTiket.DIPANGGIL,
        versi: 4,
        dipanggilPada: { not: null },
        pelayananDimulaiPada: null,
        pelayananSelesaiPada: null,
      },
      data: {
        status: StatusTiket.DILAYANI,
        pelayananDimulaiPada: waktuUji,
        versi: { increment: 1 },
      },
    });
  });

  it('tidak mengubah nomor tiket, loket, urutan FIFO maupun waktu CALL', async () => {
    await service.mulaiPelayanan(tiketId, petugasId, loketId);

    const args = tx.tiketAntrean.updateMany.mock.calls[0]?.[0] as {
      data: Record<string, unknown>;
    };
    for (const field of [
      'nomorUrut',
      'kodeTiket',
      'loketId',
      'urutanMasukAntrean',
      'dipanggilPada',
    ]) {
      expect(args.data).not.toHaveProperty(field);
    }
  });

  it('mencatat audit START_SERVICE dengan status dan konteks lengkap', async () => {
    await service.mulaiPelayanan(tiketId, petugasId, loketId);

    expect(tx.peristiwaAntrean.create).toHaveBeenCalledWith({
      data: {
        tiketAntreanId: tiketId,
        aktorId: petugasId,
        tipe: 'START_SERVICE',
        statusSebelum: StatusTiket.DIPANGGIL,
        statusSesudah: StatusTiket.DILAYANI,
        dataTambahan: {
          metode: 'QUEUE_START_SERVICE',
          loketId,
          kodeLoket: 'LKT-A1',
          penugasanId,
          urutanMasukAntrean: 1,
          dipanggilPada: dipanggilPada.toISOString(),
        },
      },
    });
  });

  it('menggunakan satu transaksi Serializable untuk status dan audit', async () => {
    await service.mulaiPelayanan(tiketId, petugasId, loketId);

    expect(prisma.$transaction).toHaveBeenCalledWith(expect.any(Function), {
      isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
      maxWait: 10000,
      timeout: 15000,
    });
    expect(tx.tiketAntrean.updateMany).toHaveBeenCalledTimes(1);
    expect(tx.peristiwaAntrean.create).toHaveBeenCalledTimes(1);
  });

  it('menolak tiket yang tidak ditemukan', async () => {
    tx.tiketAntrean.findUnique.mockResolvedValue(null);
    await expect(service.mulaiPelayanan(tiketId, petugasId, loketId)).rejects.toThrow(
      NotFoundException,
    );
  });

  it.each([StatusTiket.MENUNGGU, StatusTiket.DILEWATI, StatusTiket.DILAYANI])(
    'menolak START dari tiket berstatus %s',
    async (status) => {
      tx.tiketAntrean.findUnique.mockResolvedValue({
        ...tiketAwal(),
        status,
      });
      await expect(service.mulaiPelayanan(tiketId, petugasId, loketId)).rejects.toThrow(
        ConflictException,
      );
      expect(tx.tiketAntrean.updateMany).not.toHaveBeenCalled();
    },
  );

  it('menolak START ketika loket tiket berbeda dari loket request', async () => {
    await expect(
      service.mulaiPelayanan(tiketId, petugasId, 'ea3d4e29-2182-4481-bb26-3ba53e735aa9'),
    ).rejects.toThrow(ForbiddenException);
  });

  it('menolak tiket tanpa waktu CALL atau urutan FIFO', async () => {
    tx.tiketAntrean.findUnique.mockResolvedValue({ ...tiketAwal(), dipanggilPada: null });
    await expect(service.mulaiPelayanan(tiketId, petugasId, loketId)).rejects.toThrow(
      ConflictException,
    );
    tx.tiketAntrean.findUnique.mockResolvedValue({
      ...tiketAwal(),
      urutanMasukAntrean: null,
    });
    await expect(service.mulaiPelayanan(tiketId, petugasId, loketId)).rejects.toThrow(
      ConflictException,
    );
  });

  it('menolak tiket yang sudah memiliki waktu mulai atau selesai pelayanan', async () => {
    tx.tiketAntrean.findUnique.mockResolvedValue({
      ...tiketAwal(),
      pelayananDimulaiPada: waktuUji,
    });
    await expect(service.mulaiPelayanan(tiketId, petugasId, loketId)).rejects.toThrow(
      ConflictException,
    );
    tx.tiketAntrean.findUnique.mockResolvedValue({
      ...tiketAwal(),
      pelayananSelesaiPada: waktuUji,
    });
    await expect(service.mulaiPelayanan(tiketId, petugasId, loketId)).rejects.toThrow(
      ConflictException,
    );
  });

  it('menolak START dari USER atau PETUGAS nonaktif', async () => {
    tx.pengguna.findUnique.mockResolvedValue({
      id: petugasId,
      peran: PeranPengguna.USER,
      aktif: true,
    });
    await expect(service.mulaiPelayanan(tiketId, petugasId, loketId)).rejects.toThrow(
      ForbiddenException,
    );
    tx.pengguna.findUnique.mockResolvedValue({
      id: petugasId,
      peran: PeranPengguna.PETUGAS,
      aktif: false,
    });
    await expect(service.mulaiPelayanan(tiketId, petugasId, loketId)).rejects.toThrow(
      ForbiddenException,
    );
  });

  it('menolak petugas tanpa penugasan aktif atau loket layanan berbeda', async () => {
    tx.penugasanPetugas.findFirst.mockResolvedValue(null);
    await expect(service.mulaiPelayanan(tiketId, petugasId, loketId)).rejects.toThrow(
      ForbiddenException,
    );
    tx.penugasanPetugas.findFirst.mockResolvedValue({
      id: penugasanId,
      loket: {
        kode: 'LKT-A1',
        aktif: true,
        layananId: '00000000-0000-4000-8000-000000000012',
        layanan: { aktif: true },
      },
    });
    await expect(service.mulaiPelayanan(tiketId, petugasId, loketId)).rejects.toThrow(
      ForbiddenException,
    );
  });

  it('menolak START jika jadwal pelayanan tidak aktif', async () => {
    tx.jadwalLayanan.findUnique.mockResolvedValue({ aktif: false });
    await expect(service.mulaiPelayanan(tiketId, petugasId, loketId)).rejects.toThrow(
      ConflictException,
    );
    expect(tx.tiketAntrean.updateMany).not.toHaveBeenCalled();
  });

  it('menolak tiket dari hari pelayanan berbeda tanpa mengubah data', async () => {
    tx.tiketAntrean.findUnique.mockResolvedValue({
      ...tiketAwal(),
      tanggalAntrean: new Date('2026-10-11T00:00:00.000Z'),
    });
    await expect(service.mulaiPelayanan(tiketId, petugasId, loketId)).rejects.toThrow(
      ConflictException,
    );
    expect(tx.tiketAntrean.updateMany).not.toHaveBeenCalled();
  });

  it('konflik versi menolak START dan tidak membuat audit', async () => {
    tx.tiketAntrean.updateMany.mockResolvedValue({ count: 0 });
    await expect(service.mulaiPelayanan(tiketId, petugasId, loketId)).rejects.toThrow(
      ConflictException,
    );
    expect(tx.peristiwaAntrean.create).not.toHaveBeenCalled();
  });

  it('melakukan retry transaksi untuk konflik serialisasi P2034', async () => {
    prisma.$transaction.mockRejectedValueOnce(
      new Prisma.PrismaClientKnownRequestError('Konflik serialisasi', {
        code: 'P2034',
        clientVersion: '7.10.0',
      }),
    );
    const hasil = await service.mulaiPelayanan(tiketId, petugasId, loketId);
    expect(hasil.status).toBe(StatusTiket.DILAYANI);
    expect(prisma.$transaction).toHaveBeenCalledTimes(2);
  });

  it('menolak setelah tiga konflik serialisasi P2034', async () => {
    const konflik = () =>
      new Prisma.PrismaClientKnownRequestError('Konflik serialisasi', {
        code: 'P2034',
        clientVersion: '7.10.0',
      });
    prisma.$transaction
      .mockRejectedValueOnce(konflik())
      .mockRejectedValueOnce(konflik())
      .mockRejectedValueOnce(konflik());
    await expect(service.mulaiPelayanan(tiketId, petugasId, loketId)).rejects.toThrow(
      ConflictException,
    );
    expect(prisma.$transaction).toHaveBeenCalledTimes(3);
  });

  it('meneruskan error audit untuk rollback oleh transaksi database asli', async () => {
    tx.peristiwaAntrean.create.mockRejectedValue(new Error('Audit START gagal'));
    await expect(service.mulaiPelayanan(tiketId, petugasId, loketId)).rejects.toThrow(
      'Audit START gagal',
    );
    expect(tx.tiketAntrean.updateMany).toHaveBeenCalledTimes(1);
  });
});
