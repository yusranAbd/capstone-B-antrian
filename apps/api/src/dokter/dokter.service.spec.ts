import {
  ConflictException,
  NotFoundException,
  UnprocessableEntityException,
} from '@nestjs/common';

import { PeranPengguna, Prisma } from '../generated/prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { DokterService } from './dokter.service';

const dokterId = '11111111-1111-4111-8111-111111111111';
const layananId = '22222222-2222-4222-8222-222222222222';
const relasiId = '33333333-3333-4333-8333-333333333333';

const buatPrismaMock = () => ({
  dokter: {
    create: jest.fn(),
    findMany: jest.fn(),
    findFirst: jest.fn(),
    findUnique: jest.fn(),
    update: jest.fn(),
  },
  layanan: {
    findUnique: jest.fn(),
  },
  dokterLayanan: {
    upsert: jest.fn(),
    findUnique: jest.fn(),
    update: jest.fn(),
  },
});

describe('DokterService (H2.1)', () => {
  let prisma: ReturnType<typeof buatPrismaMock>;
  let service: DokterService;

  beforeEach(() => {
    prisma = buatPrismaMock();
    service = new DokterService(prisma as unknown as PrismaService);
  });

  it('membuat dokter dengan nama bersih dan status aktif', async () => {
    prisma.dokter.create.mockResolvedValue({ id: dokterId });
    await service.create({
      kode: 'DR-001',
      nama: '  Dr. Sinta  ',
      spesialisasi: '  Anak  ',
    });
    expect(prisma.dokter.create).toHaveBeenCalledWith({
      data: {
        kode: 'DR-001',
        nama: 'Dr. Sinta',
        spesialisasi: 'Anak',
        aktif: true,
      },
    });
  });

  it('menolak kode dokter duplikat', async () => {
    prisma.dokter.create.mockRejectedValue(
      new Prisma.PrismaClientKnownRequestError('duplikat', {
        code: 'P2002',
        clientVersion: '7.10.0',
      }),
    );
    await expect(
      service.create({ kode: 'DR-001', nama: 'Dr. Sinta' }),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it('pembaca USER hanya melihat dokter dengan relasi dan layanan aktif', async () => {
    prisma.dokter.findMany.mockResolvedValue([]);
    await service.findAll(PeranPengguna.USER);
    const arg = prisma.dokter.findMany.mock.calls[0]?.[0];
    expect(arg.where).toEqual({
      aktif: true,
      dokterLayanan: { some: { aktif: true, layanan: { aktif: true } } },
    });
    expect(arg.include.dokterLayanan.where).toEqual({
      aktif: true,
      layanan: { aktif: true },
    });
  });

  it('ADMIN dapat melihat dokter dan relasi nonaktif', async () => {
    prisma.dokter.findMany.mockResolvedValue([]);
    await service.findAll(PeranPengguna.ADMIN);
    expect(prisma.dokter.findMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: undefined }),
    );
  });

  it('detail yang tidak terlihat bagi USER dikembalikan sebagai 404', async () => {
    prisma.dokter.findFirst.mockResolvedValue(null);
    await expect(service.findOne(dokterId, PeranPengguna.USER)).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it('memperbarui nama dan spesialisasi dokter', async () => {
    prisma.dokter.findUnique.mockResolvedValue({ id: dokterId });
    prisma.dokter.update.mockResolvedValue({ id: dokterId });
    await service.update(dokterId, {
      nama: ' Dr. Citra ',
      spesialisasi: '  Ortopedi ',
    });
    expect(prisma.dokter.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: dokterId },
        data: expect.objectContaining({
          nama: 'Dr. Citra',
          spesialisasi: 'Ortopedi',
        }),
      }),
    );
  });

  it('DELETE melakukan soft delete', async () => {
    prisma.dokter.findUnique.mockResolvedValue({ id: dokterId });
    prisma.dokter.update.mockResolvedValue({ id: dokterId, aktif: false });
    await service.remove(dokterId);
    expect(prisma.dokter.update).toHaveBeenCalledWith({
      where: { id: dokterId },
      data: { aktif: false },
    });
  });

  it('tidak bisa mengubah dokter yang tidak ada', async () => {
    prisma.dokter.findUnique.mockResolvedValue(null);
    await expect(service.update(dokterId, { aktif: false })).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it('menghubungkan dokter aktif ke layanan aktif lewat upsert', async () => {
    prisma.dokter.findUnique.mockResolvedValue({ id: dokterId, aktif: true });
    prisma.layanan.findUnique.mockResolvedValue({ id: layananId, aktif: true });
    prisma.dokterLayanan.upsert.mockResolvedValue({ id: relasiId });
    await service.hubungkanLayanan(dokterId, { layananId });
    expect(prisma.dokterLayanan.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          dokterId_layananId: { dokterId, layananId },
        },
        create: { dokterId, layananId, aktif: true },
        update: { aktif: true },
      }),
    );
  });

  it('menolak relasi jika dokter tidak aktif', async () => {
    prisma.dokter.findUnique.mockResolvedValue({ id: dokterId, aktif: false });
    prisma.layanan.findUnique.mockResolvedValue({ id: layananId, aktif: true });
    await expect(
      service.hubungkanLayanan(dokterId, { layananId }),
    ).rejects.toBeInstanceOf(UnprocessableEntityException);
    expect(prisma.dokterLayanan.upsert).not.toHaveBeenCalled();
  });

  it('menolak relasi jika layanan tidak aktif', async () => {
    prisma.dokter.findUnique.mockResolvedValue({ id: dokterId, aktif: true });
    prisma.layanan.findUnique.mockResolvedValue({ id: layananId, aktif: false });
    await expect(
      service.hubungkanLayanan(dokterId, { layananId }),
    ).rejects.toBeInstanceOf(UnprocessableEntityException);
    expect(prisma.dokterLayanan.upsert).not.toHaveBeenCalled();
  });

  it('nonaktifkan relasi tanpa menghapus data', async () => {
    prisma.dokter.findUnique.mockResolvedValue({ id: dokterId });
    prisma.dokterLayanan.findUnique.mockResolvedValue({ id: relasiId });
    prisma.dokterLayanan.update.mockResolvedValue({ id: relasiId, aktif: false });
    await service.nonaktifkanLayanan(dokterId, layananId);
    expect(prisma.dokterLayanan.update).toHaveBeenCalledWith({
      where: { id: relasiId },
      data: { aktif: false },
    });
  });

  it('404 ketika relasi dokter-layanan tidak ada', async () => {
    prisma.dokter.findUnique.mockResolvedValue({ id: dokterId });
    prisma.dokterLayanan.findUnique.mockResolvedValue(null);
    await expect(
      service.nonaktifkanLayanan(dokterId, layananId),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it('GET layanan menggunakan filter dari detail dokter sesuai peran', async () => {
    prisma.dokter.findFirst.mockResolvedValue({
      id: dokterId,
      dokterLayanan: [{ id: relasiId }],
    });
    const result = await service.findLayanan(dokterId, PeranPengguna.USER);
    expect(result).toEqual([{ id: relasiId }]);
  });
});
