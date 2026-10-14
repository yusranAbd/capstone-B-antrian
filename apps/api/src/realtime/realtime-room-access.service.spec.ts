import { PeranPengguna } from '../generated/prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import {
  RealtimeRoomAccessService,
  type IdentitasSocket,
} from './realtime-room-access.service';

describe('RealtimeRoomAccessService - penugasan dan sesi aktif', () => {
  const layananId = '8d157b00-3412-4a99-b999-e253b4456420';
  const identitas: IdentitasSocket = {
    id: '69bd8820-b911-4ce7-90c8-7107faf7ad11',
    sid: 'sesi-uji',
    peran: PeranPengguna.PETUGAS,
    exp: Math.floor(new Date('2026-10-12T12:00:00Z').getTime() / 1000),
  };
  const sesiFind = jest.fn();
  const layananFind = jest.fn();
  const penugasanFind = jest.fn();
  const prisma = {
    sesiPengguna: { findFirst: sesiFind },
    layanan: { findFirst: layananFind },
    penugasanPetugas: { findFirst: penugasanFind },
  } as unknown as PrismaService;
  const service = new RealtimeRoomAccessService(prisma);
  const zonaAwal = process.env.SERVICE_TIME_ZONE;

  beforeEach(() => {
    process.env.SERVICE_TIME_ZONE = 'Asia/Jakarta';
    jest.useFakeTimers().setSystemTime(new Date('2026-10-12T02:00:00Z'));
    jest.clearAllMocks();
    sesiFind.mockResolvedValue({ id: 'sesi-uji' });
    layananFind.mockResolvedValue({ id: layananId });
    penugasanFind.mockResolvedValue({ id: 'penugasan-uji' });
  });

  afterEach(() => {
    jest.useRealTimers();
    if (zonaAwal === undefined) delete process.env.SERVICE_TIME_ZONE;
    else process.env.SERVICE_TIME_ZONE = zonaAwal;
  });

  it('menerima petugas dengan sesi, layanan, loket, dan penugasan aktif', async () => {
    expect(await service.periksa(identitas, layananId)).toBe('ALLOWED');
    expect(sesiFind).toHaveBeenCalledWith(expect.objectContaining({
      where: expect.objectContaining({
        id: 'sesi-uji',
        dicabutPada: null,
        pengguna: { aktif: true, peran: PeranPengguna.PETUGAS },
      }),
    }));
    expect(penugasanFind).toHaveBeenCalledWith(expect.objectContaining({
      where: expect.objectContaining({
        petugasId: identitas.id,
        aktif: true,
        tanggalMulai: { lte: new Date('2026-10-12T00:00:00.000Z') },
        OR: [{ tanggalSelesai: null }, { tanggalSelesai: { gte: new Date('2026-10-12T00:00:00.000Z') } }],
        loket: { aktif: true, layananId, layanan: { aktif: true } },
      }),
    }));
  });

  it('menolak access token yang sudah habis ketika join', async () => {
    expect(await service.periksa({ ...identitas, exp: 1 }, layananId)).toBe('UNAUTHORIZED');
    expect(sesiFind).not.toHaveBeenCalled();
  });

  it('menolak sesi yang dicabut, berakhir, atau akun dengan peran berubah', async () => {
    sesiFind.mockResolvedValue(null);
    expect(await service.periksa(identitas, layananId)).toBe('UNAUTHORIZED');
    expect(layananFind).not.toHaveBeenCalled();
  });

  it('menolak layanan tidak aktif atau tidak ditemukan', async () => {
    layananFind.mockResolvedValue(null);
    expect(await service.periksa(identitas, layananId)).toBe('FORBIDDEN');
    expect(penugasanFind).not.toHaveBeenCalled();
  });

  it('menolak PETUGAS tanpa penugasan yang sesuai', async () => {
    penugasanFind.mockResolvedValue(null);
    expect(await service.periksa(identitas, layananId)).toBe('FORBIDDEN');
  });

  it('mengizinkan ADMIN pada layanan aktif, tanpa perlu penugasan', async () => {
    expect(await service.periksa({ ...identitas, peran: PeranPengguna.ADMIN }, layananId)).toBe('ALLOWED');
    expect(penugasanFind).not.toHaveBeenCalled();
  });

  it('menolak USER meskipun sesi dan layanan valid', async () => {
    expect(await service.periksa({ ...identitas, peran: PeranPengguna.USER }, layananId)).toBe('FORBIDDEN');
  });

  it('menggunakan tanggal pelayanan Asia/Jakarta, bukan tanggal UTC', async () => {
    // UTC 17:30 adalah tanggal berikutnya pukul 00:30 WIB.
    jest.setSystemTime(new Date('2026-10-11T17:30:00Z'));
    expect(await service.periksa(identitas, layananId)).toBe('ALLOWED');
    const arg = penugasanFind.mock.calls[0][0] as {
      where: { tanggalMulai: { lte: Date } };
    };
    expect(arg.where.tanggalMulai.lte.toISOString()).toBe('2026-10-12T00:00:00.000Z');
  });
  it('timezone Jayapura menghasilkan tanggal room yang sama dengan REST di pergantian hari', async () => {
    process.env.SERVICE_TIME_ZONE = 'Asia/Jayapura';
    jest.setSystemTime(new Date('2026-10-11T15:30:00Z'));
    expect(await service.periksa(identitas, layananId)).toBe('ALLOWED');
    expect(penugasanFind).toHaveBeenCalledWith(expect.objectContaining({
      where: expect.objectContaining({ tanggalMulai: { lte: new Date('2026-10-12T00:00:00Z') } }),
    }));
  });
});
