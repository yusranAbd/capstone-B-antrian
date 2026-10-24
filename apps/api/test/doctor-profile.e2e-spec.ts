import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { ThrottlerStorage } from '@nestjs/throttler';
import { randomUUID } from 'node:crypto';
import { readdir, rmdir, unlink } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import sharp from 'sharp';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { PasswordService } from '../src/auth/password.service';
import { configureApp } from '../src/configure-app';
import { DOCTOR_MEDIA_ROOT } from '../src/dokter/doctor-photo.service';
import type { PeranPengguna } from '../src/generated/prisma/client';
import { PrismaService } from '../src/prisma/prisma.service';

describe('Doctor professional profile P1 (isolated e2e)', () => {
  let app: INestApplication,
    db: PrismaService,
    doctorId: string,
    clinicId: string;
  let png: Buffer;
  const users: string[] = [],
    tokens: Partial<Record<PeranPengguna, string>> = {};
  const uid = randomUUID(),
    password = `Profile-${uid}`;
  const root = resolve('.queueb-media', `qa-${uid}`);
  const auth = (role: PeranPengguna) => `Bearer ${tokens[role]}`;
  const http = () => app.getHttpServer();
  const photo = () => `/api/v1/dokter/${doctorId}/foto`;
  beforeAll(async () => {
    const url = new URL(process.env.DATABASE_URL!);
    if (
      url.hostname !== '127.0.0.1' ||
      url.port !== '5433' ||
      url.pathname !== '/capstone_antrean_test'
    )
      throw Error('Unsafe test target');
    const mod = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(DOCTOR_MEDIA_ROOT)
      .useValue(root)
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
    await app.init();
    db = app.get(PrismaService);
    expect(
      (
        await db.$queryRaw<Array<{ db: string }>>`SELECT current_database() db`
      )[0].db,
    ).toBe('capstone_antrean_test');
    const hash = await app.get(PasswordService).hash(password);
    let doctorAccount = '',
      doctorEmail = '';
    for (const role of ['ADMIN', 'USER', 'PETUGAS', 'DOKTER'] as const) {
      const u = await db.pengguna.create({
        data: {
          nama: `QA ${role}`,
          email: `${uid}-${role.toLowerCase()}@profile.test`,
          peran: role,
          kataSandiHash: hash,
        },
      });
      users.push(u.id);
      if (role === 'DOKTER') {
        doctorAccount = u.id;
        doctorEmail = u.email;
        continue;
      }
      const r = await request(http())
        .post('/api/v1/auth/login')
        .send({ email: u.email, kataSandi: password })
        .expect(200);
      tokens[role] = (r.body as { accessToken: string }).accessToken;
    }
    const c = await db.layanan.create({
      data: {
        kode: `P${uid.slice(0, 8)}`,
        nama: 'Poli profil QA',
        prefixAntrean: 'P',
        durasiDasarMenit: 10,
      },
    });
    clinicId = c.id;
    const d = await request(http())
      .post('/api/v1/dokter')
      .set('Authorization', auth('ADMIN'))
      .send({
        kode: `D${uid.slice(0, 8).toUpperCase()}`,
        nama: 'Dokter Profil QA',
        spesialisasi: 'Anak',
      })
      .expect(201);
    doctorId = (d.body as { id: string }).id;
    await request(http())
      .post(`/api/v1/dokter/${doctorId}/layanan`)
      .set('Authorization', auth('ADMIN'))
      .send({ layananId: clinicId })
      .expect(201);
    await request(http())
      .post(`/api/v1/dokter/${doctorId}/akun`)
      .set('Authorization', auth('ADMIN'))
      .send({ penggunaId: doctorAccount })
      .expect(201);
    const doctorLogin = await request(http())
      .post('/api/v1/auth/login')
      .send({ email: doctorEmail, kataSandi: password })
      .expect(200);
    tokens.DOKTER = (doctorLogin.body as { accessToken: string }).accessToken;
    png = await sharp({
      create: { width: 40, height: 50, channels: 3, background: 'teal' },
    })
      .png()
      .toBuffer();
  }, 60000);
  afterAll(async () => {
    if (db) {
      await db.dokterLayanan.deleteMany({
        where: { dokterId: doctorId ?? randomUUID() },
      });
      await db.dokter.deleteMany({ where: { id: doctorId ?? randomUUID() } });
      await db.layanan.deleteMany({ where: { id: clinicId ?? randomUUID() } });
      await db.sesiPengguna.deleteMany({
        where: { penggunaId: { in: users } },
      });
      await db.pengguna.deleteMany({ where: { id: { in: users } } });
    }
    await app?.close();
    // Only this suite's generated files and unique directory; never other media.
    try {
      for (const file of await readdir(root)) {
        if (!/^[0-9a-f-]+\.webp$/.test(file)) throw Error('Unexpected QA file');
        await unlink(join(root, file));
      }
      await rmdir(root);
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code !== 'ENOENT') throw e;
    }
  });
  it('keeps existing profiles with optional fields valid and rejects direct media reference injection', async () => {
    const r = await request(http())
      .get(`/api/v1/dokter/${doctorId}`)
      .set('Authorization', auth('USER'))
      .expect(200);
    expect(r.body).toMatchObject({ fotoProfil: null, tentangDokter: null });
    await request(http())
      .patch(`/api/v1/dokter/${doctorId}`)
      .set('Authorization', auth('ADMIN'))
      .send({ fotoProfil: '/etc/passwd' })
      .expect(400);
  });
  it.each(['USER', 'PETUGAS', 'DOKTER'] as const)(
    'rejects %s photo/biography mutations while permitting profile reads',
    async (role) => {
      await request(http())
        .post(photo())
        .set('Authorization', auth(role))
        .attach('foto', png, 'photo.png')
        .expect(403);
      await request(http())
        .delete(photo())
        .set('Authorization', auth(role))
        .expect(403);
      await request(http())
        .patch(`/api/v1/dokter/${doctorId}`)
        .set('Authorization', auth(role))
        .send({ tentangDokter: 'Not allowed' })
        .expect(403);
      await request(http())
        .get(`/api/v1/dokter/${doctorId}`)
        .set('Authorization', auth(role))
        .expect(200);
    },
  );
  it('requires JWT and validates content, upload field, size and biography length', async () => {
    await request(http())
      .post(photo())
      .attach('foto', png, 'photo.png')
      .expect(401);
    await request(http())
      .post(photo())
      .set('Authorization', auth('ADMIN'))
      .attach('foto', Buffer.from('<script>alert(1)</script>'), 'photo.png')
      .expect(400);
    await request(http())
      .post(photo())
      .set('Authorization', auth('ADMIN'))
      .attach('foto', Buffer.alloc(2 * 1024 * 1024 + 1), 'photo.jpg')
      .expect(413);
    await request(http())
      .post(photo())
      .set('Authorization', auth('ADMIN'))
      .attach('wrong', png, 'photo.png')
      .expect(400);
    await request(http())
      .post(photo())
      .set('Authorization', auth('ADMIN'))
      .expect(400);
    await request(http())
      .patch(`/api/v1/dokter/${doctorId}`)
      .set('Authorization', auth('ADMIN'))
      .send({ tentangDokter: 'a'.repeat(1501) })
      .expect(400);
  });
  it('saves trimmed biography and uploads a safe photo readable by patient and doctor without internal paths', async () => {
    await request(http())
      .patch(`/api/v1/dokter/${doctorId}`)
      .set('Authorization', auth('ADMIN'))
      .send({ tentangDokter: '  Dokter spesialis anak.  ' })
      .expect(200);
    const r = await request(http())
      .post(photo())
      .set('Authorization', auth('ADMIN'))
      .attach('foto', png, '../../private.png')
      .expect(201);
    const ref = (r.body as { fotoProfil: string }).fotoProfil;
    expect(ref).toMatch(/^\/media\/dokter\/[0-9a-f-]+\.webp$/);
    const image = await request(http())
      .get('/api/v1' + ref)
      .expect(200)
      .expect('Content-Type', /image\/webp/)
      .expect('X-Content-Type-Options', 'nosniff');
    expect((await sharp(image.body as Buffer).metadata()).format).toBe('webp');
    for (const path of [`/dokter/${doctorId}`, '/portal-dokter/profil']) {
      const profile = await request(http())
        .get('/api/v1' + path)
        .set('Authorization', auth(path.includes('portal') ? 'DOKTER' : 'USER'))
        .expect(200);
      expect(profile.body).toMatchObject({
        fotoProfil: ref,
        tentangDokter: 'Dokter spesialis anak.',
      });
      expect(JSON.stringify(profile.body)).not.toMatch(
        /\.queueb-media|[A-Z]:\\|kataSandiHash/,
      );
    }
    const list = await request(http())
      .get('/api/v1/dokter')
      .set('Authorization', auth('USER'))
      .expect(200);
    expect(
      (list.body as Array<{ id: string; fotoProfil: string }>).find(
        (d) => d.id === doctorId,
      )?.fotoProfil,
    ).toBe(ref);
  });
  it('keeps the existing photo readable when a replacement is invalid', async () => {
    const old = await db.dokter.findUniqueOrThrow({ where: { id: doctorId } });
    await request(http())
      .post(photo())
      .set('Authorization', auth('ADMIN'))
      .attach('foto', Buffer.from('invalid replacement'), 'photo.jpg')
      .expect(400);
    expect(
      (await db.dokter.findUniqueOrThrow({ where: { id: doctorId } }))
        .fotoProfil,
    ).toBe(old.fotoProfil);
    await request(http())
      .get('/api/v1' + old.fotoProfil)
      .expect(200);
  });
  it.each(['jpeg', 'webp'] as const)(
    'replaces photo using %s bytes and makes the old reference unreadable',
    async (format) => {
      const old = await db.dokter.findUniqueOrThrow({
        where: { id: doctorId },
      });
      const bytes = await sharp(png).toFormat(format).toBuffer();
      const r = await request(http())
        .post(photo())
        .set('Authorization', auth('ADMIN'))
        .attach('foto', bytes, 'not-an-extension')
        .expect(201);
      expect((r.body as { fotoProfil: string }).fotoProfil).not.toBe(
        old.fotoProfil,
      );
      await request(http())
        .get('/api/v1' + old.fotoProfil)
        .expect(404);
      expect((await readdir(root)).length).toBe(1);
    },
  );
  it('serializes concurrent replacement, keeping only the committed reference readable', async () => {
    const results = await Promise.all(
      [1, 2].map(() =>
        request(http())
          .post(photo())
          .set('Authorization', auth('ADMIN'))
          .attach('foto', png, 'photo.png')
          .expect(201),
      ),
    );
    const current = await db.dokter.findUniqueOrThrow({
      where: { id: doctorId },
    });
    for (const r of results) {
      const ref = (r.body as { fotoProfil: string }).fotoProfil;
      await request(http())
        .get('/api/v1' + ref)
        .expect(ref === current.fotoProfil ? 200 : 404);
    }
    expect((await readdir(root)).length).toBe(1);
  });
  it('removes photo idempotently, clears biography with null, and forbids file enumeration', async () => {
    const old = await db.dokter.findUniqueOrThrow({ where: { id: doctorId } });
    await request(http())
      .delete(photo())
      .set('Authorization', auth('ADMIN'))
      .expect(200, { id: doctorId, fotoProfil: null });
    await request(http())
      .delete(photo())
      .set('Authorization', auth('ADMIN'))
      .expect(200);
    await request(http())
      .get('/api/v1' + old.fotoProfil)
      .expect(404);
    await request(http()).get('/api/v1/media/dokter/private.env').expect(404);
    await request(http()).get('/api/v1/media/dokter').expect(404);
    await request(http())
      .patch(`/api/v1/dokter/${doctorId}`)
      .set('Authorization', auth('ADMIN'))
      .send({ tentangDokter: null })
      .expect(200);
    expect(
      (await db.dokter.findUniqueOrThrow({ where: { id: doctorId } }))
        .tentangDokter,
    ).toBeNull();
    expect(await readdir(root)).toEqual([]);
  });
  it('returns 404 for missing doctor without leaving orphaned uploaded files', async () => {
    await request(http())
      .post(`/api/v1/dokter/${randomUUID()}/foto`)
      .set('Authorization', auth('ADMIN'))
      .attach('foto', png, 'photo.png')
      .expect(404);
    expect(await readdir(root)).toEqual([]);
  });
});
