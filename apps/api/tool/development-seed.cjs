// Synthetic data only. Run through development-data.cjs, never on startup.
require('reflect-metadata');
const fs = require('node:fs'),
  path = require('node:path'),
  crypto = require('node:crypto'),
  assert = require('node:assert/strict');
const { ConfigService } = require('@nestjs/config');

const { JwtService } = require('@nestjs/jwt');

const { assertTarget, externalDirectory } = require('./development-data.cjs');
const START = '2026-10-27',
  END = '2026-11-30',
  VERSION = 'queueb-synthetic-20261027-v1';
const CLINICS = [
  [
    'ANAK',
    'Poliklinik Anak',
    'AN',
    'Anak',
    'Sp.A',
    'HIBRIDA',
    'Pelayanan konsultasi kesehatan dan tumbuh kembang anak.',
    ['Naila Prameswari', 'Bagas Wicaksana'],
  ],
  [
    'PDALAM',
    'Poliklinik Penyakit Dalam',
    'PD',
    'Penyakit Dalam',
    'Sp.PD',
    'HIBRIDA',
    'Pelayanan konsultasi kesehatan organ dalam bagi pasien dewasa.',
    ['Aditya Mahendra', 'Sekar Larasati'],
  ],
  [
    'MATA',
    'Poliklinik Mata',
    'MT',
    'Mata',
    'Sp.M',
    'JANJI_TEMU_DOKTER',
    'Pelayanan konsultasi kesehatan mata dan fungsi penglihatan.',
    ['Farah Kinasih', 'Arga Pranadipa'],
  ],
  [
    'BEDAH',
    'Poliklinik Bedah Umum',
    'BU',
    'Bedah Umum',
    'Sp.B',
    'ANTREAN_HARIAN',
    'Pelayanan konsultasi bedah umum dan evaluasi tindak lanjut.',
    ['Rendra Pratama', 'Ratih Candrakirana'],
  ],
  [
    'SARAF',
    'Poliklinik Saraf',
    'SR',
    'Saraf',
    'Sp.N',
    'HIBRIDA',
    'Pelayanan konsultasi sistem saraf dan tindak lanjut kesehatan saraf.',
    ['Dimas Aryasatya', 'Intan Puspitasari'],
  ],
];
const STAFF = [
  'Rahmat Abdullah',
  'Laras Ayuningtyas',
  'Fikri Ramadhan',
  'Nisa Kartikasari',
  'Arif Setiawan',
  'Dewi Purnamasari',
  'Bayu Prakoso',
  'Sari Wulandari',
];
const PATIENTS = [
  'Andi Pranata',
  'Citra Maharani',
  'Bima Saputra',
  'Aulia Fitriani',
  'Fajar Nugraha',
  'Dinda Safitri',
  'Rizky Firmansyah',
  'Nadia Permatasari',
  'Ilham Kurniawan',
  'Putri Anggraini',
  'Wahyu Hidayat',
  'Rani Kusumawati',
  'Galih Prasetyo',
  'Maya Puspita',
  'Hendra Wijaya',
  'Ayu Lestari',
  'Yoga Saputra',
  'Anisa Rahmawati',
  'Deni Saputro',
  'Melati Wulandari',
  'Reza Fadillah',
  'Nabila Zahra',
  'Teguh Santoso',
  'Tiara Apriliani',
  'Agung Wibowo',
  'Vina Oktaviani',
  'Raka Mahardika',
  'Wulan Kartini',
  'Hafiz Maulana',
  'Niken Saraswati',
  'Daffa Alfarizi',
  'Salsa Amalia',
  'Rian Purnomo',
  'Dian Paramitha',
  'Rifqi Anugrah',
  'Febriani Utami',
  'Doni Hermawan',
  'Yuni Handayani',
  'Gilang Pamungkas',
  'Laila Nuraini',
];
const email = (name) =>
  name.toLowerCase().replaceAll(' ', '.') + '@example.test';
const localDate = (d = new Date()) =>
  new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Jakarta',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(d);
const instant = (date, time) => new Date(date + 'T' + time + ':00+07:00');
function dates() {
  const out = [];
  for (
    let d = new Date(START + 'T00:00:00Z');
    d.toISOString().slice(0, 10) <= END;
    d.setUTCDate(d.getUTCDate() + 1)
  )
    out.push(d.toISOString().slice(0, 10));
  return out;
}
function assertSeedWindow(now = new Date()) {
  const today = localDate(now);
  if (
    today !== START ||
    now < instant(today, '07:00') ||
    now >= instant(today, '11:40')
  )
    throw Error(
      'Skenario live dataset ini memerlukan 27 Oktober 2026 pukul 07:00–11:40 WIB; tidak memalsukan jam/status.',
    );
}
function schedulePlan() {
  const out = [];
  for (let ci = 0; ci < CLINICS.length; ci++)
    for (const day of dates()) {
      const dow = new Date(day + 'T00:00:00Z').getUTCDay();
      if (dow === 0) continue;
      const doctor = dow % 2 === 0 ? 1 : 0;
      if (day === START) {
        out.push({ ci, doctor: 0, room: 0, day, start: '07:00', end: '12:00' });
        out.push({
          ci,
          doctor: 1,
          room: ci < 2 ? 1 : 0,
          day,
          start: '13:00',
          end: '16:00',
        });
      } else {
        const afternoon = dow === 4 || dow === 6;
        const late = ci % 2 === 1;
        out.push({
          ci,
          doctor,
          room: ci < 2 && doctor === 1 ? 1 : 0,
          day,
          start: afternoon
            ? late
              ? '14:00'
              : '13:00'
            : late
              ? '09:00'
              : '08:00',
          end: afternoon
            ? late
              ? '17:00'
              : '16:00'
            : late
              ? '12:00'
              : '11:00',
        });
      }
    }
  return out;
}
function save(file, value) {
  const tmp = file + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(value, null, 2) + '\n', { mode: 0o600 });
  fs.renameSync(tmp, file);
}
async function verify(db, state) {
  const counts = {};
  for (const [table, model] of Object.entries({
    pengguna: 'pengguna',
    layanan: 'layanan',
    dokter: 'dokter',
    dokterLayanan: 'dokterLayanan',
    loket: 'loket',
    jadwalLayanan: 'jadwalLayanan',
    jadwalPraktik: 'jadwalPraktik',
    slotPraktik: 'slotPraktik',
    penugasan: 'penugasanPetugas',
    tiket: 'tiketAntrean',
    appointment: 'janjiTemu',
    peristiwa: 'peristiwaAntrean',
    display: 'perangkatTampilan',
  }))
    counts[table] = await db[model].count();
  const roles = await db.pengguna.groupBy({ by: ['peran'], _count: true });
  const status = await db.tiketAntrean.groupBy({
    by: ['status'],
    _count: true,
  });
  const sqlChecks = {
    scheduleConflict: `SELECT count(*)::int n FROM jadwal_praktik a JOIN jadwal_praktik b ON a.id<b.id AND a.aktif AND b.aktif AND a.mulai_pada<b.selesai_pada AND b.mulai_pada<a.selesai_pada JOIN dokter_layanan da ON da.id=a.dokter_layanan_id JOIN dokter_layanan db ON db.id=b.dokter_layanan_id WHERE a.loket_id=b.loket_id OR da.dokter_id=db.dokter_id`,
    period: `SELECT count(*)::int n FROM jadwal_praktik WHERE tanggal<'2026-10-27' OR tanggal>'2026-11-30' OR (mulai_pada AT TIME ZONE 'Asia/Jakarta')::date<>tanggal OR (selesai_pada AT TIME ZONE 'Asia/Jakarta')::date<>tanggal`,
    slotBounds: `SELECT count(*)::int n FROM slot_praktik s JOIN jadwal_praktik j ON j.id=s.jadwal_praktik_id WHERE s.mulai_pada<j.mulai_pada OR s.selesai_pada>j.selesai_pada OR s.mulai_pada>=s.selesai_pada OR s.kapasitas<1`,
    slotOverlap: `SELECT count(*)::int n FROM slot_praktik a JOIN slot_praktik b ON a.id<b.id AND a.jadwal_praktik_id=b.jadwal_praktik_id AND a.mulai_pada<b.selesai_pada AND b.mulai_pada<a.selesai_pada`,
    slotCapacity: `SELECT count(*)::int n FROM (SELECT s.id FROM slot_praktik s JOIN janji_temu j ON j.slot_praktik_id=s.id JOIN tiket_antrean t ON t.id=j.tiket_id AND t.status<>'DIBATALKAN' GROUP BY s.id,s.kapasitas HAVING count(*)>s.kapasitas) x`,
    dailyCapacity: `SELECT count(*)::int n FROM (SELECT t.layanan_id,t.tanggal_antrean FROM tiket_antrean t JOIN jadwal_layanan j ON j.layanan_id=t.layanan_id AND j.hari::text=(ARRAY['MINGGU','SENIN','SELASA','RABU','KAMIS','JUMAT','SABTU'])[extract(dow FROM t.tanggal_antrean)::int+1] WHERE t.status<>'DIBATALKAN' GROUP BY t.layanan_id,t.tanggal_antrean,j.kapasitas_harian HAVING count(*)>j.kapasitas_harian) x`,
    appointmentContext: `SELECT count(*)::int n FROM janji_temu a JOIN tiket_antrean t ON t.id=a.tiket_id JOIN slot_praktik s ON s.id=a.slot_praktik_id JOIN jadwal_praktik j ON j.id=s.jadwal_praktik_id JOIN dokter_layanan d ON d.id=j.dokter_layanan_id JOIN loket l ON l.id=j.loket_id WHERE t.layanan_id<>d.layanan_id OR l.layanan_id<>t.layanan_id OR t.tanggal_antrean<>j.tanggal`,
    chronology: `SELECT count(*)::int n FROM tiket_antrean WHERE check_in_pada<dibuat_pada OR dipanggil_pada<check_in_pada OR pelayanan_dimulai_pada<check_in_pada OR pelayanan_selesai_pada<pelayanan_dimulai_pada OR pelayanan_selesai_pada>now() OR (status='SELESAI' AND (tanggal_antrean>(now() AT TIME ZONE 'Asia/Jakarta')::date OR pelayanan_selesai_pada IS NULL))`,
    assignmentConflict: `SELECT count(*)::int n FROM penugasan_petugas a JOIN penugasan_petugas b ON a.id<b.id AND a.petugas_id=b.petugas_id AND a.aktif AND b.aktif AND a.tanggal_mulai<=coalesce(b.tanggal_selesai,'infinity') AND b.tanggal_mulai<=coalesce(a.tanggal_selesai,'infinity')`,
    invalidAssignment: `SELECT count(*)::int n FROM penugasan_petugas p JOIN pengguna u ON u.id=p.petugas_id JOIN loket l ON l.id=p.loket_id WHERE p.aktif AND (u.peran<>'PETUGAS' OR NOT u.aktif OR NOT l.aktif)`,
    missingRoom: `SELECT count(*)::int n FROM layanan l WHERE NOT EXISTS(SELECT 1 FROM loket r WHERE r.layanan_id=l.id)`,
    missingDoctorAccount: `SELECT count(*)::int n FROM dokter d LEFT JOIN pengguna p ON p.id=d.pengguna_id WHERE p.id IS NULL OR p.peran<>'DOKTER'`,
  };
  const checks = {};
  for (const [key, sql] of Object.entries(sqlChecks)) {
    checks[key] = (await db.$queryRawUnsafe(sql))[0].n;
    assert.equal(checks[key], 0, key);
  }
  assert.equal(counts.layanan, 5);
  assert.equal(counts.dokter, 10);
  assert.equal(counts.loket, 7);
  assert.equal(await db.pengguna.count({ where: { peran: 'USER' } }), 40);
  assert.equal(await db.pengguna.count({ where: { peran: 'PETUGAS' } }), 8);
  assert.equal(
    await db.pengguna.count({
      where: { peran: 'ADMIN', id: state.adminId, aktif: true },
    }),
    1,
  );
  const all = await db.jadwalPraktik.aggregate({
    _min: { tanggal: true },
    _max: { tanggal: true },
  });
  assert.equal(all._min.tanggal.toISOString().slice(0, 10), START);
  assert.equal(all._max.tanggal.toISOString().slice(0, 10), END);
  if (state.complete)
    for (const s of [
      'DIPESAN',
      'CHECK_IN',
      'MENUNGGU',
      'DIPANGGIL',
      'DILAYANI',
      'SELESAI',
      'DILEWATI',
      'DIBATALKAN',
    ])
      assert(
        status.some((r) => r.status === s),
        s + ' tidak terwakili',
      );
  return {
    verifiedAt: new Date().toISOString(),
    dataset: VERSION,
    counts,
    roles,
    status,
    checks,
    period: [START, END],
    synthetic: true,
    smoke: state.smoke,
  };
}
async function main() {
  const { PrismaService } = require('../dist/prisma/prisma.service');
  const { PasswordService } = require('../dist/auth/password.service');
  const { UsersService } = require('../dist/users/users.service');
  const { AuthService } = require('../dist/auth/auth.service');
  const { LayananService } = require('../dist/layanan/layanan.service');
  const { LoketService } = require('../dist/loket/loket.service');
  const {
    JadwalLayananService,
  } = require('../dist/jadwal-layanan/jadwal-layanan.service');
  const { DokterService } = require('../dist/dokter/dokter.service');
  const {
    JadwalPraktikService,
  } = require('../dist/jadwal-praktik/jadwal-praktik.service');
  const {
    SlotPraktikService,
  } = require('../dist/slot-praktik/slot-praktik.service');
  const {
    AkunPetugasService,
  } = require('../dist/akun-petugas/akun-petugas.service');
  const {
    PenugasanPetugasService,
  } = require('../dist/penugasan-petugas/penugasan-petugas.service');
  const { ReservasiService } = require('../dist/reservasi/reservasi.service');
  const { JanjiTemuService } = require('../dist/janji-temu/janji-temu.service');
  const { QrService } = require('../dist/qr/qr.service');
  const { CheckInService } = require('../dist/check-in/check-in.service');
  const {
    AutoCheckInService,
  } = require('../dist/check-in/auto-check-in.service');
  const { QueueService } = require('../dist/queue/queue.service');
  const {
    DisplayDeviceService,
  } = require('../dist/display/display-device.service');
  const { DisplayService } = require('../dist/display/display.service');
  const {
    PortalDokterService,
  } = require('../dist/portal-dokter/portal-dokter.service');
  const [mode, ...argv] = process.argv.slice(2),
    args = Object.fromEntries(
      argv.map((a) => {
        const i = a.indexOf('=');
        return [a.slice(0, i), a.slice(i + 1)];
      }),
    );
  assertTarget(process.env.DATABASE_URL, process.env.NODE_ENV);
  if (!['seed', 'verify'].includes(mode)) throw Error('Mode tidak didukung.');
  const dir = externalDirectory(args['--output']),
    stateFile = path.join(dir, 'seed-state.json'),
    credentialFile = path.join(dir, 'akun-pengujian.json');
  const resetResult = JSON.parse(
    fs.readFileSync(path.join(dir, 'reset-result.json')),
  );
  const checkpoint = JSON.parse(fs.readFileSync(resetResult.checkpoint));
  assert.equal(checkpoint.admin.id, args['--admin-id']);
  const state = fs.existsSync(stateFile)
    ? JSON.parse(fs.readFileSync(stateFile))
    : {
        version: VERSION,
        adminId: args['--admin-id'],
        startedAt: new Date().toISOString(),
        complete: false,
      };
  assert.equal(state.version, VERSION);
  assert.equal(state.adminId, args['--admin-id']);
  const config = new ConfigService({
      ...process.env,
      SERVICE_TIME_ZONE: 'Asia/Jakarta',
    }),
    db = new PrismaService(config);
  await db.$connect();
  try {
    if (mode === 'verify' || state.complete) {
      const report = await verify(db, state);
      save(path.join(dir, 'verification.json'), report);
      console.log(
        JSON.stringify({ ...report, noOp: mode === 'seed' }, null, 2),
      );
      return;
    }
    if (fs.existsSync(stateFile))
      throw Error(
        'Seed parsial terdeteksi. Hentikan dan review state lokal; jangan mengulang transisi/menghapus otomatis.',
      );
    if ((await db.layanan.count()) || (await db.pengguna.count()) !== 1)
      throw Error(
        'Seed awal memerlukan checkpoint reset kosong yang sudah diverifikasi.',
      );
    // No fake clock or direct status writes. Operational scenarios must fit real service hours.
    const today = localDate(),
      now = new Date();
    assertSeedWindow(now);
    save(stateFile, state);
    const credentials = {
      dataset: VERSION,
      synthetic: true,
      createdAt: now.toISOString(),
      accounts: [],
    };
    save(credentialFile, credentials);
    const password = new PasswordService();
    const auth = new AuthService(
      new UsersService(db),
      password,
      new JwtService(),
      config,
      db,
    );
    const clinicService = new LayananService(db),
      roomService = new LoketService(db),
      dailyService = new JadwalLayananService(db),
      doctorService = new DokterService(db, password),
      practiceService = new JadwalPraktikService(db, config),
      slotService = new SlotPraktikService(db),
      staffService = new AkunPetugasService(db, password),
      assignmentService = new PenugasanPetugasService(db);
    const reserve = new ReservasiService(db),
      appointments = new JanjiTemuService(db),
      qr = new QrService(db),
      checkIn = new CheckInService(db),
      queue = new QueueService(db);
    // An offline maintenance process has no WebSocket clients. Domain transaction/audit is real;
    // no sockets are mocked for the actual network E2E, which runs separately on the test DB.
    const offline = { kirim: async () => {} },
      auto = new AutoCheckInService(db, checkIn, queue, offline);
    const displayDevices = new DisplayDeviceService(
        db,
        { cabutPerangkat: () => {} },
        config,
      ),
      display = new DisplayService(db),
      portal = new PortalDokterService(db);
    function secret(name, role) {
      const item = {
        nama: name,
        email: email(name),
        role,
        kataSandi: crypto.randomBytes(24).toString('base64url'),
      };
      credentials.accounts.push(item);
      save(credentialFile, credentials);
      return item;
    }
    const clinics = [],
      rooms = [],
      doctors = [],
      links = [];
    const days = ['SENIN', 'SELASA', 'RABU', 'KAMIS', 'JUMAT', 'SABTU'];
    for (let i = 0; i < CLINICS.length; i++) {
      const [
        kode,
        nama,
        prefix,
        spesialisasi,
        degree,
        modeReservasi,
        deskripsi,
        names,
      ] = CLINICS[i];
      const c = await clinicService.create({
        kode,
        nama,
        prefixAntrean: prefix,
        durasiDasarMenit: 20,
        deskripsi,
        modeReservasi,
      });
      clinics.push(c);
      rooms[i] = [];
      doctors[i] = [];
      links[i] = [];
      for (let r = 0; r < (i < 2 ? 2 : 1); r++)
        rooms[i].push(
          await roomService.create({
            layananId: c.id,
            kode: prefix + '0' + (r + 1),
            nama: 'Ruang ' + spesialisasi + ' ' + (r + 1),
            lokasi: 'Lantai ' + (i < 3 ? 1 : 2),
          }),
        );
      for (const hari of days)
        await dailyService.create({
          layananId: c.id,
          hari,
          jamBuka: '07:00',
          jamTutup: '17:00',
          kapasitasHarian: 80,
        });
      for (let d = 0; d < 2; d++) {
        const full = 'dr. ' + names[d] + ', ' + degree;
        const doc = await doctorService.create({
          kode: 'DOK' + prefix + '0' + (d + 1),
          nama: full,
          spesialisasi,
          tentangDokter:
            full +
            ' melayani konsultasi ' +
            spesialisasi.toLowerCase() +
            ' di ' +
            nama +
            '. Jadwal dan ketersediaan konsultasi dapat dilihat pada aplikasi.',
        });
        const link = await doctorService.hubungkanLayanan(doc.id, {
          layananId: c.id,
        });
        const cred = secret(names[d], 'DOKTER');
        const linked = await doctorService.provisionAkun(doc.id, {
          email: cred.email,
          kataSandi: cred.kataSandi,
        });
        doctors[i].push({ ...doc, penggunaId: linked.akun.id });
        links[i].push(link);
      }
      await displayDevices.create({
        nama: 'Display ' + spesialisasi,
        layananId: c.id,
      });
    }
    state.master = true;
    state.clinics = clinics.map((c) => c.id);
    save(stateFile, state);
    const staff = [],
      flatRooms = rooms.flat();
    for (let i = 0; i < STAFF.length; i++) {
      const cred = secret(STAFF[i], 'PETUGAS'),
        s = await staffService.create(
          { nama: cred.nama, email: cred.email, kataSandi: cred.kataSandi },
          state.adminId,
        );
      staff.push(s);
      if (i < flatRooms.length)
        await assignmentService.create({
          petugasId: s.id,
          loketId: flatRooms[i].id,
          tanggalMulai: START,
          tanggalSelesai: END,
        });
      else await staffService.status(s.id, false, state.adminId);
    }
    const patients = [];
    for (const name of PATIENTS) {
      const c = secret(name, 'USER');
      patients.push(
        await auth.register({
          nama: name,
          email: c.email,
          kataSandi: c.kataSandi,
        }),
      );
    }
    const practices = [],
      slots = [];
    for (const plan of schedulePlan()) {
      const session = await practiceService.create({
        dokterLayananId: links[plan.ci][plan.doctor].id,
        loketId: rooms[plan.ci][plan.room].id,
        tanggal: plan.day,
        mulaiPada: instant(plan.day, plan.start).toISOString(),
        selesaiPada: instant(plan.day, plan.end).toISOString(),
      });
      practices.push({
        ...session,
        ci: plan.ci,
        doctor: plan.doctor,
        day: plan.day,
      });
      for (
        let t = instant(plan.day, plan.start).getTime();
        t < instant(plan.day, plan.end).getTime();
        t += 20 * 60_000
      ) {
        const s = await slotService.create({
          jadwalPraktikId: session.id,
          mulaiPada: new Date(t).toISOString(),
          selesaiPada: new Date(t + 20 * 60_000).toISOString(),
          kapasitas: 2,
        });
        slots.push({ ...s, ci: plan.ci, day: plan.day });
      }
    }
    state.masterComplete = true;
    state.practices = practices.map((s) => s.id);
    save(stateFile, state);
    const staffFor = (room) =>
      staff[flatRooms.findIndex((r) => r.id === room.id)];
    const ticket = async (ci, pi, date = today) =>
      reserve.create(
        { layananId: clinics[ci].id, tanggalAntrean: date },
        patients[pi].id,
      );
    const enqueue = async (t, ci, oneScan = true) => {
      const room = rooms[ci][0],
        s = staffFor(room),
        q = await qr.terbitkan(t.id, t.penggunaId);
      return oneScan
        ? auto.proses({ qrPayload: q.qrPayload, loketId: room.id }, s.id)
        : checkIn.proses({ qrPayload: q.qrPayload, loketId: room.id }, s.id);
    };
    const call = async (ci) =>
      queue.panggilBerikutnya(staffFor(rooms[ci][0]).id, rooms[ci][0].id);
    const act = async (method, ci, t) =>
      queue[method](t.tiketId, staffFor(rooms[ci][0]).id, rooms[ci][0].id);
    // All timestamps below are generated by the existing services at real wall-clock time.
    await enqueue(await ticket(0, 0), 0);
    let called = await call(0);
    await act('panggilUlang', 0, called);
    await act('mulaiPelayanan', 0, called);
    await act('selesaikanPelayanan', 0, called);
    await enqueue(await ticket(0, 1), 0);
    const skipped = await call(0);
    await act('lewatiAntrean', 0, skipped);
    await enqueue(await ticket(0, 2), 0);
    called = await call(0);
    await act('panggilUlang', 0, called);
    await act('antreUlang', 0, skipped);
    state.requeuedTicket = skipped.tiketId;
    await enqueue(await ticket(0, 3), 0);
    await enqueue(await ticket(0, 4), 0, false);
    await ticket(0, 5);
    await enqueue(await ticket(1, 6), 1);
    called = await call(1);
    await act('lewatiAntrean', 1, called);
    await enqueue(await ticket(1, 7), 1);
    called = await call(1);
    await act('mulaiPelayanan', 1, called);
    await enqueue(await ticket(1, 8), 1);
    await ticket(1, 9);
    await enqueue(await ticket(3, 9), 3);
    called = await call(3);
    await act('mulaiPelayanan', 3, called);
    await act('selesaikanPelayanan', 3, called);
    await enqueue(await ticket(3, 10), 3);
    await enqueue(await ticket(4, 11), 4);
    // Appointment check-in is allowed before its slot; CALL still uses the real slot selector.
    const currentSlot = slots.find(
      (s) =>
        s.ci === 2 &&
        s.day === today &&
        s.mulaiPada > new Date() &&
        s.jadwalPraktikId ===
          practices.find((p) => p.ci === 2 && p.day === today && p.doctor === 0)
            .id,
    );
    assert(currentSlot, 'Tidak ada slot hari ini yang belum dimulai.');
    const current = await appointments.create(
      { slotPraktikId: currentSlot.id },
      patients[12].id,
    );
    await enqueue({ id: current.tiketId, penggunaId: patients[12].id }, 2);
    const future = slots.filter((s) => s.day > today && s.ci !== 3);
    for (let i = 13; i < PATIENTS.length; i++) {
      const s = future[((i - 13) * 37) % future.length];
      const a = await appointments.create(
        { slotPraktikId: s.id },
        patients[i].id,
      );
      if (i % 7 === 0) await appointments.batalkan(a.id, patients[i].id);
    }
    // Two confirmed appointments fill one future capacity-2 slot; others remain bookable.
    const full = future[5];
    for (const pi of [0, 1])
      await appointments.create({ slotPraktikId: full.id }, patients[pi].id);
    const smoke = {};
    for (const c of credentials.accounts.filter(
      (c) => c.role !== 'PETUGAS' || c.nama !== STAFF[7],
    )) {
      const login = await auth.login({
        email: c.email,
        kataSandi: c.kataSandi,
        namaPerangkat: 'Verifikasi dataset pengujian',
      });
      assert.equal(login.user.peran, c.role);
    }
    smoke.activeAccountsLogin = credentials.accounts.length - 1;
    await assert.rejects(
      auth.login({
        email: email(STAFF[7]),
        kataSandi: credentials.accounts.find((c) => c.nama === STAFF[7])
          .kataSandi,
      }),
      (e) => e.getStatus() === 401,
    );
    smoke.inactiveStaffRejected = true;
    for (let ci = 0; ci < CLINICS.length; ci++) {
      await portal.profil(doctors[ci][0].penggunaId);
      await portal.jadwal(doctors[ci][0].penggunaId, today);
      await portal.snapshot(
        doctors[ci][0].penggunaId,
        practices.find((p) => p.ci === ci && p.day === today && p.doctor === 0)
          .id,
      );
    }
    smoke.doctorOwnScope = 5;
    await assert.rejects(
      portal.snapshot(
        doctors[0][0].penggunaId,
        practices.find((p) => p.ci === 1 && p.day === today).id,
      ),
      (e) => e.getStatus() === 403,
    );
    smoke.crossClinicDoctorRejected = true;
    // Pair two real device credentials, verify isolation, then revoke only A.
    const devices = await displayDevices.list(),
      paired = [];
    for (const device of devices) {
      const activation = await displayDevices.activation(device.id),
        pairedDevice = await displayDevices.pair(activation.kode);
      paired.push(pairedDevice);
      await display.snapshot(device.layananId, pairedDevice.token, device.id);
    }
    const [a, b] = paired;
    await assert.rejects(
      display.snapshot(b.device.layananId, a.token, a.device.id),
      (e) => e.getStatus() === 403,
    );
    await assert.rejects(
      display.snapshot(a.device.layananId, b.token, a.device.id),
      (e) => e.getStatus() === 401,
    );
    await displayDevices.activation(a.device.id);
    await assert.rejects(
      display.snapshot(a.device.layananId, a.token, a.device.id),
      (e) => e.getStatus() === 401,
    );
    await display.snapshot(b.device.layananId, b.token, b.device.id);
    smoke.deviceIsolation = true;
    // Leave no seeded device credential or activation code usable. ADMIN generates fresh codes.
    for (const device of devices) await displayDevices.activation(device.id);
    smoke.displayScopes = devices.length;
    smoke.displayCredentialsNotPersisted = true;
    state.complete = true;
    state.completedAt = new Date().toISOString();
    state.smoke = smoke;
    save(stateFile, state);
    const report = await verify(db, state);
    save(path.join(dir, 'verification.json'), { ...report, smoke });
    console.log(
      JSON.stringify(
        {
          ...report,
          smoke,
          credentialsFile: credentialFile,
          adminCredentialsUnchanged: true,
        },
        null,
        2,
      ),
    );
  } finally {
    await db.$disconnect();
  }
}
module.exports = {
  schedulePlan,
  dates,
  START,
  END,
  CLINICS,
  STAFF,
  PATIENTS,
  verify,
  assertSeedWindow,
};
if (require.main === module)
  main().catch((e) => {
    // Prisma's invocation text can contain hashes or query parameters.
    console.error(
      'Seed dihentikan: ' +
        (typeof e.getStatus === 'function'
          ? 'HTTP ' + e.getStatus() + ' ' + e.message
          : e.code || e.name || 'operasi gagal') +
        '. Review checkpoint privat; tidak ada reset/restore otomatis.',
    );
    process.exitCode = 1;
  });
