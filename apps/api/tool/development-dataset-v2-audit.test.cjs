const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const {
  parseSessionArchive,
  sessionFindings,
  datasetFindings,
} = require('./development-dataset-v2-audit.cjs');
const { TABLES } = require('./development-data.cjs');
const hash = (id) => createHash('sha256').update(id).digest('hex').slice(0, 16);
test('archive parsing is offline, handles COPY nulls and rejects malformed rows', () => {
  const rows = parseSessionArchive(
    'COPY public.sesi_pengguna (id, dicabut_pada) FROM stdin;\nfixture-id\t\\N\n\\.\n',
  );
  assert.deepEqual(rows, [{ id: 'fixture-id', dicabut_pada: null }]);
  assert.throws(() => parseSessionArchive('SELECT nothing;'));
  assert.throws(() =>
    parseSessionArchive(
      'COPY public.sesi_pengguna (id, dicabut_pada) FROM stdin;\nmissing-field\n\\.',
    ),
  );
});
function session() {
  const before = {
    id: 'fixture-session',
    pengguna_id: 'fixture-account',
    token_refresh_hash: 'synthetic-old-digest',
    kedaluwarsa_pada: '2026-11-06T01:00:00Z',
    dicabut_pada: null,
    dibuat_pada: '2026-10-30T01:00:00Z',
    nama_perangkat: 'QueueB Flutter',
  };
  const current = {
    ...before,
    token_refresh_hash: 'synthetic-new-digest',
    kedaluwarsa_pada: '2026-11-06T02:00:00Z',
    peran: 'ADMIN',
  };
  return {
    before,
    current,
    historical: [
      { sessionHash: hash(before.id), afterExpires: current.kedaluwarsa_pada },
    ],
  };
}
test('normal refresh-shaped changes never prove caller attribution or become VERIFIED', () => {
  const { before, current, historical } = session();
  const result = sessionFindings(
    [before],
    [current],
    historical,
    [],
    7 * 86400000,
  )[0];
  assert.equal(result.existingRefreshMechanismCompatible, true);
  assert.equal(result.status, 'UNATTRIBUTED');
  assert.equal(result.caller, 'UNATTRIBUTED');
  assert.equal(result.latestRotationEstimate, '2026-10-30T02:00:00.000Z');
  current.kedaluwarsa_pada = new Date('2026-11-06T02:00:00.710Z');
  assert.equal(
    sessionFindings([before], [current], historical, [], 7 * 86400000)[0]
      .latestRotationEstimate,
    '2026-10-30T02:00:00.710Z',
  );
  assert.equal(result.ownerUsedByV2Smoke, false);
  assert(!JSON.stringify(result).includes(before.token_refresh_hash));
  assert(!JSON.stringify(result).includes(current.token_refresh_hash));
});
test('account overlap or missing historical rows is reported without a hidden exception', () => {
  const { before, current, historical } = session();
  const other = { ...current, id: 'new-owned-session' };
  assert.equal(
    sessionFindings(
      [before],
      [current, other],
      historical,
      [other.id],
      7 * 86400000,
    )[0].ownerUsedByV2Smoke,
    true,
  );
  assert.equal(
    sessionFindings([before], [], historical, [], 7 * 86400000)[0].status,
    'UNATTRIBUTED',
  );
  current.pengguna_id = 'changed-owner';
  assert.equal(
    sessionFindings([before], [current], historical, [], 7 * 86400000)[0]
      .existingRefreshMechanismCompatible,
    false,
  );
});
function data() {
  const baseline = Object.fromEntries(
    [...TABLES, '_prisma_migrations'].map((t) => [t, []]),
  );
  const i = {
    baseline,
    users: [
      { id: 'account', nama: 'Synthetic doctor', peran: 'DOKTER', aktif: true },
    ],
    doctors: [
      {
        id: 'doctor',
        kode: 'D1',
        nama: 'Synthetic doctor',
        pengguna_id: 'account',
        aktif: true,
      },
    ],
    links: [
      { id: 'link', dokter_id: 'doctor', layanan_id: 'service', aktif: true },
    ],
    services: [
      {
        id: 'service',
        kode: 'APOTEK',
        mode_reservasi: 'ANTREAN_HARIAN',
        aktif: true,
      },
    ],
    rooms: [{ id: 'room', layanan_id: 'service', aktif: true }],
    assignments: [],
    hours: [
      {
        layanan_id: 'service',
        hari: 'SABTU',
        aktif: true,
        kapasitas_harian: 80,
      },
    ],
    slots: [],
    practices: [
      {
        id: 'practice',
        dokter_layanan_id: 'link',
        loket_id: 'room',
        tanggal: '2026-10-31',
        mulai_pada: '2026-10-31T01:00:00Z',
        selesai_pada: '2026-10-31T05:00:00Z',
        aktif: true,
      },
    ],
  };
  const p = { baseline: structuredClone(baseline), cleanup: {} };
  p.baseline.sesi_pengguna = Array.from({ length: 147 }, (_, n) => ({
    id: 'historical-auth-' + n,
    hash: 'synthetic',
  }));
  return { i, p, state: { created: { 'practice/link/day': 'practice' } } };
}
test('audit distinguishes historical authentication sessions from practice sessions and does not force 156', () => {
  const { i, p, state } = data(),
    before = structuredClone(i),
    r = datasetFindings(i, p, state);
  assert.equal(r.schedule.target, 1);
  assert.equal(r.schedule.historicalAuthSessions, 147);
  assert.equal(r.schedule.historicalPracticeSessions, 0);
  assert.equal(r.doctors[0].accountValid, true);
  assert.equal(r.doctors[0].staffCoverage, false);
  assert.deepEqual(i, before);
  i.users[0].peran = 'USER';
  assert.equal(datasetFindings(i, p, state).doctors[0].accountValid, false);
});
test('invalid timezone date, duplicate slots and overlapping practice are detected', () => {
  const { i, p, state } = data();
  i.practices.push({ ...i.practices[0], id: 'duplicate' });
  i.slots.push(
    {
      id: 'one',
      jadwal_praktik_id: 'practice',
      mulai_pada: '2026-10-31T01:00:00Z',
      selesai_pada: '2026-10-31T01:20:00Z',
      aktif: true,
      kapasitas: 2,
    },
    {
      id: 'two',
      jadwal_praktik_id: 'practice',
      mulai_pada: '2026-10-31T01:00:00Z',
      selesai_pada: '2026-10-31T01:20:00Z',
      aktif: true,
      kapasitas: 2,
    },
    {
      id: 'outside',
      jadwal_praktik_id: 'practice',
      mulai_pada: '2026-10-30T15:00:00Z',
      selesai_pada: '2026-10-30T15:20:00Z',
      aktif: true,
      kapasitas: 2,
    },
  );
  const r = datasetFindings(i, p, state);
  assert.equal(r.schedule.doctorRoomConflicts, 1);
  assert.equal(r.schedule.duplicatePractices, 1);
  assert.equal(r.schedule.duplicateSlots, 1);
  assert(r.schedule.slotOverlap > 0);
  assert(r.schedule.invalidSlots > 0);
});
