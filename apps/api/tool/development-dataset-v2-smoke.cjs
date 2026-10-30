// A dedicated real Nest HTTP instance: only GET and auth login/logout admitted.
// Existing rate limits, JWT/session validation and RBAC remain enabled.
const fs = require('node:fs'),
  path = require('node:path'),
  assert = require('node:assert/strict');
const { setTimeout: delay } = require('node:timers/promises');
const { Client } = require('pg');
const { assertTarget } = require('./development-data.cjs');
async function smoke(config, args, plan, state, dir) {
  require('reflect-metadata');
  assertTarget(config.DATABASE_URL, config.NODE_ENV || 'development');
  const { fingerprint } = require('./development-dataset-v2.cjs');
  const { Test } = require('@nestjs/testing'),
    { ConfigService } = require('@nestjs/config');
  const { AppModule } = require('../dist/app.module'),
    { PrismaService } = require('../dist/prisma/prisma.service');
  const { configureApp } = require('../dist/configure-app');
  const prisma = new PrismaService(
    new ConfigService({ ...config, SERVICE_TIME_ZONE: 'Asia/Jakarta' }),
  );
  const module = await Test.createTestingModule({ imports: [AppModule] })
    .overrideProvider(PrismaService)
    .useValue(prisma)
    .compile();
  const app = module.createNestApplication();
  app.useLogger(['error']);
  app.use((req, res, next) => {
    if (
      req.method === 'GET' ||
      req.method === 'OPTIONS' ||
      (req.method === 'POST' &&
        ['/api/v1/auth/login', '/api/v1/auth/logout'].includes(req.path))
    )
      return next();
    res.status(405).json({
      message:
        'Dataset verification admits read-only requests and owned login/logout only',
    });
  });
  configureApp(app);
  const db = new Client({ connectionString: config.DATABASE_URL });
  await db.connect();
  const report = {
    target: plan.target,
    startedAt: new Date().toISOString(),
    transport:
      'real Nest HTTP, original JWT/RBAC/throttle; GET and login/logout only',
    roles: { PETUGAS: 0, DOKTER: 0, USER: 0 },
    boundaryDates: {},
    sessionsCreated: [],
    http5xx: 0,
  };
  const owned = [];
  let before;
  try {
    assert.equal(
      (await db.query('SELECT current_database() name')).rows[0].name,
      'capstone_antrean',
    );
    before = await fingerprint(db);
    await app.listen(0, '127.0.0.1');
    const base =
      'http://127.0.0.1:' + app.getHttpServer().address().port + '/api/v1';
    const request = async (route, token, body, expected = 200) => {
      const r = await fetch(base + route, {
        method: body === undefined ? 'GET' : 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(token ? { Authorization: 'Bearer ' + token } : {}),
        },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      });
      if (r.status >= 500) report.http5xx++;
      assert.equal(r.status, expected, 'HTTP status on ' + route);
      return r.json();
    };
    // Administrative catalog reads use official services, without manufacturing an
    // ADMIN session or requesting/resetting the primary administrator's password.
    const load = (f, c) => app.get(require('../dist/' + f)[c]);
    const services = await load(
      'layanan/layanan.service',
      'LayananService',
    ).findAll();
    assert.equal(services.length, 11);
    assert(
      (
        await load(
          'akun-petugas/akun-petugas.service',
          'AkunPetugasService',
        ).list()
      ).length >= 6,
    );
    assert(
      (
        await load(
          'penugasan-petugas/penugasan-petugas.service',
          'PenugasanPetugasService',
        ).findAll('ADMIN', plan.adminId)
      ).length >= 6,
    );
    const practice = load(
      'jadwal-praktik/jadwal-praktik.service',
      'JadwalPraktikService',
    );
    assert(
      (await practice.findAll('ADMIN', { tanggal: '2026-10-31' })).length > 0,
    );
    report.admin = {
      officialServiceCatalogReads: true,
      primaryAccountUnchanged: true,
      httpLogin: 'not attempted; existing credential not supplied',
    };
    const old = JSON.parse(
      fs.readFileSync(path.join(args['--source-batch'], 'akun-pengujian.json')),
    );
    const fresh = JSON.parse(
      fs.readFileSync(path.join(dir, 'dataset-v2-credentials.json')),
    );
    const accounts = fresh.accounts
      .map((c) => ({ email: c.email, password: c.password, role: c.role }))
      .concat(
        old.accounts
          .filter(
            (c) =>
              c.role === 'DOKTER' ||
              (c.role === 'USER' &&
                c === old.accounts.find((a) => a.role === 'USER')),
          )
          .map((c) => ({
            email: c.email,
            password: c.kataSandi,
            role: c.role,
          })),
      );
    let logins = 0;
    for (const c of accounts) {
      if (logins && logins % 5 === 0) {
        console.log('Smoke: respecting existing five-logins-per-minute limit');
        await delay(60500);
      }
      const login = await request('/auth/login', null, {
        email: c.email,
        kataSandi: c.password,
        namaPerangkat: 'Dataset V2 read-only verification',
      });
      logins++;
      assert.equal(login.user.peran, c.role);
      const token = login.accessToken;
      const sid = JSON.parse(Buffer.from(token.split('.')[1], 'base64url')).sid;
      report.sessionsCreated.push(sid);
      owned.push({ token, refresh: login.refreshToken, sid });
      try {
        await request('/auth/me', token);
        await request('/akun-petugas', token, undefined, 403);
        if (c.role === 'PETUGAS') {
          const assignments = await request('/penugasan-petugas', token);
          assert.equal(assignments.length, 1);
          const room = assignments[0].loketId;
          assert(room);
          await request('/queue/snapshot?loketId=' + room, token);
          const foreign = await prisma.loket.findFirst({
            where: { id: { not: room }, aktif: true },
            select: { id: true },
          });
          assert(foreign);
          await request(
            '/queue/snapshot?loketId=' + foreign.id,
            token,
            undefined,
            403,
          );
        }
        if (c.role === 'DOKTER') {
          await request('/portal-dokter/profil', token);
          let total = 0;
          for (const day of ['2026-10-31', '2026-11-01', '2026-11-30']) {
            const rows = await request(
              '/portal-dokter/jadwal?tanggal=' + day,
              token,
            );
            assert(Array.isArray(rows));
            if (day === '2026-11-01') assert.equal(rows.length, 0);
            total += rows.length;
          }
          assert(total > 0, 'Doctor has no boundary-date practice');
        }
        if (c.role === 'USER') {
          const catalog = await request('/layanan', token);
          for (const s of plan.services)
            assert(catalog.some((c) => c.kode === s.code && c.aktif));
          for (const day of ['2026-10-31', '2026-11-01', '2026-11-30']) {
            const rows = await request('/jadwal-praktik?tanggal=' + day, token);
            assert.equal(rows.length, day === '2026-11-01' ? 0 : 6);
            report.boundaryDates[day] = rows.length;
          }
          const session = await prisma.jadwalPraktik.findFirst({
            where: {
              tanggal: new Date('2026-10-31T00:00:00Z'),
              aktif: true,
              dokterLayanan: { layanan: { modeReservasi: 'HIBRIDA' } },
            },
            select: { id: true },
          });
          assert(session);
          const slots = await request(
            '/slot-praktik?jadwalPraktikId=' + session.id,
            token,
          );
          assert(slots.some((s) => s.tersedia === true));
          report.patient = {
            allSixDailyServicesInCatalog: true,
            availableConsultationSlots: true,
            noBookingOrQrCreated: true,
            homeAuxiliaryCodes:
              'Home visibility is verified separately by Patient Catalog V2 tests; catalog GET alone does not prove Home visibility',
          };
        }
        report.roles[c.role]++;
      } finally {
        await request('/auth/logout', token, {
          refreshToken: login.refreshToken,
        });
        owned.pop();
      }
      console.log(
        'Dataset V2 smoke completed: ' + c.role + ' ' + report.roles[c.role],
      );
    }
    // The additional existing FARM01 doctor is preserved, including its unknown
    // credential; validate its own service view without fabricating a login.
    const farm = await prisma.dokter.findUnique({ where: { kode: 'FARM01' } });
    if (farm) {
      const portal = load(
        'portal-dokter/portal-dokter.service',
        'PortalDokterService',
      );
      await portal.profil(farm.penggunaId);
      assert.equal(
        (await portal.jadwal(farm.penggunaId, '2026-10-31')).length,
        1,
      );
      report.additionalDoctor = {
        code: 'FARM01',
        officialServiceRead: true,
        httpLogin: 'not attempted; existing credential preserved',
      };
    }
    const quota = (
      await db.query(
        `SELECT j.layanan_id,j.hari,sum(s.kapasitas)::int AS used,j.kapasitas_harian FROM slot_praktik s JOIN jadwal_praktik p ON p.id=s.jadwal_praktik_id JOIN dokter_layanan d ON d.id=p.dokter_layanan_id JOIN jadwal_layanan j ON j.layanan_id=d.layanan_id AND j.hari::text=(ARRAY['MINGGU','SENIN','SELASA','RABU','KAMIS','JUMAT','SABTU'])[extract(dow from p.tanggal)::int+1] WHERE p.aktif AND s.aktif AND p.tanggal BETWEEN '2026-10-31' AND '2026-11-30' GROUP BY j.layanan_id,j.hari,p.tanggal,j.kapasitas_harian HAVING sum(s.kapasitas)>j.kapasitas_harian`,
      )
    ).rows;
    assert.equal(quota.length, 0);
    report.slotCapacityExceeded = 0;
    const after = await fingerprint(db);
    for (const t of Object.keys(before)) {
      if (t === 'sesi_pengguna') {
        assert.deepEqual(
          after[t].filter((r) => before[t].some((b) => b.id === r.id)),
          before[t],
        );
        assert.deepEqual(
          after[t]
            .filter((r) => !before[t].some((b) => b.id === r.id))
            .map((r) => r.id)
            .sort(),
          report.sessionsCreated.slice().sort(),
        );
      } else
        assert.deepEqual(
          after[t],
          before[t],
          'Smoke changed business data: ' + t,
        );
    }
    report.businessDataUnchanged = true;
    report.preExistingSessionsUnchanged = true;
    report.status = 'PASS';
  } catch (e) {
    report.status = 'FAIL';
    report.error = {
      name: e.name,
      message:
        e instanceof assert.AssertionError
          ? e.message.split('\n')[0]
          : 'inspect private diagnostics',
    };
    throw e;
  } finally {
    for (const s of owned)
      await module
        .get(require('../dist/auth/auth.service').AuthService)
        .logout({ refreshToken: s.refresh })
        .catch(() => {});
    report.finishedAt = new Date().toISOString();
    fs.writeFileSync(
      path.join(dir, 'http-smoke.json'),
      JSON.stringify(report, null, 2) + '\n',
      { mode: 0o600 },
    );
    await app.close();
    await db.end();
    console.log(
      JSON.stringify({
        status: report.status,
        roles: report.roles,
        boundaryDates: report.boundaryDates,
        http5xx: report.http5xx,
        businessDataUnchanged: report.businessDataUnchanged,
        sessionsCreated: report.sessionsCreated.length,
      }),
    );
  }
}
module.exports = { smoke };
