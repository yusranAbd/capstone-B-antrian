/** Real NestJS integration. Only unique fixtures on local capstone_antrean_test:5433. */
const path = require('node:path');
const { randomUUID, randomBytes } = require('node:crypto');
const { spawn } = require('node:child_process');
const clientPath = path.resolve(__dirname, '..');
const apiPath = path.resolve(clientPath, '../api');
const fromApi = (name) => require(path.join(apiPath, 'node_modules', name));
fromApi('dotenv').config({
  path: path.resolve(apiPath, '../../.env'),
  quiet: true,
});
const tables = [
  'pengguna',
  'layanan',
  'loket',
  'jadwal_layanan',
  'penugasan_petugas',
  'tiket_antrean',
  'urutan_antrean_harian',
  'peristiwa_antrean',
  'perangkat_tampilan',
  'sesi_pengguna',
  'notifikasi',
  'dokter',
  'dokter_layanan',
  'jadwal_praktik',
  'slot_praktik',
  'janji_temu',
];

async function main() {
  if (!process.env.DATABASE_URL)
    throw new Error('DATABASE_URL lokal wajib tersedia');
  const url = new URL(process.env.DATABASE_URL);
  if (
    !['postgresql:', 'postgres:'].includes(url.protocol) ||
    !['localhost', '127.0.0.1'].includes(url.hostname)
  )
    throw new Error('Sumber koneksi bukan PostgreSQL lokal');
  url.hostname = '127.0.0.1';
  url.port = '5433';
  url.pathname = '/capstone_antrean_test';
  const safeUrl = url.toString();
  const { Client } = fromApi('pg');
  async function readState() {
    const client = new Client({ connectionString: safeUrl });
    try {
      await client.connect();
      await client.query('BEGIN READ ONLY');
      const actual = await client.query('SELECT current_database() AS db');
      if (actual.rows[0]?.db !== 'capstone_antrean_test')
        throw new Error('Database aktual salah');
      const state = new Map();
      for (const table of tables) {
        const result = await client.query(
          'SELECT id::text AS id, md5(row_to_json(t)::text) AS hash FROM "' +
            table +
            '" t',
        );
        state.set(table, new Map(result.rows.map((r) => [r.id, r.hash])));
      }
      await client.query('ROLLBACK');
      return state;
    } finally {
      await client.end();
    }
  }
  const before = await readState();
  console.log(
    'Target integrasi Flutter tervalidasi: 127.0.0.1:5433/capstone_antrean_test',
  );
  process.env.DATABASE_URL = safeUrl;
  process.env.SERVICE_TIME_ZONE = 'Asia/Jakarta';
  process.env.CORS_ALLOWED_ORIGINS =
    'http://127.0.0.1:8080';
  process.env.NODE_ENV = 'test';
  process.env.API_PORT = '3001';
  process.chdir(apiPath);
  const { Test } = fromApi('@nestjs/testing');
  const { ConfigService } = fromApi('@nestjs/config');
  const { ThrottlerStorage } = fromApi('@nestjs/throttler');
  const { AppModule } = require(path.join(apiPath, 'dist/app.module.js'));
  const { PrismaService } = require(
    path.join(apiPath, 'dist/prisma/prisma.service.js'),
  );
  const { PasswordService } = require(
    path.join(apiPath, 'dist/auth/password.service.js'),
  );
  const { configureApp } = require(path.join(apiPath, 'dist/configure-app.js'));
  // Override provider with an explicit test URL: env files cannot redirect any query to development.
  const prisma = new PrismaService(
    new ConfigService({ DATABASE_URL: safeUrl }),
  );
  const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
    .overrideProvider(PrismaService)
    .useValue(prisma)
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
  const app = moduleRef.createNestApplication();
  app.useLogger(['warn', 'error']);
  configureApp(app);
  let serviceId = '';
  let doctorId = '';
  let fixture;
  const users = [];
  let code = 1;
  try {
    await app.listen(3001, '127.0.0.1');
    const actual = await prisma.$queryRaw`SELECT current_database() AS db`;
    if (actual[0]?.db !== 'capstone_antrean_test')
      throw new Error('Provider test tidak sesuai');
    const password = `Fixture-Flutter-${randomUUID()}!`;
    const hash = await app.get(PasswordService).hash(password);
    const unique = randomUUID().replace(/-/g, '').slice(0, 10).toUpperCase();
    const accounts = {};
    for (const [key, peran] of [
      ['admin', 'ADMIN'],
      ['petugas', 'PETUGAS'],
      ['patient1', 'USER'],
      ['patient2', 'USER'],
    ]) {
      const account = await prisma.pengguna.create({
        data: {
          email: `flutter-${key}-${unique.toLowerCase()}@test.local`,
          nama: `Fixture Flutter ${key}`,
          peran,
          kataSandiHash: hash,
        },
      });
      users.push(account.id);
      accounts[key] = { id: account.id, email: account.email, password };
    }
    async function call(route, body, token) {
      const response = await fetch(`http://127.0.0.1:3001/api/v1${route}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        body: JSON.stringify(body),
      });
      if (!response.ok)
        throw new Error(`Fixture API ${route}: HTTP ${response.status}`);
      return response.json();
    }
    const admin = await call('/auth/login', {
      email: accounts.admin.email,
      kataSandi: password,
    });
    const post = (route, body) => call(route, body, admin.accessToken);
    const date = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'Asia/Jakarta',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).format(new Date());
    const start = new Date(`${date}T00:00:00+07:00`);
    const end = new Date(`${date}T23:59:00+07:00`);
    serviceId = (
      await post('/layanan', {
        kode: `W${unique}`,
        nama: 'Poli Fixture Flutter',
        prefixAntrean: 'WF',
        durasiDasarMenit: 15,
        modeReservasi: 'HIBRIDA',
      })
    ).id;
    await post('/jadwal-layanan', {
      layananId: serviceId,
      hari: ['MINGGU', 'SENIN', 'SELASA', 'RABU', 'KAMIS', 'JUMAT', 'SABTU'][
        new Date(`${date}T00:00:00Z`).getUTCDay()
      ],
      jamBuka: '00:00',
      jamTutup: '23:59',
      kapasitasHarian: 10,
    });
    const room = await post('/loket', {
      layananId: serviceId,
      kode: `R${unique}`,
      nama: 'Ruang Fixture Flutter',
    });
    const assignment = await post('/penugasan-petugas', {
      petugasId: accounts.petugas.id,
      loketId: room.id,
      tanggalMulai: date,
    });
    doctorId = (
      await post('/dokter', {
        kode: `D${unique}`,
        nama: 'Dokter Fixture Flutter',
        spesialisasi: 'Umum',
      })
    ).id;
    const relation = await post(`/dokter/${doctorId}/layanan`, {
      layananId: serviceId,
    });
    const schedule = await post('/jadwal-praktik', {
      dokterLayananId: relation.id,
      loketId: room.id,
      tanggal: date,
      mulaiPada: start.toISOString(),
      selesaiPada: end.toISOString(),
    });
    const slotStart = new Date(Math.ceil(Date.now() / 60000) * 60000 + 2 * 60000);
    const slot = await post('/slot-praktik', {
      jadwalPraktikId: schedule.id,
      mulaiPada: slotStart.toISOString(),
      selesaiPada: new Date(slotStart.getTime() + 15 * 60_000).toISOString(),
      kapasitas: 2,
    });
    const displayToken = randomBytes(32).toString('hex');
    await prisma.perangkatTampilan.create({data: {
      layananId: serviceId, nama: 'Display Fixture Flutter',
      tokenHash: require('node:crypto').createHash('sha256').update(displayToken).digest('hex'),
    }});
    fixture = {
      date, unique, serviceCode: `W${unique}`, ...accounts, roomId: room.id, serviceId, doctorId, assignmentId: assignment.id, extraDoctorIds: [],
      scheduleId: schedule.id, slotId: slot.id, slotStart: slotStart.toISOString(), displayToken,
      extraServiceCodes: [],
    };
    if (process.argv.includes('--android')) {
      await require('./android-demo.cjs')(fixture, clientPath, async () => {
        const freshAdmin = await call('/auth/login', {email:accounts.admin.email,kataSandi:password});
        const start = new Date(Math.ceil(Date.now()/60000)*60000+2*60000);
        const result = await fetch(`http://127.0.0.1:3001/api/v1/slot-praktik/${fixture.slotId}`, {
          method:'PATCH', headers:{'Content-Type':'application/json',Authorization:`Bearer ${freshAdmin.accessToken}`},
          body:JSON.stringify({mulaiPada:start.toISOString(),selesaiPada:new Date(start.getTime()+15*60000).toISOString()}),
        });
        if(!result.ok)throw new Error('Persiapan slot Android HTTP '+result.status);
        fixture.slotStart=start.toISOString();
      });
      code=0;
    } else if (process.argv.includes('--doctor-schedule')) {
      fixture.doctorSchedule = true;
      code = 0;
    } else if (process.argv.includes('--realtime-admin')) {
      fixture.realtimeAdmin = true;
      fixture.adminLayoutOnly = process.argv.includes('--admin-layout-only');
      code = 0;
    } else if (process.argv.includes('--admin-schedules')) {
      fixture.adminSchedules = true;
      code = 0;
    } else if (process.argv.includes('--demo-browser')) {
      fixture.demoFull = true;
      code = 0;
    } else if (process.argv.includes('--browser-only')) {
      const patient = await call('/auth/login', {email: accounts.patient1.email, kataSandi: password});
      await call('/reservasi', {layananId: serviceId, tanggalAntrean: date}, patient.accessToken);
      code = 0;
    } else code = await new Promise((resolve, reject) => {
      const windows = process.platform === 'win32';
      const child = spawn(windows ? 'cmd.exe' : 'flutter', windows ? ['/d', '/s', '/c', 'flutter test test/live_integration_test.dart --reporter expanded'] : ['test', 'test/live_integration_test.dart', '--reporter', 'expanded'], {
        cwd: clientPath, stdio: 'inherit', windowsHide: true,
        env: {...process.env, FLUTTER_REAL_FIXTURE: JSON.stringify(fixture)},
      });
      child.once('error', reject);
      child.once('exit', value => resolve(value ?? 1));
    });
    if (code === 0 && (process.argv.includes('--browser') || process.argv.includes('--browser-only') || fixture.demoFull || fixture.adminSchedules || fixture.realtimeAdmin || fixture.doctorSchedule)) {
      await require('./browser-smoke.cjs')(fixture);
    }
  } catch (error) {
    code = 1;
    console.error('Integrasi Flutter gagal: ' + (error.code || error.name));
  } finally {
    // Only unique codes registered by this run, never development/master data.
    if (fixture?.extraServiceCodes.length) {
      const owned = await prisma.layanan.findMany({where: {kode: {in: fixture.extraServiceCodes}},select: {id:true}});
      const ownedIds = owned.map(row => row.id);
      await prisma.jadwalLayanan.deleteMany({where: {layananId: {in: ownedIds}}});
      await prisma.layanan.deleteMany({where: {id: {in: ownedIds}}});
    }
    if (serviceId) {
      await prisma.perangkatTampilan.deleteMany({where: {layananId: serviceId}});
      const tickets = await prisma.tiketAntrean.findMany({
        where: { layananId: serviceId },
        select: { id: true },
      });
      const ids = tickets.map((t) => t.id);
      await prisma.peristiwaAntrean.deleteMany({
        where: { tiketAntreanId: { in: ids } },
      });
      await prisma.janjiTemu.deleteMany({ where: { tiketId: { in: ids } } });
      await prisma.tiketAntrean.deleteMany({ where: { id: { in: ids } } });
      await prisma.slotPraktik.deleteMany({
        where: { jadwalPraktik: { dokterLayanan: { layananId: serviceId } } },
      });
      await prisma.jadwalPraktik.deleteMany({
        where: { dokterLayanan: { layananId: serviceId } },
      });
      await prisma.dokterLayanan.deleteMany({
        where: { layananId: serviceId },
      });
      if (doctorId) await prisma.dokter.deleteMany({ where: { id: {in: [doctorId, ...(fixture?.extraDoctorIds || [])]} } });
      await prisma.penugasanPetugas.deleteMany({
        where: { loket: { layananId: serviceId } },
      });
      await prisma.loket.deleteMany({ where: { layananId: serviceId } });
      await prisma.jadwalLayanan.deleteMany({
        where: { layananId: serviceId },
      });
      await prisma.urutanAntreanHarian.deleteMany({
        where: { layananId: serviceId },
      });
      await prisma.layanan.deleteMany({ where: { id: serviceId } });
    }
    if (users.length) {
      await prisma.sesiPengguna.deleteMany({
        where: { penggunaId: { in: users } },
      });
      await prisma.pengguna.deleteMany({ where: { id: { in: users } } });
    }
    await app.close();
  }
  const after = await readState();
  let existing = 0,
    missing = 0,
    changed = 0,
    remaining = 0;
  for (const [table, old] of before) {
    const current = after.get(table);
    existing += old.size;
    for (const [id, hash] of old) {
      if (!current.has(id)) missing++;
      else if (current.get(id) !== hash) changed++;
    }
    for (const id of current.keys()) if (!old.has(id)) remaining++;
  }
  console.log(
    JSON.stringify({
      dataExisting: { jumlah: existing, hilang: missing, berubah: changed },
      recordBaruTersisa: remaining,
    }),
  );
  process.exitCode = missing || changed || remaining ? 1 : code;
}
main().catch((error) => {
  console.error('Integrasi Flutter gagal: ' + (error.code || error.name));
  process.exitCode = 1;
});
