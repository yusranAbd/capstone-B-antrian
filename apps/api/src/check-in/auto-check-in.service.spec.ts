import { ConflictException, ForbiddenException } from '@nestjs/common';
import { Prisma, StatusTiket } from '../generated/prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { QueueService } from '../queue/queue.service';
import { RealtimeBroadcastService } from '../realtime/realtime-broadcast.service';
import { CheckInService } from './check-in.service';
import { AutoCheckInService } from './auto-check-in.service';

describe('One scan atomic composition', () => {
  function fixture(status: StatusTiket = 'CHECK_IN') {
    const tx = {
      pengguna: {
        findUnique: jest
          .fn()
          .mockResolvedValue({ aktif: true, peran: 'PETUGAS' }),
      },
      tiketAntrean: {
        findUniqueOrThrow: jest
          .fn()
          .mockResolvedValue({
            status: 'MENUNGGU',
            versi: 3,
            urutanMasukAntrean: 7,
            masukAntreanPada: new Date(),
            pengguna: { nama: 'Pasien Uji' },
            layanan: { nama: 'Poli Uji' },
          }),
      },
    };
    let committed = false;
    const prisma = {
      $transaction: jest.fn(async (fn: (t: typeof tx) => Promise<unknown>) => {
        const r = await fn(tx);
        committed = true;
        return r;
      }),
    };
    const checkIn = {
      prosesDalamTransaksi: jest
        .fn()
        .mockResolvedValue({
          tiketId: 'ticket',
          layananId: 'clinic',
          nomorAntrean: 'A-001',
          status,
          loketId: 'room',
        }),
    };
    const queue = {
      masukAntreanDalamTransaksi: jest.fn().mockResolvedValue({}),
    };
    const realtime = {
      kirim: jest.fn().mockImplementation(() => {
        expect(committed).toBe(true);
        return Promise.resolve();
      }),
    };
    const service = new AutoCheckInService(
      prisma as unknown as PrismaService,
      checkIn as unknown as CheckInService,
      queue as unknown as QueueService,
      realtime as unknown as RealtimeBroadcastService,
    );
    return { tx, prisma, checkIn, queue, realtime, service };
  }
  const dto = { qrPayload: `SQ1.${'A'.repeat(43)}`, loketId: 'room' };
  it('uses one Serializable transaction; both helpers share tx; event after commit only', async () => {
    const f = fixture();
    const r = await f.service.proses(dto, 'staff');
    expect(r).toMatchObject({
      status: 'MENUNGGU',
      sudahTerdaftar: false,
      namaPasien: 'Pasien Uji',
    });
    expect(f.prisma.$transaction).toHaveBeenCalledTimes(1);
    expect(f.prisma.$transaction).toHaveBeenCalledWith(
      expect.any(Function),
      expect.objectContaining({ isolationLevel: 'Serializable' }),
    );
    expect(f.checkIn.prosesDalamTransaksi).toHaveBeenCalledWith(
      f.tx,
      dto,
      'staff',
      expect.any(Date),
      true,
    );
    expect(f.queue.masukAntreanDalamTransaksi).toHaveBeenCalledWith(
      f.tx,
      'ticket',
      'staff',
      'room',
      expect.any(Date),
    );
    expect(f.realtime.kirim).toHaveBeenCalledWith(
      expect.objectContaining({ aksi: 'ENQUEUE', status: 'MENUNGGU' }),
    );
    expect(JSON.stringify(f.realtime.kirim.mock.calls)).not.toContain(
      'Pasien Uji',
    );
  });
  it('does not increment or broadcast a duplicate MENUNGGU scan', async () => {
    const f = fixture('MENUNGGU');
    expect(await f.service.proses(dto, 'staff')).toMatchObject({
      sudahTerdaftar: true,
    });
    expect(f.queue.masukAntreanDalamTransaksi).not.toHaveBeenCalled();
    expect(f.realtime.kirim).not.toHaveBeenCalled();
  });
  it('failed enqueue rejects the whole transaction and emits nothing', async () => {
    const f = fixture();
    f.queue.masukAntreanDalamTransaksi.mockRejectedValue(
      new ConflictException('counter missing'),
    );
    await expect(f.service.proses(dto, 'staff')).rejects.toBeInstanceOf(
      ConflictException,
    );
    expect(f.realtime.kirim).not.toHaveBeenCalled();
  });
  it('checks active role before touching QR', async () => {
    const f = fixture();
    f.tx.pengguna.findUnique.mockResolvedValue({
      aktif: false,
      peran: 'PETUGAS',
    });
    await expect(f.service.proses(dto, 'staff')).rejects.toBeInstanceOf(
      ForbiddenException,
    );
    expect(f.checkIn.prosesDalamTransaksi).not.toHaveBeenCalled();
  });
  it('retries serialization conflicts without duplicating the postcommit event', async () => {
    const f = fixture();
    f.prisma.$transaction.mockRejectedValueOnce(
      new Prisma.PrismaClientKnownRequestError('serialization', {
        code: 'P2034',
        clientVersion: '7.10.0',
      }),
    );
    await expect(f.service.proses(dto, 'staff')).resolves.toMatchObject({
      status: 'MENUNGGU',
    });
    expect(f.prisma.$transaction).toHaveBeenCalledTimes(2);
    expect(f.realtime.kirim).toHaveBeenCalledTimes(1);
  });
});
