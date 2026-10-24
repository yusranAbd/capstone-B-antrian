import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { ThrottlerStorage } from '@nestjs/throttler';
import { randomUUID } from 'node:crypto';
import type { AddressInfo, Server } from 'node:net';
import request from 'supertest';
import { io, type Socket } from 'socket.io-client';
import { AppModule } from '../src/app.module';
import { PasswordService } from '../src/auth/password.service';
import { configureApp } from '../src/configure-app';
import type { PeranPengguna } from '../src/generated/prisma/client';
import { waktuPelayanan } from '../src/hospital/hospital-context';
import { PrismaService } from '../src/prisma/prisma.service';

type Login = { accessToken: string; user: { id: string } };
type QueueRow = {
  nomorAntrean: string;
  status: string;
  layakDipanggil: boolean;
};
type Snapshot = {
  menunggu: QueueRow[];
  aktif: QueueRow[];
  totalMenunggu: number;
};

describe('Doctor daily queue visibility regression (isolated e2e)', () => {
  let app: INestApplication, db: PrismaService, staff: Login;
  const users: string[] = [],
    clinics: string[] = [],
    doctors: string[] = [];
  const sessions: string[] = [],
    rooms: string[] = [],
    tickets: string[] = [];
  const logins: Login[] = [],
    sockets: Socket[] = [];
  const uid = randomUUID().slice(0, 8),
    password = `Daily-${randomUUID()}`;
  const today = waktuPelayanan(new Date());
  const http = () => app.getHttpServer() as Server;
  const bearer = (u: Login) => `Bearer ${u.accessToken}`;
  async function account(peran: PeranPengguna, hash: string) {
    const email = `${uid}-${randomUUID()}@daily-doctor.test`;
    const u = await db.pengguna.create({
      data: { email, nama: `QA ${peran}`, peran, kataSandiHash: hash },
    });
    users.push(u.id);
    return { user: u, email };
  }
  async function login(email: string) {
    const r = await request(http())
      .post('/api/v1/auth/login')
      .send({ email, kataSandi: password })
      .expect(200);
    return r.body as Login;
  }
  async function connect(u: Login) {
    const socket = io(
      `http://127.0.0.1:${(http().address() as AddressInfo).port}/doctor`,
      {
        transports: ['websocket'],
        auth: { token: u.accessToken },
        forceNew: true,
        reconnection: false,
      },
    );
    sockets.push(socket);
    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(
        () => reject(Error('doctor ready timeout')),
        5000,
      );
      socket.once('doctor:ready', () => {
        clearTimeout(timer);
        resolve();
      });
      socket.once('connect_error', (e) => {
        clearTimeout(timer);
        reject(e);
      });
    });
    return socket;
  }
  function update(socket: Socket) {
    return new Promise<Record<string, unknown>>((resolve, reject) => {
      const timer = setTimeout(
        () => reject(Error('daily doctor invalidation missing')),
        5000,
      );
      socket.once('doctor:updated', (v) => {
        clearTimeout(timer);
        resolve(v as Record<string, unknown>);
      });
    });
  }
  async function snapshot(index: number) {
    const r = await request(http())
      .get(
        `/api/v1/portal-dokter/antrean/snapshot?jadwalPraktikId=${sessions[index]}`,
      )
      .set('Authorization', bearer(logins[index]))
      .expect(200);
    return r.body as Snapshot;
  }
  beforeAll(async () => {
    const url = new URL(process.env.DATABASE_URL!);
    if (
      url.hostname !== '127.0.0.1' ||
      url.port !== '5433' ||
      url.pathname !== '/capstone_antrean_test'
    )
      throw Error('Unsafe test target');
    const mod = await Test.createTestingModule({ imports: [AppModule] })
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
    app = mod.createNestApplication();
    configureApp(app);
    await app.listen(0, '127.0.0.1');
    db = app.get(PrismaService);
    const actual = await db.$queryRaw<
      Array<{ db: string }>
    >`SELECT current_database() AS db`;
    expect(actual[0].db).toBe('capstone_antrean_test');
    const hash = await app.get(PasswordService).hash(password);
    staff = await login((await account('PETUGAS', hash)).email);
    for (let i = 0; i < 2; i++) {
      const c = await db.layanan.create({
        data: {
          kode: `DQ${uid}${i}`,
          nama: 'Poli QA harian',
          prefixAntrean: i ? 'XX' : 'AN',
          modeReservasi: 'ANTREAN_HARIAN',
          durasiDasarMenit: 10,
        },
      });
      clinics.push(c.id);
      await db.jadwalLayanan.create({
        data: {
          layananId: c.id,
          hari: today.hari,
          jamBuka: new Date('1970-01-01T00:00:00Z'),
          jamTutup: new Date('1970-01-01T23:59:59Z'),
          kapasitasHarian: 100,
        },
      });
    }
    for (let i = 0; i < 3; i++) {
      const u = await account('DOKTER', hash);
      const d = await db.dokter.create({
        data: {
          kode: `DQ${uid}${i}`,
          nama: `Dokter harian ${i}`,
          penggunaId: u.user.id,
        },
      });
      doctors.push(d.id);
      logins.push(await login(u.email));
      const clinic = clinics[i === 2 ? 1 : 0];
      const room = await db.loket.create({
        data: { layananId: clinic, kode: `R${i}`, nama: `Ruang QA ${i}` },
      });
      rooms.push(room.id);
      const link = await db.dokterLayanan.create({
        data: { dokterId: d.id, layananId: clinic },
      });
      const s = await db.jadwalPraktik.create({
        data: {
          dokterLayananId: link.id,
          loketId: room.id,
          tanggal: today.tanggalDb,
          mulaiPada: new Date(`${today.tanggal}T00:00:00+07:00`),
          selesaiPada: new Date(`${today.tanggal}T23:59:59+07:00`),
        },
      });
      sessions.push(s.id);
    }
    await db.penugasanPetugas.create({
      data: {
        petugasId: staff.user.id,
        loketId: rooms[0],
        tanggalMulai: today.tanggalDb,
      },
    });
    for (let i = 0; i < 2; i++) {
      const patient = await login((await account('USER', hash)).email);
      const reserved = await request(http())
        .post('/api/v1/reservasi')
        .set('Authorization', bearer(patient))
        .send({ layananId: clinics[0], tanggalAntrean: today.tanggal })
        .expect(201);
      const t = reserved.body as { id: string };
      tickets.push(t.id);
      const qr = await request(http())
        .post(`/api/v1/tiket/${t.id}/qr`)
        .set('Authorization', bearer(patient))
        .send({})
        .expect(201);
      await request(http())
        .post('/api/v1/check-in')
        .set('Authorization', bearer(staff))
        .send({
          qrPayload: (qr.body as { qrPayload: string }).qrPayload,
          loketId: rooms[0],
        })
        .expect(200);
    }
  }, 60000);
  afterAll(async () => {
    sockets.forEach((s) => s.disconnect());
    if (db) {
      const ownedTickets = await db.tiketAntrean.findMany({
        where: { layananId: { in: clinics } },
        select: { id: true },
      });
      const ids = ownedTickets.map((t) => t.id);
      await db.notifikasi.deleteMany({
        where: { tiketAntreanId: { in: ids } },
      });
      await db.peristiwaAntrean.deleteMany({
        where: { tiketAntreanId: { in: ids } },
      });
      await db.tiketAntrean.deleteMany({ where: { id: { in: ids } } });
      await db.jadwalPraktik.deleteMany({ where: { id: { in: sessions } } });
      await db.dokterLayanan.deleteMany({
        where: { dokterId: { in: doctors } },
      });
      await db.dokter.deleteMany({ where: { id: { in: doctors } } });
      await db.penugasanPetugas.deleteMany({
        where: { petugasId: staff?.user.id, loketId: { in: rooms } },
      });
      await db.loket.deleteMany({ where: { id: { in: rooms } } });
      await db.jadwalLayanan.deleteMany({
        where: { layananId: { in: clinics } },
      });
      await db.urutanAntreanHarian.deleteMany({
        where: { layananId: { in: clinics } },
      });
      await db.layanan.deleteMany({ where: { id: { in: clinics } } });
      await db.sesiPengguna.deleteMany({
        where: { penggunaId: { in: users } },
      });
      await db.pengguna.deleteMany({ where: { id: { in: users } } });
    }
    await app?.close();
  });
  it('notifies own-clinic doctors about daily ENQUEUE; foreign clinic receives nothing', async () => {
    for (const u of logins) await connect(u);
    const foreign: unknown[] = [];
    sockets[2].on('doctor:updated', (v) => foreign.push(v));
    // Check-in was 001 then 002; enqueue in the opposite order to prove FIFO.
    for (const id of [tickets[1], tickets[0]]) {
      const events = Promise.all([update(sockets[0]), update(sockets[1])]);
      // Register a rejection handler immediately if the HTTP assertion fails.
      events.catch(() => {});
      await request(http())
        .post(`/api/v1/queue/${id}/masuk`)
        .set('Authorization', bearer(staff))
        .send({ loketId: rooms[0] })
        .expect(200);
      for (const e of await events)
        expect(Object.keys(e).sort()).toEqual([
          'eventId',
          'jenis',
          'terjadiPada',
          'versiSkema',
        ]);
    }
    expect(foreign).toHaveLength(0);
  });
  it('matches staff FIFO in own live sessions despite zero appointments', async () => {
    // Also enqueue if testing this regression alone, independent of socket test outcome.
    for (const id of [tickets[1], tickets[0]]) {
      const t = await db.tiketAntrean.findUniqueOrThrow({ where: { id } });
      if (t.status === 'CHECK_IN')
        await request(http())
          .post(`/api/v1/queue/${id}/masuk`)
          .set('Authorization', bearer(staff))
          .send({ loketId: rooms[0] })
          .expect(200);
    }
    const staffSnap = await request(http())
      .get(`/api/v1/queue/snapshot?loketId=${rooms[0]}`)
      .set('Authorization', bearer(staff))
      .expect(200);
    const numbers = (
      staffSnap.body as { menunggu: { tiket: QueueRow[] } }
    ).menunggu.tiket.map((t) => t.nomorAntrean);
    expect(numbers).toEqual(['AN-002', 'AN-001']);
    for (const i of [0, 1]) {
      const s = await snapshot(i);
      expect(s.totalMenunggu).toBe(2);
      expect(s.menunggu.map((t) => t.nomorAntrean)).toEqual(numbers);
      expect(s.menunggu.every((t) => t.layakDipanggil)).toBe(true);
      expect(JSON.stringify(s)).not.toMatch(
        /penggunaId|email|kataSandi|tokenQr|tiketId/,
      );
    }
    expect((await snapshot(2)).totalMenunggu).toBe(0);
  });
  it('refreshes both clinic doctors on CALL but exposes active service only in its room', async () => {
    const events = Promise.all([update(sockets[0]), update(sockets[1])]);
    events.catch(() => {});
    const called = await request(http())
      .post('/api/v1/queue/panggil')
      .set('Authorization', bearer(staff))
      .send({ loketId: rooms[0] })
      .expect(200);
    expect((called.body as { tiketId: string }).tiketId).toBe(tickets[1]);
    await events;
    expect((await snapshot(0)).aktif.map((t) => t.nomorAntrean)).toEqual([
      'AN-002',
    ]);
    expect((await snapshot(1)).aktif).toEqual([]);
    expect((await snapshot(1)).menunggu.map((t) => t.nomorAntrean)).toEqual([
      'AN-001',
    ]);
    for (const action of ['mulai-pelayanan', 'selesaikan-pelayanan']) {
      const next = Promise.all([update(sockets[0]), update(sockets[1])]);
      next.catch(() => {});
      await request(http())
        .post(`/api/v1/queue/${tickets[1]}/${action}`)
        .set('Authorization', bearer(staff))
        .send({ loketId: rooms[0] })
        .expect(200);
      await next;
    }
    expect((await snapshot(0)).aktif).toEqual([]);
  });
  it('keeps a REQUEUE ticket with null room visible and notifies both clinic doctors', async () => {
    for (const action of [
      'panggil',
      `${tickets[0]}/lewati`,
      `${tickets[0]}/antre-ulang`,
    ]) {
      const events = Promise.all([update(sockets[0]), update(sockets[1])]);
      events.catch(() => {});
      await request(http())
        .post(`/api/v1/queue/${action}`)
        .set('Authorization', bearer(staff))
        .send({ loketId: rooms[0] })
        .expect(200);
      await events;
    }
    expect(
      (await db.tiketAntrean.findUniqueOrThrow({ where: { id: tickets[0] } }))
        .loketId,
    ).toBeNull();
    for (const i of [0, 1]) {
      const s = await snapshot(i);
      expect(s.menunggu.map((t) => t.nomorAntrean)).toEqual(['AN-001']);
      expect(s.menunggu[0].layakDipanggil).toBe(true);
      expect(s.aktif).toEqual([]);
    }
    expect((await snapshot(2)).totalMenunggu).toBe(0);
  });
  it('retains doctor ownership, active-session and mutation RBAC checks', async () => {
    await request(http())
      .get(
        `/api/v1/portal-dokter/antrean/snapshot?jadwalPraktikId=${sessions[1]}`,
      )
      .set('Authorization', bearer(logins[0]))
      .expect(403);
    await db.jadwalPraktik.update({
      where: { id: sessions[0] },
      data: { aktif: false },
    });
    try {
      await request(http())
        .get(
          `/api/v1/portal-dokter/antrean/snapshot?jadwalPraktikId=${sessions[0]}`,
        )
        .set('Authorization', bearer(logins[0]))
        .expect(403);
    } finally {
      await db.jadwalPraktik.update({
        where: { id: sessions[0] },
        data: { aktif: true },
      });
    }
    await request(http())
      .post('/api/v1/queue/panggil')
      .set('Authorization', bearer(logins[0]))
      .send({ loketId: rooms[0] })
      .expect(403);
  });
});
