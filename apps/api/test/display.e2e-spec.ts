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
});
