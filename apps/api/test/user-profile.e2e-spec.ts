import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { ThrottlerGuard } from '@nestjs/throttler';
import { randomUUID } from 'node:crypto';
import { readdir, unlink, rmdir } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import sharp from 'sharp';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { PasswordService } from '../src/auth/password.service';
import { USER_AVATAR_ROOT } from '../src/auth/profile/user-avatar.service';
import { configureApp } from '../src/configure-app';
import { DOCTOR_MEDIA_ROOT } from '../src/dokter/doctor-photo.service';
import type { PeranPengguna } from '../src/generated/prisma/client';
import { PrismaService } from '../src/prisma/prisma.service';

describe('Profil akun P2 (database test terisolasi)', () => {
  let app: INestApplication, db: PrismaService, doctorId: string, png: Buffer;
  const uid = randomUUID(),
    password = `P2-${uid}`,
    root = resolve('.queueb-media', `qa-user-${uid}`),
    doctorRoot = resolve('.queueb-media', `qa-doctor-${uid}`);
  const users: Partial<
      Record<
        PeranPengguna,
        { id: string; email: string; access: string; refresh: string }
      >
    > = {},
    ids: string[] = [];
  const http = () => app.getHttpServer(),
    auth = (role: PeranPengguna) => `Bearer ${users[role]!.access}`;
  beforeAll(async () => {
    const url = new URL(process.env.DATABASE_URL!);
    if (
      url.hostname !== '127.0.0.1' ||
      url.port !== '5433' ||
      url.pathname !== '/capstone_antrean_test'
    )
      throw Error('Unsafe target');
    const mod = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(USER_AVATAR_ROOT)
      .useValue(root)
      .overrideProvider(DOCTOR_MEDIA_ROOT)
      .useValue(doctorRoot)
      .overrideGuard(ThrottlerGuard)
      .useValue({ canActivate: () => true })
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
    for (const role of ['ADMIN', 'PETUGAS', 'DOKTER', 'USER'] as const) {
      const u = await db.pengguna.create({
        data: {
          nama: `Profil QA ${role}`,
          email: `${uid}-${role.toLowerCase()}@user-profile.test`,
          kataSandiHash: hash,
          peran: role,
        },
      });
      ids.push(u.id);
      if (role === 'DOKTER')
        doctorId = (
          await db.dokter.create({
            data: {
              kode: `P2${uid.slice(0, 8)}`,
              nama: 'Dokter profesional QA',
              penggunaId: u.id,
              tentangDokter: 'Biografi profesional tetap utuh.',
            },
          })
        ).id;
      const login = await request(http())
        .post('/api/v1/auth/login')
        .send({ email: u.email, kataSandi: password })
        .expect(200);
      users[role] = {
        id: u.id,
        email: u.email,
        access: login.body.accessToken as string,
        refresh: login.body.refreshToken as string,
      };
    }
    png = await sharp({
      create: { width: 24, height: 24, channels: 3, background: '#009f9a' },
    })
      .png()
      .toBuffer();
    // Account avatars must preserve a real, non-null professional P1 photo.
    await request(http())
      .post(`/api/v1/dokter/${doctorId}/foto`)
      .set('Authorization', auth('ADMIN'))
      .attach('foto', png, 'professional.png')
      .expect(201);
  });
  afterAll(async () => {
    if (db) {
      await db.sesiPengguna.deleteMany({ where: { penggunaId: { in: ids } } });
      if (doctorId) await db.dokter.deleteMany({ where: { id: doctorId } });
      await db.pengguna.deleteMany({ where: { id: { in: ids } } });
    }
    for (const dir of [root, doctorRoot]) {
      for (const name of await readdir(dir).catch(() => []))
        await unlink(join(dir, name));
      await rmdir(dir).catch(() => {});
    }
    await app?.close();
  });
  it.each(['ADMIN', 'PETUGAS', 'DOKTER', 'USER'] as const)(
    '%s membaca dan mengubah nama sendiri tanpa mengubah kewenangan',
    async (role) => {
      const me = await request(http())
        .get('/api/v1/auth/me')
        .set('Authorization', auth(role))
        .expect(200);
      expect(me.body).toMatchObject({
        id: users[role]!.id,
        peran: role,
        aktif: true,
        avatarProfil: null,
      });
      expect(me.body.kataSandiHash).toBeUndefined();
      const changed = await request(http())
        .patch('/api/v1/auth/me')
        .set('Authorization', auth(role))
        .send({ nama: `  Nama Baru ${role}  ` })
        .expect(200);
      expect(changed.body).toMatchObject({
        id: users[role]!.id,
        nama: `Nama Baru ${role}`,
        peran: role,
        aktif: true,
      });
    },
  );
  it.each([
    { peran: 'ADMIN' },
    { aktif: false },
    { id: randomUUID() },
    { userId: randomUUID() },
    { email: 'lain@test.local' },
    { avatarProfil: '/media/dokter/injeksi.webp' },
  ])('menolak mass assignment %j', async (unsafe) => {
    await request(http())
      .patch('/api/v1/auth/me')
      .set('Authorization', auth('USER'))
      .send({ nama: 'Nama Aman', ...unsafe })
      .expect(400);
  });
  it('menolak nama invalid serta akses tanpa JWT dan endpoint pengguna lain', async () => {
    for (const nama of ['  ', 'x'.repeat(151)])
      await request(http())
        .patch('/api/v1/auth/me')
        .set('Authorization', auth('USER'))
        .send({ nama })
        .expect(400);
    await request(http())
      .patch('/api/v1/auth/me')
      .send({ nama: 'Tidak Sah' })
      .expect(401);
    await request(http())
      .patch(`/api/v1/auth/me/${users.ADMIN!.id}`)
      .set('Authorization', auth('USER'))
      .send({ nama: 'Tidak Sah' })
      .expect(404);
  });
  it.each(['ADMIN', 'PETUGAS', 'DOKTER', 'USER'] as const)(
    '%s upload, baca privat, ganti dan hapus avatar sendiri',
    async (role) => {
      const professional = await db.dokter.findUniqueOrThrow({
        where: { id: doctorId },
      });
      const first = await request(http())
        .post('/api/v1/auth/me/avatar')
        .set('Authorization', auth(role))
        .attach('foto', png, 'foto.png')
        .expect(201);
      expect(first.body).toMatchObject({
        id: users[role]!.id,
        avatarProfil: expect.stringMatching(
          /^\/media\/avatar\/[0-9a-f-]+\.webp$/,
        ),
      });
      const media = await request(http())
        .get('/api/v1/auth/me/avatar')
        .set('Authorization', auth(role))
        .expect('Content-Type', /image\/webp/)
        .expect('Cache-Control', 'private, no-store')
        .expect(200);
      expect((await sharp(media.body as Buffer).metadata()).format).toBe(
        'webp',
      );
      const replacement = await request(http())
        .post('/api/v1/auth/me/avatar')
        .set('Authorization', auth(role))
        .attach('foto', png, 'foto.png')
        .expect(201);
      expect(replacement.body.avatarProfil).not.toBe(first.body.avatarProfil);
      await request(http())
        .delete('/api/v1/auth/me/avatar')
        .set('Authorization', auth(role))
        .expect(200);
      await request(http())
        .delete('/api/v1/auth/me/avatar')
        .set('Authorization', auth(role))
        .expect(200);
      await request(http())
        .get('/api/v1/auth/me/avatar')
        .set('Authorization', auth(role))
        .expect(404);
      expect(
        await db.dokter.findUniqueOrThrow({ where: { id: doctorId } }),
      ).toEqual(professional);
    },
  );
  it('avatar privat, menolak pemalsuan tipe, ukuran, field pemilik dan pembacaan akun lain', async () => {
    await request(http()).get('/api/v1/auth/me/avatar').expect(401);
    await request(http())
      .post('/api/v1/auth/me/avatar')
      .set('Authorization', auth('USER'))
      .attach('foto', Buffer.from('<svg/>'), 'fake.png')
      .expect(400);
    await request(http())
      .post('/api/v1/auth/me/avatar')
      .set('Authorization', auth('USER'))
      .attach('foto', Buffer.alloc(2 * 1024 * 1024 + 1), 'large.png')
      .expect(413);
    await request(http())
      .post('/api/v1/auth/me/avatar')
      .set('Authorization', auth('USER'))
      .field('userId', users.ADMIN!.id)
      .attach('foto', png, 'foto.png')
      .expect(400);
    await request(http())
      .post('/api/v1/auth/me/avatar')
      .set('Authorization', auth('ADMIN'))
      .attach('foto', png, 'foto.png')
      .expect(201);
    await request(http())
      .get('/api/v1/auth/me/avatar')
      .set('Authorization', auth('USER'))
      .query({ userId: users.ADMIN!.id })
      .expect(404);
    await request(http())
      .get('/api/v1/auth/me/avatar')
      .set('Authorization', auth('ADMIN'))
      .expect(200);
  });
  it('password lama salah tidak mencabut sesi; validasi kebijakan dan UTF-8', async () => {
    await request(http())
      .post('/api/v1/auth/me/password')
      .set('Authorization', auth('USER'))
      .send({ kataSandiLama: 'salah', kataSandiBaru: 'RahasiaBaru123!' })
      .expect(400);
    for (const next of ['short', '界'.repeat(30)])
      await request(http())
        .post('/api/v1/auth/me/password')
        .set('Authorization', auth('USER'))
        .send({ kataSandiLama: password, kataSandiBaru: next })
        .expect(400);
    await request(http())
      .get('/api/v1/auth/me')
      .set('Authorization', auth('USER'))
      .expect(200);
  });
  it('password berhasil mencabut seluruh access/refresh dan login baru tetap berfungsi', async () => {
    const u = users.USER!,
      second = await request(http())
        .post('/api/v1/auth/login')
        .send({ email: u.email, kataSandi: password })
        .expect(200);
    await request(http())
      .post('/api/v1/auth/me/password')
      .set('Authorization', auth('USER'))
      .send({ kataSandiLama: password, kataSandiBaru: 'P2-Password-Baru123!' })
      .expect(200);
    for (const token of [u.access, second.body.accessToken as string])
      await request(http())
        .get('/api/v1/auth/me')
        .set('Authorization', `Bearer ${token}`)
        .expect(401);
    for (const token of [u.refresh, second.body.refreshToken as string])
      await request(http())
        .post('/api/v1/auth/refresh')
        .send({ refreshToken: token })
        .expect(401);
    await request(http())
      .post('/api/v1/auth/login')
      .send({ email: u.email, kataSandi: password })
      .expect(401);
    await request(http())
      .post('/api/v1/auth/login')
      .send({ email: u.email, kataSandi: 'P2-Password-Baru123!' })
      .expect(200);
  });
  it('dua perubahan password paralel hanya menghasilkan satu pemenang', async () => {
    const passwords = app.get(PasswordService),
      verify = passwords.verify.bind(passwords);
    let entered = 0,
      release!: () => void;
    let watchdog!: ReturnType<typeof setTimeout>;
    const gate = new Promise<void>((resolve, reject) => {
      release = resolve;
      watchdog = setTimeout(
        () => reject(Error('Password race barrier not reached')),
        5000,
      );
    });
    void gate.catch(() => {});
    const spy = jest
      .spyOn(passwords, 'verify')
      .mockImplementation(async (p, h) => {
        const valid = await verify(p, h);
        if (p === password) {
          // Both requests must pass JWT validation and observe the old hash.
          // Otherwise the winner may revoke the second JWT before it reaches CAS.
          if (++entered === 2) release();
          await gate;
        }
        return valid;
      });
    try {
      const responses = await Promise.all(
        ['P2-Paralel-Satu!', 'P2-Paralel-Dua!'].map((next) =>
          request(http())
            .post('/api/v1/auth/me/password')
            .set('Authorization', auth('PETUGAS'))
            .send({ kataSandiLama: password, kataSandiBaru: next }),
        ),
      );
      expect(entered).toBe(2);
      expect(responses.filter((r) => r.status === 200)).toHaveLength(1);
      expect(
        responses.filter((r) => [400, 409].includes(r.status)),
      ).toHaveLength(1);
    } finally {
      release();
      clearTimeout(watchdog);
      spy.mockRestore();
    }
  });
  it('login lama yang sedang verifikasi tidak hidup kembali setelah password diubah', async () => {
    const passwords = app.get(PasswordService),
      verify = passwords.verify.bind(passwords);
    let resume!: () => void,
      entered!: () => void,
      hold = true;
    const gate = new Promise<void>((r) => (resume = r)),
      ready = new Promise<void>((r) => (entered = r));
    const spy = jest
      .spyOn(passwords, 'verify')
      .mockImplementation(async (p, h) => {
        if (hold && p === password) {
          hold = false;
          entered();
          await gate;
        }
        return verify(p, h);
      });
    const pending = request(http())
      .post('/api/v1/auth/login')
      .send({ email: users.DOKTER!.email, kataSandi: password })
      .then((r) => r);
    try {
      await ready;
      await request(http())
        .post('/api/v1/auth/me/password')
        .set('Authorization', auth('DOKTER'))
        .send({ kataSandiLama: password, kataSandiBaru: 'P2-Dokter-Baru123!' })
        .expect(200);
      resume();
      expect((await pending).status).toBe(401);
    } finally {
      resume();
      spy.mockRestore();
    }
  });
  it('membatasi percobaan password berdasarkan akun terautentikasi', async () => {
    for (let i = 0; i < 5; i++)
      await request(http())
        .post('/api/v1/auth/me/password')
        .set('Authorization', auth('ADMIN'))
        .send({ kataSandiLama: 'salah', kataSandiBaru: 'P2-ValidBaru123!' })
        .expect(400);
    await request(http())
      .post('/api/v1/auth/me/password')
      .set('Authorization', auth('ADMIN'))
      .send({ kataSandiLama: 'salah', kataSandiBaru: 'P2-ValidBaru123!' })
      .expect(429);
    await request(http())
      .get('/api/v1/auth/me')
      .set('Authorization', auth('ADMIN'))
      .expect(200);
  });
});
