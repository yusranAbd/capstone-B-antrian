import { createHash, randomBytes, randomUUID } from 'node:crypto';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';

import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { ThrottlerStorage } from '@nestjs/throttler';
import { io, type Socket as ClientSocket } from 'socket.io-client';
import request from 'supertest';

import { AppModule } from '../src/app.module';
import { configureApp } from '../src/configure-app';
import { StatusTiket } from '../src/generated/prisma/client';
import { PrismaService } from '../src/prisma/prisma.service';
import type { JenisPerubahanAntrean } from '../src/realtime/realtime-events.types';
import { RealtimeBroadcastService } from '../src/realtime/realtime-broadcast.service';
import type { DisplaySnapshot } from '../src/display/display-snapshot.types';
import type { DisplayReadyEvent, DisplayUpdatedEvent } from '../src/realtime/display-realtime.types';

/** E2E ini hanya boleh berjalan pada database pengujian lokal. */
describe('Public Display Socket.IO (e2e)', () => {
  const token = randomBytes(32).toString('hex');
  const tokenHash = createHash('sha256').update(token).digest('hex');
  const unik = randomUUID().replace(/-/g, '').slice(0, 8).toUpperCase();
  const sockets: ClientSocket[] = [];
  let app: INestApplication | undefined;
  let prisma: PrismaService | undefined;
  let penggunaId = '';
  let layananId = '';
  let loketId = '';
  let perangkatId = '';
  let tiketId = '';

  function db(): PrismaService {
    if (!prisma) throw new Error('Prisma testing tidak tersedia');
    return prisma;
  }
  function server(): Server {
    if (!app) throw new Error('Server tidak tersedia');
    return app.getHttpServer() as Server;
  }
  function asal(): string {
    const alamat = server().address() as AddressInfo;
    return `http://127.0.0.1:${alamat.port}`;
  }
  function wajibDbTestingLokal(): void {
    const raw = process.env.DATABASE_URL;
    if (!raw) throw new Error('DATABASE_URL testing wajib ada');
    const url = new URL(raw);
    if (
      url.pathname !== '/capstone_antrean_test' ||
      !['localhost', '127.0.0.1'].includes(url.hostname) ||
      url.port !== '5433'
    ) throw new Error('E2E Display wajib menggunakan capstone_antrean_test localhost:5433');
    if ((process.env.SERVICE_TIME_ZONE ?? 'Asia/Jakarta') !== 'Asia/Jakarta') {
      throw new Error('SERVICE_TIME_ZONE harus Asia/Jakarta');
    }
  }
  function tanggalLayanan(): Date {
    const bagian = new Intl.DateTimeFormat('en-GB', {
      timeZone: 'Asia/Jakarta', year: 'numeric', month: '2-digit', day: '2-digit',
    }).formatToParts(new Date());
    const ambil = (jenis: string): string => bagian.find((i) => i.type === jenis)?.value ?? '';
    return new Date(`${ambil('year')}-${ambil('month')}-${ambil('day')}T00:00:00.000Z`);
  }
  function buatSocket(authToken = token, idLayanan = layananId): ClientSocket {
    const socket = io(`${asal()}/display`, {
      transports: ['websocket'],
      auth: { token: authToken, layananId: idLayanan },
      reconnection: false,
      autoConnect: false,
      forceNew: true,
      timeout: 5000,
    });
    sockets.push(socket);
    return socket;
  }
  function tungguSiap(socket: ClientSocket): Promise<DisplayReadyEvent> {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Timeout display:ready')), 6000);
      socket.once('display:ready', (data: DisplayReadyEvent) => {
        clearTimeout(timeout);
        resolve(data);
      });
      socket.once('connect_error', (error: Error) => {
        clearTimeout(timeout);
        reject(error);
      });
      socket.connect();
    });
  }
  function tungguEvent(socket: ClientSocket): Promise<DisplayUpdatedEvent> {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Timeout display:updated')), 6000);
      socket.once('display:updated', (data: DisplayUpdatedEvent) => {
        clearTimeout(timeout);
        resolve(data);
      });
    });
  }
  async function kirim(aksi: JenisPerubahanAntrean, untukLayanan = layananId) {
    if (!app) throw new Error('Aplikasi belum berjalan');
    await app.get(RealtimeBroadcastService).kirim({
      aksi, layananId: untukLayanan, tiketId,
      nomorAntrean: 'D-025', status: 'DIPANGGIL', loketId,
    });
  }

  beforeAll(async () => {
    wajibDbTestingLokal();
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(ThrottlerStorage)
      .useValue({ increment: () => Promise.resolve({
        totalHits: 1, timeToExpire: 60000, isBlocked: false, timeToBlockExpire: 0,
      }) }).compile();
    app = moduleRef.createNestApplication();
    configureApp(app);
    await app.listen(0, '127.0.0.1');
    prisma = app.get(PrismaService);
    const hasil = await db().$queryRaw<Array<{ nama: string }>>`
      SELECT current_database() AS "nama"`;
    expect(hasil[0]?.nama).toBe('capstone_antrean_test');

    const pengguna = await db().pengguna.create({ data: {
      nama: 'Pemilik tiket uji display', email: `dreal-${randomUUID()}@test.local`,
      kataSandiHash: 'fixture', peran: 'USER',
    } });
    penggunaId = pengguna.id;
    const layanan = await db().layanan.create({ data: {
      kode: `DR${unik}`, nama: 'Layanan Realtime Display',
      prefixAntrean: 'D', durasiDasarMenit: 10, aktif: true,
    } });
    layananId = layanan.id;
    const loket = await db().loket.create({ data: {
      layananId, kode: '03', nama: 'Loket 03', aktif: true,
    } });
    loketId = loket.id;
    const perangkat = await db().perangkatTampilan.create({ data: {
      layananId, nama: 'Display Realtime E2E', aktif: true, tokenHash,
    } });
    perangkatId = perangkat.id;
    const tiket = await db().tiketAntrean.create({ data: {
      penggunaId, layananId, loketId, tanggalAntrean: tanggalLayanan(),
      nomorUrut: 25, kodeTiket: `TR${randomBytes(12).toString('hex').toUpperCase()}`,
      status: StatusTiket.DIPANGGIL, urutanMasukAntrean: 1,
      checkInPada: new Date(), masukAntreanPada: new Date(), dipanggilPada: new Date(),
    } });
    tiketId = tiket.id;
    await db().peristiwaAntrean.create({ data: {
      tiketAntreanId: tiketId, tipe: 'CALL',
      statusSebelum: StatusTiket.MENUNGGU, statusSesudah: StatusTiket.DIPANGGIL,
    } });
  }, 120000);

  afterEach(async () => {
    for (const socket of sockets.splice(0)) socket.disconnect();
    if (prisma && perangkatId) await db().perangkatTampilan.update({
      where: { id: perangkatId }, data: { aktif: true, tokenHash },
    });
  });

  afterAll(async () => {
    try {
      if (prisma) {
        if (tiketId) await db().peristiwaAntrean.deleteMany({ where: { tiketAntreanId: tiketId } });
        if (tiketId) await db().tiketAntrean.deleteMany({ where: { id: tiketId } });
        if (perangkatId) await db().perangkatTampilan.deleteMany({ where: { id: perangkatId } });
        if (loketId) await db().loket.deleteMany({ where: { id: loketId } });
        if (layananId) await db().layanan.deleteMany({ where: { id: layananId } });
        if (penggunaId) await db().pengguna.deleteMany({ where: { id: penggunaId } });
      }
    } finally {
      if (app) await app.close();
    }
  }, 60000);

  it('perangkat sah menerima display:ready, sinyal CALL, dan TTS dari REST', async () => {
    const socket = buatSocket();
    expect(await tungguSiap(socket)).toEqual({ versiSkema: 1, layananId });
    const terima = tungguEvent(socket);
    await kirim('CALL');
    const pesan = await terima;
    expect(pesan).toMatchObject({ aksi: 'CALL', layananId, perluPeriksaPengumuman: true });
    const serial = JSON.stringify(pesan);
    expect(serial).not.toContain(tiketId);
    expect(serial).not.toContain('D-025');
    expect(serial).not.toContain(token);
    const response = await request(server())
      .get(`/api/v1/display/${layananId}/snapshot`)
      .set('x-display-token', token)
      .expect(200);
    const snapshot = response.body as DisplaySnapshot;
    expect(snapshot.pengumumanTerakhir).toMatchObject({ aksi: 'CALL', bahasa: 'id-ID' });
  });

  it('menolak koneksi dengan token salah atau layanan berbeda', async () => {
    for (const [kunci, layanan] of [
      ['b'.repeat(64), layananId],
      [token, randomUUID()],
    ]) {
      const socket = buatSocket(kunci, layanan);
      const pesan = await new Promise<string>((resolve, reject) => {
        const timeout = setTimeout(() => reject(new Error('Timeout connect_error')), 6000);
        socket.once('connect_error', (error: Error) => {
          clearTimeout(timeout);
          resolve(error.message);
        });
        socket.connect();
      });
      expect(pesan).toBe('UNAUTHORIZED');
      socket.disconnect();
    }
  });

  it('tidak meneruskan perubahan dari layanan lain', async () => {
    const socket = buatSocket();
    await tungguSiap(socket);
    const terima = jest.fn();
    socket.on('display:updated', terima);
    await kirim('CALL', randomUUID());
    await new Promise((resolve) => setTimeout(resolve, 200));
    expect(terima).not.toHaveBeenCalled();
  });

  it('pencabutan perangkat memutus socket dan menahan event', async () => {
    const socket = buatSocket();
    await tungguSiap(socket);
    await db().perangkatTampilan.update({ where: { id: perangkatId }, data: { aktif: false } });
    const disconnect = new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Timeout disconnect')), 6000);
      socket.once('disconnect', () => { clearTimeout(timeout); resolve(); });
    });
    const menerima = jest.fn();
    socket.on('display:updated', menerima);
    await kirim('CALL');
    await disconnect;
    expect(menerima).not.toHaveBeenCalled();
  });

  it('rotasi token menghentikan koneksi yang masih memakai token lama', async () => {
    const socket = buatSocket();
    await tungguSiap(socket);
    await db().perangkatTampilan.update({
      where: { id: perangkatId }, data: { tokenHash: 'f'.repeat(64) },
    });
    const disconnect = new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Timeout rotasi')), 6000);
      socket.once('disconnect', () => { clearTimeout(timeout); resolve(); });
    });
    await kirim('RECALL');
    await disconnect;
  });
  it('seluruh perubahan operasional memicu snapshot baru; reconnect mengirim ready', async () => {
    let socket = buatSocket();
    await tungguSiap(socket);
    const cases: Array<[JenisPerubahanAntrean, StatusTiket, number]> = [
      ['REQUEUE', StatusTiket.MENUNGGU, 1], ['CALL', StatusTiket.DIPANGGIL, 0],
      ['RECALL', StatusTiket.DIPANGGIL, 0], ['SKIP', StatusTiket.DILEWATI, 0],
      ['REQUEUE', StatusTiket.MENUNGGU, 1], ['CALL', StatusTiket.DIPANGGIL, 0],
      ['START', StatusTiket.DILAYANI, 0], ['COMPLETE', StatusTiket.SELESAI, 0],
    ];
    for (const [aksi, status, total] of cases) {
      // Fixture status is committed before invalidation, as in QueueService.
      await db().tiketAntrean.update({ where: { id: tiketId }, data: { status } });
      const event = tungguEvent(socket);
      await kirim(aksi);
      const signal = await event;
      expect(signal.perluPeriksaPengumuman).toBe(aksi === 'CALL' || aksi === 'RECALL');
      expect(JSON.stringify(signal)).not.toContain('Pemilik');
      const snapshot = (await request(server()).get(`/api/v1/display/${layananId}/snapshot`)
        .set('x-display-token', token).expect(200)).body as DisplaySnapshot;
      expect(snapshot.totalMenunggu).toBe(total);
      expect(snapshot.menunggu).toHaveLength(total);
      const hasPatientRow = status === StatusTiket.MENUNGGU || status === StatusTiket.DILEWATI;
      expect(snapshot.antrianPasien).toHaveLength(hasPatientRow ? 1 : 0);
      expect(snapshot.totalAntrianPasien).toBe(hasPatientRow ? 1 : 0);
      expect(snapshot.totalDilewati).toBe(status === StatusTiket.DILEWATI ? 1 : 0);
      if (hasPatientRow) expect(snapshot.antrianPasien?.[0].status).toBe(status);
      if (total) expect(snapshot.menunggu?.[0].namaPasien).toBe('Pemilik t. u. d.');
      if (status !== StatusTiket.DIPANGGIL) expect(snapshot.pengumumanTerakhir).toBeNull();
    }
    socket.disconnect();
    socket = buatSocket();
    expect(await tungguSiap(socket)).toMatchObject({ layananId });
  });

});
