import { INestApplication } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { Test } from '@nestjs/testing';
import { io } from 'socket.io-client';
import type { Socket as ClientSocket } from 'socket.io-client';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';

import { JwtStrategy } from '../src/auth/jwt.strategy';
import { PeranPengguna } from '../src/generated/prisma/client';
import { RealtimeGateway } from '../src/realtime/realtime.gateway';
import { RealtimeRoomAccessService } from '../src/realtime/realtime-room-access.service';

/** E2E transport Socket.IO asli, dependency JWT/database dimock secara terisolasi. */
describe('Realtime namespace /queue (e2e)', () => {
  const layananId = '8d157b00-3412-4a99-b999-e253b4456420';
  const penggunaId = '69bd8820-b911-4ce7-90c8-7107faf7ad11';
  let app: INestApplication;
  let alamat: string;
  let klien: ClientSocket | undefined;
  const verifyAsync = jest.fn();
  const validate = jest.fn();
  const periksa = jest.fn();

  beforeAll(async () => {
    const module = await Test.createTestingModule({
      providers: [
        RealtimeGateway,
        { provide: JwtService, useValue: { verifyAsync } },
        {
          provide: ConfigService,
          useValue: { getOrThrow: () => 'secret-access-uji' },
        },
        { provide: JwtStrategy, useValue: { validate } },
        { provide: RealtimeRoomAccessService, useValue: { periksa } },
      ],
    }).compile();
    app = module.createNestApplication();
    await app.listen(0, '127.0.0.1');
    const server = app.getHttpServer() as Server;
    const port = (server.address() as AddressInfo).port;
    alamat = `http://127.0.0.1:${port}/queue`;
  });

  beforeEach(() => {
    jest.clearAllMocks();
    verifyAsync.mockResolvedValue({
      sub: penggunaId,
      sid: 'sesi-uji',
      exp: Math.floor(Date.now() / 1000) + 3600,
    });
    validate.mockResolvedValue({
      id: penggunaId,
      peran: PeranPengguna.PETUGAS,
    });
    periksa.mockResolvedValue('ALLOWED');
  });

  afterEach(() => {
    klien?.disconnect();
    klien = undefined;
  });

  afterAll(async () => {
    await app.close();
  });

  function buatKlien(token?: string): ClientSocket {
    klien = io(alamat, {
      autoConnect: false,
      reconnection: false,
      transports: ['websocket'],
      timeout: 2000,
      auth: token === undefined ? {} : { token },
    });
    return klien;
  }

  function tungguKoneksi(client: ClientSocket): Promise<string> {
    return new Promise((resolve) => {
      client.once('connect', () => resolve('connected'));
      client.once('connect_error', (error: Error) => resolve(error.message));
      client.connect();
    });
  }

  it('menolak koneksi nyata tanpa JWT', async () => {
    expect(await tungguKoneksi(buatKlien())).toBe('UNAUTHORIZED');
  });

  it('menerima JWT dan mengizinkan join layanan yang sah serta leave', async () => {
    const client = buatKlien('access-token-uji');
    expect(await tungguKoneksi(client)).toBe('connected');
    const join = await client
      .timeout(2000)
      .emitWithAck('queue:join', { layananId });
    expect(join).toEqual({ ok: true, layananId });
    expect(periksa).toHaveBeenCalledTimes(1);
    const leave = await client
      .timeout(2000)
      .emitWithAck('queue:leave', { layananId });
    expect(leave).toEqual({ ok: true, layananId });
  });

  it('menolak join layanan tanpa penugasan melalui jaringan', async () => {
    periksa.mockResolvedValue('FORBIDDEN');
    const client = buatKlien('access-token-uji');
    expect(await tungguKoneksi(client)).toBe('connected');
    const balasan = await client
      .timeout(2000)
      .emitWithAck('queue:join', { layananId });
    expect(balasan).toEqual({ ok: false, kode: 'FORBIDDEN' });
  });

  it('menolak identitas USER saat handshake nyata', async () => {
    validate.mockResolvedValue({ id: penggunaId, peran: PeranPengguna.USER });
    expect(await tungguKoneksi(buatKlien('access-token-uji'))).toBe(
      'UNAUTHORIZED',
    );
  });
});
