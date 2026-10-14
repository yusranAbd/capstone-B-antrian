import { randomUUID } from 'node:crypto';
import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { ThrottlerStorage } from '@nestjs/throttler';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/configure-app';
import { ModeReservasi, PeranPengguna, StatusTiket } from '../src/generated/prisma/client';
import { PrismaService } from '../src/prisma/prisma.service';

type Akun = { id: string; token: string };
type LoginBody = { accessToken: string };
type RegisterBody = { id: string };
type JanjiBody = {
  id: string;
  nomorAntrean: string;
  tanggalPelayanan: string;
  tiket: { id: string; status: StatusTiket; kodeTiket: string };
  slotPraktik: { id: string };
};

const tanggal = '2035-10-15';
const kodeUnik = randomUUID().replace(/-/g, '').slice(0, 9).toUpperCase();
const password = 'RahasiaJanjiTemuE2E123!';
function jam(waktu: string) {
  const zona = process.env.SERVICE_TIME_ZONE ?? 'Asia/Jakarta';
  const offset: Record<string, string> = {
    'Asia/Jakarta': '+07:00',
    'Asia/Makassar': '+08:00',
    'Asia/Jayapura': '+09:00',
  };
  if (!offset[zona]) throw new Error(`Fixture E2E belum mendukung timezone ${zona}`);
  return `${tanggal}T${waktu}:00${offset[zona]}`;
}

// Test membuat/menghapus datanya sendiri dan wajib menggunakan database E2E khusus.
describe('Poliklinik HIBRIDA H3.2 (e2e)', () => {
  let app: INestApplication | undefined;
  let prisma: PrismaService | undefined;
  let user!: Akun;
  let userLain!: Akun;
  let userKetiga!: Akun;
  const akunIds: string[] = [];
  let layananId = '';
  let ruangId = '';
  let dokterId = '';
  let pasanganId = '';
  let jadwalId = '';
  let slotId = '';

  function server() {
    if (!app) throw new Error('Aplikasi E2E belum siap');
    return app.getHttpServer();
  }
  function db() {
    if (!prisma) throw new Error('Prisma E2E belum siap');
    return prisma;
  }
  const bearer = (token: string) => `Bearer ${token}`;

  async function buatAkun(peran: PeranPengguna): Promise<Akun> {
    const email = `janji-h2-${randomUUID()}@test.local`;
    const reg = await request(server()).post('/api/v1/auth/register')
      .send({ nama: 'Pasien Test Janji Temu', email, kataSandi: password }).expect(201);
    const id = (reg.body as RegisterBody).id;
    akunIds.push(id);
    if (peran !== PeranPengguna.USER) {
      await db().pengguna.update({ where: { id }, data: { peran } });
    }
    const login = await request(server()).post('/api/v1/auth/login')
      .send({ email, kataSandi: password, namaPerangkat: 'Jest Janji H2.4' }).expect(200);
    return { id, token: (login.body as LoginBody).accessToken };
  }

  async function buatSlot(kapasitas = 2, mulai = '08:00', selesai = '08:30') {
    return db().slotPraktik.create({
      data: { jadwalPraktikId: jadwalId, mulaiPada: new Date(jam(mulai)), selesaiPada: new Date(jam(selesai)), kapasitas },
    });
  }

  function booking(akun: Akun, id = slotId) {
    return request(server()).post('/api/v1/janji-temu')
      .set('Authorization', bearer(akun.token)).send({ slotPraktikId: id });
  }

  async function bersihkanJanjiDanSlot() {
    if (!prisma || !layananId) return;
    const tiket = await db().tiketAntrean.findMany({ where: { layananId }, select: { id: true } });
    const tiketIds = tiket.map((item) => item.id);
    if (tiketIds.length) {
      await db().peristiwaAntrean.deleteMany({ where: { tiketAntreanId: { in: tiketIds } } });
      await db().janjiTemu.deleteMany({ where: { tiketId: { in: tiketIds } } });
      await db().tiketAntrean.deleteMany({ where: { id: { in: tiketIds } } });
    }
    await db().slotPraktik.deleteMany({ where: { jadwalPraktikId: jadwalId } });
    await db().urutanAntreanHarian.deleteMany({ where: { layananId } });
  }

  beforeAll(async () => {
    const raw = process.env.DATABASE_URL;
    if (!raw) throw new Error('DATABASE_URL wajib diatur khusus E2E');
    const url = new URL(raw);
    if (!['127.0.0.1', 'localhost'].includes(url.hostname) ||
        url.port !== '5433' || url.pathname !== '/capstone_antrean_test') {
      throw new Error('E2E hanya boleh memakai capstone_antrean_test lokal port 5433');
    }
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(ThrottlerStorage)
      .useValue({ increment: () => Promise.resolve({
        totalHits: 1, timeToExpire: 60000, isBlocked: false, timeToBlockExpire: 0,
      }) })
      .compile();
    app = moduleRef.createNestApplication();
    configureApp(app);
    await app.init();
    prisma = app.get(PrismaService);
    user = await buatAkun(PeranPengguna.USER);
    userLain = await buatAkun(PeranPengguna.USER);
    userKetiga = await buatAkun(PeranPengguna.USER);
    const layanan = await db().layanan.create({
      data: { kode: `J${kodeUnik}`, nama: 'Poli Appointment E2E', prefixAntrean: 'JT',
        durasiDasarMenit: 15, aktif: true, modeReservasi: ModeReservasi.HIBRIDA },
    });
    layananId = layanan.id;
    // Batas harian bersama, dipakai untuk walk-in dan appointment.
    await db().jadwalLayanan.create({ data: {
      layananId,
      hari: 'SENIN', // 15 Oktober 2035
      jamBuka: new Date('1970-01-01T07:00:00Z'),
      jamTutup: new Date('1970-01-01T18:00:00Z'),
      kapasitasHarian: 3,
    } });
    const ruang = await db().loket.create({ data: { layananId, kode: `R${kodeUnik}`, nama: 'Ruang Janji E2E' } });
    ruangId = ruang.id;
    const dokter = await db().dokter.create({ data: { kode: `D${kodeUnik}`, nama: 'Dokter Janji E2E' } });
    dokterId = dokter.id;
    const relasi = await db().dokterLayanan.create({ data: { dokterId, layananId } });
    pasanganId = relasi.id;
    const jadwal = await db().jadwalPraktik.create({ data: {
      dokterLayananId: pasanganId, loketId: ruangId,
      tanggal: new Date(`${tanggal}T00:00:00Z`),
      mulaiPada: new Date(jam('07:00')), selesaiPada: new Date(jam('12:00')),
    } });
    jadwalId = jadwal.id;
  }, 120000);

  beforeEach(async () => {
    const slot = await buatSlot();
    slotId = slot.id;
  });
  afterEach(async () => {
    await bersihkanJanjiDanSlot();
  }, 30000);
  afterAll(async () => {
    try {
      if (prisma) {
        await bersihkanJanjiDanSlot();
        if (jadwalId) await db().jadwalPraktik.deleteMany({ where: { id: jadwalId } });
        if (pasanganId) await db().dokterLayanan.deleteMany({ where: { id: pasanganId } });
        if (dokterId) await db().dokter.deleteMany({ where: { id: dokterId } });
        if (layananId) {
          await db().loket.deleteMany({ where: { layananId } });
          await db().jadwalLayanan.deleteMany({ where: { layananId } });
          await db().layanan.deleteMany({ where: { id: layananId } });
        }
        if (akunIds.length) {
          await db().sesiPengguna.deleteMany({ where: { penggunaId: { in: akunIds } } });
          await db().pengguna.deleteMany({ where: { id: { in: akunIds } } });
        }
      }
    } finally {
      if (app) await app.close();
    }
  }, 60000);

  const walkIn = (akun: Akun) => request(server())
    .post('/api/v1/reservasi')
    .set('Authorization', bearer(akun.token))
    .send({ layananId, tanggalAntrean: tanggal });

  it('satu poliklinik menerima walk-in dan appointment dengan counter bersama', async () => {
    const w = await walkIn(user).expect(201);
    const a = await booking(userLain).expect(201);
    expect(w.body as { nomorUrut: number }).toMatchObject({ nomorUrut: 1 });
    expect(a.body as JanjiBody).toMatchObject({ nomorAntrean: 'JT-002' });
    expect(await db().tiketAntrean.count({ where: { layananId } })).toBe(2);
    expect(await db().janjiTemu.count({ where: { slotPraktikId: slotId } })).toBe(1);
  });

  it('batas harian poliklinik dibagi antara kedua kanal reservasi', async () => {
    await db().jadwalLayanan.update({
      where: { layananId_hari: { layananId, hari: 'SENIN' } },
      data: { kapasitasHarian: 2 },
    });
    try {
      await walkIn(user).expect(201);
      await booking(userLain).expect(201);
      await booking(userKetiga).expect(409);
      expect(await db().tiketAntrean.count({ where: { layananId } })).toBe(2);
    } finally {
      await db().jadwalLayanan.update({
        where: { layananId_hari: { layananId, hari: 'SENIN' } },
        data: { kapasitasHarian: 3 },
      });
    }
  });

  it('dua kanal paralel memperebutkan kapasitas harian terakhir: satu berhasil', async () => {
    await db().jadwalLayanan.update({
      where: { layananId_hari: { layananId, hari: 'SENIN' } },
      data: { kapasitasHarian: 1 },
    });
    try {
      const [w, a] = await Promise.all([walkIn(user), booking(userLain)]);
      expect([w.status, a.status].sort((x, y) => x - y)).toEqual([201, 409]);
      expect(await db().tiketAntrean.count({ where: { layananId } })).toBe(1);
    } finally {
      await db().jadwalLayanan.update({
        where: { layananId_hari: { layananId, hari: 'SENIN' } },
        data: { kapasitasHarian: 3 },
      });
    }
  });

  it('satu pasien tidak boleh memiliki walk-in dan janji temu aktif pada poli/tanggal sama', async () => {
    await walkIn(user).expect(201);
    await booking(user).expect(409);
    expect(await db().tiketAntrean.count({ where: { layananId, penggunaId: user.id } })).toBe(1);
  });
});
