const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs'),
  path = require('node:path'),
  { randomUUID } = require('node:crypto');
const {
  buildPlan,
  cleanup,
  fingerprint,
  dates,
  instant,
  SERVICES,
  DELETE_ORDER,
} = require('./development-dataset-v2.cjs');
const { TABLES, assertTarget } = require('./development-data.cjs');
const id = (n) => '11111111-1111-4111-8111-' + String(n).padStart(12, '0');
const at = '2026-10-27T01:07:00.000Z';
function fixture() {
  const baseline = Object.fromEntries(
    [...TABLES, '_prisma_migrations'].map((t) => [t, []]),
  );
  const i = {
    baseline,
    users: [{ id: id(1), email: 'seed@example.test', peran: 'USER' }],
    services: [],
    rooms: [],
    hours: [],
    doctors: [],
    links: [],
    assignments: [],
    practices: [],
    slots: [],
    tickets: [],
    appointments: [],
    events: [],
    notifications: [],
    counters: [],
  };
  const state = {
    version: 'queueb-synthetic-20261027-v1',
    complete: true,
    adminId: id(99),
    startedAt: '2026-10-27T01:00:00Z',
    completedAt: '2026-10-27T02:00:00Z',
    clinics: [id(2)],
    practices: [],
  };
  const e = {
    state,
    accounts: [{ email: 'seed@example.test', role: 'USER' }],
    checkpoint: { baseline: structuredClone(baseline) },
  };
  const ticket = {
    id: id(3),
    pengguna_id: id(1),
    layanan_id: id(2),
    tanggal_antrean: '2026-10-27',
    dibuat_pada: at,
    diperbarui_pada: at,
  };
  i.tickets.push(ticket);
  i.events.push({
    id: id(4),
    tiket_antrean_id: ticket.id,
    aktor_id: id(1),
    terjadi_pada: at,
  });
  return { i, e, ticket };
}
test('V2 target guard never accepts test/remote/production as development maintenance', () => {
  assert.throws(() =>
    assertTarget(
      'postgresql://127.0.0.1:5433/capstone_antrean_test',
      'development',
    ),
  );
  assert.throws(() =>
    assertTarget('postgresql://127.0.0.1:5433/capstone_antrean', 'production'),
  );
  assert.throws(() =>
    assertTarget(
      'postgresql://127.0.0.1:5433/capstone_antrean?host=remote',
      'development',
    ),
  );
});
test('provenance requires seed identity, service, creation window; generic names do not authorize cleanup', () => {
  const { i, e, ticket } = fixture();
  i.tickets.push(
    { ...ticket, id: id(5), pengguna_id: id(6) },
    { ...ticket, id: id(7), dibuat_pada: '2026-10-29T01:00:00Z' },
  );
  const p = buildPlan(i, e);
  assert.deepEqual(p.cleanup.tiket_antrean, [id(3)]);
  assert.equal(p.preservation.unclassifiedTickets, 2);
  assert(!Object.keys(p.cleanup).includes('pengguna'));
  assert(!Object.keys(p.cleanup).includes('sesi_pengguna'));
  assert(!Object.keys(p.cleanup).includes('perangkat_tampilan'));
});
test('later activity or an unknown actor protects the demo ticket and all dependents', () => {
  for (const change of [
    'ticket',
    'event',
    'actor',
    'appointment',
    'notification',
  ]) {
    const { i, e, ticket } = fixture();
    if (change === 'ticket') ticket.diperbarui_pada = '2026-10-30T00:00:00Z';
    if (change === 'event') i.events[0].terjadi_pada = '2026-10-30T00:00:00Z';
    if (change === 'actor') i.events[0].aktor_id = id(800);
    if (change === 'appointment')
      i.appointments.push({
        id: id(8),
        tiket_id: ticket.id,
        dibuat_pada: at,
        diperbarui_pada: '2026-10-30T00:00:00Z',
      });
    if (change === 'notification')
      i.notifications.push({
        id: id(9),
        tiket_antrean_id: ticket.id,
        pengguna_id: id(800),
        dibuat_pada: at,
      });
    const p = buildPlan(i, e);
    assert.equal(p.cleanup.tiket_antrean.length, 0);
    assert.equal(p.cleanup.peristiwa_antrean.length, 0);
    assert.equal(p.blocked.length, 1);
  }
});
test('counter with a retained ticket is preserved; exhausted verified seed scope is eligible', () => {
  const { i, e, ticket } = fixture();
  i.counters.push({
    id: id(10),
    layanan_id: id(2),
    tanggal: '2026-10-27',
    diperbarui_pada: at,
  });
  assert.deepEqual(buildPlan(i, e).cleanup.urutan_antrean_harian, [id(10)]);
  i.tickets.push({ ...ticket, id: id(11), pengguna_id: id(900) });
  assert.deepEqual(buildPlan(i, e).cleanup.urutan_antrean_harian, []);
});
test('expired seed practices require unchanged checkpoint and no retained appointment', () => {
  const { i, e } = fixture();
  i.practices.push({ id: id(20), tanggal: '2026-10-27', aktif: true });
  i.slots.push({ id: id(21), jadwal_praktik_id: id(20) });
  e.state.practices.push(id(20));
  for (const [t, n] of [
    ['jadwal_praktik', 20],
    ['slot_praktik', 21],
  ]) {
    i.baseline[t].push({ id: id(n), hash: 'original' });
    e.checkpoint.baseline[t].push({ id: id(n), hash: 'original' });
  }
  assert.deepEqual(buildPlan(i, e).cleanup.jadwal_praktik, [id(20)]);
  i.appointments.push({
    id: id(22),
    slot_praktik_id: id(21),
    tiket_id: id(900),
  });
  assert.deepEqual(buildPlan(i, e).cleanup.jadwal_praktik, []);
  i.appointments = [];
  i.baseline.slot_praktik[0].hash = 'changed';
  assert.deepEqual(buildPlan(i, e).cleanup.slot_praktik, []);
});
test('calendar is inclusive and explicit WIB instants never depend on host timezone', () => {
  assert.equal(dates().length, 31);
  assert.equal(dates()[0], '2026-10-31');
  assert.equal(dates().at(-1), '2026-11-30');
  assert.equal(instant('2026-10-31', '08:00'), '2026-10-31T01:00:00.000Z');
  assert.equal(instant('2026-11-01', '08:00'), '2026-11-01T01:00:00.000Z');
  assert.equal(instant('2026-11-30', '08:00'), '2026-11-30T01:00:00.000Z');
});
test('missing doctor coverage plans 26 non-overlapping workdays and preserves existing patterns', () => {
  const { i, e } = fixture();
  i.users.push({ id: id(30), peran: 'DOKTER', aktif: true });
  i.doctors.push({
    id: id(31),
    kode: 'FARM',
    pengguna_id: id(30),
    aktif: true,
  });
  i.links.push({
    id: id(32),
    dokter_id: id(31),
    layanan_id: id(33),
    aktif: true,
  });
  i.services.push({
    id: id(33),
    kode: 'APOTEK',
    mode_reservasi: 'ANTREAN_HARIAN',
    aktif: true,
  });
  i.rooms.push({ id: id(34), layanan_id: id(33), aktif: true });
  for (const hari of ['SENIN', 'SELASA', 'RABU', 'KAMIS', 'JUMAT', 'SABTU'])
    i.hours.push({
      layanan_id: id(33),
      hari,
      jam_buka: '07:00:00',
      jam_tutup: '17:00:00',
      aktif: true,
    });
  const p = buildPlan(i, e);
  assert.equal(p.practices.length, 26);
  assert(
    p.practices.every(
      (p) => new Date(p.tanggal + 'T00:00:00Z').getUTCDay() !== 0,
    ),
  );
  i.practices.push({ ...p.practices[0], id: id(35), aktif: true });
  assert.equal(buildPlan(i, e).practices.length, 0);
});
test('stable owned identities produce zero account/service additions; unowned collision fails closed', () => {
  const { i, e } = fixture(),
    state = { created: {} };
  for (const [n, s] of SERVICES.entries()) {
    i.services.push({
      id: id(100 + n),
      kode: s[0],
      mode_reservasi: 'ANTREAN_HARIAN',
      aktif: true,
    });
    i.users.push({
      id: id(200 + n),
      email: s[0].toLowerCase() + '.petugas.dataset-v2@example.test',
      peran: 'PETUGAS',
      aktif: true,
    });
    state.created['staff/' + s[0]] = id(200 + n);
  }
  const p = buildPlan(i, e, state);
  assert.equal(p.summary.newServices, 0);
  assert.equal(p.summary.newStaff, 0);
  delete state.created['staff/APOTEK'];
  assert.throws(() => buildPlan(i, e, state), /collision/);
});
test('cleanup rejects unknown tables and IDs before starting any transaction', async () => {
  let calls = 0;
  const db = {
    query: async () => {
      calls++;
    },
  };
  const p = {
    baseline: { tiket_antrean: [] },
    cleanup: { tiket_antrean: [id(50)] },
  };
  await assert.rejects(cleanup(db, p));
  assert.equal(calls, 0);
  await assert.rejects(
    cleanup(db, { baseline: {}, cleanup: { pengguna: [] } }),
  );
  assert.equal(calls, 0);
});
test(
  'real PostgreSQL cleanup rolls back injected failure and preserves every unrelated row',
  { skip: process.env.QUEUEB_V2_SQL_TEST !== '1' },
  async () => {
    const { Client } = require('pg');
    const cfg = require('dotenv').parse(
      fs.readFileSync(path.resolve(__dirname, '../../../.env')),
    );
    const source = new URL(cfg.DATABASE_URL);
    assert(['localhost', '127.0.0.1'].includes(source.hostname));
    const target = new URL('postgresql://127.0.0.1:5433/capstone_antrean_test');
    target.username = source.username;
    target.password = source.password;
    const db = new Client({ connectionString: target.toString() });
    await db.connect();
    assert.equal(
      (await db.query('SELECT current_database() name')).rows[0].name,
      'capstone_antrean_test',
    );
    const ids = Array.from({ length: 5 }, () => randomUUID());
    let baseline;
    try {
      baseline = await fingerprint(db);
      await db.query(
        "INSERT INTO pengguna(id,nama,email,kata_sandi_hash,peran,diperbarui_pada) VALUES($1,$2,$3,$4,'USER',now())",
        [
          ids[0],
          'V2 isolated fixture',
          ids[0] + '@test.local',
          'not-a-login-hash',
        ],
      );
      await db.query(
        "INSERT INTO layanan(id,kode,nama,prefix_antrean,durasi_dasar_menit,diperbarui_pada) VALUES($1,$2,$3,'V2',15,now())",
        [ids[1], 'V2' + ids[1].slice(0, 10), 'V2 isolated fixture'],
      );
      for (const [index, ticket] of ids.slice(2, 4).entries())
        await db.query(
          "INSERT INTO tiket_antrean(id,pengguna_id,layanan_id,tanggal_antrean,nomor_urut,kode_tiket,diperbarui_pada) VALUES($1,$2,$3,'2026-10-31',$4,$5,now())",
          [ticket, ids[0], ids[1], index + 1, 'V2' + ticket.slice(0, 20)],
        );
      await db.query(
        "INSERT INTO peristiwa_antrean(id,tiket_antrean_id,tipe) VALUES($1,$2,'V2_FIXTURE')",
        [ids[4], ids[2]],
      );
      const before = await fingerprint(db),
        p = {
          baseline: before,
          cleanup: Object.fromEntries(DELETE_ORDER.map((t) => [t, []])),
        };
      p.cleanup.tiket_antrean = [ids[2]];
      p.cleanup.peristiwa_antrean = [ids[4]];
      const broken = {
        query: (sql, args) => {
          if (sql.startsWith('DELETE FROM "tiket_antrean"'))
            throw Error('injected cleanup failure');
          return db.query(sql, args);
        },
      };
      await assert.rejects(cleanup(broken, p), /injected/);
      assert.deepEqual(await fingerprint(db), before);
      const result = await cleanup(db, p);
      assert.equal(result.removed.tiket_antrean, 1);
      assert(result.after.tiket_antrean.some((r) => r.id === ids[3]));
    } finally {
      try {
        await db.query('DELETE FROM peristiwa_antrean WHERE id=$1', [ids[4]]);
        await db.query('DELETE FROM tiket_antrean WHERE id=ANY($1::uuid[])', [
          ids.slice(2, 4),
        ]);
        await db.query('DELETE FROM layanan WHERE id=$1', [ids[1]]);
        await db.query('DELETE FROM pengguna WHERE id=$1', [ids[0]]);
        if (baseline)
          assert.deepEqual(
            await fingerprint(db),
            baseline,
            'Test fixture residual or baseline change',
          );
      } finally {
        await db.end();
      }
    }
  },
);
