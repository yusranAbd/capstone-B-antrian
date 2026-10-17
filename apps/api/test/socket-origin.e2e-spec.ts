import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import type { INestApplication } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Test } from '@nestjs/testing';
import { io, type Socket as ClientSocket } from 'socket.io-client';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/configure-app';

describe('Socket.IO Origin Security (e2e)', () => {
  let app: INestApplication | undefined;
  const daftarSocket: ClientSocket[] = [];
  let originSah = '';
  let alamatServer = '';

  beforeAll(async () => {
    const raw = process.env.DATABASE_URL;
    if (!raw) throw new Error('DATABASE_URL pengujian wajib tersedia');
    const url = new URL(raw);
    if (
      !['localhost', '127.0.0.1'].includes(url.hostname) ||
      url.port !== '5433' ||
      url.pathname !== '/capstone_antrean_test'
    ) throw new Error('E2E hanya boleh menggunakan capstone_antrean_test localhost:5433');

    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    configureApp(app);
    await app.listen(0, '127.0.0.1');
    const server = app.getHttpServer() as Server;
    const port = (server.address() as AddressInfo).port;
    alamatServer = `http://127.0.0.1:${port}`;
    const daftar = app.get(ConfigService).get<string[]>('CORS_ALLOWED_ORIGINS') ?? [];
    if (!daftar[0]) throw new Error('CORS_ALLOWED_ORIGINS belum dikonfigurasi');
    originSah = daftar[0];
  });

  afterAll(async () => {
    for (const client of daftarSocket) client.disconnect();
    await app?.close();
  });

  function cobaKoneksi(namespace: 'queue' | 'display' | 'patient', origin: string): Promise<string> {
    return new Promise((resolve, reject) => {
      const socket = io(`${alamatServer}/${namespace}`, {
        transports: ['websocket'],
        reconnection: false,
        forceNew: true,
        autoConnect: false,
        timeout: 4000,
        extraHeaders: { Origin: origin },
        auth: { token: 'token-uji-tidak-valid', layananId: '00000000-0000-4000-8000-000000000001' },
      });
      daftarSocket.push(socket);
      const timeout = setTimeout(() => reject(new Error('Timeout koneksi Socket.IO')), 5000);
      socket.once('connect_error', (error: Error) => {
        clearTimeout(timeout);
        resolve(error.message);
      });
      socket.once('connect', () => {
        clearTimeout(timeout);
        reject(new Error('Koneksi dengan token tidak sah seharusnya ditolak'));
      });
      socket.connect();
    });
  }

  it('menolak origin asing sebelum autentikasi pada namespace /queue', async () => {
    await expect(cobaKoneksi('queue', 'https://asing.example.invalid'))
      .resolves.toBe('ORIGIN_NOT_ALLOWED');
  });
  it('menolak origin asing sebelum autentikasi pada namespace /patient', async () => {
    await expect(cobaKoneksi('patient', 'https://asing.example.invalid')).resolves.toBe('ORIGIN_NOT_ALLOWED');
  });

  it('menolak origin asing sebelum autentikasi pada namespace /display', async () => {
    await expect(cobaKoneksi('display', 'https://asing.example.invalid'))
      .resolves.toBe('ORIGIN_NOT_ALLOWED');
  });

  it('origin sah tetap harus melewati autentikasi JWT atau token perangkat', async () => {
    await expect(cobaKoneksi('queue', originSah)).resolves.toBe('UNAUTHORIZED');
  });
});
