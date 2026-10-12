import { createHash } from 'node:crypto';

import { PrismaService } from '../prisma/prisma.service';
import { DisplayRealtimeAccessService } from './display-realtime-access.service';

const layananId = '00000000-0000-4000-8000-000000000001';
const perangkatId = '00000000-0000-4000-8000-000000000002';
const token = 'a'.repeat(64);
const tokenHash = createHash('sha256').update(token).digest('hex');

const perangkatAktif = {
  id: perangkatId, aktif: true, layananId, tokenHash, layanan: { aktif: true },
};

describe('DisplayRealtimeAccessService', () => {
  const findUnique = jest.fn();
  const service = new DisplayRealtimeAccessService({
    perangkatTampilan: { findUnique },
  } as unknown as PrismaService);

  beforeEach(() => {
    jest.clearAllMocks();
    findUnique.mockResolvedValue({ ...perangkatAktif });
  });

  it('menerima token dan layanan yang benar, menyimpan hash bukan token mentah', async () => {
    const hasil = await service.autentikasi(token, layananId);
    expect(hasil).toEqual({ perangkatId, layananId, tokenHash });
    expect(findUnique).toHaveBeenCalledWith(expect.objectContaining({
      where: { tokenHash },
    }));
    expect(JSON.stringify(hasil)).not.toContain(token);
  });

  it.each([undefined, '', 'abc', 'z'.repeat(64), 'a'.repeat(65)])(
    'menolak token salah (%s) sebelum mengakses DB', async (nilai) => {
      await expect(service.autentikasi(nilai, layananId)).rejects.toThrow('UNAUTHORIZED');
      expect(findUnique).not.toHaveBeenCalled();
    },
  );

  it('menolak ID layanan yang tidak valid', async () => {
    await expect(service.autentikasi(token, 'layanan-bebas')).rejects.toThrow('UNAUTHORIZED');
    expect(findUnique).not.toHaveBeenCalled();
  });

  it('menolak token yang tidak terdaftar', async () => {
    findUnique.mockResolvedValueOnce(null);
    await expect(service.autentikasi(token, layananId)).rejects.toThrow('UNAUTHORIZED');
  });

  it.each([
    { ...perangkatAktif, aktif: false },
    { ...perangkatAktif, layanan: { aktif: false } },
    { ...perangkatAktif, layananId: '00000000-0000-4000-8000-000000000009' },
  ])('menolak perangkat atau layanan yang tidak berwenang', async (nilai) => {
    findUnique.mockResolvedValueOnce(nilai);
    await expect(service.autentikasi(token, layananId)).rejects.toThrow('UNAUTHORIZED');
  });

  it('mengizinkan pengiriman jika perangkat masih aktif dan token belum berubah', async () => {
    const identity = await service.autentikasi(token, layananId);
    expect(await service.masihBerwenang(identity)).toBe(true);
    expect(findUnique).toHaveBeenLastCalledWith(expect.objectContaining({ where: { id: perangkatId } }));
  });

  it('mencegah pengiriman setelah perangkat dicabut', async () => {
    findUnique.mockResolvedValueOnce({ ...perangkatAktif, aktif: false });
    expect(await service.masihBerwenang({ perangkatId, layananId, tokenHash })).toBe(false);
  });

  it('mencegah pengiriman setelah token perangkat dirotasi', async () => {
    findUnique.mockResolvedValueOnce({ ...perangkatAktif, tokenHash: 'f'.repeat(64) });
    expect(await service.masihBerwenang({ perangkatId, layananId, tokenHash })).toBe(false);
  });

  it('menolak perangkat hilang saat revalidasi', async () => {
    findUnique.mockResolvedValueOnce(null);
    expect(await service.masihBerwenang({ perangkatId, layananId, tokenHash })).toBe(false);
  });
});
