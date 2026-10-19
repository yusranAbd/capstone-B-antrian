/** Real compiled Flutter UI + existing API/Socket.IO; unique test fixtures only. */
const {chromium, expect: baseExpect} = require('@playwright/test');
const {enter, button, choose, mutation, reveal} = require('./browser-demo.cjs').helpers;
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
const expect = baseExpect.configure({timeout: 25000});
module.exports = async ({fixture: f, root}) => {
  const api = 'http://127.0.0.1:3001/api/v1';
  const output = path.join(root, 'display-pairing-qa'); fs.mkdirSync(output, {recursive: true});
  const secrets = [f.admin.password, f.displayToken];
  const browser = await chromium.launch({headless: true, timeout: 60000});
  const contexts = []; const errors = [];
  const report = {database: '127.0.0.1:5433/capstone_antrean_test', adminCreate: false, adminCode: false, pairing: false, cookieHttpOnly: false, persistenceReload: false, oneTime: false, reconnect: false, revoked: false, rotation: false, call: false, recall: false, startComplete: false, privacy: false};
  let adminPage, tv;
  async function post(route, body, token) {
    const response = await fetch(api + route, {method: 'POST', headers: {'Content-Type': 'application/json', ...(token ? {Authorization: 'Bearer ' + token} : {})}, body: JSON.stringify(body)});
    assert.ok(response.ok, 'QA API ' + route + ' HTTP ' + response.status); return response.json();
  }
  async function context(viewport) {
    const c = await browser.newContext({viewport}); contexts.push(c);
    await c.addInitScript(() => { window.__displaySpeech = []; let timer;
      const Native = window.SpeechSynthesisUtterance;
      window.SpeechSynthesisUtterance = class extends Native {get voice(){return this.qaVoice||null;} set voice(v){this.qaVoice=v;}};
      speechSynthesis.getVoices = () => [{lang:'id-ID',name:'QA Indonesian',voiceURI:'qa-id',localService:true,default:true}];
      speechSynthesis.cancel = () => clearTimeout(timer);
      speechSynthesis.speak = u => {window.__displaySpeech.push(u.text);u.dispatchEvent(new Event('start')); timer=setTimeout(()=>u.dispatchEvent(new Event('end')),25);};
    });
    return c;
  }
  async function speechCount() { return tv.evaluate(() => window.__displaySpeech.length); }
  try {
    const adminContext = await context({width:1440,height:1000}); adminPage = await adminContext.newPage();
    adminPage.on('pageerror', e => errors.push(e.message));
    await adminPage.goto('http://127.0.0.1:8080/');
    await enter(adminPage,'Email',f.admin.email); await enter(adminPage,'Kata sandi',f.admin.password); await button(adminPage,'Masuk');
    await expect(adminPage.getByText('Poliklinik',{exact:true}).last()).toBeVisible();
    await adminPage.getByText('Perangkat display',{exact:true}).click();
    await adminPage.getByText('Manajemen Display',{exact:true}).click();
    await expect(adminPage.getByRole('button',{name:'Tambah perangkat',exact:true})).toBeEnabled();
    await button(adminPage,'Tambah perangkat');
    await enter(adminPage,'Nama perangkat','TV Ruang Tunggu Mata');
    await choose(adminPage, 'Poliklinik', 'Poli Fixture Flutter');
    await mutation(adminPage,'POST','/perangkat-display',()=>button(adminPage,'Simpan perangkat'));
    await expect(adminPage.getByRole('dialog')).toHaveCount(0);
    const added = adminPage.getByText('TV Ruang Tunggu Mata',{exact:true}).or(adminPage.locator('[aria-label^="TV Ruang Tunggu Mata"]')).first();
    await reveal(adminPage,added); await expect(added).toBeVisible(); report.adminCreate = true;
    const adminLogin = await post('/auth/login',{email:f.admin.email,kataSandi:f.admin.password});
    const adminToken = adminLogin.accessToken; secrets.push(adminToken);
    const devices = await (await fetch(api+'/perangkat-display',{headers:{Authorization:'Bearer '+adminToken}})).json();
    const device = devices.find(d=>d.nama==='TV Ruang Tunggu Mata' && d.layananId===f.serviceId); assert.ok(device);
    await adminPage.screenshot({path:path.join(output,'admin-display-management.png'),fullPage:true});
    // Search the new device rather than depending on the order of other clinics.
    // The management screenshot above still proves multiple devices per clinic.
    await enter(adminPage,'Cari perangkat atau poliklinik',device.nama);
    const buttons = adminPage.getByRole('button',{name:'Kode aktivasi / rotasi',exact:true});
    await expect(buttons).toHaveCount(1);
    await buttons.click();
    const issued = await mutation(adminPage,'POST',`/perangkat-display/${device.id}/aktivasi`,()=>button(adminPage,'Lanjutkan'));
    const kode = issued.kode; secrets.push(kode);
    assert.ok(/^\d{12}$/.test(kode), '12-digit activation code returned once');
    await expect(adminPage.getByText('Kode aktivasi sekali pakai',{exact:true})).toBeVisible();
    // Flutter SelectableText is painted on canvas. Keep the one-time response
    // only in memory; never capture the popup or serialize its semantics.
    report.adminCode = true;
    await button(adminPage,'Selesai');
    const tvContext = await context({width:1280,height:720}); tv = await tvContext.newPage();
    tv.on('pageerror',e=>errors.push(e.message)); let ready = 0, updates = 0;
    tv.on('websocket',ws=>ws.on('framereceived',({payload})=>{if(typeof payload==='string'){if(payload.includes('display:ready'))ready++;if(payload.includes('display:updated'))updates++;}}));
    await tv.goto('http://127.0.0.1:8080/#/display');
    await expect(tv.getByText('Aktivasi Public Display',{exact:true})).toBeVisible();
    await tv.screenshot({path:path.join(output,'tv-display-activation.png'),fullPage:true});
    await enter(tv,'Kode Aktivasi',kode); await button(tv,'Hubungkan Perangkat');
    await expect(tv.getByText('Realtime terhubung',{exact:false})).toBeVisible(); report.pairing = true;
    const cookies = await tvContext.cookies(api); const cookie = cookies.find(c=>c.name==='queueb_display');
    assert.ok(cookie && cookie.httpOnly && cookie.sameSite==='Strict'); secrets.push(cookie.value); report.cookieHttpOnly = true;
    const exposed = await tv.evaluate(()=>JSON.stringify({cookie:document.cookie,local:{...localStorage},session:{...sessionStorage},url:location.href}));
    assert.ok(!exposed.includes(cookie.value) && !exposed.includes(kode)); report.privacy = true;
    const replay = await fetch(api+'/display/pairing',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({kode})}); assert.equal(replay.status,410); report.oneTime = true;
    await tv.reload(); await expect(tv.getByText('Realtime terhubung',{exact:false})).toBeVisible(); report.persistenceReload = true;
    await button(tv,'Aktifkan suara');
    const patient = await post('/auth/login',{email:f.patient1.email,kataSandi:f.patient1.password});
    const staff = await post('/auth/login',{email:f.petugas.email,kataSandi:f.petugas.password});
    secrets.push(patient.accessToken,staff.accessToken);
    const booking = await post('/reservasi',{layananId:f.serviceId,tanggalAntrean:f.date},patient.accessToken);
    const ticket = booking.tiketId || booking.id;
    const qr = await post(`/tiket/${ticket}/qr`,{},patient.accessToken); secrets.push(qr.qrPayload);
    const checked = await post('/check-in',{qrPayload:qr.qrPayload,loketId:f.roomId},staff.accessToken);
    await post(`/queue/${checked.tiketId}/masuk`,{loketId:f.roomId},staff.accessToken);
    const called = await post('/queue/panggil',{loketId:f.roomId},staff.accessToken);
    await expect(tv.getByText(called.nomorAntrean,{exact:true}).first()).toBeVisible();
    await expect.poll(speechCount).toBe(2); report.call = true;
    await post(`/queue/${called.tiketId}/panggil-ulang`,{loketId:f.roomId},staff.accessToken); await expect.poll(speechCount).toBe(3); report.recall = true;
    const before = await speechCount(); const oldReady = ready;
    await tvContext.setOffline(true); f.disconnectDisplay(); await tv.waitForTimeout(500); await tvContext.setOffline(false);
    await expect.poll(()=>ready).toBeGreaterThan(oldReady); await expect(tv.getByText('Realtime terhubung',{exact:false})).toBeVisible();
    await tv.waitForTimeout(800); assert.equal(await speechCount(),before); report.reconnect = true;
    await tv.screenshot({path:path.join(output,'tv-paired-display.png'),fullPage:true});
    await post(`/queue/${called.tiketId}/mulai-pelayanan`,{loketId:f.roomId},staff.accessToken);
    await expect(tv.getByText('Belum ada nomor dipanggil.',{exact:false})).toBeVisible();
    await post(`/queue/${called.tiketId}/selesaikan-pelayanan`,{loketId:f.roomId},staff.accessToken); report.startComplete = true;
    await post(`/perangkat-display/${device.id}/nonaktifkan`,{},adminToken);
    await expect(tv.getByText('Akses display ditolak',{exact:true})).toBeVisible(); report.revoked = true;
    const rotation = await post(`/perangkat-display/${device.id}/aktivasi`,{},adminToken); secrets.push(rotation.kode);
    await button(tv,'Ganti perangkat'); await enter(tv,'Kode Aktivasi',rotation.kode); await button(tv,'Hubungkan Perangkat');
    await expect(tv.getByText('Realtime terhubung',{exact:false})).toBeVisible(); report.rotation = true;
    await button(tv,'Ganti perangkat'); await expect(tv.getByText('Aktivasi Public Display',{exact:true})).toBeVisible();
    assert.ok(!(await tvContext.cookies(api)).some(c=>c.name==='queueb_display'));
    assert.equal(errors.length,0); report.realtime={ready,updates}; report.browser=await browser.version();
    fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2)+'\n');
    console.log('Display pairing browser PASS: '+JSON.stringify(report));
  } catch(e) {
    let msg=e.message; for(const secret of secrets.filter(Boolean)) msg=msg.replaceAll(secret,'[redacted]');
    console.error(msg);
    // Never dump semantics/screenshots here: an activation code may be visible.
    throw new Error('Display pairing browser QA failed: '+msg);
  } finally {for(const c of contexts)await c.close();await browser.close();}
};
