import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import type { ConfigService } from '@nestjs/config';
import { PeranPengguna } from '../generated/prisma/client';
import type { PrismaService } from '../prisma/prisma.service';
import { JadwalPraktikService } from './jadwal-praktik.service';

const tanggal = '2026-10-19'; // Senin
const mulaiPada = '2026-10-19T08:00:00+07:00';
const selesaiPada = '2026-10-19T09:00:00+07:00';
const dto = { dokterLayananId: 'dokter-layanan-1', loketId: 'ruang-1', tanggal, mulaiPada, selesaiPada };
const existing = {
  id: 'jadwal-1',
  dokterLayananId: dto.dokterLayananId,
  loketId: dto.loketId,
  tanggal: new Date(`${tanggal}T00:00:00.000Z`),
  mulaiPada: new Date(mulaiPada),
  selesaiPada: new Date(selesaiPada),
  aktif: true,
  slotPraktik: [] as { id: string }[],
};

function setup() {
  const tx = {
    $queryRaw: jest.fn().mockResolvedValue([{ ok: 1 }]),
    dokterLayanan: {
      findUnique: jest.fn().mockResolvedValue({
        id: 'dokter-layanan-1',
        dokterId: 'dokter-1',
        layananId: 'poli-1',
        aktif: true,
        dokter: { aktif: true },
        layanan: { aktif: true },
      }),
    },
    loket: {
      findUnique: jest.fn().mockResolvedValue({ id: 'ruang-1', layananId: 'poli-1', aktif: true }),
    },
    jadwalLayanan: {
      findUnique: jest.fn().mockResolvedValue({
        aktif: true,
        jamBuka: new Date('1970-01-01T07:00:00.000Z'),
        jamTutup: new Date('1970-01-01T16:00:00.000Z'),
      }),
    },
    jadwalPraktik: {
      findFirst: jest.fn().mockResolvedValue(null),
      findUnique: jest.fn().mockResolvedValue({ ...existing, slotPraktik: [] }),
      create: jest.fn().mockResolvedValue({ id: 'jadwal-baru', aktif: true }),
      update: jest.fn().mockResolvedValue({ id: 'jadwal-1', aktif: false }),
    },
  };
  const prisma = {
    $transaction: jest.fn().mockImplementation((fn: (arg: typeof tx) => Promise<unknown>) => fn(tx)),
    jadwalPraktik: {
      findMany: jest.fn().mockResolvedValue([]),
      findFirst: jest.fn().mockResolvedValue(null),
    },
  };
  const config = { get: jest.fn().mockReturnValue('Asia/Jakarta') };
  return {
    tx,
    prisma,
    service: new JadwalPraktikService(
      prisma as unknown as PrismaService,
      config as unknown as ConfigService,
    ),
  };
}

describe('JadwalPraktikService H2.2', () => {
  it('membuat jadwal dan mengunci resource dokter serta ruang', async () => {
    const { service, tx } = setup();
    await expect(service.create(dto)).resolves.toEqual({ id: 'jadwal-baru', aktif: true });
    expect(tx.$queryRaw).toHaveBeenCalledTimes(2);
    expect(tx.jadwalPraktik.create).toHaveBeenCalledWith(expect.objectContaining({
      data: expect.objectContaining({ tanggal: new Date('2026-10-19T00:00:00.000Z') }),
    }));
  });

  it('menolak tanggal kalender yang tidak valid', async () => {
    const { service } = setup();
    await expect(service.create({ ...dto, tanggal: '2026-02-30' })).rejects.toBeInstanceOf(BadRequestException);
  });

  it('menolak waktu tanpa offset zona waktu', async () => {
    const { service } = setup();
    await expect(service.create({ ...dto, mulaiPada: '2026-10-19T08:00:00' })).rejects.toBeInstanceOf(BadRequestException);
  });

  it('menolak rentang waktu terbalik', async () => {
    const { service } = setup();
    await expect(service.create({ ...dto, selesaiPada: '2026-10-19T07:00:00+07:00' })).rejects.toBeInstanceOf(BadRequestException);
  });

  it('menolak waktu yang tidak tepat pada menit penuh', async () => {
    const { service } = setup();
    await expect(service.create({ ...dto, mulaiPada: '2026-10-19T08:00:23+07:00' })).rejects.toBeInstanceOf(BadRequestException);
  });

  it('menolak tanggal lokal yang tidak cocok dengan tanggal jadwal', async () => {
    const { service } = setup();
    await expect(service.create({ ...dto, tanggal: '2026-10-20' })).rejects.toBeInstanceOf(BadRequestException);
  });

  it('menolak dokter nonaktif', async () => {
    const { service, tx } = setup();
    tx.dokterLayanan.findUnique.mockResolvedValueOnce({
      dokterId: 'dokter-1', layananId: 'poli-1', aktif: true,
      dokter: { aktif: false }, layanan: { aktif: true },
    });
    await expect(service.create(dto)).rejects.toBeInstanceOf(BadRequestException);
    expect(tx.jadwalPraktik.create).not.toHaveBeenCalled();
  });

  it('menolak relasi dokter-poli tidak tersedia', async () => {
    const { service, tx } = setup();
    tx.dokterLayanan.findUnique.mockResolvedValueOnce(null);
    await expect(service.create(dto)).rejects.toBeInstanceOf(NotFoundException);
  });

  it('menolak ruangan yang tidak aktif atau berada pada poli lain', async () => {
    const { service, tx } = setup();
    tx.loket.findUnique.mockResolvedValueOnce({ id: dto.loketId, aktif: true, layananId: 'poli-lain' });
    await expect(service.create(dto)).rejects.toBeInstanceOf(BadRequestException);
  });

  it('menolak jadwal ketika hari operasional poli tidak ada', async () => {
    const { service, tx } = setup();
    tx.jadwalLayanan.findUnique.mockResolvedValueOnce(null);
    await expect(service.create(dto)).rejects.toBeInstanceOf(BadRequestException);
  });

  it('menolak jadwal di luar jam operasional poli', async () => {
    const { service } = setup();
    await expect(service.create({ ...dto, mulaiPada: '2026-10-19T06:00:00+07:00' })).rejects.toBeInstanceOf(BadRequestException);
  });

  it('menolak benturan dokter atau ruangan', async () => {
    const { service, tx } = setup();
    tx.jadwalPraktik.findFirst.mockResolvedValueOnce({ id: 'jadwal-lain' });
    await expect(service.create(dto)).rejects.toBeInstanceOf(ConflictException);
  });

  it('menggunakan filter read USER untuk seluruh relasi aktif', async () => {
    const { service, prisma } = setup();
    await service.findAll(PeranPengguna.USER, { tanggal, dokterId: 'dokter-1' });
    expect(prisma.jadwalPraktik.findMany).toHaveBeenCalledWith(expect.objectContaining({
      where: expect.objectContaining({ aktif: true, dokterLayanan: expect.any(Object) }),
    }));
  });

  it('ADMIN dapat membaca semua jadwal tanpa filter aktif', async () => {
    const { service, prisma } = setup();
    await service.findAll(PeranPengguna.ADMIN);
    expect(prisma.jadwalPraktik.findMany).toHaveBeenCalledWith(expect.objectContaining({ where: {} }));
  });

  it('mengembalikan 404 ketika detail jadwal tidak terlihat', async () => {
    const { service } = setup();
    await expect(service.findOne('tidak-ada', PeranPengguna.USER)).rejects.toBeInstanceOf(NotFoundException);
  });

  it('menolak PATCH tanpa field', async () => {
    const { service } = setup();
    await expect(service.update('jadwal-1', {})).rejects.toBeInstanceOf(BadRequestException);
  });

  it('PATCH parsial menggabungkan waktu existing dan hanya mengecek konflik di luar dirinya', async () => {
    const { service, tx } = setup();
    await service.update('jadwal-1', { selesaiPada: '2026-10-19T10:00:00+07:00' });
    expect(tx.jadwalPraktik.findFirst).toHaveBeenCalledWith(expect.objectContaining({
      where: expect.objectContaining({ id: { not: 'jadwal-1' } }),
    }));
    expect(tx.jadwalPraktik.update).toHaveBeenCalled();
  });

  it('menolak perubahan jadwal ketika slot sudah dibuat', async () => {
    const { service, tx } = setup();
    tx.jadwalPraktik.findUnique.mockResolvedValueOnce({ ...existing, slotPraktik: [{ id: 'slot-1' }] });
    await expect(service.update('jadwal-1', { mulaiPada: '2026-10-19T09:00:00+07:00' })).rejects.toBeInstanceOf(ConflictException);
  });

  it('DELETE adalah soft delete tanpa menghapus baris', async () => {
    const { service, tx } = setup();
    await service.remove('jadwal-1');
    expect(tx.jadwalPraktik.update).toHaveBeenCalledWith(expect.objectContaining({
      data: { aktif: false },
    }));
  });

  it('tidak boleh menonaktifkan jadwal yang memiliki slot', async () => {
    const { service, tx } = setup();
    tx.jadwalPraktik.findUnique.mockResolvedValueOnce({ ...existing, slotPraktik: [{ id: 'slot-1' }] });
    await expect(service.remove('jadwal-1')).rejects.toBeInstanceOf(ConflictException);
  });
});
