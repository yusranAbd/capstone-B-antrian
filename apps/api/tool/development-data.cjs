// Explicit development maintenance only. Never imported by application startup.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const cp = require('node:child_process');
const { Client } = require('pg');
const { parse } = require('dotenv');
const root = path.resolve(__dirname, '../../..');
const api = path.join(root, 'apps/api');
const TABLES = [
  'notifikasi',
  'peristiwa_antrean',
  'janji_temu',
  'tiket_antrean',
  'urutan_antrean_harian',
  'sesi_pengguna',
  'penugasan_petugas',
  'slot_praktik',
  'jadwal_praktik',
  'dokter_layanan',
  'dokter',
  'perangkat_tampilan',
  'jadwal_layanan',
  'loket',
  'layanan',
  'pengguna',
];
const sha = (v) => crypto.createHash('sha256').update(v).digest('hex');
function migrationMatches(sql, checksum) {
  return [sql, sql.replace(/\r\n/g, '\n'), sql.replace(/\r?\n/g, '\r\n')].some(
    (text) => sha(text) === checksum,
  );
}
const quote = (v) => '"' + v.replaceAll('"', '""') + '"';
function assertTarget(raw, environment) {
  const u = new URL(raw);
  if (
    !['postgres:', 'postgresql:'].includes(u.protocol) ||
    u.hostname !== '127.0.0.1' ||
    u.port !== '5433' ||
    u.pathname !== '/capstone_antrean' ||
    environment !== 'development' ||
    [...u.searchParams].some(([k, v]) => k !== 'schema' || v !== 'public')
  ) {
    throw Error(
      'Ditolak: hanya development 127.0.0.1:5433/capstone_antrean, schema public.',
    );
  }
  return u;
}
function externalDirectory(dir) {
  if (!dir || !path.isAbsolute(dir))
    throw Error('Direktori eksternal absolut wajib diisi.');
  fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
  const actual = fs.realpathSync(dir);
  // Reject all managed worktrees too, not just this checkout.
  const trees = cp
    .execFileSync('git', ['worktree', 'list', '--porcelain'], {
      cwd: root,
      encoding: 'utf8',
      windowsHide: true,
    })
    .split('\n')
    .filter((s) => s.startsWith('worktree '))
    .map((s) => s.slice(9).trim());
  for (const tree of trees) {
    const rel = path.relative(fs.realpathSync(tree), actual);
    if (
      !rel ||
      (!rel.startsWith('..' + path.sep) &&
        rel !== '..' &&
        !path.isAbsolute(rel))
    )
      throw Error('Backup dan kredensial harus di luar semua worktree Git.');
  }
  return actual;
}
function writePrivate(file, data) {
  const tmp = file + '.' + crypto.randomUUID() + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2) + '\n', {
    flag: 'wx',
    mode: 0o600,
  });
  fs.renameSync(tmp, file);
}
function tool(exe, args, env = process.env, discard = false) {
  return new Promise((resolve, reject) => {
    let out = '';
    const proc = cp.spawn(exe, args, {
      env,
      windowsHide: true,
      stdio: ['ignore', discard ? 'ignore' : 'pipe', 'pipe'],
    });
    proc.stdout?.on('data', (b) => (out += b)); // Never print PostgreSQL SQL/passwords.
    proc.stderr.on('data', () => {});
    proc.on('error', () =>
      reject(Error('Tool PostgreSQL tidak dapat dijalankan.')),
    );
    proc.on('exit', (code) =>
      code === 0
        ? resolve(out)
        : reject(
            Error(
              'Tool PostgreSQL gagal: ' + path.basename(exe) + ' exit ' + code,
            ),
          ),
    );
  });
}
async function snapshot(db) {
  const result = {};
  for (const t of [...TABLES, '_prisma_migrations'].sort()) {
    const rows = (
      await db.query(
        'SELECT id::text, md5(to_jsonb(t)::text) AS hash FROM public.' +
          quote(t) +
          ' t ORDER BY id',
      )
    ).rows;
    result[t] = rows;
  }
  return result;
}
async function inspect(db, adminId) {
  const identity = (
    await db.query(
      "SELECT current_database() database, current_setting('server_version') version, pg_is_in_recovery() recovery",
    )
  ).rows[0];
  if (identity.database !== 'capstone_antrean' || identity.recovery)
    throw Error('Identitas database aktual tidak cocok.');
  const tables = (
    await db.query(
      "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename",
    )
  ).rows.map((r) => r.tablename);
  if (
    JSON.stringify(tables) !==
    JSON.stringify([...TABLES, '_prisma_migrations'].sort())
  )
    throw Error('Inventaris tabel berbeda; perlu review sebelum reset.');
  const admins = (
    await db.query(
      "SELECT id,nama,email,aktif FROM pengguna WHERE peran='ADMIN'",
    )
  ).rows;
  if (admins.length !== 1 || !admins[0].aktif || admins[0].id !== adminId)
    throw Error('ADMIN utama tidak dapat diidentifikasi secara unik.');
  const pending = (
    await db.query(
      'SELECT count(*)::int n FROM _prisma_migrations WHERE finished_at IS NULL AND rolled_back_at IS NULL',
    )
  ).rows[0].n;
  if (pending) throw Error('Migration belum selesai.');
  const installed = (
    await db.query(
      'SELECT migration_name,checksum FROM _prisma_migrations WHERE finished_at IS NOT NULL AND rolled_back_at IS NULL',
    )
  ).rows;
  const dirs = fs
    .readdirSync(path.join(api, 'prisma/migrations'), { withFileTypes: true })
    .filter((f) => f.isDirectory());
  if (
    dirs.length !== installed.length ||
    dirs.some(
      (d) =>
        !installed.some(
          (i) =>
            i.migration_name === d.name &&
            migrationMatches(
              fs.readFileSync(
                path.join(api, 'prisma/migrations', d.name, 'migration.sql'),
                'utf8',
              ),
              i.checksum,
            ),
        ),
    )
  )
    throw Error('Migration lokal/database berbeda.');
  const fk = (
    await db.query(`SELECT fk.conname,fk.convalidated,c.relname child,p.relname parent,
    array_agg(ca.attname::text ORDER BY k.ordinality) cc,array_agg(pa.attname::text ORDER BY k.ordinality) pc
    FROM pg_constraint fk JOIN pg_class c ON c.oid=fk.conrelid JOIN pg_class p ON p.oid=fk.confrelid
    JOIN LATERAL unnest(fk.conkey,fk.confkey) WITH ORDINALITY k(ca,pa,ordinality) ON true
    JOIN pg_attribute ca ON ca.attrelid=c.oid AND ca.attnum=k.ca JOIN pg_attribute pa ON pa.attrelid=p.oid AND pa.attnum=k.pa
    WHERE fk.contype='f' AND fk.connamespace='public'::regnamespace GROUP BY fk.conname,fk.convalidated,c.relname,p.relname ORDER BY fk.conname`)
  ).rows;
  for (const f of fk) {
    if (!f.convalidated) throw Error('Foreign key belum tervalidasi.');
    const present = f.cc
      .map((c) => 'c.' + quote(c) + ' IS NOT NULL')
      .join(' AND ');
    const join = f.cc
      .map((c, i) => 'c.' + quote(c) + '=p.' + quote(f.pc[i]))
      .join(' AND ');
    const n = (
      await db.query(
        'SELECT count(*)::int n FROM ' +
          quote(f.child) +
          ' c WHERE ' +
          present +
          ' AND NOT EXISTS(SELECT 1 FROM ' +
          quote(f.parent) +
          ' p WHERE ' +
          join +
          ')',
      )
    ).rows[0].n;
    if (n) throw Error('Relasi yatim: ' + f.conname);
  }
  return {
    identity,
    admin: admins[0],
    foreignKeys: fk.length,
    migrations: installed.length,
  };
}
async function backup(db, url, dir, adminId, bin) {
  await db.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
  try {
    const info = await inspect(db, adminId),
      baseline = await snapshot(db);
    const snapshotId = (await db.query('SELECT pg_export_snapshot() id'))
      .rows[0].id;
    const name =
      'capstone_antrean_' +
      new Date().toISOString().replace(/[:.]/g, '-') +
      '_' +
      crypto.randomUUID().slice(0, 8);
    const archive = path.join(dir, name + '.dump');
    const env = {
      ...process.env,
      PGHOST: url.hostname,
      PGPORT: url.port,
      PGDATABASE: 'capstone_antrean',
      PGUSER: decodeURIComponent(url.username),
      PGPASSWORD: decodeURIComponent(url.password),
      PGOPTIONS: '-c default_transaction_read_only=on',
      PGCONNECT_TIMEOUT: '10',
    };
    await tool(
      path.join(bin, 'pg_dump.exe'),
      [
        '--format=custom',
        '--create',
        '--no-password',
        '--snapshot=' + snapshotId,
        '--file=' + archive,
      ],
      env,
    );
    const toc = await tool(path.join(bin, 'pg_restore.exe'), [
      '--list',
      archive,
    ]);
    if ((toc.match(/ TABLE DATA public /g) || []).length !== TABLES.length + 1)
      throw Error('Arsip tidak mencakup seluruh tabel.');
    await tool(
      path.join(bin, 'pg_restore.exe'),
      ['--file=-', archive],
      process.env,
      true,
    );
    const bytes = fs.readFileSync(archive);
    if (bytes.subarray(0, 5).toString() !== 'PGDMP')
      throw Error('Format backup salah.');
    const report = {
      createdAt: new Date().toISOString(),
      target: '127.0.0.1:5433/capstone_antrean',
      ...info,
      backup: {
        path: archive,
        sha256: sha(bytes),
        bytes: bytes.length,
        archiveList: true,
        fullOfflineDecode: true,
        restoredToDatabase: false,
      },
      counts: Object.fromEntries(
        Object.entries(baseline).map(([k, v]) => [k, v.length]),
      ),
      baseline,
    };
    const file = path.join(dir, name + '.checkpoint.json');
    writePrivate(file, report);
    await db.query('COMMIT');
    return { file, report };
  } catch (e) {
    await db.query('ROLLBACK');
    throw e;
  }
}
async function reset(db, checkpoint, adminId, bin) {
  const r = JSON.parse(fs.readFileSync(checkpoint));
  if (
    r.target !== '127.0.0.1:5433/capstone_antrean' ||
    r.admin.id !== adminId ||
    !r.backup.fullOfflineDecode
  )
    throw Error('Checkpoint tidak cocok.');
  if (Date.now() - Date.parse(r.createdAt) > 3600_000)
    throw Error('Backup lebih dari satu jam; buat checkpoint baru.');
  if (sha(fs.readFileSync(r.backup.path)) !== r.backup.sha256)
    throw Error('Checksum backup berubah.');
  await tool(
    path.join(bin, 'pg_restore.exe'),
    ['--file=-', r.backup.path],
    process.env,
    true,
  );
  await db.query('BEGIN');
  try {
    await db.query("SET LOCAL lock_timeout='5s'");
    // Exact known tables, no cascade, no trigger/constraint disabling, no DDL.
    await db.query(
      'LOCK TABLE ' +
        [...TABLES, '_prisma_migrations'].map(quote).join(',') +
        ' IN ACCESS EXCLUSIVE MODE',
    );
    await inspect(db, adminId);
    const before = await snapshot(db);
    for (const t of TABLES.filter((t) => t !== 'sesi_pengguna'))
      if (JSON.stringify(before[t]) !== JSON.stringify(r.baseline[t]))
        throw Error('Baseline berubah di ' + t + '; tidak ada data dihapus.');
    if (
      JSON.stringify(before._prisma_migrations) !==
      JSON.stringify(r.baseline._prisma_migrations)
    )
      throw Error('History migration berubah.');
    const removed = {};
    for (const t of TABLES)
      removed[t] = (
        await db.query(
          'DELETE FROM ' +
            quote(t) +
            (t === 'pengguna' ? ' WHERE id<>$1::uuid' : ''),
          t === 'pengguna' ? [adminId] : [],
        )
      ).rowCount;
    const after = await snapshot(db);
    if (
      JSON.stringify(after.pengguna) !==
        JSON.stringify(before.pengguna.filter((a) => a.id === adminId)) ||
      JSON.stringify(after._prisma_migrations) !==
        JSON.stringify(before._prisma_migrations) ||
      TABLES.filter((t) => t !== 'pengguna').some((t) => after[t].length)
    )
      throw Error('Postcondition reset gagal.');
    await db.query('COMMIT');
    const result = {
      resetAt: new Date().toISOString(),
      checkpoint,
      removed,
      adminUnchanged: true,
      migrationsUnchanged: true,
      allSessionsRevoked: true,
    };
    writePrivate(
      path.join(path.dirname(checkpoint), 'reset-result.json'),
      result,
    );
    return result;
  } catch (e) {
    await db.query('ROLLBACK');
    throw e;
  }
}
async function main(argv = process.argv.slice(2)) {
  const [mode, ...rest] = argv;
  const args = Object.fromEntries(
    rest.map((a) => {
      const i = a.indexOf('=');
      return [a.slice(0, i), a.slice(i + 1)];
    }),
  );
  if (!['preview', 'backup', 'reset', 'seed', 'verify', 'smoke'].includes(mode))
    throw Error(
      'Gunakan preview|backup|reset|seed|verify|smoke; lihat dokumentasi.',
    );
  const config = parse(fs.readFileSync(path.join(root, '.env')));
  // Ambient DATABASE_URL is never silently ignored.
  if (
    process.env.DATABASE_URL &&
    process.env.DATABASE_URL !== config.DATABASE_URL
  )
    throw Error('DATABASE_URL lingkungan berbeda dari konfigurasi lokal.');
  const url = assertTarget(
    config.DATABASE_URL,
    process.env.NODE_ENV || config.NODE_ENV || 'development',
  );
  if (config.SERVICE_TIME_ZONE && config.SERVICE_TIME_ZONE !== 'Asia/Jakarta')
    throw Error('Timezone harus Asia/Jakarta.');
  if (!args['--admin-id'])
    throw Error(
      '--admin-id wajib; identifikasi melalui preview awal/read-only.',
    );
  const bin = args['--pg-bin'] || 'C:/Program Files/PostgreSQL/18/bin';
  if (mode === 'smoke')
    return require('./development-smoke.cjs').smoke(config, args);
  if (['seed', 'verify'].includes(mode)) {
    const dir = externalDirectory(args['--output']);
    const proc = cp.spawnSync(
      process.execPath,
      [
        'tool/development-seed.cjs',
        mode,
        '--output=' + dir,
        '--admin-id=' + args['--admin-id'],
      ],
      {
        cwd: api,
        env: {
          ...process.env,
          ...config,
          NODE_ENV: 'development',
          SERVICE_TIME_ZONE: 'Asia/Jakarta',
        },
        stdio: 'inherit',
        windowsHide: true,
      },
    );
    if (proc.status !== 0)
      throw Error(
        'Seeding/validasi berhenti; lihat checkpoint lokal. Tidak ada restore otomatis.',
      );
    const check = new Client({ connectionString: config.DATABASE_URL });
    await check.connect();
    try {
      await check.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
      await inspect(check, args['--admin-id']);
      const result = JSON.parse(
        fs.readFileSync(path.join(dir, 'reset-result.json')),
      );
      const checkpoint = JSON.parse(fs.readFileSync(result.checkpoint));
      const after = await snapshot(check);
      const preserved = checkpoint.baseline.pengguna.find(
        (p) => p.id === args['--admin-id'],
      );
      if (
        JSON.stringify(after.pengguna.find((p) => p.id === preserved.id)) !==
        JSON.stringify(preserved)
      )
        throw Error('ADMIN utama berubah.');
      if (
        JSON.stringify(after._prisma_migrations) !==
        JSON.stringify(checkpoint.baseline._prisma_migrations)
      )
        throw Error('History migration berubah.');
      for (const table of TABLES) {
        const ids = new Set(after[table].map((r) => r.id));
        if (
          checkpoint.baseline[table].some(
            (r) =>
              !(table === 'pengguna' && r.id === preserved.id) && ids.has(r.id),
          )
        )
          throw Error('Record lama tersisa: ' + table);
      }
      await check.query('COMMIT');
      writePrivate(path.join(dir, 'preservation-verification.json'), {
        verifiedAt: new Date().toISOString(),
        adminEntireRecordUnchanged: true,
        migrationHistoryIdentical: true,
        oldOperationalRecordsRemaining: 0,
        foreignKeyOrphans: 0,
        oldSessionsRemaining: 0,
      });
      console.log(
        'ADMIN/kredensial dan migration identik; seluruh ID operasional/sesi lama hilang; foreign key valid.',
      );
    } finally {
      await check.end();
    }
    return;
  }
  const db = new Client({
    connectionString: config.DATABASE_URL,
    application_name: 'queueb-development-maintenance',
  });
  await db.connect();
  try {
    if (mode === 'preview') {
      await db.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
      const info = await inspect(db, args['--admin-id']);
      const snap = await snapshot(db);
      console.log(
        JSON.stringify(
          {
            mode,
            ...info,
            counts: Object.fromEntries(
              Object.entries(snap).map(([k, v]) => [k, v.length]),
            ),
            deletePlan: TABLES,
            seed: {
              clinics: 5,
              doctors: 10,
              rooms: 7,
              staff: 8,
              patients: 40,
              period: ['2026-10-27', '2026-11-30'],
              timeZone: 'Asia/Jakarta',
            },
          },
          null,
          2,
        ),
      );
      await db.query('ROLLBACK');
    }
    if (mode === 'backup') {
      const dir = externalDirectory(args['--output']);
      const b = await backup(db, url, dir, args['--admin-id'], bin);
      console.log(
        JSON.stringify(
          {
            checkpoint: b.file,
            backup: b.report.backup,
            counts: b.report.counts,
          },
          null,
          2,
        ),
      );
    }
    if (mode === 'reset') {
      if (
        args['--confirm'] !== 'RESET-capstone_antrean' ||
        args['--maintenance'] !== 'acknowledged'
      )
        throw Error(
          'Reset memerlukan --confirm=RESET-capstone_antrean --maintenance=acknowledged.',
        );
      if (!args['--checkpoint']) throw Error('Checkpoint backup wajib.');
      // Fail before deletion when the fixed-period live scenarios cannot be seeded.
      require('./development-seed.cjs').assertSeedWindow();
      externalDirectory(path.dirname(args['--checkpoint']));
      console.log(
        JSON.stringify(
          await reset(db, args['--checkpoint'], args['--admin-id'], bin),
          null,
          2,
        ),
      );
    }
  } finally {
    await db.end();
  }
}
module.exports = {
  assertTarget,
  externalDirectory,
  TABLES,
  inspect,
  reset,
  main,
  migrationMatches,
};
if (require.main === module)
  main().catch((e) => {
    console.error('Dihentikan: ' + e.message);
    process.exitCode = 1;
  });
