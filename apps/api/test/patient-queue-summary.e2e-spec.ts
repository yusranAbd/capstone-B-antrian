import { createHash, randomBytes, randomUUID } from 'node:crypto';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { ThrottlerStorage } from '@nestjs/throttler';
import { hash } from 'bcryptjs';
import request from 'supertest';
import { io, type Socket } from 'socket.io-client';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/configure-app';
import { HariLayanan, type StatusTiket } from '../src/generated/prisma/client';
import { waktuPelayanan } from '../src/hospital/hospital-context';
import { PrismaService } from '../src/prisma/prisma.service';
import { PatientRealtimeGateway } from '../src/realtime/patient-realtime.gateway';

describe('Patient queue summary, persisted PostgreSQL and authenticated realtime', () => {
  const unique = randomUUID().slice(0, 8),
    users: Array<{ id: string; key: string; token: string; email: string }> =
      [],
    services: string[] = [],
    rooms: string[] = [],
    tickets: string[] = [],
    sockets: Socket[] = [];
  let app: INestApplication | undefined,
    db: PrismaService | undefined,
    order = 0;
  const day = waktuPelayanan(new Date()).tanggal,
    today = new Date(day + 'T00:00:00Z');
  const server = () => app!.getHttpServer() as Server;
  const user = (key = 'a') => users.find((u) => u.key === key)!;
  const get = (id = services[0], date = day, key = 'a') =>
    request(server())
      .get('/api/v1/layanan/antrean')
      .query({ layananId: id, tanggal: date })
      .set('Authorization', 'Bearer ' + user(key).token);
  const scan = (qr: string, room = rooms[0], staff = 'staff') =>
    request(server())
      .post('/api/v1/check-in/auto-antrean')
      .set('Authorization', 'Bearer ' + user(staff).token)
      .send({ qrPayload: qr, loketId: room });
  async function ticket(
    options: {
      service?: string;
      date?: string;
      status?: StatusTiket;
      checked?: boolean;
      room?: string;
      owner?: string;
    } = {},
  ) {
    const qr = 'SQ1.' + randomBytes(32).toString('base64url');
    const row = await db!.tiketAntrean.create({
      data: {
        penggunaId: user(options.owner ?? 'a').id,
        layananId: options.service ?? services[0],
        tanggalAntrean: new Date((options.date ?? day) + 'T00:00:00Z'),
        nomorUrut: ++order,
        kodeTiket: 'PQ' + randomBytes(12).toString('hex'),
        status: options.status ?? 'DIPESAN',
        checkInPada: options.checked ? new Date() : null,
        urutanMasukAntrean: options.status === 'MENUNGGU' ? order : null,
        loketId: options.room ?? null,
        tokenQrHash: createHash('sha256').update(qr).digest('hex'),
        qrKedaluwarsaPada: new Date(Date.now() + 600000),
      },
    });
    tickets.push(row.id);
    return { id: row.id, qr };
  }
  async function client(ids: string[], date = day, key = 'a') {
    const s = io(
      `http://127.0.0.1:${(server().address() as AddressInfo).port}/patient`,
      {
        transports: ['websocket'],
        forceNew: true,
        autoConnect: false,
        auth: { token: user(key).token },
      },
    );
    sockets.push(s);
    const ready = new Promise<void>((resolve, reject) => {
      s.once('patient:ready', () => resolve());
      s.once('connect_error', reject);
    });
    s.connect();
    await ready;
    const ack = await new Promise<Record<string, unknown>>((resolve) =>
      s.emit(
        'patient:antrean:ikuti',
        { layananIds: ids, tanggalPelayanan: date },
        resolve,
      ),
    );
    expect(ack.ok).toBe(true);
    return s;
  }
  function changed(s: Socket) {
    return new Promise<Record<string, unknown>>((resolve, reject) => {
      const timer = setTimeout(
        () => reject(new Error('Queue summary invalidation missing')),
        8000,
      );
      const handler = (event: Record<string, unknown>) => {
        if (event.jenis === 'ANTREAN') {
          clearTimeout(timer);
          s.off('patient:updated', handler);
          resolve(event);
        }
      };
      s.on('patient:updated', handler);
    });
  }
  beforeAll(async () => {
    const target = new URL(process.env.DATABASE_URL ?? 'http://invalid');
    if (
      target.hostname !== '127.0.0.1' ||
      target.port !== '5433' ||
      target.pathname !== '/capstone_antrean_test' ||
      target.search
    )
      throw Error('Isolated test database required');
    const module = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(ThrottlerStorage)
      .useValue({
        increment: () =>
          Promise.resolve({
            totalHits: 1,
            timeToExpire: 60000,
            isBlocked: false,
            timeToBlockExpire: 0,
          }),
      })
      .compile();
    app = module.createNestApplication();
    configureApp(app);
    await app.listen(0, '127.0.0.1');
    db = app.get(PrismaService);
    expect(
      (
        await db!.$queryRaw<
          Array<{ db: string }>
        >`SELECT current_database() AS db`
      )[0].db,
    ).toBe('capstone_antrean_test');
    const password = 'QueueSummaryFixture123!',
      digest = await hash(password, 10);
    for (const [key, role] of [
      ['a', 'USER'],
      ['b', 'USER'],
      ['staff', 'PETUGAS'],
      ['staff2', 'PETUGAS'],
      ['admin', 'ADMIN'],
    ] as const) {
      const email = `queue-summary-${key}-${unique}@test.local`;
      const row = await db!.pengguna.create({
        data: {
          nama: `PRIVATE-${key}-${unique}`,
          email,
          kataSandiHash: digest,
          peran: role,
        },
      });
      users.push({ id: row.id, key, token: '', email });
      const login = await request(server())
        .post('/api/v1/auth/login')
        .send({ email, kataSandi: password })
        .expect(200);
      user(key).token = login.body.accessToken;
    }
    for (let i = 0; i < 2; i++) {
      const service = await db!.layanan.create({
        data: {
          kode: `PQ${i}${unique}`,
          nama: `Summary service ${i}`,
          prefixAntrean: i ? 'APT' : 'PEN',
          durasiDasarMenit: 10,
          modeReservasi: 'ANTREAN_HARIAN',
        },
      });
      services.push(service.id);
      for (let j = 0; j < (i ? 1 : 2); j++) {
        const room = await db!.loket.create({
          data: {
            layananId: service.id,
            kode: `PQ${j}${unique}`,
            nama: 'Summary room',
          },
        });
        rooms.push(room.id);
        for (const key of ['staff', 'staff2'])
          await db!.penugasanPetugas.create({
            data: {
              petugasId: user(key).id,
              loketId: room.id,
              tanggalMulai: today,
            },
          });
      }
      await db!.jadwalLayanan.createMany({
        data: Object.values(HariLayanan).map((hari) => ({
          layananId: service.id,
          hari,
          jamBuka: new Date('1970-01-01T00:00:00Z'),
          jamTutup: new Date('1970-01-01T23:59:59Z'),
          kapasitasHarian: 500,
        })),
      });
      await db!.urutanAntreanHarian.create({
        data: { layananId: service.id, tanggal: today, nomorTerakhir: 10000 },
      });
    }
  }, 30000);
  afterEach(async () => {
    jest.restoreAllMocks();
    for (const s of sockets.splice(0)) s.disconnect();
    if (db && tickets.length) {
      const ids = tickets.splice(0);
      await db!.peristiwaAntrean.deleteMany({
        where: { tiketAntreanId: { in: ids } },
      });
      await db!.tiketAntrean.deleteMany({ where: { id: { in: ids } } });
    }
  });
  afterAll(async () => {
    if (db) {
      await db!.peristiwaAntrean.deleteMany({
        where: { tiketAntrean: { layananId: { in: services } } },
      });
      await db!.tiketAntrean.deleteMany({
        where: { layananId: { in: services } },
      });
      await db!.urutanAntreanHarian.deleteMany({
        where: { layananId: { in: services } },
      });
      await db!.penugasanPetugas.deleteMany({
        where: { loketId: { in: rooms } },
      });
      await db!.jadwalLayanan.deleteMany({
        where: { layananId: { in: services } },
      });
      await db!.loket.deleteMany({ where: { id: { in: rooms } } });
      await db!.layanan.deleteMany({ where: { id: { in: services } } });
      await db!.sesiPengguna.deleteMany({
        where: { penggunaId: { in: users.map((u) => u.id) } },
      });
      await db!.pengguna.deleteMany({
        where: { id: { in: users.map((u) => u.id) } },
      });
    }
    await app?.close();
  });
  it('zero check-in is an authoritative zero with no private fields', async () => {
    const r = await get().expect(200);
    expect(r.headers['cache-control']).toBe('no-store');
    expect(r.body.layanan).toEqual([
      {
        layananId: services[0],
        totalCheckIn: 0,
        jumlahMenunggu: 0,
        sedangDilayani: [],
      },
    ]);
  });
  it('two independent users receive one committed check-in invalidation and authoritative total', async () => {
    const a = await client([services[0]]),
      b = await client([services[0]], day, 'b'),
      t = await ticket();
    const events = [changed(a), changed(b)];
    await scan(t.qr).expect(200);
    for (const event of await Promise.all(events)) {
      expect(event).toMatchObject({
        versiSkema: 1,
        jenis: 'ANTREAN',
        layananId: services[0],
        tanggalPelayanan: day,
      });
      expect(Object.keys(event).sort()).toEqual([
        'eventId',
        'jenis',
        'layananId',
        'tanggalPelayanan',
        'terjadiPada',
        'versiSkema',
      ]);
    }
    expect((await get().expect(200)).body.layanan[0]).toMatchObject({
      totalCheckIn: 1,
      jumlahMenunggu: 1,
    });
    expect(
      (await get(services[0], day, 'b').expect(200)).body.layanan[0]
        .totalCheckIn,
    ).toBe(1);
  });
  it('repeated scan never double counts or duplicates CHECK_IN audit', async () => {
    const t = await ticket();
    await scan(t.qr).expect(200);
    const repeated = await scan(t.qr).expect(200);
    expect(repeated.body.sudahTerdaftar).toBe(true);
    expect((await get().expect(200)).body.layanan[0].totalCheckIn).toBe(1);
    expect(
      await db!.peristiwaAntrean.count({
        where: { tiketAntreanId: t.id, tipe: 'CHECK_IN' },
      }),
    ).toBe(1);
  });
  it('invalid/failed check-in emits no success and leaves total unchanged', async () => {
    const s = await client([services[0]]),
      events: unknown[] = [];
    s.on('patient:updated', (e: unknown) => events.push(e));
    const t = await ticket();
    const r = await scan(t.qr, rooms[2]);
    expect(r.status).toBeGreaterThanOrEqual(400);
    expect(r.status).toBeLessThan(500);
    expect((await get().expect(200)).body.layanan[0].totalCheckIn).toBe(0);
    await new Promise((r) => setTimeout(r, 60));
    expect(events).toEqual([]);
  });
  it('rolled-back persisted update is excluded', async () => {
    const t = await ticket();
    await expect(
      db!.$transaction(async (tx) => {
        await tx.tiketAntrean.update({
          where: { id: t.id },
          data: { checkInPada: new Date(), status: 'CHECK_IN' },
        });
        throw Error('rollback fixture');
      }),
    ).rejects.toThrow('rollback fixture');
    expect((await get().expect(200)).body.layanan[0].totalCheckIn).toBe(0);
  });
  it('completed remains cumulative; reserved but not checked-in is excluded', async () => {
    await ticket({ status: 'SELESAI', checked: true });
    await ticket();
    expect((await get().expect(200)).body.layanan[0]).toMatchObject({
      totalCheckIn: 1,
      jumlahMenunggu: 0,
      sedangDilayani: [],
    });
  });
  it('waiting uses MENUNGGU/FIFO, not CHECK_IN or DIPESAN', async () => {
    await ticket({ status: 'MENUNGGU', checked: true });
    await ticket({ status: 'CHECK_IN', checked: true });
    await ticket();
    expect((await get().expect(200)).body.layanan[0]).toMatchObject({
      totalCheckIn: 2,
      jumlahMenunggu: 1,
    });
  });
  it('parallel staff check-ins count two unique tickets authoritatively', async () => {
    const a = await ticket(),
      b = await ticket({ owner: 'b' });
    await Promise.all([
      scan(a.qr, rooms[0], 'staff').expect(200),
      scan(b.qr, rooms[1], 'staff2').expect(200),
    ]);
    expect((await get().expect(200)).body.layanan[0]).toMatchObject({
      totalCheckIn: 2,
      jumlahMenunggu: 2,
    });
  });
  it('CALL/RECALL/SKIP/REQUEUE/START/COMPLETE change serving/waiting without adding checked-in total', async () => {
    const t = await ticket();
    await scan(t.qr).expect(200);
    const command = (path: string) =>
      request(server())
        .post('/api/v1/queue/' + path)
        .set('Authorization', 'Bearer ' + user('staff').token)
        .send({ loketId: rooms[0] })
        .expect(200);
    await command('panggil');
    expect((await get().expect(200)).body.layanan[0]).toMatchObject({
      totalCheckIn: 1,
      jumlahMenunggu: 0,
      sedangDilayani: [],
    });
    await command(t.id + '/panggil-ulang');
    await command(t.id + '/lewati');
    expect((await get().expect(200)).body.layanan[0]).toMatchObject({
      totalCheckIn: 1,
      jumlahMenunggu: 0,
      sedangDilayani: [],
    });
    await command(t.id + '/antre-ulang');
    expect((await get().expect(200)).body.layanan[0]).toMatchObject({
      totalCheckIn: 1,
      jumlahMenunggu: 1,
      sedangDilayani: [],
    });
    await command('panggil');
    await command(t.id + '/mulai-pelayanan');
    const active = (await get().expect(200)).body.layanan[0];
    expect(active.totalCheckIn).toBe(1);
    expect(active.sedangDilayani).toHaveLength(1);
    await command(t.id + '/selesaikan-pelayanan');
    expect((await get().expect(200)).body.layanan[0]).toMatchObject({
      totalCheckIn: 1,
      sedangDilayani: [],
    });
  });
  it('multiple active rooms remain a collection; no names/user/ticket identifiers leak', async () => {
    await ticket({ status: 'DILAYANI', checked: true, room: rooms[0] });
    await ticket({
      status: 'DILAYANI',
      checked: true,
      room: rooms[1],
      owner: 'b',
    });
    const r = await get().expect(200);
    expect(r.body.layanan[0].sedangDilayani).toHaveLength(2);
    for (const row of r.body.layanan[0].sedangDilayani)
      expect(Object.keys(row).sort()).toEqual([
        'kodeLoket',
        'loketId',
        'nomorAntrean',
      ]);
    const text = JSON.stringify(r.body);
    for (const u of users) {
      expect(text).not.toContain(u.id);
      expect(text).not.toContain(u.email);
    }
    expect(text).not.toContain('PRIVATE-');
  });
  it('inconsistent room from another service is not presented as serving', async () => {
    await ticket({ status: 'DILAYANI', checked: true, room: rooms[2] });
    expect((await get().expect(200)).body.layanan[0]).toMatchObject({
      totalCheckIn: 1,
      sedangDilayani: [],
    });
  });
  it('service/date isolation and scoped subscriber membership', async () => {
    await ticket({ checked: true });
    await ticket({ service: services[1], checked: true });
    await ticket({ date: '2026-01-01', checked: true });
    const foreign = await client([services[1]], day, 'b'),
      events: unknown[] = [];
    foreign.on('patient:updated', (e: unknown) => events.push(e));
    const own = await client([services[0]]),
      expected = changed(own),
      t = await ticket();
    await scan(t.qr).expect(200);
    await expected;
    expect((await get().expect(200)).body.layanan[0].totalCheckIn).toBe(2);
    expect(
      (await get(services[1]).expect(200)).body.layanan[0].totalCheckIn,
    ).toBe(1);
    expect(
      (await get(services[0], '2026-01-01').expect(200)).body.layanan[0]
        .totalCheckIn,
    ).toBe(1);
    expect(events).toEqual([]);
  });
  it('event loss does not fail or repeat committed check-in; reconnect restores snapshot', async () => {
    const spy = jest
      .spyOn(app!.get(PatientRealtimeGateway), 'invalidateQueue')
      .mockRejectedValueOnce(new Error('simulated transport loss'));
    const t = await ticket();
    await scan(t.qr).expect(200);
    expect(spy).toHaveBeenCalledTimes(1);
    spy.mockRestore();
    const s = await client([services[0]]);
    expect((await get().expect(200)).body.layanan[0].totalCheckIn).toBe(1);
    s.disconnect();
    const next = await ticket({ owner: 'b' });
    await scan(next.qr).expect(200);
    await client([services[0]]);
    expect((await get().expect(200)).body.layanan[0].totalCheckIn).toBe(2);
  });
  it.each(['staff', 'admin'])(
    'role %s cannot use USER read endpoint',
    async (key) => {
      await get(services[0], day, key).expect(403);
    },
  );
  it('invalid JWT and display cookie are not patient credentials', async () => {
    await request(server())
      .get('/api/v1/layanan/antrean')
      .set('Authorization', 'Bearer invalid')
      .expect(401);
    await request(server())
      .get('/api/v1/layanan/antrean')
      .set('Cookie', 'display_token=not-patient')
      .expect(401);
  });
  it.each(['2026-02-30', '2026-1-01', '2026-10-30T00:00:00Z', '0000-01-01'])(
    'strict date rejects %s',
    async (date) => {
      await get(services[0], date).expect(400);
    },
  );
  it('invalid, missing and inactive services fail closed; batch matches catalog IDs', async () => {
    await get('bad').expect(400);
    await get(randomUUID()).expect(404);
    await db!.layanan.update({
      where: { id: services[1] },
      data: { aktif: false },
    });
    try {
      await get(services[1]).expect(404);
    } finally {
      await db!.layanan.update({
        where: { id: services[1] },
        data: { aktif: true },
      });
    }
    const r = await get(services.join(',')).expect(200);
    expect(
      r.body.layanan.map((s: { layananId: string }) => s.layananId).sort(),
    ).toEqual([...services].sort());
  });
  it('forged subscription cannot join unknown services or malformed dates', async () => {
    const s = await client([services[0]]);
    for (const value of [
      { layananIds: [randomUUID()], tanggalPelayanan: day },
      { layananIds: [services[0]], tanggalPelayanan: '2026-02-30' },
      { layananIds: ['bad'], tanggalPelayanan: day },
    ]) {
      const ack = await new Promise<{ ok: boolean }>((resolve) =>
        s.emit('patient:antrean:ikuti', value, resolve),
      );
      expect(ack.ok).toBe(false);
    }
  });
});
