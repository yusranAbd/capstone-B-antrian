import { ForbiddenException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { PortalDokterService } from './portal-dokter.service';
describe('PortalDokterService scope', () => {
  const dokter = { findFirst: jest.fn() },
    jadwalPraktik = { findMany: jest.fn(), findFirst: jest.fn() },
    janjiTemu = { findMany: jest.fn() };
  const tx = { jadwalPraktik };
  const prisma = {
    dokter,
    jadwalPraktik,
    janjiTemu,
    $transaction: (fn: (t: typeof tx) => Promise<unknown>) => fn(tx),
  };
  const service = new PortalDokterService(prisma as unknown as PrismaService);
  beforeEach(() => {
    jest.resetAllMocks();
    dokter.findFirst.mockResolvedValue({
      id: 'own-doctor',
      kode: 'DR',
      nama: 'Dokter',
      aktif: true,
      spesialisasi: null,
      dokterLayanan: [],
    });
    jadwalPraktik.findMany.mockResolvedValue([]);
    janjiTemu.findMany.mockResolvedValue([]);
  });
  it('fails closed when profile/account is missing', async () => {
    dokter.findFirst.mockResolvedValue(null);
    await expect(service.profil('account')).rejects.toThrow(ForbiddenException);
    expect(janjiTemu.findMany).not.toHaveBeenCalled();
  });
  it('scopes schedules by account-derived doctor and date', async () => {
    await service.jadwal('account', '2026-10-18');
    expect(dokter.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          penggunaId: 'account',
          aktif: true,
          pengguna: { aktif: true, peran: 'DOKTER' },
        },
      }),
    );
    expect(jadwalPraktik.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          tanggal: new Date('2026-10-18'),
          dokterLayanan: { dokterId: 'own-doctor' },
        },
      }),
    );
  });
  it('scopes appointments through slot and own practice; does not select patient identity', async () => {
    await service.janjiTemu('account', '2026-10-18');
    expect(janjiTemu.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          slotPraktik: {
            jadwalPraktik: { dokterLayanan: { dokterId: 'own-doctor' } },
          },
          tiket: { tanggalAntrean: new Date('2026-10-18') },
        },
      }),
    );
    const call = JSON.stringify(janjiTemu.findMany.mock.calls[0]);
    expect(call).not.toMatch(/penggunaId|tokenQr|email|kataSandi/);
  });
  it('denies snapshot before querying tickets when session is not authorized', async () => {
    jadwalPraktik.findFirst.mockResolvedValue(null);
    await expect(service.snapshot('account', 'foreign')).rejects.toThrow(
      ForbiddenException,
    );
    expect(jadwalPraktik.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          id: 'foreign',
          aktif: true,
          dokterLayanan: expect.objectContaining({ dokterId: 'own-doctor' }),
        }),
      }),
    );
  });
});
