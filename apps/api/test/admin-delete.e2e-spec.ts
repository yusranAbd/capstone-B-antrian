import { randomUUID } from 'node:crypto';
import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import type { Server } from 'node:http';
import request from 'supertest';
import { io, type Socket } from 'socket.io-client';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/configure-app';
import { PrismaService } from '../src/prisma/prisma.service';
import { PasswordService } from '../src/auth/password.service';
import { PeranPengguna, HariLayanan } from '../src/generated/prisma/client';
import {
  DELETE_RESOURCES,
  type DeleteResource,
} from '../src/admin-delete/admin-delete.service';

describe('ADMIN permanent deletion (isolated)', () => {
  let app: INestApplication, db: PrismaService, server: Server;
  const run = randomUUID().slice(0, 8),
    tokens = {} as Record<PeranPengguna, string>,
    users: string[] = [];
  const ids = {
    layanan: [] as string[],
    dokter: [] as string[],
    loket: [] as string[],
    links: [] as string[],
    weekly: [] as string[],
    sessions: [] as string[],
    slots: [] as string[],
    assignments: [] as string[],
    devices: [] as string[],
    tickets: [] as string[],
    appointments: [] as string[],
  };
  let seq = 0,
    staffId = '',
    userId = '';
  const auth = (role: PeranPengguna = PeranPengguna.ADMIN) => ({
    Authorization: `Bearer ${tokens[role]}`,
  });
  const endpoint = (resource: DeleteResource, id: string) =>
    `/api/v1/${resource}/${id}/permanen`;
  const date = new Date('2030-06-03T00:00:00Z');
  async function clinic() {
    const row = await db.layanan.create({
      data: {
        kode: `DEL${run}${++seq}`,
        nama: 'Delete fixture',
        prefixAntrean: 'D',
        durasiDasarMenit: 10,
        modeReservasi: 'HIBRIDA',
      },
    });
    ids.layanan.push(row.id);
    return row;
  }
  async function doctor() {
    const row = await db.dokter.create({
      data: { kode: `D${run}${++seq}`, nama: 'Doctor delete fixture' },
    });
    ids.dokter.push(row.id);
    return row;
  }
  async function room(layananId: string) {
    const row = await db.loket.create({
      data: { layananId, kode: `R${++seq}`, nama: 'Room fixture' },
    });
    ids.loket.push(row.id);
    return row;
  }
  async function context() {
    const c = await clinic(),
      d = await doctor(),
      r = await room(c.id);
    const link = await db.dokterLayanan.create({
      data: { dokterId: d.id, layananId: c.id },
    });
    ids.links.push(link.id);
    const weekly = await db.jadwalLayanan.create({
      data: {
        layananId: c.id,
        hari: HariLayanan.SENIN,
        jamBuka: new Date('1970-01-01T00:00:00Z'),
        jamTutup: new Date('1970-01-01T23:59:00Z'),
        kapasitasHarian: 100,
      },
    });
    ids.weekly.push(weekly.id);
    const session = await db.jadwalPraktik.create({
      data: {
        dokterLayananId: link.id,
        loketId: r.id,
        tanggal: date,
        mulaiPada: new Date('2030-06-03T01:00:00Z'),
        selesaiPada: new Date('2030-06-03T05:00:00Z'),
      },
    });
    ids.sessions.push(session.id);
    const slot = await db.slotPraktik.create({
      data: {
        jadwalPraktikId: session.id,
        mulaiPada: new Date('2030-06-03T01:00:00Z'),
        selesaiPada: new Date('2030-06-03T01:30:00Z'),
      },
    });
    ids.slots.push(slot.id);
    const assignment = await db.penugasanPetugas.create({
      data: { petugasId: staffId, loketId: r.id, tanggalMulai: date },
    });
    ids.assignments.push(assignment.id);
    return { c, d, r, link, weekly, session, slot, assignment };
  }
  async function device(layananId: string) {
    const response = await request(server)
      .post('/api/v1/perangkat-display')
      .set(auth())
      .send({ layananId, nama: 'TV Delete Fixture' })
      .expect(201);
    const id = response.body.id as string;
    ids.devices.push(id);
    return id;
  }
  beforeAll(async () => {
    const target = new URL(process.env.DATABASE_URL ?? 'http://invalid');
    if (
      target.hostname !== '127.0.0.1' ||
      target.port !== '5433' ||
      target.pathname !== '/capstone_antrean_test'
    )
      throw new Error(
        'Only isolated test DB 127.0.0.1:5433/capstone_antrean_test',
      );
    const mod = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = mod.createNestApplication();
    configureApp(app);
    await app.listen(0, '127.0.0.1');
    db = app.get(PrismaService);
    server = app.getHttpServer() as Server;
    expect(
      (await db.$queryRaw<{ db: string }[]>`SELECT current_database() AS db`)[0]
        .db,
    ).toBe('capstone_antrean_test');
    const password = `Fixture-${randomUUID()}!`,
      hash = await app.get(PasswordService).hash(password);
    for (const role of Object.values(PeranPengguna)) {
      const u = await db.pengguna.create({
        data: {
          nama: 'Admin delete test',
          email: `${role.toLowerCase()}-${run}@test.local`,
          kataSandiHash: hash,
          peran: role,
        },
      });
      users.push(u.id);
      if (role === 'PETUGAS') staffId = u.id;
      if (role === 'USER') userId = u.id;
      if (role === 'DOKTER') {
        const d = await doctor();
        await db.dokter.update({
          where: { id: d.id },
          data: { penggunaId: u.id },
        });
      }
      const login = await request(server)
        .post('/api/v1/auth/login')
        .send({ email: u.email, kataSandi: password })
        .expect(200);
      tokens[role] = login.body.accessToken as string;
    }
  }, 120000);
  afterAll(async () => {
    if (db) {
      await db.peristiwaAntrean.deleteMany({
        where: { tiketAntreanId: { in: ids.tickets } },
      });
      await db.janjiTemu.deleteMany({
        where: { id: { in: ids.appointments } },
      });
      await db.notifikasi.deleteMany({
        where: { tiketAntreanId: { in: ids.tickets } },
      });
      await db.tiketAntrean.deleteMany({ where: { id: { in: ids.tickets } } });
      await db.slotPraktik.deleteMany({ where: { id: { in: ids.slots } } });
      await db.jadwalPraktik.deleteMany({
        where: { id: { in: ids.sessions } },
      });
      await db.dokterLayanan.deleteMany({ where: { id: { in: ids.links } } });
      await db.penugasanPetugas.deleteMany({
        where: { id: { in: ids.assignments } },
      });
      await db.jadwalLayanan.deleteMany({ where: { id: { in: ids.weekly } } });
      await db.perangkatTampilan.deleteMany({
        where: { id: { in: ids.devices } },
      });
      await db.loket.deleteMany({ where: { id: { in: ids.loket } } });
      await db.dokter.deleteMany({ where: { id: { in: ids.dokter } } });
      await db.urutanAntreanHarian.deleteMany({
        where: { layananId: { in: ids.layanan } },
      });
      await db.layanan.deleteMany({ where: { id: { in: ids.layanan } } });
      await db.sesiPengguna.deleteMany({
        where: { penggunaId: { in: users } },
      });
      await db.pengguna.deleteMany({ where: { id: { in: users } } });
    }
    if (app) await app.close();
  });
  it.each(Object.keys(DELETE_RESOURCES) as DeleteResource[])(
    'requires ADMIN JWT for %s',
    async (resource) => {
      const url = endpoint(resource, randomUUID());
      await request(server).delete(url).expect(401);
      for (const role of [
        PeranPengguna.USER,
        PeranPengguna.PETUGAS,
        PeranPengguna.DOKTER,
      ])
        await request(server).delete(url).set(auth(role)).expect(403);
      await request(server).delete(url).set(auth()).expect(404);
    },
  );
  it.each(Object.keys(DELETE_RESOURCES) as DeleteResource[])(
    'deletes unused %s without deleting its parent/user',
    async (resource) => {
      let id: string;
      switch (resource) {
        case 'layanan':
          id = (await clinic()).id;
          break;
        case 'dokter': {
          const d = await doctor(),
            c = await clinic();
          const link = await db.dokterLayanan.create({
            data: { dokterId: d.id, layananId: c.id },
          });
          ids.links.push(link.id);
          id = d.id;
          break;
        }
        case 'loket':
          id = (await room((await clinic()).id)).id;
          break;
        case 'jadwal-layanan': {
          const c = await clinic();
          const w = await db.jadwalLayanan.create({
            data: {
              layananId: c.id,
              hari: 'SENIN',
              jamBuka: new Date('1970-01-01T01:00:00Z'),
              jamTutup: new Date('1970-01-01T02:00:00Z'),
              kapasitasHarian: 10,
            },
          });
          ids.weekly.push(w.id);
          id = w.id;
          break;
        }
        case 'jadwal-praktik': {
          const c = await context();
          await db.slotPraktik.delete({ where: { id: c.slot.id } });
          id = c.session.id;
          break;
        }
        case 'slot-praktik':
          id = (await context()).slot.id;
          break;
        case 'penugasan-petugas':
          id = (await context()).assignment.id;
          break;
        case 'perangkat-display':
          id = await device((await clinic()).id);
          break;
      }
      await request(server)
        .delete(endpoint(resource, id))
        .set(auth())
        .expect(200, { id, dihapus: true });
      await request(server)
        .delete(endpoint(resource, id))
        .set(auth())
        .expect(404);
      expect(await db.pengguna.count({ where: { id: { in: users } } })).toBe(4);
    },
  );
  it('protects booking/ticket/audit and indirect operational references', async () => {
    const c = await context();
    const ticket = await db.tiketAntrean.create({
      data: {
        penggunaId: userId,
        layananId: c.c.id,
        loketId: c.r.id,
        tanggalAntrean: date,
        nomorUrut: 1,
        kodeTiket: `D-${run}-${++seq}`,
      },
    });
    ids.tickets.push(ticket.id);
    const appointment = await db.janjiTemu.create({
      data: { tiketId: ticket.id, slotPraktikId: c.slot.id },
    });
    ids.appointments.push(appointment.id);
    const audit = await db.peristiwaAntrean.create({
      data: {
        tiketAntreanId: ticket.id,
        tipe: 'RESERVASI',
        statusSesudah: 'DIPESAN',
      },
    });
    const targets: [DeleteResource, string][] = [
      ['layanan', c.c.id],
      ['dokter', c.d.id],
      ['loket', c.r.id],
      ['jadwal-layanan', c.weekly.id],
      ['jadwal-praktik', c.session.id],
      ['slot-praktik', c.slot.id],
      ['penugasan-petugas', c.assignment.id],
    ];
    for (const [resource, id] of targets) {
      const r = await request(server)
        .delete(endpoint(resource, id))
        .set(auth())
        .expect(409);
      expect(r.body.message).toContain('Nonaktifkan');
    }
    expect(
      await db.tiketAntrean.findUnique({ where: { id: ticket.id } }),
    ).toEqual(ticket);
    expect(
      await db.janjiTemu.findUnique({ where: { id: appointment.id } }),
    ).toEqual(appointment);
    expect(
      await db.peristiwaAntrean.findUnique({ where: { id: audit.id } }),
    ).toEqual(audit);
  });
  it('serializes two simultaneous deletes without an unhandled error', async () => {
    const c = await clinic();
    const responses = await Promise.all([
      request(server).delete(endpoint('layanan', c.id)).set(auth()),
      request(server).delete(endpoint('layanan', c.id)).set(auth()),
    ]);
    expect(responses.filter((r) => r.status === 200)).toHaveLength(1);
    expect(responses.every((r) => [200, 404, 409].includes(r.status))).toBe(
      true,
    );
    expect(await db.layanan.findUnique({ where: { id: c.id } })).toBeNull();
  });
  it('serializes deletion against concurrent appointment booking', async () => {
    const c = await context();
    const [deletion, booking] = await Promise.all([
      request(server).delete(endpoint('slot-praktik', c.slot.id)).set(auth()),
      request(server)
        .post('/api/v1/janji-temu')
        .set(auth(PeranPengguna.USER))
        .send({ slotPraktikId: c.slot.id }),
    ]);
    if (booking.status === 201) {
      const appointment = booking.body as { id: string; tiketId: string };
      ids.appointments.push(appointment.id);
      ids.tickets.push(appointment.tiketId);
      expect(deletion.status).toBe(409);
      expect(
        await db.slotPraktik.findUnique({ where: { id: c.slot.id } }),
      ).not.toBeNull();
    } else {
      expect([404, 409]).toContain(booking.status);
      expect(deletion.status).toBe(200);
      expect(
        await db.janjiTemu.count({ where: { slotPraktikId: c.slot.id } }),
      ).toBe(0);
    }
  });
  it('rejects a doctor linked to an existing account without changing the account', async () => {
    const d = await doctor();
    await db.dokter.update({
      where: { id: d.id },
      data: { penggunaId: userId },
    });
    await request(server)
      .delete(endpoint('dokter', d.id))
      .set(auth())
      .expect(409);
    expect(
      await db.pengguna.findUnique({ where: { id: userId } }),
    ).not.toBeNull();
  });
  it('keeps legacy deactivate semantics', async () => {
    const c = await clinic();
    await request(server)
      .delete(`/api/v1/layanan/${c.id}`)
      .set(auth())
      .expect(200);
    expect(
      (await db.layanan.findUniqueOrThrow({ where: { id: c.id } })).aktif,
    ).toBe(false);
  });
  it('revokes a paired display, old code, reconnect and REST session; rename preserves credentials', async () => {
    const c = await clinic(),
      id = await device(c.id);
    const activation = await request(server)
      .post(`/api/v1/perangkat-display/${id}/aktivasi`)
      .set(auth())
      .expect(200);
    const pair = await request(server)
      .post('/api/v1/display/pairing')
      .send({ kode: activation.body.kode })
      .expect(200);
    const cookie = (pair.headers['set-cookie'] as unknown as string[])[0].split(
      ';',
    )[0];
    const before = await db.perangkatTampilan.findUniqueOrThrow({
      where: { id },
    });
    await request(server)
      .patch(`/api/v1/perangkat-display/${id}`)
      .set(auth())
      .send({ nama: 'TV Renamed Fixture' })
      .expect(200);
    const after = await db.perangkatTampilan.findUniqueOrThrow({
      where: { id },
    });
    expect(after.tokenHash).toBe(before.tokenHash);
    const address = server.address();
    if (!address || typeof address === 'string') throw new Error('No server');
    const socket: Socket = io(`http://127.0.0.1:${address.port}/display`, {
      transports: ['websocket'],
      auth: { layananId: c.id },
      extraHeaders: { cookie },
      reconnection: false,
      autoConnect: false,
    });
    try {
      await new Promise<void>((resolve, reject) => {
        socket.once('display:ready', () => resolve());
        socket.once('connect_error', reject);
        socket.connect();
      });
      const disconnected = new Promise<void>((resolve) =>
        socket.once('disconnect', () => resolve()),
      );
      await request(server)
        .delete(endpoint('perangkat-display', id))
        .set(auth())
        .expect(200);
      await disconnected;
      await request(server)
        .get('/api/v1/display/sesi')
        .set('Cookie', cookie)
        .expect(401);
      await request(server)
        .post('/api/v1/display/pairing')
        .send({ kode: activation.body.kode })
        .expect(401);
      await new Promise<void>((resolve, reject) => {
        socket.once('connect_error', () => resolve());
        socket.once('connect', () =>
          reject(new Error('Deleted device reconnected')),
        );
        socket.connect();
      });
    } finally {
      socket.disconnect();
    }
  });
});
