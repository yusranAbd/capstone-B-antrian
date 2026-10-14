import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { ModeReservasi, Prisma, StatusTiket } from '../generated/prisma/client';
import type { PrismaService } from '../prisma/prisma.service';
import { JanjiTemuService } from './janji-temu.service';

const penggunaId = '11111111-1111-4111-8111-111111111111';
const slotId = '22222222-2222-4222-8222-222222222222';
const jadwalId = '33333333-3333-4333-8333-333333333333';
const layananId = '44444444-4444-4444-8444-444444444444';
const janjiId = '55555555-5555-4555-8555-555555555555';
const tiketId = '66666666-6666-4666-8666-666666666666';
const tanggal = new Date('2035-10-15T00:00:00Z');
const mulai = new Date('2035-10-15T01:00:00Z');
const selesai = new Date('2035-10-15T01:30:00Z');

function buatSlot(overrides: Record<string, unknown> = {}) {
  return {
    id: slotId,
    aktif: true,
    kapasitas: 2,
    mulaiPada: mulai,
    selesaiPada: selesai,
    jadwalPraktik: {
      id: jadwalId, tanggal, aktif: true,
      mulaiPada: new Date('2035-10-15T00:00:00Z'),
      selesaiPada: new Date('2035-10-15T04:00:00Z'),
      loket: { aktif: true, layananId },
      dokterLayanan: {
        aktif: true,
        dokter: { aktif: true },
        layanan: { id: layananId, aktif: true, modeReservasi: ModeReservasi.JANJI_TEMU_DOKTER as ModeReservasi },
      },
    },
    ...overrides,
  };
}

function buatDetail(status: StatusTiket = StatusTiket.DIPESAN) {
  return {
    id: janjiId,
    tiket: {
      id: tiketId, penggunaId, nomorUrut: 7,
      tanggalAntrean: tanggal, status,
      layanan: { prefixAntrean: 'PL' },
    },
    slotPraktik: { id: slotId, mulaiPada: mulai },
  };
}

function setup() {
  const tx = {
    $queryRaw: jest.fn().mockResolvedValue([{ ok: 1 }]),
    slotPraktik: { findUnique: jest.fn().mockResolvedValue(buatSlot()) },
    janjiTemu: {
      count: jest.fn().mockResolvedValue(0),
      create: jest.fn().mockResolvedValue({ id: janjiId }),
      findFirst: jest.fn().mockResolvedValue({ tiketId, tiket: { status: StatusTiket.DIPESAN } }),
    },
    urutanAntreanHarian: { upsert: jest.fn().mockResolvedValue({ nomorTerakhir: 7 }) },
    tiketAntrean: {
      findFirst: jest.fn().mockResolvedValue(null),
      create: jest.fn().mockResolvedValue({ id: tiketId }),
      updateMany: jest.fn().mockResolvedValue({ count: 1 }),
    },
    peristiwaAntrean: { create: jest.fn().mockResolvedValue({ id: 'audit-id' }) },
  };
  const prisma = {
    slotPraktik: { findUnique: jest.fn().mockResolvedValue({ jadwalPraktikId: jadwalId }) },
    janjiTemu: {
      findFirst: jest.fn().mockResolvedValue(buatDetail()),
      findMany: jest.fn().mockResolvedValue([buatDetail()]),
    },
    $transaction: jest.fn().mockImplementation((callback: (db: typeof tx) => Promise<unknown>) => callback(tx)),
  };
  const service = new JanjiTemuService(prisma as unknown as PrismaService);
  return { tx, prisma, service };
}

describe('JanjiTemuService H2.4', () => {
  it('booking atomik menerbitkan tiket, janji temu, dan audit dalam satu transaksi', async () => {
    const { service, tx, prisma } = setup();
    await expect(service.create({ slotPraktikId: slotId }, penggunaId))
      .resolves.toMatchObject({ id: janjiId, nomorAntrean: 'PL-007', tanggalPelayanan: '2035-10-15' });
    expect(tx.$queryRaw).toHaveBeenCalledTimes(2);
    expect(tx.urutanAntreanHarian.upsert).toHaveBeenCalledTimes(1);
    expect(tx.tiketAntrean.create).toHaveBeenCalledWith(expect.objectContaining({
      data: expect.objectContaining({ status: StatusTiket.DIPESAN, penggunaId, layananId }),
    }));
    expect(tx.janjiTemu.create).toHaveBeenCalledWith(expect.objectContaining({
      data: { tiketId, slotPraktikId: slotId },
    }));
    expect(tx.peristiwaAntrean.create).toHaveBeenCalledWith(expect.objectContaining({
      data: expect.objectContaining({ tipe: 'APPOINTMENT_BOOK' }),
    }));
    expect(prisma.$transaction).toHaveBeenCalledWith(expect.any(Function), expect.objectContaining({
      isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
    }));
  });

  it('booking menolak ID slot yang tidak ditemukan', async () => {
    const { service, prisma } = setup();
    prisma.slotPraktik.findUnique.mockResolvedValueOnce(null);
    await expect(service.create({ slotPraktikId: slotId }, penggunaId)).rejects.toBeInstanceOf(NotFoundException);
  });

  it('booking menolak layanan yang masih memakai mode antrean harian', async () => {
    const { service, tx } = setup();
    const slot = buatSlot();
    slot.jadwalPraktik.dokterLayanan.layanan.modeReservasi = ModeReservasi.ANTREAN_HARIAN;
    tx.slotPraktik.findUnique.mockResolvedValueOnce(slot);
    await expect(service.create({ slotPraktikId: slotId }, penggunaId)).rejects.toBeInstanceOf(BadRequestException);
  });

  it('booking menolak slot yang nonaktif', async () => {
    const { service, tx } = setup();
    tx.slotPraktik.findUnique.mockResolvedValueOnce(buatSlot({ aktif: false }));
    await expect(service.create({ slotPraktikId: slotId }, penggunaId)).rejects.toBeInstanceOf(BadRequestException);
  });

  it('booking menolak dokter nonaktif', async () => {
    const { service, tx } = setup();
    const slot = buatSlot();
    slot.jadwalPraktik.dokterLayanan.dokter.aktif = false;
    tx.slotPraktik.findUnique.mockResolvedValueOnce(slot);
    await expect(service.create({ slotPraktikId: slotId }, penggunaId)).rejects.toBeInstanceOf(BadRequestException);
  });

  it('booking menolak lokasi layanan berbeda', async () => {
    const { service, tx } = setup();
    const slot = buatSlot();
    slot.jadwalPraktik.loket.layananId = 'layanan-lain';
    tx.slotPraktik.findUnique.mockResolvedValueOnce(slot);
    await expect(service.create({ slotPraktikId: slotId }, penggunaId)).rejects.toBeInstanceOf(BadRequestException);
  });

  it('booking menolak waktu slot yang sudah berlalu', async () => {
    const { service, tx } = setup();
    tx.slotPraktik.findUnique.mockResolvedValueOnce(buatSlot({ mulaiPada: new Date('2020-01-01') }));
    await expect(service.create({ slotPraktikId: slotId }, penggunaId)).rejects.toBeInstanceOf(BadRequestException);
  });

  it('booking menolak waktu slot di luar jadwal praktik', async () => {
    const { service, tx } = setup();
    tx.slotPraktik.findUnique.mockResolvedValueOnce(buatSlot({ selesaiPada: new Date('2035-10-15T06:00:00Z') }));
    await expect(service.create({ slotPraktikId: slotId }, penggunaId)).rejects.toBeInstanceOf(BadRequestException);
  });

  it('booking menolak kapasitas yang sudah penuh', async () => {
    const { service, tx } = setup();
    tx.janjiTemu.count.mockResolvedValueOnce(2);
    await expect(service.create({ slotPraktikId: slotId }, penggunaId)).rejects.toBeInstanceOf(ConflictException);
    expect(tx.tiketAntrean.create).not.toHaveBeenCalled();
  });

  it('booking menghitung hanya janji yang belum dibatalkan', async () => {
    const { service, tx } = setup();
    await service.create({ slotPraktikId: slotId }, penggunaId);
    expect(tx.janjiTemu.count).toHaveBeenCalledWith({
      where: { slotPraktikId: slotId, tiket: { is: { status: { not: StatusTiket.DIBATALKAN } } } },
    });
  });

  it('booking mencegah dua tiket aktif milik pasien untuk poli/tanggal yang sama', async () => {
    const { service, tx } = setup();
    tx.tiketAntrean.findFirst.mockResolvedValueOnce({ id: 'tiket-lama' });
    await expect(service.create({ slotPraktikId: slotId }, penggunaId)).rejects.toBeInstanceOf(ConflictException);
    expect(tx.janjiTemu.create).not.toHaveBeenCalled();
  });

  it('booking mengulangi transaksi serializable saat gagal P2034', async () => {
    const { service, prisma } = setup();
    const gagal = new Prisma.PrismaClientKnownRequestError('konflik', { code: 'P2034', clientVersion: '7.10.0' });
    const asli = prisma.$transaction.getMockImplementation();
    prisma.$transaction.mockRejectedValueOnce(gagal);
    if (!asli) throw new Error('Mock transaksi tidak tersedia');
    prisma.$transaction.mockImplementation(asli);
    await expect(service.create({ slotPraktikId: slotId }, penggunaId)).resolves.toHaveProperty('id', janjiId);
    expect(prisma.$transaction).toHaveBeenCalledTimes(2);
  });

  it('booking rollback seluruh transaksi jika audit gagal', async () => {
    const { service, tx } = setup();
    tx.peristiwaAntrean.create.mockRejectedValueOnce(new Error('audit gagal'));
    await expect(service.create({ slotPraktikId: slotId }, penggunaId)).rejects.toThrow('audit gagal');
  });

  it('mendaftar dan membaca hanya janji temu pemilik', async () => {
    const { service, prisma } = setup();
    await expect(service.findAll(penggunaId)).resolves.toHaveLength(1);
    await expect(service.findOne(janjiId, penggunaId)).resolves.toMatchObject({ nomorAntrean: 'PL-007' });
    expect(prisma.janjiTemu.findMany).toHaveBeenCalledWith(expect.objectContaining({
      where: { tiket: { is: { penggunaId } } },
    }));
    expect(prisma.janjiTemu.findFirst).toHaveBeenCalledWith(expect.objectContaining({
      where: { id: janjiId, tiket: { is: { penggunaId } } },
    }));
  });

  it('detail nonpemilik mengembalikan 404', async () => {
    const { service, prisma } = setup();
    prisma.janjiTemu.findFirst.mockResolvedValueOnce(null);
    await expect(service.findOne(janjiId, penggunaId)).rejects.toBeInstanceOf(NotFoundException);
  });

  it('pembatalan hanya status DIPESAN dan mempertahankan relasi histori', async () => {
    const { service, prisma, tx } = setup();
    prisma.janjiTemu.findFirst.mockResolvedValueOnce({
      slotPraktikId: slotId,
      slotPraktik: { jadwalPraktikId: jadwalId },
    });
    await expect(service.batalkan(janjiId, penggunaId)).resolves.toMatchObject({ id: janjiId });
    expect(tx.$queryRaw).toHaveBeenCalledTimes(2);
    expect(tx.tiketAntrean.updateMany).toHaveBeenCalledWith({
      where: { id: tiketId, penggunaId, status: StatusTiket.DIPESAN },
      data: { status: StatusTiket.DIBATALKAN, versi: { increment: 1 } },
    });
    expect(tx.peristiwaAntrean.create).toHaveBeenCalledWith(expect.objectContaining({
      data: expect.objectContaining({ tipe: 'APPOINTMENT_CANCEL' }),
    }));
  });

  it('pembatalan menolak tiket yang sudah check-in', async () => {
    const { service, prisma, tx } = setup();
    prisma.janjiTemu.findFirst.mockResolvedValueOnce({
      slotPraktikId: slotId,
      slotPraktik: { jadwalPraktikId: jadwalId },
    });
    tx.janjiTemu.findFirst.mockResolvedValueOnce({ tiketId, tiket: { status: StatusTiket.CHECK_IN } });
    await expect(service.batalkan(janjiId, penggunaId)).rejects.toBeInstanceOf(ConflictException);
    expect(tx.tiketAntrean.updateMany).not.toHaveBeenCalled();
  });

  it('pembatalan nonpemilik mengembalikan 404', async () => {
    const { service, prisma } = setup();
    prisma.janjiTemu.findFirst.mockResolvedValueOnce(null);
    await expect(service.batalkan(janjiId, penggunaId)).rejects.toBeInstanceOf(NotFoundException);
  });

  it('pembatalan menolak jika status tiket sudah berubah di antara pembacaan dan update', async () => {
    const { service, prisma, tx } = setup();
    prisma.janjiTemu.findFirst.mockResolvedValueOnce({
      slotPraktikId: slotId,
      slotPraktik: { jadwalPraktikId: jadwalId },
    });
    tx.tiketAntrean.updateMany.mockResolvedValueOnce({ count: 0 });
    await expect(service.batalkan(janjiId, penggunaId)).rejects.toBeInstanceOf(ConflictException);
  });
});
