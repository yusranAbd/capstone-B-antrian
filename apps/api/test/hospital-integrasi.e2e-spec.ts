import { randomUUID } from 'node:crypto';
import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { ThrottlerStorage } from '@nestjs/throttler';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/configure-app';
import {
  HariLayanan,
  ModeReservasi,
  PeranPengguna,
  StatusTiket,
} from '../src/generated/prisma/client';
import { PrismaService } from '../src/prisma/prisma.service';

type Akun = { id: string; email: string; token: string };
type Janji = { id: string; tiket: { id: string } };
type Waiting = Array<{
  tiketId: string;
  status: string;
  layakDipanggil?: boolean;
  alasanTidakLayak?: string | null;
}>;

/** Hanya fixture unik milik suite; tidak mengubah database utama atau menjalankan migration. */
describe('Integrasi Hospital dan HOSP-OPS-01 (e2e)', () => {
  let app: INestApplication | undefined;
  let prisma: PrismaService | undefined;
  let pasien: Akun[] = [];
  let petugas!: Akun;
  let petugasLain!: Akun;
  let admin!: Akun;
  const akunIds: string[] = [];
  const sandi = 'Fixture-Hospital-Integrasi-123!';
  const zonaAwal = process.env.SERVICE_TIME_ZONE;
  let layananId = '';
  let ruangId = '';
  let ruangLainId = '';
  let dokterId = '';
  let relasiId = '';
  let sesiId = '';
  let slotId = '';
  let tanggal = '';
  let tanggalDb: Date;
  let mulaiSlot: Date;
  let akhirSlot: Date;
  let akhirSesi: Date;
  const db = () => {
    if (!prisma) throw new Error('Prisma belum siap');
    return prisma;
  };
  const server = () => {
    if (!app) throw new Error('HTTP belum siap');
    return app.getHttpServer();
  };
  const auth = (akun: Akun) => ({ Authorization: `Bearer ${akun.token}` });
  async function buatMaster(
    path: string,
    body: object,
  ): Promise<{ id: string }> {
    const res = await request(server())
      .post(`/api/v1/${path}`)
      .set(auth(admin))
      .send(body)
      .expect(201);
    return res.body as { id: string };
  }

  async function login(akun: Akun) {
    const hasil = await request(server())
      .post('/api/v1/auth/login')
      .send({ email: akun.email, kataSandi: sandi })
      .expect(200);
    akun.token = (hasil.body as { accessToken: string }).accessToken;
  }
  async function akun(peran: PeranPengguna): Promise<Akun> {
    const email = `integrasi-${randomUUID()}@test.local`;
    const res = await request(server())
      .post('/api/v1/auth/register')
      .send({ nama: 'Fixture Integrasi Hospital', email, kataSandi: sandi })
      .expect(201);
    const id = (res.body as { id: string }).id;
    akunIds.push(id);
    if (peran !== PeranPengguna.USER)
      await db().pengguna.update({ where: { id }, data: { peran } });
    const hasil = { id, email, token: '' };
    await login(hasil);
    return hasil;
  }
  const booking = (pemilik: Akun) =>
    request(server())
      .post('/api/v1/janji-temu')
      .set(auth(pemilik))
      .send({ slotPraktikId: slotId });
  const walkIn = (pemilik: Akun) =>
    request(server())
      .post('/api/v1/reservasi')
      .set(auth(pemilik))
      .send({ layananId, tanggalAntrean: tanggal });
  const queue = (path: string, petugasPeminta = petugas, ruang = ruangId) =>
    request(server())
      .post(`/api/v1/queue/${path}`)
      .set(auth(petugasPeminta))
      .send({ loketId: ruang });
  async function qr(tiketId: string, pemilik: Akun) {
    const res = await request(server())
      .post(`/api/v1/tiket/${tiketId}/qr`)
      .set(auth(pemilik))
      .expect(201);
    return (res.body as { qrPayload: string }).qrPayload;
  }
  async function masuk(tiketId: string, pemilik: Akun) {
    const payload = await qr(tiketId, pemilik);
    await request(server())
      .post('/api/v1/check-in')
      .set(auth(petugas))
      .send({ qrPayload: payload, loketId: ruangId })
      .expect(200);
    await queue(`${tiketId}/masuk`).expect(200);
  }

  beforeAll(async () => {
    const url = new URL(process.env.DATABASE_URL ?? 'http://invalid');
    if (
      !['postgresql:', 'postgres:'].includes(url.protocol) ||
      url.hostname !== '127.0.0.1' ||
      url.port !== '5433' ||
      url.pathname !== '/capstone_antrean_test'
    ) {
      throw new Error('E2E wajib memakai 127.0.0.1:5433/capstone_antrean_test');
    }
    process.env.SERVICE_TIME_ZONE = 'UTC';
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(ThrottlerStorage)
      .useValue({
        increment: () =>
          Promise.resolve({
            totalHits: 1,
            timeToExpire: 60_000,
            isBlocked: false,
            timeToBlockExpire: 0,
          }),
      })
      .compile();
    app = moduleRef.createNestApplication();
    configureApp(app);
    await app.listen(0, '127.0.0.1');
    prisma = app.get(PrismaService);
    const actual = await db().$queryRaw<
      Array<{ nama: string }>
    >`SELECT current_database() AS "nama"`;
    if (actual[0]?.nama !== 'capstone_antrean_test')
      throw new Error('Koneksi aktual E2E tidak sesuai');
    for (let i = 0; i < 3; i++) pasien.push(await akun(PeranPengguna.USER));
    petugas = await akun(PeranPengguna.PETUGAS);
    petugasLain = await akun(PeranPengguna.PETUGAS);
    admin = await akun(PeranPengguna.ADMIN);
  }, 120_000);

  beforeEach(async () => {
    tanggal = new Date().toISOString().slice(0, 10);
    // Hanya Date yang dikontrol. Timer HTTP/DB tetap nyata; tidak menetapkan toleransi operasional.
    jest.useFakeTimers({
      now: new Date(`${tanggal}T12:00:00Z`),
      doNotFake: [
        'nextTick',
        'setTimeout',
        'clearTimeout',
        'setInterval',
        'clearInterval',
        'setImmediate',
        'clearImmediate',
        'hrtime',
        'performance',
        'queueMicrotask',
      ],
    });
    for (const pemilik of [...pasien, petugas, petugasLain, admin])
      await login(pemilik);
    tanggalDb = new Date(`${tanggal}T00:00:00Z`);
    mulaiSlot = new Date(`${tanggal}T12:01:00Z`);
    akhirSlot = new Date(`${tanggal}T12:02:00Z`);
    akhirSesi = new Date(`${tanggal}T12:10:00Z`);
    const unik = randomUUID().replace(/-/g, '').slice(0, 10).toUpperCase();
    layananId = (
      await buatMaster('layanan', {
        kode: `I${unik}`,
        nama: 'Poli Integrasi E2E',
        prefixAntrean: 'HI',
        durasiDasarMenit: 5,
        modeReservasi: ModeReservasi.HIBRIDA,
      })
    ).id;
    const hari = [
      HariLayanan.MINGGU,
      HariLayanan.SENIN,
      HariLayanan.SELASA,
      HariLayanan.RABU,
      HariLayanan.KAMIS,
      HariLayanan.JUMAT,
      HariLayanan.SABTU,
    ][tanggalDb.getUTCDay()];
    await buatMaster('jadwal-layanan', {
      layananId,
      hari,
      kapasitasHarian: 5,
      jamBuka: '00:00',
      jamTutup: '23:59',
    });
    ruangId = (
      await buatMaster('loket', {
        layananId,
        kode: `A${unik}`,
        nama: 'Ruang Integrasi A',
      })
    ).id;
    ruangLainId = (
      await buatMaster('loket', {
        layananId,
        kode: `B${unik}`,
        nama: 'Ruang Integrasi B',
      })
    ).id;
    await buatMaster('penugasan-petugas', {
      petugasId: petugas.id,
      loketId: ruangId,
      tanggalMulai: tanggal,
    });
    await buatMaster('penugasan-petugas', {
      petugasId: petugasLain.id,
      loketId: ruangLainId,
      tanggalMulai: tanggal,
    });
    dokterId = (
      await buatMaster('dokter', {
        kode: `D${unik}`,
        nama: 'Dokter Integrasi E2E',
      })
    ).id;
    relasiId = (await buatMaster(`dokter/${dokterId}/layanan`, { layananId }))
      .id;
    sesiId = (
      await buatMaster('jadwal-praktik', {
        dokterLayananId: relasiId,
        loketId: ruangId,
        tanggal,
        mulaiPada: tanggalDb.toISOString(),
        selesaiPada: akhirSesi.toISOString(),
      })
    ).id;
    slotId = (
      await buatMaster('slot-praktik', {
        jadwalPraktikId: sesiId,
        mulaiPada: mulaiSlot.toISOString(),
        selesaiPada: akhirSlot.toISOString(),
        kapasitas: 5,
      })
    ).id;
  }, 60_000);

  afterEach(async () => {
    jest.useRealTimers();
    if (!prisma || !layananId) return;
    const ids = (
      await db().tiketAntrean.findMany({
        where: { layananId },
        select: { id: true },
      })
    ).map((t) => t.id);
    await db().peristiwaAntrean.deleteMany({
      where: { tiketAntreanId: { in: ids } },
    });
    await db().janjiTemu.deleteMany({ where: { tiketId: { in: ids } } });
    await db().tiketAntrean.deleteMany({ where: { id: { in: ids } } });
    // Setup can fail before a session ID exists; still clean only this clinic's fixtures.
    await db().slotPraktik.deleteMany({
      where: { jadwalPraktik: { dokterLayanan: { layananId } } },
    });
    await db().jadwalPraktik.deleteMany({
      where: { dokterLayanan: { layananId } },
    });
    await db().dokterLayanan.deleteMany({ where: { layananId } });
    if (dokterId) await db().dokter.deleteMany({ where: { id: dokterId } });
    await db().penugasanPetugas.deleteMany({
      where: { loket: { layananId } },
    });
    await db().loket.deleteMany({ where: { layananId } });
    await db().jadwalLayanan.deleteMany({ where: { layananId } });
    await db().urutanAntreanHarian.deleteMany({ where: { layananId } });
    await db().layanan.deleteMany({ where: { id: layananId } });
    layananId = '';
    ruangId = '';
    ruangLainId = '';
    dokterId = '';
    sesiId = '';
    slotId = '';
  }, 60_000);

  afterAll(async () => {
    try {
      if (prisma && akunIds.length) {
        await db().sesiPengguna.deleteMany({
          where: { penggunaId: { in: akunIds } },
        });
        await db().pengguna.deleteMany({ where: { id: { in: akunIds } } });
      }
    } finally {
      jest.useRealTimers();
      await app?.close();
      if (zonaAwal === undefined) delete process.env.SERVICE_TIME_ZONE;
      else process.env.SERVICE_TIME_ZONE = zonaAwal;
    }
  }, 60_000);

  it.each(['appointment', 'walk-in'] as const)(
    '%s melewati QR, CHECK_IN, ENQUEUE, CALL, START, COMPLETE',
    async (jenis) => {
      const poli = await request(server())
        .get('/api/v1/layanan')
        .set(auth(pasien[0]))
        .expect(200);
      expect(poli.body).toEqual(
        expect.arrayContaining([
          expect.objectContaining({
            id: layananId,
            modeReservasi: ModeReservasi.HIBRIDA,
          }),
        ]),
      );
      if (jenis === 'appointment') {
        const dokter = await request(server())
          .get('/api/v1/dokter')
          .set(auth(pasien[0]))
          .expect(200);
        expect(dokter.body).toEqual(
          expect.arrayContaining([expect.objectContaining({ id: dokterId })]),
        );
        const jadwal = await request(server())
          .get('/api/v1/jadwal-praktik')
          .set(auth(pasien[0]))
          .query({ dokterId, layananId, tanggal })
          .expect(200);
        expect(jadwal.body).toEqual(
          expect.arrayContaining([expect.objectContaining({ id: sesiId })]),
        );
        const slots = await request(server())
          .get('/api/v1/slot-praktik')
          .set(auth(pasien[0]))
          .query({ jadwalPraktikId: sesiId })
          .expect(200);
        expect(slots.body).toEqual(
          expect.arrayContaining([
            expect.objectContaining({ id: slotId, tersedia: true }),
          ]),
        );
      }
      const res = await (
        jenis === 'appointment' ? booking(pasien[0]) : walkIn(pasien[0])
      ).expect(201);
      const id =
        jenis === 'appointment'
          ? (res.body as Janji).tiket.id
          : (res.body as { id: string }).id;
      if (jenis === 'appointment')
        jest.setSystemTime(new Date(akhirSlot.getTime() + 1000));
      await masuk(id, pasien[0]);
      const call = await queue('panggil').expect(200);
      expect((call.body as { tiketId: string }).tiketId).toBe(id);
      await queue(`${id}/mulai-pelayanan`).expect(200);
      await queue(`${id}/selesaikan-pelayanan`).expect(200);
      const tiket = await db().tiketAntrean.findUniqueOrThrow({
        where: { id },
      });
      expect(tiket.status).toBe(StatusTiket.SELESAI);
      expect(tiket.tokenQrHash).toBeNull();
      const audit = await db().peristiwaAntrean.findMany({
        where: { tiketAntreanId: id },
      });
      expect(audit.map((a) => a.tipe)).toEqual(
        expect.arrayContaining([
          'CHECK_IN',
          'ENQUEUE',
          'CALL',
          'START_SERVICE',
          'COMPLETE',
        ]),
      );
    },
  );

  it('walk-in dan appointment berbagi poli, kapasitas, nomor dan prioritas operasional', async () => {
    const walk = await walkIn(pasien[0]).expect(201);
    const janji = await booking(pasien[1]).expect(201);
    const walkId = (walk.body as { id: string }).id;
    const janjiId = (janji.body as Janji).tiket.id;
    await masuk(walkId, pasien[0]);
    await masuk(janjiId, pasien[1]);
    jest.setSystemTime(new Date(akhirSlot.getTime() + 1000));
    const call = await queue('panggil').expect(200);
    expect((call.body as { tiketId: string }).tiketId).toBe(janjiId);
    await queue(`${janjiId}/mulai-pelayanan`).expect(200);
    await queue(`${janjiId}/selesaikan-pelayanan`).expect(200);
    expect(
      ((await queue('panggil').expect(200)).body as { tiketId: string })
        .tiketId,
    ).toBe(walkId);
  });

  it.each(['ruang', 'dokter', 'relasi', 'slot', 'tanggal', 'sesi'] as const)(
    'CHECK_IN menolak konteks %s yang berubah setelah booking dan tidak mengonsumsi QR',
    async (kasus) => {
      const id = ((await booking(pasien[0]).expect(201)).body as Janji).tiket
        .id;
      let payload = await qr(id, pasien[0]);
      let ruang = ruangId;
      let peminta = petugas;
      if (kasus === 'ruang') {
        ruang = ruangLainId;
        peminta = petugasLain;
      }
      if (kasus === 'dokter')
        await db().dokter.update({
          where: { id: dokterId },
          data: { aktif: false },
        });
      if (kasus === 'relasi')
        await db().dokterLayanan.update({
          where: { id: relasiId },
          data: { aktif: false },
        });
      if (kasus === 'slot')
        await db().slotPraktik.update({
          where: { id: slotId },
          data: { aktif: false },
        });
      if (kasus === 'tanggal')
        await db().jadwalPraktik.update({
          where: { id: sesiId },
          data: {
            tanggal: new Date(tanggalDb.getTime() + 86_400_000),
          },
        });
      if (kasus === 'sesi') {
        jest.setSystemTime(new Date(akhirSesi.getTime() + 1000));
        payload = await qr(id, pasien[0]);
      }
      await request(server())
        .post('/api/v1/check-in')
        .set(auth(peminta))
        .send({ qrPayload: payload, loketId: ruang })
        .expect(kasus === 'ruang' ? 403 : 400);
      const tiket = await db().tiketAntrean.findUniqueOrThrow({
        where: { id },
      });
      expect(tiket.status).toBe(StatusTiket.DIPESAN);
      expect(tiket.tokenQrHash).not.toBeNull();
    },
  );

  it.each(['ruang', 'dokter', 'slot', 'tanggal', 'sesi'] as const)(
    'ENQUEUE menolak konteks %s yang berubah setelah CHECK_IN tanpa counter/audit',
    async (kasus) => {
      const id = ((await booking(pasien[0]).expect(201)).body as Janji).tiket
        .id;
      const payload = await qr(id, pasien[0]);
      await request(server())
        .post('/api/v1/check-in')
        .set(auth(petugas))
        .send({ qrPayload: payload, loketId: ruangId })
        .expect(200);
      if (kasus === 'dokter')
        await db().dokter.update({
          where: { id: dokterId },
          data: { aktif: false },
        });
      if (kasus === 'slot')
        await db().slotPraktik.update({
          where: { id: slotId },
          data: { aktif: false },
        });
      if (kasus === 'tanggal')
        await db().jadwalPraktik.update({
          where: { id: sesiId },
          data: { tanggal: new Date(tanggalDb.getTime() + 86_400_000) },
        });
      if (kasus === 'sesi')
        jest.setSystemTime(new Date(akhirSesi.getTime() + 1000));
      await queue(
        `${id}/masuk`,
        kasus === 'ruang' ? petugasLain : petugas,
        kasus === 'ruang' ? ruangLainId : ruangId,
      ).expect(kasus === 'ruang' ? 403 : 409);
      const tiket = await db().tiketAntrean.findUniqueOrThrow({
        where: { id },
      });
      expect(tiket.status).toBe(StatusTiket.CHECK_IN);
      expect(tiket.urutanMasukAntrean).toBeNull();
      expect(
        await db().peristiwaAntrean.count({
          where: { tiketAntreanId: id, tipe: 'ENQUEUE' },
        }),
      ).toBe(0);
    },
  );

  it('HOSP-OPS-01: MENUNGGU setelah akhir sesi tetap tercatat beserta alasan, tanpa tindakan otomatis', async () => {
    const id = ((await booking(pasien[0]).expect(201)).body as Janji).tiket.id;
    await masuk(id, pasien[0]);
    const sebelum = await db().tiketAntrean.findUniqueOrThrow({
      where: { id },
    });
    const jumlahAudit = await db().peristiwaAntrean.count({
      where: { tiketAntreanId: id },
    });
    jest.setSystemTime(new Date(akhirSesi.getTime() + 1000));
    const daftar = await request(server())
      .get('/api/v1/queue/menunggu')
      .set(auth(petugas))
      .query({ loketId: ruangId, hanyaTidakLayak: true })
      .expect(200);
    expect((daftar.body as Waiting)[0]).toMatchObject({
      tiketId: id,
      status: 'MENUNGGU',
      layakDipanggil: false,
      alasanTidakLayak: 'SESI_BERAKHIR',
    });
    await queue('panggil').expect(404);
    await queue('panggil', petugasLain, ruangLainId).expect(404);
    const snapshot = await request(server())
      .get('/api/v1/queue/snapshot')
      .set(auth(petugas))
      .query({ loketId: ruangId })
      .expect(200);
    expect(
      (snapshot.body as { menunggu: { tiket: Waiting } }).menunggu.tiket[0],
    ).toMatchObject({
      tiketId: id,
      status: 'MENUNGGU',
      layakDipanggil: false,
      alasanTidakLayak: 'SESI_BERAKHIR',
    });
    for (const nilai of ['yes', '1', 'TRUE', '']) {
      await request(server())
        .get('/api/v1/queue/menunggu')
        .set(auth(petugas))
        .query({ loketId: ruangId, hanyaTidakLayak: nilai })
        .expect(400);
    }
    expect(
      await db().tiketAntrean.findUniqueOrThrow({ where: { id } }),
    ).toEqual(sebelum);
    expect(
      await db().peristiwaAntrean.count({ where: { tiketAntreanId: id } }),
    ).toBe(jumlahAudit);
    await request(server())
      .get('/api/v1/queue/menunggu')
      .set(auth(pasien[0]))
      .query({ loketId: ruangId, hanyaTidakLayak: true })
      .expect(403);
  });

  it.each(['DIPANGGIL', 'DILAYANI'] as const)(
    '%s sebelum akhir sesi tetap dapat menyelesaikan pelayanan',
    async (status) => {
      const id = ((await booking(pasien[0]).expect(201)).body as Janji).tiket
        .id;
      await masuk(id, pasien[0]);
      jest.setSystemTime(mulaiSlot);
      await queue('panggil').expect(200);
      if (status === 'DILAYANI')
        await queue(`${id}/mulai-pelayanan`).expect(200);
      jest.setSystemTime(new Date(akhirSesi.getTime() + 1000));
      if (status === 'DIPANGGIL')
        await queue(`${id}/mulai-pelayanan`).expect(200);
      expect(
        (
          (await queue(`${id}/selesaikan-pelayanan`).expect(200)).body as {
            status: string;
          }
        ).status,
      ).toBe('SELESAI');
    },
  );

  it.each([ModeReservasi.JANJI_TEMU_DOKTER, ModeReservasi.HIBRIDA])(
    'kapasitas harian mode %s membatasi booking dan menandai slot belum penuh tidak tersedia',
    async (mode) => {
      await db().layanan.update({
        where: { id: layananId },
        data: { modeReservasi: mode },
      });
      await db().jadwalLayanan.updateMany({
        where: { layananId },
        data: { kapasitasHarian: 2 },
      });
      await booking(pasien[0]).expect(201);
      await booking(pasien[1]).expect(201);
      await booking(pasien[2]).expect(409);
      const slot = await request(server())
        .get(`/api/v1/slot-praktik/${slotId}`)
        .set(auth(pasien[2]))
        .expect(200);
      expect(slot.body).toMatchObject({ sisaKapasitas: 3, tersedia: false });
    },
  );

  it('20 booking paralel untuk kapasitas satu hanya membuat satu tiket/appointment/audit', async () => {
    await db().slotPraktik.update({
      where: { id: slotId },
      data: { kapasitas: 1 },
    });
    const hasil = await Promise.all(
      Array.from({ length: 20 }, (_, i) => booking(pasien[i % pasien.length])),
    );
    expect(hasil.filter((res) => res.status === 201)).toHaveLength(1);
    expect(hasil.filter((res) => res.status === 409)).toHaveLength(19);
    expect(await db().tiketAntrean.count({ where: { layananId } })).toBe(1);
    expect(
      await db().janjiTemu.count({ where: { slotPraktikId: slotId } }),
    ).toBe(1);
    expect(
      await db().peristiwaAntrean.count({
        where: { tiketAntrean: { layananId }, tipe: 'APPOINTMENT_BOOK' },
      }),
    ).toBe(1);
  });

  it('dua CALL paralel tetap hanya menghasilkan satu tiket aktif', async () => {
    const janji = ((await booking(pasien[0]).expect(201)).body as Janji).tiket
      .id;
    const walk = ((await walkIn(pasien[1]).expect(201)).body as { id: string })
      .id;
    await masuk(janji, pasien[0]);
    await masuk(walk, pasien[1]);
    jest.setSystemTime(mulaiSlot);
    const hasil = await Promise.all([queue('panggil'), queue('panggil')]);
    expect(hasil.map((r) => r.status).sort((a, b) => a - b)).toEqual([
      200, 409,
    ]);
    expect(
      await db().tiketAntrean.count({
        where: { layananId, status: StatusTiket.DIPANGGIL },
      }),
    ).toBe(1);
  });
});
