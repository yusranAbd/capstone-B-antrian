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
import {
  HariLayanan,
  ModeReservasi,
  PeranPengguna,
} from '../src/generated/prisma/client';
import { PrismaService } from '../src/prisma/prisma.service';
import { waktuPelayanan } from '../src/hospital/hospital-context';

interface Clinic {
  id: string;
  room: string;
  session: string;
  slot: string;
  doctor: string;
  link: string;
}
describe('One-Scan QR atomic API (isolated PostgreSQL)', () => {
  const unique = randomUUID().slice(0, 8);
  const accounts: Array<{
    id: string;
    role: PeranPengguna;
    token: string;
    email: string;
  }> = [];
  const clinics = new Map<ModeReservasi, Clinic>();
  const sockets: Socket[] = [];
  const tickets: string[] = [];
  const displayToken = randomBytes(32).toString('hex');
  let app: INestApplication;
  let db: PrismaService;
  let order = 0;
  const today = waktuPelayanan(new Date()).tanggalDb;
  const start = new Date(today.getTime() - 7 * 3600000);
  const end = new Date(start.getTime() + 24 * 3600000 - 60000);
  const days = Object.values(HariLayanan);
  const account = (r: PeranPengguna) => accounts.find((a) => a.role === r)!;
  const server = () => app.getHttpServer() as Server;
  const clinic = (m: ModeReservasi = 'ANTREAN_HARIAN') => clinics.get(m)!;
  function scan(qr: string, c = clinic(), role: PeranPengguna = 'PETUGAS') {
    return request(server())
      .post('/api/v1/check-in/auto-antrean')
      .set('Authorization', `Bearer ${account(role).token}`)
      .send({ qrPayload: qr, loketId: c.room });
  }
  async function ticket(c = clinic()) {
    const qr = `SQ1.${randomBytes(32).toString('base64url')}`;
    const row = await db.tiketAntrean.create({
      data: {
        penggunaId: account('USER').id,
        layananId: c.id,
        tanggalAntrean: today,
        nomorUrut: ++order,
        kodeTiket: `OS${randomBytes(12).toString('hex')}`,
        status: 'DIPESAN',
        tokenQrHash: createHash('sha256').update(qr).digest('hex'),
        qrKedaluwarsaPada: new Date(Date.now() + 600000),
      },
    });
    tickets.push(row.id);
    return { id: row.id, qr, number: row.nomorUrut };
  }
  function wait(socket: Socket, event: string): Promise<unknown> {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(
        () => reject(new Error(`Timeout ${event}`)),
        8000,
      );
      socket.once(event, (value: unknown) => {
        clearTimeout(timer);
        resolve(value);
      });
    });
  }
  async function socket(
    namespace: string,
    token: string,
    c = clinic('HIBRIDA'),
  ) {
    const port = (server().address() as AddressInfo).port;
    const s = io(`http://127.0.0.1:${port}/${namespace}`, {
      transports: ['websocket'],
      auth: { token, layananId: c.id },
      autoConnect: false,
      forceNew: true,
      reconnection: false,
    });
    sockets.push(s);
    if (namespace === 'queue') {
      const connected = wait(s, 'connect');
      s.connect();
      await connected;
      const ack = await new Promise<{ ok: boolean }>((resolve) =>
        s.emit('queue:join', { layananId: c.id }, resolve),
      );
      expect(ack.ok).toBe(true);
    } else {
      const ready = wait(s, `${namespace}:ready`);
      s.connect();
      await ready;
    }
    return s;
  }
  beforeAll(async () => {
    const url = new URL(process.env.DATABASE_URL ?? 'http://invalid');
    if (
      url.hostname !== '127.0.0.1' ||
      url.port !== '5433' ||
      url.pathname !== '/capstone_antrean_test'
    )
      throw Error('Test DB target rejected');
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
        await db.$queryRaw<
          Array<{ db: string }>
        >`SELECT current_database() AS db`
      )[0].db,
    ).toBe('capstone_antrean_test');
    const password = await hash('OneScanFixture123!', 10);
    for (const role of ['USER', 'PETUGAS', 'ADMIN', 'DOKTER'] as const) {
      const email = `one-scan-${role}-${unique}@test.local`.toLowerCase();
      const a = await db.pengguna.create({
        data: {
          nama: `Pasien Uji ${role}`,
          email,
          kataSandiHash: password,
          peran: role,
        },
      });
      accounts.push({ id: a.id, role, token: '', email });
    }
    for (const mode of Object.values(ModeReservasi)) {
      const c = await db.layanan.create({
        data: {
          kode: `OS${mode.slice(0, 2)}${unique}`,
          nama: `Poli One Scan ${mode}`,
          prefixAntrean: 'OS',
          durasiDasarMenit: 10,
          modeReservasi: mode,
        },
      });
      const r = await db.loket.create({
        data: { layananId: c.id, kode: '01', nama: 'Ruang One Scan' },
      });
      await db.jadwalLayanan.createMany({
        data: days.map((hari) => ({
          layananId: c.id,
          hari,
          jamBuka: new Date('1970-01-01T00:00:00Z'),
          jamTutup: new Date('1970-01-01T23:59:59Z'),
          kapasitasHarian: 500,
        })),
      });
      await db.penugasanPetugas.create({
        data: {
          petugasId: account('PETUGAS').id,
          loketId: r.id,
          tanggalMulai: today,
        },
      });
      await db.urutanAntreanHarian.create({
        data: { layananId: c.id, tanggal: today, nomorTerakhir: 100 },
      });
      const d = await db.dokter.create({
        data: {
          kode: `OSD${mode.slice(0, 2)}${unique}`,
          nama: 'Dokter One Scan',
          penggunaId: mode === 'HIBRIDA' ? account('DOKTER').id : null,
        },
      });
      const link = await db.dokterLayanan.create({
        data: { dokterId: d.id, layananId: c.id },
      });
      const session = await db.jadwalPraktik.create({
        data: {
          dokterLayananId: link.id,
          loketId: r.id,
          tanggal: today,
          mulaiPada: start,
          selesaiPada: end,
        },
      });
      const slot = await db.slotPraktik.create({
        data: {
          jadwalPraktikId: session.id,
          mulaiPada: new Date(start.getTime() + 60000),
          selesaiPada: new Date(start.getTime() + 120000),
          kapasitas: 100,
        },
      });
      clinics.set(mode, {
        id: c.id,
        room: r.id,
        session: session.id,
        slot: slot.id,
        doctor: d.id,
        link: link.id,
      });
    }
    await db.perangkatTampilan.create({
      data: {
        layananId: clinic('HIBRIDA').id,
        nama: 'One Scan TV',
        tokenHash: createHash('sha256').update(displayToken).digest('hex'),
      },
    });
    for (const a of accounts) {
      const r = await request(server())
        .post('/api/v1/auth/login')
        .send({ email: a.email, kataSandi: 'OneScanFixture123!' })
        .expect(200);
      a.token = (r.body as { accessToken: string }).accessToken;
    }
  }, 120000);
  afterEach(async () => {
    for (const s of sockets.splice(0)) s.disconnect();
  });
  afterAll(async () => {
    if (!db) {
      if (app) await app.close();
      return;
    }
    try {
      if (tickets.length) {
        await db.peristiwaAntrean.deleteMany({
          where: { tiketAntreanId: { in: tickets } },
        });
        await db.janjiTemu.deleteMany({ where: { tiketId: { in: tickets } } });
        await db.tiketAntrean.deleteMany({ where: { id: { in: tickets } } });
      }
      for (const c of clinics.values()) {
        await db.perangkatTampilan.deleteMany({ where: { layananId: c.id } });
        await db.slotPraktik.deleteMany({
          where: { jadwalPraktikId: c.session },
        });
        await db.jadwalPraktik.deleteMany({ where: { id: c.session } });
        await db.dokterLayanan.deleteMany({ where: { id: c.link } });
        await db.dokter.deleteMany({ where: { id: c.doctor } });
        await db.penugasanPetugas.deleteMany({ where: { loketId: c.room } });
        await db.jadwalLayanan.deleteMany({ where: { layananId: c.id } });
        await db.urutanAntreanHarian.deleteMany({ where: { layananId: c.id } });
        await db.loket.deleteMany({ where: { id: c.room } });
        await db.layanan.deleteMany({ where: { id: c.id } });
      }
      const ids = accounts.map((a) => a.id);
      await db.sesiPengguna.deleteMany({ where: { penggunaId: { in: ids } } });
      await db.pengguna.deleteMany({ where: { id: { in: ids } } });
    } finally {
      await app.close();
    }
  }, 60000);

  it.each(['ANTREAN_HARIAN', 'HIBRIDA'] as const)(
    'walk-in %s becomes waiting in one request, two audits',
    async (mode) => {
      const c = clinic(mode),
        t = await ticket(c);
      const r = await scan(t.qr, c).expect(200);
      expect(r.body).toMatchObject({
        tiketId: t.id,
        status: 'MENUNGGU',
        sudahTerdaftar: false,
        namaPasien: 'Pasien Uji USER',
      });
      expect(
        await db.peristiwaAntrean.count({
          where: {
            tiketAntreanId: t.id,
            tipe: { in: ['CHECK_IN', 'ENQUEUE'] },
          },
        }),
      ).toBe(2);
      const stored = await db.tiketAntrean.findUniqueOrThrow({
        where: { id: t.id },
      });
      expect(stored.tokenQrHash).toBeNull();
      expect(stored.checkInPada).not.toBeNull();
      expect(JSON.stringify(r.body)).not.toContain(t.qr);
    },
  );
  it('appointment valid after slot end while session remains live', async () => {
    const c = clinic('JANJI_TEMU_DOKTER'),
      t = await ticket(c);
    await db.janjiTemu.create({
      data: { tiketId: t.id, slotPraktikId: c.slot },
    });
    await scan(t.qr, c).expect(200);
    expect(
      (await db.tiketAntrean.findUniqueOrThrow({ where: { id: t.id } })).status,
    ).toBe('MENUNGGU');
  });
  it('expired QR and wrong date are rejected without consuming token', async () => {
    const t = await ticket();
    await db.tiketAntrean.update({
      where: { id: t.id },
      data: { qrKedaluwarsaPada: new Date(Date.now() - 1000) },
    });
    await scan(t.qr).expect(410);
    await db.tiketAntrean.update({
      where: { id: t.id },
      data: {
        qrKedaluwarsaPada: new Date(Date.now() + 600000),
        tanggalAntrean: new Date(today.getTime() + 86400000),
      },
    });
    await scan(t.qr).expect(400);
    expect(
      (await db.tiketAntrean.findUniqueOrThrow({ where: { id: t.id } }))
        .tokenQrHash,
    ).not.toBeNull();
  });
  it('rejects another clinic, malformed QR, JWT missing, and all nonstaff roles', async () => {
    const t = await ticket();
    await scan(t.qr, clinic('HIBRIDA')).expect(403);
    await scan('SQ1.partial').expect(400);
    await request(server())
      .post('/api/v1/check-in/auto-antrean')
      .send({ qrPayload: t.qr, loketId: clinic().room })
      .expect(401);
    for (const role of ['USER', 'ADMIN', 'DOKTER'] as const)
      await scan(t.qr, clinic(), role).expect(403);
  });
  it.each([
    'DIPANGGIL',
    'DILAYANI',
    'SELESAI',
    'DIBATALKAN',
    'DILEWATI',
  ] as const)('rejects %s without automatic requeue', async (status) => {
    const t = await ticket();
    await db.tiketAntrean.update({ where: { id: t.id }, data: { status } });
    await scan(t.qr).expect(409);
  });
  it('continues a legacy CHECK_IN using consumed QR proof; legacy replay remains rejected', async () => {
    const t = await ticket();
    await request(server())
      .post('/api/v1/check-in')
      .set('Authorization', `Bearer ${account('PETUGAS').token}`)
      .send({ qrPayload: t.qr, loketId: clinic().room })
      .expect(200);
    await scan(t.qr).expect(200);
    await request(server())
      .post('/api/v1/check-in')
      .set('Authorization', `Bearer ${account('PETUGAS').token}`)
      .send({ qrPayload: t.qr, loketId: clinic().room })
      .expect(400);
    expect(
      await db.peristiwaAntrean.count({
        where: { tiketAntreanId: t.id, tipe: 'CHECK_IN' },
      }),
    ).toBe(1);
  });
  it('two concurrent scans and retries produce one FIFO position and one ENQUEUE', async () => {
    const t = await ticket();
    const before = await db.urutanAntreanHarian.findUniqueOrThrow({
      where: { layananId_tanggal: { layananId: clinic().id, tanggal: today } },
    });
    const responses = await Promise.all([scan(t.qr), scan(t.qr)]);
    expect(responses.map((r) => r.status)).toEqual([200, 200]);
    expect(
      responses.filter(
        (r) => (r.body as { sudahTerdaftar: boolean }).sudahTerdaftar,
      ),
    ).toHaveLength(1);
    const again = await scan(t.qr).expect(200);
    expect(again.body).toMatchObject({
      sudahTerdaftar: true,
      status: 'MENUNGGU',
    });
    expect(
      await db.peristiwaAntrean.count({
        where: { tiketAntreanId: t.id, tipe: 'ENQUEUE' },
      }),
    ).toBe(1);
    expect(
      (
        await db.urutanAntreanHarian.findUniqueOrThrow({
          where: { id: before.id },
        })
      ).urutanMasukTerakhir,
    ).toBe(before.urutanMasukTerakhir + 1);
  });
  it('enqueue failure rolls back CHECK_IN, QR consumption and audit', async () => {
    const c = clinic(),
      t = await ticket();
    const counter = await db.urutanAntreanHarian.findUniqueOrThrow({
      where: { layananId_tanggal: { layananId: c.id, tanggal: today } },
    });
    // Only this suite owns the fixture counter; restore it immediately afterwards.
    await db.urutanAntreanHarian.delete({ where: { id: counter.id } });
    try {
      await scan(t.qr, c).expect(409);
      const row = await db.tiketAntrean.findUniqueOrThrow({
        where: { id: t.id },
      });
      expect(row.status).toBe('DIPESAN');
      expect(row.checkInPada).toBeNull();
      expect(row.tokenQrHash).not.toBeNull();
      expect(
        await db.peristiwaAntrean.count({ where: { tiketAntreanId: t.id } }),
      ).toBe(0);
    } finally {
      await db.urutanAntreanHarian.create({
        data: {
          id: counter.id,
          layananId: c.id,
          tanggal: today,
          nomorTerakhir: counter.nomorTerakhir,
          urutanMasukTerakhir: counter.urutanMasukTerakhir,
        },
      });
    }
    await scan(t.qr, c).expect(200);
  });
  it('expired consumed proof is rejected without allocating another FIFO position', async () => {
    const t = await ticket();
    await scan(t.qr).expect(200);
    const audit = await db.peristiwaAntrean.findFirstOrThrow({
      where: { tiketAntreanId: t.id, tipe: 'CHECK_IN' },
    });
    const meta = audit.dataTambahan as Record<string, string>;
    await db.peristiwaAntrean.update({
      where: { id: audit.id },
      data: {
        dataTambahan: {
          ...meta,
          qrBerlakuHingga: new Date(Date.now() - 1000).toISOString(),
        },
      },
    });
    await scan(t.qr).expect(410);
    expect(
      await db.peristiwaAntrean.count({
        where: { tiketAntreanId: t.id, tipe: 'ENQUEUE' },
      }),
    ).toBe(1);
  });
  it('inactive assignment and invalid practice context preserve the original QR', async () => {
    const c = clinic('JANJI_TEMU_DOKTER'),
      t = await ticket(c);
    await db.janjiTemu.create({
      data: { tiketId: t.id, slotPraktikId: c.slot },
    });
    await db.penugasanPetugas.updateMany({
      where: { petugasId: account('PETUGAS').id, loketId: c.room },
      data: { aktif: false },
    });
    try {
      await scan(t.qr, c).expect(403);
    } finally {
      await db.penugasanPetugas.updateMany({
        where: { petugasId: account('PETUGAS').id, loketId: c.room },
        data: { aktif: true },
      });
    }
    await db.jadwalPraktik.update({
      where: { id: c.session },
      data: { aktif: false },
    });
    try {
      await scan(t.qr, c).expect(400);
    } finally {
      await db.jadwalPraktik.update({
        where: { id: c.session },
        data: { aktif: true },
      });
    }
    expect(
      (await db.tiketAntrean.findUniqueOrThrow({ where: { id: t.id } })).status,
    ).toBe('DIPESAN');
  });
  it('ENQUEUE invalidates staff, display, doctor and patient after commit; snapshots show waiting', async () => {
    const c = clinic('HIBRIDA'),
      t = await ticket(c);
    const staff = await socket('queue', account('PETUGAS').token, c),
      display = await socket('display', displayToken, c);
    const doctor = await socket('doctor', account('DOKTER').token, c),
      patient = await socket('patient', account('USER').token, c);
    const events = [
      wait(staff, 'queue:updated'),
      wait(display, 'display:updated'),
      wait(doctor, 'doctor:updated'),
      wait(patient, 'patient:updated'),
    ];
    await scan(t.qr, c).expect(200);
    const data = await Promise.all(events);
    expect(data[0]).toMatchObject({ aksi: 'ENQUEUE', status: 'MENUNGGU' });
    expect(data[1]).toMatchObject({
      aksi: 'ENQUEUE',
      perluPeriksaPengumuman: false,
    });
    expect(JSON.stringify(data)).not.toContain(t.qr);
    expect(JSON.stringify(data)).not.toContain('Pasien Uji USER');
    const staffSnapshot = await request(server())
      .get(`/api/v1/queue/snapshot?loketId=${c.room}`)
      .set('Authorization', `Bearer ${account('PETUGAS').token}`)
      .expect(200);
    expect(JSON.stringify(staffSnapshot.body)).toContain(t.id);
    const tv = await request(server())
      .get(`/api/v1/display/${c.id}/snapshot`)
      .set('x-display-token', displayToken)
      .expect(200);
    expect(JSON.stringify(tv.body)).toContain('OS-');
    const doc = await request(server())
      .get(
        `/api/v1/portal-dokter/antrean/snapshot?jadwalPraktikId=${c.session}`,
      )
      .set('Authorization', `Bearer ${account('DOKTER').token}`)
      .expect(200);
    expect(JSON.stringify(doc.body)).toContain(
      `OS-${String(t.number).padStart(3, '0')}`,
    );
    expect(JSON.stringify(doc.body)).not.toContain(t.id);
  });
});
