import { type INestApplication } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { Test } from '@nestjs/testing';
import type { Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { io, type Socket } from 'socket.io-client';
import { JwtStrategy } from '../src/auth/jwt.strategy';
import { PrismaService } from '../src/prisma/prisma.service';
import { PatientRealtimeGateway } from '../src/realtime/patient-realtime.gateway';

/** Real Socket.IO transport; no database writes. DB/JWT doubles are explicit. */
describe('Patient realtime (transport e2e)', () => {
  let app: INestApplication, url: string, gateway: PatientRealtimeGateway;
  const clients: Socket[] = [];
  const verifyAsync = jest.fn(),
    validate = jest.fn(),
    findMany = jest.fn();
  beforeAll(async () => {
    const module = await Test.createTestingModule({
      providers: [
        PatientRealtimeGateway,
        { provide: JwtService, useValue: { verifyAsync } },
        { provide: JwtStrategy, useValue: { validate } },
        {
          provide: ConfigService,
          useValue: { getOrThrow: () => 'test-only-secret' },
        },
        { provide: PrismaService, useValue: { sesiPengguna: { findMany } } },
      ],
    }).compile();
    app = module.createNestApplication();
    await app.listen(0, '127.0.0.1');
    url = `http://127.0.0.1:${((app.getHttpServer() as Server).address() as AddressInfo).port}/patient`;
    gateway = app.get(PatientRealtimeGateway);
  });
  beforeEach(() => {
    jest.clearAllMocks();
    verifyAsync.mockImplementation((token: string) =>
      Promise.resolve({
        sub: token,
        sid: `session-${token}`,
        exp: Math.floor(Date.now() / 1000) + 3600,
      }),
    );
    validate.mockImplementation((p: { sub: string }) =>
      Promise.resolve({ id: p.sub, peran: 'USER' }),
    );
    findMany.mockResolvedValue([
      { id: 'session-a', penggunaId: 'a' },
      { id: 'session-b', penggunaId: 'b' },
    ]);
  });
  afterEach(() => {
    for (const c of clients.splice(0)) c.disconnect();
  });
  afterAll(async () => {
    await app.close();
  });
  function client(token?: string) {
    const c = io(url, {
      autoConnect: false,
      reconnection: false,
      transports: ['websocket'],
      auth: token ? { token, penggunaId: 'forged', tiketId: 'other' } : {},
    });
    clients.push(c);
    return c;
  }
  function connect(c: Socket): Promise<string> {
    return new Promise((resolve) => {
      c.once('patient:ready', () => resolve('ready'));
      c.once('connect_error', (e) => resolve(e.message));
      c.connect();
    });
  }
  it('mewajibkan access JWT dan menolak ADMIN/PETUGAS/token rusak atau kedaluwarsa', async () => {
    expect(await connect(client())).toBe('UNAUTHORIZED');
    for (const role of ['ADMIN', 'PETUGAS']) {
      validate.mockResolvedValueOnce({ id: 'a', peran: role });
      expect(await connect(client('a'))).toBe('UNAUTHORIZED');
    }
    verifyAsync.mockRejectedValueOnce(new Error('invalid signature'));
    expect(await connect(client('bad'))).toBe('UNAUTHORIZED');
    verifyAsync.mockResolvedValueOnce({ sub: 'a', sid: 'session-a', exp: 1 });
    expect(await connect(client('a'))).toBe('UNAUTHORIZED');
    verifyAsync.mockResolvedValueOnce({
      sub: 'a',
      sid: 'session-a',
      exp: Math.floor(Date.now() / 1000) + 3600,
      type: 'refresh',
    });
    expect(await connect(client('a'))).toBe('UNAUTHORIZED');
  });
  it('invalidasi tiket hanya diterima pemilik, tanpa data pribadi dan tanpa join room', async () => {
    const a = client('a'),
      b = client('b');
    expect(await connect(a)).toBe('ready');
    expect(await connect(b)).toBe('ready');
    const foreign = jest.fn();
    b.on('patient:updated', foreign);
    // Client-supplied identities and forged subscribe events cannot alter scope.
    b.emit('patient:join', { penggunaId: 'a', tiketId: 'private-ticket' });
    const event = new Promise<Record<string, unknown>>((resolve) =>
      a.once('patient:updated', resolve),
    );
    await gateway.invalidate('TIKET', 'a');
    expect(Object.keys(await event).sort()).toEqual([
      'eventId',
      'jenis',
      'terjadiPada',
      'versiSkema',
    ]);
    await new Promise((resolve) => setTimeout(resolve, 75));
    expect(foreign).not.toHaveBeenCalled();
    expect(findMany).toHaveBeenCalledTimes(1);
    expect(findMany.mock.calls[0][0].where).toMatchObject({
      dicabutPada: null,
      pengguna: { aktif: true, peran: 'USER' },
    });
  });
  it('katalog diterima kedua USER terautentikasi tanpa payload master', async () => {
    const a = client('a'),
      b = client('b');
    await connect(a);
    await connect(b);
    const events = [a, b].map(
      (c) => new Promise((resolve) => c.once('patient:updated', resolve)),
    );
    await gateway.invalidate('KATALOG');
    for (const e of await Promise.all(events))
      expect(e).toMatchObject({ versiSkema: 1, jenis: 'KATALOG' });
  });
  it('sesi dicabut/role berubah ditolak sebelum event dan koneksi diputus', async () => {
    const a = client('a');
    await connect(a);
    findMany.mockResolvedValue([]);
    const event = jest.fn();
    a.on('patient:updated', event);
    const disconnected = new Promise((resolve) =>
      a.once('disconnect', resolve),
    );
    await gateway.invalidate('TIKET', 'a');
    await disconnected;
    expect(event).not.toHaveBeenCalled();
  });
  it('database bermasalah menahan event dan memutus sesi secara fail closed', async () => {
    const a = client('a');
    await connect(a);
    findMany.mockRejectedValue(new Error('offline'));
    const event = jest.fn();
    a.on('patient:updated', event);
    const disconnected = new Promise((resolve) =>
      a.once('disconnect', resolve),
    );
    await gateway.invalidate('KATALOG');
    await disconnected;
    expect(event).not.toHaveBeenCalled();
  });
});
