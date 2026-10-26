import { createHash, randomBytes, randomUUID } from 'node:crypto';
import type { Server } from 'node:http';

import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { ThrottlerStorage } from '@nestjs/throttler';
import request from 'supertest';

import { AppModule } from '../src/app.module';
import { configureApp } from '../src/configure-app';
import { StatusTiket } from '../src/generated/prisma/client';
import { PrismaService } from '../src/prisma/prisma.service';
import type { DisplaySnapshot } from '../src/display/display-snapshot.types';

describe('Public Display Snapshot (e2e)', () => {
  const unik = randomUUID().replace(/-/g, '').slice(0, 8).toUpperCase();
  const token = randomBytes(32).toString('hex');
  const tokenHash = createHash('sha256').update(token).digest('hex');
  let app: INestApplication | undefined;
  let prisma: PrismaService | undefined;
  let penggunaId = '';
  let layananId = '';
  let loketId = '';
  let perangkatId = '';
  let tiketId = '';
  let auditId = '';

  function db(): PrismaService {
    if (!prisma) throw new Error('Prisma testing tidak tersedia');
    return prisma;
  }

  function server(): Server {
    if (!app) throw new Error('Server testing tidak tersedia');
    return app.getHttpServer() as Server;
  }

  function wajibDbTestingLokal(): void {
    const raw = process.env.DATABASE_URL;
    if (!raw) throw new Error('DATABASE_URL wajib diatur');
    const url = new URL(raw);
    if (
      url.pathname !== '/capstone_antrean_test' ||
      !['localhost', '127.0.0.1'].includes(url.hostname) ||
      url.port !== '5433'
    ) {
      throw new Error('E2E Display hanya boleh memakai capstone_antrean_test lokal port 5433');
    }
    if ((process.env.SERVICE_TIME_ZONE ?? 'Asia/Jakarta') !== 'Asia/Jakarta') {
      throw new Error('E2E Display mensyaratkan SERVICE_TIME_ZONE=Asia/Jakarta');
    }
  }

  function tanggalLayanan(): Date {
    const bagian = new Intl.DateTimeFormat('en-GB', {
      timeZone: 'Asia/Jakarta', year: 'numeric', month: '2-digit', day: '2-digit',
    }).formatToParts(new Date());
    const ambil = (jenis: string): string =>
      bagian.find((item) => item.type === jenis)?.value ?? '';
    return new Date(`${ambil('year')}-${ambil('month')}-${ambil('day')}T00:00:00.000Z`);
  }

  function bacaSnapshot(kunci: string = token, layanan: string = layananId) {
    return request(server())
      .get(`/api/v1/display/${layanan}/snapshot`)
      .set('x-display-token', kunci);
  }

  beforeAll(async () => {
    wajibDbTestingLokal();
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
    await app.listen(0, '127.0.0.1');
    prisma = app.get(PrismaService);

    const actualDb = await db().$queryRaw<Array<{ nama: string }>>`
      SELECT current_database() AS "nama"`;
    expect(actualDb[0]?.nama).toBe('capstone_antrean_test');

    const pengguna = await db().pengguna.create({
      data: {
        nama: 'Pemilik Tiket Display E2E',
        email: `display-${randomUUID()}@test.local`,
        kataSandiHash: 'hash-fixture-tidak-digunakan-untuk-login',
        peran: 'USER',
      },
    });
    penggunaId = pengguna.id;
    const layanan = await db().layanan.create({
      data: {
        kode: `PD${unik}`,
        nama: 'Layanan Display E2E',
        prefixAntrean: 'D',
        durasiDasarMenit: 10,
        aktif: true,
      },
    });
    layananId = layanan.id;
    const loket = await db().loket.create({
      data: { layananId, kode: '03', nama: 'Loket Tiga', aktif: true },
    });
    loketId = loket.id;
    const perangkat = await db().perangkatTampilan.create({
      data: { layananId, nama: 'Kiosk E2E', tokenHash, aktif: true },
    });
    perangkatId = perangkat.id;
    const tiket = await db().tiketAntrean.create({
      data: {
        penggunaId, layananId, loketId,
        tanggalAntrean: tanggalLayanan(),
        nomorUrut: 25,
        kodeTiket: `TK${randomBytes(12).toString('hex').toUpperCase()}`,
        status: StatusTiket.DIPANGGIL,
        urutanMasukAntrean: 1,
        checkInPada: new Date(),
        masukAntreanPada: new Date(),
        dipanggilPada: new Date(),
      },
    });
    tiketId = tiket.id;
    const peristiwa = await db().peristiwaAntrean.create({
      data: {
        tiketAntreanId: tiketId,
        tipe: 'CALL',
        statusSebelum: StatusTiket.MENUNGGU,
        statusSesudah: StatusTiket.DIPANGGIL,
      },
    });
    auditId = peristiwa.id;
  }, 120000);

  afterEach(async () => {
    if (!prisma || !perangkatId || !tiketId) return;
    await db().perangkatTampilan.update({
      where: { id: perangkatId }, data: { aktif: true },
    });
    await db().tiketAntrean.update({
      where: { id: tiketId }, data: { status: StatusTiket.DIPANGGIL },
    });
    await db().peristiwaAntrean.deleteMany({
      where: { tiketAntreanId: tiketId, id: { not: auditId } },
    });
  });

  afterAll(async () => {
    try {
      if (prisma) {
        if (tiketId) {
          await db().peristiwaAntrean.deleteMany({ where: { tiketAntreanId: tiketId } });
          await db().tiketAntrean.deleteMany({ where: { id: tiketId } });
        }
        if (perangkatId) await db().perangkatTampilan.deleteMany({ where: { id: perangkatId } });
        if (loketId) await db().loket.deleteMany({ where: { id: loketId } });
        if (layananId) await db().layanan.deleteMany({ where: { id: layananId } });
        if (penggunaId) await db().pengguna.deleteMany({ where: { id: penggunaId } });
      }
    } finally {
      if (app) await app.close();
    }
  }, 60000);

  it('menerima perangkat sah dan hanya mengirim data publik serta TTS CALL', async () => {
    const response = await bacaSnapshot().expect(200);
    const body = response.body as DisplaySnapshot;
    expect(response.headers['cache-control']).toBe('no-store');
    expect(body).toMatchObject({
      versiSkema: 1,
      layanan: { nama: 'Layanan Display E2E' },
      loket: [{ kode: '03', tiketAktif: [{ nomorAntrean: 'D-025', status: 'DIPANGGIL' }] }],
      pengumumanTerakhir: {
        peristiwaId: auditId,
        aksi: 'CALL',
        nomorAntrean: 'D-025',
        bahasa: 'id-ID',
      },
    });
    const serialized = JSON.stringify(body);
    expect(serialized).not.toContain(penggunaId);
    expect(serialized).not.toContain(tiketId);
    expect(serialized).not.toContain(token);
    expect(serialized).not.toContain(tokenHash);
    expect(serialized).not.toContain('kataSandiHash');
  });

  it('menolak request tanpa token dan token yang salah', async () => {
    await request(server()).get(`/api/v1/display/${layananId}/snapshot`).expect(401);
    await bacaSnapshot('b'.repeat(64)).expect(401);
  });

  it('menolak perangkat pada layanan berbeda dan perangkat yang dicabut', async () => {
    await bacaSnapshot(token, randomUUID()).expect(403);
    await db().perangkatTampilan.update({ where: { id: perangkatId }, data: { aktif: false } });
    await bacaSnapshot().expect(403);
  });

  it('membedakan pengumuman RECALL berdasarkan ID audit yang baru', async () => {
    const baru = await db().peristiwaAntrean.create({
      data: {
        tiketAntreanId: tiketId,
        tipe: 'RECALL',
        statusSebelum: StatusTiket.DIPANGGIL,
        statusSesudah: StatusTiket.DIPANGGIL,
      },
    });
    const res = await bacaSnapshot().expect(200);
    const body = res.body as DisplaySnapshot;
    expect(body.pengumumanTerakhir).toMatchObject({
      aksi: 'RECALL', peristiwaId: baru.id,
    });
  });

  it('tidak menawarkan TTS panggilan lama setelah tiket mulai DILAYANI', async () => {
    await db().tiketAntrean.update({
      where: { id: tiketId }, data: { status: StatusTiket.DILAYANI },
    });
    const res = await bacaSnapshot().expect(200);
    const body = res.body as DisplaySnapshot;
    expect(body.pengumumanTerakhir).toBeNull();
    expect(body.loket[0]?.tiketAktif[0]?.status).toBe('DILAYANI');
  });
  it('daftar menunggu tersamar dan nama panggilan tunduk kebijakan server', async () => {
    const mode = process.env.DISPLAY_PATIENT_NAME_MODE;
    const approved = process.env.DISPLAY_FULL_NAMES_APPROVED;
    try {
      delete process.env.DISPLAY_PATIENT_NAME_MODE;
      delete process.env.DISPLAY_FULL_NAMES_APPROVED;
      await db().tiketAntrean.update({ where: { id: tiketId }, data: { status: StatusTiket.MENUNGGU } });
      const waiting = (await bacaSnapshot().expect(200)).body as DisplaySnapshot;
      expect(waiting.totalMenunggu).toBe(1);
      expect(waiting.menunggu).toEqual([{ nomorAntrean: 'D-025', namaPasien: 'Pemilik T. D. E.' }]);
      expect(JSON.stringify(waiting)).not.toContain('Pemilik Tiket Display E2E');
      await db().tiketAntrean.update({ where: { id: tiketId }, data: { status: StatusTiket.DIPANGGIL } });
      process.env.DISPLAY_PATIENT_NAME_MODE = 'LENGKAP';
      expect(((await bacaSnapshot().expect(200)).body as DisplaySnapshot).modeNama).toBe('SAMAR');
      process.env.DISPLAY_FULL_NAMES_APPROVED = 'true';
      const full = (await bacaSnapshot().expect(200)).body as DisplaySnapshot;
      expect(full.loket[0].tiketAktif[0].namaPasien).toBe('Pemilik Tiket Display E2E');
      expect(full.pengumumanTerakhir?.teks).toContain('atas nama Pemilik Tiket Display E2E');
      expect(full.menunggu).toEqual([]);
      process.env.DISPLAY_PATIENT_NAME_MODE = 'TANPA_NAMA';
      const hidden = (await bacaSnapshot().expect(200)).body as DisplaySnapshot;
      expect(hidden.loket[0].tiketAktif[0].namaPasien).toBeNull();
      expect(hidden.pengumumanTerakhir?.teks).not.toContain('atas nama');
    } finally {
      if (mode === undefined) delete process.env.DISPLAY_PATIENT_NAME_MODE; else process.env.DISPLAY_PATIENT_NAME_MODE = mode;
      if (approved === undefined) delete process.env.DISPLAY_FULL_NAMES_APPROVED; else process.env.DISPLAY_FULL_NAMES_APPROVED = approved;
    }
  });

  it('tiket dibatalkan tidak masuk daftar menunggu atau pengumuman', async () => {
    await db().tiketAntrean.update({ where: { id: tiketId }, data: { status: StatusTiket.DIBATALKAN } });
    const body = (await bacaSnapshot().expect(200)).body as DisplaySnapshot;
    expect(body.totalMenunggu).toBe(0);
    expect(body.menunggu).toEqual([]);
    expect(body.antrianPasien).toEqual([]);
    expect(body.totalAntrianPasien).toBe(0);
    expect(body.pengumumanTerakhir).toBeNull();
  });

  it('SKIP tampil DILEWATI dan REQUEUE berpindah status tanpa duplikasi', async () => {
    await db().tiketAntrean.update({ where: { id: tiketId }, data: { status: StatusTiket.DILEWATI } });
    const skipped = (await bacaSnapshot().expect(200)).body as DisplaySnapshot;
    expect(skipped.totalMenunggu).toBe(0);
    expect(skipped.totalDilewati).toBe(1);
    expect(skipped.totalAntrianPasien).toBe(1);
    expect(skipped.antrianPasien).toEqual([
      { nomorAntrean: 'D-025', namaPasien: 'Pemilik T. D. E.', status: 'DILEWATI' },
    ]);
    expect(skipped.menunggu).toEqual([]);
    expect(skipped.pengumumanTerakhir).toBeNull();
    await db().tiketAntrean.update({ where: { id: tiketId }, data: { status: StatusTiket.MENUNGGU } });
    const requeued = (await bacaSnapshot().expect(200)).body as DisplaySnapshot;
    expect(requeued.totalDilewati).toBe(0);
    expect(requeued.totalAntrianPasien).toBe(1);
    expect(requeued.antrianPasien?.map((r) => r.status)).toEqual(['MENUNGGU']);
  });
  it('nama lengkap dari kebijakan server, tiket hari lain dikecualikan', async () => {
    const mode = process.env.DISPLAY_PATIENT_NAME_MODE;
    const approved = process.env.DISPLAY_FULL_NAMES_APPROVED;
    try {
      process.env.DISPLAY_PATIENT_NAME_MODE = 'LENGKAP';
      process.env.DISPLAY_FULL_NAMES_APPROVED = 'true';
      await db().tiketAntrean.update({ where: { id: tiketId }, data: { status: StatusTiket.DILEWATI } });
      const full = (await bacaSnapshot().expect(200)).body as DisplaySnapshot;
      expect(full.antrianPasien?.[0].namaPasien).toBe('Pemilik Tiket Display E2E');
      await db().tiketAntrean.update({ where: { id: tiketId }, data: { tanggalAntrean: new Date(tanggalLayanan().getTime() - 86400000) } });
      const previousDay = (await bacaSnapshot().expect(200)).body as DisplaySnapshot;
      expect(previousDay.antrianPasien).toEqual([]);
      expect(previousDay.totalAntrianPasien).toBe(0);
    } finally {
      await db().tiketAntrean.update({ where: { id: tiketId }, data: { tanggalAntrean: tanggalLayanan() } });
      if (mode === undefined) delete process.env.DISPLAY_PATIENT_NAME_MODE; else process.env.DISPLAY_PATIENT_NAME_MODE = mode;
      if (approved === undefined) delete process.env.DISPLAY_FULL_NAMES_APPROVED; else process.env.DISPLAY_FULL_NAMES_APPROVED = approved;
    }
  });
});
