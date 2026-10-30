const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  assertTarget,
  TABLES,
  externalDirectory,
  migrationMatches,
} = require('./development-data.cjs');
const {
  schedulePlan,
  dates,
  CLINICS,
  STAFF,
  PATIENTS,
  assertSeedWindow,
} = require('./development-seed.cjs');
const correct = 'postgresql://127.0.0.1:5433/capstone_antrean?schema=public';
test('guard accepts only exact approved development target', () => {
  assert.equal(
    assertTarget(correct, 'development').pathname,
    '/capstone_antrean',
  );
  for (const u of [
    correct.replace('127.0.0.1', 'localhost'),
    correct.replace('5433', '5432'),
    correct.replace('capstone_antrean', 'capstone_antrean_test'),
    correct.replace('capstone_antrean', 'production'),
    correct.replace('schema=public', 'schema=other'),
    correct + '&host=example.test',
  ])
    assert.throws(() => assertTarget(u, 'development'));
  for (const env of ['production', 'test', '', undefined])
    assert.throws(() => assertTarget(correct, env));
});
test('migration checksum tolerates only LF/CRLF, never changed SQL', () => {
  const hash = (s) =>
    require('node:crypto').createHash('sha256').update(s).digest('hex');
  const sql = 'ALTER TABLE x ADD COLUMN y INT;\n';
  assert(migrationMatches(sql.replaceAll('\n', '\r\n'), hash(sql)));
  assert(migrationMatches(sql, hash(sql.replaceAll('\n', '\r\n'))));
  assert(!migrationMatches(sql.replace('INT', 'TEXT'), hash(sql)));
});
test('backup path inside repository is rejected', () => {
  assert.throws(() => externalDirectory(process.cwd()), /di luar/);
  assert.throws(() => externalDirectory('backups'), /absolut/);
});
test('delete ordering covers every domain model without cascade or migration deletion', () => {
  assert.equal(TABLES.length, 16);
  assert.equal(new Set(TABLES).size, 16);
  assert(!TABLES.includes('_prisma_migrations'));
  for (const [child, parent] of [
    ['janji_temu', 'tiket_antrean'],
    ['janji_temu', 'slot_praktik'],
    ['peristiwa_antrean', 'pengguna'],
    ['tiket_antrean', 'loket'],
    ['slot_praktik', 'jadwal_praktik'],
    ['jadwal_praktik', 'dokter_layanan'],
    ['dokter', 'pengguna'],
    ['sesi_pengguna', 'pengguna'],
    ['loket', 'layanan'],
  ])
    assert(TABLES.indexOf(child) < TABLES.indexOf(parent));
});
test('calendar period and workdays are real, with no doctor or room collisions', () => {
  const calendar = dates(),
    plans = schedulePlan();
  assert.equal(calendar.length, 35);
  assert.equal(calendar[0], '2026-10-27');
  assert.equal(calendar.at(-1), '2026-11-30');
  for (const p of plans) {
    assert.notEqual(new Date(p.day + 'T00:00:00Z').getUTCDay(), 0);
    assert(p.start >= '07:00' && p.end <= '17:00' && p.end > p.start);
    assert(calendar.includes(p.day));
  }
  for (let i = 0; i < plans.length; i++)
    for (let j = i + 1; j < plans.length; j++) {
      const a = plans[i],
        b = plans[j];
      if (
        a.ci === b.ci &&
        a.day === b.day &&
        (a.doctor === b.doctor || a.room === b.room)
      )
        assert(!(a.start < b.end && b.start < a.end));
    }
  for (let ci = 0; ci < 5; ci++)
    for (let d = 0; d < 2; d++)
      assert(plans.filter((p) => p.ci === ci && p.doctor === d).length > 5);
});
test('synthetic identities and specialist titles stay consistent', () => {
  assert.equal(CLINICS.length, 5);
  assert.equal(CLINICS.flatMap((c) => c[7]).length, 10);
  assert.equal(STAFF.length, 8);
  assert.equal(PATIENTS.length, 40);
  assert.deepEqual(
    CLINICS.map((c) => c[4]),
    ['Sp.A', 'Sp.PD', 'Sp.M', 'Sp.B', 'Sp.N'],
  );
  const names = [...CLINICS.flatMap((c) => c[7]), ...STAFF, ...PATIENTS];
  assert.equal(new Set(names).size, names.length);
  assert(!names.some((n) => /demo|dummy|test user|sample doctor/i.test(n)));
});
test('fixed live seed window fails before a later reset, without faking domain time', () => {
  assert.doesNotThrow(() =>
    assertSeedWindow(new Date('2026-10-27T07:00:00+07:00')),
  );
  assert.doesNotThrow(() =>
    assertSeedWindow(new Date('2026-10-27T11:39:59+07:00')),
  );
  for (const t of [
    '2026-10-27T06:59:59+07:00',
    '2026-10-27T11:40:00+07:00',
    '2026-10-28T08:00:00+07:00',
  ])
    assert.throws(() => assertSeedWindow(new Date(t)));
});

// Keep the scoped V2 safety tests in the existing tooling CI lifecycle.
require('./development-dataset-v2.test.cjs');
require('./development-dataset-v2-audit.test.cjs');
