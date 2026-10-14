import { randomUUID } from 'node:crypto';
import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';

import { AppModule } from '../src/app.module';
import { configureApp } from '../src/configure-app';
import { ModeReservasi, PeranPengguna } from '../src/generated/prisma/client';
import { PrismaService } from '../src/prisma/prisma.service';

// ==========================================
// TIPE RESPONSE
// ==========================================

interface RegisterResponse {
  id: string;
  email: string;
  peran: PeranPengguna;
}

interface LoginResponse {
  accessToken: string;
  refreshToken: string;
  user: {
    id: string;
    email: string;
    peran: PeranPengguna;
  };
}

interface LayananResponse {
  id: string;
  kode: string;
  nama: string;
  deskripsi: string | null;
  prefixAntrean: string;
  durasiDasarMenit: number;
  aktif: boolean;
  modeReservasi: ModeReservasi;
}

// ==========================================
// E2E MANAJEMEN LAYANAN
// ==========================================

describe('Manajemen Layanan API (e2e)', () => {
  let app: INestApplication | undefined;
  let prisma: PrismaService | undefined;

  const identitas = randomUUID().replace(/-/g, '');

  const emailUser = `user-${identitas}@test.local`;
  const emailAdmin = `admin-${identitas}@test.local`;

  const kataSandi = 'RahasiaE2E123!';

  const kodeLayanan = `T${identitas.slice(0, 8).toUpperCase()}`;

  let userId = '';
  let adminId = '';
  let layananId = '';
  const layananHospitalIds: string[] = [];

  let tokenUser = '';
  let tokenAdmin = '';

  // ========================================
  // HELPER
  // ========================================

  function httpServer() {
    if (!app) {
      throw new Error('Aplikasi pengujian belum diinisialisasi');
    }

    return app.getHttpServer();
  }

  function database(): PrismaService {
    if (!prisma) {
      throw new Error('Prisma pengujian belum tersedia');
    }

    return prisma;
  }

  // ========================================
  // SETUP
  // ========================================

  beforeAll(async () => {
    // Pastikan tidak menggunakan database development.
    const databaseUrl = process.env.DATABASE_URL;

    if (!databaseUrl) {
      throw new Error('DATABASE_URL pengujian wajib tersedia');
    }

    const url = new URL(databaseUrl);

    const databaseName = url.pathname.slice(1);

    if (
      databaseName !== 'capstone_antrean_test' ||
      !['localhost', '127.0.0.1'].includes(url.hostname) ||
      url.port !== '5433'
    ) {
      throw new Error(
        'E2E layanan hanya boleh berjalan pada ' +
          'database lokal capstone_antrean_test:5433',
      );
    }

    // Inisialisasi aplikasi NestJS.
    const moduleRef = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleRef.createNestApplication();

    configureApp(app);

    await app.init();

    prisma = app.get(PrismaService);

    // ======================================
    // BUAT AKUN USER
    // ======================================

    const userResponse = await request(httpServer())
      .post('/api/v1/auth/register')
      .send({
        nama: 'User E2E Layanan',
        email: emailUser,
        kataSandi,
      })
      .expect(201);

    const pengguna = userResponse.body as RegisterResponse;

    userId = pengguna.id;

    expect(pengguna.peran).toBe(PeranPengguna.USER);

    // ======================================
    // BUAT AKUN ADMIN
    // ======================================

    const adminResponse = await request(httpServer())
      .post('/api/v1/auth/register')
      .send({
        nama: 'Admin E2E Layanan',
        email: emailAdmin,
        kataSandi,
      })
      .expect(201);

    const admin = adminResponse.body as RegisterResponse;

    adminId = admin.id;

    // Promosi ADMIN hanya di database pengujian.
    await database().pengguna.update({
      where: {
        id: adminId,
      },
      data: {
        peran: PeranPengguna.ADMIN,
      },
    });

    // ======================================
    // LOGIN USER
    // ======================================

    const loginUser = await request(httpServer())
      .post('/api/v1/auth/login')
      .send({
        email: emailUser,
        kataSandi,
        namaPerangkat: 'E2E Layanan USER',
      })
      .expect(200);

    const userLogin = loginUser.body as LoginResponse;

    tokenUser = userLogin.accessToken;

    expect(userLogin.user.peran).toBe(PeranPengguna.USER);

    // ======================================
    // LOGIN ADMIN
    // ======================================

    const loginAdmin = await request(httpServer())
      .post('/api/v1/auth/login')
      .send({
        email: emailAdmin,
        kataSandi,
        namaPerangkat: 'E2E Layanan ADMIN',
      })
      .expect(200);

    const adminLogin = loginAdmin.body as LoginResponse;

    tokenAdmin = adminLogin.accessToken;

    expect(adminLogin.user.peran).toBe(PeranPengguna.ADMIN);
  });

  // ========================================
  // CLEANUP
  // ========================================

  afterAll(async () => {
    try {
      if (prisma) {
        // Hapus layanan yang dibuat khusus untuk test.
        if (layananId || layananHospitalIds.length) {
          await prisma.layanan.deleteMany({
            where: {
              id: { in: [layananId, ...layananHospitalIds].filter(Boolean) },
            },
          });
        }

        const penggunaIds = [userId, adminId].filter(Boolean);

        if (penggunaIds.length > 0) {
          await prisma.sesiPengguna.deleteMany({
            where: {
              penggunaId: {
                in: penggunaIds,
              },
            },
          });

          await prisma.pengguna.deleteMany({
            where: {
              id: {
                in: penggunaIds,
              },
            },
          });
        }
      }
    } finally {
      if (app) {
        await app.close();
      }
    }
  });

  // ========================================
  // TEST 1: AUTHENTICATION DAN RBAC
  // ========================================

  it('menolak create tanpa JWT dan role USER', async () => {
    const body = {
      kode: kodeLayanan,
      nama: 'Layanan E2E',
      prefixAntrean: 'E',
      durasiDasarMenit: 15,
    };

    // Tanpa token.
    await request(httpServer()).post('/api/v1/layanan').send(body).expect(401);

    // Token USER.
    await request(httpServer())
      .post('/api/v1/layanan')
      .set('Authorization', `Bearer ${tokenUser}`)
      .send(body)
      .expect(403);
  });

  // ========================================
  // TEST 2: VALIDASI DTO
  // ========================================

  it('menolak data layanan tidak valid', async () => {
    await request(httpServer())
      .post('/api/v1/layanan')
      .set('Authorization', `Bearer ${tokenAdmin}`)
      .send({
        kode: 'kode-kecil',
        nama: 'AB',
        prefixAntrean: '123',
        durasiDasarMenit: -5,
      })
      .expect(400);
  });

  // ========================================
  // TEST 3: CREATE DAN KODE DUPLIKAT
  // ========================================

  it('ADMIN membuat layanan dan kode duplikat ditolak', async () => {
    const body = {
      kode: kodeLayanan,
      nama: 'Layanan Pengujian E2E',
      deskripsi: 'Layanan khusus pengujian API.',
      prefixAntrean: 'E',
      durasiDasarMenit: 15,
    };

    const response = await request(httpServer())
      .post('/api/v1/layanan')
      .set('Authorization', `Bearer ${tokenAdmin}`)
      .send(body)
      .expect(201);

    const layanan = response.body as LayananResponse;

    layananId = layanan.id;

    expect(layanan.kode).toBe(kodeLayanan);
    expect(layanan.nama).toBe(body.nama);
    expect(layanan.aktif).toBe(true);
    expect(layanan.modeReservasi).toBe(ModeReservasi.ANTREAN_HARIAN);

    // Kode sama tidak boleh dibuat dua kali.
    await request(httpServer())
      .post('/api/v1/layanan')
      .set('Authorization', `Bearer ${tokenAdmin}`)
      .send(body)
      .expect(409);
  });

  // ========================================
  // TEST 4: READ ALL DAN READ ONE
  // ========================================

  it.each([ModeReservasi.JANJI_TEMU_DOKTER, ModeReservasi.HIBRIDA])(
    'ADMIN membuat poli %s dan USER membaca mode yang sama',
    async (modeReservasi) => {
      const body = {
        kode: `H${randomUUID().replace(/-/g, '').slice(0, 10).toUpperCase()}`,
        nama: 'Poli Hospital API',
        prefixAntrean: 'H',
        durasiDasarMenit: 15,
        modeReservasi,
      };
      await request(httpServer())
        .post('/api/v1/layanan')
        .set('Authorization', `Bearer ${tokenUser}`)
        .send(body)
        .expect(403);
      const res = await request(httpServer())
        .post('/api/v1/layanan')
        .set('Authorization', `Bearer ${tokenAdmin}`)
        .send(body)
        .expect(201);
      const poli = res.body as LayananResponse;
      layananHospitalIds.push(poli.id);
      expect(poli.modeReservasi).toBe(modeReservasi);
      const detail = await request(httpServer())
        .get(`/api/v1/layanan/${poli.id}`)
        .set('Authorization', `Bearer ${tokenUser}`)
        .expect(200);
      expect((detail.body as LayananResponse).modeReservasi).toBe(
        modeReservasi,
      );
      // Perubahan mode poli existing sengaja tidak dibuka pada MVP.
      await request(httpServer())
        .patch(`/api/v1/layanan/${poli.id}`)
        .set('Authorization', `Bearer ${tokenAdmin}`)
        .send({ modeReservasi: ModeReservasi.ANTREAN_HARIAN })
        .expect(400);
      expect(
        (await database().layanan.findUniqueOrThrow({ where: { id: poli.id } }))
          .modeReservasi,
      ).toBe(modeReservasi);
    },
  );

  it('menolak mode invalid atau null tanpa membuat poli', async () => {
    const kode = `V${identitas.slice(0, 10).toUpperCase()}`;
    for (const modeReservasi of ['INVALID', null, 1]) {
      await request(httpServer())
        .post('/api/v1/layanan')
        .set('Authorization', `Bearer ${tokenAdmin}`)
        .send({
          kode,
          nama: 'Poli Invalid',
          prefixAntrean: 'V',
          durasiDasarMenit: 15,
          modeReservasi,
        })
        .expect(400);
    }
    expect(await database().layanan.count({ where: { kode } })).toBe(0);
  });

  it('ADMIN dan USER dapat melihat layanan aktif', async () => {
    const responseAdmin = await request(httpServer())
      .get('/api/v1/layanan')
      .set('Authorization', `Bearer ${tokenAdmin}`)
      .expect(200);

    const daftarAdmin = responseAdmin.body as LayananResponse[];

    expect(daftarAdmin.some((layanan) => layanan.id === layananId)).toBe(true);

    const responseUser = await request(httpServer())
      .get('/api/v1/layanan')
      .set('Authorization', `Bearer ${tokenUser}`)
      .expect(200);

    const daftarUser = responseUser.body as LayananResponse[];

    expect(daftarUser.some((layanan) => layanan.id === layananId)).toBe(true);

    const detail = await request(httpServer())
      .get(`/api/v1/layanan/${layananId}`)
      .set('Authorization', `Bearer ${tokenUser}`)
      .expect(200);

    const layanan = detail.body as LayananResponse;

    expect(layanan.id).toBe(layananId);
    expect(layanan.aktif).toBe(true);
  });

  // ========================================
  // TEST 5: UPDATE
  // ========================================

  it('ADMIN dapat update dan USER tidak diizinkan', async () => {
    await request(httpServer())
      .patch(`/api/v1/layanan/${layananId}`)
      .set('Authorization', `Bearer ${tokenUser}`)
      .send({
        nama: 'Perubahan Tidak Sah',
      })
      .expect(403);

    const response = await request(httpServer())
      .patch(`/api/v1/layanan/${layananId}`)
      .set('Authorization', `Bearer ${tokenAdmin}`)
      .send({
        nama: 'Layanan E2E Diperbarui',
        durasiDasarMenit: 25,
      })
      .expect(200);

    const layanan = response.body as LayananResponse;

    expect(layanan.nama).toBe('Layanan E2E Diperbarui');

    expect(layanan.durasiDasarMenit).toBe(25);
  });

  // ========================================
  // TEST 6: SOFT DELETE
  // ========================================

  it('ADMIN menonaktifkan layanan dan USER tidak dapat melihatnya', async () => {
    await request(httpServer())
      .delete(`/api/v1/layanan/${layananId}`)
      .set('Authorization', `Bearer ${tokenUser}`)
      .expect(403);

    const response = await request(httpServer())
      .delete(`/api/v1/layanan/${layananId}`)
      .set('Authorization', `Bearer ${tokenAdmin}`)
      .expect(200);

    const layanan = response.body as LayananResponse;

    expect(layanan.aktif).toBe(false);

    // USER tidak dapat membuka layanan nonaktif.
    await request(httpServer())
      .get(`/api/v1/layanan/${layananId}`)
      .set('Authorization', `Bearer ${tokenUser}`)
      .expect(404);

    // USER juga tidak melihatnya dalam daftar.
    const responseUser = await request(httpServer())
      .get('/api/v1/layanan')
      .set('Authorization', `Bearer ${tokenUser}`)
      .expect(200);

    const daftarUser = responseUser.body as LayananResponse[];

    expect(daftarUser.some((item) => item.id === layananId)).toBe(false);

    // ADMIN tetap dapat melihat data nonaktif.
    const responseAdmin = await request(httpServer())
      .get(`/api/v1/layanan/${layananId}`)
      .set('Authorization', `Bearer ${tokenAdmin}`)
      .expect(200);

    const layananAdmin = responseAdmin.body as LayananResponse;

    expect(layananAdmin.aktif).toBe(false);
  });

  // ========================================
  // TEST 7: AKTIFKAN KEMBALI
  // ========================================

  it('ADMIN dapat mengaktifkan kembali layanan', async () => {
    const response = await request(httpServer())
      .patch(`/api/v1/layanan/${layananId}`)
      .set('Authorization', `Bearer ${tokenAdmin}`)
      .send({
        aktif: true,
      })
      .expect(200);

    const layanan = response.body as LayananResponse;

    expect(layanan.aktif).toBe(true);

    // USER kembali dapat melihat layanan.
    await request(httpServer())
      .get(`/api/v1/layanan/${layananId}`)
      .set('Authorization', `Bearer ${tokenUser}`)
      .expect(200);
  });

  // ========================================
  // TEST 8: DATA TIDAK DITEMUKAN
  // ========================================

  it('mengembalikan 404 untuk data tidak ada dan 400 untuk ID tidak valid', async () => {
    const idTidakAda = '00000000-0000-4000-8000-000000000000';

    await request(httpServer())
      .get(`/api/v1/layanan/${idTidakAda}`)
      .set('Authorization', `Bearer ${tokenAdmin}`)
      .expect(404);

    await request(httpServer())
      .get('/api/v1/layanan/bukan-uuid')
      .set('Authorization', `Bearer ${tokenAdmin}`)
      .expect(400);
  });
});
