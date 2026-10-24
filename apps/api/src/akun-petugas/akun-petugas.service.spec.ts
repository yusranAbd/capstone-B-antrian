import { ConflictException, NotFoundException } from '@nestjs/common';
import { PasswordService } from '../auth/password.service';
import { Prisma, PeranPengguna } from '../generated/prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { AkunPetugasService } from './akun-petugas.service';

describe('AkunPetugasService', () => {
  const account = {
    id: '11111111-1111-4111-8111-111111111111',
    nama: 'Petugas',
    email: 'staff@example.test',
    peran: PeranPengguna.PETUGAS,
    aktif: true,
  };
  const actor = '22222222-2222-4222-8222-222222222222';
  let service: AkunPetugasService;
  const tx = {
    $queryRaw: jest.fn(),
    pengguna: { findUnique: jest.fn(), update: jest.fn() },
    sesiPengguna: { updateMany: jest.fn() },
  };
  const prisma = {
    pengguna: { findMany: jest.fn(), create: jest.fn() },
    $transaction: jest.fn(),
  };
  const password = { hash: jest.fn() };
  beforeEach(() => {
    jest.clearAllMocks();
    prisma.$transaction.mockImplementation(
      (callback: (client: typeof tx) => unknown) => callback(tx),
    );
    tx.pengguna.findUnique.mockResolvedValue(account);
    tx.pengguna.update.mockResolvedValue(account);
    prisma.pengguna.create.mockResolvedValue(account);
    password.hash.mockResolvedValue('hash');
    service = new AkunPetugasService(
      prisma as unknown as PrismaService,
      password as unknown as PasswordService,
    );
  });
  it('lists only PETUGAS with safe selected fields', async () => {
    await service.list();
    const args = prisma.pengguna.findMany.mock.calls[0][0];
    expect(args.where).toEqual({ peran: 'PETUGAS' });
    expect(Object.keys(args.select).sort()).toEqual([
      'aktif',
      'email',
      'id',
      'nama',
      'peran',
    ]);
  });
  it('normalizes identity and fixes role server-side with existing password hashing', async () => {
    await service.create(
      {
        nama: ' Petugas ',
        email: 'STAFF@EXAMPLE.TEST',
        kataSandi: 'password123',
      },
      actor,
    );
    expect(password.hash).toHaveBeenCalledWith('password123');
    expect(prisma.pengguna.create.mock.calls[0][0].data).toEqual({
      nama: 'Petugas',
      email: 'staff@example.test',
      kataSandiHash: 'hash',
      aktif: true,
      peran: 'PETUGAS',
    });
  });
  it('maps unique email conflicts', async () => {
    prisma.pengguna.create.mockRejectedValue(
      new Prisma.PrismaClientKnownRequestError('duplicate', {
        code: 'P2002',
        clientVersion: '7.10.0',
      }),
    );
    await expect(
      service.create(
        { nama: 'Petugas', email: account.email, kataSandi: 'password123' },
        actor,
      ),
    ).rejects.toThrow(ConflictException);
  });
  it('disables and revokes sessions in the same transaction, without changing assignments', async () => {
    await service.status(account.id, false, actor);
    expect(tx.$queryRaw).toHaveBeenCalled();
    expect(tx.pengguna.update.mock.calls[0][0].data).toEqual({ aktif: false });
    expect(tx.sesiPengguna.updateMany).toHaveBeenCalledWith({
      where: { penggunaId: account.id, dicabutPada: null },
      data: { dicabutPada: expect.any(Date) },
    });
  });
  it('reactivation never revives old sessions', async () => {
    await service.status(account.id, true, actor);
    expect(tx.sesiPengguna.updateMany).not.toHaveBeenCalled();
  });
  it('does not mutate missing accounts or another role', async () => {
    for (const candidate of [null, { ...account, peran: 'ADMIN' }]) {
      tx.pengguna.findUnique.mockResolvedValue(candidate);
      await expect(service.status(account.id, false, actor)).rejects.toThrow(
        NotFoundException,
      );
    }
    expect(tx.pengguna.update).not.toHaveBeenCalled();
  });
});
