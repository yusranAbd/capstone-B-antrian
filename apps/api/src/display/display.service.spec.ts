import { createHash } from 'node:crypto';

import { ForbiddenException, UnauthorizedException } from '@nestjs/common';

import { ModeReservasi, Prisma, StatusTiket } from '../generated/prisma/client';
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
    jadwalPraktik: { findMany: jest.fn().mockResolvedValue([]) },
  };
}

describe('DisplayService - snapshot publik berbasis token perangkat', () => {
  let tx: ReturnType<typeof buatTransaksiMock>;
  let transaction: jest.Mock;
  let service: DisplayService;
  let zonaWaktuAwal: string | undefined;
  let modeNamaAwal: string | undefined;

  beforeAll(() => {
    zonaWaktuAwal = process.env.SERVICE_TIME_ZONE;
    modeNamaAwal = process.env.DISPLAY_PATIENT_NAME_MODE;
    process.env.SERVICE_TIME_ZONE = 'Asia/Jakarta';
    // This suite asserts the masked projection, independently of operator .env.
    process.env.DISPLAY_PATIENT_NAME_MODE = 'SAMAR';
    jest.useFakeTimers().setSystemTime(new Date('2026-10-12T04:00:00.000Z'));
  });

  afterAll(() => {
    jest.useRealTimers();
    if (zonaWaktuAwal === undefined) delete process.env.SERVICE_TIME_ZONE;
    else process.env.SERVICE_TIME_ZONE = zonaWaktuAwal;
    if (modeNamaAwal === undefined)
      delete process.env.DISPLAY_PATIENT_NAME_MODE;
    else process.env.DISPLAY_PATIENT_NAME_MODE = modeNamaAwal;
  });

  beforeEach(() => {
    tx = buatTransaksiMock();
    tx.perangkatTampilan.findUnique.mockResolvedValue({
      aktif: true,
      layananId,
      layanan: { aktif: true },
    });
    tx.layanan.findUniqueOrThrow.mockResolvedValue({
      kode: 'ADM',
      nama: 'Administrasi',
      prefixAntrean: 'A',
      modeReservasi: ModeReservasi.ANTREAN_HARIAN,
    });
    tx.loket.findMany.mockResolvedValue([
      { id: loketId, kode: '01', nama: 'Loket Satu' },
    ]);
    tx.tiketAntrean.findMany.mockImplementation(
      (query: { where: { status: unknown } }) =>
        Promise.resolve(
          query.where.status === StatusTiket.MENUNGGU ||
            query.where.status === StatusTiket.DILEWATI
            ? []
            : [
                {
                  loketId,
                  nomorUrut: 25,
                  status: StatusTiket.DIPANGGIL,
                  dipanggilPada: new Date('2026-10-12T03:55:00.000Z'),
                },
              ],
        ),
    );
    tx.tiketAntrean.count.mockImplementation(
      (q: { where: { status: StatusTiket } }) =>
        Promise.resolve(q.where.status === StatusTiket.MENUNGGU ? 7 : 0),
    );
    tx.peristiwaAntrean.findFirst.mockResolvedValue({
      id: '00000000-0000-4000-8000-000000000003',
      tipe: 'CALL',
      terjadiPada: new Date('2026-10-12T03:55:00.000Z'),
      tiketAntrean: { nomorUrut: 25, loket: { kode: '01' } },
    });
    transaction = jest.fn(
      async (callback: (p: typeof tx) => Promise<unknown>) => callback(tx),
    );
    service = new DisplayService({
      $transaction: transaction,
    } as unknown as PrismaService);
  });

  it('menghasilkan snapshot minimal tanpa data pribadi dan teks TTS', async () => {
    const hasil = await service.snapshot(layananId, token);
    expect(hasil).toMatchObject({
      versiSkema: 1,
      tanggalPelayanan: '2026-10-12',
      layanan: { kode: 'ADM', nama: 'Administrasi' },
      totalMenunggu: 7,
      loket: [
        {
          kode: '01',
          nama: 'Loket Satu',
          tiketAktif: [{ nomorAntrean: 'A-025', status: 'DIPANGGIL' }],
        },
      ],
      pengumumanTerakhir: {
        aksi: 'CALL',
        kodeLoket: '01',
        teks: 'Panggilan nomor antrean A, nol dua lima, silakan menuju ke Administrasi, terima kasih.',
        bahasa: 'id-ID',
      },
    });
    expect(JSON.stringify(hasil)).not.toContain('kataSandiHash');
    expect(JSON.stringify(hasil)).not.toContain('penggunaId');
    expect(JSON.stringify(hasil)).not.toContain(token);
  });

  it('menolak token kosong dan format token salah tanpa membaca database', async () => {
    await expect(service.snapshot(layananId, undefined)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
    await expect(service.snapshot(layananId, 'abc')).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
    expect(transaction).not.toHaveBeenCalled();
  });

  it('menggunakan hash SHA-256 dan tidak mencari token mentah', async () => {
    await service.snapshot(layananId, token);
    expect(tx.perangkatTampilan.findUnique).toHaveBeenCalledWith({
      where: { tokenHash },
      select: {
        id: true,
        sesiBerakhirPada: true,
        aktif: true,
        layananId: true,
        layanan: { select: { aktif: true } },
      },
    });
  });

  it('menolak token yang tidak terdaftar', async () => {
    tx.perangkatTampilan.findUnique.mockResolvedValue(null);
    await expect(service.snapshot(layananId, token)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
    expect(tx.layanan.findUniqueOrThrow).not.toHaveBeenCalled();
  });

  it('menolak perangkat tidak aktif, layanan tidak aktif, dan layanan berbeda', async () => {
    for (const perangkat of [
      { aktif: false, layananId, layanan: { aktif: true } },
      { aktif: true, layananId, layanan: { aktif: false } },
      {
        aktif: true,
        layananId: '00000000-0000-4000-8000-000000000009',
        layanan: { aktif: true },
      },
    ]) {
      tx.perangkatTampilan.findUnique.mockResolvedValueOnce(perangkat);
      await expect(service.snapshot(layananId, token)).rejects.toBeInstanceOf(
        ForbiddenException,
      );
    }
    expect(tx.layanan.findUniqueOrThrow).not.toHaveBeenCalled();
  });

  it('menggunakan satu transaksi RepeatableRead untuk seluruh query', async () => {
    await service.snapshot(layananId, token);
    expect(transaction).toHaveBeenCalledWith(expect.any(Function), {
      isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead,
      timeout: 15_000,
    });
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
    expect(tx.peristiwaAntrean.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          tipe: { in: ['CALL', 'RECALL'] },
          tiketAntrean: {
            is: {
              layananId,
              tanggalAntrean: new Date('2026-10-12T00:00:00.000Z'),
              status: StatusTiket.DIPANGGIL,
              loket: { is: { aktif: true } },
            },
          },
        },
      }),
    );
  });
  it('memproyeksikan nama tersamar, FIFO harian dan hanya select nama pengguna', async () => {
    const waiting = [
      { id: 'w1', nomorUrut: 9, pengguna: { nama: 'Yusran Abdullah' } },
      { id: 'w2', nomorUrut: 1, pengguna: { nama: 'Sindi Rohmawati Setyana' } },
    ];
    tx.tiketAntrean.findMany.mockImplementation(
      (q: { where: { status: unknown } }) =>
        Promise.resolve(q.where.status === StatusTiket.MENUNGGU ? waiting : []),
    );
    const result = await service.snapshot(layananId, token);
    expect(result.modeNama).toBe('SAMAR');
    expect(result.menunggu).toEqual([
      { nomorAntrean: 'A-009', namaPasien: 'Yusran A.' },
      { nomorAntrean: 'A-001', namaPasien: 'Sindi R. S.' },
    ]);
    expect(JSON.stringify(result)).not.toContain('Abdullah');
    const query = tx.tiketAntrean.findMany.mock.calls.find(
      (args) => args[0].where.status === StatusTiket.MENUNGGU,
    )?.[0];
    expect(query.where).toEqual({
      layananId,
      tanggalAntrean: new Date('2026-10-12T00:00:00Z'),
      status: StatusTiket.MENUNGGU,
      urutanMasukAntrean: { not: null },
    });
    expect(query.select.pengguna).toEqual({ select: { nama: true } });
    expect(query.orderBy).toEqual([
      { urutanMasukAntrean: 'asc' },
      { id: 'asc' },
    ]);
  });

  it('daftar HIBRIDA memprioritaskan appointment, REQUEUE memakai timestamp terbaru', async () => {
    tx.layanan.findUniqueOrThrow.mockResolvedValue({
      kode: 'ADM',
      nama: 'Administrasi',
      prefixAntrean: 'A',
      modeReservasi: ModeReservasi.HIBRIDA,
    });
    tx.jadwalPraktik.findMany.mockResolvedValue([{ loketId }]);
    const slot = {
      aktif: true,
      mulaiPada: new Date('2026-10-12T03:00:00Z'),
      selesaiPada: new Date('2026-10-12T03:30:00Z'),
      jadwalPraktik: {
        aktif: true,
        tanggal: new Date('2026-10-12T00:00:00Z'),
        mulaiPada: new Date('2026-10-12T02:00:00Z'),
        selesaiPada: new Date('2026-10-12T05:00:00Z'),
        loketId,
        loket: { aktif: true, layananId },
        dokterLayanan: {
          aktif: true,
          layananId,
          dokter: { aktif: true },
          layanan: { aktif: true },
        },
      },
    };
    const base = {
      layananId,
      tanggalAntrean: new Date('2026-10-12T00:00:00Z'),
      checkInPada: new Date('2026-10-12T02:00:00Z'),
      pengguna: { nama: 'Pasien Contoh' },
    };
    const waiting = [
      {
        ...base,
        id: 'walk',
        nomorUrut: 1,
        urutanMasukAntrean: 1,
        janjiTemu: null,
      },
      {
        ...base,
        id: 'requeue',
        nomorUrut: 2,
        urutanMasukAntrean: 4,
        janjiTemu: { slotPraktik: slot },
        peristiwaAntrean: [{ terjadiPada: new Date('2026-10-12T03:59:00Z') }],
      },
      {
        ...base,
        id: 'appt',
        nomorUrut: 3,
        urutanMasukAntrean: 3,
        janjiTemu: { slotPraktik: slot },
      },
    ];
    tx.tiketAntrean.findMany.mockImplementation(
      (q: { where: { status: unknown } }) =>
        Promise.resolve(q.where.status === StatusTiket.MENUNGGU ? waiting : []),
    );
    const result = await service.snapshot(layananId, token);
    expect(result.menunggu?.map((t) => t.nomorAntrean)).toEqual([
      'A-003',
      'A-002',
      'A-001',
    ]);
  });

  it('menyertakan DILEWATI terpisah dari total dan urutan MENUNGGU', async () => {
    tx.tiketAntrean.findMany.mockImplementation(
      (q: { where: { status: unknown } }) =>
        Promise.resolve(
          q.where.status === StatusTiket.DILEWATI
            ? [{ nomorUrut: 8, pengguna: { nama: 'Pasien Dilewati' } }]
            : [],
        ),
    );
    tx.tiketAntrean.count.mockImplementation(
      (q: { where: { status: StatusTiket } }) =>
        Promise.resolve(q.where.status === StatusTiket.DILEWATI ? 1 : 0),
    );
    const result = await service.snapshot(layananId, token);
    expect(result.totalMenunggu).toBe(0);
    expect(result.totalDilewati).toBe(1);
    expect(result.totalAntrianPasien).toBe(1);
    expect(result.menunggu).toEqual([]);
    expect(result.antrianPasien).toEqual([
      { nomorAntrean: 'A-008', namaPasien: 'Pasien D.', status: 'DILEWATI' },
    ]);
    const query = tx.tiketAntrean.findMany.mock.calls.find(
      (args) => args[0].where.status === StatusTiket.DILEWATI,
    )?.[0];
    expect(query.where).toEqual({
      layananId,
      tanggalAntrean: new Date('2026-10-12T00:00:00Z'),
      status: StatusTiket.DILEWATI,
    });
    expect(query.take).toBe(100);
    expect(query.select).toEqual({
      nomorUrut: true,
      pengguna: { select: { nama: true } },
    });
  });
});
