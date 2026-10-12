import { randomBytes, randomUUID } from 'node:crypto';
import type { Server } from 'node:http';

import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { ThrottlerStorage } from '@nestjs/throttler';
import request from 'supertest';

import { AppModule } from '../src/app.module';
import { configureApp } from '../src/configure-app';
import {
  HariLayanan,
  PeranPengguna,
  StatusTiket,
} from '../src/generated/prisma/client';
import { PrismaService } from '../src/prisma/prisma.service';
import type { SnapshotAntrean } from '../src/queue/queue-snapshot.types';

interface AkunTesting {
  id: string;
  token: string;
}

const SEMUA_HARI: HariLayanan[] = [
  HariLayanan.SENIN,
  HariLayanan.SELASA,
  HariLayanan.RABU,
  HariLayanan.KAMIS,
  HariLayanan.JUMAT,
  HariLayanan.SABTU,
  HariLayanan.MINGGU,
];

describe('Queue REST Snapshot (e2e)', () => {
  const unik = randomUUID().replace(/-/g, '').slice(0, 8).toUpperCase();
  const kataSandi = 'RahasiaSnapshotE2E123!';
  const idPengguna: string[] = [];
  let app: INestApplication | undefined;
  let prisma: PrismaService | undefined;
  let petugas!: AkunTesting;
  let pemilik!: AkunTesting;
  let layananId = '';
  let loketId = '';
  let loketLainId = '';
  let tiketId = '';
  let tanggalDb: Date;

  function db(): PrismaService {
    if (!prisma) throw new Error('Prisma testing belum tersedia');
    return prisma;
  }

  function server(): Server {
    if (!app) throw new Error('NestJS testing belum tersedia');
    return app.getHttpServer() as Server;
  }

  function wajibDatabaseLokal(): void {
    const databaseUrl = process.env.DATABASE_URL;
    if (!databaseUrl) throw new Error('DATABASE_URL wajib diatur');
    const url = new URL(databaseUrl);
    if (
      url.pathname !== '/capstone_antrean_test' ||
      !['localhost', '127.0.0.1'].includes(url.hostname) ||
      url.port !== '5433'
    ) {
      throw new Error('Snapshot E2E hanya boleh memakai capstone_antrean_test lokal port 5433');
    }
    if ((process.env.SERVICE_TIME_ZONE ?? 'Asia/Jakarta') !== 'Asia/Jakarta') {
      throw new Error('Snapshot E2E memakai SERVICE_TIME_ZONE=Asia/Jakarta');
    }
  }

  function tanggalPelayanan(): Date {
    const bagian = new Intl.DateTimeFormat('en-GB', {
      timeZone: 'Asia/Jakarta',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).formatToParts(new Date());
    const ambil = (jenis: string): string =>
      bagian.find((item) => item.type === jenis)?.value ?? '';
    return new Date(
      `${ambil('year')}-${ambil('month')}-${ambil('day')}T00:00:00.000Z`,
    );
  }

  async function buatAkun(nama: string, peran: PeranPengguna): Promise<AkunTesting> {
    const email = `snapshot-${randomUUID()}@test.local`;
    const registrasi = await request(server())
      .post('/api/v1/auth/register')
      .send({ nama, email, kataSandi })
      .expect(201);
    const id = (registrasi.body as { id: string }).id;
    idPengguna.push(id);
    if (peran !== PeranPengguna.USER) {
      await db().pengguna.update({ where: { id }, data: { peran } });
    }
    const login = await request(server())
      .post('/api/v1/auth/login')
      .send({ email, kataSandi, namaPerangkat: 'Jest Snapshot E2E' })
      .expect(200);
    return {
      id,
      token: (login.body as { accessToken: string }).accessToken,
    };
  }

  function getSnapshot(token: string, idLoket: string) {
    return request(server())
      .get('/api/v1/queue/snapshot')
      .query({ loketId: idLoket })
      .set('Authorization', `Bearer ${token}`);
  }

  beforeAll(async () => {
    wajibDatabaseLokal();
    tanggalDb = tanggalPelayanan();
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
    await app.listen(0, '127.0.0.1');
    prisma = app.get(PrismaService);

    const hasil = await db().$queryRaw<Array<{ nama: string }>>`
      SELECT current_database() AS "nama"`;
    expect(hasil[0]?.nama).toBe('capstone_antrean_test');

    pemilik = await buatAkun('Pemilik Tiket Snapshot', PeranPengguna.USER);
    petugas = await buatAkun('Petugas Snapshot', PeranPengguna.PETUGAS);

    const layanan = await db().layanan.create({
      data: {
        kode: `SS${unik}`,
        nama: 'Layanan Snapshot E2E',
        prefixAntrean: 'S',
        durasiDasarMenit: 10,
        aktif: true,
      },
    });
    layananId = layanan.id;
    await db().jadwalLayanan.createMany({
      data: SEMUA_HARI.map((hari) => ({
        layananId,
        hari,
        jamBuka: new Date('1970-01-01T00:00:00.000Z'),
        jamTutup: new Date('1970-01-01T23:59:59.000Z'),
        kapasitasHarian: 1000,
        aktif: true,
      })),
    });
    const loket = await db().loket.create({
      data: { layananId, kode: 'LS-1', nama: 'Loket Snapshot Satu', aktif: true },
    });
    loketId = loket.id;
    const loketLain = await db().loket.create({
      data: { layananId, kode: 'LS-2', nama: 'Loket Snapshot Dua', aktif: true },
    });
    loketLainId = loketLain.id;
    await db().penugasanPetugas.create({
      data: {
        petugasId: petugas.id,
        loketId,
        tanggalMulai: new Date(tanggalDb.getTime() - 86400000),
        tanggalSelesai: new Date(tanggalDb.getTime() + 86400000),
        aktif: true,
      },
    });
  }, 120000);

  beforeEach(async () => {
    const counter = await db().urutanAntreanHarian.upsert({
      where: { layananId_tanggal: { layananId, tanggal: tanggalDb } },
      create: {
        layananId,
        tanggal: tanggalDb,
        nomorTerakhir: 1,
        urutanMasukTerakhir: 1,
      },
      update: {
        nomorTerakhir: { increment: 1 },
        urutanMasukTerakhir: { increment: 1 },
      },
    });
    const tiket = await db().tiketAntrean.create({
      data: {
        penggunaId: pemilik.id,
        layananId,
        tanggalAntrean: tanggalDb,
        nomorUrut: counter.nomorTerakhir,
        urutanMasukAntrean: counter.urutanMasukTerakhir,
        masukAntreanPada: new Date(),
        kodeTiket: `TK${randomBytes(12).toString('hex').toUpperCase()}`,
        status: StatusTiket.MENUNGGU,
        checkInPada: new Date(),
      },
    });
    tiketId = tiket.id;
  }, 30000);

  afterEach(async () => {
    if (prisma && tiketId) {
      await db().peristiwaAntrean.deleteMany({ where: { tiketAntreanId: tiketId } });
      await db().tiketAntrean.deleteMany({ where: { id: tiketId } });
      tiketId = '';
    }
    if (prisma && petugas?.id && loketId) {
      await db().penugasanPetugas.updateMany({
        where: { petugasId: petugas.id, loketId },
        data: { aktif: true },
      });
    }
  }, 30000);

  afterAll(async () => {
    try {
      if (prisma) {
        if (layananId) {
          const tiket = await db().tiketAntrean.findMany({
            where: { layananId }, select: { id: true },
          });
          const ids = tiket.map((t) => t.id);
          if (ids.length) {
            await db().peristiwaAntrean.deleteMany({
              where: { tiketAntreanId: { in: ids } },
            });
          }
          await db().tiketAntrean.deleteMany({ where: { layananId } });
          await db().urutanAntreanHarian.deleteMany({ where: { layananId } });
          if (loketId) {
            await db().penugasanPetugas.deleteMany({ where: { loketId } });
          }
          await db().jadwalLayanan.deleteMany({ where: { layananId } });
          await db().loket.deleteMany({ where: { layananId } });
          await db().layanan.deleteMany({ where: { id: layananId } });
        }
        if (idPengguna.length) {
          await db().sesiPengguna.deleteMany({
            where: { penggunaId: { in: idPengguna } },
          });
          await db().pengguna.deleteMany({
            where: { id: { in: idPengguna } },
          });
        }
      }
    } finally {
      if (app) await app.close();
    }
  }, 60000);

  it('GET snapshot memperlihatkan FIFO dan semua loket, tanpa informasi pribadi', async () => {
    const res = await getSnapshot(petugas.token, loketId).expect(200);
    const body = res.body as SnapshotAntrean;
    expect(body.versiSkema).toBe(1);
    expect(body.layanan.id).toBe(layananId);
    expect(body.loketPeminta.id).toBe(loketId);
    expect(body.menunggu.total).toBe(1);
    expect(body.menunggu.tiket).toHaveLength(1);
    expect(body.menunggu.tiket[0]).toMatchObject({
      tiketId,
      status: StatusTiket.MENUNGGU,
    });
    expect(body.loket.map((item) => item.id)).toEqual([loketId, loketLainId]);
    expect(body.loket.every((item) => item.tiketAktif.length === 0)).toBe(true);
    expect(JSON.stringify(body)).not.toContain(petugas.token);
    expect(JSON.stringify(body)).not.toContain('kataSandiHash');
  });

  it('sesudah CALL commit snapshot berpindah dari MENUNGGU menjadi DIPANGGIL', async () => {
    const responsCall = await request(server())
      .post('/api/v1/queue/panggil')
      .set('Authorization', `Bearer ${petugas.token}`)
      .send({ loketId })
      .expect(200);
    expect((responsCall.body as { tiketId: string }).tiketId).toBe(tiketId);
    const res = await getSnapshot(petugas.token, loketId).expect(200);
    const body = res.body as SnapshotAntrean;
    expect(body.menunggu.total).toBe(0);
    expect(body.loket[0]?.tiketAktif[0]).toMatchObject({
      tiketId,
      status: StatusTiket.DIPANGGIL,
    });
  });

  it('menolak akses tanpa JWT dan pemilik tiket berperan USER', async () => {
    await request(server())
      .get('/api/v1/queue/snapshot')
      .query({ loketId })
      .expect(401);
    await getSnapshot(pemilik.token, loketId).expect(403);
  });

  it('menolak loket lain atau penugasan yang telah dicabut', async () => {
    await getSnapshot(petugas.token, loketLainId).expect(403);
    await db().penugasanPetugas.updateMany({
      where: { petugasId: petugas.id, loketId },
      data: { aktif: false },
    });
    await getSnapshot(petugas.token, loketId).expect(403);
  });
});
