import {
  GoneException,
  UnauthorizedException,
  ConflictException,
  UnprocessableEntityException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DisplayDeviceService } from './display-device.service';
import { PrismaService } from '../prisma/prisma.service';
import { DisplayRealtimeGateway } from '../realtime/display-realtime.gateway';
import {
  cookieToken,
  checkDisplayOrigin,
  displayCookie,
} from './display-cookie';
import type { Request, Response } from 'express';
describe('Display device pairing', () => {
  const device = {
    id: 'device',
    aktif: true,
    layananId: 'clinic',
    layanan: { aktif: true },
    kodeDigunakanPada: null,
    kodeBerlakuHingga: new Date(Date.now() + 300_000),
  };
  let service: DisplayDeviceService;
  let table: {
    findUnique: jest.Mock;
    updateMany: jest.Mock;
    findUniqueOrThrow: jest.Mock;
    create: jest.Mock;
    findMany: jest.Mock;
  };
  let revoke: jest.Mock;
  let clinic: jest.Mock;
  beforeEach(() => {
    table = {
      findUnique: jest.fn().mockResolvedValue(device),
      updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      findUniqueOrThrow: jest
        .fn()
        .mockResolvedValue({ id: 'device', layananId: 'clinic' }),
      create: jest.fn(),
      findMany: jest.fn(),
    };
    revoke = jest.fn();
    clinic = jest.fn().mockResolvedValue({ aktif: true });
    service = new DisplayDeviceService(
      {
        perangkatTampilan: table,
        layanan: { findUnique: clinic },
        $transaction: (fn: (tx: unknown) => unknown) =>
          fn({ perangkatTampilan: table }),
      } as unknown as PrismaService,
      { cabutPerangkat: revoke } as unknown as DisplayRealtimeGateway,
      new ConfigService({
        JWT_REFRESH_SECRET: 'display-pairing-unit-test-secret',
      }),
    );
  });
  it('creates a device without a recoverable credential', async () => {
    await service.create({ layananId: 'clinic', nama: '  TV Anak  ' });
    const data = table.create.mock.calls[0][0].data;
    expect(data.nama).toBe('TV Anak');
    expect(data.tokenHash).toMatch(/^[a-f0-9]{64}$/);
    expect(table.create.mock.calls[0][0].select.tokenHash).toBeUndefined();
  });
  it('rejects inactive clinics', async () => {
    clinic.mockResolvedValue({ aktif: false });
    await expect(
      service.create({ layananId: 'clinic', nama: 'TV' }),
    ).rejects.toBeInstanceOf(UnprocessableEntityException);
  });
  it('generates 12 digits, stores only domain-separated HMAC, revokes previous credential', async () => {
    const result = await service.activation('device');
    expect(/^\d{12}$/.test(result.kode)).toBe(true);
    const data = table.updateMany.mock.calls[0][0].data;
    expect(data.kodeAktivasiHash).not.toBe(result.kode);
    expect(data.kodeAktivasiHash).toMatch(/^[a-f0-9]{64}$/);
    expect(result.berlakuHingga.getTime() - Date.now()).toBeLessThanOrEqual(
      300000,
    );
    expect(revoke).toHaveBeenCalledWith('device');
  });
  it.each([
    [null, UnauthorizedException],
    [{ ...device, aktif: false }, UnauthorizedException],
    [{ ...device, kodeDigunakanPada: new Date() }, GoneException],
    [{ ...device, kodeBerlakuHingga: new Date(0) }, GoneException],
  ])('rejects missing/inactive/consumed/expired code', async (value, error) => {
    table.findUnique.mockResolvedValue(value);
    await expect(service.pair('123456789012')).rejects.toBeInstanceOf(error);
    expect(table.updateMany).not.toHaveBeenCalled();
  });
  it('claims conditionally with expiry, active clinic and unused checks', async () => {
    const result = await service.pair('123456789012');
    expect(result.token).toHaveLength(64);
    expect(table.updateMany.mock.calls[0][0].where).toMatchObject({
      aktif: true,
      kodeDigunakanPada: null,
      layanan: { aktif: true },
    });
    expect(table.updateMany.mock.calls[0][0].data.tokenHash).not.toBe(
      result.token,
    );
  });
  it('loser of concurrent claim gets conflict', async () => {
    table.updateMany.mockResolvedValue({ count: 0 });
    await expect(service.pair('123456789012')).rejects.toBeInstanceOf(
      ConflictException,
    );
  });
  it('deactivation invalidates activation and all credentials', async () => {
    await service.deactivate('device');
    expect(table.updateMany.mock.calls[0][0].data).toMatchObject({
      aktif: false,
      kodeAktivasiHash: null,
      sesiBerakhirPada: null,
    });
    expect(revoke).toHaveBeenCalledWith('device');
  });
  it('rejects expired server session', async () => {
    table.findUnique.mockResolvedValue({
      ...device,
      sesiBerakhirPada: new Date(0),
    });
    await expect(service.session('a'.repeat(64))).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });
  it('forget is idempotent for unknown cookies', async () => {
    table.findUnique.mockResolvedValue(null);
    await expect(service.forget('a'.repeat(64))).resolves.toEqual({ ok: true });
    expect(table.updateMany).not.toHaveBeenCalled();
  });
  it('forget with an old credential cannot disconnect a concurrent rotated session', async () => {
    table.updateMany.mockResolvedValue({ count: 0 });
    await expect(service.forget('a'.repeat(64))).resolves.toEqual({ ok: true });
    expect(revoke).not.toHaveBeenCalled();
  });
  it('cookie parser rejects malformed or duplicated credentials', () => {
    expect(cookieToken('queueb_display=bad')).toBeUndefined();
    expect(
      cookieToken(
        `queueb_display=${'a'.repeat(64)}; queueb_display=${'b'.repeat(64)}`,
      ),
    ).toBeUndefined();
    expect(
      cookieToken(`other=1; queueb_display=${'a'.repeat(64)}`),
    ).toHaveLength(64);
  });
  it('untrusted browser origin is rejected before mutation', () => {
    expect(() =>
      checkDisplayOrigin({
        headers: { origin: 'https://evil.invalid' },
      } as Request),
    ).toThrow();
    expect(() => checkDisplayOrigin({ headers: {} } as Request)).not.toThrow();
  });
  it('sets HttpOnly Strict cookie, no Domain and no token response body', () => {
    const cookie = jest.fn();
    displayCookie({ cookie } as unknown as Response, 'value');
    expect(cookie.mock.calls[0][2]).toMatchObject({
      httpOnly: true,
      sameSite: 'strict',
      path: '/',
    });
    expect(cookie.mock.calls[0][2].domain).toBeUndefined();
  });
});
