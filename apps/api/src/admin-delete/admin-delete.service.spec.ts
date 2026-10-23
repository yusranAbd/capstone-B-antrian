import { ConflictException, Logger, NotFoundException } from '@nestjs/common';
import {
  AdminDeleteService,
  DELETE_RESOURCES,
  type DeleteResource,
} from './admin-delete.service';
import { PrismaService } from '../prisma/prisma.service';
import { DisplayRealtimeGateway } from '../realtime/display-realtime.gateway';

describe('Admin permanent deletion', () => {
  const id = '11111111-1111-4111-8111-111111111111';
  let tx: ReturnType<typeof mockTx>, service: AdminDeleteService;
  const revoke = jest.fn();
  let auditLog: jest.SpyInstance;
  function mockTx() {
    const model = () => ({
      count: jest.fn().mockResolvedValue(0),
      deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
      findUniqueOrThrow: jest.fn().mockResolvedValue({
        penggunaId: null,
        layananId: id,
        loketId: id,
        tanggal: new Date(),
        tanggalMulai: new Date(),
        tanggalSelesai: null,
        dokterLayanan: { layananId: id },
      }),
    });
    return {
      $executeRaw: jest.fn().mockResolvedValue(1),
      $queryRaw: jest.fn().mockResolvedValue([{ id }]),
      layanan: model(),
      dokter: model(),
      loket: model(),
      dokterLayanan: model(),
      jadwalLayanan: model(),
      jadwalPraktik: model(),
      slotPraktik: model(),
      janjiTemu: model(),
      tiketAntrean: model(),
      penugasanPetugas: model(),
      perangkatTampilan: model(),
      urutanAntreanHarian: model(),
    };
  }
  beforeEach(() => {
    tx = mockTx();
    revoke.mockReset();
    const prisma = {
      $transaction: jest.fn((fn: (v: typeof tx) => Promise<unknown>) => fn(tx)),
    };
    service = new AdminDeleteService(
      prisma as unknown as PrismaService,
      { cabutPerangkat: revoke } as unknown as DisplayRealtimeGateway,
    );
    auditLog = jest.spyOn(Logger.prototype, 'log').mockImplementation(() => {});
  });
  afterEach(() => jest.restoreAllMocks());
  it.each(Object.keys(DELETE_RESOURCES) as DeleteResource[])(
    'deletes unused %s and logs only identifiers',
    async (resource) => {
      expect(await service.remove(resource, id, 'admin-id')).toEqual({
        id,
        dihapus: true,
      });
      expect(auditLog).toHaveBeenCalledWith(
        expect.stringContaining('HAPUS_PERMANEN'),
      );
      expect(revoke).toHaveBeenCalledTimes(
        resource === 'perangkat-display' ? 1 : 0,
      );
    },
  );
  it.each([
    ['layanan', 'tiketAntrean'],
    ['layanan', 'urutanAntreanHarian'],
    ['layanan', 'loket'],
    ['layanan', 'jadwalLayanan'],
    ['layanan', 'dokterLayanan'],
    ['layanan', 'perangkatTampilan'],
    ['dokter', 'jadwalPraktik'],
    ['loket', 'tiketAntrean'],
    ['loket', 'jadwalPraktik'],
    ['loket', 'penugasanPetugas'],
    ['jadwal-layanan', 'tiketAntrean'],
    ['jadwal-layanan', 'jadwalPraktik'],
    ['jadwal-praktik', 'janjiTemu'],
    ['jadwal-praktik', 'tiketAntrean'],
    ['jadwal-praktik', 'slotPraktik'],
    ['slot-praktik', 'janjiTemu'],
    ['penugasan-petugas', 'tiketAntrean'],
  ] as const)('protects references for %s / %s', async (resource, model) => {
    tx[model].count.mockResolvedValue(1);
    await expect(service.remove(resource, id, 'admin')).rejects.toThrow(
      ConflictException,
    );
    expect(auditLog).not.toHaveBeenCalled();
    expect(revoke).not.toHaveBeenCalled();
  });
  it('never deletes a linked doctor account', async () => {
    tx.dokter.findUniqueOrThrow.mockResolvedValue({
      penggunaId: 'account',
      layananId: id,
      loketId: id,
      tanggal: new Date(),
      tanggalMulai: new Date(),
      tanggalSelesai: null,
      dokterLayanan: { layananId: id },
    });
    await expect(service.remove('dokter', id, 'admin')).rejects.toThrow(
      ConflictException,
    );
    expect(tx.dokterLayanan.deleteMany).not.toHaveBeenCalled();
  });
  it('returns 404 when already gone', async () => {
    tx.$queryRaw.mockResolvedValue([]);
    await expect(service.remove('dokter', id, 'admin')).rejects.toThrow(
      NotFoundException,
    );
  });
  it.each(['P2034', 'P2028'])(
    'maps concurrent conflict %s without revocation or success audit',
    async (code) => {
      tx.$queryRaw.mockRejectedValue({ code });
      await expect(
        service.remove('perangkat-display', id, 'admin'),
      ).rejects.toThrow(ConflictException);
      expect(revoke).not.toHaveBeenCalled();
      expect(auditLog).not.toHaveBeenCalled();
    },
  );
  it.each(['40001', '40P01', '55P03', '23503'])(
    'handles PostgreSQL adapter cause %s as 409',
    async (originalCode) => {
      tx.$queryRaw.mockRejectedValue({
        code: 'P2010',
        meta: { driverAdapterError: { cause: { originalCode } } },
      });
      await expect(
        service.remove('perangkat-display', id, 'admin'),
      ).rejects.toThrow(ConflictException);
      expect(revoke).not.toHaveBeenCalled();
      expect(auditLog).not.toHaveBeenCalled();
    },
  );
  it('does not hide an unexpected SQL programming error as a conflict', async () => {
    const failure = {
      code: 'P2010',
      meta: { driverAdapterError: { cause: { originalCode: '42601' } } },
    };
    tx.$queryRaw.mockRejectedValue(failure);
    await expect(service.remove('layanan', id, 'admin')).rejects.toBe(failure);
  });
});
