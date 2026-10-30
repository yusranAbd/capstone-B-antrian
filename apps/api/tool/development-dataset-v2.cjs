// Explicit, allowlisted development maintenance. Never imported on startup.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
const { Client } = require('pg');
const { parse } = require('dotenv');
const {
  assertTarget,
  externalDirectory,
  inspect,
  TABLES,
} = require('./development-data.cjs');
const ROOT = path.resolve(__dirname, '../../..');
const STAFF_START = '2026-10-30';
const START = '2026-10-31',
  END = '2026-11-30',
  VERSION = 'queueb-development-dataset-v2';
const DAYS = ['MINGGU', 'SENIN', 'SELASA', 'RABU', 'KAMIS', 'JUMAT', 'SABTU'];
const SERVICES = [
  ['PENDAFTARAN', 'Pendaftaran', 'PEN', 'Nadia Putri'],
  ['APOTEK', 'Apotek', 'APT', 'Arif Hidayat'],
  ['LABORATORIUM', 'Laboratorium', 'LAB', 'Rina Maharani'],
  ['RADIOLOGI', 'Radiologi', 'RAD', 'Dimas Pratama'],
  ['KASIR', 'Kasir/Pembayaran', 'KSR', 'Fajar Maulana'],
  ['REKAM_MEDIS', 'Rekam Medis', 'RM', 'Salsa Nabila'],
];
const DELETE_ORDER = [
  'notifikasi',
  'peristiwa_antrean',
  'janji_temu',
  'tiket_antrean',
  'urutan_antrean_harian',
  'slot_praktik',
  'jadwal_praktik',
];
const sha = (value) => crypto.createHash('sha256').update(value).digest('hex');
const read = (file) =>
  JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
function assertPrivateDirectory(dir) {
  if (process.platform === 'win32') {
    // A secret-bearing batch must not inherit broad drive permissions.
    // The path is passed as data, never interpolated into PowerShell code.
    const aclEnv = { ...process.env, QUEUEB_V2_PRIVATE_DIR: dir };
    // Windows PowerShell must load its own modules, not an inherited pwsh path.
    delete aclEnv.PSModulePath;
    cp.execFileSync(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        "$ErrorActionPreference='Stop'; $a=Get-Acl -LiteralPath $env:QUEUEB_V2_PRIVATE_DIR; if(-not $a.AreAccessRulesProtected){exit 2}; $allowed=@([Security.Principal.WindowsIdentity]::GetCurrent().User.Value,'S-1-5-18'); foreach($r in $a.Access){if($r.AccessControlType -eq 'Allow'){if($r.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -notin $allowed){exit 3}}}",
      ],
      {
        env: aclEnv,
        stdio: 'ignore',
        windowsHide: true,
      },
    );
  } else {
    assert.equal(
      fs.statSync(dir).mode & 0o077,
      0,
      'Private directory permissions required',
    );
  }
}
function save(file, value) {
  const tmp = file + '.' + crypto.randomUUID() + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(value, null, 2) + '\n', {
    flag: 'wx',
    mode: 0o600,
  });
  fs.renameSync(tmp, file);
}
const email = (code) => code.toLowerCase() + '.petugas.dataset-v2@example.test';
const instant = (day, time) =>
  new Date(day + 'T' + time + ':00+07:00').toISOString();
function dates() {
  const out = [];
  for (
    let t = Date.parse(START + 'T00:00:00Z');
    t <= Date.parse(END + 'T00:00:00Z');
    t += 86400000
  )
    out.push(new Date(t).toISOString().slice(0, 10));
  return out;
}
async function fingerprint(db) {
  const result = {};
  for (const t of [...TABLES, '_prisma_migrations'])
    result[t] = (
      await db.query(
        'SELECT id::text,md5(to_jsonb(t)::text) hash FROM "' +
          t +
          '" t ORDER BY id',
      )
    ).rows;
  return result;
}
async function capture(db) {
  const all = async (sql) => (await db.query(sql)).rows;
  return {
    baseline: await fingerprint(db),
    users: await all('SELECT id,nama,email,peran,aktif FROM pengguna'),
    services: await all(
      'SELECT id,kode,nama,prefix_antrean,mode_reservasi,aktif,deskripsi FROM layanan',
    ),
    rooms: await all('SELECT id,layanan_id,kode,nama,aktif FROM loket'),
    hours: await all(
      'SELECT id,layanan_id,hari,jam_buka::text,jam_tutup::text,kapasitas_harian,aktif FROM jadwal_layanan',
    ),
    doctors: await all('SELECT id,kode,nama,pengguna_id,aktif FROM dokter'),
    links: await all('SELECT * FROM dokter_layanan'),
    assignments: await all(
      'SELECT *,tanggal_mulai::text,tanggal_selesai::text FROM penugasan_petugas',
    ),
    practices: await all('SELECT *,tanggal::text FROM jadwal_praktik'),
    slots: await all('SELECT * FROM slot_praktik'),
    tickets: await all(
      'SELECT id,pengguna_id,layanan_id,tanggal_antrean::text,dibuat_pada,diperbarui_pada FROM tiket_antrean',
    ),
    appointments: await all('SELECT * FROM janji_temu'),
    events: await all(
      'SELECT id,tiket_antrean_id,aktor_id,terjadi_pada FROM peristiwa_antrean',
    ),
    notifications: await all(
      'SELECT id,pengguna_id,tiket_antrean_id,dibuat_pada FROM notifikasi',
    ),
    counters: await all('SELECT *,tanggal::text FROM urutan_antrean_harian'),
  };
}
function buildPlan(i, evidence, registry = { created: {} }) {
  const { state, accounts, checkpoint } = evidence;
  assert.equal(state.version, 'queueb-synthetic-20261027-v1');
  assert.equal(state.complete, true);
  const within = (value) =>
    Date.parse(value) >= Date.parse(state.startedAt) &&
    Date.parse(value) <= Date.parse(state.completedAt);
  const seededUsers = new Set(
    i.users
      .filter((u) =>
        accounts.some((c) => c.email === u.email && c.role === u.peran),
      )
      .map((u) => u.id),
  );
  const candidates = i.tickets.filter(
    (t) =>
      seededUsers.has(t.pengguna_id) &&
      state.clinics.includes(t.layanan_id) &&
      within(t.dibuat_pada),
  );
  const blocked = [],
    eligible = [];
  for (const t of candidates) {
    const later =
      !within(t.diperbarui_pada) ||
      i.events.some(
        (e) =>
          e.tiket_antrean_id === t.id &&
          (!within(e.terjadi_pada) ||
            (e.aktor_id && !seededUsers.has(e.aktor_id))),
      ) ||
      i.appointments.some(
        (a) =>
          a.tiket_id === t.id &&
          (!within(a.dibuat_pada) || !within(a.diperbarui_pada)),
      ) ||
      i.notifications.some(
        (n) =>
          n.tiket_antrean_id === t.id &&
          (!within(n.dibuat_pada) || !seededUsers.has(n.pengguna_id)),
      );
    if (later)
      blocked.push({
        model: 'tiket_antrean',
        id: t.id,
        reason: 'Later or unverified activity/dependency; preserved',
      });
    else eligible.push(t.id);
  }
  const ids = new Set(eligible),
    cleanup = Object.fromEntries(DELETE_ORDER.map((t) => [t, []]));
  cleanup.tiket_antrean = eligible;
  cleanup.peristiwa_antrean = i.events
    .filter((e) => ids.has(e.tiket_antrean_id))
    .map((e) => e.id);
  cleanup.janji_temu = i.appointments
    .filter((a) => ids.has(a.tiket_id))
    .map((a) => a.id);
  cleanup.notifikasi = i.notifications
    .filter((n) => ids.has(n.tiket_antrean_id))
    .map((n) => n.id);
  cleanup.urutan_antrean_harian = i.counters
    .filter(
      (c) =>
        state.clinics.includes(c.layanan_id) &&
        within(c.diperbarui_pada) &&
        i.tickets.some(
          (t) =>
            ids.has(t.id) &&
            t.layanan_id === c.layanan_id &&
            t.tanggal_antrean === c.tanggal,
        ) &&
        !i.tickets.some(
          (t) =>
            !ids.has(t.id) &&
            t.layanan_id === c.layanan_id &&
            t.tanggal_antrean === c.tanggal,
        ),
    )
    .map((c) => c.id);
  const oldHash = (table, id) =>
    checkpoint.baseline[table]?.find((r) => r.id === id)?.hash;
  const currentHash = (table, id) =>
    i.baseline[table]?.find((r) => r.id === id)?.hash;
  for (const p of i.practices.filter(
    (p) => state.practices.includes(p.id) && p.tanggal < START,
  )) {
    const slots = i.slots.filter((s) => s.jadwal_praktik_id === p.id);
    const dependency = i.appointments.some(
      (a) =>
        slots.some((s) => s.id === a.slot_praktik_id) &&
        !cleanup.janji_temu.includes(a.id),
    );
    if (
      dependency ||
      oldHash('jadwal_praktik', p.id) !== currentHash('jadwal_praktik', p.id) ||
      slots.some(
        (s) =>
          !oldHash('slot_praktik', s.id) ||
          oldHash('slot_praktik', s.id) !== currentHash('slot_praktik', s.id),
      )
    ) {
      blocked.push({
        model: 'jadwal_praktik',
        id: p.id,
        reason: 'Unknown dependency or changed schedule/slot; preserved',
      });
      continue;
    }
    cleanup.slot_praktik.push(...slots.map((s) => s.id));
    cleanup.jadwal_praktik.push(p.id);
  }
  const servicePlan = SERVICES.map(([code, name, prefix, staff]) => {
    const existing = i.services.find((s) => s.kode === code);
    if (existing)
      assert(
        existing.aktif && existing.mode_reservasi === 'ANTREAN_HARIAN',
        'Existing daily service incompatible: ' + code,
      );
    const ownId = registry.created?.['staff/' + code];
    const account = i.users.find((u) => u.email === email(code));
    if (account)
      assert.equal(
        account.id,
        ownId,
        'Unowned account email collision: ' + code,
      );
    return {
      code,
      name,
      prefix,
      staff,
      email: email(code),
      existingService: existing?.id,
      existingRoom: i.rooms.find(
        (r) => r.layanan_id === existing?.id && r.aktif,
      )?.id,
      accountId: account?.id,
      createService: !existing,
      createStaff: !account,
    };
  });
  const practicePlan = [],
    kept = i.practices.filter(
      (p) => !cleanup.jadwal_praktik.includes(p.id) && p.aktif,
    );
  for (const d of i.doctors.filter((d) => d.aktif)) {
    const user = i.users.find((u) => u.id === d.pengguna_id);
    assert(
      user && user.aktif && user.peran === 'DOKTER',
      'Active doctor has no valid DOKTER account: ' + d.kode,
    );
    const links = i.links.filter(
      (l) =>
        l.dokter_id === d.id &&
        l.aktif &&
        i.services.some((s) => s.id === l.layanan_id && s.aktif),
    );
    assert(links.length, 'Active doctor has no valid service: ' + d.kode);
    if (
      kept.some(
        (p) =>
          p.tanggal >= START &&
          p.tanggal <= END &&
          links.some((l) => l.id === p.dokter_layanan_id),
      )
    )
      continue;
    const link = links[0];
    for (const day of dates()) {
      const dow = new Date(day + 'T00:00:00Z').getUTCDay();
      if (dow === 0) continue;
      const hours = i.hours.find(
        (h) =>
          h.layanan_id === link.layanan_id && h.hari === DAYS[dow] && h.aktif,
      );
      assert(hours, 'Doctor missing operational calendar: ' + d.kode);
      let chosen;
      for (const room of i.rooms.filter(
        (r) => r.layanan_id === link.layanan_id && r.aktif,
      )) {
        for (const [start, end] of dow === 6
          ? [['08:00', '12:00']]
          : [
              ['08:00', '12:00'],
              ['13:00', '16:00'],
            ]) {
          if (
            start < hours.jam_buka.slice(0, 5) ||
            end > hours.jam_tutup.slice(0, 5)
          )
            continue;
          const from = instant(day, start),
            to = instant(day, end);
          const overlap = kept
            .concat(practicePlan)
            .some(
              (p) =>
                p.aktif !== false &&
                p.tanggal === day &&
                (p.loket_id === room.id ||
                  i.links.find((l) => l.id === p.dokter_layanan_id)
                    ?.dokter_id === d.id) &&
                Date.parse(p.mulai_pada) < Date.parse(to) &&
                Date.parse(from) < Date.parse(p.selesai_pada),
            );
          if (!overlap) {
            chosen = {
              dokter_layanan_id: link.id,
              loket_id: room.id,
              tanggal: day,
              mulai_pada: from,
              selesai_pada: to,
              doctorCode: d.kode,
            };
            break;
          }
        }
        if (chosen) break;
      }
      assert(chosen, 'No conflict-free practice window: ' + d.kode + ' ' + day);
      practicePlan.push(chosen);
    }
  }
  return {
    version: VERSION,
    target: '127.0.0.1:5433/capstone_antrean',
    period: [START, END],
    assignmentPeriod: [STAFF_START, END],
    createdAt: new Date().toISOString(),
    adminId: state.adminId,
    baseline: i.baseline,
    cleanup,
    blocked,
    services: servicePlan,
    practices: practicePlan,
    preservation: {
      users: i.users.length,
      sessions: i.baseline.sesi_pengguna.length,
      devices: i.baseline.perangkat_tampilan.length,
      unclassifiedTickets: i.tickets.length - candidates.length,
    },
    summary: {
      delete: Object.fromEntries(
        Object.entries(cleanup).map(([t, ids]) => [t, ids.length]),
      ),
      blocked: blocked.length,
      newServices: servicePlan.filter((s) => s.createService).length,
      newStaff: servicePlan.filter((s) => s.createStaff).length,
      newPractices: practicePlan.length,
      reusedTargetPractices: kept.filter(
        (p) => p.tanggal >= START && p.tanggal <= END,
      ).length,
    },
  };
}
async function cleanup(db, plan) {
  for (const [table, ids] of Object.entries(plan.cleanup)) {
    assert(DELETE_ORDER.includes(table));
    assert.equal(ids.length, new Set(ids).size);
    assert(
      ids.every(
        (id) =>
          /^[0-9a-f-]{36}$/i.test(id) &&
          plan.baseline[table].some((r) => r.id === id),
      ),
      'Unallowlisted cleanup ID',
    );
  }
  await db.query('BEGIN');
  try {
    await db.query("SET LOCAL lock_timeout='5s'");
    await db.query("SET LOCAL statement_timeout='15s'");
    await db.query(
      'LOCK TABLE ' +
        [...TABLES, '_prisma_migrations'].map((t) => '"' + t + '"').join(',') +
        ' IN SHARE ROW EXCLUSIVE MODE',
    );
    const before = await fingerprint(db);
    for (const t of Object.keys(before))
      if (t !== 'sesi_pengguna')
        assert.deepEqual(
          before[t],
          plan.baseline[t],
          'Baseline changed before cleanup: ' + t,
        );
    const removed = {};
    for (const t of DELETE_ORDER) {
      const ids = plan.cleanup[t];
      if (!ids.length) {
        removed[t] = 0;
        continue;
      }
      const r = await db.query(
        'DELETE FROM "' + t + '" WHERE id = ANY($1::uuid[]) RETURNING id',
        [ids],
      );
      assert.equal(r.rowCount, ids.length, 'Cleanup row count mismatch');
      removed[t] = r.rowCount;
    }
    const after = await fingerprint(db);
    for (const t of Object.keys(before))
      assert.deepEqual(
        after[t],
        before[t].filter((r) => !plan.cleanup[t]?.includes(r.id)),
        'Unplanned cleanup change: ' + t,
      );
    await db.query('COMMIT');
    return { removed, before, after };
  } catch (e) {
    await db.query('ROLLBACK');
    throw e;
  }
}
function domains(config) {
  require('reflect-metadata');
  const { Logger } = require('@nestjs/common');
  Logger.overrideLogger(['error', 'warn']);
  const { ConfigService } = require('@nestjs/config');
  const load = (dir, cls) => require('../dist/' + dir)[cls];
  const db = new (load('prisma/prisma.service', 'PrismaService'))(
    new ConfigService(config),
  );
  const password = new (load('auth/password.service', 'PasswordService'))();
  return {
    db,
    password,
    service: new (load('layanan/layanan.service', 'LayananService'))(db),
    room: new (load('loket/loket.service', 'LoketService'))(db),
    hours: new (load(
      'jadwal-layanan/jadwal-layanan.service',
      'JadwalLayananService',
    ))(db),
    staff: new (load(
      'akun-petugas/akun-petugas.service',
      'AkunPetugasService',
    ))(db, password),
    assignment: new (load(
      'penugasan-petugas/penugasan-petugas.service',
      'PenugasanPetugasService',
    ))(db),
    practice: new (load(
      'jadwal-praktik/jadwal-praktik.service',
      'JadwalPraktikService',
    ))(db, new ConfigService(config)),
    slot: new (load('slot-praktik/slot-praktik.service', 'SlotPraktikService'))(
      db,
    ),
  };
}
async function provision(d, plan, dir, state) {
  const stateFile = path.join(dir, 'dataset-v2-state.json'),
    credentialFile = path.join(dir, 'dataset-v2-credentials.json');
  const credentials = fs.existsSync(credentialFile)
    ? read(credentialFile)
    : { version: VERSION, synthetic: true, accounts: [] };
  const journal = () => save(stateFile, state);
  async function ensure(key, find, valid, create) {
    let row = await find();
    if (row) {
      assert(valid(row), 'Existing record differs: ' + key);
      if (!state.created[key]) {
        assert(
          state.pending === key || key.startsWith('reuse/'),
          'Unowned stable-key collision: ' + key,
        );
        state.created[key] = row.id;
        journal();
      }
      return row;
    }
    assert(!state.created[key], 'Previously created record missing: ' + key);
    state.pending = key;
    journal();
    row = await create();
    assert(valid(row), 'Created record differs: ' + key);
    state.created[key] = row.id;
    state.pending = null;
    journal();
    return row;
  }
  for (const s of plan.services) {
    const key = (s.existingService ? 'reuse/' : '') + 'service/' + s.code;
    const service = await ensure(
      key,
      () => d.db.layanan.findUnique({ where: { kode: s.code } }),
      (r) =>
        r.aktif &&
        r.modeReservasi === 'ANTREAN_HARIAN' &&
        (s.existingService ||
          (r.nama === s.name && r.prefixAntrean === s.prefix)),
      () =>
        d.service.create({
          kode: s.code,
          nama: s.name,
          prefixAntrean: s.prefix,
          durasiDasarMenit: 15,
          modeReservasi: 'ANTREAN_HARIAN',
          deskripsi:
            'Layanan simulasi pengembangan Dataset V2; bukan konfigurasi operasional resmi.',
        }),
    );
    const roomKey = (s.existingRoom ? 'reuse/' : '') + 'room/' + s.code;
    const room = await ensure(
      roomKey,
      () =>
        s.existingRoom
          ? d.db.loket.findUnique({ where: { id: s.existingRoom } })
          : d.db.loket.findUnique({
              where: {
                layananId_kode: {
                  layananId: service.id,
                  kode: s.prefix + '01',
                },
              },
            }),
      (r) => r.layananId === service.id && r.aktif,
      () =>
        d.room.create({
          layananId: service.id,
          kode: s.prefix + '01',
          nama: 'Loket ' + s.name,
          lokasi: 'Simulasi pengembangan V2',
        }),
    );
    for (const hari of DAYS.slice(1)) {
      const existing = await d.db.jadwalLayanan.findUnique({
        where: { layananId_hari: { layananId: service.id, hari } },
      });
      if (s.existingService && existing) {
        assert(existing.aktif);
        continue;
      }
      const close = hari === 'SABTU' ? '12:00' : '16:00';
      await ensure(
        'hours/' + s.code + '/' + hari,
        () =>
          d.db.jadwalLayanan.findUnique({
            where: { layananId_hari: { layananId: service.id, hari } },
          }),
        (r) =>
          r.aktif &&
          r.kapasitasHarian === 80 &&
          r.jamBuka.toISOString().slice(11, 16) === '08:00' &&
          r.jamTutup.toISOString().slice(11, 16) === close,
        () =>
          d.hours.create({
            layananId: service.id,
            hari,
            jamBuka: '08:00',
            jamTutup: close,
            kapasitasHarian: 80,
          }),
      );
    }
    let cred = credentials.accounts.find((c) => c.email === s.email);
    if (!cred) {
      cred = {
        name: s.staff,
        email: s.email,
        role: 'PETUGAS',
        password: crypto.randomBytes(24).toString('base64url'),
      };
      credentials.accounts.push(cred);
      save(credentialFile, credentials);
    }
    const staff = await ensure(
      'staff/' + s.code,
      () => d.db.pengguna.findUnique({ where: { email: s.email } }),
      (r) => r.nama === s.staff && r.peran === 'PETUGAS' && r.aktif,
      () =>
        d.staff.create(
          { nama: s.staff, email: s.email, kataSandi: cred.password },
          plan.adminId,
        ),
    );
    const full = await d.db.pengguna.findUnique({ where: { id: staff.id } });
    assert(
      await d.password.verify(cred.password, full.kataSandiHash),
      'Owned account password drift',
    );
    await ensure(
      'assignment/' + s.code,
      () =>
        d.db.penugasanPetugas.findFirst({
          where: {
            petugasId: staff.id,
            loketId: room.id,
            tanggalMulai: new Date(STAFF_START + 'T00:00:00Z'),
            tanggalSelesai: new Date(END + 'T00:00:00Z'),
            aktif: true,
          },
        }),
      (r) => r.petugasId === staff.id && r.loketId === room.id && r.aktif,
      () =>
        d.assignment.create({
          petugasId: staff.id,
          loketId: room.id,
          tanggalMulai: STAFF_START,
          tanggalSelesai: END,
        }),
    );
  }
  for (const p of plan.practices) {
    const session = await ensure(
      'practice/' + p.dokter_layanan_id + '/' + p.tanggal,
      () =>
        d.db.jadwalPraktik.findUnique({
          where: {
            dokterLayananId_mulaiPada: {
              dokterLayananId: p.dokter_layanan_id,
              mulaiPada: new Date(p.mulai_pada),
            },
          },
        }),
      (r) =>
        r.loketId === p.loket_id &&
        r.aktif &&
        r.selesaiPada.toISOString() === p.selesai_pada,
      () =>
        d.practice.create({
          dokterLayananId: p.dokter_layanan_id,
          loketId: p.loket_id,
          tanggal: p.tanggal,
          mulaiPada: p.mulai_pada,
          selesaiPada: p.selesai_pada,
        }),
    );
    for (
      let t = Date.parse(p.mulai_pada);
      t < Date.parse(p.selesai_pada);
      t += 1200000
    ) {
      const from = new Date(t),
        to = new Date(t + 1200000);
      await ensure(
        'slot/' + session.id + '/' + from.toISOString(),
        () =>
          d.db.slotPraktik.findUnique({
            where: {
              jadwalPraktikId_mulaiPada: {
                jadwalPraktikId: session.id,
                mulaiPada: from,
              },
            },
          }),
        (r) =>
          r.aktif &&
          r.kapasitas === 2 &&
          r.selesaiPada.toISOString() === to.toISOString(),
        () =>
          d.slot.create({
            jadwalPraktikId: session.id,
            mulaiPada: from.toISOString(),
            selesaiPada: to.toISOString(),
            kapasitas: 2,
          }),
      );
    }
  }
  state.complete = true;
  state.completedAt = new Date().toISOString();
  journal();
}
async function verify(db, plan, state) {
  const after = await capture(db),
    removed = plan.cleanup;
  for (const t of Object.keys(plan.baseline)) {
    for (const row of plan.baseline[t]) {
      const actual = after.baseline[t].find((r) => r.id === row.id);
      if (removed[t]?.includes(row.id))
        assert(!actual, 'Deleted fixture returned');
      else
        assert(
          actual && actual.hash === row.hash,
          'Pre-existing record changed: ' + t,
        );
    }
  }
  const overlap = after.practices
    .filter((p) => p.aktif)
    .some((a, index, all) =>
      all
        .slice(index + 1)
        .some(
          (b) =>
            a.tanggal === b.tanggal &&
            (a.loket_id === b.loket_id ||
              after.links.find((l) => l.id === a.dokter_layanan_id)
                ?.dokter_id ===
                after.links.find((l) => l.id === b.dokter_layanan_id)
                  ?.dokter_id) &&
            Date.parse(a.mulai_pada) < Date.parse(b.selesai_pada) &&
            Date.parse(b.mulai_pada) < Date.parse(a.selesai_pada),
        ),
    );
  assert(!overlap, 'Active doctor/room overlap');
  for (const p of after.practices.filter((p) =>
    Object.values(state.created).includes(p.id),
  ))
    assert(
      p.tanggal >= START && p.tanggal <= END,
      'New practice outside target',
    );
  for (const p of after.practices) {
    const slots = after.slots
      .filter((s) => s.jadwal_praktik_id === p.id)
      .sort((a, b) => Date.parse(a.mulai_pada) - Date.parse(b.mulai_pada));
    for (let n = 0; n < slots.length; n++) {
      const s = slots[n];
      assert(
        s.kapasitas > 0 &&
          Date.parse(s.mulai_pada) >= Date.parse(p.mulai_pada) &&
          Date.parse(s.selesai_pada) <= Date.parse(p.selesai_pada),
      );
      if (n)
        assert(
          Date.parse(slots[n - 1].selesai_pada) <= Date.parse(s.mulai_pada),
          'Slot overlap',
        );
    }
  }
  for (const s of plan.services) {
    const u = after.users.find(
      (u) => u.id === state.created['staff/' + s.code],
    );
    assert(u && u.peran === 'PETUGAS' && u.aktif);
    assert.equal(
      after.assignments.filter(
        (a) =>
          a.petugas_id === u.id &&
          a.aktif &&
          a.tanggal_mulai === STAFF_START &&
          a.tanggal_selesai === END,
      ).length,
      1,
    );
  }
  for (const d of after.doctors.filter((d) => d.aktif))
    assert(
      after.practices.some(
        (p) =>
          p.aktif &&
          p.tanggal >= START &&
          p.tanggal <= END &&
          after.links.some(
            (l) => l.id === p.dokter_layanan_id && l.dokter_id === d.id,
          ),
      ),
      'Doctor without target practice',
    );
  return {
    version: VERSION,
    counts: Object.fromEntries(
      Object.entries(after.baseline).map(([t, r]) => [t, r.length]),
    ),
    removed: Object.fromEntries(
      Object.entries(removed).map(([t, ids]) => [t, ids.length]),
    ),
    preservedBaseline: true,
    devicesUnchanged: true,
    adminAndExistingAccountsUnchanged: true,
    scheduleOverlap: 0,
    slotOverlap: 0,
    allNewPracticesWithinTarget: true,
    activeDoctors: after.doctors.filter((d) => d.aktif).length,
    targetPractices: after.practices.filter(
      (p) => p.tanggal >= START && p.tanggal <= END,
    ).length,
    blocked: plan.blocked.length,
  };
}
async function main(argv = process.argv.slice(2)) {
  const [mode, ...rest] = argv,
    args = Object.fromEntries(
      rest.map((s) => {
        const n = s.indexOf('=');
        assert(n > 0);
        return [s.slice(0, n), s.slice(n + 1)];
      }),
    );
  assert(
    ['plan', 'apply', 'verify', 'smoke'].includes(mode),
    'Use plan|apply|verify|smoke',
  );
  const config = parse(fs.readFileSync(path.join(ROOT, '.env')));
  if (process.env.DATABASE_URL)
    assert.equal(
      process.env.DATABASE_URL,
      config.DATABASE_URL,
      'Ambient target differs',
    );
  assertTarget(
    config.DATABASE_URL,
    process.env.NODE_ENV || config.NODE_ENV || 'development',
  );
  assert(
    !config.SERVICE_TIME_ZONE || config.SERVICE_TIME_ZONE === 'Asia/Jakarta',
  );
  const dir = externalDirectory(args['--output']);
  assertPrivateDirectory(dir);
  const db = new Client({
    connectionString: config.DATABASE_URL,
    application_name: 'queueb-dataset-v2-maintenance',
  });
  await db.connect();
  try {
    const stateFile = path.join(dir, 'dataset-v2-state.json');
    const state = fs.existsSync(stateFile)
      ? read(stateFile)
      : {
          version: VERSION,
          created: {},
          complete: false,
          cleanupComplete: false,
        };
    const wasComplete = state.complete;
    assert.equal(state.version, VERSION);
    const planFile = path.join(
      dir,
      path.basename(args['--plan'] || args['--report'] || 'plan.json'),
    );
    if (mode === 'plan') {
      const seed = read(path.join(args['--source-batch'], 'seed-state.json'));
      const accounts = read(
        path.join(args['--source-batch'], 'akun-pengujian.json'),
      ).accounts;
      const checkpoint = read(args['--provenance-checkpoint']);
      await db.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
      await inspect(db, seed.adminId);
      const plan = buildPlan(
        await capture(db),
        { state: seed, accounts, checkpoint },
        state,
      );
      plan.evidence = {
        sourceManifestSha: sha(
          fs.readFileSync(path.join(args['--source-batch'], 'seed-state.json')),
        ),
        checkpointSha: sha(fs.readFileSync(args['--provenance-checkpoint'])),
      };
      await db.query('ROLLBACK');
      assert(
        !fs.existsSync(planFile),
        'Plan report already exists; use a new --report name',
      );
      save(planFile, plan);
      console.log(JSON.stringify(plan.summary));
      return;
    }
    const plan = read(planFile);
    assert.equal(plan.version, VERSION);
    assert.equal(plan.target, '127.0.0.1:5433/capstone_antrean');
    const hash = sha(fs.readFileSync(planFile));
    if (state.planSha) assert.equal(state.planSha, hash);
    await db.query('BEGIN READ ONLY');
    await inspect(db, plan.adminId);
    await db.query('ROLLBACK');
    if (mode === 'smoke') {
      assert(state.complete, 'Provisioning incomplete');
      return await require('./development-dataset-v2-smoke.cjs').smoke(
        config,
        args,
        plan,
        state,
        dir,
      );
    }
    if (mode === 'apply') {
      assert.equal(args['--confirm'], 'APPLY-DATASET-V2');
      const backup = read(args['--backup-checkpoint']);
      assert.equal(backup.target, plan.target);
      assert.equal(backup.admin.id, plan.adminId);
      assert(backup.backup.fullOfflineDecode && backup.backup.archiveList);
      assert(
        Date.now() - Date.parse(backup.createdAt) < 3600000,
        'Backup older than one hour',
      );
      assert.equal(
        sha(fs.readFileSync(backup.backup.path)),
        backup.backup.sha256,
        'Backup checksum differs',
      );
      cp.execFileSync(
        path.join(
          args['--pg-bin'] || 'C:/Program Files/PostgreSQL/18/bin',
          'pg_restore.exe',
        ),
        ['--file=-', backup.backup.path],
        { stdio: 'ignore', windowsHide: true },
      );
      if (!state.cleanupComplete) {
        state.planSha = hash;
        save(stateFile, state);
        const result = await cleanup(db, plan);
        save(path.join(dir, 'cleanup-result.json'), result);
        state.cleanupComplete = true;
        save(stateFile, state);
      }
      if (!state.complete) {
        const d = domains({ ...config, SERVICE_TIME_ZONE: 'Asia/Jakarta' });
        try {
          await d.db.$connect();
          await provision(d, plan, dir, state);
        } finally {
          await d.db.$disconnect();
        }
      }
    }
    assert(state.complete, 'Provisioning incomplete; inspect private journal');
    await db.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
    await inspect(db, plan.adminId);
    const result = await verify(db, plan, state);
    await db.query('ROLLBACK');
    save(path.join(dir, 'verification.json'), result);
    console.log(
      JSON.stringify({ ...result, noOp: mode === 'verify' || wasComplete }),
    );
  } finally {
    await db.end();
  }
}
module.exports = {
  buildPlan,
  cleanup,
  fingerprint,
  capture,
  dates,
  instant,
  START,
  END,
  SERVICES,
  DELETE_ORDER,
  assertPrivateDirectory,
  main,
};
if (require.main === module)
  main().catch((e) => {
    console.error(
      'Dataset V2 stopped: ' +
        (typeof e.getStatus === 'function'
          ? 'HTTP ' + e.getStatus()
          : e.code || e.name) +
        '; inspect private plan/journal. No reset or automatic restore.',
    );
    process.exitCode = 1;
  });
