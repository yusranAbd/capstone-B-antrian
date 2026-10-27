// Login and GET only. No booking/queue mutation or cleanup on development.
const fs = require('node:fs'),
  path = require('node:path'),
  assert = require('node:assert/strict');
const { Client } = require('pg');
const { assertTarget, externalDirectory } = require('./development-data.cjs');
async function smoke(config, args) {
  assertTarget(config.DATABASE_URL, config.NODE_ENV || 'development');
  const dir = externalDirectory(args['--output']);
  const credentials = JSON.parse(
    fs.readFileSync(path.join(dir, 'akun-pengujian.json')),
  );
  const state = JSON.parse(fs.readFileSync(path.join(dir, 'seed-state.json')));
  assert(state.complete, 'Seed harus lengkap sebelum smoke test.');
  const db = new Client({
    connectionString: config.DATABASE_URL,
    options: '-c default_transaction_read_only=on',
  });
  const base =
    'http://127.0.0.1:' + String(config.API_PORT || 3000) + '/api/v1';
  async function request(route, token, body) {
    const r = await fetch(base + route, {
      method: body ? 'POST' : 'GET',
      headers: {
        ...(token ? { Authorization: 'Bearer ' + token } : {}),
        ...(body ? { 'Content-Type': 'application/json' } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(15000),
    });
    return { status: r.status, data: await r.json() };
  }
  await db.connect();
  try {
    assert.equal(
      (await db.query('SELECT current_database() db')).rows[0].db,
      'capstone_antrean',
    );
    const health = await request('/health');
    assert.equal(health.status, 200);
    assert.equal(health.data.service, 'capstone-antrean-api');
    const report = {
      at: new Date().toISOString(),
      health: 200,
      roles: {},
      rbac: {},
      synthetic: true,
      queueMutations: false,
    };
    for (const role of ['USER', 'PETUGAS', 'DOKTER']) {
      const c = credentials.accounts.find((c) => c.role === role);
      const login = await request('/auth/login', null, {
        email: c.email,
        kataSandi: c.kataSandi,
        namaPerangkat: 'Verifikasi HTTP dataset',
      });
      assert.equal(login.status, 200);
      const token = login.data.accessToken;
      assert(token);
      for (const route of ['/auth/me', '/layanan'])
        assert.equal((await request(route, token)).status, 200);
      const denied = await request('/akun-petugas', token);
      assert.equal(denied.status, 403);
      report.roles[role] = { login: true, profile: true, clinics: true };
      report.rbac[role] = 403;
      if (role === 'USER') {
        for (const route of [
          '/dokter',
          '/jadwal-praktik',
          '/slot-praktik?jadwalPraktikId=' + state.practices[0],
          '/tiket/saya',
          '/janji-temu',
        ]) {
          const result = await request(route, token);
          assert.equal(result.status, 200);
          assert(Array.isArray(result.data) && result.data.length > 0);
        }
        report.roles[role].bookingCatalogAndHistory = true;
      }
      if (role === 'PETUGAS') {
        const room = (
          await db.query(
            'SELECT p.loket_id id FROM penugasan_petugas p JOIN pengguna u ON u.id=p.petugas_id WHERE u.email=$1 AND p.aktif',
            [c.email],
          )
        ).rows[0];
        assert(room);
        for (const route of [
          '/queue/menunggu?loketId=' + room.id,
          '/queue/snapshot?loketId=' + room.id,
        ])
          assert.equal((await request(route, token)).status, 200);
        report.roles[role].waitingAndSnapshot = true;
      }
      if (role === 'DOKTER') {
        const today = new Intl.DateTimeFormat('en-CA', {
          timeZone: 'Asia/Jakarta',
          year: 'numeric',
          month: '2-digit',
          day: '2-digit',
        }).format(new Date());
        for (const route of [
          '/portal-dokter/profil',
          '/portal-dokter/jadwal?tanggal=' + today,
          '/portal-dokter/janji-temu?tanggal=' + today,
        ])
          assert.equal((await request(route, token)).status, 200);
        const session = (
          await db.query(
            'SELECT j.id FROM jadwal_praktik j JOIN dokter_layanan d ON d.id=j.dokter_layanan_id JOIN dokter p ON p.id=d.dokter_id JOIN pengguna u ON u.id=p.pengguna_id WHERE u.email=$1 AND j.mulai_pada<=now() AND j.selesai_pada>now()',
            [c.email],
          )
        ).rows[0];
        if (session) {
          assert.equal(
            (
              await request(
                '/portal-dokter/antrean/snapshot?jadwalPraktikId=' + session.id,
                token,
              )
            ).status,
            200,
          );
          report.roles[role].liveSnapshot = true;
        } else
          report.roles[role].liveSnapshot =
            'Tidak ada sesi aktif saat smoke dijalankan';
      }
    }
    fs.writeFileSync(
      path.join(dir, 'http-smoke.json'),
      JSON.stringify(report, null, 2) + '\n',
      { mode: 0o600 },
    );
    console.log(JSON.stringify(report, null, 2));
    return report;
  } finally {
    await db.end();
  }
}
module.exports = { smoke };
