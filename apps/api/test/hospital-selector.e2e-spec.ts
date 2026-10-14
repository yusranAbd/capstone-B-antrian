import { randomBytes, randomUUID } from 'node:crypto';
import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { ThrottlerStorage } from '@nestjs/throttler';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/configure-app';
import {
  HariLayanan, ModeReservasi, PeranPengguna, StatusTiket,
} from '../src/generated/prisma/client';
import { PrismaService } from '../src/prisma/prisma.service';

type Akun = { id: string; token: string };
type Login = { accessToken: string };
type Daftar = { id: string };
type TiketHttp = { tiketId: string; status: StatusTiket; nomorAntrean: string };
type DaftarHttp = Array<{ tiketId: string; layakDipanggil?: boolean }>;
type SnapshotHttp = { menunggu: { tiket: Array<{ tiketId: string }> } };

/**
 * E2E menggunakan data terisolasi dalam capstone_antrean_test.
 * Tidak pernah menjalankan migrate reset atau memodifikasi layanan existing.
 */
describe('Hospital Queue Selector H3.3 (e2e)', () => {
  let app: INestApplication | undefined;
  let prisma: PrismaService | undefined;
  let petugas!: Akun;
  let pasienA!: Akun;
  let pasienB!: Akun;
  const akunIds: string[] = [];
  const kodeUnik = randomUUID().replace(/-/g, '').slice(0, 10).toUpperCase();
  const password = 'Rahasia-Hospital-Selector-E2E-123!';
  let layananId = '';
  let loketA = '';
  let loketB = '';
  let relasiA = '';
  let relasiB = '';
  let dokterA = '';
  let dokterB = '';
  let jadwalA = '';
  let jadwalB = '';
  let slotA = '';
  let slotB = '';
  let penugasanId = '';
  let tanggalDb: Date;
  let mulaiLayanan: Date;
  let selesaiLayanan: Date;
  let tanggalLokal = '';
  let zonaAwal: string | undefined;
  let urutan = 0;

  const db = () => {
    if (!prisma) throw new Error('Prisma E2E belum siap');
    return prisma;
  };
  const server = () => {
    if (!app) throw new Error('HTTP E2E belum siap');
    return app.getHttpServer();
  };
  const header = () => ({ Authorization: `Bearer ${petugas.token}` });

  async function buatAkun(peran: PeranPengguna): Promise<Akun> {
    const email = `hospital-h33-${randomUUID()}@test.local`;
    const register = await request(server()).post('/api/v1/auth/register')
      .send({ nama: 'Pengguna E2E H33', email, kataSandi: password }).expect(201);
    const id = (register.body as Daftar).id;
    akunIds.push(id);
    if (peran === PeranPengguna.PETUGAS) {
      await db().pengguna.update({ where: { id }, data: { peran } });
    }
    const login = await request(server()).post('/api/v1/auth/login')
      .send({ email, kataSandi: password, namaPerangkat: 'E2E H33' }).expect(200);
    return { id, token: (login.body as Login).accessToken };
  }

  async function buatTiket(
    penggunaId: string,
    menitLalu: number,
    slotId?: string,
  ) {
    urutan += 1;
    // Fixture counter yang diperlukan operasi REQUEUE existing.
    await db().urutanAntreanHarian.upsert({
      where: { layananId_tanggal: { layananId, tanggal: tanggalDb } },
      create: { layananId, tanggal: tanggalDb, nomorTerakhir: urutan, urutanMasukTerakhir: urutan },
      update: { nomorTerakhir: urutan, urutanMasukTerakhir: urutan },
    });
    const checkIn = new Date(Date.now() - menitLalu * 60_000);
    const tiket = await db().tiketAntrean.create({
      data: {
        penggunaId, layananId, tanggalAntrean: tanggalDb,
        nomorUrut: urutan,
        kodeTiket: `TK${randomBytes(12).toString('hex').toUpperCase()}`,
        status: StatusTiket.MENUNGGU,
        checkInPada: checkIn,
        masukAntreanPada: checkIn,
        urutanMasukAntrean: urutan,
      },
    });
    if (slotId) await db().janjiTemu.create({
      data: { tiketId: tiket.id, slotPraktikId: slotId },
    });
    return tiket.id;
  }

  async function bersihkanTiket() {
    if (!prisma || !layananId) return;
    const tiket = await db().tiketAntrean.findMany({
      where: { layananId }, select: { id: true },
    });
    const ids = tiket.map((x) => x.id);
    if (!ids.length) return;
    await db().peristiwaAntrean.deleteMany({ where: { tiketAntreanId: { in: ids } } });
    await db().janjiTemu.deleteMany({ where: { tiketId: { in: ids } } });
    await db().tiketAntrean.deleteMany({ where: { id: { in: ids } } });
  }

  beforeAll(async () => {
    const raw = process.env.DATABASE_URL;
    if (!raw) throw new Error('DATABASE_URL E2E wajib diatur');
    const url = new URL(raw);
    if (!['postgresql:', 'postgres:'].includes(url.protocol) ||
        !['127.0.0.1', 'localhost'].includes(url.hostname) ||
        url.port !== '5433' || url.pathname !== '/capstone_antrean_test') {
      throw new Error('E2E hanya boleh memakai capstone_antrean_test lokal port 5433');
    }
    // Sesuaikan jam layanan di test tanpa mengubah konfigurasi .env pada disk.
    zonaAwal = process.env.SERVICE_TIME_ZONE;
    process.env.SERVICE_TIME_ZONE = 'UTC';
    const now = new Date();
    tanggalLokal = now.toISOString().slice(0, 10);
    tanggalDb = new Date(`${tanggalLokal}T00:00:00.000Z`);
    mulaiLayanan = new Date(now.getTime() - 180 * 60_000);
    selesaiLayanan = new Date(now.getTime() + 180 * 60_000);
    const hari = [
      HariLayanan.MINGGU, HariLayanan.SENIN, HariLayanan.SELASA,
      HariLayanan.RABU, HariLayanan.KAMIS, HariLayanan.JUMAT, HariLayanan.SABTU,
    ][tanggalDb.getUTCDay()];
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(ThrottlerStorage)
      .useValue({ increment: () => Promise.resolve({
        totalHits: 1, timeToExpire: 60_000, isBlocked: false, timeToBlockExpire: 0,
      }) })
      .compile();
    app = moduleRef.createNestApplication();
    configureApp(app);
    await app.init();
    prisma = app.get(PrismaService);
    const connexion = await db().$queryRaw<Array<{ database: string }>>`
      SELECT current_database() AS "database"
    `;
    if (connexion[0]?.database !== 'capstone_antrean_test') {
      throw new Error('Koneksi aktual E2E tidak mengarah ke capstone_antrean_test');
    }
    petugas = await buatAkun(PeranPengguna.PETUGAS);
    pasienA = await buatAkun(PeranPengguna.USER);
    pasienB = await buatAkun(PeranPengguna.USER);
    const layanan = await db().layanan.create({ data: {
      kode: `H${kodeUnik}`, nama: 'Poli Hibrida H33', prefixAntrean: 'HS',
      modeReservasi: ModeReservasi.HIBRIDA, durasiDasarMenit: 15,
    } });
    layananId = layanan.id;
    await db().jadwalLayanan.create({ data: {
      layananId, hari, jamBuka: new Date('1970-01-01T00:00:00Z'),
      jamTutup: new Date('1970-01-01T23:59:59Z'), kapasitasHarian: 20,
    } });
    const ruangA = await db().loket.create({ data: {
      layananId, kode: `A${kodeUnik}`, nama: 'Ruang A',
    } });
    const ruangB = await db().loket.create({ data: {
      layananId, kode: `B${kodeUnik}`, nama: 'Ruang B',
    } });
    loketA = ruangA.id;
    loketB = ruangB.id;
    const p = await db().penugasanPetugas.create({ data: {
      petugasId: petugas.id, loketId: loketA, tanggalMulai: tanggalDb,
    } });
    penugasanId = p.id;
    const da = await db().dokter.create({ data: { kode: `A${kodeUnik}`, nama: 'Dokter H33 A' } });
    const dbb = await db().dokter.create({ data: { kode: `B${kodeUnik}`, nama: 'Dokter H33 B' } });
    dokterA = da.id;
    dokterB = dbb.id;
    const ra = await db().dokterLayanan.create({ data: { dokterId: dokterA, layananId } });
    const rb = await db().dokterLayanan.create({ data: { dokterId: dokterB, layananId } });
    relasiA = ra.id;
    relasiB = rb.id;
    const ja = await db().jadwalPraktik.create({ data: {
      dokterLayananId: relasiA, loketId: loketA,
      tanggal: tanggalDb, mulaiPada: mulaiLayanan, selesaiPada: selesaiLayanan,
    } });
    const jb = await db().jadwalPraktik.create({ data: {
      dokterLayananId: relasiB, loketId: loketB,
      tanggal: tanggalDb, mulaiPada: mulaiLayanan, selesaiPada: selesaiLayanan,
    } });
    jadwalA = ja.id;
    jadwalB = jb.id;
    const slot = await db().slotPraktik.create({ data: {
      jadwalPraktikId: jadwalA, mulaiPada: new Date(now.getTime() - 60 * 60_000),
      selesaiPada: new Date(now.getTime() + 60 * 60_000), kapasitas: 10,
    } });
    const slotRuangB = await db().slotPraktik.create({ data: {
      jadwalPraktikId: jadwalB, mulaiPada: new Date(now.getTime() - 60 * 60_000),
      selesaiPada: new Date(now.getTime() + 60 * 60_000), kapasitas: 10,
    } });
    slotA = slot.id;
    slotB = slotRuangB.id;
  }, 120_000);

  afterEach(async () => {
    await bersihkanTiket();
  }, 30_000);

  afterAll(async () => {
    try {
      if (prisma) {
        await bersihkanTiket();
        if (layananId) {
          await db().slotPraktik.deleteMany({ where: { jadwalPraktikId: { in: [jadwalA, jadwalB] } } });
          await db().jadwalPraktik.deleteMany({ where: { id: { in: [jadwalA, jadwalB] } } });
          await db().dokterLayanan.deleteMany({ where: { id: { in: [relasiA, relasiB] } } });
          await db().dokter.deleteMany({ where: { id: { in: [dokterA, dokterB] } } });
          if (penugasanId) await db().penugasanPetugas.deleteMany({ where: { id: penugasanId } });
          await db().loket.deleteMany({ where: { layananId } });
          await db().jadwalLayanan.deleteMany({ where: { layananId } });
          await db().urutanAntreanHarian.deleteMany({ where: { layananId } });
          await db().layanan.deleteMany({ where: { id: layananId } });
        }
        if (akunIds.length) {
          await db().sesiPengguna.deleteMany({ where: { penggunaId: { in: akunIds } } });
          await db().pengguna.deleteMany({ where: { id: { in: akunIds } } });
        }
      }
    } finally {
      if (app) await app.close();
      if (zonaAwal === undefined) delete process.env.SERVICE_TIME_ZONE;
      else process.env.SERVICE_TIME_ZONE = zonaAwal;
    }
  }, 60_000);

  it('CALL dan GET menunggu/snapshot sama-sama mengutamakan janji yang layak', async () => {
    const walk = await buatTiket(pasienA.id, 20);
    const janji = await buatTiket(pasienB.id, 5, slotA);
    const waiting = await request(server()).get('/api/v1/queue/menunggu')
      .set(header()).query({ loketId: loketA }).expect(200);
    expect((waiting.body as DaftarHttp).map((t) => t.tiketId)).toEqual([janji, walk]);
    const snapshot = await request(server()).get('/api/v1/queue/snapshot')
      .set(header()).query({ loketId: loketA }).expect(200);
    expect((snapshot.body as SnapshotHttp).menunggu.tiket.map((t) => t.tiketId)).toEqual([janji, walk]);
    const called = await request(server()).post('/api/v1/queue/panggil')
      .set(header()).send({ loketId: loketA }).expect(200);
    expect((called.body as TiketHttp).tiketId).toBe(janji);
  });

  it('walk-in dipanggil jika slot janji temu belum mulai', async () => {
    // Slot tambahan baru berlaku 90 menit lagi.
    const mulai = new Date(Date.now() + 90 * 60_000);
    const selesai = new Date(Date.now() + 120 * 60_000);
    const slotNanti = await db().slotPraktik.create({ data: {
      jadwalPraktikId: jadwalA, mulaiPada: mulai, selesaiPada: selesai, kapasitas: 2,
    } });
    try {
      const walk = await buatTiket(pasienA.id, 20);
      await buatTiket(pasienB.id, 5, slotNanti.id);
      const res = await request(server()).post('/api/v1/queue/panggil')
        .set(header()).send({ loketId: loketA }).expect(200);
      expect((res.body as TiketHttp).tiketId).toBe(walk);
    } finally {
      await bersihkanTiket();
      await db().slotPraktik.delete({ where: { id: slotNanti.id } });
    }
  });

  it('ruang A tidak memanggil pasien appointment di ruang B', async () => {
    await buatTiket(pasienA.id, 5, slotB);
    await request(server()).post('/api/v1/queue/panggil')
      .set(header()).send({ loketId: loketA }).expect(404);
    expect(await db().tiketAntrean.count({ where: {
      layananId, status: StatusTiket.DIPANGGIL,
    } })).toBe(0);
  });

  it.each([ModeReservasi.HIBRIDA, ModeReservasi.JANJI_TEMU_DOKTER])(
    'appointment setelah slot berakhir tetap layak pada CALL, daftar dan snapshot mode %s', async (mode) => {
      const asli = await db().slotPraktik.findUniqueOrThrow({ where: { id: slotA } });
      await db().layanan.update({ where: { id: layananId }, data: { modeReservasi: mode } });
      try {
        await db().slotPraktik.update({ where: { id: slotA }, data: {
          selesaiPada: new Date(Date.now() - 10 * 60_000),
        } });
        const janji = await buatTiket(pasienA.id, 20, slotA);
        const daftar = await request(server()).get('/api/v1/queue/menunggu')
          .set(header()).query({ loketId: loketA }).expect(200);
        expect((daftar.body as DaftarHttp)[0]).toMatchObject({ tiketId: janji, layakDipanggil: true });
        const snapshot = await request(server()).get('/api/v1/queue/snapshot')
          .set(header()).query({ loketId: loketA }).expect(200);
        expect((snapshot.body as SnapshotHttp).menunggu.tiket[0]?.tiketId).toBe(janji);
        const hasil = await request(server()).post('/api/v1/queue/panggil')
          .set(header()).send({ loketId: loketA }).expect(200);
        expect((hasil.body as TiketHttp).tiketId).toBe(janji);
      } finally {
        await db().slotPraktik.update({ where: { id: slotA }, data: { selesaiPada: asli.selesaiPada } });
        await db().layanan.update({ where: { id: layananId }, data: { modeReservasi: ModeReservasi.HIBRIDA } });
      }
    },
  );

  it.each(['JANJI_TEMU', 'WALK_IN'] as const)(
    'REQUEUE %s menggunakan waktu antre ulang tanpa mengubah nomor dan check-in', async (jenis) => {
      const slotId = jenis === 'JANJI_TEMU' ? slotA : undefined;
      const ulang = await buatTiket(pasienA.id, 20, slotId);
      const menunggu = await buatTiket(pasienB.id, 5, slotId);
      const sebelum = await db().tiketAntrean.findUniqueOrThrow({ where: { id: ulang } });
      const call = await request(server()).post('/api/v1/queue/panggil')
        .set(header()).send({ loketId: loketA }).expect(200);
      expect((call.body as TiketHttp).tiketId).toBe(ulang);
      await request(server()).post(`/api/v1/queue/${ulang}/lewati`)
        .set(header()).send({ loketId: loketA }).expect(200);
      const requeue = await request(server()).post(`/api/v1/queue/${ulang}/antre-ulang`)
        .set(header()).send({ loketId: loketA }).expect(200);
      expect((requeue.body as TiketHttp).nomorAntrean).toBe((call.body as TiketHttp).nomorAntrean);
      const sesudah = await db().tiketAntrean.findUniqueOrThrow({ where: { id: ulang } });
      expect(sesudah.checkInPada).toEqual(sebelum.checkInPada);
      expect(sesudah.urutanMasukAntrean).toBeGreaterThan(sebelum.urutanMasukAntrean ?? 0);
      const daftar = await request(server()).get('/api/v1/queue/menunggu')
        .set(header()).query({ loketId: loketA }).expect(200);
      expect((daftar.body as DaftarHttp).map((tiket) => tiket.tiketId)).toEqual([menunggu, ulang]);
      const snapshot = await request(server()).get('/api/v1/queue/snapshot')
        .set(header()).query({ loketId: loketA }).expect(200);
      expect((snapshot.body as SnapshotHttp).menunggu.tiket.map((tiket) => tiket.tiketId)).toEqual([menunggu, ulang]);
      const berikut = await request(server()).post('/api/v1/queue/panggil')
        .set(header()).send({ loketId: loketA }).expect(200);
      expect((berikut.body as TiketHttp).tiketId).toBe(menunggu);
    },
  );

  it.each(['sesi-berakhir', 'sesi-belum-mulai', 'tanggal-sesi-lain', 'tanggal-tiket-lain', 'sesi-nonaktif', 'ruang-lain'] as const)(
    'slot berakhir tidak mengizinkan CALL appointment dengan %s', async (kasus) => {
      const sesiAsli = await db().jadwalPraktik.findUniqueOrThrow({ where: { id: jadwalA } });
      const slotAsli = await db().slotPraktik.findUniqueOrThrow({ where: { id: slotA } });
      const kini = new Date();
      const tanggalLain = new Date(tanggalDb.getTime() + 86_400_000);
      try {
        await db().slotPraktik.update({ where: { id: slotA }, data: {
          selesaiPada: new Date(kini.getTime() - 10 * 60_000),
        } });
        const janji = await buatTiket(pasienA.id, 20, slotA);
        if (kasus === 'sesi-berakhir') {
          await db().jadwalPraktik.update({ where: { id: jadwalA }, data: {
            selesaiPada: new Date(kini.getTime() - 5 * 60_000),
          } });
        }
        if (kasus === 'sesi-belum-mulai') {
          await db().jadwalPraktik.update({ where: { id: jadwalA }, data: {
            mulaiPada: new Date(kini.getTime() + 60_000),
          } });
        }
        if (kasus === 'tanggal-sesi-lain') {
          await db().jadwalPraktik.update({ where: { id: jadwalA }, data: { tanggal: tanggalLain } });
        }
        if (kasus === 'tanggal-tiket-lain') {
          await db().tiketAntrean.update({ where: { id: janji }, data: { tanggalAntrean: tanggalLain } });
        }
        if (kasus === 'sesi-nonaktif') {
          await db().jadwalPraktik.update({ where: { id: jadwalA }, data: { aktif: false } });
        }
        if (kasus === 'ruang-lain') {
          await db().jadwalPraktik.update({ where: { id: jadwalA }, data: { loketId: loketB } });
        }
        const daftar = await request(server()).get('/api/v1/queue/menunggu')
          .set(header()).query({ loketId: loketA }).expect(200);
        const snapshot = await request(server()).get('/api/v1/queue/snapshot')
          .set(header()).query({ loketId: loketA }).expect(200);
        if (kasus === 'tanggal-tiket-lain') {
          expect(daftar.body).toEqual([]);
          expect((snapshot.body as SnapshotHttp).menunggu.tiket).toEqual([]);
        } else {
          expect((daftar.body as DaftarHttp)[0]).toMatchObject({ tiketId: janji, layakDipanggil: false });
          expect((snapshot.body as SnapshotHttp).menunggu.tiket[0]).toMatchObject({ tiketId: janji, layakDipanggil: false });
        }
        await request(server()).post('/api/v1/queue/panggil')
          .set(header()).send({ loketId: loketA }).expect(404);
        expect(await db().tiketAntrean.count({ where: { layananId, status: StatusTiket.DIPANGGIL } })).toBe(0);
      } finally {
        await db().jadwalPraktik.update({ where: { id: jadwalA }, data: {
          mulaiPada: sesiAsli.mulaiPada, selesaiPada: sesiAsli.selesaiPada,
          tanggal: sesiAsli.tanggal, aktif: sesiAsli.aktif, loketId: sesiAsli.loketId,
        } });
        await db().slotPraktik.update({ where: { id: slotA }, data: { selesaiPada: slotAsli.selesaiPada } });
      }
    },
  );

  it('pelayanan yang sudah dimulai dapat diselesaikan setelah sesi praktik berakhir', async () => {
    const janji = await buatTiket(pasienA.id, 20, slotA);
    await request(server()).post('/api/v1/queue/panggil')
      .set(header()).send({ loketId: loketA }).expect(200);
    await request(server()).post(`/api/v1/queue/${janji}/mulai-pelayanan`)
      .set(header()).send({ loketId: loketA }).expect(200);
    const sesiAsli = await db().jadwalPraktik.findUniqueOrThrow({ where: { id: jadwalA } });
    try {
      await db().jadwalPraktik.update({ where: { id: jadwalA }, data: {
        selesaiPada: new Date(Date.now() - 60_000),
      } });
      const selesai = await request(server()).post(`/api/v1/queue/${janji}/selesaikan-pelayanan`)
        .set(header()).send({ loketId: loketA }).expect(200);
      expect((selesai.body as TiketHttp).status).toBe(StatusTiket.SELESAI);
    } finally {
      await db().jadwalPraktik.update({ where: { id: jadwalA }, data: { selesaiPada: sesiAsli.selesaiPada } });
    }
  });

  it('ANTREAN_HARIAN tetap FIFO urutan masuk walaupun waktu check-in berlawanan', async () => {
    await db().layanan.update({ where: { id: layananId }, data: { modeReservasi: ModeReservasi.ANTREAN_HARIAN } });
    try {
      const pertama = await buatTiket(pasienA.id, 5);
      const kedua = await buatTiket(pasienB.id, 20);
      const daftar = await request(server()).get('/api/v1/queue/menunggu')
        .set(header()).query({ loketId: loketA }).expect(200);
      expect((daftar.body as DaftarHttp).map((tiket) => tiket.tiketId)).toEqual([pertama, kedua]);
      expect((daftar.body as DaftarHttp)[0]).not.toHaveProperty('layakDipanggil');
      const snapshot = await request(server()).get('/api/v1/queue/snapshot')
        .set(header()).query({ loketId: loketA }).expect(200);
      expect((snapshot.body as SnapshotHttp).menunggu.tiket.map((tiket) => tiket.tiketId)).toEqual([pertama, kedua]);
      const berikut = await request(server()).post('/api/v1/queue/panggil')
        .set(header()).send({ loketId: loketA }).expect(200);
      expect((berikut.body as TiketHttp).tiketId).toBe(pertama);
    } finally {
      await db().layanan.update({ where: { id: layananId }, data: { modeReservasi: ModeReservasi.HIBRIDA } });
    }
  });

  it('REQUEUE berulang memakai audit terbaru, bukan audit antre ulang pertama', async () => {
    const pertama = await buatTiket(pasienA.id, 20);
    const kedua = await buatTiket(pasienB.id, 5);
    const panggilDanAntreUlang = async (id: string) => {
      const call = await request(server()).post('/api/v1/queue/panggil')
        .set(header()).send({ loketId: loketA }).expect(200);
      expect((call.body as TiketHttp).tiketId).toBe(id);
      await request(server()).post(`/api/v1/queue/${id}/lewati`)
        .set(header()).send({ loketId: loketA }).expect(200);
      await request(server()).post(`/api/v1/queue/${id}/antre-ulang`)
        .set(header()).send({ loketId: loketA }).expect(200);
    };
    await panggilDanAntreUlang(pertama);
    await panggilDanAntreUlang(kedua);
    await panggilDanAntreUlang(pertama);
    const daftar = await request(server()).get('/api/v1/queue/menunggu')
      .set(header()).query({ loketId: loketA }).expect(200);
    expect((daftar.body as DaftarHttp).map((tiket) => tiket.tiketId)).toEqual([kedua, pertama]);
    const berikut = await request(server()).post('/api/v1/queue/panggil')
      .set(header()).send({ loketId: loketA }).expect(200);
    expect((berikut.body as TiketHttp).tiketId).toBe(kedua);
  });

  it('dua CALL bersamaan pada satu loket tidak boleh sama-sama berhasil', async () => {
    await buatTiket(pasienA.id, 20);
    await buatTiket(pasienB.id, 5, slotA);
    const [a, b] = await Promise.all([
      request(server()).post('/api/v1/queue/panggil').set(header()).send({ loketId: loketA }),
      request(server()).post('/api/v1/queue/panggil').set(header()).send({ loketId: loketA }),
    ]);
    expect([a.status, b.status].sort((x, y) => x - y)).toEqual([200, 409]);
    expect(await db().tiketAntrean.count({ where: {
      layananId, status: StatusTiket.DIPANGGIL,
    } })).toBe(1);
  });
});
