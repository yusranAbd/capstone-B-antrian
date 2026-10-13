import { randomUUID } from 'node:crypto';

import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { ThrottlerStorage } from '@nestjs/throttler';
import request from 'supertest';

import { AppModule } from '../src/app.module';
import { configureApp } from '../src/configure-app';
import { PeranPengguna } from '../src/generated/prisma/client';
import { PrismaService } from '../src/prisma/prisma.service';

interface AkunUji {
  id: string;
  token: string;
}

interface RegisterResponse {
  id: string;
}

interface LoginResponse {
  accessToken: string;
  user: { id: string; peran: PeranPengguna };
}

interface DokterResponse {
  id: string;
  kode: string;
  nama: string;
  spesialisasi: string | null;
  aktif: boolean;
  dokterLayanan?: Array<{
    id: string;
    layananId: string;
    aktif: boolean;
  }>;
}

interface RelasiResponse {
  id: string;
  dokterId: string;
  layananId: string;
  aktif: boolean;
}

describe('Doctor Management API (e2e)', () => {
  let app: INestApplication | undefined;
  let prisma: PrismaService | undefined;
  let admin!: AkunUji;
  let petugas!: AkunUji;
  let pasien!: AkunUji;
  let layananId = '';
  let dokterId = '';

  const penggunaIds: string[] = [];
  const kodeDokterLain: string[] = [];
  const unik = randomUUID().replace(/-/g, '').slice(0, 8).toUpperCase();
  const kataSandi = 'RahasiaDokterE2E123!';

  function server() {
    if (!app) throw new Error('Aplikasi E2E belum siap');
    return app.getHttpServer();
  }

  function db(): PrismaService {
    if (!prisma) throw new Error('Prisma E2E belum siap');
    return prisma;
  }

  function auth(token: string): string {
    return `Bearer ${token}`;
  }

  function kodeBaru(): string {
    return `DR${randomUUID().replace(/-/g, '').slice(0, 12).toUpperCase()}`;
  }

  async function buatAkun(nama: string, peran: PeranPengguna): Promise<AkunUji> {
    const email = `dokter-${randomUUID()}@test.local`;
    const register = await request(server())
      .post('/api/v1/auth/register')
      .send({ nama, email, kataSandi })
      .expect(201);
    const id = (register.body as RegisterResponse).id;
    penggunaIds.push(id);

    if (peran !== PeranPengguna.USER) {
      await db().pengguna.update({ where: { id }, data: { peran } });
    }
    const login = await request(server())
      .post('/api/v1/auth/login')
      .send({ email, kataSandi, namaPerangkat: 'Jest H2.1 Dokter' })
      .expect(200);
    const hasil = login.body as LoginResponse;
    expect(hasil.user.peran).toBe(peran);
    return { id: hasil.user.id, token: hasil.accessToken };
  }

  beforeAll(async () => {
    const raw = process.env.DATABASE_URL;
    if (!raw) throw new Error('DATABASE_URL E2E wajib tersedia');
    const url = new URL(raw);
    if (
      url.pathname !== '/capstone_antrean_test' ||
      !['localhost', '127.0.0.1'].includes(url.hostname) ||
      url.port !== '5433'
    ) {
      throw new Error('E2E hanya boleh memakai capstone_antrean_test lokal port 5433');
    }

    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
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

    app = moduleRef.createNestApplication();
    configureApp(app);
    await app.init();
    prisma = app.get(PrismaService);

    admin = await buatAkun('Admin Dokter E2E', PeranPengguna.ADMIN);
    petugas = await buatAkun('Petugas Dokter E2E', PeranPengguna.PETUGAS);
    pasien = await buatAkun('Pasien Dokter E2E', PeranPengguna.USER);

    const layanan = await db().layanan.create({
      data: {
        kode: `HD${unik}`,
        nama: 'Poliklinik Uji H2.1',
        prefixAntrean: 'HD',
        durasiDasarMenit: 15,
        aktif: true,
      },
    });
    layananId = layanan.id;
  }, 120000);

  beforeEach(async () => {
    const dokter = await db().dokter.create({
      data: {
        kode: kodeBaru(),
        nama: 'Dokter Dasar Pengujian',
        spesialisasi: 'Umum',
        aktif: true,
      },
    });
    dokterId = dokter.id;
  }, 30000);

  afterEach(async () => {
    if (!prisma || !dokterId) return;
    await db().dokterLayanan.deleteMany({ where: { dokterId } });
    await db().dokter.deleteMany({ where: { id: dokterId } });
    dokterId = '';
    // Dokter lain yang dibuat oleh endpoint POST juga dibersihkan tanpa menyentuh data lain.
    if (kodeDokterLain.length > 0) {
      const lain = await db().dokter.findMany({
        where: { kode: { in: kodeDokterLain } },
        select: { id: true },
      });
      const ids = lain.map((d) => d.id);
      if (ids.length > 0) {
        await db().dokterLayanan.deleteMany({ where: { dokterId: { in: ids } } });
        await db().dokter.deleteMany({ where: { id: { in: ids } } });
      }
      kodeDokterLain.length = 0;
    }
  }, 30000);

  afterAll(async () => {
    try {
      if (prisma) {
        // Pembersihan hanya untuk data uji milik suite ini.
        if (dokterId) {
          await prisma.dokterLayanan.deleteMany({ where: { dokterId } });
          await prisma.dokter.deleteMany({ where: { id: dokterId } });
        }
        if (layananId) await prisma.layanan.deleteMany({ where: { id: layananId } });
        if (penggunaIds.length > 0) {
          await prisma.sesiPengguna.deleteMany({
            where: { penggunaId: { in: penggunaIds } },
          });
          await prisma.pengguna.deleteMany({
            where: { id: { in: penggunaIds } },
          });
        }
      }
    } finally {
      if (app) await app.close();
    }
  }, 60000);

  it('menolak akses dokter tanpa JWT', async () => {
    await request(server()).get('/api/v1/dokter').expect(401);
    await request(server()).get(`/api/v1/dokter/${dokterId}`).expect(401);
    await request(server()).post('/api/v1/dokter').send({}).expect(401);
  });

  it('hanya ADMIN boleh membuat dan mengubah dokter', async () => {
    const payload = { kode: kodeBaru(), nama: 'Dr. E2E Baru', spesialisasi: 'Anak' };
    await request(server())
      .post('/api/v1/dokter')
      .set('Authorization', auth(pasien.token))
      .send(payload)
      .expect(403);
    await request(server())
      .post('/api/v1/dokter')
      .set('Authorization', auth(petugas.token))
      .send(payload)
      .expect(403);
    await request(server())
      .patch(`/api/v1/dokter/${dokterId}`)
      .set('Authorization', auth(pasien.token))
      .send({ nama: 'Perubahan Terlarang' })
      .expect(403);
    await request(server())
      .delete(`/api/v1/dokter/${dokterId}`)
      .set('Authorization', auth(petugas.token))
      .expect(403);

    kodeDokterLain.push(payload.kode);
    const res = await request(server())
      .post('/api/v1/dokter')
      .set('Authorization', auth(admin.token))
      .send(payload)
      .expect(201);
    const dokter = res.body as DokterResponse;
    expect(dokter.kode).toBe(payload.kode);
    expect(dokter.nama).toBe(payload.nama);
    expect(dokter.aktif).toBe(true);
  });

  it('menolak DTO yang tidak valid atau properti tambahan', async () => {
    for (const body of [
      { kode: 'lower', nama: 'Dokter Valid' },
      { kode: 'AB', nama: 'XY' },
      { kode: 'AB', nama: 'Dokter Valid', fieldRahasia: true },
    ]) {
      await request(server())
        .post('/api/v1/dokter')
        .set('Authorization', auth(admin.token))
        .send(body)
        .expect(400);
    }
    await request(server())
      .get('/api/v1/dokter/bukan-uuid')
      .set('Authorization', auth(admin.token))
      .expect(400);
  });

  it('mengembalikan 409 untuk kode dokter duplikat', async () => {
    const ada = await db().dokter.findUniqueOrThrow({ where: { id: dokterId } });
    await request(server())
      .post('/api/v1/dokter')
      .set('Authorization', auth(admin.token))
      .send({ kode: ada.kode, nama: 'Dokter Duplikat' })
      .expect(409);
  });

  it('USER hanya melihat dokter aktif dengan relasi poli aktif', async () => {
    const awal = await request(server())
      .get('/api/v1/dokter')
      .set('Authorization', auth(pasien.token))
      .expect(200);
    expect((awal.body as DokterResponse[]).some((d) => d.id === dokterId)).toBe(false);

    await request(server())
      .post(`/api/v1/dokter/${dokterId}/layanan`)
      .set('Authorization', auth(admin.token))
      .send({ layananId })
      .expect(201);

    const sesudah = await request(server())
      .get('/api/v1/dokter')
      .set('Authorization', auth(pasien.token))
      .expect(200);
    const ditemukan = (sesudah.body as DokterResponse[]).find((d) => d.id === dokterId);
    expect(ditemukan).toBeDefined();
    expect(ditemukan?.dokterLayanan?.[0]?.layananId).toBe(layananId);

    await db().dokter.update({ where: { id: dokterId }, data: { aktif: false } });
    const nonaktif = await request(server())
      .get('/api/v1/dokter')
      .set('Authorization', auth(pasien.token))
      .expect(200);
    expect((nonaktif.body as DokterResponse[]).some((d) => d.id === dokterId)).toBe(false);

    const adminLihat = await request(server())
      .get(`/api/v1/dokter/${dokterId}`)
      .set('Authorization', auth(admin.token))
      .expect(200);
    expect((adminLihat.body as DokterResponse).aktif).toBe(false);
  });

  it('detail dokter untuk USER 404 sampai terhubung dengan poli aktif', async () => {
    await request(server())
      .get(`/api/v1/dokter/${dokterId}`)
      .set('Authorization', auth(pasien.token))
      .expect(404);

    await request(server())
      .post(`/api/v1/dokter/${dokterId}/layanan`)
      .set('Authorization', auth(admin.token))
      .send({ layananId })
      .expect(201);

    const detail = await request(server())
      .get(`/api/v1/dokter/${dokterId}`)
      .set('Authorization', auth(pasien.token))
      .expect(200);
    expect((detail.body as DokterResponse).id).toBe(dokterId);
  });

  it('PATCH mengubah nama dan spesialisasi serta menerima null', async () => {
    const hasil = await request(server())
      .patch(`/api/v1/dokter/${dokterId}`)
      .set('Authorization', auth(admin.token))
      .send({ nama: '  Dokter Diperbarui  ', spesialisasi: null })
      .expect(200);
    const dokter = hasil.body as DokterResponse;
    expect(dokter.nama).toBe('Dokter Diperbarui');
    expect(dokter.spesialisasi).toBeNull();
  });

  it('DELETE dokter adalah soft delete, USER tidak melihatnya', async () => {
    await request(server())
      .post(`/api/v1/dokter/${dokterId}/layanan`)
      .set('Authorization', auth(admin.token))
      .send({ layananId })
      .expect(201);

    const hasil = await request(server())
      .delete(`/api/v1/dokter/${dokterId}`)
      .set('Authorization', auth(admin.token))
      .expect(200);
    expect((hasil.body as DokterResponse).aktif).toBe(false);
    expect(await db().dokter.count({ where: { id: dokterId } })).toBe(1);
    await request(server())
      .get(`/api/v1/dokter/${dokterId}`)
      .set('Authorization', auth(pasien.token))
      .expect(404);
  });

  it('POST relasi mengaktifkan kembali hubungan lama tanpa duplikasi', async () => {
    const endpoint = `/api/v1/dokter/${dokterId}/layanan`;
    const buat = await request(server())
      .post(endpoint)
      .set('Authorization', auth(admin.token))
      .send({ layananId })
      .expect(201);
    expect((buat.body as RelasiResponse).aktif).toBe(true);

    const hapus = await request(server())
      .delete(`${endpoint}/${layananId}`)
      .set('Authorization', auth(admin.token))
      .expect(200);
    expect((hapus.body as RelasiResponse).aktif).toBe(false);

    const aktifkan = await request(server())
      .post(endpoint)
      .set('Authorization', auth(admin.token))
      .send({ layananId })
      .expect(201);
    expect((aktifkan.body as RelasiResponse).id).toBe((buat.body as RelasiResponse).id);
    expect((aktifkan.body as RelasiResponse).aktif).toBe(true);
  });

  it('daftar relasi membedakan ADMIN dan USER saat relasi nonaktif', async () => {
    const endpoint = `/api/v1/dokter/${dokterId}/layanan`;
    await request(server())
      .post(endpoint)
      .set('Authorization', auth(admin.token))
      .send({ layananId })
      .expect(201);
    await request(server())
      .delete(`${endpoint}/${layananId}`)
      .set('Authorization', auth(admin.token))
      .expect(200);

    const adminRes = await request(server())
      .get(endpoint)
      .set('Authorization', auth(admin.token))
      .expect(200);
    expect((adminRes.body as RelasiResponse[]).some((r) => r.layananId === layananId)).toBe(true);

    await request(server())
      .get(endpoint)
      .set('Authorization', auth(pasien.token))
      .expect(404);
  });

  it('menolak penghubungan pada dokter nonaktif, tanpa mengubah data', async () => {
    await db().dokter.update({ where: { id: dokterId }, data: { aktif: false } });
    await request(server())
      .post(`/api/v1/dokter/${dokterId}/layanan`)
      .set('Authorization', auth(admin.token))
      .send({ layananId })
      .expect(422);
    expect(await db().dokterLayanan.count({ where: { dokterId } })).toBe(0);
  });

  it('mengembalikan 404 untuk dokter atau relasi yang tidak ada', async () => {
    await request(server())
      .get(`/api/v1/dokter/${randomUUID()}`)
      .set('Authorization', auth(admin.token))
      .expect(404);
    await request(server())
      .delete(`/api/v1/dokter/${dokterId}/layanan/${layananId}`)
      .set('Authorization', auth(admin.token))
      .expect(404);
  });
});
