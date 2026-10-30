import { BadRequestException, NotFoundException } from '@nestjs/common';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { Prisma, StatusTiket } from '../generated/prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import {
  PatientQueueQueryDto,
  validPatientQueueDate,
} from './dto/patient-queue-query.dto';
import { PatientQueueSummaryService } from './patient-queue-summary.service';

const serviceId = '11111111-1111-4111-8111-111111111111';
describe('Patient queue read model', () => {
  const services = jest.fn(),
    groups = jest.fn(),
    active = jest.fn();
  const transaction = jest.fn(
    (read: (tx: unknown) => unknown, _options?: unknown) =>
      read({
        layanan: { findMany: services },
        tiketAntrean: { groupBy: groups, findMany: active },
      }),
  );
  const model = new PatientQueueSummaryService({
    $transaction: transaction,
  } as unknown as PrismaService);
  beforeEach(() => {
    jest.clearAllMocks();
    services.mockResolvedValue([{ id: serviceId, prefixAntrean: ' PEN ' }]);
    groups.mockResolvedValue([]);
    active.mockResolvedValue([]);
  });
  it('authoritative zero and empty serving are valid, without reserved-ticket totals', async () => {
    const result = await model.snapshot({
      tanggal: '2026-10-30',
      layananId: [serviceId],
    });
    expect(result).toEqual({
      versiSkema: 1,
      tanggalPelayanan: '2026-10-30',
      diperolehPada: expect.any(String),
      layanan: [
        {
          layananId: serviceId,
          totalCheckIn: 0,
          jumlahMenunggu: 0,
          sedangDilayani: [],
        },
      ],
    });
    expect(transaction.mock.calls[0]?.[1]).toEqual({
      isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead,
      maxWait: 3000,
      timeout: 10000,
    });
  });
  it('counts unique persisted ticket rows including completed; waiting uses checked-in FIFO status', async () => {
    groups
      .mockResolvedValueOnce([{ layananId: serviceId, _count: { _all: 42 } }])
      .mockResolvedValueOnce([{ layananId: serviceId, _count: { _all: 31 } }]);
    const result = await model.snapshot({
      tanggal: '2026-10-30',
      layananId: [serviceId],
    });
    expect(result.layanan[0]?.totalCheckIn).toBe(42);
    expect(result.layanan[0]?.jumlahMenunggu).toBe(31);
    expect(groups.mock.calls[0][0]).toEqual({
      by: ['layananId'],
      where: {
        layananId: { in: [serviceId] },
        tanggalAntrean: new Date('2026-10-30T00:00:00Z'),
        checkInPada: { not: null },
      },
      _count: { _all: true },
    });
    expect(groups.mock.calls[1][0].where).toEqual({
      ...groups.mock.calls[0][0].where,
      status: StatusTiket.MENUNGGU,
      urutanMasukAntrean: { not: null },
    });
  });
  it('serving keeps all active rooms and projects no person or ticket identifier', async () => {
    active.mockResolvedValue([
      {
        layananId: serviceId,
        nomorUrut: 7,
        loket: { id: 'room-a', kode: 'A', layananId: serviceId },
        pengguna: { nama: 'PRIVATE' },
      },
      {
        layananId: serviceId,
        nomorUrut: 11,
        loket: { id: 'room-b', kode: 'B', layananId: serviceId },
        nik: 'PRIVATE',
      },
    ]);
    const result = await model.snapshot({ tanggal: '2026-10-30' });
    expect(result.layanan[0]?.sedangDilayani).toEqual([
      { loketId: 'room-a', kodeLoket: 'A', nomorAntrean: 'PEN-007' },
      { loketId: 'room-b', kodeLoket: 'B', nomorAntrean: 'PEN-011' },
    ]);
    expect(JSON.stringify(result)).not.toContain('PRIVATE');
    expect(active.mock.calls[0][0].where.status).toBe(StatusTiket.DILAYANI);
    expect(active.mock.calls[0][0].select).toEqual({
      layananId: true,
      nomorUrut: true,
      loket: { select: { id: true, kode: true, layananId: true } },
    });
  });
  it('inactive/missing requested IDs fail closed', async () => {
    services.mockResolvedValue([]);
    await expect(
      model.snapshot({ tanggal: '2026-10-30', layananId: [serviceId] }),
    ).rejects.toBeInstanceOf(NotFoundException);
    expect(groups).not.toHaveBeenCalled();
  });
  it.each([
    '2026-02-30',
    '2026-1-01',
    '2026-10-30T00:00:00Z',
    '0000-01-01',
    'bad',
  ])('rejects invalid calendar date %s', async (tanggal) => {
    expect(validPatientQueueDate(tanggal)).toBe(false);
    await expect(model.snapshot({ tanggal })).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });
  it('DTO validates batch ids, strict dates and bounds', async () => {
    const valid = plainToInstance(PatientQueueQueryDto, {
      layananId: serviceId,
      tanggal: '2026-10-30',
    });
    expect(await validate(valid)).toEqual([]);
    expect(valid.layananId).toEqual([serviceId]);
    for (const raw of [
      { layananId: 'bad' },
      { layananId: serviceId + ',' + serviceId },
      { layananId: Array(101).fill(serviceId) },
      { tanggal: '2026-02-30' },
    ]) {
      expect(
        (await validate(plainToInstance(PatientQueueQueryDto, raw))).length,
      ).toBeGreaterThan(0);
    }
  });
});
