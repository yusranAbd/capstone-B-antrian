import { BadRequestException, ConflictException } from '@nestjs/common';
import { ProfileService } from './profile.service';
import type { PrismaService } from '../../prisma/prisma.service';
import type { PasswordService } from '../password.service';

describe('ProfileService', () => {
  function setup() {
    const tx = {
      $executeRaw: jest.fn(),
      $queryRaw: jest.fn(),
      pengguna: { updateMany: jest.fn().mockResolvedValue({ count: 1 }) },
      sesiPengguna: { updateMany: jest.fn() },
    };
    const prisma = {
      pengguna: {
        findUnique: jest
          .fn()
          .mockResolvedValue({ aktif: true, kataSandiHash: 'old' }),
      },
      $transaction: jest.fn((fn: (value: typeof tx) => unknown) => fn(tx)),
    };
    const passwords = {
      verify: jest
        .fn()
        .mockImplementation((p: string) =>
          Promise.resolve(p === 'old-password'),
        ),
      hash: jest.fn().mockResolvedValue('new-hash'),
    };
    return {
      service: new ProfileService(
        prisma as unknown as PrismaService,
        passwords as unknown as PasswordService,
      ),
      tx,
      prisma,
      passwords,
    };
  }
  it('password salah tidak mengubah database', async () => {
    const { service, prisma } = setup();
    await expect(
      service.changePassword('self', {
        kataSandiLama: 'wrong',
        kataSandiBaru: 'new-password',
      }),
    ).rejects.toThrow(BadRequestException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });
  it('password sama ditolak', async () => {
    const { service } = setup();
    await expect(
      service.changePassword('self', {
        kataSandiLama: 'old-password',
        kataSandiBaru: 'old-password',
      }),
    ).rejects.toThrow(BadRequestException);
  });
  it('hash baru dan pencabutan seluruh sesi dilakukan dalam satu transaksi', async () => {
    const { service, tx } = setup();
    await expect(
      service.changePassword('self', {
        kataSandiLama: 'old-password',
        kataSandiBaru: 'new-password',
      }),
    ).resolves.toMatchObject({ loginUlang: true });
    expect(tx.pengguna.updateMany).toHaveBeenCalledWith({
      where: { id: 'self', aktif: true, kataSandiHash: 'old' },
      data: { kataSandiHash: 'new-hash' },
    });
    expect(tx.sesiPengguna.updateMany).toHaveBeenCalledWith({
      where: { penggunaId: 'self', dicabutPada: null },
      data: { dicabutPada: expect.any(Date) },
    });
  });
  it('CAS gagal tidak mencabut sesi milik perubahan yang menang', async () => {
    const { service, tx } = setup();
    tx.pengguna.updateMany.mockResolvedValue({ count: 0 });
    await expect(
      service.changePassword('self', {
        kataSandiLama: 'old-password',
        kataSandiBaru: 'new-password',
      }),
    ).rejects.toThrow(ConflictException);
    expect(tx.sesiPengguna.updateMany).not.toHaveBeenCalled();
  });
});
