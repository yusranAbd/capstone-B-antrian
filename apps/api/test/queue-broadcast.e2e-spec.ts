import { randomBytes, randomUUID } from 'node:crypto';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';

import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { ThrottlerStorage } from '@nestjs/throttler';
import { io } from 'socket.io-client';
import type { Socket as ClientSocket } from 'socket.io-client';
import request from 'supertest';

import { AppModule } from '../src/app.module';
import { configureApp } from '../src/configure-app';
import {
  HariLayanan,
  PeranPengguna,
  StatusTiket,
} from '../src/generated/prisma/client';
import { PrismaService } from '../src/prisma/prisma.service';
import type {
  JenisPerubahanAntrean,
  QueueUpdatedEvent,
} from '../src/realtime/realtime-events.types';

interface AkunE2e {
  id: string;
  email: string;
  token: string;
}

interface ResponsRegister {
  id: string;
}

interface ResponsLogin {
  accessToken: string;
}

const SEMUA_HARI: HariLayanan[] = [
  HariLayanan.MINGGU,
  HariLayanan.SENIN,
  HariLayanan.SELASA,
  HariLayanan.RABU,
  HariLayanan.KAMIS,
  HariLayanan.JUMAT,
  HariLayanan.SABTU,
];

function tanggalLayanan(): Date {
  const zonaWaktu = process.env.SERVICE_TIME_ZONE ?? 'Asia/Jakarta';
  const bagian = new Intl.DateTimeFormat('en-GB', {
    timeZone: zonaWaktu,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date());
  const ambil = (jenis: string) =>
    bagian.find((item) => item.type === jenis)?.value ?? '';
  const tanggal = `${ambil('year')}-${ambil('month')}-${ambil('day')}`;
  return new Date(`${tanggal}T00:00:00.000Z`);
}

async function jeda(milidetik: number): Promise<void> {
  await new Promise<void>((resolve) => setTimeout(resolve, milidetik));
}

/** HTTP + Socket.IO + PostgreSQL asli; sengaja hanya untuk database E2E lokal. */
describe('Queue Broadcast melalui HTTP dan Socket.IO (e2e)', () => {
  const unik = randomUUID().replace(/-/g, '').slice(0, 8).toUpperCase();
  const kataSandi = 'RahasiaRealtimeE2E123!';
  const penggunaIds: string[] = [];
  const koneksi: ClientSocket[] = [];
  const eventMasuk: QueueUpdatedEvent[] = [];

  let app: INestApplication | undefined;
  let prisma: PrismaService | undefined;
  let alamatSocket = '';
  let akunPemilik!: AkunE2e;
  let petugasA!: AkunE2e;
  let petugasB!: AkunE2e;
  let layananId = '';
  let layananLainId = '';
  let loketId = '';
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

  function wajibDatabaseTesting(): void {
    const databaseUrl = process.env.DATABASE_URL;
    if (!databaseUrl) throw new Error('DATABASE_URL testing wajib ditentukan');
    const url = new URL(databaseUrl);
    if (
      url.pathname !== '/capstone_antrean_test' ||
      !['localhost', '127.0.0.1'].includes(url.hostname) ||
      url.port !== '5433'
    ) {
      throw new Error('Broadcast E2E hanya boleh memakai capstone_antrean_test lokal port 5433');
    }
    // Penugasan room saat ini memakai Asia/Jakarta, sama dengan default QueueService.
    if ((process.env.SERVICE_TIME_ZONE ?? 'Asia/Jakarta') !== 'Asia/Jakarta') {
      throw new Error('E2E ini memerlukan SERVICE_TIME_ZONE=Asia/Jakarta');
    }
  }

  async function buatAkun(nama: string, peran: PeranPengguna): Promise<AkunE2e> {
    const email = `broadcast-${randomUUID()}@test.local`;
    const registrasi = await request(server())
      .post('/api/v1/auth/register')
      .send({ nama, email, kataSandi })
      .expect(201);
    const id = (registrasi.body as ResponsRegister).id;
    penggunaIds.push(id);

    if (peran !== PeranPengguna.USER) {
      await db().pengguna.update({ where: { id }, data: { peran } });
    }
    const login = await request(server())
      .post('/api/v1/auth/login')
      .send({ email, kataSandi, namaPerangkat: 'Jest Broadcast E2E' })
      .expect(200);

    return { id, email, token: (login.body as ResponsLogin).accessToken };
  }

  async function socketPetugas(token: string): Promise<ClientSocket> {
    const client = io(alamatSocket, {
      autoConnect: false,
      reconnection: false,
      transports: ['websocket'],
      timeout: 5000,
      auth: { token },
    });
    koneksi.push(client);

    const status = await new Promise<string>((resolve) => {
      client.once('connect', () => resolve('connected'));
      client.once('connect_error', (error: Error) => resolve(error.message));
      client.connect();
    });
    expect(status).toBe('connected');
    return client;
  }

  async function gabungRoom(client: ClientSocket, id: string): Promise<unknown> {
    const hasil: unknown = await client.timeout(5000).emitWithAck(
      'queue:join',
      { layananId: id },
    );
    return hasil;
  }

  async function sambungkanKeRoom(token: string = petugasA.token): Promise<ClientSocket> {
    const client = await socketPetugas(token);
    const balasan = await gabungRoom(client, layananId);
    expect(balasan).toEqual({ ok: true, layananId });
    client.on('queue:updated', (payload: QueueUpdatedEvent) => {
      eventMasuk.push(payload);
    });
    return client;
  }

  async function tungguJumlahEvent(jumlah: number): Promise<void> {
    const batas = Date.now() + 5000;
    while (eventMasuk.length < jumlah && Date.now() < batas) {
      await jeda(20);
    }
    expect(eventMasuk).toHaveLength(jumlah);
  }

  async function postAntrean(
    aksi: 'ENQUEUE' | 'CALL' | 'RECALL' | 'SKIP' | 'REQUEUE' | 'START' | 'COMPLETE',
    token: string = petugasA.token,
  ) {
    const rute: Record<typeof aksi, string> = {
      ENQUEUE: `/api/v1/queue/${tiketId}/masuk`,
      CALL: '/api/v1/queue/panggil',
      RECALL: `/api/v1/queue/${tiketId}/panggil-ulang`,
      SKIP: `/api/v1/queue/${tiketId}/lewati`,
      REQUEUE: `/api/v1/queue/${tiketId}/antre-ulang`,
      START: `/api/v1/queue/${tiketId}/mulai-pelayanan`,
      COMPLETE: `/api/v1/queue/${tiketId}/selesaikan-pelayanan`,
    };
    return request(server())
      .post(rute[aksi])
      .set('Authorization', `Bearer ${token}`)
      .send({ loketId });
  }

  beforeAll(async () => {
    wajibDatabaseTesting();
    tanggalDb = tanggalLayanan();

    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(ThrottlerStorage)
      .useValue({
        increment: () => Promise.resolve({
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
    const port = (server().address() as AddressInfo).port;
    alamatSocket = `http://127.0.0.1:${port}/queue`;
    prisma = app.get(PrismaService);

    const namaDatabase = await db().$queryRaw<Array<{ nama: string }>>`
      SELECT current_database() AS "nama"`;
    expect(namaDatabase[0]?.nama).toBe('capstone_antrean_test');

    akunPemilik = await buatAkun('Pemilik Tiket Broadcast', PeranPengguna.USER);
    petugasA = await buatAkun('Petugas Broadcast A', PeranPengguna.PETUGAS);
    petugasB = await buatAkun('Petugas Broadcast B', PeranPengguna.PETUGAS);

    const layanan = await db().layanan.create({
      data: {
        kode: `RT${unik}`,
        nama: 'Layanan Broadcast E2E',
        prefixAntrean: 'R',
        durasiDasarMenit: 10,
        aktif: true,
      },
    });
    layananId = layanan.id;

    const layananLain = await db().layanan.create({
      data: {
        kode: `NO${unik}`,
        nama: 'Layanan Tanpa Penugasan E2E',
        prefixAntrean: 'N',
        durasiDasarMenit: 10,
        aktif: true,
      },
    });
    layananLainId = layananLain.id;

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
      data: {
        layananId,
        kode: `LT${unik}`,
        nama: 'Loket Broadcast E2E',
        aktif: true,
      },
    });
    loketId = loket.id;

    await db().penugasanPetugas.createMany({
      data: [petugasA, petugasB].map((petugas) => ({
        petugasId: petugas.id,
        loketId,
        tanggalMulai: new Date(tanggalDb.getTime() - 86400000),
        tanggalSelesai: new Date(tanggalDb.getTime() + 86400000),
        aktif: true,
      })),
    });
  }, 120000);

  beforeEach(async () => {
    eventMasuk.length = 0;
    const counter = await db().urutanAntreanHarian.upsert({
      where: { layananId_tanggal: { layananId, tanggal: tanggalDb } },
      create: { layananId, tanggal: tanggalDb, nomorTerakhir: 1 },
      update: { nomorTerakhir: { increment: 1 } },
    });
    const tiket = await db().tiketAntrean.create({
      data: {
        penggunaId: akunPemilik.id,
        layananId,
        loketId,
        tanggalAntrean: tanggalDb,
        nomorUrut: counter.nomorTerakhir,
        kodeTiket: `TK${randomBytes(12).toString('hex').toUpperCase()}`,
        status: StatusTiket.CHECK_IN,
        checkInPada: new Date(),
      },
    });
    tiketId = tiket.id;
  }, 30000);

  afterEach(async () => {
    for (const client of koneksi) {
      client.removeAllListeners();
      client.disconnect();
    }
    koneksi.length = 0;
    eventMasuk.length = 0;

    // Kembalikan penugasan jika suatu tes mematikannya.
    if (prisma && petugasA && loketId) {
      await db().penugasanPetugas.updateMany({
        where: { petugasId: petugasA.id, loketId },
        data: { aktif: true },
      });
    }
    if (prisma && tiketId) {
      await db().peristiwaAntrean.deleteMany({ where: { tiketAntreanId: tiketId } });
      await db().tiketAntrean.deleteMany({ where: { id: tiketId } });
      tiketId = '';
    }
  }, 30000);

  afterAll(async () => {
    try {
      if (prisma) {
        if (layananId) {
          const tiketTersisa = await db().tiketAntrean.findMany({
            where: { layananId }, select: { id: true },
          });
          const tiketIds = tiketTersisa.map((item) => item.id);
          if (tiketIds.length) {
            await db().peristiwaAntrean.deleteMany({
              where: { tiketAntreanId: { in: tiketIds } },
            });
          }
          await db().tiketAntrean.deleteMany({ where: { layananId } });
          await db().urutanAntreanHarian.deleteMany({ where: { layananId } });
          await db().penugasanPetugas.deleteMany({ where: { loketId } });
          await db().jadwalLayanan.deleteMany({ where: { layananId } });
          await db().loket.deleteMany({ where: { layananId } });
          await db().layanan.deleteMany({ where: { id: layananId } });
        }
        if (layananLainId) {
          await db().layanan.deleteMany({ where: { id: layananLainId } });
        }
        if (penggunaIds.length) {
          await db().sesiPengguna.deleteMany({
            where: { penggunaId: { in: penggunaIds } },
          });
          await db().pengguna.deleteMany({ where: { id: { in: penggunaIds } } });
        }
      }
    } finally {
      if (app) await app.close();
    }
  }, 60000);

  it('CALL sukses mengirim queue:updated ke klien pada room yang benar', async () => {
    expect((await postAntrean('ENQUEUE')).status).toBe(200);
    await sambungkanKeRoom();
    const respons = await postAntrean('CALL');
    expect(respons.status).toBe(200);
    await tungguJumlahEvent(1);
    expect(eventMasuk[0]).toMatchObject({
      versiSkema: 1,
      aksi: 'CALL',
      layananId,
      tiketId,
      status: StatusTiket.DIPANGGIL,
      loketId,
    });
    expect(eventMasuk[0]?.eventId).toMatch(/^[0-9a-f-]{36}$/i);
    expect(new Date(eventMasuk[0].terjadiPada).getTime()).not.toBeNaN();
    const serial = JSON.stringify(eventMasuk[0]);
    expect(serial).not.toContain(akunPemilik.email);
    expect(serial).not.toContain(petugasA.token);
  }, 30000);

  it('mengirim ENQUEUE, CALL, RECALL, SKIP, REQUEUE, START, COMPLETE via jaringan', async () => {
    await sambungkanKeRoom();
    const urutan: JenisPerubahanAntrean[] = [
      'ENQUEUE', 'CALL', 'RECALL', 'SKIP',
      'REQUEUE', 'CALL', 'START', 'COMPLETE',
    ];
    for (const [indeks, aksi] of urutan.entries()) {
      const respons = await postAntrean(aksi);
      expect(respons.status).toBe(200);
      await tungguJumlahEvent(indeks + 1);
      expect(eventMasuk[indeks]).toMatchObject({ aksi, layananId, tiketId });
    }
    const idUnik = new Set(eventMasuk.map((event) => event.eventId));
    expect(idUnik.size).toBe(urutan.length);
    expect(eventMasuk[urutan.length - 1]?.status).toBe(StatusTiket.SELESAI);
    const tiket = await db().tiketAntrean.findUniqueOrThrow({ where: { id: tiketId } });
    expect(tiket.status).toBe(StatusTiket.SELESAI);
  }, 60000);

  it('rollback CALL karena audit gagal tidak mengirim event', async () => {
    expect((await postAntrean('ENQUEUE')).status).toBe(200);
    await sambungkanKeRoom();
    const sebelum = await db().tiketAntrean.findUniqueOrThrow({ where: { id: tiketId } });
    // Proteksi DDL: hostname, nama DB, port, current_database, dan UUID diverifikasi.
    wajibDatabaseTesting();
    const namaDatabase = await db().$queryRaw<Array<{ nama: string }>>`
      SELECT current_database() AS "nama"`;
    expect(namaDatabase[0]?.nama).toBe('capstone_antrean_test');
    expect(tiketId).toMatch(/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i);
    const namaConstraint = `e2e_broadcast_rollback_${randomBytes(6).toString('hex')}`;
    let terpasang = false;
    try {
      await db().$executeRawUnsafe(
        `ALTER TABLE "public"."peristiwa_antrean"
         ADD CONSTRAINT "${namaConstraint}"
         CHECK (NOT (
           "tiket_antrean_id" = '${tiketId}'::uuid AND "tipe" = 'CALL'
         ))`,
      );
      terpasang = true;
      const respons = await postAntrean('CALL');
      expect(respons.status).toBe(500);
      await jeda(350);
      expect(eventMasuk).toHaveLength(0);
    } finally {
      if (terpasang) {
        await db().$executeRawUnsafe(
          `ALTER TABLE "public"."peristiwa_antrean"
           DROP CONSTRAINT IF EXISTS "${namaConstraint}"`,
        );
      }
    }
    const sesudah = await db().tiketAntrean.findUniqueOrThrow({ where: { id: tiketId } });
    expect(sesudah.status).toBe(StatusTiket.MENUNGGU);
    expect(sesudah.versi).toBe(sebelum.versi);
    expect(await db().peristiwaAntrean.count({
      where: { tiketAntreanId: tiketId, tipe: 'CALL' },
    })).toBe(0);
  }, 60000);

  it('room layanan tanpa penugasan ditolak dan tidak menerima event', async () => {
    const client = await socketPetugas(petugasA.token);
    expect(await gabungRoom(client, layananLainId))
      .toEqual({ ok: false, kode: 'FORBIDDEN' });
    client.on('queue:updated', (payload: QueueUpdatedEvent) => {
      eventMasuk.push(payload);
    });
    const respons = await postAntrean('ENQUEUE');
    expect(respons.status).toBe(200);
    await jeda(350);
    expect(eventMasuk).toHaveLength(0);
  }, 30000);

  it('penugasan dicabut setelah join: broadcast ditahan dan room dilepas', async () => {
    const client = await sambungkanKeRoom();
    await db().penugasanPetugas.updateMany({
      where: { petugasId: petugasA.id, loketId },
      data: { aktif: false },
    });
    // Petugas B tetap aktif agar perubahan antrean sah.
    const respons = await postAntrean('ENQUEUE', petugasB.token);
    expect(respons.status).toBe(200);
    await jeda(350);
    expect(eventMasuk).toHaveLength(0);
    // Join baru sesudah pencabutan masih harus ditolak.
    expect(await gabungRoom(client, layananId))
      .toEqual({ ok: false, kode: 'FORBIDDEN' });
  }, 30000);

  it('sesi dicabut setelah join: event ditahan dan socket diputus', async () => {
    const client = await sambungkanKeRoom();
    const sesi = await db().sesiPengguna.findFirstOrThrow({
      where: {
        penggunaId: petugasA.id,
        dicabutPada: null,
      },
      orderBy: { dibuatPada: 'desc' },
      select: { id: true },
    });
    await db().sesiPengguna.update({
      where: { id: sesi.id },
      data: { dicabutPada: new Date() },
    });
    const respons = await postAntrean('ENQUEUE', petugasB.token);
    expect(respons.status).toBe(200);
    const batas = Date.now() + 3000;
    while (client.connected && Date.now() < batas) await jeda(20);
    expect(client.connected).toBe(false);
    expect(eventMasuk).toHaveLength(0);
  }, 30000);
});
