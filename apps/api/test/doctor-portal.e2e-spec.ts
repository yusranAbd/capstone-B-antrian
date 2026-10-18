import { randomUUID } from 'node:crypto';
import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import { ThrottlerStorage } from '@nestjs/throttler';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import { io, type Socket } from 'socket.io-client';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { PasswordService } from '../src/auth/password.service';
import { configureApp } from '../src/configure-app';
import { PeranPengguna, StatusTiket } from '../src/generated/prisma/client';
import { waktuPelayanan } from '../src/hospital/hospital-context';
import { PrismaService } from '../src/prisma/prisma.service';

type Auth = {
  accessToken: string;
  refreshToken: string;
  user: { id: string; peran: string };
};
type Row = { id: string; [key: string]: unknown };
describe('Doctor portal isolated full-stack (e2e)', () => {
  let app: INestApplication,
    db: PrismaService,
    admin: Auth,
    doctor: Auth,
    other: Auth,
    staff: Auth,
    patient: Auth;
  let clinic = '',
    room = '',
    foreignRoom = '',
    dr = '',
    drB = '',
    session = '',
    foreignSession = '',
    ticket = '',
    foreignTicket = '',
    walkin = '';
  const users: string[] = [],
    doctors: string[] = [],
    sockets: Socket[] = [];
  const uid = randomUUID().slice(0, 8),
    password = 'DoctorPortalQA123!';
  const today = waktuPelayanan(new Date());
  const auth = (t: Auth) => `Bearer ${t.accessToken}`;
  const http = () => app.getHttpServer() as Server;
  async function login(email: string) {
    const r = await request(http())
      .post('/api/v1/auth/login')
      .send({ email, kataSandi: password })
      .expect(200);
    return r.body as Auth;
  }
  async function account(role: PeranPengguna) {
    const email = `${uid}-${randomUUID()}@portal.test`;
    const u = await db.pengguna.create({
      data: {
        nama: `QA ${role}`,
        email,
        peran: role,
        kataSandiHash: await app.get(PasswordService).hash(password),
      },
    });
    users.push(u.id);
    return login(email);
  }
  async function connect(token: string, namespace = '/doctor') {
    const socket = io(
      `http://127.0.0.1:${(http().address() as AddressInfo).port}${namespace}`,
      {
        transports: ['websocket'],
        auth: { token },
        forceNew: true,
        reconnection: false,
      },
    );
    sockets.push(socket);
    await new Promise<void>((resolve, reject) => {
      socket.once('doctor:ready', () => resolve());
      socket.once('connect_error', reject);
      setTimeout(() => reject(Error('Socket timeout')), 3000).unref();
    });
    return socket;
  }
  beforeAll(async () => {
    const u = new URL(process.env.DATABASE_URL!);
    if (
      u.hostname !== '127.0.0.1' ||
      u.port !== '5433' ||
      u.pathname !== '/capstone_antrean_test'
    )
      throw Error('Target E2E salah');
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
      Array<{ db: string; port: number }>
    >`SELECT current_database() AS db, inet_server_port() AS port`;
    expect(actual[0].db).toBe('capstone_antrean_test');
    expect([5432, 5433]).toContain(actual[0].port);
    admin = await account('ADMIN');
    staff = await account('PETUGAS');
    patient = await account('USER');
    for (const name of ['Satu', 'Dua']) {
      const d = await db.dokter.create({
        data: {
          kode: `${uid}-${name}`,
          nama: `Dokter ${name}`,
          spesialisasi: 'Umum',
        },
      });
      doctors.push(d.id);
      const email = `${uid}-${name}@portal.test`;
      const r = await request(http())
        .post(`/api/v1/dokter/${d.id}/akun`)
        .set('Authorization', auth(admin))
        .send({ email, kataSandi: password })
        .expect(201);
      const body = r.body as { akun: { id: string; peran: string } };
      users.push(body.akun.id);
      expect(body.akun.peran).toBe('DOKTER');
      expect(JSON.stringify(body)).not.toContain('kataSandi');
      if (name === 'Satu') {
        dr = d.id;
        doctor = await login(email);
      } else {
        drB = d.id;
        other = await login(email);
      }
    }
    const c = await db.layanan.create({
      data: {
        kode: `DP${uid}`,
        nama: 'Poli Portal QA',
        prefixAntrean: 'DP',
        durasiDasarMenit: 10,
        modeReservasi: 'HIBRIDA',
      },
    });
    clinic = c.id;
    await db.jadwalLayanan.create({
      data: {
        layananId: clinic,
        hari: today.hari,
        jamBuka: new Date('1970-01-01T00:00:00Z'),
        jamTutup: new Date('1970-01-01T23:59:59Z'),
        kapasitasHarian: 100,
      },
    });
    for (const d of [dr, drB]) {
      const r = await db.loket.create({
        data: {
          layananId: clinic,
          kode: d === dr ? 'A' : 'B',
          nama: d === dr ? 'Ruang A' : 'Ruang B',
        },
      });
      const link = await db.dokterLayanan.create({
        data: { dokterId: d, layananId: clinic },
      });
      const s = await db.jadwalPraktik.create({
        data: {
          dokterLayananId: link.id,
          loketId: r.id,
          tanggal: today.tanggalDb,
          mulaiPada: new Date(`${today.tanggal}T00:00:00+07:00`),
          selesaiPada: new Date(`${today.tanggal}T23:59:59+07:00`),
        },
      });
      const sl = await db.slotPraktik.create({
        data: {
          jadwalPraktikId: s.id,
          mulaiPada: s.mulaiPada,
          selesaiPada: s.selesaiPada,
          kapasitas: 10,
        },
      });
      const t = await db.tiketAntrean.create({
        data: {
          penggunaId: patient.user.id,
          layananId: clinic,
          loketId: r.id,
          tanggalAntrean: today.tanggalDb,
          nomorUrut: d === dr ? 1 : 2,
          kodeTiket: `DP-${randomUUID().slice(0, 20)}`,
          status: StatusTiket.MENUNGGU,
          checkInPada: new Date(),
          urutanMasukAntrean: d === dr ? 1 : 2,
          janjiTemu: { create: { slotPraktikId: sl.id } },
        },
      });
      if (d === dr) {
        room = r.id;
        session = s.id;
        ticket = t.id;
      } else {
        foreignRoom = r.id;
        foreignSession = s.id;
        foreignTicket = t.id;
      }
    }
    const w = await db.tiketAntrean.create({
      data: {
        penggunaId: patient.user.id,
        layananId: clinic,
        loketId: room,
        tanggalAntrean: today.tanggalDb,
        nomorUrut: 3,
        kodeTiket: `DP-${randomUUID().slice(0, 20)}`,
        status: 'MENUNGGU',
        checkInPada: new Date(),
        urutanMasukAntrean: 3,
      },
    });
    walkin = w.id;
    await db.urutanAntreanHarian.create({
      data: {
        layananId: clinic,
        tanggal: today.tanggalDb,
        nomorTerakhir: 3,
        urutanMasukTerakhir: 3,
      },
    });
    await db.penugasanPetugas.create({
      data: {
        petugasId: staff.user.id,
        loketId: room,
        tanggalMulai: today.tanggalDb,
      },
    });
  }, 60000);
  afterAll(async () => {
    sockets.forEach((s) => s.disconnect());
    if (db) {
      if (clinic) {
        const ids = (
          await db.tiketAntrean.findMany({
            where: { layananId: clinic },
            select: { id: true },
          })
        ).map((t) => t.id);
        await db.notifikasi.deleteMany({
          where: { tiketAntreanId: { in: ids } },
        });
        await db.peristiwaAntrean.deleteMany({
          where: { tiketAntreanId: { in: ids } },
        });
        await db.janjiTemu.deleteMany({ where: { tiketId: { in: ids } } });
        await db.tiketAntrean.deleteMany({ where: { id: { in: ids } } });
        await db.slotPraktik.deleteMany({
          where: { jadwalPraktik: { dokterLayanan: { layananId: clinic } } },
        });
        await db.jadwalPraktik.deleteMany({
          where: { dokterLayanan: { layananId: clinic } },
        });
        await db.dokterLayanan.deleteMany({ where: { layananId: clinic } });
        await db.penugasanPetugas.deleteMany({
          where: { loket: { layananId: clinic } },
        });
        await db.loket.deleteMany({ where: { layananId: clinic } });
        await db.jadwalLayanan.deleteMany({ where: { layananId: clinic } });
        await db.urutanAntreanHarian.deleteMany({
          where: { layananId: clinic },
        });
        await db.layanan.deleteMany({ where: { id: clinic } });
      }
      await db.dokter.deleteMany({ where: { id: { in: doctors } } });
      await db.sesiPengguna.deleteMany({
        where: { penggunaId: { in: users } },
      });
      await db.pengguna.deleteMany({ where: { id: { in: users } } });
    }
    await app?.close();
  }, 30000);
  it('derives own profile/schedules/appointments and returns no patient identity or account secrets', async () => {
    const p = await request(http())
      .get('/api/v1/portal-dokter/profil')
      .set('Authorization', auth(doctor))
      .expect(200);
    expect((p.body as Row).id).toBe(dr);
    const s = await request(http())
      .get(`/api/v1/portal-dokter/jadwal?tanggal=${today.tanggal}`)
      .set('Authorization', auth(doctor))
      .expect(200);
    expect((s.body as Row[]).map((r) => r.id)).toEqual([session]);
    const a = await request(http())
      .get('/api/v1/portal-dokter/janji-temu')
      .set('Authorization', auth(doctor))
      .expect(200);
    expect((a.body as Row[]).map((r) => r.nomorAntrean)).toEqual(['DP-001']);
    expect(JSON.stringify(a.body)).not.toMatch(
      /penggunaId|email|kataSandi|tokenQr|kodeTiket|tiketId|Pasien/,
    );
    await request(http())
      .get(`/api/v1/portal-dokter/jadwal?dokterId=${drB}`)
      .set('Authorization', auth(doctor))
      .expect(400);
    await request(http())
      .get('/api/v1/portal-dokter/jadwal?tanggal=2026-02-30')
      .set('Authorization', auth(doctor))
      .expect(400);
  });
  it('permits owned session and HIBRIDA walk-in but denies foreign, inactive, expired and different-day session', async () => {
    const r = await request(http())
      .get(`/api/v1/portal-dokter/antrean/snapshot?jadwalPraktikId=${session}`)
      .set('Authorization', auth(doctor))
      .expect(200);
    expect((r.body as { totalMenunggu: number }).totalMenunggu).toBe(2);
    expect(JSON.stringify(r.body)).not.toContain('DP-002');
    await request(http())
      .get(
        `/api/v1/portal-dokter/antrean/snapshot?jadwalPraktikId=${foreignSession}`,
      )
      .set('Authorization', auth(doctor))
      .expect(403);
    for (const change of [
      { aktif: false },
      { selesaiPada: new Date(Date.now() - 1000) },
      { tanggal: new Date('2020-01-01') },
    ]) {
      const old = await db.jadwalPraktik.findUniqueOrThrow({
        where: { id: session },
      });
      try {
        await db.jadwalPraktik.update({ where: { id: session }, data: change });
        await request(http())
          .get(
            `/api/v1/portal-dokter/antrean/snapshot?jadwalPraktikId=${session}`,
          )
          .set('Authorization', auth(doctor))
          .expect(403);
      } finally {
        await db.jadwalPraktik.update({
          where: { id: session },
          data: {
            aktif: old.aktif,
            tanggal: old.tanggal,
            selesaiPada: old.selesaiPada,
          },
        });
      }
    }
  });
  it.each([
    'masuk',
    'panggil-ulang',
    'lewati',
    'antre-ulang',
    'mulai-pelayanan',
    'selesaikan-pelayanan',
  ])('forbids doctor queue mutation %s', async (action) => {
    await request(http())
      .post(`/api/v1/queue/${ticket}/${action}`)
      .set('Authorization', auth(doctor))
      .send({ loketId: room })
      .expect(403);
  });
  it('forbids CALL, QR check-in, master writes, self-link, staff snapshot and other patient appointments', async () => {
    for (const path of [
      '/queue/panggil',
      '/check-in',
      `/dokter/${dr}/akun`,
      '/jadwal-praktik',
      '/slot-praktik',
      '/layanan',
      '/reservasi',
      '/janji-temu',
    ]) {
      await request(http())
        .post(`/api/v1${path}`)
        .set('Authorization', auth(doctor))
        .send({ loketId: room })
        .expect(403);
    }
    for (const path of [
      `/queue/snapshot?loketId=${room}`,
      '/janji-temu',
      '/penugasan-petugas',
    ])
      await request(http())
        .get(`/api/v1${path}`)
        .set('Authorization', auth(doctor))
        .expect(403);
  });
  it.each(['ADMIN', 'PETUGAS', 'USER'])(
    'denies non-doctor role %s',
    async (role) => {
      const u = role === 'ADMIN' ? admin : role === 'PETUGAS' ? staff : patient;
      for (const path of [
        'profil',
        'jadwal',
        'janji-temu',
        `antrean/snapshot?jadwalPraktikId=${session}`,
      ])
        await request(http())
          .get(`/api/v1/portal-dokter/${path}`)
          .set('Authorization', auth(u))
          .expect(403);
    },
  );
  it('rejects public DOKTER registration and master PATCH/DELETE/QR attempts', async () => {
    await request(http())
      .post('/api/v1/auth/register')
      .send({
        nama: 'Tidak Boleh',
        email: `${uid}-public@portal.test`,
        kataSandi: password,
        peran: 'DOKTER',
      })
      .expect(400);
    for (const route of [
      `dokter/${dr}`,
      `jadwal-praktik/${session}`,
      `slot-praktik/${randomUUID()}`,
    ]) {
      await request(http())
        .patch(`/api/v1/${route}`)
        .set('Authorization', auth(doctor))
        .send({ aktif: false })
        .expect(403);
      await request(http())
        .delete(`/api/v1/${route}`)
        .set('Authorization', auth(doctor))
        .expect(403);
    }
    await request(http())
      .post(`/api/v1/tiket/${ticket}/qr`)
      .set('Authorization', auth(doctor))
      .send({})
      .expect(403);
  });
  it('isolates a foreign appointment even when its ticket points at the same room', async () => {
    await db.tiketAntrean.update({
      where: { id: foreignTicket },
      data: { loketId: room },
    });
    try {
      const r = await request(http())
        .get(
          `/api/v1/portal-dokter/antrean/snapshot?jadwalPraktikId=${session}`,
        )
        .set('Authorization', auth(doctor))
        .expect(200);
      expect((r.body as { totalMenunggu: number }).totalMenunggu).toBe(2);
      expect(JSON.stringify(r.body)).not.toContain('DP-002');
    } finally {
      await db.tiketAntrean.update({
        where: { id: foreignTicket },
        data: { loketId: foreignRoom },
      });
    }
  });
  it('keeps provisioning unique, rejects existing non-doctor account and atomic race leaves one account', async () => {
    await request(http())
      .post(`/api/v1/dokter/${dr}/akun`)
      .set('Authorization', auth(admin))
      .send({ penggunaId: other.user.id })
      .expect(409);
    const d = await db.dokter.create({
      data: { kode: `DP-${randomUUID().slice(0, 8)}`, nama: 'Dokter Tiga' },
    });
    doctors.push(d.id);
    await request(http())
      .post(`/api/v1/dokter/${d.id}/akun`)
      .set('Authorization', auth(admin))
      .send({ penggunaId: patient.user.id })
      .expect(422);
    await request(http())
      .post(`/api/v1/dokter/${d.id}/akun`)
      .set('Authorization', auth(admin))
      .send({ penggunaId: other.user.id })
      .expect(409);
    await request(http())
      .post(`/api/v1/dokter/${d.id}/akun`)
      .set('Authorization', auth(admin))
      .send({
        penggunaId: other.user.id,
        email: 'bad@portal.test',
        kataSandi: password,
      })
      .expect(400);
    const emails = [`${uid}-race1@portal.test`, `${uid}-race2@portal.test`];
    const results = await Promise.all(
      emails.map((email) =>
        request(http())
          .post(`/api/v1/dokter/${d.id}/akun`)
          .set('Authorization', auth(admin))
          .send({ email, kataSandi: password }),
      ),
    );
    const created = await db.pengguna.findMany({
      where: { email: { in: emails } },
      select: { id: true },
    });
    users.push(...created.map((u) => u.id));
    expect(results.map((r) => r.status).sort((a, b) => a - b)).toEqual([
      201, 409,
    ]);
    expect(created).toHaveLength(1);
  });
  it('links an unlinked DOKTER account and rejects its login before linking', async () => {
    const email = `${uid}-link@portal.test`;
    const u = await db.pengguna.create({
      data: {
        email,
        nama: 'Tautkan',
        peran: 'DOKTER',
        kataSandiHash: await app.get(PasswordService).hash(password),
      },
    });
    users.push(u.id);
    await request(http())
      .post('/api/v1/auth/login')
      .send({ email, kataSandi: password })
      .expect(401);
    const d = await db.dokter.create({
      data: { kode: `DP-${randomUUID().slice(0, 8)}`, nama: 'Dokter Tautkan' },
    });
    doctors.push(d.id);
    await request(http())
      .post(`/api/v1/dokter/${d.id}/akun`)
      .set('Authorization', auth(admin))
      .send({ penggunaId: u.id })
      .expect(201);
    expect((await login(email)).user.peran).toBe('DOKTER');
  });
  it('revalidates inactive account/profile and revoked session, supports refresh rotation', async () => {
    for (const model of ['dokter', 'pengguna'] as const) {
      const id = model === 'dokter' ? dr : doctor.user.id;
      if (model === 'dokter')
        await db.dokter.update({ where: { id }, data: { aktif: false } });
      else await db.pengguna.update({ where: { id }, data: { aktif: false } });
      try {
        await request(http())
          .get('/api/v1/portal-dokter/profil')
          .set('Authorization', auth(doctor))
          .expect(401);
        await request(http())
          .post('/api/v1/auth/refresh')
          .send({ refreshToken: doctor.refreshToken })
          .expect(401);
      } finally {
        if (model === 'dokter')
          await db.dokter.update({ where: { id }, data: { aktif: true } });
        else await db.pengguna.update({ where: { id }, data: { aktif: true } });
      }
    }
    const fresh = await request(http())
      .post('/api/v1/auth/refresh')
      .send({ refreshToken: doctor.refreshToken })
      .expect(200);
    await request(http())
      .post('/api/v1/auth/refresh')
      .send({ refreshToken: doctor.refreshToken })
      .expect(401);
    doctor = fresh.body as Auth;
    const temporary = await login(`${uid}-Satu@portal.test`);
    await request(http())
      .post('/api/v1/auth/logout')
      .send({ refreshToken: temporary.refreshToken })
      .expect(200);
    await request(http())
      .get('/api/v1/portal-dokter/profil')
      .set('Authorization', auth(temporary))
      .expect(401);
  });
  it('rejects expired doctor JWT and disconnects at access token expiry', async () => {
    const jwt = app.get(JwtService),
      config = app.get(ConfigService);
    const claims = jwt.decode<{ sid: string }>(doctor.accessToken);
    const payload = {
      sub: doctor.user.id,
      sid: claims.sid,
      role: 'DOKTER',
      email: `${uid}-Satu@portal.test`,
    };
    const token = await jwt.signAsync(payload, {
      secret: config.getOrThrow<string>('JWT_ACCESS_SECRET'),
      expiresIn: '3s',
    });
    const socket = await connect(token);
    await new Promise<void>((resolve, reject) => {
      const deadline = setTimeout(
        () => reject(Error('Doctor JWT did not expire')),
        6000,
      );
      socket.once('disconnect', () => {
        clearTimeout(deadline);
        resolve();
      });
    });
    await request(http())
      .get('/api/v1/portal-dokter/profil')
      .set('Authorization', `Bearer ${token}`)
      .expect(401);
    await expect(connect(token)).rejects.toThrow();
  });
  it('delivers committed CALL/START/COMPLETE only to authorized doctor; no staff room and no PHI', async () => {
    await expect(connect(staff.accessToken)).rejects.toThrow();
    const a = await connect(doctor.accessToken),
      b = await connect(other.accessToken);
    const otherEvents: unknown[] = [];
    b.on('doctor:updated', (v) => otherEvents.push(v));
    for (const [path, expected] of [
      ['panggil', 'DIPANGGIL'],
      [`${ticket}/mulai-pelayanan`, 'DILAYANI'],
      [`${ticket}/selesaikan-pelayanan`, 'SELESAI'],
    ]) {
      const update = new Promise<Record<string, unknown>>((resolve, reject) => {
        a.once('doctor:updated', resolve);
        setTimeout(() => reject(Error('No doctor update')), 4000).unref();
      });
      await request(http())
        .post(`/api/v1/queue/${path}`)
        .set('Authorization', auth(staff))
        .send({ loketId: room })
        .expect(200);
      expect(
        Object.keys(await update).sort((a, b) => a.localeCompare(b)),
      ).toEqual(['eventId', 'jenis', 'terjadiPada', 'versiSkema']);
      const snap = await request(http())
        .get(
          `/api/v1/portal-dokter/antrean/snapshot?jadwalPraktikId=${session}`,
        )
        .set('Authorization', auth(doctor))
        .expect(200);
      if (expected !== 'SELESAI')
        expect(JSON.stringify(snap.body)).toContain(expected);
      else expect((snap.body as { aktif: unknown[] }).aktif).toHaveLength(0);
    }
    expect(otherEvents).toHaveLength(0);
    const forbidden = io(
      `http://127.0.0.1:${(http().address() as AddressInfo).port}/queue`,
      {
        auth: { token: doctor.accessToken },
        transports: ['websocket'],
        forceNew: true,
        reconnection: false,
      },
    );
    sockets.push(forbidden);
    await new Promise<void>((resolve, reject) => {
      forbidden.once('connect_error', () => resolve());
      forbidden.once('connect', () =>
        reject(Error('Doctor admitted to staff namespace')),
      );
    });
    // Other doctor's room ticket and room-bound walk-in are preserved.
    expect(
      (
        await db.tiketAntrean.findUniqueOrThrow({
          where: { id: foreignTicket },
        })
      ).status,
    ).toBe('MENUNGGU');
    expect(
      (await db.tiketAntrean.findUniqueOrThrow({ where: { id: walkin } }))
        .status,
    ).toBe('MENUNGGU');
    expect(foreignRoom).not.toBe(room);
    const temporary = await login(`${uid}-Satu@portal.test`);
    const revoked = await connect(temporary.accessToken);
    const leaked: unknown[] = [];
    revoked.on('doctor:updated', (e) => leaked.push(e));
    await request(http())
      .post('/api/v1/auth/logout')
      .send({ refreshToken: temporary.refreshToken })
      .expect(200);
    const disconnected = new Promise<void>((resolve, reject) => {
      revoked.once('disconnect', () => resolve());
      setTimeout(
        () => reject(Error('Revoked doctor socket not disconnected')),
        4000,
      ).unref();
    });
    await request(http())
      .post('/api/v1/queue/panggil')
      .set('Authorization', auth(staff))
      .send({ loketId: room })
      .expect(200);
    await disconnected;
    expect(leaked).toHaveLength(0);
  });
});
