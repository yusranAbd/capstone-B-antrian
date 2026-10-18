/** Compiled Flutter → real local test API/Socket.IO. No REST/queue stubs. */
const {chromium, expect: baseExpect} = require('@playwright/test');
const {enter, button} = require('./browser-demo.cjs').helpers;
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
const expect = baseExpect.configure({timeout: 25000});

module.exports = async function ({fixture: f, root}) {
  const output = path.join(root, 'display-v2-qa');
  fs.mkdirSync(output, {recursive: true});
  const secrets = [f.displayToken, f.admin.password];
  const api = 'http://127.0.0.1:3001/api/v1';
  async function post(route, body, token) {
    const response = await fetch(api + route, {method: 'POST', headers: {'Content-Type': 'application/json', ...(token ? {Authorization: 'Bearer ' + token} : {})}, body: JSON.stringify(body)});
    assert.ok(response.ok, 'Fixture API ' + route + ': HTTP ' + response.status);
    return response.json();
  }
  const report = {database: '127.0.0.1:5433/capstone_antrean_test', transport: 'Flutter Web → real NestJS + /display + REST snapshot', speechEngine: 'controlled Web Speech id-ID; no claim of audible hardware synthesis', sizes: [], singleRoom: false, multipleRooms: false, zeroWaiting: false, call: false, recall: false, start: false, complete: false, reconnect: false, noHistoricalSpeech: false, invalidToken: false, missingVoice: false, fullscreen: false, privacy: false};
  const browser = await chromium.launch({
    headless: true,
    timeout: 60000,
    ...(process.env.FLUTTER_BROWSER_CHANNEL ? {channel: process.env.FLUTTER_BROWSER_CHANNEL} : {}),
  });
  report.browser = await browser.version();
  const contexts = [];
  let page, latest, snapshotReads = 0, readyFrames = 0, updateFrames = 0;
  const runtimeErrors = [], requests = [];
  async function display({voice = true, token = f.displayToken, observe = false} = {}) {
    const context = await browser.newContext({viewport: {width: 1280, height: 720}});
    contexts.push(context);
    await context.addInitScript((available) => {
      window.__displaySpeech = [];
      let timer;
      const Native = window.SpeechSynthesisUtterance;
      window.SpeechSynthesisUtterance = class extends Native {
        get voice() { return this.qaVoice || null; }
        set voice(value) { this.qaVoice = value; }
      };
      speechSynthesis.getVoices = () => available ? [{lang: 'id-ID', name: 'QA controlled Indonesian', voiceURI: 'qa-id', localService: true, default: true}] : [];
      speechSynthesis.cancel = () => clearTimeout(timer);
      speechSynthesis.speak = utterance => {
        window.__displaySpeech.push({text: utterance.text, lang: utterance.lang});
        utterance.dispatchEvent(new Event('start'));
        timer = setTimeout(() => utterance.dispatchEvent(new Event('end')), 25);
      };
    }, voice);
    const p = await context.newPage();
    p.on('pageerror', e => runtimeErrors.push(e.message));
    if (observe) {
      // Instrument before navigation/handshake, so the initial transport and
      // its CALL/RECALL frames are observed as well as the reconnected socket.
      p.on('websocket', ws => ws.on('framereceived', ({payload}) => {
        if (typeof payload !== 'string') return;
        if (payload.includes('display:ready')) readyFrames++;
        if (payload.includes('display:updated')) updateFrames++;
      }));
      p.on('response', async response => {
        if (new URL(response.url()).pathname === `/api/v1/display/${f.serviceId}/snapshot` && response.ok()) {
          const data = await response.json().catch(() => null);
          if (data) { latest = data; snapshotReads++; }
        }
      });
      p.on('request', request => {
        if (new URL(request.url()).pathname.startsWith('/api/v1/')) requests.push({url: request.url(), method: request.method(), token: request.headers()['x-display-token']});
      });
    }
    await p.goto('http://127.0.0.1:8080/');
    await button(p, 'Buka Public Display');
    await enter(p, 'ID layanan', f.serviceId);
    await enter(p, 'Token perangkat', token);
    await button(p, 'Hubungkan display');
    return p;
  }
  async function publicNumber(p, number) {
    await expect(p.getByText(number, {exact: true}).or(p.locator('[aria-label*="' + number + '"]')).first()).toBeVisible();
  }
  async function speechCount(p) { return p.evaluate(() => window.__displaySpeech.length); }
  try {
    page = await display({observe: true});
    await expect(page.getByText('Realtime terhubung', {exact: false})).toBeVisible();
    await expect(page.getByText(f.roomName, {exact: false}).first()).toBeVisible();
    report.singleRoom = true;
    await expect(page.getByText('Belum ada nomor dipanggil.', {exact: false})).toBeVisible();
    await button(page, 'Aktifkan suara');
    await expect(page.getByRole('button', {name: 'Matikan suara', exact: true})).toBeVisible();
    assert.equal(await speechCount(page), 1);

    const admin = await post('/auth/login', {email: f.admin.email, kataSandi: f.admin.password});
    const staff = await post('/auth/login', {email: f.petugas.email, kataSandi: f.petugas.password});
    const patient = await post('/auth/login', {email: f.patient1.email, kataSandi: f.patient1.password});
    secrets.push(admin.accessToken, staff.accessToken, patient.accessToken);
    for (const n of [2, 3]) await post('/loket', {layananId: f.serviceId, kode: `LKT-0${n}`, nama: `Ruang Pemeriksaan ${n}`}, admin.accessToken);
    await button(page, 'Muat ulang');
    for (const n of [2, 3]) await expect(page.getByText(`Ruang Pemeriksaan ${n}`, {exact: false}).first()).toBeVisible();
    report.multipleRooms = true;
    await expect.poll(() => latest?.totalMenunggu).toBe(0); report.zeroWaiting = true;
    await page.screenshot({path: path.join(output, 'empty-1280x720.png')});

    const walk = await post('/reservasi', {layananId: f.serviceId, tanggalAntrean: f.date}, patient.accessToken);
    const qr = await post(`/tiket/${walk.id}/qr`, {}, patient.accessToken); secrets.push(qr.qrPayload);
    await post('/check-in', {qrPayload: qr.qrPayload, loketId: f.roomId}, staff.accessToken);
    await post(`/queue/${walk.id}/masuk`, {loketId: f.roomId}, staff.accessToken);
    await expect.poll(() => latest?.totalMenunggu).toBe(1);
    const beforeCall = snapshotReads;
    const call = await post('/queue/panggil', {loketId: f.roomId}, staff.accessToken);
    assert.equal(call.tiketId, walk.id);
    await expect.poll(() => latest?.pengumumanTerakhir?.aksi).toBe('CALL');
    await expect.poll(() => speechCount(page)).toBe(2);
    const number = latest.pengumumanTerakhir.nomorAntrean;
    await publicNumber(page, number);
    assert.ok(snapshotReads > beforeCall);
    assert.equal((await page.evaluate(() => window.__displaySpeech.at(-1))).text, latest.pengumumanTerakhir.teks);
    report.call = true;
    for (const size of [{width: 1280, height: 720}, {width: 1920, height: 1080}]) {
      await page.setViewportSize(size); await page.waitForTimeout(300);
      await page.mouse.move(5, 5);
      await page.screenshot({path: path.join(output, `call-${size.width}x${size.height}.png`)});
      report.sizes.push(size);
    }
    await page.setViewportSize({width: 1280, height: 720});
    await button(page, 'Layar penuh');
    await expect.poll(() => page.evaluate(() => !!document.fullscreenElement)).toBe(true);
    await button(page, 'Keluar fullscreen');
    await expect.poll(() => page.evaluate(() => !!document.fullscreenElement)).toBe(false);
    report.fullscreen = true;
    const firstAudit = latest.pengumumanTerakhir.peristiwaId;
    await post(`/queue/${walk.id}/panggil-ulang`, {loketId: f.roomId}, staff.accessToken);
    await expect.poll(() => speechCount(page)).toBe(3);
    await expect.poll(() => latest?.pengumumanTerakhir?.peristiwaId).not.toBe(firstAudit);
    report.recall = true;
    await button(page, 'Muat ulang'); await page.waitForTimeout(400);
    assert.equal(await speechCount(page), 3);

    // Fresh page/refresh baseline sees a live CALL but never speaks its history.
    const fresh = await display();
    await expect(fresh.getByText('Realtime terhubung', {exact: false})).toBeVisible();
    await publicNumber(fresh, number);
    await button(fresh, 'Aktifkan suara');
    assert.equal(await speechCount(fresh), 1);
    await fresh.reload();
    await button(fresh, 'Buka Public Display');
    await expect(fresh.getByRole('textbox', {name: 'Token perangkat', exact: true})).toHaveValue('');
    await fresh.context().close();
    await page.bringToFront();
    await page.waitForTimeout(400);
    report.noHistoricalSpeech = true;

    await page.context().setOffline(true);
    f.disconnectDisplay();
    await expect(page.getByText('Realtime terputus', {exact: false}).or(page.getByText('Realtime belum tersambung', {exact: false}))).toBeVisible();
    await post(`/queue/${walk.id}/panggil-ulang`, {loketId: f.roomId}, staff.accessToken);
    const offlineAudit = latest.pengumumanTerakhir.peristiwaId;
    await page.context().setOffline(false);
    await expect(page.getByText('Realtime terhubung', {exact: false})).toBeVisible();
    await expect.poll(() => latest?.pengumumanTerakhir?.peristiwaId !== offlineAudit).toBe(true);
    await page.waitForTimeout(400);
    assert.equal(await speechCount(page), 3, 'Reconnect must silently baseline missed RECALL');
    await post(`/queue/${walk.id}/panggil-ulang`, {loketId: f.roomId}, staff.accessToken);
    await expect.poll(() => speechCount(page)).toBe(4);
    report.reconnect = true;

    await post(`/queue/${walk.id}/mulai-pelayanan`, {loketId: f.roomId}, staff.accessToken);
    await expect.poll(() => latest?.loket.flatMap(r => r.tiketAktif).some(t => t.status === 'DILAYANI')).toBe(true);
    await expect(page.getByText('Sedang dilayani', {exact: false}).first()).toBeVisible();
    await expect(page.getByText('Belum ada nomor dipanggil.', {exact: false})).toBeVisible();
    report.start = true;
    await post(`/queue/${walk.id}/selesaikan-pelayanan`, {loketId: f.roomId}, staff.accessToken);
    await expect.poll(() => latest?.loket.flatMap(r => r.tiketAktif).length).toBe(0);
    assert.equal(await speechCount(page), 4);
    report.complete = true;

    const noVoice = await display({voice: false});
    await expect(noVoice.getByText('Realtime terhubung', {exact: false})).toBeVisible();
    await button(noVoice, 'Aktifkan suara');
    await expect(noVoice.getByText('Suara tidak tersedia. Gunakan pengumuman visual.', {exact: false})).toBeVisible();
    await expect(noVoice.getByRole('button', {name: 'Aktifkan suara', exact: true})).toBeVisible();
    report.missingVoice = true;
    await noVoice.context().close();
    const denied = await display({token: 'b'.repeat(64)});
    await expect(denied.getByText('Akses display ditolak', {exact: false}).first()).toBeVisible();
    await expect(denied.getByText(number, {exact: true})).toHaveCount(0);
    report.invalidToken = true;
    await denied.context().close();

    assert.ok(requests.length > 5 && requests.every(r => r.method === 'GET' && new URL(r.url).pathname === `/api/v1/display/${f.serviceId}/snapshot`));
    assert.ok(requests.every(r => r.token === f.displayToken && !r.url.includes(f.displayToken)));
    const storage = await page.evaluate(() => JSON.stringify({local: {...localStorage}, session: {...sessionStorage}}));
    assert.ok(!storage.includes(f.displayToken));
    const visible = await page.locator('flt-semantics').allTextContents();
    assert.ok(!JSON.stringify(visible).includes(f.patient1.email));
    assert.ok(!JSON.stringify(latest).includes('tiketId') && !JSON.stringify(latest).includes('email'));
    report.privacy = true;
    report.realtime = {readyFrames, updateFrames, snapshotReads};
    assert.ok(readyFrames >= 1 && updateFrames >= 5);
    assert.equal(runtimeErrors.length, 0, 'Browser runtime errors');
    fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify(report, null, 2) + '\n');
    console.log('Public Display V2 Web PASS: ' + JSON.stringify(report));
  } catch (error) {
    if (page && !page.isClosed()) {
      report.speechRequests = await page.evaluate(() => window.__displaySpeech).catch(() => []);
      report.lastAnnouncementAction = latest?.pengumumanTerakhir?.aksi;
    }
    fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify(report, null, 2) + '\n');
    if (page && !page.isClosed()) await page.screenshot({path: path.join(output, 'failure.png')}).catch(() => {});
    let message = error.message;
    for (const secret of secrets) message = message.replaceAll(secret, '[redacted]');
    throw new Error('Public Display V2 QA: ' + message);
  } finally {
    for (const context of contexts) await context.close().catch(() => {});
    await browser.close();
  }
};
