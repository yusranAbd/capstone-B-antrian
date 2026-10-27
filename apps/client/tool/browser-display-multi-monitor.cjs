/** Real Chrome profiles + compiled Flutter + real local NestJS/Socket.IO.
 * Fixtures must be unique to capstone_antrean_test; never pass production credentials. */
const { chromium, expect: baseExpect } = require('@playwright/test');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const expect = baseExpect.configure({ timeout: 30000 });

module.exports = async ({
  fixture: f,
  webUrl,
  apiBase,
  output,
  profiles,
  fontFile,
  engineRoot,
  finalPolish = false,
}) => {
  for (const raw of [webUrl, apiBase]) {
    const u = new URL(raw);
    assert.ok(
      u.protocol === 'http:' &&
        ['127.0.0.1', 'localhost'].includes(u.hostname) &&
        !u.username &&
        !u.password &&
        !u.search,
      'Only explicit local QA URLs are allowed',
    );
  }
  assert.equal(
    f.baseline.length,
    13,
    'Review a changed test baseline before running',
  );
  fs.mkdirSync(output, { recursive: true });
  const secrets = [
    f.admin.token,
    f.patient.token,
    ...f.staff.map((s) => s.token),
  ];
  const sanitize = (v) =>
    secrets
      .filter(Boolean)
      .reduce((s, x) => s.replaceAll(x, '[redacted]'), String(v));
  const report = {
    engine:
      'Google Chrome headless, two distinct persistent user-data directories',
    speech: 'controlled id-ID Web Speech, not a speaker hardware test',
    cases: {},
    profiles: 2,
    monitors: 4,
    unexpected401403: [],
    consoleErrors: [],
    failedRequests: [],
    canceledRequests: [],
    apiErrors: [],
    layout: [],
    phase: 'bootstrap',
  };
  const contexts = [],
    pages = [],
    pending = new Set();
  let closing = false;
  async function post(route, body, actor = f.admin) {
    const res = await fetch(apiBase + route, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + actor.token,
      },
      body: JSON.stringify(body),
    });
    assert.ok(res.ok, route + ': HTTP ' + res.status);
    return res.json();
  }
  async function makeProfile(dir) {
    const context = await chromium.launchPersistentContext(dir, {
      channel: 'chrome',
      headless: true,
      viewport: { width: 1366, height: 768 },
      serviceWorkers: 'block',
      timeout: 60000,
    });
    contexts.push(context);
    await context.route('**/*', (route) => {
      const u = new URL(route.request().url());
      if (u.hostname === 'fonts.gstatic.com' && fontFile)
        return route.fulfill({
          body: fs.readFileSync(fontFile),
          contentType: 'font/ttf',
          headers: { 'Access-Control-Allow-Origin': '*' },
        });
      if (
        engineRoot &&
        u.hostname === 'www.gstatic.com' &&
        u.pathname.startsWith('/flutter-canvaskit/')
      ) {
        const file = path.resolve(
          engineRoot,
          u.pathname.split('/').slice(3).join('/'),
        );
        assert.ok(file.startsWith(path.resolve(engineRoot) + path.sep));
        return route.fulfill({
          body: fs.readFileSync(file),
          contentType: file.endsWith('.wasm')
            ? 'application/wasm'
            : 'text/javascript',
          headers: { 'Access-Control-Allow-Origin': '*' },
        });
      }
      const allowed = [new URL(webUrl), new URL(apiBase)].some(
        (a) => a.origin === u.origin,
      );
      return allowed ? route.continue() : route.abort();
    });
    await context.addInitScript(() => {
      window.__qaSpeech = [];
      const Native = window.SpeechSynthesisUtterance;
      window.SpeechSynthesisUtterance = class extends Native {
        get voice() {
          return this.qaVoice || null;
        }
        set voice(v) {
          this.qaVoice = v;
        }
      };
      speechSynthesis.getVoices = () => [
        {
          lang: 'id-ID',
          name: 'QA Indonesian',
          voiceURI: 'qa-id',
          localService: true,
          default: true,
        },
      ];
      let timer,
        speaking = 0;
      window.__qaSpeechMaxConcurrent = 0;
      speechSynthesis.cancel = () => {
        clearTimeout(timer);
        speaking = 0;
      };
      speechSynthesis.speak = (u) => {
        window.__qaSpeech.push(u.text);
        speaking++;
        window.__qaSpeechMaxConcurrent = Math.max(
          window.__qaSpeechMaxConcurrent,
          speaking,
        );
        u.dispatchEvent(new Event('start'));
        timer = setTimeout(() => {
          speaking = 0;
          u.dispatchEvent(new Event('end'));
        }, 25);
      };
    });
    report.chromeVersion = context.browser().version();
    return context;
  }
  async function createMonitor(context, index) {
    const p = await context.newPage();
    const info = {
      p,
      context,
      index,
      id: f.devices[index],
      clinic: f.clinics[index === 1 ? 1 : 0],
      epoch: 0,
      ready: 0,
      events: [],
      snapshots: [],
      outgoingAuth: [],
    };
    pages.push(info);
    const requestPhases = new WeakMap();
    p.on('request', (r) =>
      requestPhases.set(r, { phase: report.phase, epoch: info.epoch }),
    );
    p.on('pageerror', (e) => report.consoleErrors.push(sanitize(e.message)));
    p.on('console', (m) => {
      if (m.type() === 'error' && !/401|403/.test(m.text()))
        report.consoleErrors.push(sanitize(m.text()));
    });
    p.on('requestfailed', (r) => {
      if (!closing) {
        const failure = {
          index,
          path: new URL(r.url()).pathname,
          error: r.failure()?.errorText,
        };
        if (failure.error === 'net::ERR_ABORTED')
          report.canceledRequests.push(failure);
        else report.failedRequests.push(failure);
      }
    });
    p.on('response', (response) => {
      if (!response.url().startsWith(apiBase + '/display/')) return;
      const task = (async () => {
        const status = response.status(),
          phase = requestPhases.get(response.request())?.phase;
        if (status >= 500)
          report.apiErrors.push({
            index,
            path: new URL(response.url()).pathname,
            status,
            phase,
          });
        if (
          [401, 403].includes(status) &&
          !(index === 0 && ['rotate', 're-pair', 'disable'].includes(phase))
        )
          report.unexpected401403.push({
            index,
            path: new URL(response.url()).pathname,
            status,
            phase,
          });
        if (response.url().endsWith('/snapshot') && response.ok()) {
          const selector = await response
            .request()
            .headerValue('x-display-device-id');
          assert.equal(selector, info.id, 'Wrong per-tab REST selector');
          info.snapshots.push({ status, selector });
        }
      })().catch((e) => {
        if (!closing) report.consoleErrors.push(sanitize(e.message));
      });
      pending.add(task);
      task.finally(() => pending.delete(task));
    });
    p.on('websocket', (ws) => {
      assert.equal(
        new URL(ws.url()).origin,
        new URL(apiBase).origin.replace('http:', 'ws:'),
      );
      ws.on('framereceived', ({ payload }) => {
        const text = payload.toString(),
          prefix = '42/display,';
        if (text.startsWith('44/display,'))
          info.events.push({
            aksi: 'HANDSHAKE_ERROR',
            message: sanitize(text),
          });
        if (!text.startsWith(prefix)) return;
        const [event, body] = JSON.parse(text.slice(prefix.length));
        if (event === 'display:ready') {
          assert.equal(body.layananId, info.clinic);
          info.ready++;
        }
        if (event === 'display:updated') {
          assert.equal(body.layananId, info.clinic, 'Cross-clinic event');
          assert.equal(body.namaPasien, undefined);
          info.events.push(body);
        }
      });
      ws.on('framesent', ({ payload }) => {
        const text = payload.toString(),
          prefix = '40/display,';
        if (text.startsWith(prefix)) {
          const data = JSON.parse(text.slice(prefix.length));
          assert.equal(data.perangkatId, info.id);
          assert.equal(data.layananId, info.clinic);
          assert.equal(data.token, undefined);
          info.outgoingAuth.push({
            perangkatId: data.perangkatId,
            layananId: data.layananId,
          });
        }
      });
    });
    await open(info);
    return info;
  }
  async function open(info) {
    await info.p.goto(webUrl, { waitUntil: 'domcontentloaded' });
    await info.p.locator('flt-glass-pane').waitFor({ state: 'attached' });
    await enableSemantics(info.p);
  }
  async function enableSemantics(page) {
    await expect
      .poll(async () => {
        const placeholder = page.locator('flt-semantics-placeholder');
        if (await placeholder.count())
          await placeholder.evaluate((el) => el.click());
        return (
          (await page
            .getByRole('button', {
              name: 'Hubungkan Perangkat',
              exact: true,
              includeHidden: true,
            })
            .count()) > 0 ||
          (await page
            .getByRole('button', {
              name: 'Ganti perangkat',
              exact: true,
              includeHidden: true,
            })
            .count()) > 0
        );
      })
      .toBe(true);
  }
  async function press(info, name) {
    await info.p.bringToFront();
    await info.p
      .getByRole('button', { name, exact: true, includeHidden: true })
      .first()
      .click();
  }
  async function pair(info, code) {
    secrets.push(code);
    await expect(
      info.p.getByText('Aktivasi Public Display', { exact: true }),
    ).toBeVisible();
    const field = info.p.getByRole('textbox', {
      name: 'Kode Aktivasi',
      includeHidden: true,
    });
    await info.p.bringToFront();
    await field.click();
    await field.press('ControlOrMeta+A');
    await field.press('Backspace');
    await field.pressSequentially(code, { delay: 8 });
    await expect
      .poll(async () => (await field.inputValue()) === code)
      .toBe(true);
    await field.press('Tab');
    await press(info, 'Hubungkan Perangkat');
    await live(info);
  }
  async function live(info) {
    await expect(
      info.p.getByText('Realtime terhubung', { exact: true }),
    ).toBeVisible();
    await expect.poll(() => info.snapshots.length).toBeGreaterThan(0);
  }
  async function shot(info, name) {
    await info.p.bringToFront();
    await info.p.screenshot({
      path: path.join(output, name),
      fullPage: false,
      timeout: 60000,
      animations: 'disabled',
    });
  }
  function eventCount(info, action) {
    return info.events.filter((e) => e.aksi === action).length;
  }
  async function queueAction(action, route) {
    report.phase = action;
    const old = pages.map((i) => eventCount(i, action));
    await post(route, { loketId: f.rooms[0] }, f.staff[0]);
    for (const info of pages.filter((i) => i.index !== 1))
      await expect
        .poll(() => eventCount(info, action))
        .toBeGreaterThan(old[info.index]);
    assert.equal(
      eventCount(pages[1], action),
      old[1],
      'Bedah received Anak invalidation',
    );
  }
  try {
    const profileA = await makeProfile(profiles[0]),
      profileB = await makeProfile(profiles[1]);
    const a = await createMonitor(profileA, 0);
    const b = await createMonitor(profileA, 1);
    await pair(
      a,
      (await post('/perangkat-display/' + a.id + '/aktivasi', {})).kode,
    );
    await pair(
      b,
      (await post('/perangkat-display/' + b.id + '/aktivasi', {})).kode,
    );
    await live(a);
    await live(b);
    report.cases.differentClinicsSameProfile = true;
    const c = await createMonitor(profileA, 2);
    await pair(
      c,
      (await post('/perangkat-display/' + c.id + '/aktivasi', {})).kode,
    );
    const d = await createMonitor(profileB, 3);
    await pair(
      d,
      (await post('/perangkat-display/' + d.id + '/aktivasi', {})).kode,
    );
    report.cases.twoChromeProfiles = true;
    const cookieA = await profileA.cookies(apiBase),
      cookieB = await profileB.cookies(apiBase);
    for (const info of pages) {
      const cookie = (info.index === 3 ? cookieB : cookieA).find(
        (v) => v.name === 'queueb_display_' + info.id,
      );
      assert.ok(
        cookie &&
          cookie.httpOnly &&
          cookie.sameSite === 'Strict' &&
          !cookie.secure,
      );
      secrets.push(cookie.value);
      const exposed = await info.p.evaluate(() =>
        JSON.stringify({
          cookie: document.cookie,
          local: { ...localStorage },
          session: { ...sessionStorage },
          url: location.href,
        }),
      );
      for (const secret of secrets)
        assert.ok(
          !exposed.includes(secret),
          'Credential visible to JavaScript/storage/URL',
        );
      const selected = await info.p.evaluate(() =>
        Object.values(sessionStorage),
      );
      assert.deepEqual(selected, [info.id]);
    }
    assert.equal(
      cookieB.filter((c) => c.name.startsWith('queueb_display_')).length,
      1,
    );
    const unauthorizedProfile = await profileB.request.get(
      apiBase + '/display/' + b.clinic + '/snapshot',
      { headers: { 'x-display-device-id': b.id } },
    );
    assert.equal(unauthorizedProfile.status(), 401);
    report.cases.otherProfileCannotBorrowCredential = true;
    report.cases.httpOnlyAndNoStorageToken = true;
    const wrong = await profileA.request.get(
      apiBase + '/display/' + b.clinic + '/snapshot',
      { headers: { 'x-display-device-id': a.id } },
    );
    assert.equal(wrong.status(), 403);
    report.cases.crossClinicDenied = true;
    await press(a, 'Aktifkan suara');
    await expect(
      a.p.getByRole('button', { name: 'Matikan suara', exact: true }),
    ).toBeVisible();
    for (const info of [b, c, d])
      await expect(
        info.p.getByRole('button', { name: 'Aktifkan suara', exact: true }),
      ).toBeVisible();
    report.cases.independentAudio = true;
    await queueAction('CALL', '/queue/panggil');
    for (const info of [a, c, d])
      await expect(
        info.p.getByText('SEDANG DIPANGGIL', { exact: true }),
      ).toBeVisible();
    await expect
      .poll(() => a.p.evaluate(() => window.__qaSpeech.length))
      .toBe(2);
    report.cases.call = true;
    await queueAction('RECALL', '/queue/' + f.tickets[0] + '/panggil-ulang');
    await expect
      .poll(() => a.p.evaluate(() => window.__qaSpeech.length))
      .toBe(3);
    report.cases.recall = true;
    await shot(a, 'chrome-anak-1366.png');
    await shot(b, 'chrome-bedah-1366.png');
    await shot(c, 'chrome-same-clinic-1366.png');
    await shot(d, 'chrome-profile-2-1366.png');
    const bReady = b.ready,
      cReady = c.ready,
      dReady = d.ready,
      aReady = a.ready;
    await Promise.all([...pending]);
    a.epoch++;
    await a.p.reload({ waitUntil: 'domcontentloaded' });
    await enableSemantics(a.p);
    await live(a);
    await expect.poll(() => a.ready).toBeGreaterThan(aReady);
    assert.equal(b.ready, bReady);
    assert.equal(c.ready, cReady);
    assert.equal(d.ready, dReady);
    assert.equal(await a.p.evaluate(() => window.__qaSpeech.length), 0);
    report.cases.reloadAndSocketReconnect = true;
    await queueAction('SKIP', '/queue/' + f.tickets[0] + '/lewati');
    for (const info of [a, c, d])
      await expect(info.p.getByText('Dilewati', { exact: true })).toBeVisible();
    report.cases.skip = true;
    await queueAction('REQUEUE', '/queue/' + f.tickets[0] + '/antre-ulang');
    for (const info of [a, c, d]) {
      await expect(info.p.getByText('Menunggu', { exact: true })).toBeVisible();
      await expect
        .poll(async () => {
          const response = await info.context.request.get(
            apiBase + '/display/' + info.clinic + '/snapshot',
            { headers: { 'x-display-device-id': info.id } },
          );
          assert.equal(response.status(), 200);
          const snapshot = await response.json();
          assert.equal(snapshot.layanan.kode, f.clinicCodes[0]);
          return (
            snapshot.antrianPasien.length === 1 &&
            snapshot.antrianPasien[0].status === 'MENUNGGU'
          );
        })
        .toBe(true);
      await expect(info.p.getByText('AN-001', { exact: true })).toHaveCount(1);
    }
    report.cases.requeueNoDuplicate = true;
    report.cases.sameClinicConsistent = true;
    if (finalPolish) {
      for (const [width, height] of [
        [1280, 720],
        [1366, 768],
        [1920, 1080],
      ]) {
        await a.p.bringToFront();
        await a.p.setViewportSize({ width, height });
        await queueAction('CALL', '/queue/panggil');
        await expect(
          a.p.getByText('SEDANG DIPANGGIL', { exact: true }),
        ).toBeVisible();
        await shot(a, 'polish-call-' + width + '.png');
        await queueAction('SKIP', '/queue/' + f.tickets[0] + '/lewati');
        await queueAction('REQUEUE', '/queue/' + f.tickets[0] + '/antre-ulang');
      }
      await press(a, 'Layar penuh');
      await expect
        .poll(() => a.p.evaluate(() => !!document.fullscreenElement))
        .toBe(true);
      await press(a, 'Keluar fullscreen');
      await expect
        .poll(() => a.p.evaluate(() => !!document.fullscreenElement))
        .toBe(false);
      report.cases.fullscreen = true;
      await d.p.evaluate(() => {
        speechSynthesis.getVoices = () => [];
      });
      await press(d, 'Aktifkan suara');
      await expect(
        d.p.getByText('Suara tidak tersedia. Gunakan pengumuman visual.', {
          exact: true,
        }),
      ).toBeVisible();
      await expect(
        d.p.getByRole('button', { name: 'Aktifkan suara', exact: true }),
      ).toBeVisible();
      report.cases.missingIndonesianVoice = true;
      await f.addWaiting();
      await press(a, 'Muat ulang');
      await expect
        .poll(async () => {
          const r = await a.context.request.get(
            apiBase + '/display/' + a.clinic + '/snapshot',
            { headers: { 'x-display-device-id': a.id } },
          );
          const v = await r.json();
          return v.totalAntrianPasien;
        })
        .toBe(14);
      await expect(a.p.getByText('AN-014', { exact: true })).toBeVisible({
        timeout: 45000,
      });
      report.cases.autoPagination = true;
      await shot(a, 'polish-pagination-1920.png');
    }
    report.phase = 'rotate';
    const code = (await post('/perangkat-display/' + a.id + '/aktivasi', {}))
      .kode;
    secrets.push(code);
    await expect(
      a.p.getByText('Akses display ditolak', { exact: true }),
    ).toBeVisible();
    for (const info of [b, c, d]) await live(info);
    report.phase = 're-pair';
    await press(a, 'Ganti perangkat');
    await pair(a, code);
    for (const info of [b, c, d]) await live(info);
    const rotatedCookie = (await profileA.cookies(apiBase)).find(
      (v) => v.name === 'queueb_display_' + a.id,
    );
    secrets.push(rotatedCookie.value);
    assert.ok(rotatedCookie.httpOnly && rotatedCookie.sameSite === 'Strict');
    assert.ok(
      rotatedCookie.value !==
        cookieA.find((v) => v.name === rotatedCookie.name).value,
    );
    report.cases.rotationOnlyA = true;
    report.phase = 'disable';
    await post('/perangkat-display/' + a.id + '/nonaktifkan', {});
    await expect(
      a.p.getByText('Akses display ditolak', { exact: true }),
    ).toBeVisible();
    await expect(
      a.p.getByText(/Perangkat dinonaktifkan/).first(),
    ).toBeVisible();
    for (const info of [b, c, d]) await live(info);
    report.cases.deactivationOnlyA = true;
    for (const [width, height] of [
      [1280, 720],
      [1366, 768],
      [1920, 1080],
    ]) {
      await b.p.bringToFront();
      await b.p.setViewportSize({ width, height });
      await b.p.waitForTimeout(100);
      const metrics = await b.p.evaluate(() => ({
        width: innerWidth,
        height: innerHeight,
        scrollWidth: document.scrollingElement.scrollWidth,
        scrollHeight: document.scrollingElement.scrollHeight,
      }));
      assert.ok(metrics.scrollWidth <= width && metrics.scrollHeight <= height);
      report.layout.push({ ...metrics, noScroll: true });
      await shot(b, 'chrome-layout-' + width + '.png');
    }
    await Promise.all([...pending]);
    assert.deepEqual(report.apiErrors, []);
    assert.deepEqual(report.unexpected401403, []);
    assert.deepEqual(report.consoleErrors, []);
    assert.deepEqual(report.failedRequests, []);
    assert.ok(pages.every((p) => p.outgoingAuth.length > 0));
    report.cases.noUnexpected401403 = true;
    report.cases.noCrossClinicLeak = true;
    report.cases.noScroll = true;
    for (const info of pages)
      assert.ok(
        await info.p.evaluate(() => window.__qaSpeechMaxConcurrent <= 1),
      );
    report.cases.noOverlappingSpeech = true;
    report.connections = pages.map((i) => ({
      monitor: i.index + 1,
      ready: i.ready,
      invalidations: i.events.length,
      snapshots: i.snapshots.length,
    }));
    report.success = true;
    fs.writeFileSync(
      path.join(output, 'report.json'),
      JSON.stringify(report, null, 2),
    );
    return report;
  } catch (e) {
    report.success = false;
    report.error = sanitize(e.message);
    report.diagnostics = await Promise.all(
      pages.map(async (info) => ({
        monitor: info.index + 1,
        ready: info.ready,
        snapshots: info.snapshots.length,
        outgoingAuth: info.outgoingAuth,
        text: sanitize(
          await info.p
            .locator('body')
            .innerText()
            .catch(() => 'closed'),
        ).slice(0, 1400),
      })),
    );
    fs.writeFileSync(
      path.join(output, 'report.json'),
      JSON.stringify(report, null, 2),
    );
    throw new Error('Multi-monitor Chrome QA: ' + report.error);
  } finally {
    closing = true;
    for (const context of contexts) await context.close();
  }
};
