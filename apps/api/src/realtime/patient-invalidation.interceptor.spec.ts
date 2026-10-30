import { type CallHandler, type ExecutionContext } from '@nestjs/common';
import { PATH_METADATA } from '@nestjs/common/constants';
import { lastValueFrom, of, Subject, throwError } from 'rxjs';
import { PrismaService } from '../prisma/prisma.service';
import { PatientInvalidationInterceptor } from './patient-invalidation.interceptor';
import { PatientRealtimeGateway } from './patient-realtime.gateway';

describe('PatientInvalidationInterceptor', () => {
  const invalidate = jest.fn(),
    invalidateQueue = jest.fn(),
    findUnique = jest.fn();
  const interceptor = new PatientInvalidationInterceptor(
    { invalidate, invalidateQueue } as unknown as PatientRealtimeGateway,
    { tiketAntrean: { findUnique } } as unknown as PrismaService,
  );
  function context(controller: string, role = 'USER', method = 'POST') {
    class Controller {}
    Reflect.defineMetadata(PATH_METADATA, controller, Controller);
    return {
      getType: () => 'http',
      getClass: () => Controller,
      switchToHttp: () => ({
        getRequest: () => ({ method, user: { id: 'actor', peran: role } }),
      }),
    } as unknown as ExecutionContext;
  }
  beforeEach(() => {
    jest.clearAllMocks();
    invalidate.mockResolvedValue(undefined);
    invalidateQueue.mockResolvedValue(undefined);
    findUnique.mockResolvedValue({
      penggunaId: 'owner',
      layananId: 'service',
      tanggalAntrean: new Date('2026-10-30T00:00:00Z'),
    });
  });
  it('tidak mengirim sebelum operasi selesai atau ketika transaksi gagal', async () => {
    const pending = new Subject<unknown>();
    const result = lastValueFrom(
      interceptor.intercept(context('reservasi'), { handle: () => pending }),
    );
    expect(invalidate).not.toHaveBeenCalled();
    pending.error(new Error('rollback'));
    await expect(result).rejects.toThrow('rollback');
    expect(invalidate).not.toHaveBeenCalled();
  });
  it.each(['reservasi', 'janji-temu'])(
    'invalidasi %s hanya ke pemilik JWT sesudah sukses',
    async (controller) => {
      const result = { id: 'appointment-or-ticket' };
      expect(
        await lastValueFrom(
          interceptor.intercept(context(controller), {
            handle: () => of(result),
          }),
        ),
      ).toBe(result);
      expect(invalidate.mock.calls).toEqual([['TIKET', 'actor'], ['KATALOG']]);
    },
  );
  it.each(['queue', 'check-in'])(
    '%s mencari pemilik tiket dari hasil commit, bukan ID petugas',
    async (controller) => {
      await lastValueFrom(
        interceptor.intercept(context(controller, 'PETUGAS'), {
          handle: () => of({ tiketId: 'ticket' }),
        }),
      );
      expect(findUnique).toHaveBeenCalledWith({
        where: { id: 'ticket' },
        select: { penggunaId: true, layananId: true, tanggalAntrean: true },
      });
      expect(invalidate).toHaveBeenCalledWith('TIKET', 'owner');
      expect(invalidate).not.toHaveBeenCalledWith('TIKET', 'actor');
      expect(invalidateQueue).toHaveBeenCalledWith('service', '2026-10-30');
    },
  );
  it.each([
    'layanan',
    'dokter',
    'loket',
    'jadwal-layanan',
    'jadwal-praktik',
    'slot-praktik',
  ])('invalidasi master %s tidak membawa data privat', async (controller) => {
    await lastValueFrom(
      interceptor.intercept(context(controller, 'ADMIN', 'PATCH'), {
        handle: () => of({ nama: 'ignored', id: 'ignored' }),
      }),
    );
    expect(invalidate.mock.calls).toEqual([['KATALOG']]);
  });
  it('GET, modul lain, role lain dan operasi ditolak tidak memicu broadcast', async () => {
    for (const ctx of [
      context('dokter', 'ADMIN', 'GET'),
      context('auth'),
      context('dokter', 'USER'),
    ])
      await lastValueFrom(interceptor.intercept(ctx, { handle: () => of({}) }));
    await expect(
      lastValueFrom(
        interceptor.intercept(context('dokter', 'ADMIN'), {
          handle: () => throwError(() => new Error('invalid')),
        }),
      ),
    ).rejects.toThrow('invalid');
    expect(invalidate).not.toHaveBeenCalled();
  });
  it('kegagalan invalidasi tidak mengubah respons atau mengulang transaksi', async () => {
    invalidate.mockRejectedValue(new Error('offline'));
    const handle = jest.fn(() => of({ tiketId: 'ticket' }));
    expect(
      await lastValueFrom(
        interceptor.intercept(context('queue', 'PETUGAS'), {
          handle,
        } as CallHandler),
      ),
    ).toEqual({ tiketId: 'ticket' });
    expect(handle).toHaveBeenCalledTimes(1);
  });
});
