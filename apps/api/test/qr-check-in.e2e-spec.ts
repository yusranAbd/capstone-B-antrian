import { createHash, randomBytes, randomUUID } from 'node:crypto';

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

// ==========================================
// TIPE DATA
// ==========================================

interface AkunUji {
  id: string;
  token: string;
}

interface RegisterResponse {
  id: string;
}

interface LoginResponse {
  accessToken: string;
  user: {
    id: string;
    peran: PeranPengguna;
  };
}

interface QrResponse {
  tiketId: string;
  qrPayload: string;
  berlakuHingga: string;
  masaBerlakuDetik: number;
  status: StatusTiket;
}

interface CheckInResponse {
  tiketId: string;
  layananId: string;
  nomorAntrean: string;
  status: StatusTiket;
  checkInPada: string;
  loketId: string;
  petugasId: string;
}

// ==========================================
// HELPER TANGGAL PELAYANAN
// ==========================================

function tanggalPelayananLokal(): string {
  const zonaWaktu = process.env.SERVICE_TIME_ZONE ?? 'Asia/Jakarta';

  const bagian = new Intl.DateTimeFormat('en-GB', {
    timeZone: zonaWaktu,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date());

  const ambil = (jenis: string) =>
    bagian.find((item) => item.type === jenis)?.value ?? '';

  return [ambil('year'), ambil('month'), ambil('day')].join('-');
}

function tanggalDb(nilai: string): Date {
  return new Date(`${nilai}T00:00:00.000Z`);
}

function geserTanggal(tanggal: Date, jumlahHari: number): Date {
  return new Date(tanggal.getTime() + jumlahHari * 24 * 60 * 60 * 1000);
}

// ==========================================
// E2E QR CHECK-IN
// ==========================================

describe('QR Check-In API (e2e)', () => {
  let app: INestApplication | undefined;
  let prisma: PrismaService | undefined;

  let admin!: AkunUji;
  let userA!: AkunUji;
  let userB!: AkunUji;
  let petugasA!: AkunUji;
  let petugasB!: AkunUji;

  let layananId = '';
  let loketId = '';
  let tiketId = '';
  let nomorUrut = 0;

  let tanggalHariIni = '';
  let hariIniDb: Date;

  const penggunaIds: string[] = [];

  const unik = randomUUID().replace(/-/g, '').slice(0, 8).toUpperCase();

  const kataSandi = 'RahasiaQrE2E123!';

  const semuaHari: HariLayanan[] = [
    HariLayanan.MINGGU,
    HariLayanan.SENIN,
    HariLayanan.SELASA,
    HariLayanan.RABU,
    HariLayanan.KAMIS,
    HariLayanan.JUMAT,
    HariLayanan.SABTU,
  ];

  function server() {
    if (!app) {
      throw new Error('Aplikasi E2E belum siap');
    }

    return app.getHttpServer();
  }

  function db(): PrismaService {
    if (!prisma) {
      throw new Error('Prisma E2E belum siap');
    }

    return prisma;
  }

  // ========================================
  // HELPER AKUN
  // ========================================

  async function buatAkun(
    nama: string,
    peran: PeranPengguna,
  ): Promise<AkunUji> {
    const email = `qr-${randomUUID()}@test.local`;

    const registrasi = await request(server())
      .post('/api/v1/auth/register')
      .send({
        nama,
        email,
        kataSandi,
      })
      .expect(201);

    const hasilRegistrasi = registrasi.body as RegisterResponse;

    penggunaIds.push(hasilRegistrasi.id);

    if (peran !== PeranPengguna.USER) {
      await db().pengguna.update({
        where: {
          id: hasilRegistrasi.id,
        },
        data: {
          peran,
        },
      });
    }

    const login = await request(server())
      .post('/api/v1/auth/login')
      .send({
        email,
        kataSandi,
        namaPerangkat: 'Jest E2E QR',
      })
      .expect(200);

    const hasilLogin = login.body as LoginResponse;

    expect(hasilLogin.user.peran).toBe(peran);

    return {
      id: hasilLogin.user.id,
      token: hasilLogin.accessToken,
    };
  }

  // ========================================
  // HELPER PENERBITAN DAN CHECK-IN
  // ========================================

  async function terbitkanQr(): Promise<QrResponse> {
    const response = await request(server())
      .post(`/api/v1/tiket/${tiketId}/qr`)
      .set('Authorization', `Bearer ${userA.token}`)
      .expect(201);

    return response.body as QrResponse;
  }

  function pindaiQr(
    qrPayload: string,
    tokenPetugas: string = petugasA.token,
    idLoket: string = loketId,
  ) {
    return request(server())
      .post('/api/v1/check-in')
      .set('Authorization', `Bearer ${tokenPetugas}`)
      .send({
        qrPayload,
        loketId: idLoket,
      });
  }

  // ========================================
  // SETUP TEST DATABASE
  // ========================================

  beforeAll(async () => {
    const databaseUrl = process.env.DATABASE_URL;

    if (!databaseUrl) {
      throw new Error('DATABASE_URL testing wajib ditentukan');
    }

    const url = new URL(databaseUrl);

    if (
      url.pathname !== '/capstone_antrean_test' ||
      !['127.0.0.1', 'localhost'].includes(url.hostname) ||
      url.port !== '5433'
    ) {
      throw new Error(
        'E2E hanya boleh memakai ' +
          'capstone_antrean_test lokal pada port 5433',
      );
    }

    tanggalHariIni = tanggalPelayananLokal();
    hariIniDb = tanggalDb(tanggalHariIni);

    const moduleRef = await Test.createTestingModule({
      imports: [AppModule],
    })
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

    admin = await buatAkun('Admin QR E2E', PeranPengguna.ADMIN);

    userA = await buatAkun('Pengguna QR A', PeranPengguna.USER);

    userB = await buatAkun('Pengguna QR B', PeranPengguna.USER);

    petugasA = await buatAkun('Petugas QR A', PeranPengguna.PETUGAS);

    petugasB = await buatAkun('Petugas QR B', PeranPengguna.PETUGAS);

    // Layanan khusus QR E2E.
    const layanan = await db().layanan.create({
      data: {
        kode: `QR${unik}`,
        nama: 'Layanan Pengujian QR',
        deskripsi: 'Khusus E2E QR Check-In',
        prefixAntrean: 'Q',
        durasiDasarMenit: 10,
        aktif: true,
      },
    });

    layananId = layanan.id;

    // Jadwal test mencakup seluruh hari.
    await db().jadwalLayanan.createMany({
      data: semuaHari.map((hari) => ({
        layananId,
        hari,
        jamBuka: new Date('1970-01-01T00:00:00.000Z'),
        jamTutup: new Date('1970-01-01T23:59:59.000Z'),
        kapasitasHarian: 1000,
        aktif: true,
      })),
    });

    // Loket aktif untuk layanan ini.
    const loket = await db().loket.create({
      data: {
        layananId,
        kode: `L${unik}`,
        nama: 'Loket QR E2E',
        lokasi: 'Ruang Testing',
        aktif: true,
      },
    });

    loketId = loket.id;

    // Dua petugas sama-sama berwenang
    // pada loket pengujian.
    const tanggalMulai = geserTanggal(hariIniDb, -1);

    const tanggalSelesai = geserTanggal(hariIniDb, 1);

    await db().penugasanPetugas.createMany({
      data: [
        {
          petugasId: petugasA.id,
          loketId,
          tanggalMulai,
          tanggalSelesai,
          aktif: true,
        },
        {
          petugasId: petugasB.id,
          loketId,
          tanggalMulai,
          tanggalSelesai,
          aktif: true,
        },
      ],
    });
  }, 120000);

  // ========================================
  // SATU TIKET SEGAR PER TEST
  // ========================================

  beforeEach(async () => {
    const counter = await db().urutanAntreanHarian.upsert({
      where: {
        layananId_tanggal: {
          layananId,
          tanggal: hariIniDb,
        },
      },
      create: {
        layananId,
        tanggal: hariIniDb,
        nomorTerakhir: 1,
      },
      update: {
        nomorTerakhir: {
          increment: 1,
        },
      },
    });

    nomorUrut = counter.nomorTerakhir;

    const tiket = await db().tiketAntrean.create({
      data: {
        penggunaId: userA.id,
        layananId,
        tanggalAntrean: hariIniDb,
        nomorUrut,
        kodeTiket: `TK${randomBytes(12).toString('hex').toUpperCase()}`,
        status: StatusTiket.DIPESAN,
      },
    });

    tiketId = tiket.id;
  }, 30000);

  afterEach(async () => {
    if (!prisma || !tiketId) {
      return;
    }

    await db().peristiwaAntrean.deleteMany({
      where: {
        tiketAntreanId: tiketId,
      },
    });

    await db().tiketAntrean.deleteMany({
      where: {
        id: tiketId,
      },
    });

    tiketId = '';
  }, 30000);

  // ========================================
  // CLEANUP
  // ========================================

  afterAll(async () => {
    try {
      if (prisma) {
        if (layananId) {
          const tiketTersisa = await prisma.tiketAntrean.findMany({
            where: {
              layananId,
            },
            select: {
              id: true,
            },
          });

          const idTiket = tiketTersisa.map((item) => item.id);

          if (idTiket.length > 0) {
            await prisma.peristiwaAntrean.deleteMany({
              where: {
                tiketAntreanId: {
                  in: idTiket,
                },
              },
            });
          }

          await prisma.tiketAntrean.deleteMany({
            where: {
              layananId,
            },
          });

          await prisma.urutanAntreanHarian.deleteMany({
            where: {
              layananId,
            },
          });

          await prisma.penugasanPetugas.deleteMany({
            where: {
              loketId,
            },
          });

          await prisma.jadwalLayanan.deleteMany({
            where: {
              layananId,
            },
          });

          await prisma.loket.deleteMany({
            where: {
              layananId,
            },
          });

          await prisma.layanan.deleteMany({
            where: {
              id: layananId,
            },
          });
        }

        if (penggunaIds.length > 0) {
          await prisma.sesiPengguna.deleteMany({
            where: {
              penggunaId: {
                in: penggunaIds,
              },
            },
          });

          await prisma.pengguna.deleteMany({
            where: {
              id: {
                in: penggunaIds,
              },
            },
          });
        }
      }
    } finally {
      if (app) {
        await app.close();
      }
    }
  }, 60000);

  // ========================================
  // 1. JWT
  // ========================================

  it('menolak penerbitan QR dan check-in tanpa JWT', async () => {
    await request(server()).post(`/api/v1/tiket/${tiketId}/qr`).expect(401);

    await request(server())
      .post('/api/v1/check-in')
      .send({
        qrPayload: `SQ1.${'A'.repeat(43)}`,
        loketId,
      })
      .expect(401);
  });

  // ========================================
  // 2. ROLE ACCESS
  // ========================================

  it('membatasi penerbitan QR dan scan berdasarkan role', async () => {
    await request(server())
      .post(`/api/v1/tiket/${tiketId}/qr`)
      .set('Authorization', `Bearer ${admin.token}`)
      .expect(403);

    await request(server())
      .post(`/api/v1/tiket/${tiketId}/qr`)
      .set('Authorization', `Bearer ${petugasA.token}`)
      .expect(403);

    await pindaiQr(`SQ1.${'A'.repeat(43)}`, userA.token).expect(403);

    await pindaiQr(`SQ1.${'A'.repeat(43)}`, admin.token).expect(403);
  });

  // ========================================
  // 3. PENERBITAN QR AMAN
  // ========================================

  it('menerbitkan token QR dengan hash dan expiry', async () => {
    const qr = await terbitkanQr();

    expect(qr.tiketId).toBe(tiketId);
    expect(qr.qrPayload).toMatch(/^SQ1\.[A-Za-z0-9_-]{43}$/);

    expect(qr.masaBerlakuDetik).toBe(600);
    expect(qr.status).toBe(StatusTiket.DIPESAN);

    const tiket = await db().tiketAntrean.findUnique({
      where: {
        id: tiketId,
      },
    });

    const hash = createHash('sha256')
      .update(qr.qrPayload, 'utf8')
      .digest('hex');

    expect(tiket?.tokenQrHash).toBe(hash);

    expect(tiket?.qrKedaluwarsaPada).not.toBeNull();

    expect(new Date(qr.berlakuHingga).getTime()).toBeGreaterThan(Date.now());

    expect(qr).not.toHaveProperty('tokenQrHash');
  });

  // ========================================
  // 4. KEPEMILIKAN
  // ========================================

  it('menolak QR tiket yang bukan milik pengguna', async () => {
    await request(server())
      .post(`/api/v1/tiket/${tiketId}/qr`)
      .set('Authorization', `Bearer ${userB.token}`)
      .expect(404);

    await request(server())
      .post('/api/v1/tiket/bukan-uuid/qr')
      .set('Authorization', `Bearer ${userA.token}`)
      .expect(400);
  });

  // ========================================
  // 5. VALIDASI TANGGAL PENERBITAN
  // ========================================

  it('menolak QR sebelum tanggal pelayanan', async () => {
    await db().tiketAntrean.update({
      where: {
        id: tiketId,
      },
      data: {
        tanggalAntrean: geserTanggal(hariIniDb, 2),
      },
    });

    await request(server())
      .post(`/api/v1/tiket/${tiketId}/qr`)
      .set('Authorization', `Bearer ${userA.token}`)
      .expect(400);
  });

  // ========================================
  // 6. STATUS TIKET
  // ========================================

  it('menolak penerbitan QR untuk tiket yang sudah CHECK_IN', async () => {
    await db().tiketAntrean.update({
      where: {
        id: tiketId,
      },
      data: {
        status: StatusTiket.CHECK_IN,
      },
    });

    await request(server())
      .post(`/api/v1/tiket/${tiketId}/qr`)
      .set('Authorization', `Bearer ${userA.token}`)
      .expect(409);
  });

  // ========================================
  // 7. ROTASI QR
  // ========================================

  it('penerbitan QR baru membatalkan token sebelumnya', async () => {
    const pertama = await terbitkanQr();
    const kedua = await terbitkanQr();

    expect(pertama.qrPayload).not.toBe(kedua.qrPayload);

    await pindaiQr(pertama.qrPayload).expect(400);

    await pindaiQr(kedua.qrPayload).expect(200);
  });

  // ========================================
  // 8. TOKEN INVALID
  // ========================================

  it('menolak format QR dan token palsu', async () => {
    await pindaiQr('bukan-qr').expect(400);

    await pindaiQr(`SQ1.${'Z'.repeat(43)}`).expect(400);

    await pindaiQr(
      `SQ1.${'Z'.repeat(43)}`,
      petugasA.token,
      'bukan-uuid',
    ).expect(400);
  });

  // ========================================
  // 9. EXPIRED TOKEN
  // ========================================

  it('menolak QR yang sudah kedaluwarsa', async () => {
    const qr = await terbitkanQr();

    await db().tiketAntrean.update({
      where: {
        id: tiketId,
      },
      data: {
        qrKedaluwarsaPada: new Date(Date.now() - 60 * 1000),
      },
    });

    await pindaiQr(qr.qrPayload).expect(410);

    const tiket = await db().tiketAntrean.findUnique({
      where: {
        id: tiketId,
      },
    });

    expect(tiket?.status).toBe(StatusTiket.DIPESAN);
  });

  // ========================================
  // 10. PENUGASAN NONAKTIF
  // ========================================

  it('menolak scan dari petugas tanpa penugasan aktif', async () => {
    const qr = await terbitkanQr();

    const where = {
      petugasId: petugasA.id,
      loketId,
    };

    await db().penugasanPetugas.updateMany({
      where,
      data: {
        aktif: false,
      },
    });

    try {
      await pindaiQr(qr.qrPayload, petugasA.token).expect(403);
    } finally {
      await db().penugasanPetugas.updateMany({
        where,
        data: {
          aktif: true,
        },
      });
    }
  });

  // ========================================
  // 11. TANGGAL CHECK-IN SALAH
  // ========================================

  it('menolak check-in di luar tanggal tiket', async () => {
    const qr = await terbitkanQr();

    // Ubah hanya data tiket E2E.
    await db().tiketAntrean.update({
      where: {
        id: tiketId,
      },
      data: {
        tanggalAntrean: geserTanggal(hariIniDb, 1),
      },
    });

    await pindaiQr(qr.qrPayload).expect(400);
  });

  // ========================================
  // 12. CHECK-IN BERHASIL DAN ANTI-REPLAY
  // ========================================

  it('check-in berhasil, audit tercatat, dan QR tidak dapat dipakai ulang', async () => {
    const qr = await terbitkanQr();

    const sebelum = await db().tiketAntrean.findUniqueOrThrow({
      where: {
        id: tiketId,
      },
    });

    const response = await pindaiQr(qr.qrPayload).expect(200);

    const hasil = response.body as CheckInResponse;

    expect(hasil.tiketId).toBe(tiketId);
    expect(hasil.status).toBe(StatusTiket.CHECK_IN);

    expect(hasil.loketId).toBe(loketId);
    expect(hasil.petugasId).toBe(petugasA.id);

    expect(hasil.nomorAntrean).toBe(`Q-${String(nomorUrut).padStart(3, '0')}`);

    const sesudah = await db().tiketAntrean.findUniqueOrThrow({
      where: {
        id: tiketId,
      },
    });

    expect(sesudah.status).toBe(StatusTiket.CHECK_IN);

    expect(sesudah.checkInPada).not.toBeNull();
    expect(sesudah.tokenQrHash).toBeNull();
    expect(sesudah.qrKedaluwarsaPada).toBeNull();
    expect(sesudah.loketId).toBe(loketId);
    expect(sesudah.versi).toBe(sebelum.versi + 1);

    const audit = await db().peristiwaAntrean.findMany({
      where: {
        tiketAntreanId: tiketId,
        tipe: 'CHECK_IN',
      },
    });

    expect(audit).toHaveLength(1);

    expect(audit[0]).toMatchObject({
      aktorId: petugasA.id,
      statusSebelum: StatusTiket.DIPESAN,
      statusSesudah: StatusTiket.CHECK_IN,
    });

    // Scan ulang harus ditolak.
    await pindaiQr(qr.qrPayload).expect(400);
  }, 30000);

  // ========================================
  // 13. RACE CONDITION
  // ========================================

  it('dua petugas tidak dapat check-in tiket yang sama secara bersamaan', async () => {
    const qr = await terbitkanQr();

    const sebelum = await db().tiketAntrean.findUniqueOrThrow({
      where: {
        id: tiketId,
      },
    });

    const [hasilA, hasilB] = await Promise.all([
      pindaiQr(qr.qrPayload, petugasA.token),
      pindaiQr(qr.qrPayload, petugasB.token),
    ]);

    const status = [hasilA.status, hasilB.status];

    // Tepat satu request berhasil.
    expect(status.filter((nilai) => nilai === 200)).toHaveLength(1);

    const penolakan = status.find((nilai) => nilai !== 200);

    expect([400, 409]).toContain(penolakan);

    const tiket = await db().tiketAntrean.findUniqueOrThrow({
      where: {
        id: tiketId,
      },
    });

    expect(tiket.status).toBe(StatusTiket.CHECK_IN);

    expect(tiket.versi).toBe(sebelum.versi + 1);

    expect(tiket.tokenQrHash).toBeNull();

    const jumlahAudit = await db().peristiwaAntrean.count({
      where: {
        tiketAntreanId: tiketId,
        tipe: 'CHECK_IN',
      },
    });

    expect(jumlahAudit).toBe(1);
  }, 30000);

  // ========================================
  // 14. CHECK-IN DI LUAR JAM PELAYANAN
  // ========================================

  it('menolak check-in di luar jam pelayanan tanpa mengubah tiket', async () => {
    // 1. Terbitkan QR valid untuk tiket test.
    const qr = await terbitkanQr();

    const sebelum = await db().tiketAntrean.findUniqueOrThrow({
      where: {
        id: tiketId,
      },
    });

    // 2. Temukan jadwal hari pelayanan.
    const hari = semuaHari[hariIniDb.getUTCDay()];

    const whereJadwal = {
      layananId_hari: {
        layananId,
        hari,
      },
    };

    const jadwalAsli = await db().jadwalLayanan.findUniqueOrThrow({
      where: whereJadwal,
    });

    // 3. Tentukan rentang waktu yang pasti
    // berada di luar jam saat test berjalan.
    const zonaWaktu = process.env.SERVICE_TIME_ZONE ?? 'Asia/Jakarta';

    const bagianJam = new Intl.DateTimeFormat('en-GB', {
      timeZone: zonaWaktu,
      hour: '2-digit',
      hourCycle: 'h23',
    }).formatToParts(new Date());

    const jamSekarang = Number(
      bagianJam.find((bagian) => bagian.type === 'hour')?.value ?? '0',
    );

    // Pagi: jadwal 15.00-16.00.
    // Siang/malam: jadwal 03.00-04.00.
    const jamBuka = jamSekarang < 12 ? '15:00:00' : '03:00:00';

    const jamTutup = jamSekarang < 12 ? '16:00:00' : '04:00:00';

    await db().jadwalLayanan.update({
      where: whereJadwal,
      data: {
        jamBuka: new Date(`1970-01-01T${jamBuka}.000Z`),
        jamTutup: new Date(`1970-01-01T${jamTutup}.000Z`),
      },
    });

    try {
      // 4. Petugas mencoba check-in.
      const response = await pindaiQr(qr.qrPayload).expect(400);

      expect(response.body).toMatchObject({
        message: 'Check-in berada di luar jam pelayanan',
      });

      // 5. Pastikan tiket tetap DIPESAN.
      const sesudah = await db().tiketAntrean.findUniqueOrThrow({
        where: {
          id: tiketId,
        },
      });

      expect(sesudah.status).toBe(StatusTiket.DIPESAN);

      expect(sesudah.checkInPada).toBeNull();

      // QR tidak boleh dikonsumsi.
      expect(sesudah.tokenQrHash).toBe(sebelum.tokenQrHash);

      // Versi tidak berubah.
      expect(sesudah.versi).toBe(sebelum.versi);

      // Tidak boleh ada audit CHECK_IN.
      const jumlahAudit = await db().peristiwaAntrean.count({
        where: {
          tiketAntreanId: tiketId,
          tipe: 'CHECK_IN',
        },
      });

      expect(jumlahAudit).toBe(0);
    } finally {
      // 6. WAJIB kembalikan jadwal.
      await db().jadwalLayanan.update({
        where: whereJadwal,
        data: {
          jamBuka: jadwalAsli.jamBuka,
          jamTutup: jadwalAsli.jamTutup,
        },
      });
    }
  }, 30000);

  // ========================================
  // 15. ROLLBACK KETIKA AUDIT GAGAL
  // ========================================

  it('melakukan rollback jika audit CHECK_IN gagal disimpan', async () => {
    const qr = await terbitkanQr();

    // 1. Simpan kondisi tiket sebelum scan.
    const sebelum = await db().tiketAntrean.findUniqueOrThrow({
      where: {
        id: tiketId,
      },
    });

    expect(sebelum.status).toBe(StatusTiket.DIPESAN);

    expect(sebelum.tokenQrHash).not.toBeNull();

    // 2. Pengamanan ID untuk statement DDL.
    // ID berasal dari database testing.
    if (
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
        tiketId,
      )
    ) {
      throw new Error('UUID tiket pengujian tidak valid');
    }

    // 3. Validasi ekstra untuk memastikan
    // DDL tidak menyentuh database development.
    const databaseUrl = process.env.DATABASE_URL;

    if (!databaseUrl) {
      throw new Error('DATABASE_URL test tidak ditemukan');
    }

    const url = new URL(databaseUrl);

    if (
      url.pathname !== '/capstone_antrean_test' ||
      !['127.0.0.1', 'localhost'].includes(url.hostname) ||
      url.port !== '5433'
    ) {
      throw new Error(
        'Rollback E2E hanya boleh menggunakan database testing lokal',
      );
    }

    // 4. Nama constraint unik khusus test ini.
    const namaConstraint = `e2e_qr_rollback_${randomUUID()
      .replace(/-/g, '')
      .slice(0, 12)}`;

    let constraintTerpasang = false;

    try {
      // 5. Tambahkan constraint sementara.
      // Hanya audit untuk tiket ini yang
      // sengaja dibuat gagal.
      await db().$executeRawUnsafe(
        `ALTER TABLE "public"."peristiwa_antrean"
         ADD CONSTRAINT "${namaConstraint}"
         CHECK (
           "tiket_antrean_id" <>
           '${tiketId}'::uuid
         )`,
      );

      constraintTerpasang = true;

      // 6. Lakukan scan QR sebenarnya.
      // Audit gagal setelah update tiket.
      // Tanpa transaction rollback, tiket
      // akan tertinggal di status CHECK_IN.
      const response = await pindaiQr(qr.qrPayload);

      // Kegagalan database yang disengaja
      // menghasilkan internal server error.
      expect(response.status).toBe(500);
    } finally {
      // 7. SELALU hapus constraint test.
      if (constraintTerpasang) {
        await db().$executeRawUnsafe(
          `ALTER TABLE "public"."peristiwa_antrean"
           DROP CONSTRAINT IF EXISTS
           "${namaConstraint}"`,
        );
      }
    }

    // 8. Periksa keadaan database
    // setelah transaksi gagal.
    const sesudah = await db().tiketAntrean.findUniqueOrThrow({
      where: {
        id: tiketId,
      },
    });

    // Status tidak boleh berubah.
    expect(sesudah.status).toBe(StatusTiket.DIPESAN);

    expect(sesudah.checkInPada).toBeNull();
    expect(sesudah.loketId).toBeNull();

    // Hash dan expiry tetap tersimpan.
    expect(sesudah.tokenQrHash).toBe(sebelum.tokenQrHash);

    expect(sesudah.qrKedaluwarsaPada).toEqual(sebelum.qrKedaluwarsaPada);

    // Versi tetap sama.
    expect(sesudah.versi).toBe(sebelum.versi);

    // Tidak ada catatan audit parsial.
    const jumlahAudit = await db().peristiwaAntrean.count({
      where: {
        tiketAntreanId: tiketId,
        tipe: 'CHECK_IN',
      },
    });

    expect(jumlahAudit).toBe(0);
  }, 30000);

  // ==========================================
  // QUEUE ENGINE API - E2E
  // ==========================================

  describe('Queue Engine API (e2e)', () => {
    const urlMasuk = (id: string) => `/api/v1/queue/${id}/masuk`;

    function masukAntrean(
      id: string = tiketId,
      token: string = petugasA.token,
    ) {
      return request(server())
        .post(urlMasuk(id))
        .set('Authorization', `Bearer ${token}`)
        .send({ loketId });
    }

    function daftarMenunggu(token: string = petugasA.token) {
      return request(server())
        .get('/api/v1/queue/menunggu')
        .query({ loketId })
        .set('Authorization', `Bearer ${token}`);
    }

    async function siapkanTiketCheckIn() {
      const qr = await terbitkanQr();

      await pindaiQr(qr.qrPayload, petugasA.token, loketId).expect(200);
    }

    // ========================================
    // 1. JWT WAJIB
    // ========================================

    it('menolak endpoint Queue tanpa JWT', async () => {
      await request(server())
        .post(urlMasuk(tiketId))
        .send({ loketId })
        .expect(401);

      await request(server())
        .get('/api/v1/queue/menunggu')
        .query({ loketId })
        .expect(401);
    });

    // ========================================
    // 2. RBAC - USER DITOLAK
    // ========================================

    it('menolak akses Queue dari role USER', async () => {
      await masukAntrean(tiketId, userA.token).expect(403);

      await daftarMenunggu(userA.token).expect(403);
    });

    // ========================================
    // 3. CHECK_IN -> MENUNGGU
    // ========================================

    it('memasukkan tiket CHECK_IN ke FIFO dan mencatat audit', async () => {
      await siapkanTiketCheckIn();

      const counterSebelum = await db().urutanAntreanHarian.findUniqueOrThrow({
        where: {
          layananId_tanggal: {
            layananId,
            tanggal: hariIniDb,
          },
        },
      });

      const tiketSebelum = await db().tiketAntrean.findUniqueOrThrow({
        where: { id: tiketId },
      });

      const response = await masukAntrean().expect(200);

      const hasil = response.body as {
        tiketId: string;
        status: StatusTiket;
        urutanMasukAntrean: number;
        nomorAntrean: string;
      };

      expect(hasil.tiketId).toBe(tiketId);
      expect(hasil.status).toBe(StatusTiket.MENUNGGU);

      expect(hasil.urutanMasukAntrean).toBe(
        counterSebelum.urutanMasukTerakhir + 1,
      );

      const tiketSesudah = await db().tiketAntrean.findUniqueOrThrow({
        where: { id: tiketId },
      });

      expect(tiketSesudah.status).toBe(StatusTiket.MENUNGGU);

      expect(tiketSesudah.versi).toBe(tiketSebelum.versi + 1);

      expect(tiketSesudah.masukAntreanPada).not.toBeNull();

      // Nomor tiket permanen.
      expect(tiketSesudah.nomorUrut).toBe(tiketSebelum.nomorUrut);

      expect(tiketSesudah.kodeTiket).toBe(tiketSebelum.kodeTiket);

      const audit = await db().peristiwaAntrean.findMany({
        where: {
          tiketAntreanId: tiketId,
          tipe: 'ENQUEUE',
        },
      });

      expect(audit).toHaveLength(1);

      expect(audit[0]).toMatchObject({
        aktorId: petugasA.id,
        statusSebelum: StatusTiket.CHECK_IN,
        statusSesudah: StatusTiket.MENUNGGU,
      });
    });

    // ========================================
    // 4. ANTI DUPLIKASI
    // ========================================

    it('menolak masuk antrean dua kali tanpa menaikkan counter', async () => {
      await siapkanTiketCheckIn();

      await masukAntrean().expect(200);

      const sebelum = await db().urutanAntreanHarian.findUniqueOrThrow({
        where: {
          layananId_tanggal: {
            layananId,
            tanggal: hariIniDb,
          },
        },
      });

      await masukAntrean().expect(409);

      const sesudah = await db().urutanAntreanHarian.findUniqueOrThrow({
        where: {
          layananId_tanggal: {
            layananId,
            tanggal: hariIniDb,
          },
        },
      });

      expect(sesudah.urutanMasukTerakhir).toBe(sebelum.urutanMasukTerakhir);

      const jumlahAudit = await db().peristiwaAntrean.count({
        where: {
          tiketAntreanId: tiketId,
          tipe: 'ENQUEUE',
        },
      });

      expect(jumlahAudit).toBe(1);
    });

    // ========================================
    // 5. FIFO DUA TIKET
    // ========================================

    it('mengurutkan dua tiket menurut FIFO, bukan ID atau nomor tiket', async () => {
      await siapkanTiketCheckIn();

      // Tiket pertama masuk antrean.
      const pertama = await masukAntrean().expect(200);

      // Buat tiket kedua khusus pengujian
      // pada layanan dan tanggal yang sama.
      const counterNomor = await db().urutanAntreanHarian.update({
        where: {
          layananId_tanggal: {
            layananId,
            tanggal: hariIniDb,
          },
        },
        data: {
          nomorTerakhir: {
            increment: 1,
          },
        },
      });

      const tiketKedua = await db().tiketAntrean.create({
        data: {
          penggunaId: userB.id,
          layananId,
          loketId,
          tanggalAntrean: hariIniDb,
          nomorUrut: counterNomor.nomorTerakhir,
          kodeTiket: `TK${randomBytes(12).toString('hex').toUpperCase()}`,
          status: StatusTiket.CHECK_IN,
          checkInPada: new Date(),
        },
      });

      try {
        // Tiket kedua masuk antrean.
        const kedua = await masukAntrean(tiketKedua.id).expect(200);

        const urutanPertama = (
          pertama.body as {
            urutanMasukAntrean: number;
          }
        ).urutanMasukAntrean;

        const urutanKedua = (
          kedua.body as {
            urutanMasukAntrean: number;
          }
        ).urutanMasukAntrean;

        expect(urutanKedua).toBe(urutanPertama + 1);

        // GET mengembalikan urutan FIFO.
        const daftar = await daftarMenunggu().expect(200);

        const hasil = daftar.body as Array<{
          tiketId: string;
          urutanMasukAntrean: number;
          status: StatusTiket;
        }>;

        expect(hasil).toHaveLength(2);

        expect(hasil.map((item) => item.tiketId)).toEqual([
          tiketId,
          tiketKedua.id,
        ]);

        expect(hasil.map((item) => item.urutanMasukAntrean)).toEqual([
          urutanPertama,
          urutanKedua,
        ]);
      } finally {
        // Hapus fixture tambahan.
        await db().peristiwaAntrean.deleteMany({
          where: {
            tiketAntreanId: tiketKedua.id,
          },
        });

        await db().tiketAntrean.delete({
          where: {
            id: tiketKedua.id,
          },
        });
      }
    }, 30000);

    // ========================================
    // 6. PENUGASAN PETUGAS NONAKTIF
    // ========================================

    it('menolak operasi jika penugasan PETUGAS nonaktif', async () => {
      await siapkanTiketCheckIn();

      const filterPenugasan = {
        petugasId: petugasA.id,
        loketId,
      };

      await db().penugasanPetugas.updateMany({
        where: filterPenugasan,
        data: {
          aktif: false,
        },
      });

      try {
        await masukAntrean().expect(403);

        await daftarMenunggu().expect(403);
      } finally {
        await db().penugasanPetugas.updateMany({
          where: filterPenugasan,
          data: {
            aktif: true,
          },
        });
      }

      const tiket = await db().tiketAntrean.findUniqueOrThrow({
        where: { id: tiketId },
      });

      expect(tiket.status).toBe(StatusTiket.CHECK_IN);
    });

    // ========================================
    // 7. RACE CONDITION
    // ========================================

    it('dua request bersamaan hanya dapat memasukkan tiket sekali', async () => {
      await siapkanTiketCheckIn();

      const counterSebelum = await db().urutanAntreanHarian.findUniqueOrThrow({
        where: {
          layananId_tanggal: {
            layananId,
            tanggal: hariIniDb,
          },
        },
      });

      const [responseA, responseB] = await Promise.all([
        masukAntrean(),
        masukAntrean(),
      ]);

      const status = [responseA.status, responseB.status].sort((a, b) => a - b);

      expect(status).toEqual([200, 409]);

      // Tepat satu request diterima.
      expect(status).toEqual([200, 409]);

      const tiket = await db().tiketAntrean.findUniqueOrThrow({
        where: { id: tiketId },
      });

      expect(tiket.status).toBe(StatusTiket.MENUNGGU);

      const counterSesudah = await db().urutanAntreanHarian.findUniqueOrThrow({
        where: {
          layananId_tanggal: {
            layananId,
            tanggal: hariIniDb,
          },
        },
      });

      // Counter hanya bertambah satu.
      expect(counterSesudah.urutanMasukTerakhir).toBe(
        counterSebelum.urutanMasukTerakhir + 1,
      );

      const jumlahAudit = await db().peristiwaAntrean.count({
        where: {
          tiketAntreanId: tiketId,
          tipe: 'ENQUEUE',
        },
      });

      expect(jumlahAudit).toBe(1);
    }, 30000);

    // ========================================
    // 8. ROLLBACK JIKA AUDIT ENQUEUE GAGAL
    // ========================================

    it('rollback tiket dan counter FIFO jika audit ENQUEUE gagal', async () => {
      // 1. Siapkan tiket CHECK_IN melalui API.
      await siapkanTiketCheckIn();

      // 2. Pastikan koneksi menggunakan database
      // testing lokal, bukan development.
      const koneksi = process.env.DATABASE_URL;

      if (!koneksi) {
        throw new Error('DATABASE_URL testing belum ditentukan');
      }

      const url = new URL(koneksi);

      if (
        url.pathname !== '/capstone_antrean_test' ||
        !['localhost', '127.0.0.1'].includes(url.hostname) ||
        url.port !== '5433'
      ) {
        throw new Error(
          'Pengujian rollback hanya boleh berjalan pada PostgreSQL testing lokal',
        );
      }

      const databaseAktif = await db().$queryRaw<
        Array<{ namaDatabase: string }>
      >`SELECT current_database() AS "namaDatabase"`;

      expect(databaseAktif[0]?.namaDatabase).toBe('capstone_antrean_test');

      // 3. Ambil kondisi awal.
      const tiketSebelum = await db().tiketAntrean.findUniqueOrThrow({
        where: { id: tiketId },
      });

      const counterSebelum = await db().urutanAntreanHarian.findUniqueOrThrow({
        where: {
          layananId_tanggal: {
            layananId,
            tanggal: hariIniDb,
          },
        },
      });

      expect(tiketSebelum.status).toBe(StatusTiket.CHECK_IN);

      expect(tiketSebelum.urutanMasukAntrean).toBeNull();

      const auditSebelum = await db().peristiwaAntrean.count({
        where: {
          tiketAntreanId: tiketId,
          tipe: 'ENQUEUE',
        },
      });

      expect(auditSebelum).toBe(0);

      // 4. Validasi UUID sebelum interpolasi DDL.
      if (
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
          tiketId,
        )
      ) {
        throw new Error('UUID tiket testing tidak valid');
      }

      // randomBytes sudah digunakan di file E2E
      // pada pengujian FIFO sebelumnya.
      const namaConstraint = `e2e_queue_rollback_${randomBytes(6).toString(
        'hex',
      )}`;

      let constraintTerpasang = false;

      try {
        // 5. Buat constraint sementara yang hanya
        // menolak audit ENQUEUE milik tiket ini.
        await db().$executeRawUnsafe(
          `ALTER TABLE "public"."peristiwa_antrean"
           ADD CONSTRAINT "${namaConstraint}"
           CHECK (
             NOT (
               "tiket_antrean_id" = '${tiketId}'::uuid
               AND "tipe" = 'ENQUEUE'
             )
           )`,
        );

        constraintTerpasang = true;

        // 6. Jalankan endpoint sebenarnya.
        // Status, counter, dan audit berada
        // di dalam satu transaksi PostgreSQL.
        await masukAntrean().expect(500);
      } finally {
        // 7. Hapus constraint walaupun
        // pengujian mengalami kegagalan.
        if (constraintTerpasang) {
          await db().$executeRawUnsafe(
            `ALTER TABLE "public"."peristiwa_antrean"
             DROP CONSTRAINT IF EXISTS
             "${namaConstraint}"`,
          );
        }
      }

      // 8. Baca ulang kondisi database.
      const tiketSesudah = await db().tiketAntrean.findUniqueOrThrow({
        where: { id: tiketId },
      });

      const counterSesudah = await db().urutanAntreanHarian.findUniqueOrThrow({
        where: {
          layananId_tanggal: {
            layananId,
            tanggal: hariIniDb,
          },
        },
      });

      const auditSesudah = await db().peristiwaAntrean.count({
        where: {
          tiketAntreanId: tiketId,
          tipe: 'ENQUEUE',
        },
      });

      // 9. Status tetap CHECK_IN.
      expect(tiketSesudah.status).toBe(StatusTiket.CHECK_IN);

      // 10. Nomor FIFO tidak dialokasikan.
      expect(tiketSesudah.urutanMasukAntrean).toBeNull();

      expect(tiketSesudah.masukAntreanPada).toBeNull();

      // 11. Versi tiket tidak bertambah.
      expect(tiketSesudah.versi).toBe(tiketSebelum.versi);

      // 12. Nomor tiket tetap sama.
      expect(tiketSesudah.nomorUrut).toBe(tiketSebelum.nomorUrut);

      expect(tiketSesudah.kodeTiket).toBe(tiketSebelum.kodeTiket);

      // 13. Counter FIFO harus rollback.
      expect(counterSesudah.urutanMasukTerakhir).toBe(
        counterSebelum.urutanMasukTerakhir,
      );

      // 14. Tidak ada audit ENQUEUE parsial.
      expect(auditSesudah).toBe(0);
    }, 30000);

    // ========================================
    // QUEUE ENGINE - CALL E2E
    // ========================================

    function panggilAntrean(
      token: string = petugasA.token,
      idLoket: string = loketId,
    ) {
      return request(server())
        .post('/api/v1/queue/panggil')
        .set('Authorization', `Bearer ${token}`)
        .send({ loketId: idLoket });
    }

    // ========================================
    // 1. CALL BERHASIL
    // ========================================

    it('CALL mengubah MENUNGGU menjadi DIPANGGIL dan mencatat audit', async () => {
      // Siapkan tiket dan lakukan QR Check-In.
      await siapkanTiketCheckIn();

      // Masukkan ke antrean FIFO.
      await masukAntrean().expect(200);

      const tiketSebelum = await db().tiketAntrean.findUniqueOrThrow({
        where: { id: tiketId },
      });

      expect(tiketSebelum.status).toBe(StatusTiket.MENUNGGU);

      const response = await panggilAntrean().expect(200);

      const hasil = response.body as {
        tiketId: string;
        loketId: string;
        nomorAntrean: string;
        status: StatusTiket;
        urutanMasukAntrean: number;
        versi: number;
      };

      expect(hasil.tiketId).toBe(tiketId);
      expect(hasil.loketId).toBe(loketId);

      expect(hasil.status).toBe(StatusTiket.DIPANGGIL);

      expect(hasil.versi).toBe(tiketSebelum.versi + 1);

      expect(hasil.urutanMasukAntrean).toBe(tiketSebelum.urutanMasukAntrean);

      // Verifikasi langsung ke PostgreSQL.
      const tiketSesudah = await db().tiketAntrean.findUniqueOrThrow({
        where: { id: tiketId },
      });

      expect(tiketSesudah.status).toBe(StatusTiket.DIPANGGIL);

      expect(tiketSesudah.loketId).toBe(loketId);

      expect(tiketSesudah.dipanggilPada).not.toBeNull();

      // Nomor tiket tidak berubah.
      expect(tiketSesudah.nomorUrut).toBe(tiketSebelum.nomorUrut);

      expect(tiketSesudah.kodeTiket).toBe(tiketSebelum.kodeTiket);

      // Verifikasi audit CALL.
      const audit = await db().peristiwaAntrean.findMany({
        where: {
          tiketAntreanId: tiketId,
          tipe: 'CALL',
        },
      });

      expect(audit).toHaveLength(1);

      expect(audit[0]).toMatchObject({
        aktorId: petugasA.id,
        statusSebelum: StatusTiket.MENUNGGU,
        statusSesudah: StatusTiket.DIPANGGIL,
      });
    }, 30000);

    // ========================================
    // 2. LOKET SIBUK
    // ========================================

    it('menolak CALL kedua ketika loket masih memiliki tiket aktif', async () => {
      await siapkanTiketCheckIn();
      await masukAntrean().expect(200);

      await panggilAntrean().expect(200);

      // Loket masih menangani tiket DIPANGGIL.
      await panggilAntrean().expect(409);

      // Pastikan tidak muncul audit CALL ganda.
      const jumlahAudit = await db().peristiwaAntrean.count({
        where: {
          tiketAntreanId: tiketId,
          tipe: 'CALL',
        },
      });

      expect(jumlahAudit).toBe(1);
    }, 30000);

    // ========================================
    // 3. RBAC USER
    // ========================================

    it('menolak pemanggilan oleh akun USER', async () => {
      await panggilAntrean(userA.token).expect(403);
    });

    // ========================================
    // 4. DUA REQUEST PADA LOKET YANG SAMA
    // ========================================

    it('dua CALL bersamaan pada loket yang sama hanya berhasil sekali', async () => {
      await siapkanTiketCheckIn();
      await masukAntrean().expect(200);

      const [responseA, responseB] = await Promise.all([
        panggilAntrean(),
        panggilAntrean(),
      ]);

      const kodeStatus = [responseA.status, responseB.status].sort(
        (a, b) => a - b,
      );

      // Satu berhasil, satu ditolak.
      expect(kodeStatus).toEqual([200, 409]);

      const tiket = await db().tiketAntrean.findUniqueOrThrow({
        where: { id: tiketId },
      });

      expect(tiket.status).toBe(StatusTiket.DIPANGGIL);

      const jumlahAudit = await db().peristiwaAntrean.count({
        where: {
          tiketAntreanId: tiketId,
          tipe: 'CALL',
        },
      });

      expect(jumlahAudit).toBe(1);
    }, 30000);
    // ========================================
    // 01G-D.3-A.5 — ROLLBACK AUDIT CALL (E2E)
    // ========================================
    it('CALL rollback jika penyimpanan audit gagal', async () => {
      await siapkanTiketCheckIn();
      await masukAntrean().expect(200);

      // DDL sementara tidak boleh menyentuh database development.
      const databaseUrl = process.env.DATABASE_URL;
      if (!databaseUrl) {
        throw new Error('DATABASE_URL E2E belum ditentukan');
      }
      const url = new URL(databaseUrl);
      if (
        url.pathname !== '/capstone_antrean_test' ||
        !['localhost', '127.0.0.1'].includes(url.hostname) ||
        url.port !== '5433'
      ) {
        throw new Error('Rollback CALL wajib menggunakan PostgreSQL testing lokal');
      }
      const database = await db().$queryRaw<
        Array<{ namaDatabase: string }>
      >`SELECT current_database() AS "namaDatabase"`;
      expect(database[0]?.namaDatabase).toBe('capstone_antrean_test');

      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(tiketId)) {
        throw new Error('ID tiket E2E bukan UUID yang valid');
      }

      const sebelum = await db().tiketAntrean.findUniqueOrThrow({
        where: { id: tiketId },
      });
      expect(sebelum.status).toBe(StatusTiket.MENUNGGU);
      expect(sebelum.dipanggilPada).toBeNull();
      expect(await db().peristiwaAntrean.count({
        where: { tiketAntreanId: tiketId, tipe: 'CALL' },
      })).toBe(0);

      // Constraint unik, hanya menolak audit CALL untuk tiket fixture ini.
      const namaConstraint = `e2e_call_rollback_${randomBytes(6).toString('hex')}`;
      let constraintTerpasang = false;
      try {
        await db().$executeRawUnsafe(
          `ALTER TABLE "public"."peristiwa_antrean"
           ADD CONSTRAINT "${namaConstraint}"
           CHECK (NOT (
             "tiket_antrean_id" = '${tiketId}'::uuid
             AND "tipe" = 'CALL'
           ))`,
        );
        constraintTerpasang = true;

        // Perubahan status akan gagal di tahap audit dan harus rollback.
        await panggilAntrean().expect(500);
      } finally {
        if (constraintTerpasang) {
          await db().$executeRawUnsafe(
            `ALTER TABLE "public"."peristiwa_antrean"
             DROP CONSTRAINT IF EXISTS "${namaConstraint}"`,
          );
        }
      }

      const sesudah = await db().tiketAntrean.findUniqueOrThrow({
        where: { id: tiketId },
      });
      expect(sesudah.status).toBe(StatusTiket.MENUNGGU);
      expect(sesudah.versi).toBe(sebelum.versi);
      expect(sesudah.loketId).toBe(sebelum.loketId);
      expect(sesudah.dipanggilPada).toEqual(sebelum.dipanggilPada);
      expect(sesudah.urutanMasukAntrean).toBe(sebelum.urutanMasukAntrean);
      expect(sesudah.masukAntreanPada).toEqual(sebelum.masukAntreanPada);
      expect(sesudah.nomorUrut).toBe(sebelum.nomorUrut);
      expect(sesudah.kodeTiket).toBe(sebelum.kodeTiket);
      expect(await db().peristiwaAntrean.count({
        where: { tiketAntreanId: tiketId, tipe: 'CALL' },
      })).toBe(0);

      // Antrean tidak hilang akibat percobaan CALL gagal.
      const antrean = await daftarMenunggu().expect(200);
      expect(antrean.body).toEqual(expect.arrayContaining([
        expect.objectContaining({ tiketId, status: StatusTiket.MENUNGGU }),
      ]));
    }, 30000);

    // ========================================
    // 01G-D.3-A.4-B — CALL MULTI-LOKET (E2E)
    // ========================================
    // Satu layanan, dua loket, dua petugas.
    // Fixture loket kedua dibuat/dihapus setiap test.

    describe('CALL Multi-Loket (e2e)', () => {
      let loketKeduaId: string | null = null;
      let tiketKeduaId: string | null = null;

      beforeEach(async () => {
        const loketKedua = await db().loket.create({
          data: {
            layananId,
            kode: `B${randomBytes(7).toString('hex').toUpperCase()}`,
            nama: 'Loket B - E2E CALL',
            lokasi: 'Ruang Testing',
            aktif: true,
          },
        });

        loketKeduaId = loketKedua.id;

        // PETUGAS B berwenang di loket kedua, sedangkan
        // PETUGAS A hanya menggunakan loket pertama.
        await db().penugasanPetugas.create({
          data: {
            petugasId: petugasB.id,
            loketId: loketKedua.id,
            tanggalMulai: geserTanggal(hariIniDb, -1),
            tanggalSelesai: geserTanggal(hariIniDb, 1),
            aktif: true,
          },
        });
      }, 30000);

      afterEach(async () => {
        // Cleanup child berjalan sebelum afterEach luar
        // yang menghapus tiket pertama.
        if (tiketKeduaId) {
          await db().peristiwaAntrean.deleteMany({
            where: { tiketAntreanId: tiketKeduaId },
          });
          await db().tiketAntrean.deleteMany({
            where: { id: tiketKeduaId },
          });
          tiketKeduaId = null;
        }

        if (loketKeduaId) {
          await db().penugasanPetugas.deleteMany({
            where: { loketId: loketKeduaId },
          });
          await db().loket.deleteMany({
            where: { id: loketKeduaId },
          });
          loketKeduaId = null;
        }
      }, 30000);

      async function buatTiketKeduaMenunggu(): Promise<{
        id: string;
        urutanMasukAntrean: number;
      }> {
        // Fixture tiket kedua dimulai dari CHECK_IN,
        // karena QR Check-In telah diuji di suite yang sama.
        // Masuk ke MENUNGGU tetap melalui endpoint HTTP.
        const counter = await db().urutanAntreanHarian.update({
          where: {
            layananId_tanggal: { layananId, tanggal: hariIniDb },
          },
          data: { nomorTerakhir: { increment: 1 } },
        });

        const tiketKedua = await db().tiketAntrean.create({
          data: {
            penggunaId: userB.id,
            layananId,
            loketId,
            tanggalAntrean: hariIniDb,
            nomorUrut: counter.nomorTerakhir,
            kodeTiket: `TK${randomBytes(12).toString('hex').toUpperCase()}`,
            status: StatusTiket.CHECK_IN,
            checkInPada: new Date(),
          },
        });
        tiketKeduaId = tiketKedua.id;

        const respons = await masukAntrean(tiketKedua.id).expect(200);
        const hasil = respons.body as {
          urutanMasukAntrean: number;
          status: StatusTiket;
        };

        expect(hasil.status).toBe(StatusTiket.MENUNGGU);

        return {
          id: tiketKedua.id,
          urutanMasukAntrean: hasil.urutanMasukAntrean,
        };
      }

      // ======================================
      // A. DUA LOKET + DUA TIKET MENUNGGU
      // ======================================
      it('dua loket memanggil dua tiket FIFO berbeda tanpa klaim ganda', async () => {
        await siapkanTiketCheckIn();
        const antreanPertama = await masukAntrean().expect(200);
        const tiketKedua = await buatTiketKeduaMenunggu();

        const urutanPertama = (
          antreanPertama.body as { urutanMasukAntrean: number }
        ).urutanMasukAntrean;

        expect(tiketKedua.urutanMasukAntrean).toBe(urutanPertama + 1);

        if (!loketKeduaId) {
          throw new Error('Loket kedua belum dibuat');
        }
        const idLoketB = loketKeduaId;

        // Kedua PETUGAS melakukan CALL hampir bersamaan.
        // Assignment tiket ke A/B dapat berbeda tiap run;
        // yang wajib adalah setiap tiket hanya diklaim sekali.
        const [responsA, responsB] = await Promise.all([
          panggilAntrean(petugasA.token, loketId),
          panggilAntrean(petugasB.token, idLoketB),
        ]);

        expect([responsA.status, responsB.status]).toEqual([200, 200]);

        const hasilA = responsA.body as {
          tiketId: string;
          loketId: string;
          status: StatusTiket;
          urutanMasukAntrean: number;
        };
        const hasilB = responsB.body as typeof hasilA;

        expect(hasilA.loketId).toBe(loketId);
        expect(hasilB.loketId).toBe(idLoketB);
        expect(hasilA.status).toBe(StatusTiket.DIPANGGIL);
        expect(hasilB.status).toBe(StatusTiket.DIPANGGIL);

        expect(
          [hasilA.tiketId, hasilB.tiketId].sort((a, b) => a.localeCompare(b)),
        ).toEqual(
          [tiketId, tiketKedua.id].sort((a, b) => a.localeCompare(b)),
        );
        expect([
          hasilA.urutanMasukAntrean,
          hasilB.urutanMasukAntrean,
        ].sort((a, b) => a - b)).toEqual([
          urutanPertama,
          tiketKedua.urutanMasukAntrean,
        ]);

        // Kedua tiket sudah keluar dari daftar MENUNGGU.
        const daftarTersisa = await daftarMenunggu().expect(200);
        expect(daftarTersisa.body).toEqual([]);

        const tiketDatabase = await db().tiketAntrean.findMany({
          where: { id: { in: [tiketId, tiketKedua.id] } },
          select: {
            id: true,
            status: true,
            loketId: true,
            dipanggilPada: true,
            urutanMasukAntrean: true,
          },
        });

        expect(tiketDatabase).toHaveLength(2);
        expect(
          tiketDatabase.every(
            (item) =>
              item.status === StatusTiket.DIPANGGIL &&
              item.dipanggilPada !== null,
          ),
        ).toBe(true);
        expect(
          tiketDatabase
            .map((item) => item.loketId ?? '')
            .sort((a, b) => a.localeCompare(b)),
        ).toEqual(
          [loketId, idLoketB].sort((a, b) => a.localeCompare(b)),
        );

        const audit = await db().peristiwaAntrean.findMany({
          where: {
            tiketAntreanId: { in: [tiketId, tiketKedua.id] },
            tipe: 'CALL',
          },
        });

        expect(audit).toHaveLength(2);
        expect(
          audit
            .map((item) => item.tiketAntreanId)
            .sort((a, b) => a.localeCompare(b)),
        ).toEqual(
          [tiketId, tiketKedua.id].sort((a, b) => a.localeCompare(b)),
        );
        expect(audit).toEqual(
          expect.arrayContaining([
            expect.objectContaining({
              tiketAntreanId: hasilA.tiketId,
              aktorId: petugasA.id,
              statusSebelum: StatusTiket.MENUNGGU,
              statusSesudah: StatusTiket.DIPANGGIL,
            }),
            expect.objectContaining({
              tiketAntreanId: hasilB.tiketId,
              aktorId: petugasB.id,
              statusSebelum: StatusTiket.MENUNGGU,
              statusSesudah: StatusTiket.DIPANGGIL,
            }),
          ]),
        );
      }, 30000);

      // ======================================
      // B. DUA LOKET BERSAING SATU TIKET
      // ======================================
      it('dua loket yang berebut satu tiket menghasilkan tepat satu CALL', async () => {
        await siapkanTiketCheckIn();
        await masukAntrean().expect(200);

        if (!loketKeduaId) {
          throw new Error('Loket kedua belum dibuat');
        }

        const [responsA, responsB] = await Promise.all([
          panggilAntrean(petugasA.token, loketId),
          panggilAntrean(petugasB.token, loketKeduaId),
        ]);

        const kodeStatus = [responsA.status, responsB.status];
        expect(kodeStatus.filter((status) => status === 200)).toHaveLength(1);
        expect(
          kodeStatus.filter((status) => status !== 200),
        ).toHaveLength(1);
        expect([404, 409]).toContain(
          kodeStatus.find((status) => status !== 200),
        );

        const tiket = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        expect(tiket.status).toBe(StatusTiket.DIPANGGIL);
        expect([loketId, loketKeduaId]).toContain(tiket.loketId);

        const audit = await db().peristiwaAntrean.findMany({
          where: { tiketAntreanId: tiketId, tipe: 'CALL' },
        });
        expect(audit).toHaveLength(1);

        const pemenang = responsA.status === 200 ? petugasA : petugasB;
        expect(audit[0].aktorId).toBe(pemenang.id);
      }, 30000);

      // ======================================
      // C. SCOPE PENUGASAN ANTARLOKET
      // ======================================
      it('PETUGAS A ditolak saat mencoba CALL pada loket B tanpa penugasan', async () => {
        if (!loketKeduaId) {
          throw new Error('Loket kedua belum dibuat');
        }

        await panggilAntrean(petugasA.token, loketKeduaId).expect(403);
      });
    });

    // ========================================
    // 01G-D.3-B — RECALL (E2E)
    // ========================================
    describe('RECALL Antrean (e2e)', () => {
      function panggilUlang(
        token: string = petugasA.token,
        idTiket: string = tiketId,
        idLoket: string = loketId,
      ) {
        return request(server())
          .post(`/api/v1/queue/${idTiket}/panggil-ulang`)
          .set('Authorization', `Bearer ${token}`)
          .send({ loketId: idLoket });
      }

      it('RECALL mempertahankan nomor, status, loket dan mencatat audit', async () => {
        await siapkanTiketCheckIn();
        await masukAntrean().expect(200);
        await panggilAntrean().expect(200);

        const sebelum = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });

        const response = await panggilUlang().expect(200);
        const hasil = response.body as {
          tiketId: string;
          nomorAntrean: string;
          status: StatusTiket;
          loketId: string;
          dipanggilPada: string;
          dipanggilUlangPada: string;
          versi: number;
        };

        expect(hasil.tiketId).toBe(tiketId);
        expect(hasil.status).toBe(StatusTiket.DIPANGGIL);
        expect(hasil.loketId).toBe(loketId);
        expect(hasil.nomorAntrean).toMatch(/^.+-\d{3,}$/);
        expect(hasil.versi).toBe(sebelum.versi + 1);
        expect(hasil.dipanggilPada).toBe(sebelum.dipanggilPada?.toISOString());
        expect(new Date(hasil.dipanggilUlangPada).getTime()).not.toBeNaN();

        const sesudah = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        expect(sesudah.status).toBe(StatusTiket.DIPANGGIL);
        expect(sesudah.nomorUrut).toBe(sebelum.nomorUrut);
        expect(sesudah.kodeTiket).toBe(sebelum.kodeTiket);
        expect(sesudah.loketId).toBe(sebelum.loketId);
        expect(sesudah.urutanMasukAntrean).toBe(sebelum.urutanMasukAntrean);
        expect(sesudah.dipanggilPada).toEqual(sebelum.dipanggilPada);
        expect(sesudah.versi).toBe(sebelum.versi + 1);

        const auditRecall = await db().peristiwaAntrean.findMany({
          where: { tiketAntreanId: tiketId, tipe: 'RECALL' },
        });
        expect(auditRecall).toHaveLength(1);
        expect(auditRecall[0]).toMatchObject({
          aktorId: petugasA.id,
          statusSebelum: StatusTiket.DIPANGGIL,
          statusSesudah: StatusTiket.DIPANGGIL,
        });
      }, 30000);

      it('dua RECALL menghasilkan dua audit dan nomor antrean tetap', async () => {
        await siapkanTiketCheckIn();
        await masukAntrean().expect(200);
        await panggilAntrean().expect(200);

        const sebelum = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });

        await panggilUlang().expect(200);
        await panggilUlang().expect(200);

        const sesudah = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        expect(sesudah.versi).toBe(sebelum.versi + 2);
        expect(sesudah.status).toBe(StatusTiket.DIPANGGIL);
        expect(sesudah.nomorUrut).toBe(sebelum.nomorUrut);
        expect(sesudah.dipanggilPada).toEqual(sebelum.dipanggilPada);
        expect(await db().peristiwaAntrean.count({
          where: { tiketAntreanId: tiketId, tipe: 'RECALL' },
        })).toBe(2);
        expect(await db().peristiwaAntrean.count({
          where: { tiketAntreanId: tiketId, tipe: 'CALL' },
        })).toBe(1);
      }, 30000);

      it('menolak RECALL oleh akun USER', async () => {
        await panggilUlang(userA.token).expect(403);
      });

      it('menolak RECALL sebelum tiket berstatus DIPANGGIL', async () => {
        await siapkanTiketCheckIn();
        await masukAntrean().expect(200);
        await panggilUlang().expect(409);
      }, 30000);

      it('menolak RECALL melalui loket yang bukan loket pemanggil', async () => {
        await siapkanTiketCheckIn();
        await masukAntrean().expect(200);
        await panggilAntrean().expect(200);
        await panggilUlang(petugasA.token, tiketId, randomUUID()).expect(403);
      }, 30000);
    });

    // ========================================
    // 01G-D.3-C — SKIP ANTREAN (E2E)
    // ========================================
    describe('SKIP Antrean (e2e)', () => {
      function lewatiAntrean(
        token: string = petugasA.token,
        idTiket: string = tiketId,
        idLoket: string = loketId,
      ) {
        return request(server())
          .post(`/api/v1/queue/${idTiket}/lewati`)
          .set('Authorization', `Bearer ${token}`)
          .send({ loketId: idLoket });
      }

      async function siapkanTiketDipanggil() {
        await siapkanTiketCheckIn();
        await masukAntrean().expect(200);
        await panggilAntrean().expect(200);
      }

      it('SKIP mengubah status, menjaga nomor tiket, dan mencatat audit', async () => {
        await siapkanTiketDipanggil();

        const sebelum = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        expect(sebelum.status).toBe(StatusTiket.DIPANGGIL);

        const respons = await lewatiAntrean().expect(200);
        const hasil = respons.body as {
          tiketId: string;
          loketId: string;
          nomorAntrean: string;
          status: StatusTiket;
          urutanMasukAntrean: number;
          dipanggilPada: string;
          dilewatiPada: string;
          versi: number;
        };

        expect(hasil.tiketId).toBe(tiketId);
        expect(hasil.loketId).toBe(loketId);
        expect(hasil.nomorAntrean).toMatch(/^.+-\d{3,}$/);
        expect(hasil.status).toBe(StatusTiket.DILEWATI);
        expect(hasil.urutanMasukAntrean).toBe(sebelum.urutanMasukAntrean);
        expect(hasil.dipanggilPada).toBe(sebelum.dipanggilPada?.toISOString());
        expect(new Date(hasil.dilewatiPada).getTime()).not.toBeNaN();
        expect(hasil.versi).toBe(sebelum.versi + 1);

        const sesudah = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        expect(sesudah.status).toBe(StatusTiket.DILEWATI);
        expect(sesudah.versi).toBe(sebelum.versi + 1);
        expect(sesudah.nomorUrut).toBe(sebelum.nomorUrut);
        expect(sesudah.kodeTiket).toBe(sebelum.kodeTiket);
        expect(sesudah.loketId).toBe(sebelum.loketId);
        expect(sesudah.dipanggilPada).toEqual(sebelum.dipanggilPada);
        expect(sesudah.urutanMasukAntrean).toBe(sebelum.urutanMasukAntrean);

        const audit = await db().peristiwaAntrean.findMany({
          where: { tiketAntreanId: tiketId, tipe: 'SKIP' },
        });
        expect(audit).toHaveLength(1);
        expect(audit[0]).toMatchObject({
          aktorId: petugasA.id,
          statusSebelum: StatusTiket.DIPANGGIL,
          statusSesudah: StatusTiket.DILEWATI,
          dataTambahan: { metode: 'QUEUE_SKIP', loketId },
        });
      }, 30000);

      it('menolak SKIP tanpa JWT atau oleh USER', async () => {
        await request(server())
          .post(`/api/v1/queue/${tiketId}/lewati`)
          .send({ loketId })
          .expect(401);
        await lewatiAntrean(userA.token).expect(403);
      });

      it('menolak SKIP jika tiket belum DIPANGGIL', async () => {
        await siapkanTiketCheckIn();
        await masukAntrean().expect(200);
        await lewatiAntrean().expect(409);
        expect(await db().peristiwaAntrean.count({
          where: { tiketAntreanId: tiketId, tipe: 'SKIP' },
        })).toBe(0);
      }, 30000);

      it('menolak SKIP dari loket yang berbeda', async () => {
        await siapkanTiketDipanggil();
        await lewatiAntrean(petugasA.token, tiketId, randomUUID()).expect(403);
        const tiket = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        expect(tiket.status).toBe(StatusTiket.DIPANGGIL);
      }, 30000);

      it('menolak SKIP jika penugasan petugas tidak aktif', async () => {
        await siapkanTiketDipanggil();
        const where = { petugasId: petugasA.id, loketId };
        await db().penugasanPetugas.updateMany({
          where,
          data: { aktif: false },
        });
        try {
          await lewatiAntrean().expect(403);
        } finally {
          await db().penugasanPetugas.updateMany({
            where,
            data: { aktif: true },
          });
        }
        const tiket = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        expect(tiket.status).toBe(StatusTiket.DIPANGGIL);
      }, 30000);

      it('menolak SKIP kedua dan mencegah audit ganda', async () => {
        await siapkanTiketDipanggil();
        const sebelum = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        await lewatiAntrean().expect(200);
        await lewatiAntrean().expect(409);

        const sesudah = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        expect(sesudah.status).toBe(StatusTiket.DILEWATI);
        expect(sesudah.versi).toBe(sebelum.versi + 1);
        expect(await db().peristiwaAntrean.count({
          where: { tiketAntreanId: tiketId, tipe: 'SKIP' },
        })).toBe(1);
      }, 30000);

      it('dua SKIP bersamaan hanya menghasilkan satu perubahan dan audit', async () => {
        await siapkanTiketDipanggil();
        const sebelum = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });

        const [responsA, responsB] = await Promise.all([
          lewatiAntrean(petugasA.token),
          lewatiAntrean(petugasB.token),
        ]);
        const status = [responsA.status, responsB.status].sort((a, b) => a - b);
        expect(status).toEqual([200, 409]);

        const sesudah = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        expect(sesudah.status).toBe(StatusTiket.DILEWATI);
        expect(sesudah.versi).toBe(sebelum.versi + 1);
        const audit = await db().peristiwaAntrean.findMany({
          where: { tiketAntreanId: tiketId, tipe: 'SKIP' },
        });
        expect(audit).toHaveLength(1);
        const pemenang = responsA.status === 200 ? petugasA : petugasB;
        expect(audit[0].aktorId).toBe(pemenang.id);
      }, 30000);

      it('rollback perubahan tiket jika audit SKIP gagal', async () => {
        await siapkanTiketDipanggil();

        // Pengujian DDL hanya boleh berjalan pada database E2E lokal.
        const koneksi = process.env.DATABASE_URL;
        if (!koneksi) {
          throw new Error('DATABASE_URL testing belum ditentukan');
        }
        const url = new URL(koneksi);
        if (
          url.pathname !== '/capstone_antrean_test' ||
          !['localhost', '127.0.0.1'].includes(url.hostname) ||
          url.port !== '5433'
        ) {
          throw new Error('Rollback SKIP hanya boleh menggunakan database testing lokal');
        }
        const database = await db().$queryRaw<
          Array<{ namaDatabase: string }>
        >`SELECT current_database() AS "namaDatabase"`;
        expect(database[0]?.namaDatabase).toBe('capstone_antrean_test');
        if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(tiketId)) {
          throw new Error('UUID tiket E2E tidak valid');
        }

        const sebelum = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        expect(sebelum.status).toBe(StatusTiket.DIPANGGIL);
        const namaConstraint = `e2e_skip_rollback_${randomBytes(6).toString('hex')}`;
        let constraintTerpasang = false;
        try {
          await db().$executeRawUnsafe(
            `ALTER TABLE "public"."peristiwa_antrean"
             ADD CONSTRAINT "${namaConstraint}"
             CHECK (NOT (
               "tiket_antrean_id" = '${tiketId}'::uuid
               AND "tipe" = 'SKIP'
             ))`,
          );
          constraintTerpasang = true;

          // Insert audit sengaja gagal; HTTP 500 menunjukkan transaksi dibatalkan.
          await lewatiAntrean().expect(500);
        } finally {
          if (constraintTerpasang) {
            await db().$executeRawUnsafe(
              `ALTER TABLE "public"."peristiwa_antrean"
               DROP CONSTRAINT IF EXISTS "${namaConstraint}"`,
            );
          }
        }

        const sesudah = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        expect(sesudah.status).toBe(StatusTiket.DIPANGGIL);
        expect(sesudah.versi).toBe(sebelum.versi);
        expect(sesudah.loketId).toBe(sebelum.loketId);
        expect(sesudah.dipanggilPada).toEqual(sebelum.dipanggilPada);
        expect(sesudah.urutanMasukAntrean).toBe(sebelum.urutanMasukAntrean);
        expect(sesudah.nomorUrut).toBe(sebelum.nomorUrut);
        expect(sesudah.kodeTiket).toBe(sebelum.kodeTiket);
        expect(await db().peristiwaAntrean.count({
          where: { tiketAntreanId: tiketId, tipe: 'SKIP' },
        })).toBe(0);
      }, 30000);

      it('loket dapat CALL tiket berikutnya setelah SKIP', async () => {
        await siapkanTiketDipanggil();
        await lewatiAntrean().expect(200);
        let tiketKeduaId: string | null = null;

        try {
          const counter = await db().urutanAntreanHarian.update({
            where: { layananId_tanggal: { layananId, tanggal: hariIniDb } },
            data: { nomorTerakhir: { increment: 1 } },
          });
          const tiketKedua = await db().tiketAntrean.create({
            data: {
              penggunaId: userB.id,
              layananId,
              loketId,
              tanggalAntrean: hariIniDb,
              nomorUrut: counter.nomorTerakhir,
              kodeTiket: `TK${randomBytes(12).toString('hex').toUpperCase()}`,
              status: StatusTiket.CHECK_IN,
              checkInPada: new Date(),
            },
          });
          tiketKeduaId = tiketKedua.id;
          await masukAntrean(tiketKedua.id).expect(200);

          const respons = await panggilAntrean().expect(200);
          const hasil = respons.body as {
            tiketId: string;
            status: StatusTiket;
            loketId: string;
          };
          expect(hasil.tiketId).toBe(tiketKedua.id);
          expect(hasil.status).toBe(StatusTiket.DIPANGGIL);
          expect(hasil.loketId).toBe(loketId);
          const pertama = await db().tiketAntrean.findUniqueOrThrow({
            where: { id: tiketId },
          });
          expect(pertama.status).toBe(StatusTiket.DILEWATI);
        } finally {
          if (tiketKeduaId) {
            await db().peristiwaAntrean.deleteMany({
              where: { tiketAntreanId: tiketKeduaId },
            });
            await db().tiketAntrean.deleteMany({
              where: { id: tiketKeduaId },
            });
          }
        }
      }, 30000);
    });


    // ========================================
    // 01G-D.3-D — REQUEUE (E2E)
    // ========================================
    describe('REQUEUE Antrean (e2e)', () => {
      function antreUlang(
        token: string = petugasA.token,
        idTiket: string = tiketId,
        idLoket: string = loketId,
      ) {
        return request(server())
          .post(`/api/v1/queue/${idTiket}/antre-ulang`)
          .set('Authorization', `Bearer ${token}`)
          .send({ loketId: idLoket });
      }

      async function siapkanTiketDilewati() {
        await siapkanTiketCheckIn();
        await masukAntrean().expect(200);
        await panggilAntrean().expect(200);
        await request(server())
          .post(`/api/v1/queue/${tiketId}/lewati`)
          .set('Authorization', `Bearer ${petugasA.token}`)
          .send({ loketId })
          .expect(200);
      }

      it('REQUEUE memindahkan tiket ke belakang FIFO, menjaga nomor dan audit', async () => {
        await siapkanTiketDilewati();
        let tiketKeduaId: string | null = null;
        try {
          // Buat tiket menunggu kedua agar posisi paling belakang dapat diverifikasi.
          const nomor = await db().urutanAntreanHarian.update({
            where: { layananId_tanggal: { layananId, tanggal: hariIniDb } },
            data: { nomorTerakhir: { increment: 1 } },
          });
          const tiketKedua = await db().tiketAntrean.create({
            data: {
              penggunaId: userB.id,
              layananId,
              loketId,
              tanggalAntrean: hariIniDb,
              nomorUrut: nomor.nomorTerakhir,
              kodeTiket: `TK${randomBytes(12).toString('hex').toUpperCase()}`,
              status: StatusTiket.CHECK_IN,
              checkInPada: new Date(),
            },
          });
          tiketKeduaId = tiketKedua.id;
          const responsMasuk = await masukAntrean(tiketKeduaId).expect(200);
          const urutanKedua = (responsMasuk.body as { urutanMasukAntrean: number }).urutanMasukAntrean;

          const sebelum = await db().tiketAntrean.findUniqueOrThrow({ where: { id: tiketId } });
          const counterSebelum = await db().urutanAntreanHarian.findUniqueOrThrow({
            where: { layananId_tanggal: { layananId, tanggal: hariIniDb } },
          });
          expect(sebelum.status).toBe(StatusTiket.DILEWATI);

          const response = await antreUlang().expect(200);
          const hasil = response.body as {
            tiketId: string;
            status: StatusTiket;
            nomorAntrean: string;
            loketId: string | null;
            urutanMasukSebelumnya: number;
            urutanMasukAntrean: number;
            versi: number;
          };
          expect(hasil.tiketId).toBe(tiketId);
          expect(hasil.status).toBe(StatusTiket.MENUNGGU);
          expect(hasil.loketId).toBeNull();
          expect(hasil.urutanMasukSebelumnya).toBe(sebelum.urutanMasukAntrean);
          expect(hasil.urutanMasukAntrean).toBe(counterSebelum.urutanMasukTerakhir + 1);
          expect(hasil.urutanMasukAntrean).toBeGreaterThan(urutanKedua);
          expect(hasil.versi).toBe(sebelum.versi + 1);
          expect(hasil.nomorAntrean).toBe(`Q-${String(nomorUrut).padStart(3, '0')}`);

          const sesudah = await db().tiketAntrean.findUniqueOrThrow({ where: { id: tiketId } });
          expect(sesudah.status).toBe(StatusTiket.MENUNGGU);
          expect(sesudah.loketId).toBeNull();
          expect(sesudah.dipanggilPada).toBeNull();
          expect(sesudah.masukAntreanPada).not.toEqual(sebelum.masukAntreanPada);
          expect(sesudah.urutanMasukAntrean).toBe(hasil.urutanMasukAntrean);
          expect(sesudah.nomorUrut).toBe(sebelum.nomorUrut);
          expect(sesudah.kodeTiket).toBe(sebelum.kodeTiket);

          const daftar = await daftarMenunggu().expect(200);
          const hasilDaftar = daftar.body as Array<{ tiketId: string }>;
          expect(hasilDaftar.map((item) => item.tiketId)).toEqual([tiketKeduaId, tiketId]);

          const audit = await db().peristiwaAntrean.findMany({
            where: { tiketAntreanId: tiketId, tipe: 'REQUEUE' },
          });
          expect(audit).toHaveLength(1);
          expect(audit[0]).toMatchObject({
            aktorId: petugasA.id,
            statusSebelum: StatusTiket.DILEWATI,
            statusSesudah: StatusTiket.MENUNGGU,
            dataTambahan: {
              metode: 'QUEUE_REQUEUE',
              urutanMasukSebelumnya: sebelum.urutanMasukAntrean,
              urutanMasukSesudah: hasil.urutanMasukAntrean,
            },
          });

          // CALL berikutnya tetap mendahulukan tiket kedua.
          const dipanggil = await panggilAntrean().expect(200);
          expect((dipanggil.body as { tiketId: string }).tiketId).toBe(tiketKeduaId);
        } finally {
          if (tiketKeduaId) {
            await db().peristiwaAntrean.deleteMany({ where: { tiketAntreanId: tiketKeduaId } });
            await db().tiketAntrean.deleteMany({ where: { id: tiketKeduaId } });
          }
        }
      }, 30000);

      it('menolak REQUEUE tanpa JWT serta dari USER', async () => {
        await request(server())
          .post(`/api/v1/queue/${tiketId}/antre-ulang`)
          .send({ loketId })
          .expect(401);
        await antreUlang(userA.token).expect(403);
      });

      it('menolak REQUEUE saat tiket masih MENUNGGU', async () => {
        await siapkanTiketCheckIn();
        await masukAntrean().expect(200);
        await antreUlang().expect(409);
        expect(await db().peristiwaAntrean.count({
          where: { tiketAntreanId: tiketId, tipe: 'REQUEUE' },
        })).toBe(0);
      }, 30000);

      it('menolak REQUEUE untuk loket yang tidak sesuai', async () => {
        await siapkanTiketDilewati();
        await antreUlang(petugasA.token, tiketId, randomUUID()).expect(403);
        const tiket = await db().tiketAntrean.findUniqueOrThrow({ where: { id: tiketId } });
        expect(tiket.status).toBe(StatusTiket.DILEWATI);
      }, 30000);

      it('menolak REQUEUE jika penugasan PETUGAS tidak aktif', async () => {
        await siapkanTiketDilewati();
        const where = { petugasId: petugasA.id, loketId };
        await db().penugasanPetugas.updateMany({ where, data: { aktif: false } });
        try {
          await antreUlang().expect(403);
        } finally {
          await db().penugasanPetugas.updateMany({ where, data: { aktif: true } });
        }
        const tiket = await db().tiketAntrean.findUniqueOrThrow({ where: { id: tiketId } });
        expect(tiket.status).toBe(StatusTiket.DILEWATI);
      }, 30000);

      it('REQUEUE kedua ditolak tanpa menaikkan counter atau menduplikasi audit', async () => {
        await siapkanTiketDilewati();
        await antreUlang().expect(200);
        const counterSebelum = await db().urutanAntreanHarian.findUniqueOrThrow({
          where: { layananId_tanggal: { layananId, tanggal: hariIniDb } },
        });
        await antreUlang().expect(409);
        const counterSesudah = await db().urutanAntreanHarian.findUniqueOrThrow({
          where: { layananId_tanggal: { layananId, tanggal: hariIniDb } },
        });
        expect(counterSesudah.urutanMasukTerakhir).toBe(counterSebelum.urutanMasukTerakhir);
        expect(await db().peristiwaAntrean.count({
          where: { tiketAntreanId: tiketId, tipe: 'REQUEUE' },
        })).toBe(1);
      }, 30000);

      it('dua REQUEUE bersamaan hanya boleh mengubah antrean satu kali', async () => {
        await siapkanTiketDilewati();
        const sebelum = await db().tiketAntrean.findUniqueOrThrow({ where: { id: tiketId } });
        const counterSebelum = await db().urutanAntreanHarian.findUniqueOrThrow({
          where: { layananId_tanggal: { layananId, tanggal: hariIniDb } },
        });
        const [responsA, responsB] = await Promise.all([
          antreUlang(petugasA.token),
          antreUlang(petugasB.token),
        ]);
        const hasil = [responsA.status, responsB.status].sort((a, b) => a - b);
        expect(hasil).toEqual([200, 409]);
        const sesudah = await db().tiketAntrean.findUniqueOrThrow({ where: { id: tiketId } });
        const counterSesudah = await db().urutanAntreanHarian.findUniqueOrThrow({
          where: { layananId_tanggal: { layananId, tanggal: hariIniDb } },
        });
        expect(sesudah.status).toBe(StatusTiket.MENUNGGU);
        expect(sesudah.versi).toBe(sebelum.versi + 1);
        expect(counterSesudah.urutanMasukTerakhir).toBe(counterSebelum.urutanMasukTerakhir + 1);
        const audit = await db().peristiwaAntrean.findMany({
          where: { tiketAntreanId: tiketId, tipe: 'REQUEUE' },
        });
        expect(audit).toHaveLength(1);
        const petugasBerhasil = responsA.status === 200 ? petugasA.id : petugasB.id;
        expect(audit[0].aktorId).toBe(petugasBerhasil);
      }, 30000);

      it('rollback REQUEUE mengembalikan status, loket dan counter jika audit gagal', async () => {
        await siapkanTiketDilewati();
        const databaseUrl = process.env.DATABASE_URL;
        if (!databaseUrl) throw new Error('DATABASE_URL testing tidak ada');
        const url = new URL(databaseUrl);
        if (
          url.pathname !== '/capstone_antrean_test' ||
          !['localhost', '127.0.0.1'].includes(url.hostname) ||
          url.port !== '5433'
        ) throw new Error('Rollback hanya boleh berjalan pada PostgreSQL testing lokal');
        const database = await db().$queryRaw<
          Array<{ namaDatabase: string }>
        >`SELECT current_database() AS "namaDatabase"`;
        expect(database[0]?.namaDatabase).toBe('capstone_antrean_test');
        if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(tiketId)) {
          throw new Error('UUID pengujian tidak valid');
        }
        const sebelum = await db().tiketAntrean.findUniqueOrThrow({ where: { id: tiketId } });
        const counterSebelum = await db().urutanAntreanHarian.findUniqueOrThrow({
          where: { layananId_tanggal: { layananId, tanggal: hariIniDb } },
        });
        const namaConstraint = `e2e_requeue_rollback_${randomBytes(6).toString('hex')}`;
        let terpasang = false;
        try {
          await db().$executeRawUnsafe(
            `ALTER TABLE "public"."peristiwa_antrean"
             ADD CONSTRAINT "${namaConstraint}"
             CHECK (NOT (
               "tiket_antrean_id" = '${tiketId}'::uuid
               AND "tipe" = 'REQUEUE'
             ))`,
          );
          terpasang = true;
          await antreUlang().expect(500);
        } finally {
          if (terpasang) {
            await db().$executeRawUnsafe(
              `ALTER TABLE "public"."peristiwa_antrean"
               DROP CONSTRAINT IF EXISTS "${namaConstraint}"`,
            );
          }
        }
        const sesudah = await db().tiketAntrean.findUniqueOrThrow({ where: { id: tiketId } });
        const counterSesudah = await db().urutanAntreanHarian.findUniqueOrThrow({
          where: { layananId_tanggal: { layananId, tanggal: hariIniDb } },
        });
        expect(sesudah.status).toBe(StatusTiket.DILEWATI);
        expect(sesudah.versi).toBe(sebelum.versi);
        expect(sesudah.loketId).toBe(sebelum.loketId);
        expect(sesudah.dipanggilPada).toEqual(sebelum.dipanggilPada);
        expect(sesudah.urutanMasukAntrean).toBe(sebelum.urutanMasukAntrean);
        expect(sesudah.masukAntreanPada).toEqual(sebelum.masukAntreanPada);
        expect(sesudah.nomorUrut).toBe(sebelum.nomorUrut);
        expect(sesudah.kodeTiket).toBe(sebelum.kodeTiket);
        expect(counterSesudah.urutanMasukTerakhir).toBe(counterSebelum.urutanMasukTerakhir);
        expect(await db().peristiwaAntrean.count({
          where: { tiketAntreanId: tiketId, tipe: 'REQUEUE' },
        })).toBe(0);
      }, 30000);

      it('setelah REQUEUE tiket dapat dipanggil kembali tanpa membuat tiket baru', async () => {
        await siapkanTiketDilewati();
        const sebelum = await db().tiketAntrean.findUniqueOrThrow({ where: { id: tiketId } });
        await antreUlang().expect(200);
        const response = await panggilAntrean().expect(200);
        const hasil = response.body as { tiketId: string; status: StatusTiket; loketId: string };
        expect(hasil.tiketId).toBe(tiketId);
        expect(hasil.status).toBe(StatusTiket.DIPANGGIL);
        expect(hasil.loketId).toBe(loketId);
        const sesudah = await db().tiketAntrean.findUniqueOrThrow({ where: { id: tiketId } });
        expect(sesudah.nomorUrut).toBe(sebelum.nomorUrut);
        expect(sesudah.kodeTiket).toBe(sebelum.kodeTiket);
        expect(sesudah.urutanMasukAntrean).toBeGreaterThan(sebelum.urutanMasukAntrean ?? 0);
        expect(await db().peristiwaAntrean.count({
          where: { tiketAntreanId: tiketId, tipe: 'CALL' },
        })).toBe(2);
      }, 30000);
    });

    // ========================================
    // 01G-D.3-E — START PELAYANAN (E2E)
    // ========================================
    describe('START Pelayanan (e2e)', () => {
      function mulaiPelayanan(
        token: string = petugasA.token,
        idTiket: string = tiketId,
        idLoket: string = loketId,
      ) {
        return request(server())
          .post(`/api/v1/queue/${idTiket}/mulai-pelayanan`)
          .set('Authorization', `Bearer ${token}`)
          .send({ loketId: idLoket });
      }

      async function siapkanTiketDipanggil() {
        await siapkanTiketCheckIn();
        await masukAntrean().expect(200);
        await panggilAntrean().expect(200);
      }

      it('START mengubah DIPANGGIL menjadi DILAYANI, mencatat waktu dan audit', async () => {
        await siapkanTiketDipanggil();
        const sebelum = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        expect(sebelum.status).toBe(StatusTiket.DIPANGGIL);
        expect(sebelum.pelayananDimulaiPada).toBeNull();

        const respons = await mulaiPelayanan().expect(200);
        const hasil = respons.body as {
          tiketId: string;
          layananId: string;
          loketId: string;
          kodeLoket: string;
          nomorAntrean: string;
          status: StatusTiket;
          urutanMasukAntrean: number;
          dipanggilPada: string;
          pelayananDimulaiPada: string;
          versi: number;
        };
        expect(hasil).toMatchObject({
          tiketId,
          layananId,
          loketId,
          status: StatusTiket.DILAYANI,
          urutanMasukAntrean: sebelum.urutanMasukAntrean,
          versi: sebelum.versi + 1,
          nomorAntrean: `Q-${String(nomorUrut).padStart(3, '0')}`,
          dipanggilPada: sebelum.dipanggilPada?.toISOString(),
        });
        expect(new Date(hasil.pelayananDimulaiPada).getTime()).not.toBeNaN();

        const sesudah = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        expect(sesudah.status).toBe(StatusTiket.DILAYANI);
        expect(sesudah.pelayananDimulaiPada?.toISOString()).toBe(
          hasil.pelayananDimulaiPada,
        );
        expect(sesudah.pelayananSelesaiPada).toBeNull();
        expect(sesudah.versi).toBe(sebelum.versi + 1);
        expect(sesudah.nomorUrut).toBe(sebelum.nomorUrut);
        expect(sesudah.kodeTiket).toBe(sebelum.kodeTiket);
        expect(sesudah.urutanMasukAntrean).toBe(sebelum.urutanMasukAntrean);
        expect(sesudah.dipanggilPada).toEqual(sebelum.dipanggilPada);
        expect(sesudah.loketId).toBe(loketId);

        const audit = await db().peristiwaAntrean.findMany({
          where: { tiketAntreanId: tiketId, tipe: 'START_SERVICE' },
        });
        expect(audit).toHaveLength(1);
        expect(audit[0]).toMatchObject({
          aktorId: petugasA.id,
          statusSebelum: StatusTiket.DIPANGGIL,
          statusSesudah: StatusTiket.DILAYANI,
          dataTambahan: {
            metode: 'QUEUE_START_SERVICE',
            loketId,
            urutanMasukAntrean: sebelum.urutanMasukAntrean,
          },
        });
      }, 30000);

      it('menolak START tanpa JWT dan dari akun USER', async () => {
        await request(server())
          .post(`/api/v1/queue/${tiketId}/mulai-pelayanan`)
          .send({ loketId })
          .expect(401);
        await mulaiPelayanan(userA.token).expect(403);
      });

      it('menolak START ketika tiket masih MENUNGGU', async () => {
        await siapkanTiketCheckIn();
        await masukAntrean().expect(200);
        await mulaiPelayanan().expect(409);
        const tiket = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        expect(tiket.status).toBe(StatusTiket.MENUNGGU);
        expect(tiket.pelayananDimulaiPada).toBeNull();
        expect(await db().peristiwaAntrean.count({
          where: { tiketAntreanId: tiketId, tipe: 'START_SERVICE' },
        })).toBe(0);
      }, 30000);

      it('menolak START melalui loket berbeda tanpa mengubah tiket', async () => {
        await siapkanTiketDipanggil();
        const sebelum = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        await mulaiPelayanan(petugasA.token, tiketId, randomUUID()).expect(403);
        const sesudah = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        expect(sesudah.status).toBe(StatusTiket.DIPANGGIL);
        expect(sesudah.versi).toBe(sebelum.versi);
        expect(sesudah.pelayananDimulaiPada).toBeNull();
      }, 30000);

      it('menolak START jika penugasan PETUGAS tidak aktif', async () => {
        await siapkanTiketDipanggil();
        const where = { petugasId: petugasA.id, loketId };
        await db().penugasanPetugas.updateMany({
          where,
          data: { aktif: false },
        });
        try {
          await mulaiPelayanan().expect(403);
        } finally {
          await db().penugasanPetugas.updateMany({
            where,
            data: { aktif: true },
          });
        }
        const tiket = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        expect(tiket.status).toBe(StatusTiket.DIPANGGIL);
        expect(tiket.pelayananDimulaiPada).toBeNull();
      }, 30000);

      it('menolak START kedua tanpa membuat audit atau versi ganda', async () => {
        await siapkanTiketDipanggil();
        const sebelum = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        await mulaiPelayanan().expect(200);
        await mulaiPelayanan().expect(409);
        const sesudah = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        expect(sesudah.status).toBe(StatusTiket.DILAYANI);
        expect(sesudah.versi).toBe(sebelum.versi + 1);
        expect(await db().peristiwaAntrean.count({
          where: { tiketAntreanId: tiketId, tipe: 'START_SERVICE' },
        })).toBe(1);
      }, 30000);

      it('dua START bersamaan hanya dapat berhasil sekali', async () => {
        await siapkanTiketDipanggil();
        const sebelum = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        const [responsA, responsB] = await Promise.all([
          mulaiPelayanan(petugasA.token),
          mulaiPelayanan(petugasB.token),
        ]);
        const status = [responsA.status, responsB.status].sort((a, b) => a - b);
        expect(status).toEqual([200, 409]);
        const sesudah = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        expect(sesudah.status).toBe(StatusTiket.DILAYANI);
        expect(sesudah.versi).toBe(sebelum.versi + 1);
        const audit = await db().peristiwaAntrean.findMany({
          where: { tiketAntreanId: tiketId, tipe: 'START_SERVICE' },
        });
        expect(audit).toHaveLength(1);
        const pemenang = responsA.status === 200 ? petugasA.id : petugasB.id;
        expect(audit[0].aktorId).toBe(pemenang);
      }, 30000);

      it('menolak CALL berikutnya ketika loket sedang melayani tiket DILAYANI', async () => {
        await siapkanTiketDipanggil();
        await mulaiPelayanan().expect(200);
        await panggilAntrean().expect(409);
        const tiket = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        expect(tiket.status).toBe(StatusTiket.DILAYANI);
        expect(await db().peristiwaAntrean.count({
          where: { tiketAntreanId: tiketId, tipe: 'CALL' },
        })).toBe(1);
      }, 30000);

      it('rollback START mengembalikan status, waktu dan versi ketika audit gagal', async () => {
        await siapkanTiketDipanggil();
        const databaseUrl = process.env.DATABASE_URL;
        if (!databaseUrl) {
          throw new Error('DATABASE_URL testing tidak ada');
        }
        const url = new URL(databaseUrl);
        if (
          url.pathname !== '/capstone_antrean_test' ||
          !['localhost', '127.0.0.1'].includes(url.hostname) ||
          url.port !== '5433'
        ) {
          throw new Error('Rollback START hanya boleh pada PostgreSQL testing lokal');
        }
        const database = await db().$queryRaw<
          Array<{ namaDatabase: string }>
        >`SELECT current_database() AS "namaDatabase"`;
        expect(database[0]?.namaDatabase).toBe('capstone_antrean_test');
        if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(tiketId)) {
          throw new Error('UUID pengujian START tidak valid');
        }

        const sebelum = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        expect(sebelum.status).toBe(StatusTiket.DIPANGGIL);
        const namaConstraint = `e2e_start_rollback_${randomBytes(6).toString('hex')}`;
        let terpasang = false;
        try {
          await db().$executeRawUnsafe(
            `ALTER TABLE "public"."peristiwa_antrean"
             ADD CONSTRAINT "${namaConstraint}"
             CHECK (NOT (
               "tiket_antrean_id" = '${tiketId}'::uuid
               AND "tipe" = 'START_SERVICE'
             ))`,
          );
          terpasang = true;
          await mulaiPelayanan().expect(500);
        } finally {
          if (terpasang) {
            await db().$executeRawUnsafe(
              `ALTER TABLE "public"."peristiwa_antrean"
               DROP CONSTRAINT IF EXISTS "${namaConstraint}"`,
            );
          }
        }

        const sesudah = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        expect(sesudah.status).toBe(StatusTiket.DIPANGGIL);
        expect(sesudah.versi).toBe(sebelum.versi);
        expect(sesudah.pelayananDimulaiPada).toEqual(sebelum.pelayananDimulaiPada);
        expect(sesudah.pelayananSelesaiPada).toEqual(sebelum.pelayananSelesaiPada);
        expect(sesudah.loketId).toBe(sebelum.loketId);
        expect(sesudah.dipanggilPada).toEqual(sebelum.dipanggilPada);
        expect(sesudah.urutanMasukAntrean).toBe(sebelum.urutanMasukAntrean);
        expect(sesudah.nomorUrut).toBe(sebelum.nomorUrut);
        expect(sesudah.kodeTiket).toBe(sebelum.kodeTiket);
        expect(await db().peristiwaAntrean.count({
          where: { tiketAntreanId: tiketId, tipe: 'START_SERVICE' },
        })).toBe(0);
      }, 30000);
    });

    // ========================================
    // 01G-D.3-F — COMPLETE PELAYANAN (E2E)
    // ========================================
    describe('COMPLETE Pelayanan (e2e)', () => {
      function selesaikanPelayanan(
        token: string = petugasA.token,
        idTiket: string = tiketId,
        idLoket: string = loketId,
      ) {
        return request(server())
          .post(`/api/v1/queue/${idTiket}/selesaikan-pelayanan`)
          .set('Authorization', `Bearer ${token}`)
          .send({ loketId: idLoket });
      }

      async function siapkanTiketDilayani() {
        await siapkanTiketCheckIn();
        await masukAntrean().expect(200);
        await panggilAntrean().expect(200);
        await request(server())
          .post(`/api/v1/queue/${tiketId}/mulai-pelayanan`)
          .set('Authorization', `Bearer ${petugasA.token}`)
          .send({ loketId })
          .expect(200);
      }

      it('COMPLETE mengubah DILAYANI menjadi SELESAI, mencatat waktu dan audit', async () => {
        await siapkanTiketDilayani();
        const sebelum = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        expect(sebelum.status).toBe(StatusTiket.DILAYANI);
        expect(sebelum.pelayananDimulaiPada).not.toBeNull();
        expect(sebelum.pelayananSelesaiPada).toBeNull();

        const respons = await selesaikanPelayanan().expect(200);
        const hasil = respons.body as {
          tiketId: string;
          layananId: string;
          loketId: string;
          nomorAntrean: string;
          status: StatusTiket;
          urutanMasukAntrean: number;
          pelayananDimulaiPada: string;
          pelayananSelesaiPada: string;
          versi: number;
        };
        expect(hasil).toMatchObject({
          tiketId,
          layananId,
          loketId,
          nomorAntrean: `Q-${String(nomorUrut).padStart(3, '0')}`,
          status: StatusTiket.SELESAI,
          urutanMasukAntrean: sebelum.urutanMasukAntrean,
          pelayananDimulaiPada: sebelum.pelayananDimulaiPada?.toISOString(),
          versi: sebelum.versi + 1,
        });
        expect(new Date(hasil.pelayananSelesaiPada).getTime()).not.toBeNaN();
        expect(new Date(hasil.pelayananSelesaiPada).getTime()).toBeGreaterThanOrEqual(
          sebelum.pelayananDimulaiPada?.getTime() ?? 0,
        );

        const sesudah = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        expect(sesudah.status).toBe(StatusTiket.SELESAI);
        expect(sesudah.pelayananSelesaiPada?.toISOString()).toBe(
          hasil.pelayananSelesaiPada,
        );
        expect(sesudah.pelayananDimulaiPada).toEqual(sebelum.pelayananDimulaiPada);
        expect(sesudah.versi).toBe(sebelum.versi + 1);
        expect(sesudah.nomorUrut).toBe(sebelum.nomorUrut);
        expect(sesudah.kodeTiket).toBe(sebelum.kodeTiket);
        expect(sesudah.urutanMasukAntrean).toBe(sebelum.urutanMasukAntrean);
        expect(sesudah.dipanggilPada).toEqual(sebelum.dipanggilPada);
        expect(sesudah.loketId).toBe(loketId);

        const audit = await db().peristiwaAntrean.findMany({
          where: { tiketAntreanId: tiketId, tipe: 'COMPLETE' },
        });
        expect(audit).toHaveLength(1);
        expect(audit[0]).toMatchObject({
          aktorId: petugasA.id,
          statusSebelum: StatusTiket.DILAYANI,
          statusSesudah: StatusTiket.SELESAI,
          dataTambahan: {
            metode: 'QUEUE_COMPLETE_SERVICE',
            loketId,
            pelayananDimulaiPada: sebelum.pelayananDimulaiPada?.toISOString(),
            pelayananSelesaiPada: hasil.pelayananSelesaiPada,
          },
        });
      }, 30000);

      it('menolak COMPLETE tanpa JWT dan dari akun USER', async () => {
        await request(server())
          .post(`/api/v1/queue/${tiketId}/selesaikan-pelayanan`)
          .send({ loketId })
          .expect(401);
        await selesaikanPelayanan(userA.token).expect(403);
      });

      it('menolak COMPLETE sebelum START, saat tiket masih DIPANGGIL', async () => {
        await siapkanTiketCheckIn();
        await masukAntrean().expect(200);
        await panggilAntrean().expect(200);
        await selesaikanPelayanan().expect(409);
        const tiket = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        expect(tiket.status).toBe(StatusTiket.DIPANGGIL);
        expect(tiket.pelayananSelesaiPada).toBeNull();
        expect(await db().peristiwaAntrean.count({
          where: { tiketAntreanId: tiketId, tipe: 'COMPLETE' },
        })).toBe(0);
      }, 30000);

      it('menolak COMPLETE dari loket berbeda tanpa perubahan tiket', async () => {
        await siapkanTiketDilayani();
        const sebelum = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        await selesaikanPelayanan(petugasA.token, tiketId, randomUUID()).expect(403);
        const sesudah = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        expect(sesudah.status).toBe(StatusTiket.DILAYANI);
        expect(sesudah.versi).toBe(sebelum.versi);
        expect(sesudah.pelayananSelesaiPada).toBeNull();
      }, 30000);

      it('menolak COMPLETE ketika penugasan PETUGAS tidak aktif', async () => {
        await siapkanTiketDilayani();
        const where = { petugasId: petugasA.id, loketId };
        await db().penugasanPetugas.updateMany({
          where,
          data: { aktif: false },
        });
        try {
          await selesaikanPelayanan().expect(403);
        } finally {
          await db().penugasanPetugas.updateMany({
            where,
            data: { aktif: true },
          });
        }
        const tiket = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        expect(tiket.status).toBe(StatusTiket.DILAYANI);
        expect(tiket.pelayananSelesaiPada).toBeNull();
      }, 30000);

      it('menolak COMPLETE kedua tanpa audit atau versi ganda', async () => {
        await siapkanTiketDilayani();
        const sebelum = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        await selesaikanPelayanan().expect(200);
        await selesaikanPelayanan().expect(409);
        const sesudah = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        expect(sesudah.status).toBe(StatusTiket.SELESAI);
        expect(sesudah.versi).toBe(sebelum.versi + 1);
        expect(await db().peristiwaAntrean.count({
          where: { tiketAntreanId: tiketId, tipe: 'COMPLETE' },
        })).toBe(1);
      }, 30000);

      it('dua COMPLETE bersamaan hanya menghasilkan satu perubahan dan audit', async () => {
        await siapkanTiketDilayani();
        const sebelum = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        const [responsA, responsB] = await Promise.all([
          selesaikanPelayanan(petugasA.token),
          selesaikanPelayanan(petugasB.token),
        ]);
        const status = [responsA.status, responsB.status].sort((a, b) => a - b);
        expect(status).toEqual([200, 409]);
        const sesudah = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        expect(sesudah.status).toBe(StatusTiket.SELESAI);
        expect(sesudah.versi).toBe(sebelum.versi + 1);
        const audit = await db().peristiwaAntrean.findMany({
          where: { tiketAntreanId: tiketId, tipe: 'COMPLETE' },
        });
        expect(audit).toHaveLength(1);
        const pemenang = responsA.status === 200 ? petugasA.id : petugasB.id;
        expect(audit[0].aktorId).toBe(pemenang);
      }, 30000);

      it('loket bebas untuk CALL tiket berikutnya setelah COMPLETE', async () => {
        await siapkanTiketDilayani();
        await selesaikanPelayanan().expect(200);
        let tiketKeduaId: string | null = null;
        try {
          const nomor = await db().urutanAntreanHarian.update({
            where: { layananId_tanggal: { layananId, tanggal: hariIniDb } },
            data: { nomorTerakhir: { increment: 1 } },
          });
          const tiketKedua = await db().tiketAntrean.create({
            data: {
              penggunaId: userB.id,
              layananId,
              loketId,
              tanggalAntrean: hariIniDb,
              nomorUrut: nomor.nomorTerakhir,
              kodeTiket: `TK${randomBytes(12).toString('hex').toUpperCase()}`,
              status: StatusTiket.CHECK_IN,
              checkInPada: new Date(),
            },
          });
          tiketKeduaId = tiketKedua.id;
          await masukAntrean(tiketKeduaId).expect(200);
          const respons = await panggilAntrean().expect(200);
          expect(respons.body).toMatchObject({
            tiketId: tiketKeduaId,
            status: StatusTiket.DIPANGGIL,
            loketId,
          });
          const tiketPertama = await db().tiketAntrean.findUniqueOrThrow({
            where: { id: tiketId },
          });
          expect(tiketPertama.status).toBe(StatusTiket.SELESAI);
        } finally {
          if (tiketKeduaId) {
            await db().peristiwaAntrean.deleteMany({
              where: { tiketAntreanId: tiketKeduaId },
            });
            await db().tiketAntrean.deleteMany({
              where: { id: tiketKeduaId },
            });
          }
        }
      }, 30000);

      it('rollback COMPLETE mempertahankan status, waktu dan versi jika audit gagal', async () => {
        await siapkanTiketDilayani();
        const databaseUrl = process.env.DATABASE_URL;
        if (!databaseUrl) {
          throw new Error('DATABASE_URL testing tidak ada');
        }
        const url = new URL(databaseUrl);
        if (
          url.pathname !== '/capstone_antrean_test' ||
          !['localhost', '127.0.0.1'].includes(url.hostname) ||
          url.port !== '5433'
        ) {
          throw new Error('Rollback COMPLETE hanya pada PostgreSQL testing lokal');
        }
        const database = await db().$queryRaw<
          Array<{ namaDatabase: string }>
        >`SELECT current_database() AS "namaDatabase"`;
        expect(database[0]?.namaDatabase).toBe('capstone_antrean_test');
        if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(tiketId)) {
          throw new Error('UUID pengujian COMPLETE tidak valid');
        }

        const sebelum = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        expect(sebelum.status).toBe(StatusTiket.DILAYANI);
        const namaConstraint = `e2e_complete_rollback_${randomBytes(6).toString('hex')}`;
        let terpasang = false;
        try {
          await db().$executeRawUnsafe(
            `ALTER TABLE "public"."peristiwa_antrean"
             ADD CONSTRAINT "${namaConstraint}"
             CHECK (NOT (
               "tiket_antrean_id" = '${tiketId}'::uuid
               AND "tipe" = 'COMPLETE'
             ))`,
          );
          terpasang = true;
          await selesaikanPelayanan().expect(500);
        } finally {
          if (terpasang) {
            await db().$executeRawUnsafe(
              `ALTER TABLE "public"."peristiwa_antrean"
               DROP CONSTRAINT IF EXISTS "${namaConstraint}"`,
            );
          }
        }
        const sesudah = await db().tiketAntrean.findUniqueOrThrow({
          where: { id: tiketId },
        });
        expect(sesudah.status).toBe(StatusTiket.DILAYANI);
        expect(sesudah.versi).toBe(sebelum.versi);
        expect(sesudah.pelayananDimulaiPada).toEqual(sebelum.pelayananDimulaiPada);
        expect(sesudah.pelayananSelesaiPada).toEqual(sebelum.pelayananSelesaiPada);
        expect(sesudah.loketId).toBe(sebelum.loketId);
        expect(sesudah.dipanggilPada).toEqual(sebelum.dipanggilPada);
        expect(sesudah.urutanMasukAntrean).toBe(sebelum.urutanMasukAntrean);
        expect(sesudah.nomorUrut).toBe(sebelum.nomorUrut);
        expect(sesudah.kodeTiket).toBe(sebelum.kodeTiket);
        expect(await db().peristiwaAntrean.count({
          where: { tiketAntreanId: tiketId, tipe: 'COMPLETE' },
        })).toBe(0);
      }, 30000);
    });

  });
});
