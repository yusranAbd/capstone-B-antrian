/** Real Flutter + NestJS + /queue; data owned by run-live's isolated fixture. */
const {chromium, expect: baseExpect} = require('@playwright/test');
const expect = baseExpect.configure({timeout:25000});
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
const {enter, button, mutation, cameraVideo} = require('./browser-demo.cjs').helpers;

module.exports = async function staffV3({fixture:f, root}) {
  const output = path.resolve(__dirname, '../../../docs/frontend/images/staff-v3');
  fs.mkdirSync(output, {recursive:true});
  const video = path.join(root, `staff-camera-${f.unique}.y4m`);
  const report = {database:'127.0.0.1:5433/capstone_antrean_test', widths:[], queueEvents:0, reconnect:false};
  let browser, page;
  const errors = [];
  async function api(route, token, body, method='POST') {
    let r;
    try { r = await fetch('http://127.0.0.1:3001/api/v1'+route, {
      method, headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},
      ...(body===undefined?{}:{body:JSON.stringify(body)}),
    }); } catch(error) { throw new Error(`QA network ${method} ${route}: ${error.cause?.code || error.name}`); }
    assert.ok(r.ok, `QA ${method} ${route}: HTTP ${r.status}`);
    return r.json();
  }
  async function semantic(text) {
    await expect.poll(() => page.locator('[aria-label], flt-semantics').evaluateAll(
      (nodes,target) => nodes.some(n => (n.getAttribute('aria-label')||n.textContent||'').includes(target)),text)).toBe(true);
  }
  async function capture(name, width=1366, height=768) {
    await page.setViewportSize({width,height});
    await page.mouse.move(5,5); await page.waitForTimeout(350);
    await page.screenshot({path:path.join(output,name+'.png')});
    report.widths.push(`${width}x${height}`);
  }
  async function login() {
    await enter(page,'Email',f.petugas.email);
    await enter(page,'Kata sandi',f.petugas.password);
    await mutation(page,'POST','/auth/login',()=>button(page,'Masuk'));
    await expect(page.getByRole('button',{name:'Pindai kamera',exact:true})).toBeVisible();
  }
  try {
    if(f.staffBefore) {
      browser=await chromium.launch({channel:'msedge',headless:true});
      page=await browser.newPage({viewport:{width:1366,height:768}});
      await page.goto('http://127.0.0.1:8080/'); await login();
      await capture('00-sebelum-1366'); return;
    }
    const patient = await api('/auth/login',null,{email:f.patient1.email,kataSandi:f.patient1.password});
    const walk = await api('/reservasi',patient.accessToken,{layananId:f.serviceId,tanggalAntrean:f.date});
    const walkQR = await api(`/tiket/${walk.id}/qr`,patient.accessToken,{});
    const patient2 = await api('/auth/login',null,{email:f.patient2.email,kataSandi:f.patient2.password});
    const booking = await api('/janji-temu',patient2.accessToken,{slotPraktikId:f.slotId});
    const appointmentQR = await api(`/tiket/${booking.tiket.id}/qr`,patient2.accessToken,{});
    const staffSession = await api('/auth/login',null,{email:f.petugas.email,kataSandi:f.petugas.password});
    cameraVideo(walkQR.qrPayload, video);
    browser = await chromium.launch({channel:'msedge',headless:true,
      args:['--use-fake-device-for-media-stream',`--use-file-for-fake-video-capture=${video}`]});
    const context = await browser.newContext({viewport:{width:1366,height:768},permissions:['camera']});
    page = await context.newPage();
    page.on('pageerror',e=>errors.push(e.message));
    page.on('websocket',ws=>ws.on('framereceived',frame=>{
      if(typeof frame.payload==='string' && frame.payload.includes('queue:updated')) report.queueEvents++;
    }));
    await page.goto('http://127.0.0.1:8080/'); await login();
    await semantic('Realtime terhubung');
    const roomLabel=f.roomName+' · Poli Fixture Flutter';
    await page.getByRole('button',{name:new RegExp(f.roomName)}).or(page.getByText(roomLabel,{exact:true})).last().click();
    await page.getByRole('menuitem',{name:new RegExp(f.roomName)}).or(page.getByRole('option',{name:new RegExp(f.roomName)})).or(page.locator('[aria-label]').filter({hasText:roomLabel})).or(page.getByText(roomLabel,{exact:true})).last().click();
    await semantic('Realtime terhubung');
    await capture('01-dashboard-1366');
    await capture('02-dashboard-1440',1440,900);
    await capture('03-dashboard-1920',1920,1080);
    await page.setViewportSize({width:1366,height:768});
    console.log('PETUGAS: room selection and empty viewport PASS');
    await button(page,'Pindai kamera');
    await expect(page.getByRole('button',{name:'Tutup',exact:true})).toHaveCount(0);
    const checked = await mutation(page,'POST','/check-in',()=>button(page,'Check-In'));
    assert.equal(checked.tiketId,walk.id);
    await capture('04-check-in');
    await mutation(page,'POST',`/queue/${walk.id}/masuk`,()=>button(page,'Masuk Antrean'));
    await enter(page,'Payload QR (SQ1…)',appointmentQR.qrPayload);
    await mutation(page,'POST','/check-in',()=>button(page,'Check-In'));
    await mutation(page,'POST',`/queue/${booking.tiket.id}/masuk`,()=>button(page,'Masuk Antrean'));
    assert.equal(typeof booking.nomorAntrean,'string');
    await enter(page,'Cari nomor antrean',booking.nomorAntrean);
    await semantic('Appointment');
    await enter(page,'Cari nomor antrean','');
    console.log('PETUGAS: camera decode, walk-in + appointment Check-In/ENQUEUE PASS');
    // Respect the actual slot clock and selector, without a QA bypass.
    while(Date.now()<new Date(f.slotStart).getTime()+500)
      await page.waitForTimeout(Math.min(15000,new Date(f.slotStart).getTime()+500-Date.now()));
    let called=await mutation(page,'POST','/queue/panggil',()=>button(page,'Panggil berikutnya'));
    assert.equal(called.tiketId,booking.tiket.id);
    await expect(page.getByRole('button',{name:'Mulai Pelayanan',exact:true})).toBeVisible();
    await capture('05-antrean-aktif');
    // An external authorized recall must refresh the UI without a UI mutation.
    const externalRefresh = page.waitForResponse(r=>new URL(r.url()).pathname==='/api/v1/queue/snapshot' && r.ok());
    await api(`/queue/${called.tiketId}/panggil-ulang`,staffSession.accessToken,{loketId:f.roomId});
    await externalRefresh;
    report.externalEventRefresh=true;
    await mutation(page,'POST',`/queue/${called.tiketId}/panggil-ulang`,()=>button(page,'Panggil Ulang'));
    await mutation(page,'POST',`/queue/${called.tiketId}/lewati`,()=>button(page,'Lewati'));
    await page.reload(); // Temporary receipts deliberately do not survive reload.
    await login(); // Web intentionally keeps bearer credentials in memory only.
    await semantic('Realtime terhubung');
    await button(page,'Pemulihan ID tiket');
    await enter(page,'ID tiket untuk masuk / antre ulang',called.tiketId);
    await mutation(page,'POST',`/queue/${called.tiketId}/antre-ulang`,()=>button(page,'Antre Ulang'));
    await button(page,'Pemulihan ID tiket');
    called=await mutation(page,'POST','/queue/panggil',()=>button(page,'Panggil berikutnya'));
    assert.equal(called.tiketId,booking.tiket.id);
    for(const id of [booking.tiket.id,walk.id]) {
      if(id===walk.id) {
        called=await mutation(page,'POST','/queue/panggil',()=>button(page,'Panggil berikutnya'));
        assert.equal(called.tiketId,id);
      }
      await mutation(page,'POST',`/queue/${id}/mulai-pelayanan`,()=>button(page,'Mulai Pelayanan'));
      await mutation(page,'POST',`/queue/${id}/selesaikan-pelayanan`,()=>button(page,'Selesaikan Pelayanan'));
    }
    assert.ok(report.queueEvents>=8,'Socket events must drive REST refresh');
    let snapshotReads=0;
    page.on('response',r=>{if(new URL(r.url()).pathname==='/api/v1/queue/snapshot' && r.ok()) snapshotReads++;});
    f.disconnectStaff();
    await semantic('Realtime terputus');
    await semantic('Realtime terhubung');
    await expect.poll(()=>snapshotReads).toBeGreaterThan(0);
    report.reconnect=true;
    const snapshot = await api(`/queue/snapshot?loketId=${f.roomId}`,staffSession.accessToken,undefined,'GET');
    assert.equal(snapshot.menunggu.total,0);
    for(const [account,id] of [[patient,walk.id],[patient2,booking.tiket.id]])
      assert.equal((await api(`/tiket/${id}`,account.accessToken,undefined,'GET')).status,'SELESAI');
    await semantic('Belum ada pasien menunggu.');
    await expect(page.getByRole('button',{name:'Panggil berikutnya',exact:true})).toBeEnabled();
    await capture('06-selesai-kosong');
    for(const width of [320,375,414,768]) {
      await page.setViewportSize({width,height:900});
      await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
    }
    report.narrowWidths=[320,375,414,768];
    await capture('07-tablet',768,1024);
    await context.addInitScript(()=>{navigator.mediaDevices.getUserMedia=()=>Promise.reject(new DOMException('QA denied','NotAllowedError'));});
    await page.reload();
    await login();
    await button(page,'Pindai kamera');
    await semantic('Kamera tidak tersedia atau izin ditolak.');
    await button(page,'Tutup');
    await button(page,'Keluar akun');
    await expect(page.getByRole('button',{name:'Masuk',exact:true})).toBeVisible();
    assert.deepEqual(errors,[]);
    Object.assign(report,{cameraDecode:true,cameraDenied:true,appointment:true,walkIn:true,
      call:true,recall:true,skip:true,requeueRecovery:true,start:true,complete:true,logout:true,runtimeErrors:0});
    fs.writeFileSync(path.join(root,'qa-staff-v3.json'),JSON.stringify(report,null,2));
    console.log('PETUGAS V3: '+JSON.stringify(report));
  } catch(error) {
    if(page && !page.isClosed()) {
      await page.screenshot({path:path.join(root,'staff-v3-failure.png')}).catch(()=>{});
      console.error('QA labels: '+JSON.stringify(await page.locator('[aria-label]').evaluateAll(nodes=>nodes.map(n=>n.getAttribute('aria-label')).filter(s=>s&&!s.includes('SQ1.')&&!s.includes('@test.local')))));
    }
    console.error('PETUGAS QA: '+error.message.replace(/SQ1\.[\w.-]+/g,'[QR redacted]'));
    throw new Error('Portal PETUGAS QA gagal; lihat diagnostik teredaksi.');
  } finally {await browser?.close(); if(fs.existsSync(video))fs.unlinkSync(video);}
};
