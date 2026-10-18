/** Guarded local QA runner. Additive migration is opt-in and test database only. */
const path = require('node:path');
const fs = require('node:fs');
const { spawn } = require('node:child_process');
const api = path.resolve(__dirname, '..');
require(path.join(api, 'node_modules/dotenv')).config({
  path: path.resolve(api, '../../.env'),
  quiet: true,
});
const { Client } = require(path.join(api, 'node_modules/pg'));
async function run(args, env) {
  return new Promise((resolve, reject) => {
    const c = spawn(process.execPath, args, {
      cwd: api,
      stdio: 'inherit',
      windowsHide: true,
      env,
    });
    c.once('error', reject);
    c.once('exit', (code) => resolve(code ?? 1));
  });
}
(async () => {
  const url = new URL(process.env.DATABASE_URL);
  if (
    !['postgres:', 'postgresql:'].includes(url.protocol) ||
    !['localhost', '127.0.0.1'].includes(url.hostname)
  )
    throw Error('Sumber bukan PostgreSQL lokal');
  url.hostname = '127.0.0.1';
  url.port = '5433';
  url.pathname = '/capstone_antrean_test';
  const db = new Client({ connectionString: url.toString() });
  await db.connect();
  const env = {
    ...process.env,
    DATABASE_URL: url.toString(),
    SERVICE_TIME_ZONE: 'Asia/Jakarta',
    CORS_ALLOWED_ORIGINS: 'http://localhost:5173,http://127.0.0.1:8080',
  };
  try {
    const actual = (
      await db.query(
        'SELECT current_database() AS db, inet_server_port() AS port',
      )
    ).rows[0];
    if (
      actual.db !== 'capstone_antrean_test' ||
      ![5432, 5433].includes(actual.port)
    )
      throw Error('Target database tidak sesuai');
    console.log('Target tervalidasi: 127.0.0.1:5433/capstone_antrean_test');
    const applied = new Set(
      (
        await db.query(
          'SELECT migration_name FROM _prisma_migrations WHERE finished_at IS NOT NULL AND rolled_back_at IS NULL',
        )
      ).rows.map((r) => r.migration_name),
    );
    const pending = fs
      .readdirSync(path.join(api, 'prisma/migrations'), { withFileTypes: true })
      .filter((d) => d.isDirectory() && !applied.has(d.name))
      .map((d) => d.name);
    if (pending.length) {
      if (
        !process.argv.includes('--migrate-test-db') ||
        pending.length !== 1 ||
        pending[0] !== '20261018_doctor_portal_identity'
      )
        throw Error('Migration pending tidak diizinkan');
      if (
        await run(
          ['node_modules/prisma/build/index.js', 'migrate', 'deploy'],
          env,
        )
      )
        throw Error('Migration test gagal');
    }
    async function fingerprint() {
      await db.query('BEGIN READ ONLY');
      try {
        const tables = (
          await db.query(
            "SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename <> '_prisma_migrations' ORDER BY tablename",
          )
        ).rows;
        const state = {};
        for (const { tablename: t } of tables) {
          if (!/^[a-z_]+$/.test(t)) throw Error('Identifier tidak sah');
          state[t] = (
            await db.query(
              'SELECT id::text, md5(row_to_json(t)::text) AS hash FROM "' +
                t +
                '" t ORDER BY id',
            )
          ).rows;
        }
        return state;
      } finally {
        await db.query('ROLLBACK');
      }
    }
    const before = await fingerprint();
    const args = [
      '--experimental-vm-modules',
      'node_modules/jest/bin/jest.js',
      '--config',
      'test/jest-e2e.json',
      '--runInBand',
      '--no-cache',
    ];
    if (!process.argv.includes('--all')) args.push('doctor-portal.e2e-spec');
    const code = await run(args, env);
    const same = JSON.stringify(before) === JSON.stringify(await fingerprint());
    console.log(
      JSON.stringify({
        recordExisting: Object.values(before).reduce((n, r) => n + r.length, 0),
        dataExistingDanCleanupSesuai: same,
      }),
    );
    process.exitCode = same ? code : 1;
  } finally {
    await db.end();
  }
})().catch((e) => {
  console.error('QA gagal: ' + (e.code || e.message));
  process.exitCode = 1;
});
