import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { PeranPengguna } from '../generated/prisma/client';
import type { PrismaService } from '../prisma/prisma.service';
import { SlotPraktikService } from './slot-praktik.service';

const awal = '2035-10-15T08:00:00+07:00';
const akhir = '2035-10-15T08:30:00+07:00';
const dto = { jadwalPraktikId: 'jadwal-1', mulaiPada: awal, selesaiPada: akhir, kapasitas: 2 };
const parent = {
  id: 'jadwal-1', aktif: true,
  mulaiPada: new Date('2035-10-15T07:00:00+07:00'),
  selesaiPada: new Date('2035-10-15T11:00:00+07:00'),
  dokterLayanan: { aktif: true, dokter: { aktif: true }, layanan: { aktif: true } },
  loket: { aktif: true },
};
const slot = {
  id: 'slot-1', jadwalPraktikId: 'jadwal-1',
  mulaiPada: new Date(awal), selesaiPada: new Date(akhir),
  kapasitas: 2, aktif: true, jadwalPraktik: parent,
  _count: { janjiTemu: 0 },
};

function setup() {
  const tx = {
    $queryRaw: jest.fn().mockResolvedValue([{ ok: 1 }]),
    jadwalPraktik: { findUnique: jest.fn().mockResolvedValue(parent) },
    slotPraktik: {
      findFirst: jest.fn().mockResolvedValue(null),
      findUnique: jest.fn().mockResolvedValue(slot),
      create: jest.fn().mockResolvedValue(slot),
      update: jest.fn().mockResolvedValue(slot),
    },
  };
  const prisma = {
    $transaction: jest.fn().mockImplementation((fn: (arg: typeof tx) => Promise<unknown>) => fn(tx)),
    slotPraktik: {
      findMany: jest.fn().mockResolvedValue([slot]),
      findFirst: jest.fn().mockResolvedValue(slot),
      findUnique: jest.fn().mockResolvedValue({ jadwalPraktikId: 'jadwal-1' }),
    },
  };
  const service = new SlotPraktikService(prisma as unknown as PrismaService);
  return { tx, prisma, service };
}

describe('SlotPraktikService H2.3', () => {
  it('membuat slot dan mengunci jadwal sebelum pemeriksaan benturan', async () => {
    const { service, tx } = setup();
    await expect(service.create(dto)).resolves.toMatchObject({ id: 'slot-1', sisaKapasitas: 2, tersedia: true });
    expect(tx.$queryRaw).toHaveBeenCalledTimes(1);
    expect(tx.slotPraktik.create).toHaveBeenCalledWith(expect.objectContaining({
      data: expect.objectContaining({ jadwalPraktikId: dto.jadwalPraktikId, kapasitas: 2 }),
    }));
  });

  it('menolak waktu tanpa offset', async () => {
    const { service } = setup();
    await expect(service.create({ ...dto, mulaiPada: '2035-10-15T08:00:00' })).rejects.toBeInstanceOf(BadRequestException);
  });

  it('menolak rentang terbalik', async () => {
    const { service } = setup();
    await expect(service.create({ ...dto, selesaiPada: '2035-10-15T07:00:00+07:00' })).rejects.toBeInstanceOf(BadRequestException);
  });

  it('menolak waktu yang tidak tepat menit penuh', async () => {
    const { service } = setup();
    await expect(service.create({ ...dto, mulaiPada: '2035-10-15T08:00:05+07:00' })).rejects.toBeInstanceOf(BadRequestException);
  });

  it('menolak kapasitas nol', async () => {
    const { service } = setup();
    await expect(service.create({ ...dto, kapasitas: 0 })).rejects.toBeInstanceOf(BadRequestException);
  });

  it('menolak waktu di luar sesi praktik', async () => {
    const { service } = setup();
    await expect(service.create({ ...dto, mulaiPada: '2035-10-15T06:45:00+07:00' })).rejects.toBeInstanceOf(BadRequestException);
  });

  it('menolak jadwal yang tidak ada', async () => {
    const { service, tx } = setup();
    tx.jadwalPraktik.findUnique.mockResolvedValueOnce(null);
    await expect(service.create(dto)).rejects.toBeInstanceOf(NotFoundException);
  });

  it('menolak dokter atau sesi nonaktif', async () => {
    const { service, tx } = setup();
    tx.jadwalPraktik.findUnique.mockResolvedValueOnce({ ...parent, dokterLayanan: { ...parent.dokterLayanan, dokter: { aktif: false } } });
    await expect(service.create(dto)).rejects.toBeInstanceOf(BadRequestException);
  });

  it('menolak overlap dengan slot aktif', async () => {
    const { service, tx } = setup();
    tx.slotPraktik.findFirst.mockResolvedValueOnce({ id: 'slot-lain' });
    await expect(service.create(dto)).rejects.toBeInstanceOf(ConflictException);
  });

  it('menerima waktu berbatasan tanpa overlap', async () => {
    const { service, tx } = setup();
    await service.create({ ...dto, mulaiPada: akhir, selesaiPada: '2035-10-15T09:00:00+07:00' });
    expect(tx.slotPraktik.findFirst).toHaveBeenCalledWith(expect.objectContaining({
      where: expect.objectContaining({ mulaiPada: { lt: new Date('2035-10-15T09:00:00+07:00') }, selesaiPada: { gt: new Date(akhir) } }),
    }));
  });

  it('daftar USER dibatasi oleh relasi aktif', async () => {
    const { service, prisma } = setup();
    const daftar = await service.findAll(PeranPengguna.USER, { jadwalPraktikId: 'jadwal-1' });
    expect(daftar).toHaveLength(1);
    expect(prisma.slotPraktik.findMany).toHaveBeenCalledWith(expect.objectContaining({
      where: expect.objectContaining({ aktif: true, jadwalPraktik: expect.anything() }),
    }));
  });

  it('ADMIN dapat membaca slot nonaktif', async () => {
    const { service, prisma } = setup();
    await service.findAll(PeranPengguna.ADMIN, { jadwalPraktikId: 'jadwal-1' });
    expect(prisma.slotPraktik.findMany).toHaveBeenCalledWith(expect.objectContaining({
      where: { jadwalPraktikId: 'jadwal-1' },
    }));
  });

  it('detail slot yang tidak terlihat menghasilkan 404', async () => {
    const { service, prisma } = setup();
    prisma.slotPraktik.findFirst.mockResolvedValueOnce(null);
    await expect(service.findOne('slot-lain', PeranPengguna.USER)).rejects.toBeInstanceOf(NotFoundException);
  });

  it('menghitung janji dan sisa kapasitas tanpa membuka data pasien', async () => {
    const { service, prisma } = setup();
    prisma.slotPraktik.findMany.mockResolvedValueOnce([{ ...slot, _count: { janjiTemu: 2 } }]);
    const hasil = await service.findAll(PeranPengguna.ADMIN, { jadwalPraktikId: 'jadwal-1' });
    expect(hasil[0]).toMatchObject({ jumlahJanjiTemu: 2, sisaKapasitas: 0, tersedia: false });
    expect(hasil[0]).not.toHaveProperty('_count');
  });

  it('menolak PATCH kosong', async () => {
    const { service } = setup();
    await expect(service.update('slot-1', {})).rejects.toBeInstanceOf(BadRequestException);
  });

  it('menolak PATCH slot yang tidak ditemukan', async () => {
    const { service, prisma } = setup();
    prisma.slotPraktik.findUnique.mockResolvedValueOnce(null);
    await expect(service.update('tidak-ada', { kapasitas: 3 })).rejects.toBeInstanceOf(NotFoundException);
  });

  it('tidak boleh menggeser waktu slot yang sudah memiliki janji', async () => {
    const { service, tx } = setup();
    tx.slotPraktik.findUnique.mockResolvedValueOnce({ ...slot, _count: { janjiTemu: 1 } });
    await expect(service.update('slot-1', { mulaiPada: akhir })).rejects.toBeInstanceOf(ConflictException);
  });

  it('tidak boleh menurunkan kapasitas di bawah jumlah janji', async () => {
    const { service, tx } = setup();
    tx.slotPraktik.findUnique.mockResolvedValueOnce({ ...slot, _count: { janjiTemu: 2 } });
    await expect(service.update('slot-1', { kapasitas: 1 })).rejects.toBeInstanceOf(ConflictException);
  });

  it('PATCH kapasitas mengunci jadwal dan slot', async () => {
    const { service, tx } = setup();
    await service.update('slot-1', { kapasitas: 4 });
    expect(tx.$queryRaw).toHaveBeenCalledTimes(2);
    expect(tx.slotPraktik.update).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ kapasitas: 4 }) }));
  });

  it('PATCH waktu harus tetap tidak overlap', async () => {
    const { service, tx } = setup();
    tx.slotPraktik.findFirst.mockResolvedValueOnce({ id: 'slot-bentrok' });
    await expect(service.update('slot-1', { selesaiPada: '2035-10-15T08:45:00+07:00' })).rejects.toBeInstanceOf(ConflictException);
  });

  it('DELETE adalah soft delete', async () => {
    const { service, tx } = setup();
    await service.remove('slot-1');
    expect(tx.slotPraktik.update).toHaveBeenCalledWith(expect.objectContaining({ data: { aktif: false } }));
  });

  it('menolak DELETE ketika sudah mempunyai janji temu', async () => {
    const { service, tx } = setup();
    tx.slotPraktik.findUnique.mockResolvedValueOnce({ ...slot, _count: { janjiTemu: 1 } });
    await expect(service.remove('slot-1')).rejects.toBeInstanceOf(ConflictException);
  });
});
