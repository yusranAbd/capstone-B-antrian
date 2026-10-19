const path = require('node:path');
const fs = require('node:fs');
const { spawn } = require('node:child_process');
const root = path.resolve(__dirname, '..');
require(path.join(root, 'node_modules/dotenv')).config({
  path: path.join(root, '../../.env'),
  quiet: true,
});
const { Client } = require(path.join(root, 'node_modules/pg'));
(async () => {
  const target = new URL(process.env.DATABASE_URL || 'http://invalid');
  if (
    !['postgres:', 'postgresql:'].includes(target.protocol) ||
    !['localhost', '127.0.0.1'].includes(target.hostname)
  )
    throw new Error('Only a local credential source is accepted');
  target.hostname = '127.0.0.1';
  target.port = '5433';
  target.pathname = '/capstone_antrean_test';
  process.env.DATABASE_URL = target.toString();
  process.env.NODE_ENV = 'test';
  process.env.SERVICE_TIME_ZONE = 'Asia/Jakarta';
  const client = new Client({
    connectionString: target.toString(),
    connectionTimeoutMillis: 5000,
  });
  await client.connect();
  const run = (script, args) =>
    new Promise((resolve, reject) => {
      const child = spawn(
        process.execPath,
        ['--experimental-vm-modules', script, ...args],
        { cwd: root, env: process.env, stdio: 'inherit', windowsHide: true },
      );
      child.on('error', reject);
      child.on('exit', (code) => resolve(code ?? 1));
    });
  try {
    const actual = await client.query(
      'SELECT current_database() AS db, inet_server_port() AS port',
    );
    if (
      actual.rows[0].db !== 'capstone_antrean_test' ||
      ![5432, 5433].includes(actual.rows[0].port)
    )
      throw new Error('Wrong database/server');
    console.log('Target validated: 127.0.0.1:5433/capstone_antrean_test');
    const before = new Map();
    const tables = (
      await client.query(
        "SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename <> '_prisma_migrations'",
      )
    ).rows.map((r) => r.tablename);
    async function state(table) {
      if (!/^[a-z_]+$/.test(table)) throw new Error('Unexpected table');
      return new Map(
        (
          await client.query(
            "SELECT id::text AS id, md5((jsonb_build_object('kode_aktivasi_hash',NULL,'kode_berlaku_hingga',NULL,'kode_digunakan_pada',NULL,'sesi_berakhir_pada',NULL) || to_jsonb(t))::text) AS hash FROM \"" +
              table +
              '" t',
          )
        ).rows.map((r) => [r.id, r.hash]),
      );
    }
    for (const table of tables) before.set(table, await state(table));
    let code;
    try {
      if (process.argv.includes('--deploy-test-migration')) {
        const applied = new Set(
          (
            await client.query(
              'SELECT migration_name FROM _prisma_migrations WHERE finished_at IS NOT NULL AND rolled_back_at IS NULL',
            )
          ).rows.map((r) => r.migration_name),
        );
        const pending = fs
          .readdirSync(path.join(root, 'prisma/migrations'))
          .filter(
            (v) =>
              fs
                .statSync(path.join(root, 'prisma/migrations', v))
                .isDirectory() && !applied.has(v),
          );
        if (pending.some((v) => v !== '20261019_display_device_pairing'))
          throw new Error('Unexpected pending migration');
        if (
          (await run(path.join(root, 'node_modules/prisma/build/index.js'), [
            'migrate',
            'deploy',
          ])) !== 0
        )
          throw new Error('Test migration failed; stop without rollback');
      }
      code = await run(path.join(root, 'node_modules/jest/bin/jest.js'), [
        '--config',
        'test/jest-e2e.json',
        '--runInBand',
        ...process.argv.slice(2).filter((v) => v !== '--deploy-test-migration'),
      ]);
    } finally {
      let existing = 0,
        changed = 0,
        missing = 0,
        remaining = 0;
      for (const table of tables) {
        const old = before.get(table),
          after = await state(table);
        existing += old.size;
        for (const [id, hash] of old) {
          if (!after.has(id)) missing++;
          else if (hash !== after.get(id)) changed++;
        }
        for (const id of after.keys()) if (!old.has(id)) remaining++;
      }
      console.log(JSON.stringify({ existing, missing, changed, remaining }));
      process.exitCode = changed || missing || remaining ? 1 : code;
    }
  } finally {
    await client.end();
  }
})().catch((e) => {
  console.error('Isolated QA failed: ' + (e.code || e.name));
  process.exitCode = 1;
});
