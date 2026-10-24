import { randomUUID } from 'node:crypto';
import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/configure-app';
import { AuthService } from '../src/auth/auth.service';
import { PasswordService } from '../src/auth/password.service';
import { PrismaService } from '../src/prisma/prisma.service';
import { PeranPengguna } from '../src/generated/prisma/client';

describe('ADMIN management P0 (isolated)', () => {
  let app: INestApplication, db: PrismaService;
  const run = randomUUID().slice(0, 8),
    password = `P0-${randomUUID()}!`;
  const tokens = {} as Record<PeranPengguna, string>;
  const users: string[] = [],
    doctors: string[] = [],
    rooms: string[] = [];
  let clinicId = '',
    staffId = '',
    staffToken = '',
    refresh = '',
    assignmentId = '';
  const auth = (role: PeranPengguna = 'ADMIN') => ({
    Authorization: `Bearer ${tokens[role]}`,
  });
  const server = () => app.getHttpServer() as Parameters<typeof request>[0];
  const accountPath = '/api/v1/akun-petugas';
  const assignmentPath = '/api/v1/penugasan-petugas';
  const assignment = (
    id: string,
    start = '2035-01-10',
    end: string | null = '2035-01-20',
  ) => ({
    petugasId: id,
    loketId: rooms[0],
    tanggalMulai: start,
    tanggalSelesai: end,
  });
  async function createStaff(label: string) {
    const result = await request(server())
      .post(accountPath)
      .set(auth())
      .send({
        nama: `Petugas ${label}`,
        email: `${label}-${run}@p0.test`,
        kataSandi: password,
      })
      .expect(201);
    users.push(result.body.id as string);
    return result.body as {
      id: string;
      nama: string;
      email: string;
      aktif: boolean;
      peran: string;
    };
  }
  beforeAll(async () => {
    const target = new URL(process.env.DATABASE_URL ?? 'http://invalid');
    if (
      target.hostname !== '127.0.0.1' ||
      target.port !== '5433' ||
      target.pathname !== '/capstone_antrean_test'
    )
      throw new Error('P0 E2E requires 127.0.0.1:5433/capstone_antrean_test');
    const mod = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = mod.createNestApplication();
    configureApp(app);
    await app.init();
    db = app.get(PrismaService);
    expect(
      (await db.$queryRaw<{ db: string }[]>`SELECT current_database() AS db`)[0]
        .db,
    ).toBe('capstone_antrean_test');
    const hash = await app.get(PasswordService).hash(password);
    for (const role of Object.values(PeranPengguna)) {
      const u = await db.pengguna.create({
        data: {
          nama: `P0 ${role}`,
          email: `${role.toLowerCase()}-${run}@p0.test`,
          kataSandiHash: hash,
          peran: role,
        },
      });
      users.push(u.id);
      if (role === 'DOKTER') {
        const d = await db.dokter.create({
          data: { kode: `P0${run}`, nama: 'Dokter P0', penggunaId: u.id },
        });
        doctors.push(d.id);
      }
      tokens[role] = (
        await app
          .get(AuthService)
          .login({ email: u.email, kataSandi: password })
      ).accessToken;
    }
    const clinic = await db.layanan.create({
      data: {
        kode: `P0${run}`,
        nama: 'Poliklinik P0',
        prefixAntrean: 'P',
        durasiDasarMenit: 15,
      },
    });
    clinicId = clinic.id;
    for (const kode of ['P01', 'P02']) {
      const room = await db.loket.create({
        data: { layananId: clinicId, kode, nama: `Ruang ${kode}` },
      });
      rooms.push(room.id);
    }
  });
  afterAll(async () => {
    if (db) {
      await db.penugasanPetugas.deleteMany({
        where: { petugasId: { in: users } },
      });
      await db.dokterLayanan.deleteMany({
        where: { dokterId: { in: doctors } },
      });
      await db.loket.deleteMany({ where: { id: { in: rooms } } });
      if (clinicId) await db.layanan.delete({ where: { id: clinicId } });
      await db.dokter.deleteMany({ where: { id: { in: doctors } } });
      await db.sesiPengguna.deleteMany({
        where: { penggunaId: { in: users } },
      });
      await db.pengguna.deleteMany({ where: { id: { in: users } } });
    }
    await app?.close();
  });

  it('requires JWT and ADMIN for account list/create/status and doctor account directory', async () => {
    await request(server()).get(accountPath).expect(401);
    for (const role of ['USER', 'PETUGAS', 'DOKTER'] as const) {
      await request(server()).get(accountPath).set(auth(role)).expect(403);
      await request(server())
        .post(accountPath)
        .set(auth(role))
        .send({})
        .expect(403);
      await request(server())
        .patch(`${accountPath}/${users[0]}`)
        .set(auth(role))
        .send({ aktif: false })
        .expect(403);
      await request(server())
        .get('/api/v1/dokter/akun-tersedia')
        .set(auth(role))
        .expect(403);
    }
  });
  it('creates fixed-role PETUGAS, normalizes email, hashes password and returns only safe metadata', async () => {
    const created = await createStaff('baru');
    staffId = created.id;
    expect(created.peran).toBe('PETUGAS');
    expect(created.aktif).toBe(true);
    expect(Object.keys(created).sort()).toEqual([
      'aktif',
      'email',
      'id',
      'nama',
      'peran',
    ]);
    const stored = await db.pengguna.findUniqueOrThrow({
      where: { id: staffId },
    });
    expect(stored.kataSandiHash).not.toBe(password);
    expect(
      await app.get(PasswordService).verify(password, stored.kataSandiHash),
    ).toBe(true);
    const list = await request(server())
      .get(accountPath)
      .set(auth())
      .expect(200);
    expect((list.body as { id: string }[]).some((a) => a.id === staffId)).toBe(
      true,
    );
    await request(server())
      .post(accountPath)
      .set(auth())
      .send({
        nama: 'Petugas duplikat',
        email: created.email.toUpperCase(),
        kataSandi: password,
      })
      .expect(409);
    await request(server())
      .post(accountPath)
      .set(auth())
      .send({
        nama: 'Petugas ilegal',
        email: `role-${run}@p0.test`,
        kataSandi: password,
        peran: 'ADMIN',
      })
      .expect(400);
  });
  it('assigns a new account without prior assignment and rejects inclusive boundary overlap', async () => {
    const result = await request(server())
      .post(assignmentPath)
      .set(auth())
      .send(assignment(staffId))
      .expect(201);
    assignmentId = result.body.id as string;
    expect(result.body.petugas.aktif).toBe(true);
    await request(server())
      .post(assignmentPath)
      .set(auth())
      .send({
        ...assignment(staffId, '2035-01-20', '2035-01-21'),
        loketId: rooms[1],
      })
      .expect(409);
  });
  it('revokes sessions on account disable, rejects assignments and requires fresh login after reactivation', async () => {
    const login = await request(server())
      .post('/api/v1/auth/login')
      .send({ email: `baru-${run}@p0.test`, kataSandi: password })
      .expect(200);
    staffToken = login.body.accessToken as string;
    refresh = login.body.refreshToken as string;
    await request(server())
      .patch(`${accountPath}/${staffId}`)
      .set(auth())
      .send({ aktif: false })
      .expect(200);
    await request(server())
      .get('/api/v1/auth/me')
      .set({ Authorization: `Bearer ${staffToken}` })
      .expect(401);
    await request(server())
      .post('/api/v1/auth/refresh')
      .send({ refreshToken: refresh })
      .expect(401);
    await request(server())
      .post('/api/v1/auth/login')
      .send({ email: `baru-${run}@p0.test`, kataSandi: password })
      .expect(401);
    await request(server())
      .post(assignmentPath)
      .set(auth())
      .send(assignment(staffId, '2035-02-01', null))
      .expect(400);
    await request(server())
      .patch(`${assignmentPath}/${assignmentId}`)
      .set(auth())
      .send({ actif: true })
      .expect(400);
    await request(server())
      .patch(`${assignmentPath}/${assignmentId}`)
      .set(auth())
      .send({ aktif: true })
      .expect(400);
    // Ending an assignment stays possible even if its account is disabled.
    await request(server())
      .delete(`${assignmentPath}/${assignmentId}`)
      .set(auth())
      .expect(200);
    await request(server())
      .patch(`${accountPath}/${staffId}`)
      .set(auth())
      .send({ aktif: true })
      .expect(200);
    await request(server())
      .get('/api/v1/auth/me')
      .set({ Authorization: `Bearer ${staffToken}` })
      .expect(401);
    await request(server())
      .post('/api/v1/auth/refresh')
      .send({ refreshToken: refresh })
      .expect(401);
    await request(server())
      .post('/api/v1/auth/login')
      .send({ email: `baru-${run}@p0.test`, kataSandi: password })
      .expect(200);
  });
  it('does not change another role and validates status input', async () => {
    await request(server())
      .patch(`${accountPath}/${users[0]}`)
      .set(auth())
      .send({ aktif: false })
      .expect(404);
    await request(server())
      .patch(`${accountPath}/${randomUUID()}`)
      .set(auth())
      .send({ aktif: false })
      .expect(404);
    await request(server())
      .patch(`${accountPath}/${staffId}`)
      .set(auth())
      .send({ aktif: 'false' })
      .expect(400);
    await request(server())
      .patch(`${accountPath}/${staffId}`)
      .set(auth())
      .send({ aktif: true, peran: 'ADMIN' })
      .expect(400);
  });
  it('serializes simultaneous overlapping creates across different counters', async () => {
    const staff = await createStaff('parallel');
    const results = await Promise.all(
      rooms.map((loketId) =>
        request(server())
          .post(assignmentPath)
          .set(auth())
          .send({ ...assignment(staff.id), loketId }),
      ),
    );
    expect(results.map((r) => r.status).sort((a, b) => a - b)).toEqual([
      201, 409,
    ]);
    expect(
      await db.penugasanPetugas.count({
        where: { petugasId: staff.id, aktif: true },
      }),
    ).toBe(1);
  });
  it('serializes concurrent updates and allows different staff in one counter', async () => {
    const staff = await createStaff('update');
    const ids: string[] = [];
    for (const [start, end] of [
      ['2035-03-01', '2035-03-02'],
      ['2035-04-01', '2035-04-02'],
    ]) {
      const r = await request(server())
        .post(assignmentPath)
        .set(auth())
        .send(assignment(staff.id, start, end))
        .expect(201);
      ids.push(r.body.id as string);
    }
    const results = await Promise.all(
      ids.map((id) =>
        request(server())
          .patch(`${assignmentPath}/${id}`)
          .set(auth())
          .send({ tanggalMulai: '2035-05-01', tanggalSelesai: '2035-05-02' }),
      ),
    );
    expect(results.map((r) => r.status).sort((a, b) => a - b)).toEqual([
      200, 409,
    ]);
    const other = await createStaff('same-room');
    await request(server())
      .post(assignmentPath)
      .set(auth())
      .send(assignment(other.id, '2035-05-01', '2035-05-02'))
      .expect(201);
  });
  it('lists only unlinked active doctor accounts, keeps provisioning and privacy intact', async () => {
    const hash = await app.get(PasswordService).hash(password);
    const u = await db.pengguna.create({
      data: {
        nama: 'Dokter tersedia',
        email: `doctor-link-${run}@p0.test`,
        kataSandiHash: hash,
        peran: 'DOKTER',
      },
    });
    users.push(u.id);
    const d = await db.dokter.create({
      data: { kode: `D${run}`, nama: 'Dokter baru P0' },
    });
    doctors.push(d.id);
    const available = await request(server())
      .get('/api/v1/dokter/akun-tersedia')
      .set(auth())
      .expect(200);
    expect(
      (available.body as { id: string }[]).some((a) => a.id === u.id),
    ).toBe(true);
    await request(server())
      .post(`/api/v1/dokter/${d.id}/akun`)
      .set(auth())
      .send({ penggunaId: u.id })
      .expect(201);
    const detail = await request(server())
      .get(`/api/v1/dokter/${d.id}`)
      .set(auth())
      .expect(200);
    expect(detail.body.pengguna).toEqual({
      nama: u.nama,
      email: u.email,
      aktif: true,
    });
    expect(JSON.stringify(detail.body)).not.toContain('kataSandiHash');
    const remaining = await request(server())
      .get('/api/v1/dokter/akun-tersedia')
      .set(auth())
      .expect(200);
    expect(
      (remaining.body as { id: string }[]).some((a) => a.id === u.id),
    ).toBe(false);
    await db.dokterLayanan.create({
      data: { dokterId: d.id, layananId: clinicId },
    });
    const publicCatalog = await request(server())
      .get('/api/v1/dokter')
      .set(auth('USER'))
      .expect(200);
    expect(JSON.stringify(publicCatalog.body)).not.toContain(u.email);
    const publicDoctor = (publicCatalog.body as { id: string }[]).find(
      (row) => row.id === d.id,
    );
    expect(publicDoctor).toBeDefined();
    expect(publicDoctor).not.toHaveProperty('pengguna');
    expect(publicDoctor).not.toHaveProperty('penggunaId');
  });
});
