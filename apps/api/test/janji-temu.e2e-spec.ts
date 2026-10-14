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
describe('Appointment Booking API H2.4 (e2e)', () => {
  let app: INestApplication | undefined;
  let prisma: PrismaService | undefined;
  let admin!: Akun;
  let user!: Akun;
  let userLain!: Akun;
  let petugas!: Akun;
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
    admin = await buatAkun(PeranPengguna.ADMIN);
    user = await buatAkun(PeranPengguna.USER);
    userLain = await buatAkun(PeranPengguna.USER);
    petugas = await buatAkun(PeranPengguna.PETUGAS);
    const layanan = await db().layanan.create({
      data: { kode: `J${kodeUnik}`, nama: 'Poli Appointment E2E', prefixAntrean: 'JT',
        durasiDasarMenit: 15, aktif: true, modeReservasi: ModeReservasi.JANJI_TEMU_DOKTER },
    });
    layananId = layanan.id;
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

  it('JWT diperlukan untuk booking dan daftar janji temu', async () => {
    await request(server()).post('/api/v1/janji-temu').send({ slotPraktikId: slotId }).expect(401);
    await request(server()).get('/api/v1/janji-temu').expect(401);
  });

  it('hanya USER dapat membuat janji temu', async () => {
    await booking(admin).expect(403);
    await booking(petugas).expect(403);
  });

  it('DTO menolak UUID tidak valid dan field asing', async () => {
    await request(server()).post('/api/v1/janji-temu').set('Authorization', bearer(user.token))
      .send({ slotPraktikId: 'bukan-uuid' }).expect(400);
    await request(server()).post('/api/v1/janji-temu').set('Authorization', bearer(user.token))
      .send({ slotPraktikId: slotId, penggunaId: userLain.id }).expect(400);
  });

  it('booking membuat tiket, nomor permanen, janji dan audit yang konsisten', async () => {
    const res = await booking(user).expect(201);
    const isi = res.body as JanjiBody;
    expect(isi).toMatchObject({ nomorAntrean: 'JT-001', tanggalPelayanan: tanggal });
    expect(isi.tiket).toMatchObject({ status: StatusTiket.DIPESAN });
    expect(isi.slotPraktik.id).toBe(slotId);
    expect(isi.tiket.kodeTiket).toHaveLength(26);
    const tersimpan = await db().janjiTemu.findUnique({ where: { id: isi.id }, include: { tiket: true } });
    expect(tersimpan?.tiketId).toBe(isi.tiket.id);
    expect(tersimpan?.tiket.penggunaId).toBe(user.id);
    const audit = await db().peristiwaAntrean.findMany({ where: { tiketAntreanId: isi.tiket.id } });
    expect(audit).toHaveLength(1);
    expect(audit[0]?.tipe).toBe('APPOINTMENT_BOOK');
    // Tiket yang sama tersedia lewat endpoint tiket existing (tanpa mengganti QR/token).
    await request(server()).get(`/api/v1/tiket/${isi.tiket.id}`)
      .set('Authorization', bearer(user.token)).expect(200);
  });

  it('pemilik dapat melihat daftar dan detail, tetapi pengguna lain memperoleh 404', async () => {
    const isi = (await booking(user).expect(201)).body as JanjiBody;
    const daftar = await request(server()).get('/api/v1/janji-temu')
      .set('Authorization', bearer(user.token)).expect(200);
    expect((daftar.body as JanjiBody[]).some((item) => item.id === isi.id)).toBe(true);
    await request(server()).get(`/api/v1/janji-temu/${isi.id}`)
      .set('Authorization', bearer(userLain.token)).expect(404);
    const listLain = await request(server()).get('/api/v1/janji-temu')
      .set('Authorization', bearer(userLain.token)).expect(200);
    expect((listLain.body as JanjiBody[]).some((item) => item.id === isi.id)).toBe(false);
  });

  it('menolak reservasi ganda untuk poliklinik dan tanggal yang sama', async () => {
    await booking(user).expect(201);
    await booking(user).expect(409);
    const jumlah = await db().janjiTemu.count({ where: { slotPraktikId: slotId } });
    expect(jumlah).toBe(1);
  });

  it('kapasitas satu dengan dua USER paralel hanya menghasilkan satu booking', async () => {
    await db().slotPraktik.update({ where: { id: slotId }, data: { kapasitas: 1 } });
    const [a, b] = await Promise.all([booking(user), booking(userLain)]);
    expect([a.status, b.status].sort((x, y) => x - y)).toEqual([201, 409]);
    expect(await db().janjiTemu.count({ where: { slotPraktikId: slotId } })).toBe(1);
  });

  it('pasien tidak boleh memakai endpoint reservasi harian pada mode dokter', async () => {
    await request(server()).post('/api/v1/reservasi').set('Authorization', bearer(user.token))
      .send({ layananId, tanggalAntrean: tanggal }).expect(400);
    expect(await db().tiketAntrean.count({ where: { layananId } })).toBe(0);
  });

  it('pembatalan melepas kapasitas dan menjaga tiket serta histori', async () => {
    await db().slotPraktik.update({ where: { id: slotId }, data: { kapasitas: 1 } });
    const pertama = (await booking(user).expect(201)).body as JanjiBody;
    await request(server()).post(`/api/v1/janji-temu/${pertama.id}/batalkan`)
      .set('Authorization', bearer(user.token)).expect(201);
    const tiket = await db().tiketAntrean.findUnique({ where: { id: pertama.tiket.id } });
    expect(tiket?.status).toBe(StatusTiket.DIBATALKAN);
    expect(await db().janjiTemu.count({ where: { id: pertama.id } })).toBe(1);
    const lihatSlot = await request(server()).get(`/api/v1/slot-praktik/${slotId}`)
      .set('Authorization', bearer(userLain.token)).expect(200);
    expect(lihatSlot.body as Record<string, unknown>).toMatchObject({ jumlahJanjiTemu: 0, sisaKapasitas: 1, tersedia: true });
    await booking(userLain).expect(201);
    await request(server()).post(`/api/v1/janji-temu/${pertama.id}/batalkan`)
      .set('Authorization', bearer(user.token)).expect(409);
  });

  it('pengguna lain tidak dapat membatalkan janji milik pasien', async () => {
    const pertama = (await booking(user).expect(201)).body as JanjiBody;
    await request(server()).post(`/api/v1/janji-temu/${pertama.id}/batalkan`)
      .set('Authorization', bearer(userLain.token)).expect(404);
    expect((await db().tiketAntrean.findUnique({ where: { id: pertama.tiket.id } }))?.status)
      .toBe(StatusTiket.DIPESAN);
  });

  it('janji yang sudah CHECK_IN tidak dapat dibatalkan', async () => {
    const pertama = (await booking(user).expect(201)).body as JanjiBody;
    await db().tiketAntrean.update({ where: { id: pertama.tiket.id }, data: { status: StatusTiket.CHECK_IN } });
    await request(server()).post(`/api/v1/janji-temu/${pertama.id}/batalkan`)
      .set('Authorization', bearer(user.token)).expect(409);
  });
});
