import { createHash } from 'node:crypto';

import { ForbiddenException, UnauthorizedException } from '@nestjs/common';

import { Prisma, StatusTiket } from '../generated/prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { DisplayService } from './display.service';

const layananId = '00000000-0000-4000-8000-000000000001';
const loketId = '00000000-0000-4000-8000-000000000002';
const token = 'a'.repeat(64);
const tokenHash = createHash('sha256').update(token).digest('hex');

function buatTransaksiMock() {
  return {
    perangkatTampilan: { findUnique: jest.fn() },
    layanan: { findUniqueOrThrow: jest.fn() },
    loket: { findMany: jest.fn() },
    tiketAntrean: { findMany: jest.fn(), count: jest.fn() },
    peristiwaAntrean: { findFirst: jest.fn() },
  };
}

describe('DisplayService - snapshot publik berbasis token perangkat', () => {
  let tx: ReturnType<typeof buatTransaksiMock>;
  let transaction: jest.Mock;
  let service: DisplayService;
  let zonaWaktuAwal: string | undefined;

  beforeAll(() => {
    zonaWaktuAwal = process.env.SERVICE_TIME_ZONE;
    process.env.SERVICE_TIME_ZONE = 'Asia/Jakarta';
    jest.useFakeTimers().setSystemTime(new Date('2026-10-12T04:00:00.000Z'));
  });

  afterAll(() => {
    jest.useRealTimers();
    if (zonaWaktuAwal === undefined) delete process.env.SERVICE_TIME_ZONE;
    else process.env.SERVICE_TIME_ZONE = zonaWaktuAwal;
  });

  beforeEach(() => {
    tx = buatTransaksiMock();
    tx.perangkatTampilan.findUnique.mockResolvedValue({
      aktif: true,
      layananId,
      layanan: { aktif: true },
    });
    tx.layanan.findUniqueOrThrow.mockResolvedValue({
      kode: 'ADM', nama: 'Administrasi', prefixAntrean: 'A',
    });
    tx.loket.findMany.mockResolvedValue([
      { id: loketId, kode: '01', nama: 'Loket Satu' },
    ]);
    tx.tiketAntrean.findMany.mockResolvedValue([
      {
        loketId,
        nomorUrut: 25,
        status: StatusTiket.DIPANGGIL,
        dipanggilPada: new Date('2026-10-12T03:55:00.000Z'),
      },
    ]);
    tx.tiketAntrean.count.mockResolvedValue(7);
    tx.peristiwaAntrean.findFirst.mockResolvedValue({
      id: '00000000-0000-4000-8000-000000000003',
      tipe: 'CALL',
      terjadiPada: new Date('2026-10-12T03:55:00.000Z'),
      tiketAntrean: { nomorUrut: 25, loket: { kode: '01' } },
    });
    transaction = jest.fn(async (callback: (p: typeof tx) => Promise<unknown>) => callback(tx));
    service = new DisplayService({ $transaction: transaction } as unknown as PrismaService);
  });

  it('menghasilkan snapshot minimal tanpa data pribadi dan teks TTS', async () => {
    const hasil = await service.snapshot(layananId, token);
    expect(hasil).toMatchObject({
      versiSkema: 1,
      tanggalPelayanan: '2026-10-12',
      layanan: { kode: 'ADM', nama: 'Administrasi' },
      totalMenunggu: 7,
      loket: [{
        kode: '01',
        nama: 'Loket Satu',
        tiketAktif: [{ nomorAntrean: 'A-025', status: 'DIPANGGIL' }],
      }],
      pengumumanTerakhir: {
        aksi: 'CALL',
        kodeLoket: '01',
        teks: 'Nomor antrean A-025, silakan menuju loket 01.',
        bahasa: 'id-ID',
      },
    });
    expect(JSON.stringify(hasil)).not.toContain('kataSandiHash');
    expect(JSON.stringify(hasil)).not.toContain('penggunaId');
    expect(JSON.stringify(hasil)).not.toContain(token);
  });

  it('menolak token kosong dan format token salah tanpa membaca database', async () => {
    await expect(service.snapshot(layananId, undefined)).rejects.toBeInstanceOf(UnauthorizedException);
    await expect(service.snapshot(layananId, 'abc')).rejects.toBeInstanceOf(UnauthorizedException);
    expect(transaction).not.toHaveBeenCalled();
  });

  it('menggunakan hash SHA-256 dan tidak mencari token mentah', async () => {
    await service.snapshot(layananId, token);
    expect(tx.perangkatTampilan.findUnique).toHaveBeenCalledWith({
      where: { tokenHash },
      select: { aktif: true, layananId: true, layanan: { select: { aktif: true } } },
    });
  });

  it('menolak token yang tidak terdaftar', async () => {
    tx.perangkatTampilan.findUnique.mockResolvedValue(null);
    await expect(service.snapshot(layananId, token)).rejects.toBeInstanceOf(UnauthorizedException);
    expect(tx.layanan.findUniqueOrThrow).not.toHaveBeenCalled();
  });

  it('menolak perangkat tidak aktif, layanan tidak aktif, dan layanan berbeda', async () => {
    for (const perangkat of [
      { aktif: false, layananId, layanan: { aktif: true } },
      { aktif: true, layananId, layanan: { aktif: false } },
      { aktif: true, layananId: '00000000-0000-4000-8000-000000000009', layanan: { aktif: true } },
    ]) {
      tx.perangkatTampilan.findUnique.mockResolvedValueOnce(perangkat);
      await expect(service.snapshot(layananId, token)).rejects.toBeInstanceOf(ForbiddenException);
    }
    expect(tx.layanan.findUniqueOrThrow).not.toHaveBeenCalled();
  });

  it('menggunakan satu transaksi RepeatableRead untuk seluruh query', async () => {
    await service.snapshot(layananId, token);
    expect(transaction).toHaveBeenCalledWith(
      expect.any(Function),
      { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead },
    );
  });

  it('membedakan RECALL dari CALL menggunakan ID audit yang baru', async () => {
    tx.peristiwaAntrean.findFirst.mockResolvedValue({
      id: '00000000-0000-4000-8000-000000000004',
      tipe: 'RECALL',
      terjadiPada: new Date('2026-10-12T03:59:00.000Z'),
      tiketAntrean: { nomorUrut: 25, loket: { kode: '01' } },
    });
    const hasil = await service.snapshot(layananId, token);
    expect(hasil.pengumumanTerakhir).toMatchObject({
      peristiwaId: '00000000-0000-4000-8000-000000000004',
      aksi: 'RECALL',
      nomorAntrean: 'A-025',
    });
  });

  it('mengembalikan pengumuman null ketika tidak ada tiket sedang DIPANGGIL', async () => {
    tx.peristiwaAntrean.findFirst.mockResolvedValue(null);
    const hasil = await service.snapshot(layananId, token);
    expect(hasil.pengumumanTerakhir).toBeNull();
  });

  it('membatasi pemanggilan dari audit pada layanan, tanggal, dan tiket DIPANGGIL', async () => {
    await service.snapshot(layananId, token);
    expect(tx.peristiwaAntrean.findFirst).toHaveBeenCalledWith(expect.objectContaining({
      where: {
        tipe: { in: ['CALL', 'RECALL'] },
        tiketAntrean: { is: {
          layananId,
          tanggalAntrean: new Date('2026-10-12T00:00:00.000Z'),
          status: StatusTiket.DIPANGGIL,
          loket: { is: { aktif: true } },
        } },
      },
    }));
  });
});
