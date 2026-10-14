import { randomUUID } from 'node:crypto';
import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { ThrottlerStorage } from '@nestjs/throttler';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/configure-app';
import { PeranPengguna } from '../src/generated/prisma/client';
import { PrismaService } from '../src/prisma/prisma.service';

type Akun = { id: string; token: string };
type RegisterBody = { id: string };
type LoginBody = { accessToken: string };
type SlotBody = {
  id: string;
  aktif: boolean;
  kapasitas: number;
  jumlahJanjiTemu: number;
  sisaKapasitas: number;
  tersedia: boolean;
};

// Seluruh fixture di masa depan, sehingga status ketersediaan tidak bergantung tanggal pengujian.
const tanggal = '2035-10-15';
function jam(nilai: string): string {
  const zona = process.env.SERVICE_TIME_ZONE ?? 'Asia/Jakarta';
  const offset: Record<string, string> = {
    'Asia/Jakarta': '+07:00',
    'Asia/Makassar': '+08:00',
    'Asia/Jayapura': '+09:00',
  };
  if (!offset[zona]) throw new Error(`Fixture E2E belum mendukung timezone ${zona}`);
  return `${tanggal}T${nilai}:00${offset[zona]}`;
}
const unik = randomUUID().replace(/-/g, '').slice(0, 8).toUpperCase();

describe('Consultation Slot API H2.3 (e2e)', () => {
  let app: INestApplication | undefined;
  let prisma: PrismaService | undefined;
  let admin!: Akun;
  let user!: Akun;
  let petugas!: Akun;
  const akunIds: string[] = [];
  let layananId = '';
  let ruangId = '';
  let dokterId = '';
  let linkId = '';
  let jadwalId = '';
  const password = 'RahasiaSlotH2E2E123!';

  function server() {
    if (!app) throw new Error('Aplikasi E2E belum siap');
    return app.getHttpServer();
  }
  function db() {
    if (!prisma) throw new Error('Prisma E2E belum siap');
    return prisma;
  }
  const bearer = (token: string) => `Bearer ${token}`;
  const bodySlot = (ubah: Record<string, unknown> = {}) => ({
    jadwalPraktikId: jadwalId,
    mulaiPada: jam('08:00'),
    selesaiPada: jam('08:30'),
    kapasitas: 2,
    ...ubah,
  });

  async function buatAkun(peran: PeranPengguna): Promise<Akun> {
    const email = `slot-h2-${randomUUID()}@test.local`;
    const hasil = await request(server())
      .post('/api/v1/auth/register')
      .send({ nama: 'Pengguna E2E Slot', email, kataSandi: password })
      .expect(201);
    const id = (hasil.body as RegisterBody).id;
    akunIds.push(id);
    if (peran !== PeranPengguna.USER) {
      await db().pengguna.update({ where: { id }, data: { peran } });
    }
    const login = await request(server())
      .post('/api/v1/auth/login')
      .send({ email, kataSandi: password, namaPerangkat: 'Jest Slot H2.3' })
      .expect(200);
    return { id, token: (login.body as LoginBody).accessToken };
  }

  beforeAll(async () => {
    const raw = process.env.DATABASE_URL;
    if (!raw) throw new Error('DATABASE_URL E2E wajib diatur');
    const url = new URL(raw);
    if (url.pathname !== '/capstone_antrean_test' ||
        !['localhost', '127.0.0.1'].includes(url.hostname) || url.port !== '5433') {
      throw new Error('E2E hanya boleh memakai capstone_antrean_test lokal port 5433');
    }
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(ThrottlerStorage)
      .useValue({
        increment: () => Promise.resolve({
          totalHits: 1, timeToExpire: 60000, isBlocked: false, timeToBlockExpire: 0,
        }),
      })
      .compile();
    app = moduleRef.createNestApplication();
    configureApp(app);
    await app.init();
    prisma = app.get(PrismaService);
    admin = await buatAkun(PeranPengguna.ADMIN);
    user = await buatAkun(PeranPengguna.USER);
    petugas = await buatAkun(PeranPengguna.PETUGAS);
    const layanan = await db().layanan.create({
      data: { kode: `SL${unik}`, nama: 'Poli Slot E2E', prefixAntrean: 'SL', durasiDasarMenit: 15, aktif: true,
        modeReservasi: 'JANJI_TEMU_DOKTER' },
    });
    layananId = layanan.id;
    await db().jadwalLayanan.create({ data: { layananId, hari: 'SENIN',
      jamBuka: new Date('1970-01-01T07:00:00Z'), jamTutup: new Date('1970-01-01T17:00:00Z'),
      kapasitasHarian: 50 } });
    const ruang = await db().loket.create({
      data: { layananId, kode: `R${unik}`, nama: 'Ruang Slot E2E' },
    });
    ruangId = ruang.id;
    const dokter = await db().dokter.create({
      data: { kode: `D${unik}`, nama: 'Dokter Slot E2E' },
    });
    dokterId = dokter.id;
    const pasangan = await db().dokterLayanan.create({ data: { dokterId, layananId } });
    linkId = pasangan.id;
    const jadwal = await db().jadwalPraktik.create({
      data: {
        dokterLayananId: linkId, loketId: ruangId,
        tanggal: new Date(`${tanggal}T00:00:00.000Z`),
        mulaiPada: new Date(jam('07:00')), selesaiPada: new Date(jam('12:00')),
      },
    });
    jadwalId = jadwal.id;
  }, 120000);

  async function bersihkanSlot() {
    if (!prisma || !jadwalId) return;
    const slots = await db().slotPraktik.findMany({
      where: { jadwalPraktikId: jadwalId }, select: { id: true },
    });
    const ids = slots.map((item) => item.id);
    if (ids.length === 0) return;
    const janji = await db().janjiTemu.findMany({
      where: { slotPraktikId: { in: ids } }, select: { tiketId: true },
    });
    await db().janjiTemu.deleteMany({ where: { slotPraktikId: { in: ids } } });
    if (janji.length) await db().tiketAntrean.deleteMany({ where: { id: { in: janji.map((j) => j.tiketId) } } });
    await db().slotPraktik.deleteMany({ where: { id: { in: ids } } });
  }

  afterEach(async () => { await bersihkanSlot(); }, 30000);
  afterAll(async () => {
    try {
      if (prisma) {
        await bersihkanSlot();
        if (jadwalId) await prisma.jadwalPraktik.deleteMany({ where: { id: jadwalId } });
        if (linkId) await prisma.dokterLayanan.deleteMany({ where: { id: linkId } });
        if (dokterId) await prisma.dokter.deleteMany({ where: { id: dokterId } });
        if (layananId) {
          await prisma.loket.deleteMany({ where: { layananId } });
          await prisma.jadwalLayanan.deleteMany({ where: { layananId } });
          await prisma.layanan.deleteMany({ where: { id: layananId } });
        }
        if (akunIds.length) {
          await prisma.sesiPengguna.deleteMany({ where: { penggunaId: { in: akunIds } } });
          await prisma.pengguna.deleteMany({ where: { id: { in: akunIds } } });
        }
      }
    } finally {
      if (app) await app.close();
    }
  }, 60000);

  async function buatSlot(perubahan: Record<string, unknown> = {}) {
    const response = await request(server())
      .post('/api/v1/slot-praktik')
      .set('Authorization', bearer(admin.token))
      .send(bodySlot(perubahan))
      .expect(201);
    return response.body as SlotBody;
  }

  it('menolak GET dan POST tanpa JWT', async () => {
    await request(server()).get('/api/v1/slot-praktik').expect(401);
    await request(server()).post('/api/v1/slot-praktik').send(bodySlot()).expect(401);
  });

  it('USER dan PETUGAS tidak dapat memutasi slot', async () => {
    const slot = await buatSlot();
    await request(server()).post('/api/v1/slot-praktik')
      .set('Authorization', bearer(user.token)).send(bodySlot()).expect(403);
    await request(server()).patch(`/api/v1/slot-praktik/${slot.id}`)
      .set('Authorization', bearer(petugas.token)).send({ kapasitas: 3 }).expect(403);
    await request(server()).delete(`/api/v1/slot-praktik/${slot.id}`)
      .set('Authorization', bearer(user.token)).expect(403);
  });

  it('ADMIN membuat slot, USER melihat kapasitas dan sisa', async () => {
    const slot = await buatSlot();
    expect(slot).toMatchObject({ aktif: true, kapasitas: 2, jumlahJanjiTemu: 0, sisaKapasitas: 2, tersedia: true });
    const daftar = await request(server())
      .get(`/api/v1/slot-praktik?jadwalPraktikId=${jadwalId}`)
      .set('Authorization', bearer(user.token)).expect(200);
    expect((daftar.body as SlotBody[]).some((item) => item.id === slot.id)).toBe(true);
    await request(server()).get(`/api/v1/slot-praktik/${slot.id}`)
      .set('Authorization', bearer(user.token)).expect(200);
  });

  it('menolak DTO tidak valid, field asing dan daftar tanpa jadwal ID', async () => {
    await request(server()).post('/api/v1/slot-praktik')
      .set('Authorization', bearer(admin.token))
      .send(bodySlot({ kapasitas: 0 })).expect(400);
    await request(server()).post('/api/v1/slot-praktik')
      .set('Authorization', bearer(admin.token))
      .send(bodySlot({ rahasia: 'x' })).expect(400);
    await request(server()).get('/api/v1/slot-praktik')
      .set('Authorization', bearer(user.token)).expect(400);
  });

  it('menolak slot di luar jam praktik', async () => {
    await request(server()).post('/api/v1/slot-praktik')
      .set('Authorization', bearer(admin.token))
      .send(bodySlot({ mulaiPada: jam('06:30') })).expect(400);
  });

  it('menolak overlap tetapi menerima slot berdampingan', async () => {
    await buatSlot();
    await request(server()).post('/api/v1/slot-praktik')
      .set('Authorization', bearer(admin.token))
      .send(bodySlot({ mulaiPada: jam('08:15'), selesaiPada: jam('08:45') })).expect(409);
    await buatSlot({ mulaiPada: jam('08:30'), selesaiPada: jam('09:00') });
  });

  it('dua permintaan paralel untuk slot sama: hanya satu berhasil', async () => {
    const [resA, resB] = await Promise.all([
      request(server()).post('/api/v1/slot-praktik').set('Authorization', bearer(admin.token)).send(bodySlot()),
      request(server()).post('/api/v1/slot-praktik').set('Authorization', bearer(admin.token)).send(bodySlot()),
    ]);
    expect([resA.status, resB.status].sort((a, b) => a - b)).toEqual([201, 409]);
  });

  it('PATCH memperbesar kapasitas dan menggeser waktu ke rentang aman', async () => {
    const slot = await buatSlot();
    const response = await request(server()).patch(`/api/v1/slot-praktik/${slot.id}`)
      .set('Authorization', bearer(admin.token))
      .send({ kapasitas: 4, selesaiPada: jam('08:45') }).expect(200);
    expect(response.body as SlotBody).toMatchObject({ kapasitas: 4, sisaKapasitas: 4 });
  });

  it('DELETE menonaktifkan slot dan USER tidak dapat melihatnya', async () => {
    const slot = await buatSlot();
    await request(server()).delete(`/api/v1/slot-praktik/${slot.id}`)
      .set('Authorization', bearer(admin.token)).expect(200);
    await request(server()).get(`/api/v1/slot-praktik/${slot.id}`)
      .set('Authorization', bearer(user.token)).expect(404);
    const adminView = await request(server()).get(`/api/v1/slot-praktik/${slot.id}`)
      .set('Authorization', bearer(admin.token)).expect(200);
    expect(adminView.body as SlotBody).toMatchObject({ aktif: false, tersedia: false });
  });

  it('slot yang sudah terkait janji temu tidak dapat dinonaktifkan atau digeser', async () => {
    const slot = await buatSlot();
    const tiket = await db().tiketAntrean.create({
      data: {
        penggunaId: user.id, layananId,
        tanggalAntrean: new Date(`${tanggal}T00:00:00.000Z`),
        nomorUrut: 1,
        kodeTiket: `SLOT${unik}`,
      },
    });
    await db().janjiTemu.create({ data: { tiketId: tiket.id, slotPraktikId: slot.id } });
    const read = await request(server()).get(`/api/v1/slot-praktik/${slot.id}`)
      .set('Authorization', bearer(user.token)).expect(200);
    expect(read.body as SlotBody).toMatchObject({ jumlahJanjiTemu: 1, sisaKapasitas: 1 });
    await request(server()).delete(`/api/v1/slot-praktik/${slot.id}`)
      .set('Authorization', bearer(admin.token)).expect(409);
    await request(server()).patch(`/api/v1/slot-praktik/${slot.id}`)
      .set('Authorization', bearer(admin.token))
      .send({ mulaiPada: jam('08:05') }).expect(409);
  });
});
