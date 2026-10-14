import { randomUUID } from 'node:crypto';
import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { ThrottlerStorage } from '@nestjs/throttler';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/configure-app';
import { HariLayanan, PeranPengguna } from '../src/generated/prisma/client';
import { PrismaService } from '../src/prisma/prisma.service';

type Akun = { id: string; token: string };
type RegisterBody = { id: string };
type LoginBody = { accessToken: string };
type JadwalBody = { id: string; aktif: boolean; mulaiPada: string };

// Fixture 2035-10-15 adalah Senin. Gunakan offset sesuai SERVICE_TIME_ZONE Indonesia.
const tanggal = '2035-10-15';
function jam(nilai: string): string {
  const zona = process.env.SERVICE_TIME_ZONE ?? 'Asia/Jakarta';
  const offset: Record<string, string> = {
    'Asia/Jakarta': '+07:00',
    'Asia/Makassar': '+08:00',
    'Asia/Jayapura': '+09:00',
  };
  if (!offset[zona])
    throw new Error(`Fixture E2E belum mendukung timezone ${zona}`);
  return `${tanggal}T${nilai}:00${offset[zona]}`;
}
const unik = randomUUID().replace(/-/g, '').slice(0, 8).toUpperCase();

// Suite ini memakai nama database dan port hardcoded untuk mencegah
// permintaan HTTP mengubah database development utama.
describe('Practice Schedule API H2.2 (e2e)', () => {
  let app: INestApplication | undefined;
  let prisma: PrismaService | undefined;
  let admin!: Akun;
  let user!: Akun;
  const akunIds: string[] = [];
  let layananId = '';
  let ruangA = '';
  let ruangB = '';
  let dokterA = '';
  let dokterB = '';
  let linkA = '';
  let linkB = '';
  const password = 'RahasiaJadwalH2E2E123!';

  function server() {
    if (!app) throw new Error('Aplikasi E2E belum siap');
    return app.getHttpServer();
  }

  function db(): PrismaService {
    if (!prisma) throw new Error('Prisma E2E belum siap');
    return prisma;
  }

  const bearer = (token: string) => `Bearer ${token}`;

  const bodyJadwal = (perubahan: Record<string, unknown> = {}) => ({
    dokterLayananId: linkA,
    loketId: ruangA,
    tanggal,
    mulaiPada: jam('08:00'),
    selesaiPada: jam('09:00'),
    ...perubahan,
  });

  async function buatAkun(peran: PeranPengguna): Promise<Akun> {
    const email = `jadwal-h2-${randomUUID()}@test.local`;
    const register = await request(server())
      .post('/api/v1/auth/register')
      .send({ nama: 'Pengguna Jadwal E2E', email, kataSandi: password })
      .expect(201);
    const id = (register.body as RegisterBody).id;
    akunIds.push(id);
    if (peran !== PeranPengguna.USER) {
      await db().pengguna.update({ where: { id }, data: { peran } });
    }
    const login = await request(server())
      .post('/api/v1/auth/login')
      .send({ email, kataSandi: password, namaPerangkat: 'Jest Jadwal H2.2' })
      .expect(200);
    return { id, token: (login.body as LoginBody).accessToken };
  }

  beforeAll(async () => {
    const raw = process.env.DATABASE_URL;
    if (!raw) throw new Error('DATABASE_URL E2E wajib diatur');
    const url = new URL(raw);
    if (
      url.pathname !== '/capstone_antrean_test' ||
      !['localhost', '127.0.0.1'].includes(url.hostname) ||
      url.port !== '5433'
    ) {
      throw new Error(
        'E2E hanya boleh memakai capstone_antrean_test lokal port 5433',
      );
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
    admin = await buatAkun(PeranPengguna.ADMIN);
    user = await buatAkun(PeranPengguna.USER);

    const layanan = await db().layanan.create({
      data: {
        kode: `JH${unik}`,
        nama: 'Poli Uji Jadwal H2.2',
        prefixAntrean: 'JH',
        durasiDasarMenit: 15,
        aktif: true,
      },
    });
    layananId = layanan.id;
    const [loket1, loket2] = await Promise.all([
      db().loket.create({
        data: { layananId, kode: `RA${unik}`, nama: 'Ruang A' },
      }),
      db().loket.create({
        data: { layananId, kode: `RB${unik}`, nama: 'Ruang B' },
      }),
    ]);
    ruangA = loket1.id;
    ruangB = loket2.id;
    await db().jadwalLayanan.create({
      data: {
        layananId,
        hari: HariLayanan.SENIN,
        jamBuka: new Date('1970-01-01T07:00:00.000Z'),
        jamTutup: new Date('1970-01-01T16:00:00.000Z'),
        kapasitasHarian: 30,
      },
    });
    const dokter1 = await db().dokter.create({
      data: { kode: `JA${unik}`, nama: 'Dokter A H2', spesialisasi: 'Umum' },
    });
    const dokter2 = await db().dokter.create({
      data: { kode: `JB${unik}`, nama: 'Dokter B H2', spesialisasi: 'Umum' },
    });
    dokterA = dokter1.id;
    dokterB = dokter2.id;
    const pasangan1 = await db().dokterLayanan.create({
      data: { dokterId: dokterA, layananId },
    });
    const pasangan2 = await db().dokterLayanan.create({
      data: { dokterId: dokterB, layananId },
    });
    linkA = pasangan1.id;
    linkB = pasangan2.id;
  }, 120000);

  afterEach(async () => {
    if (!prisma || !linkA || !linkB) return;
    const jadwal = await db().jadwalPraktik.findMany({
      where: { dokterLayananId: { in: [linkA, linkB] } },
      select: { id: true },
    });
    const ids = jadwal.map((item) => item.id);
    if (ids.length > 0) {
      await db().slotPraktik.deleteMany({
        where: { jadwalPraktikId: { in: ids } },
      });
      await db().jadwalPraktik.deleteMany({ where: { id: { in: ids } } });
    }
  }, 30000);

  afterAll(async () => {
    try {
      if (prisma) {
        if (linkA || linkB) {
          const daftar = [linkA, linkB].filter(Boolean);
          const jadwal = await prisma.jadwalPraktik.findMany({
            where: { dokterLayananId: { in: daftar } },
            select: { id: true },
          });
          const ids = jadwal.map((item) => item.id);
          if (ids.length > 0) {
            await prisma.slotPraktik.deleteMany({
              where: { jadwalPraktikId: { in: ids } },
            });
            await prisma.jadwalPraktik.deleteMany({
              where: { id: { in: ids } },
            });
          }
          await prisma.dokterLayanan.deleteMany({
            where: { id: { in: daftar } },
          });
        }
        if (dokterA || dokterB) {
          await prisma.dokter.deleteMany({
            where: { id: { in: [dokterA, dokterB].filter(Boolean) } },
          });
        }
        if (layananId) {
          await prisma.jadwalLayanan.deleteMany({ where: { layananId } });
          await prisma.loket.deleteMany({ where: { layananId } });
          await prisma.layanan.deleteMany({ where: { id: layananId } });
        }
        if (akunIds.length > 0) {
          await prisma.sesiPengguna.deleteMany({
            where: { penggunaId: { in: akunIds } },
          });
          await prisma.pengguna.deleteMany({ where: { id: { in: akunIds } } });
        }
      }
    } finally {
      if (app) await app.close();
    }
  }, 60000);

  async function buatJadwal(body: Record<string, unknown> = {}) {
    const response = await request(server())
      .post('/api/v1/jadwal-praktik')
      .set('Authorization', bearer(admin.token))
      .send(bodyJadwal(body))
      .expect(201);
    return response.body as JadwalBody;
  }

  it('menolak akses tanpa JWT', async () => {
    await request(server()).get('/api/v1/jadwal-praktik').expect(401);
    await request(server())
      .post('/api/v1/jadwal-praktik')
      .send(bodyJadwal())
      .expect(401);
  });

  it('USER tidak boleh membuat, mengubah, atau menonaktifkan jadwal', async () => {
    const created = await buatJadwal();
    await request(server())
      .post('/api/v1/jadwal-praktik')
      .set('Authorization', bearer(user.token))
      .send(bodyJadwal())
      .expect(403);
    await request(server())
      .patch(`/api/v1/jadwal-praktik/${created.id}`)
      .set('Authorization', bearer(user.token))
      .send({ aktif: false })
      .expect(403);
    await request(server())
      .delete(`/api/v1/jadwal-praktik/${created.id}`)
      .set('Authorization', bearer(user.token))
      .expect(403);
  });

  it('ADMIN membuat jadwal dan USER dapat membaca jadwal aktif', async () => {
    const created = await buatJadwal();
    expect(created.aktif).toBe(true);
    const daftar = await request(server())
      .get(`/api/v1/jadwal-praktik?tanggal=${tanggal}`)
      .set('Authorization', bearer(user.token))
      .expect(200);
    expect(
      (daftar.body as JadwalBody[]).some((jadwal) => jadwal.id === created.id),
    ).toBe(true);
    await request(server())
      .get(`/api/v1/jadwal-praktik/${created.id}`)
      .set('Authorization', bearer(user.token))
      .expect(200);
  });

  it('menolak DTO dengan jam tanpa offset dan properti asing', async () => {
    await request(server())
      .post('/api/v1/jadwal-praktik')
      .set('Authorization', bearer(admin.token))
      .send(bodyJadwal({ mulaiPada: `${tanggal}T08:00:00` }))
      .expect(400);
    await request(server())
      .post('/api/v1/jadwal-praktik')
      .set('Authorization', bearer(admin.token))
      .send(bodyJadwal({ fieldRahasia: true }))
      .expect(400);
  });

  it('menolak jadwal di luar jam operasional', async () => {
    await request(server())
      .post('/api/v1/jadwal-praktik')
      .set('Authorization', bearer(admin.token))
      .send(bodyJadwal({ mulaiPada: jam('06:00') }))
      .expect(400);
  });

  it('menolak benturan dokter meskipun pindah ruang', async () => {
    await buatJadwal();
    await request(server())
      .post('/api/v1/jadwal-praktik')
      .set('Authorization', bearer(admin.token))
      .send(
        bodyJadwal({
          loketId: ruangB,
          mulaiPada: jam('08:30'),
          selesaiPada: jam('09:30'),
        }),
      )
      .expect(409);
  });

  it('menolak benturan ruang meskipun dokter berbeda', async () => {
    await buatJadwal();
    await request(server())
      .post('/api/v1/jadwal-praktik')
      .set('Authorization', bearer(admin.token))
      .send(
        bodyJadwal({
          dokterLayananId: linkB,
          mulaiPada: jam('08:30'),
          selesaiPada: jam('09:30'),
        }),
      )
      .expect(409);
  });

  it('menerima dua jadwal bersebelahan tanpa overlap', async () => {
    await buatJadwal();
    await buatJadwal({ mulaiPada: jam('09:00'), selesaiPada: jam('10:00') });
  });

  it('membatasi benturan serentak secara transaksional', async () => {
    const [resA, resB] = await Promise.all([
      request(server())
        .post('/api/v1/jadwal-praktik')
        .set('Authorization', bearer(admin.token))
        .send(bodyJadwal()),
      request(server())
        .post('/api/v1/jadwal-praktik')
        .set('Authorization', bearer(admin.token))
        .send(
          bodyJadwal({ mulaiPada: jam('08:30'), selesaiPada: jam('09:30') }),
        ),
    ]);
    expect([resA.status, resB.status].sort((a, b) => a - b)).toEqual([
      201, 409,
    ]);
  });

  it('PATCH memvalidasi overlap dan DELETE merupakan soft delete', async () => {
    const a = await buatJadwal();
    const b = await buatJadwal({
      mulaiPada: jam('10:00'),
      selesaiPada: jam('11:00'),
    });
    await request(server())
      .patch(`/api/v1/jadwal-praktik/${b.id}`)
      .set('Authorization', bearer(admin.token))
      .send({ mulaiPada: jam('08:30') })
      .expect(409);
    await request(server())
      .delete(`/api/v1/jadwal-praktik/${a.id}`)
      .set('Authorization', bearer(admin.token))
      .expect(200);
    const detail = await request(server())
      .get(`/api/v1/jadwal-praktik/${a.id}`)
      .set('Authorization', bearer(admin.token))
      .expect(200);
    expect((detail.body as JadwalBody).aktif).toBe(false);
    await request(server())
      .get(`/api/v1/jadwal-praktik/${a.id}`)
      .set('Authorization', bearer(user.token))
      .expect(404);
  });

  it('menolak pengubahan ketika sudah ada slot praktik', async () => {
    const jadwal = await buatJadwal();
    await db().slotPraktik.create({
      data: {
        jadwalPraktikId: jadwal.id,
        mulaiPada: new Date(jam('08:00')),
        selesaiPada: new Date(jam('08:30')),
        kapasitas: 1,
      },
    });
    await request(server())
      .patch(`/api/v1/jadwal-praktik/${jadwal.id}`)
      .set('Authorization', bearer(admin.token))
      .send({ selesaiPada: jam('10:00') })
      .expect(409);
    await request(server())
      .delete(`/api/v1/jadwal-praktik/${jadwal.id}`)
      .set('Authorization', bearer(admin.token))
      .expect(409);
  });
});
