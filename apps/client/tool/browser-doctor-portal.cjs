/** Real Flutter → NestJS → Socket.IO proof. Fixture lifecycle is owned by run-live.cjs. */
const {chromium, expect: baseExpect} = require('@playwright/test');
const expect = baseExpect.configure({timeout: 25000});
const {enter, button, reveal} = require('./browser-demo.cjs').helpers;
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
module.exports = async function({fixture: f, root}) {
  const images = path.resolve(__dirname, '../../../docs/frontend/images');
  fs.mkdirSync(images, {recursive:true});
  async function post(route, body, token) {
    let r;
    try { r = await fetch('http://127.0.0.1:3001/api/v1' + route, {method:'POST', headers: {'Content-Type':'application/json', ...(token ? {Authorization:'Bearer '+token} : {})}, body:JSON.stringify(body)}); }
    catch(e) { throw Error('QA POST '+route+': '+(e.cause?.code || e.name)); }
    assert.ok(r.ok, route + ' HTTP ' + r.status); return r.json();
  }
  const staff = await post('/auth/login', {email:f.petugas.email, kataSandi:f.petugas.password});
  const patient = await post('/auth/login', {email:f.patient1.email, kataSandi:f.patient1.password});
  const appt = await post('/janji-temu', {slotPraktikId:f.slotId}, patient.accessToken);
  const walkUser = await post('/auth/login', {email:f.patient2.email, kataSandi:f.patient2.password});
  const walk = await post('/reservasi', {layananId:f.serviceId, tanggalAntrean:f.date}, walkUser.accessToken);
  const qr = await post(`/tiket/${walk.id}/qr`, {}, walkUser.accessToken);
  const browser = await chromium.launch({channel:'msedge',headless:true});
  let page;
  const errors = [], methods = [];
  let doctorEvents = 0;
  const report = {database:'127.0.0.1:5433/capstone_antrean_test', transport:'Flutter Web release → NestJS/Prisma/PostgreSQL + Socket.IO /doctor', widths:[], appointment:false, walkIn:false, realtimeCall:false, realtimeComplete:false, readOnly:false};
  try {
    page = await browser.newPage({viewport:{width:390,height:1000}});
    page.on('websocket', ws => ws.on('framereceived', frame => { if(typeof frame.payload === 'string' && frame.payload.includes('doctor:updated')) doctorEvents++; }));
    page.on('pageerror', e => errors.push(e.message));
    page.on('request', r => { if(new URL(r.url()).pathname.startsWith('/api/v1/portal-dokter')) methods.push(r.method()); });
    await page.goto('http://127.0.0.1:8080/');
    await enter(page, 'Email', f.doctor.email); await enter(page, 'Kata sandi', f.doctor.password); await button(page, 'Masuk');
    await expect(page.getByRole('group', {name:/^Beranda Dokter/}).first()).toBeVisible();
    await expect(page.locator('[aria-label*="Realtime terhubung"]').first()).toBeVisible();
    await expect(page.getByRole('checkbox', {name:'Appointment: 1',exact:true})).toBeVisible(); report.appointment=true;
    for(const width of [320,390,768,1280]) {
      await page.setViewportSize({width,height:1000}); await page.waitForTimeout(200);
      await page.mouse.move(10,10); await page.waitForTimeout(350); await page.screenshot({path:path.join(images,`doctor-portal-home-${width}.png`)}); report.widths.push(width);
    }
    await page.setViewportSize({width:390,height:1000});
    // Check-in/enqueue/CALL performed by authorized staff API; doctor UI stays open.
    await post('/check-in', {qrPayload:qr.qrPayload, loketId:f.roomId}, staff.accessToken);
    await post(`/queue/${walk.id}/masuk`, {loketId:f.roomId}, staff.accessToken);
    await page.getByRole('tab', {name:'Monitoring',exact:true}).click();
    await expect(page.locator('[aria-label*="Menunggu: 1"]').first()).toBeVisible(); report.walkIn=true;
    const called = await post('/queue/panggil', {loketId:f.roomId}, staff.accessToken);
    assert.equal(called.tiketId,walk.id);
    await expect(page.getByRole('checkbox', {name:'DIPANGGIL',exact:true})).toBeVisible();
    await page.screenshot({path:path.join(images,'doctor-portal-call-mobile.png')}); report.realtimeCall=true;
    await post(`/queue/${walk.id}/mulai-pelayanan`, {loketId:f.roomId}, staff.accessToken);
    await expect(page.getByRole('checkbox', {name:'DILAYANI',exact:true})).toBeVisible();
    await post(`/queue/${walk.id}/selesaikan-pelayanan`, {loketId:f.roomId}, staff.accessToken);
    await expect(page.getByText('Belum ada nomor dipanggil.', {exact:false}).or(page.locator('[aria-label*="Belum ada nomor dipanggil."]')).first()).toBeVisible(); report.realtimeComplete=true;
    await page.getByRole('tab', {name:'Janji Temu Saya',exact:true}).click();
    await expect(page.getByText(appt.nomorAntrean, {exact:false}).or(page.locator('[aria-label*="'+appt.nomorAntrean+'"]')).first()).toBeVisible();
    await page.mouse.move(10,10); await page.waitForTimeout(350);
    await page.screenshot({path:path.join(images,'doctor-portal-appointments-mobile.png')});
    assert.ok(methods.length > 5 && methods.every(m=>m==='GET')); report.readOnly=true; assert.ok(doctorEvents >= 3); report.doctorEvents = doctorEvents;
    assert.equal(errors.length,0,'Browser runtime errors');
    fs.writeFileSync(path.resolve(__dirname,'../../../docs/frontend/doctor-portal-web-qa.json'),JSON.stringify(report,null,2)+'\n');
    console.log('Doctor Portal Web PASS: '+JSON.stringify(report));
  } catch(e) {
    if(page && !page.isClosed()) {
      await page.screenshot({path:path.join(root,'doctor-portal-failure.png')}).catch(()=>{});
      console.error('Doctor portal failure: '+e.message);
      console.error(JSON.stringify(await page.locator('[aria-label]').evaluateAll(ns=>ns.map(n=>({role:n.getAttribute('role'),label:n.getAttribute('aria-label')})))));
    }
    throw e;
  } finally { await browser.close(); }
};
