import { randomUUID } from 'node:crypto';
import { ThrottlerStorageService, ThrottlerStorage } from '@nestjs/throttler';
import { Test } from '@nestjs/testing';
import type { INestApplication } from '@nestjs/common';
import type { Server } from 'node:http';
import request from 'supertest';
import { io, type Socket } from 'socket.io-client';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/configure-app';
import { PrismaService } from '../src/prisma/prisma.service';
import { DisplayRealtimeGateway } from '../src/realtime/display-realtime.gateway';
import { PasswordService } from '../src/auth/password.service';

describe('Display pairing (isolated e2e)', () => {
  let app: INestApplication, prisma: PrismaService, server: Server;
  let adminToken: string,
    userToken: string,
    clinic: string,
    otherClinic: string;
  const users: string[] = [],
    devices: string[] = [];
  const sockets: Socket[] = [];
  const unique = randomUUID();
  const base = '/api/v1';
  const admin = () => ({ Authorization: `Bearer ${adminToken}` });
  const event = <T>(socket: Socket, name: string): Promise<T> =>
    new Promise((resolve, reject) => {
      const timeout = setTimeout(
        () => reject(new Error(`Socket ${name} timeout`)),
        4000,
      );
      socket.once(name, (value: T) => {
        clearTimeout(timeout);
        resolve(value);
      });
    });
  async function createDevice(layananId = clinic) {
    const r = await request(server)
      .post(`${base}/perangkat-display`)
      .set(admin())
      .send({ nama: 'TV Ruang Tunggu', layananId })
      .expect(201);
    devices.push(r.body.id as string);
    return r.body.id as string;
  }
  async function code(id: string) {
    const r = await request(server)
      .post(`${base}/perangkat-display/${id}/aktivasi`)
      .set(admin())
      .send({})
      .expect(200);
    return r.body.kode as string;
  }
  async function pair(kode: string) {
    const r = await request(server)
      .post(`${base}/display/pairing`)
      .send({ kode })
      .expect(200);
    const cookies = r.headers['set-cookie'] as unknown as string[];
    expect(cookies[0].includes('HttpOnly')).toBe(true);
    expect(cookies[0].includes('SameSite=Strict')).toBe(true);
    expect(Object.keys(r.body).some((k) => /token|hash|kode/i.test(k))).toBe(
      false,
    );
    return cookies[0].split(';')[0];
  }
  beforeAll(async () => {
    const target = new URL(process.env.DATABASE_URL ?? 'http://invalid');
    if (
      target.hostname !== '127.0.0.1' ||
      target.port !== '5433' ||
      target.pathname !== '/capstone_antrean_test'
    )
      throw new Error('Only explicit isolated test DB is allowed');
    const module = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = module.createNestApplication();
    configureApp(app);
    await app.listen(0, '127.0.0.1');
    prisma = app.get(PrismaService);
    server = app.getHttpServer() as Server;
    expect(
      (
        await prisma.$queryRaw<
          Array<{ db: string }>
        >`SELECT current_database() AS db`
      )[0].db,
    ).toBe('capstone_antrean_test');
    const password = `E2E-${randomUUID()}!`;
    const hash = await app.get(PasswordService).hash(password);
    for (const role of ['ADMIN', 'USER'] as const) {
      const u = await prisma.pengguna.create({
        data: {
          nama: 'Display Pairing E2E',
          email: `${role.toLowerCase()}-${unique}@test.local`,
          kataSandiHash: hash,
          peran: role,
        },
      });
      users.push(u.id);
      const login = await request(server)
        .post(`${base}/auth/login`)
        .send({ email: u.email, kataSandi: password })
        .expect(200);
      if (role === 'ADMIN') adminToken = login.body.accessToken as string;
      else userToken = login.body.accessToken as string;
    }
    for (let i = 0; i < 2; i++) {
      const c = await prisma.layanan.create({
        data: {
          kode: `PAIR${unique.slice(0, 8)}${i}`,
          nama: 'Poliklinik Pairing',
          prefixAntrean: 'P',
          durasiDasarMenit: 10,
        },
      });
      if (i === 0) clinic = c.id;
      else otherClinic = c.id;
    }
  }, 120000);
  beforeEach(() => {
    app.get<ThrottlerStorageService>(ThrottlerStorage).onApplicationShutdown();
  });
  afterAll(async () => {
    sockets.forEach((s) => s.disconnect());
    if (prisma) {
      await prisma.perangkatTampilan.deleteMany({
        where: { id: { in: devices } },
      });
      await prisma.layanan.deleteMany({
        where: { id: { in: [clinic, otherClinic].filter(Boolean) } },
      });
      await prisma.sesiPengguna.deleteMany({
        where: { penggunaId: { in: users } },
      });
      await prisma.pengguna.deleteMany({ where: { id: { in: users } } });
    }
    if (app) await app.close();
  });
  it('requires ADMIN and rejects unknown fields', async () => {
    await request(server).get(`${base}/perangkat-display`).expect(401);
    await request(server)
      .get(`${base}/perangkat-display`)
      .auth(userToken, { type: 'bearer' })
      .expect(403);
    await request(server)
      .post(`${base}/perangkat-display`)
      .set(admin())
      .send({ nama: 'TV', layananId: clinic, tokenHash: 'forbidden' })
      .expect(400);
  });
  it('lists several devices for one clinic without credentials', async () => {
    await createDevice();
    await createDevice();
    const r = await request(server)
      .get(`${base}/perangkat-display`)
      .set(admin())
      .expect(200);
    expect(
      r.body.filter((d: { layananId: string }) => d.layananId === clinic)
        .length,
    ).toBe(2);
    expect(JSON.stringify(r.body)).not.toMatch(
      /tokenHash|kodeAktivasiHash|kodeBerlakuHingga/,
    );
  });
  it('pairs once, restores HttpOnly session and isolates snapshot by clinic', async () => {
    const id = await createDevice();
    const kode = await code(id);
    const cookie = await pair(kode);
    await request(server)
      .post(`${base}/display/pairing`)
      .send({ kode })
      .expect(410);
    const sesi = await request(server)
      .get(`${base}/display/sesi`)
      .set('Cookie', cookie)
      .expect(200);
    expect(sesi.body.layananId).toBe(clinic);
    await request(server)
      .get(`${base}/display/${clinic}/snapshot`)
      .set('Cookie', cookie)
      .expect(200);
    await request(server)
      .get(`${base}/display/${otherClinic}/snapshot`)
      .set('Cookie', cookie)
      .expect(403);
    expect(
      (await prisma.perangkatTampilan.findUniqueOrThrow({ where: { id } }))
        .terakhirAktifPada,
    ).not.toBeNull();
  });
  it('only one concurrent pairing wins', async () => {
    const kode = await code(await createDevice());
    const results = await Promise.all(
      [1, 2].map(() =>
        request(server).post(`${base}/display/pairing`).send({ kode }),
      ),
    );
    expect(results.filter((r) => r.status === 200)).toHaveLength(1);
    expect([409, 410]).toContain(results.find((r) => r.status !== 200)?.status);
  });
  it('rejects expired code and prevents cross-origin claim without consuming it', async () => {
    const id = await createDevice();
    const kode = await code(id);
    await request(server)
      .post(`${base}/display/pairing`)
      .set('Origin', 'https://evil.invalid')
      .send({ kode })
      .expect(403);
    await prisma.perangkatTampilan.update({
      where: { id },
      data: { kodeBerlakuHingga: new Date(0) },
    });
    await request(server)
      .post(`${base}/display/pairing`)
      .send({ kode })
      .expect(410);
  });
  it('rotation revokes cookies and old codes, deactivation revokes active socket immediately', async () => {
    const id = await createDevice();
    const first = await code(id);
    const oldCookie = await pair(first);
    const second = await code(id);
    await request(server)
      .get(`${base}/display/sesi`)
      .set('Cookie', oldCookie)
      .expect(401);
    await request(server)
      .get(`${base}/display/${clinic}/snapshot`)
      .set('Cookie', oldCookie)
      .expect(401);
    const cookie = await pair(second);
    const port = (server.address() as { port: number }).port;
    const socket = io(`http://127.0.0.1:${port}/display`, {
      transports: ['websocket'],
      autoConnect: false,
      reconnection: false,
      auth: { layananId: clinic },
      extraHeaders: { Cookie: cookie },
    });
    sockets.push(socket);
    const ready = event(socket, 'display:ready');
    socket.connect();
    await ready;
    const disconnected = event(socket, 'disconnect');
    await request(server)
      .post(`${base}/perangkat-display/${id}/nonaktifkan`)
      .set(admin())
      .expect(200);
    await disconnected;
    await request(server)
      .get(`${base}/display/sesi`)
      .set('Cookie', cookie)
      .expect(401);
    await request(server)
      .get(`${base}/display/${clinic}/snapshot`)
      .set('Cookie', cookie)
      .expect(401);
    const revoked = io(`http://127.0.0.1:${port}/display`, {
      transports: ['websocket'],
      autoConnect: false,
      reconnection: false,
      auth: { layananId: clinic },
      extraHeaders: { Cookie: cookie },
    });
    sockets.push(revoked);
    const denied = event(revoked, 'connect_error');
    revoked.connect();
    await denied;
  });
  it('safe forget clears cookie and revokes its credential', async () => {
    const cookie = await pair(await code(await createDevice()));
    const r = await request(server)
      .post(`${base}/display/putuskan`)
      .set('Cookie', cookie)
      .send({})
      .expect(200);
    expect((r.headers['set-cookie'] as unknown as string[])[0]).toContain(
      'Max-Age=0',
    );
    await request(server)
      .get(`${base}/display/sesi`)
      .set('Cookie', cookie)
      .expect(401);
  });
  it('server expiry applies even if credential is sent as legacy token header', async () => {
    const id = await createDevice();
    const cookie = await pair(await code(id));
    await prisma.perangkatTampilan.update({
      where: { id },
      data: { sesiBerakhirPada: new Date(0) },
    });
    await request(server)
      .get(`${base}/display/sesi`)
      .set('Cookie', cookie)
      .expect(401);
    await request(server)
      .get(`${base}/display/${clinic}/snapshot`)
      .set('x-display-token', cookie.split('=')[1])
      .expect(401);
  });
  it('limits repeated activation attempts (real Throttler storage)', async () => {
    // Separate client address remains impossible to spoof: use the real per-route
    // counter, already hit by earlier scenarios, to prove the configured ceiling.
    const results = [];
    for (let i = 0; i < 6; i++)
      results.push(
        (
          await request(server)
            .post(`${base}/display/pairing`)
            .send({ kode: '000000000000' })
        ).status,
      );
    expect(results).toContain(429);
  });
  it('mereproduksi cookie legacy satu profil yang menimpa scope monitor pertama', async () => {
    const a = await createDevice(); const b = await createDevice(otherClinic);
    const cookieA = await pair(await code(a));
    const cookieB = await pair(await code(b));
    expect(cookieA.split('=')[0]).toBe(cookieB.split('=')[0]);
    // Browser cookie jar retains only the last value for the same name/path.
    await request(server).get(base + '/display/' + clinic + '/snapshot').set('Cookie', cookieB).expect(403);
    expect((await request(server).get(base + '/display/sesi').set('Cookie', cookieB).expect(200)).body.id).toBe(b);
  });

  it('mengisolasi tiga monitor, dua poli, rotasi, reconnect, dan pencabutan dalam satu cookie jar', async () => {
    const ids = [await createDevice(), await createDevice(otherClinic), await createDevice()];
    const clinics = [clinic, otherClinic, clinic];
    const jar = new Map<string, string>();
    const cookies = () => [...jar.values()].join('; ');
    const activate = async (id: string) => {
      const r = await request(server).post(base + '/display/pairing').send({ kode: await code(id), isolasiSesi: true }).expect(200);
      const set = (r.headers['set-cookie'] as unknown as string[])[0];
      expect(set).toContain('HttpOnly'); expect(set).toContain('SameSite=Strict');
      const value = set.split(';')[0];
      expect(value.startsWith('queueb_display_' + id + '=')).toBe(true);
      jar.set(id, value);
    };
    for (const id of ids) await activate(id);
    for (let i = 0; i < ids.length; i++) {
      const r = await request(server).get(base + '/display/sesi').set('Cookie', cookies()).set('x-display-device-id', ids[i]).expect(200);
      expect(r.body.id).toBe(ids[i]); expect(r.body.layananId).toBe(clinics[i]);
      await request(server).get(base + '/display/' + clinics[i] + '/snapshot').set('Cookie', cookies()).set('x-display-device-id', ids[i]).expect(200);
    }
    await request(server).get(base + '/display/' + otherClinic + '/snapshot').set('Cookie', cookies()).set('x-display-device-id', ids[0]).expect(403);
    await request(server).get(base + '/display/sesi').set('Cookie', cookies()).set('x-display-device-id', randomUUID()).expect(401);
    // Possession of A's cookie does not select B, even on the same clinic.
    await request(server).get(base + '/display/sesi').set('Cookie', jar.get(ids[0])!).set('x-display-device-id', ids[2]).expect(401);
    const forged = 'queueb_display_' + ids[2] + '=' + jar.get(ids[0])!.split('=')[1];
    await request(server).get(base + '/display/sesi').set('Cookie', forged).set('x-display-device-id', ids[2]).expect(401);
    await request(server).get(base + '/display/' + clinic + '/snapshot').set('Cookie', forged).set('x-display-device-id', ids[2]).expect(401);
    const port = (server.address() as { port: number }).port;
    const forgedSocket = io('http://127.0.0.1:' + port + '/display', { transports: ['websocket'], autoConnect: false, reconnection: false, auth: { layananId: clinic, perangkatId: ids[2] }, extraHeaders: { Cookie: forged } });
    sockets.push(forgedSocket); const refused = event<Error>(forgedSocket, 'connect_error'); forgedSocket.connect();
    expect((await refused).message).toBe('UNAUTHORIZED');
    const connect = async (i: number) => {
      const socket = io('http://127.0.0.1:' + port + '/display', { transports: ['websocket'], autoConnect: false, reconnection: false, auth: { layananId: clinics[i], perangkatId: ids[i] }, extraHeaders: { Cookie: cookies() } });
      sockets.push(socket); const ready = event(socket, 'display:ready'); socket.connect();
      expect(await ready).toMatchObject({ layananId: clinics[i] }); return socket;
    };
    let a = await connect(0); const b = await connect(1); const c = await connect(2);
    const receivedByB: unknown[] = []; b.on('display:updated', (v: unknown) => receivedByB.push(v));
    for (const aksi of ['CALL', 'RECALL', 'SKIP', 'REQUEUE', 'START', 'COMPLETE'] as const) {
      const nextA = event(a, 'display:updated'); const nextC = event(c, 'display:updated');
      await app.get(DisplayRealtimeGateway).broadcastPerubahan({ versiSkema: 1, eventId: randomUUID(), terjadiPada: new Date().toISOString(), layananId: clinic, tiketId: randomUUID(), nomorAntrean: 'P-001', status: 'MENUNGGU', aksi });
      expect(await nextA).toMatchObject({ layananId: clinic, aksi }); expect(await nextC).toMatchObject({ layananId: clinic, aksi });
    }
    expect(receivedByB).toEqual([]);
    a.disconnect(); a = await connect(0); // Reload/reconnect only A.
    const disconnected = event(a, 'disconnect'); await activate(ids[0]); await disconnected;
    expect(b.connected).toBe(true); expect(c.connected).toBe(true);
    a = await connect(0);
    const revoked = event(a, 'disconnect');
    await request(server).post(base + '/perangkat-display/' + ids[0] + '/nonaktifkan').set(admin()).expect(200);
    await revoked; expect(b.connected).toBe(true); expect(c.connected).toBe(true);
    const disabled = await request(server).get(base + '/display/sesi').set('Cookie', cookies()).set('x-display-device-id', ids[0]).expect(401);
    expect(disabled.body.message).toContain('dinonaktifkan');
    const forget = await request(server).post(base + '/display/putuskan').set('Cookie', cookies()).set('x-display-device-id', ids[2]).send({}).expect(200);
    expect((forget.headers['set-cookie'] as unknown as string[])[0]).toContain('queueb_display_' + ids[2] + '=');
    expect((await request(server).get(base + '/display/sesi').set('Cookie', cookies()).set('x-display-device-id', ids[1]).expect(200)).body.id).toBe(ids[1]);
  });
});
