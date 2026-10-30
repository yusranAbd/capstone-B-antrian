// Read-only V2 audit. Never logs in, refreshes, provisions or cleans up data.
const fs = require('node:fs'),
  path = require('node:path'),
  cp = require('node:child_process'),
  crypto = require('node:crypto'),
  assert = require('node:assert/strict');
const { Client } = require('pg'),
  { parse } = require('dotenv');
const { assertTarget, inspect } = require('./development-data.cjs');
const {
  assertPrivateDirectory,
  capture,
  fingerprint,
  START,
  END,
  SERVICES,
} = require('./development-dataset-v2.cjs');
const ROOT = path.resolve(__dirname, '../../..');
const read = (f) =>
  JSON.parse(fs.readFileSync(f, 'utf8').replace(/^\uFEFF/, ''));
const sha = (x) => crypto.createHash('sha256').update(x).digest('hex');
const safeId = (id) => sha(id).slice(0, 16);
function parseSessionArchive(sql) {
  const lines = sql.split(/\r?\n/),
    at = lines.findIndex((s) => s.startsWith('COPY public.sesi_pengguna '));
  assert(at >= 0, 'Session table not found in archive');
  const columns = lines[at].match(/\((.+)\) FROM stdin/)[1].split(', '),
    rows = [];
  for (let n = at + 1; n < lines.length && lines[n] !== '\\.'; n++) {
    const values = lines[n].split('\t');
    assert.equal(values.length, columns.length, 'Malformed COPY row');
    rows.push(
      Object.fromEntries(
        columns.map((c, i) => [c, values[i] === '\\N' ? null : values[i]]),
      ),
    );
  }
  return rows;
}
function sessionFindings(before, current, historical, smokeIds, refreshTtlMs) {
  const smokeOwners = new Set(
    current.filter((r) => smokeIds.includes(r.id)).map((r) => r.pengguna_id),
  );
  return historical.map((h) => {
    const prior = before.find((r) => safeId(r.id) === h.sessionHash),
      now = current.find((r) => safeId(r.id) === h.sessionHash);
    if (!prior || !now)
      return {
        session: h.sessionHash,
        status: 'UNATTRIBUTED',
        present: !!now,
        reason: 'Historical row missing; not normalized',
      };
    const fields = Object.keys(prior).filter((k) => {
      if (['dibuat_pada', 'dicabut_pada', 'kedaluwarsa_pada'].includes(k))
        return (
          (prior[k] ? new Date(prior[k]).toISOString() : null) !==
          (now[k] ? new Date(now[k]).toISOString() : null)
        );
      return prior[k] !== now[k];
    });
    const compatible =
      fields.length === 2 &&
      fields.includes('token_refresh_hash') &&
      fields.includes('kedaluwarsa_pada') &&
      Date.parse(now.kedaluwarsa_pada) > Date.parse(prior.kedaluwarsa_pada);
    return {
      session: h.sessionHash,
      role: now.peran,
      present: true,
      status: 'UNATTRIBUTED',
      changedFields: fields,
      historicalObservedRotation: new Date(
        Date.parse(h.afterExpires) - refreshTtlMs,
      ).toISOString(),
      latestRotationEstimate: new Date(
        new Date(now.kedaluwarsa_pada).getTime() - refreshTtlMs,
      ).toISOString(),
      originalExpiry: prior.kedaluwarsa_pada,
      currentExpiry: now.kedaluwarsa_pada,
      originalClientLabel:
        prior.nama_perangkat === 'QueueB Flutter'
          ? 'QueueB Flutter'
          : 'other label withheld',
      ownerUsedByV2Smoke: smokeOwners.has(now.pengguna_id),
      sessionCreatedByV2Smoke: smokeIds.includes(now.id),
      existingRefreshMechanismCompatible: compatible,
      caller: 'UNATTRIBUTED',
      attribution:
        'Column compatibility and client timer source do not establish request origin',
    };
  });
}
function datasetFindings(i, plan, state) {
  const target = i.practices.filter(
      (p) => p.tanggal >= START && p.tanggal <= END,
    ),
    allActive = i.practices.filter((p) => p.aktif);
  const newPracticeIds = Object.entries(state.created)
    .filter(([k]) => k.startsWith('practice/'))
    .map(([, v]) => v);
  const newSlotIds = Object.entries(state.created)
    .filter(([k]) => k.startsWith('slot/'))
    .map(([, v]) => v);
  const doctorOf = (p) =>
    i.links.find((l) => l.id === p.dokter_layanan_id)?.dokter_id;
  let conflicts = 0;
  for (let n = 0; n < allActive.length; n++)
    for (const b of allActive.slice(n + 1)) {
      const a = allActive[n];
      if (
        a.tanggal === b.tanggal &&
        (a.loket_id === b.loket_id || doctorOf(a) === doctorOf(b)) &&
        Date.parse(a.mulai_pada) < Date.parse(b.selesai_pada) &&
        Date.parse(b.mulai_pada) < Date.parse(a.selesai_pada)
      )
        conflicts++;
    }
  const dayWib = (date) =>
    new Intl.DateTimeFormat('en-CA', {
      timeZone: 'Asia/Jakarta',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).format(new Date(date));
  let invalidSlots = 0,
    slotOverlap = 0;
  const quota = new Map();
  for (const p of i.practices) {
    const slots = i.slots
      .filter((s) => s.jadwal_praktik_id === p.id)
      .sort((a, b) => Date.parse(a.mulai_pada) - Date.parse(b.mulai_pada));
    for (let n = 0; n < slots.length; n++) {
      const s = slots[n];
      if (
        s.kapasitas <= 0 ||
        Date.parse(s.mulai_pada) >= Date.parse(s.selesai_pada) ||
        Date.parse(s.mulai_pada) < Date.parse(p.mulai_pada) ||
        Date.parse(s.selesai_pada) > Date.parse(p.selesai_pada) ||
        dayWib(s.mulai_pada) !== p.tanggal
      )
        invalidSlots++;
      if (n && Date.parse(slots[n - 1].selesai_pada) > Date.parse(s.mulai_pada))
        slotOverlap++;
    }
    if (p.aktif && target.includes(p)) {
      const link = i.links.find((l) => l.id === p.dokter_layanan_id);
      const key = link.layanan_id + '/' + p.tanggal;
      quota.set(
        key,
        (quota.get(key) || 0) +
          slots.filter((s) => s.aktif).reduce((n, s) => n + s.kapasitas, 0),
      );
    }
  }
  const days = ['MINGGU', 'SENIN', 'SELASA', 'RABU', 'KAMIS', 'JUMAT', 'SABTU'];
  const capacityExceeded = [...quota].filter(([key, total]) => {
    const [service, day] = key.split('/'),
      h = i.hours.find(
        (h) =>
          h.layanan_id === service &&
          h.hari === days[new Date(day + 'T00:00:00Z').getUTCDay()] &&
          h.aktif,
      );
    return !h || total > h.kapasitas_harian;
  }).length;
  const doctors = i.doctors.map((d) => {
    const user = i.users.find((u) => u.id === d.pengguna_id),
      links = i.links.filter((l) => l.dokter_id === d.id && l.aktif),
      practices = target.filter(
        (p) => links.some((l) => l.id === p.dokter_layanan_id) && p.aktif,
      );
    return {
      code: d.kode,
      doctor: safeId(d.id),
      account: user ? safeId(user.id) : null,
      active: d.aktif,
      accountValid: !!user && user.aktif && user.peran === 'DOKTER',
      identityMatches: !!user && user.nama === d.nama,
      services: links.map(
        (l) => i.services.find((s) => s.id === l.layanan_id)?.kode,
      ),
      targetPractices: practices.length,
      roomRelationsValid: practices.every((p) =>
        i.rooms.some(
          (r) =>
            r.id === p.loket_id &&
            r.aktif &&
            r.layanan_id ===
              i.links.find((l) => l.id === p.dokter_layanan_id)?.layanan_id,
        ),
      ),
      staffCoverage: practices.every((p) =>
        i.assignments.some(
          (a) =>
            a.loket_id === p.loket_id &&
            a.aktif &&
            a.tanggal_mulai <= p.tanggal &&
            (!a.tanggal_selesai || a.tanggal_selesai >= p.tanggal) &&
            i.users.some(
              (u) => u.id === a.petugas_id && u.peran === 'PETUGAS' && u.aktif,
            ),
        ),
      ),
    };
  });
  const services = SERVICES.map(([code]) => {
    const s = i.services.find((s) => s.kode === code),
      rooms = i.rooms.filter((r) => r.layanan_id === s?.id && r.aktif),
      hours = i.hours.filter((h) => h.layanan_id === s?.id && h.aktif);
    const staffed = rooms.some((r) =>
      i.assignments.some(
        (a) =>
          a.loket_id === r.id &&
          a.aktif &&
          a.tanggal_mulai <= START &&
          (!a.tanggal_selesai || a.tanggal_selesai >= END) &&
          i.users.some(
            (u) => u.id === a.petugas_id && u.aktif && u.peran === 'PETUGAS',
          ),
      ),
    );
    return {
      code,
      active: !!s?.aktif,
      mode: s?.mode_reservasi,
      rooms: rooms.length,
      calendarDays: hours.length,
      staffCoverage: staffed,
      backendDailyCompatible:
        !!s?.aktif &&
        ['ANTREAN_HARIAN', 'HIBRIDA'].includes(s.mode_reservasi) &&
        rooms.length > 0 &&
        hours.length === 6 &&
        staffed,
    };
  });
  const duplicatePractices =
    i.practices.length -
    new Set(
      i.practices.map(
        (p) => p.dokter_layanan_id + '/' + new Date(p.mulai_pada).toISOString(),
      ),
    ).size;
  const duplicateSlots =
    i.slots.length -
    new Set(
      i.slots.map(
        (s) => s.jadwal_praktik_id + '/' + new Date(s.mulai_pada).toISOString(),
      ),
    ).size;
  const outsideNewPractices = i.practices.filter(
    (p) =>
      newPracticeIds.includes(p.id) &&
      !(p.tanggal >= START && p.tanggal <= END),
  ).length;
  const changed = {};
  for (const t of Object.keys(plan.baseline)) {
    const bad = plan.baseline[t].filter(
      (r) =>
        !plan.cleanup[t]?.includes(r.id) &&
        !i.baseline[t].some((a) => a.id === r.id && a.hash === r.hash),
    );
    if (bad.length) changed[t] = bad.length;
  }
  return {
    counts: Object.fromEntries(
      Object.entries(i.baseline).map(([t, r]) => [t, r.length]),
    ),
    doctors,
    services,
    schedule: {
      period: [START, END],
      target: target.length,
      reused: target.filter((p) =>
        plan.baseline.jadwal_praktik.some((r) => r.id === p.id),
      ).length,
      newTarget: target.filter((p) => newPracticeIds.includes(p.id)).length,
      newSlots: i.slots.filter((s) => newSlotIds.includes(s.id)).length,
      historicalPracticeSessions: i.practices.length - target.length,
      historicalAuthSessions: plan.baseline.sesi_pengguna.length,
      doctorRoomConflicts: conflicts,
      duplicatePractices,
      duplicateSlots,
      slotOverlap,
      invalidSlots,
      capacityExceeded,
      outsideNewPractices,
      boundaries: Object.fromEntries(
        ['2026-10-31', '2026-11-01', '2026-11-30'].map((day) => [
          day,
          target.filter((p) => p.tanggal === day).length,
        ]),
      ),
    },
    changedPreservedRows: changed,
    allBusinessPreserved: Object.keys(changed).every(
      (t) => t === 'sesi_pengguna',
    ),
  };
}
async function readModels(config, inventory) {
  // Reuse endpoint services without HTTP authentication or an application server.
  // PostgreSQL enforces read-only mode on every connection in this Prisma pool.
  const url = new URL(config.DATABASE_URL);
  url.searchParams.set('options', '-c default_transaction_read_only=on');
  const { ConfigService } = require('@nestjs/config');
  const { PrismaService } = require('../dist/prisma/prisma.service');
  const { LayananService } = require('../dist/layanan/layanan.service');
  const {
    JadwalPraktikService,
  } = require('../dist/jadwal-praktik/jadwal-praktik.service');
  const {
    PortalDokterService,
  } = require('../dist/portal-dokter/portal-dokter.service');
  const {
    SlotPraktikService,
  } = require('../dist/slot-praktik/slot-praktik.service');
  const settings = new ConfigService({
    ...config,
    DATABASE_URL: url.toString(),
  });
  const prisma = new PrismaService(settings);
  try {
    await prisma.$connect();
    const [identity] = await prisma.$queryRawUnsafe(
      "SELECT current_database() AS db,current_setting('default_transaction_read_only') AS readonly",
    );
    assert.equal(identity.db, 'capstone_antrean');
    assert.equal(identity.readonly, 'on');
    const catalog = new LayananService(prisma);
    const practices = new JadwalPraktikService(prisma, settings);
    const portal = new PortalDokterService(prisma);
    const slots = new SlotPraktikService(prisma);
    const result = {
      connectionReadOnly: true,
      httpAuthentication: 'NOT ATTEMPTED',
      catalogs: {},
      boundaries: {},
      doctors: [],
    };
    for (const role of ['ADMIN', 'USER']) {
      const services = await catalog.findAll(role);
      result.catalogs[role] = SERVICES.map((s) => s[0]).every((code) =>
        services.some((s) => s.kode === code && s.aktif),
      );
      const all = await practices.findAll(role);
      const target = all.filter((p) => {
        const day = p.tanggal.toISOString().slice(0, 10);
        return day >= START && day <= END;
      });
      assert.equal(target.length, 156);
      for (const day of [START, '2026-11-01', END]) {
        result.boundaries[role + '/' + day] = (
          await practices.findAll(role, { tanggal: day })
        ).length;
      }
    }
    for (const d of inventory.doctors) {
      const profile = await portal.profil(d.pengguna_id);
      assert.equal(profile.id, d.id);
      const visible = await practices.findAll('USER', { dokterId: d.id });
      const first = visible.find((p) => {
        const day = p.tanggal.toISOString().slice(0, 10);
        return day >= START && day <= END;
      });
      assert(first, 'Doctor must have a visible target practice');
      const own = await portal.jadwal(
        d.pengguna_id,
        first.tanggal.toISOString().slice(0, 10),
      );
      assert(own.some((p) => p.id === first.id));
      const available = await slots.findAll('USER', {
        jadwalPraktikId: first.id,
      });
      assert(
        available.length > 0,
        'Existing slot endpoint must read doctor slots',
      );
      result.doctors.push({
        code: d.kode,
        profile: true,
        ownSchedule: true,
        patientSchedule: true,
        slotRead: true,
      });
    }
    assert(Object.values(result.catalogs).every(Boolean));
    return result;
  } finally {
    await prisma.$disconnect();
  }
}
async function main(argv = process.argv.slice(2)) {
  const args = Object.fromEntries(
    argv.map((s) => {
      const at = s.indexOf('=');
      assert(at > 0);
      return [s.slice(0, at), s.slice(at + 1)];
    }),
  );
  const config = parse(fs.readFileSync(path.join(ROOT, '.env')));
  assertTarget(config.DATABASE_URL, config.NODE_ENV || 'development');
  if (process.env.DATABASE_URL)
    assert.equal(config.DATABASE_URL, process.env.DATABASE_URL);
  const dir = fs.realpathSync(args['--output']);
  assertPrivateDirectory(dir);
  const plan = read(path.join(dir, 'plan-final.json')),
    state = read(path.join(dir, 'dataset-v2-state.json')),
    historical = read(path.join(dir, 'existing-session-delta.json')),
    smoke = read(path.join(dir, 'http-smoke.json'));
  const backup = args['--backup'];
  const backupHash = sha(fs.readFileSync(backup));
  assert.equal(backupHash, args['--sha256'], 'Backup checksum mismatch');
  const original = parseSessionArchive(
    cp.execFileSync(
      path.join(
        args['--pg-bin'] || 'C:/Program Files/PostgreSQL/18/bin',
        'pg_restore.exe',
      ),
      ['--data-only', '--table=sesi_pengguna', '--file=-', backup],
      {
        encoding: 'utf8',
        maxBuffer: 8 * 1024 * 1024,
        windowsHide: true,
        stdio: ['ignore', 'pipe', 'ignore'],
      },
    ),
  );
  const ttl = /^(\d+)(s|m|h|d)$/.exec(config.JWT_REFRESH_EXPIRES_IN);
  assert(ttl);
  const ttlMs =
    Number(ttl[1]) * { s: 1000, m: 60000, h: 3600000, d: 86400000 }[ttl[2]];
  const db = new Client({
    connectionString: config.DATABASE_URL,
    options: '-c default_transaction_read_only=on',
    application_name: 'queueb-v2-final-readonly-audit',
  });
  await db.connect();
  try {
    await db.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
    const startedAt = new Date().toISOString();
    const identity = await inspect(db, plan.adminId);
    const inventory = await capture(db);
    const current = (
      await db.query(
        'SELECT s.*,p.peran FROM sesi_pengguna s JOIN pengguna p ON p.id=s.pengguna_id',
      )
    ).rows;
    const settings = (
      await db.query(
        "SELECT name,setting FROM pg_settings WHERE name IN ('logging_collector','log_destination','log_statement','log_min_duration_statement','log_connections','log_line_prefix')",
      )
    ).rows;
    const logfile = (await db.query('SELECT pg_current_logfile() name')).rows[0]
      .name;
    const activity = (
      await db.query(
        'SELECT application_name,state,count(*)::int connections FROM pg_stat_activity WHERE datname=current_database() AND pid<>pg_backend_pid() GROUP BY application_name,state',
      )
    ).rows;
    const dataset = datasetFindings(inventory, plan, state),
      sessions = sessionFindings(
        original,
        current,
        historical.changes,
        smoke.sessionsCreated,
        ttlMs,
      );
    const initial = inventory.baseline;
    await db.query('ROLLBACK');
    const serviceReads = await readModels(config, inventory);
    await db.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
    const final = await fingerprint(db);
    await db.query('ROLLBACK');
    const intervalUnchanged = JSON.stringify(initial) === JSON.stringify(final);
    const report = {
      startedAt,
      finishedAt: new Date().toISOString(),
      database: '127.0.0.1:5433/capstone_antrean',
      readOnly: true,
      backup: { sha256: backupHash, unchanged: true },
      foreignKeys: identity.foreignKeys,
      migrations: identity.migrations,
      sessions,
      dataset,
      serviceReads,
      logging: {
        settings,
        currentLogfile: logfile,
        applicationConnections: activity,
      },
      verification: {
        historicalStrict:
          Object.keys(dataset.changedPreservedRows).length === 0
            ? 'PASS'
            : 'FAIL',
        historicalSessionAttribution: sessions.every(
          (s) => s.status === 'VERIFIED',
        )
          ? 'PASS'
          : 'FAIL',
        readOnlyAuditWindow: intervalUnchanged ? 'PASS' : 'FAIL',
        stageAGate:
          sessions.every((s) => s.status === 'VERIFIED') &&
          Object.keys(dataset.changedPreservedRows).length === 0
            ? 'PASS'
            : 'FAIL',
      },
      baseline: initial,
      finalFingerprint: final,
      writesPerformed: 0,
      newLogins: 0,
      refreshRequests: 0,
    };
    const file = path.join(
      dir,
      path.basename(args['--report'] || 'final-verification-audit.json'),
    );
    assert(!fs.existsSync(file), 'Audit report exists; choose a new --report');
    fs.writeFileSync(file, JSON.stringify(report, null, 2) + '\n', {
      flag: 'wx',
      mode: 0o600,
    });
    console.log(
      JSON.stringify({
        report: file,
        backupVerified: true,
        verification: report.verification,
        sessions: sessions.map((s) => ({
          session: s.session,
          role: s.role,
          status: s.status,
          fields: s.changedFields,
          ownerUsedByV2Smoke: s.ownerUsedByV2Smoke,
          at: s.historicalObservedRotation,
        })),
        schedule: dataset.schedule,
        doctors: dataset.doctors.map((d) => ({
          code: d.code,
          valid: d.accountValid,
          nameMatch: d.identityMatches,
          sessions: d.targetPractices,
          staffCoverage: d.staffCoverage,
        })),
        dailyServices: dataset.services,
        logging: { settings, currentLogfile: logfile },
        writesPerformed: 0,
        newLogins: 0,
      }),
    );
    return report;
  } finally {
    await db.end();
  }
}
module.exports = {
  parseSessionArchive,
  sessionFindings,
  datasetFindings,
  main,
};
if (require.main === module)
  main()
    .then((report) => {
      if (
        Object.values(report.verification).some((status) => status !== 'PASS')
      )
        process.exitCode = 2;
    })
    .catch((e) => {
      console.error('Read-only audit stopped: ' + (e.code || e.name));
      process.exitCode = 1;
    });
