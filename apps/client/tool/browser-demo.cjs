/** Full demo through the compiled Flutter UI. No REST stubs or queue clock changes. */
const {chromium, expect: baseExpect} = require('@playwright/test');
const expect = baseExpect.configure({timeout:25000});
const fs = require('node:fs');
const path = require('node:path');
const QRCode = require('qrcode');
const base = 'http://127.0.0.1:8080/';
const escape = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const localMinute = value => new Date(value.getTime() + 7 * 3600000).toISOString().slice(0,16);

async function reveal(page, locator, reset=false) {
  if (!reset && await locator.count()) return;
  const size=page.viewportSize();
  await page.mouse.move(size.width*0.75,size.height*0.65);
  await page.mouse.wheel(0,-6000); await page.waitForTimeout(100);
  for(let step=0;step<10;step++) {
    if(await locator.count()) return;
    await page.mouse.wheel(0,400); await page.waitForTimeout(120);
  }
}

async function enter(page, name, value) {
  await page.bringToFront();
  const input = page.getByRole('textbox', {name:new RegExp(escape(name)),includeHidden:true});
  await reveal(page,input);
  await input.click(); await input.press('ControlOrMeta+A'); await input.press('Backspace');
  await input.pressSequentially(value, {delay:6});
  await expect.poll(async () => (await input.inputValue()) === value).toBe(true);
  await input.press('Tab');
}
async function button(page, name) { await page.bringToFront();const control=page.getByRole('button', {name, exact:true, includeHidden:true}).first();await reveal(page,control,['Masuk Antrean','Antre Ulang'].includes(name));await control.click(); }
async function choose(page, label, option) {
  const scope = await page.getByRole('dialog').count() ? page.getByRole('dialog') : page;
  const name = new RegExp('^' + escape(label) + '(?:\\s|$)');
  const control=(label === 'Dokter' ? scope.getByRole('button', {name:label,exact:true}).or(scope.getByRole('combobox', {name})) : scope.getByRole('button', {name}).or(scope.getByRole('combobox', {name}))).first();
  await reveal(page,control); await control.click();
  const choice = new RegExp(escape(option));
  await page.getByRole('menuitem', {name:choice}).or(page.getByRole('option', {name:choice})).or(page.getByText(option, {exact:false})).last().click();
}
async function mutation(page, method, route, action) {
  const response = page.waitForResponse(res => res.request().method() === method && new URL(res.url()).pathname === '/api/v1' + route, {timeout:30000});
  response.catch(()=>{}); // Action failures must not leave an unhandled waiter that interrupts fixture cleanup.
  await action(); const result = await response;
  if (!result.ok()) throw new Error(`UI ${method} ${route}: HTTP ${result.status()} ${JSON.stringify(await result.json())}`);
  return result.json();
}
async function nav(page, title) {
  await page.bringToFront();
  await expect(page.getByRole('button', {name:'Tambah', exact:true})).toBeEnabled();
  await page.waitForTimeout(150); // Wait for Flutter's enabled semantic tree after catalog refresh.
  const name=new RegExp('^'+escape(title)+'(?:\\s|$)');
  const item=page.getByRole('tab', {name}).or(page.getByRole('button', {name}));
  if(!await item.count()) {
    const category=['Poliklinik','Dokter','Ruang & loket'].includes(title)?'Master data':title==='Penugasan petugas'?'Manajemen petugas':'Manajemen jadwal';
    await page.getByRole('button',{name:new RegExp('^'+escape(category)+'(?:\\s|$)')}).click();
  }
  await item.click();
  await expect(page.getByRole('button', {name:'Tambah', exact:true})).toBeEnabled();
}
function card(page, title) { return page.getByRole('group', {name: new RegExp('^' + escape(title) + '(?:\\s|$)')}).first(); }
async function save(page, method, route, record=()=>{}) {
  const result = await mutation(page, method, route, () => button(page, 'Simpan'));
  record(result);
  await expect(page.getByRole('dialog')).toHaveCount(0);
  await expect(page.getByRole('button', {name:'Tambah', exact:true})).toBeEnabled();
  return result;
}
function cameraVideo(payload, target) {
  const modules = QRCode.create(payload, {errorCorrectionLevel:'M'}).modules;
  const width=640, height=480, scale=8, left=Math.floor((width-modules.size*scale)/2), top=Math.floor((height-modules.size*scale)/2);
  const y=Buffer.alloc(width*height,235), uv=Buffer.alloc(width*height/2,128);
  for (let row=0;row<modules.size;row++) for (let col=0;col<modules.size;col++) {
    if (modules.data[row*modules.size+col]) for (let dy=0;dy<scale;dy++) y.fill(16,(top+row*scale+dy)*width+left+col*scale,(top+row*scale+dy)*width+left+(col+1)*scale);
  }
  const frame=Buffer.concat([Buffer.from('FRAME\n'),y,uv]);
  fs.writeFileSync(target, Buffer.concat([Buffer.from(`YUV4MPEG2 W${width} H${height} F5:1 Ip A1:1 C420\n`),...Array(10).fill(frame)]));
}

module.exports = async function demo({fixture:f, root}) {
  const browsers=[], contexts=[], qrSecrets=[]; let current, publicPage;
  const videoFile=path.join(root, `camera-${f.unique}.y4m`);
  const report={admin:false,appointment:false,walkIn:false,queue:false,display:false,cameraDecode:false,cameraDenied:false,physicalCamera:null,tts:null,ttsLogic:null};
  const errors=[];
  const watchdog=setTimeout(()=>{for(const b of browsers)b.close().catch(()=>{});},7*60*1000);watchdog.unref();
  async function browser(args=[]) { const b=await chromium.launch({channel:process.env.FLUTTER_BROWSER_CHANNEL||'msedge',headless:true,args}); browsers.push(b);return b; }
  async function pageIn(b, account, viewport={width:1440,height:1100}, init) {
    const context=await b.newContext({viewport});contexts.push(context);if(init)await context.addInitScript(init);const page=await context.newPage();current=page;
    page.on('pageerror',error=>errors.push(error.message)); await page.goto(base);
    if(account === 'patient1') {await expect(page.getByRole('textbox',{name:'Email',exact:true})).toBeVisible();await page.screenshot({path:path.join(root,'mobile-01-login.png')});}
    if(account) {await enter(page,'Email',f[account].email); await enter(page,'Kata sandi',f[account].password); await button(page,'Masuk'); await expect(page.getByRole('button',{name:'Profil akun',exact:true})).toBeVisible();}
    if(account === 'patient1') {await expect(page.getByRole('progressbar')).toHaveCount(0);await page.screenshot({path:path.join(root,'mobile-02-beranda.png')});}
    return page;
  }
  try {
    const b=await browser(); const admin=await pageIn(b,'admin');
    // Only the owned fixture is edited; pre-existing rows are never selected.
    f.serviceName='Poli Demo Flutter '+f.unique;
    await card(admin,'Poli Fixture Flutter').getByRole('button',{name:'Ubah',exact:true,includeHidden:true}).click();
    await enter(admin,'Nama',f.serviceName); await save(admin,'PATCH',`/layanan/${f.serviceId}`);
    await nav(admin,'Dokter'); await button(admin,'Tambah');
    const doctorName='Dokter Demo '+f.unique;
    await enter(admin,'Kode','DD'+f.unique); await enter(admin,'Nama',doctorName); await enter(admin,'Spesialisasi','Umum');
    const doctor=await save(admin,'POST','/dokter',value=>f.extraDoctorIds.push(value.id));f.doctorId=doctor.id;
    await card(admin,doctorName).getByRole('button',{name:'Hubungkan poliklinik',exact:true,includeHidden:true}).click();
    await choose(admin,'Poliklinik untuk dihubungkan',f.serviceName);
    await mutation(admin,'POST',`/dokter/${doctor.id}/layanan`,()=>button(admin,'Hubungkan')); await button(admin,'Tutup');
    await nav(admin,'Ruang & loket'); await button(admin,'Tambah');
    await choose(admin,'Poliklinik',f.serviceName); await enter(admin,'Kode','RD'+f.unique); await enter(admin,'Nama','Ruang Demo '+f.unique);
    const room=await save(admin,'POST','/loket'); f.roomId=room.id;
    await nav(admin,'Jadwal praktik'); await button(admin,'Tambah');
    await choose(admin,'Dokter & poliklinik',doctorName); await choose(admin,'Ruang / loket','Ruang Demo '+f.unique);
    await enter(admin,'Tanggal pelayanan (YYYY-MM-DD)',f.date); await enter(admin,'Mulai (YYYY-MM-DDTHH:mm)',f.date+'T00:00'); await enter(admin,'Selesai (YYYY-MM-DDTHH:mm)',f.date+'T23:59');
    const session=await save(admin,'POST','/jadwal-praktik');f.scheduleId=session.id;
    await nav(admin,'Slot konsultasi'); await button(admin,'Tambah');
    await choose(admin,'Sesi praktik',doctorName);
    const slotStart=new Date(Math.ceil(Date.now()/60000)*60000+2*60000); f.slotStart=slotStart.toISOString();
    await enter(admin,'Mulai (YYYY-MM-DDTHH:mm)',localMinute(slotStart)); await enter(admin,'Selesai (YYYY-MM-DDTHH:mm)',localMinute(new Date(slotStart.getTime()+15*60000))); await enter(admin,'Kapasitas slot','2');
    const slot=await save(admin,'POST','/slot-praktik');f.slotId=slot.id;
    await nav(admin,'Penugasan petugas');
    const assignmentClinic=admin.getByRole('button',{name:new RegExp('^'+escape(f.serviceName)+'(?:\\s|$)')});
    await reveal(admin,assignmentClinic);if(await assignmentClinic.count())await assignmentClinic.click();
    await card(admin,'Fixture Flutter petugas').getByRole('button',{name:'Ubah',exact:true,includeHidden:true}).click();
    await choose(admin,'Ruang / loket','Ruang Demo '+f.unique);
    await mutation(admin,'PATCH',`/penugasan-petugas/${f.assignmentId}`,()=>button(admin,'Simpan')); await expect(admin.getByRole('dialog')).toHaveCount(0);
    report.admin=true;console.log('Demo UI ADMIN: PASS (poli/dokter/relasi/ruang/jadwal/slot/penugasan)');

    const walk=await pageIn(b,'patient1',{width:390,height:1000});
    await walk.getByRole('tab',{name:'Pendaftaran',exact:true}).click();
    await choose(walk,'Poliklinik',f.serviceName); await walk.getByRole('button',{name:'Walk-in',exact:true}).last().click();
    await button(walk,'Reservasi walk-in'); const walkTicket=await mutation(walk,'POST','/reservasi',()=>button(walk,'Lanjutkan'));
    await button(walk,'Lihat tiket / QR'); const walkQR=await mutation(walk,'POST',`/tiket/${walkTicket.id}/qr`,()=>button(walk,'Terbitkan QR')); qrSecrets.push(walkQR.qrPayload);
    await button(walk,'Tutup'); report.walkIn=true;
    const appt=await pageIn(b,'patient2',{width:390,height:1000});
    await appt.getByRole('tab',{name:'Pendaftaran',exact:true}).click();
    await choose(appt,'Poliklinik',f.serviceName); await appt.screenshot({path:path.join(root,'mobile-03-poliklinik.png')}); await button(appt,'Lihat Jadwal'); await button(appt,'Lihat slot');
    await appt.getByRole('button', {name:/Sisa slot 2/}).click();
    await appt.screenshot({path:path.join(root,'mobile-04-booking.png')});
    await button(appt,'Booking janji temu'); const booking=await mutation(appt,'POST','/janji-temu',()=>button(appt,'Lanjutkan'));
    await button(appt,'Lihat tiket / QR'); const apptQR=await mutation(appt,'POST',`/tiket/${booking.tiket.id}/qr`,()=>button(appt,'Terbitkan QR'));qrSecrets.push(apptQR.qrPayload); await appt.screenshot({path:path.join(root,'mobile-05-tiket.png')}); await button(appt,'Tutup');report.appointment=true;
    console.log('Demo UI USER: PASS (walk-in + appointment + dua tiket QR)');

    const display=publicPage=await pageIn(b);
    report.displaySnapshots=[];
    display.on('response',async res=>{if(new URL(res.url()).pathname===`/api/v1/display/${f.serviceId}/snapshot`){const data=await res.json().catch(()=>({}));report.displaySnapshots.push({status:res.status(),total:data.totalMenunggu});}});
    // Observe the real speech engine without replacing synthesis or success/error events.
    await display.evaluate(()=>{
      window.__qaSpeech=[]; const speak=window.speechSynthesis.speak.bind(window.speechSynthesis);
      window.speechSynthesis.speak=utterance=>{const item={text:utterance.text,lang:utterance.lang,voiceLang:utterance.voice?.lang,events:[]};window.__qaSpeech.push(item);for(const name of ['start','end','error'])utterance.addEventListener(name,e=>item.events.push(e.error||name));speak(utterance);};
    });
    await button(display,'Buka Public Display'); await enter(display,'ID layanan',f.serviceId); await enter(display,'Token perangkat',f.displayToken);await button(display,'Hubungkan display');
    await expect(display.getByText('Realtime terhubung',{exact:false})).toBeVisible(); await button(display,'Aktifkan suara');
    const voices=await display.evaluate(()=>window.speechSynthesis.getVoices().map(v=>v.lang));
    report.tts={voices,requests:await display.evaluate(()=>window.__qaSpeech),audioEnabled:await display.getByRole('button',{name:'Matikan suara',exact:true}).count()===1};
    // A separate page verifies dispatch/dedup independent of installed voices.
    // The first display above retains the real native engine and its actual errors.
    const soundLogic=await pageIn(b,null,{width:1440,height:1100},()=>{
      window.__qaSpeech=[];let timer;
      const NativeUtterance=window.SpeechSynthesisUtterance;
      window.SpeechSynthesisUtterance=class extends NativeUtterance {get voice(){return this.qaVoice||null;}set voice(value){this.qaVoice=value;}};
      speechSynthesis.getVoices=()=>[{lang:'id-ID',name:'QA controlled voice',voiceURI:'qa-id',localService:true,default:true}];
      speechSynthesis.cancel=()=>clearTimeout(timer);
      speechSynthesis.speak=u=>{window.__qaSpeech.push({text:u.text,lang:u.lang,voiceLang:u.voice?.lang});u.dispatchEvent(new Event('start'));timer=setTimeout(()=>u.dispatchEvent(new Event('end')),30);};
    });
    await button(soundLogic,'Buka Public Display');await enter(soundLogic,'ID layanan',f.serviceId);await enter(soundLogic,'Token perangkat',f.displayToken);await button(soundLogic,'Hubungkan display');
    await expect(soundLogic.getByText('Realtime terhubung',{exact:false})).toBeVisible();await button(soundLogic,'Aktifkan suara');await expect(soundLogic.getByRole('button',{name:'Matikan suara',exact:true})).toBeVisible();

    // Open and stop the real laptop camera without storing any frames/photos.
    const hardware=await b.newContext({permissions:['camera']});contexts.push(hardware); const hardwarePage=await hardware.newPage(); await hardwarePage.goto(base);
    report.physicalCamera=await hardwarePage.evaluate(async()=>Promise.race([(async()=>{try{const stream=await navigator.mediaDevices.getUserMedia({video:true,audio:false}); const track=stream.getVideoTracks()[0];const info={opened:track.readyState==='live',width:track.getSettings().width,height:track.getSettings().height}; stream.getTracks().forEach(t=>t.stop());return info;}catch(e){return {opened:false,error:e.name};}})(),new Promise(resolve=>setTimeout(()=>resolve({opened:false,error:'CameraProbeTimeout'}),10000))]));await hardware.close();

    cameraVideo(walkQR.qrPayload,videoFile);
    const cameraBrowser=await browser(['--use-fake-device-for-media-stream',`--use-file-for-fake-video-capture=${videoFile}`]);
    const staff=await pageIn(cameraBrowser,'petugas',{width:390,height:1000}); await staff.context().grantPermissions(['camera']);
    await expect(staff.getByText('Realtime terhubung',{exact:false})).toBeVisible();
    await button(staff,'Pindai kamera');
    // The action waits for the scanner overlay to close. Backend identity proves the decoded QR.
    const checked=await mutation(staff,'POST','/check-in',()=>button(staff,'Check-In'));
    expect(checked.tiketId).toBe(walkTicket.id); report.cameraDecode=true;
    await mutation(staff,'POST',`/queue/${walkTicket.id}/masuk`,()=>button(staff,'Masuk Antrean'));
    await enter(staff,'Payload QR (SQ1…)',apptQR.qrPayload);await mutation(staff,'POST','/check-in',()=>button(staff,'Check-In'));
    await mutation(staff,'POST',`/queue/${booking.tiket.id}/masuk`,()=>button(staff,'Masuk Antrean'));
    await display.bringToFront();await expect(display.getByText('Menunggu: 2',{exact:false}).or(display.getByRole('group',{name:/Menunggu: 2/})).first()).toBeVisible({timeout:20000});
    const wait=new Date(f.slotStart).getTime()-Date.now();if(wait>0){console.log(`Demo menunggu awal slot sah: ${Math.ceil(wait/1000)} detik`);await new Promise(resolve=>setTimeout(resolve,wait+500));}
    let called=await mutation(staff,'POST','/queue/panggil',()=>button(staff,'Panggil berikutnya'));expect(called.tiketId).toBe(booking.tiket.id);
    await staff.screenshot({path:path.join(root,'mobile-06-petugas.png')});
    await display.bringToFront();await expect(display.getByText(booking.nomorAntrean,{exact:true}).or(display.getByRole('group',{name:new RegExp(escape(booking.nomorAntrean))})).first()).toBeVisible({timeout:20000});
    await expect.poll(()=>soundLogic.evaluate(()=>window.__qaSpeech.length),{timeout:10000}).toBe(2);
    await mutation(staff,'POST',`/queue/${called.tiketId}/panggil-ulang`,()=>button(staff,'Panggil Ulang'));
    await expect.poll(()=>soundLogic.evaluate(()=>window.__qaSpeech.length),{timeout:10000}).toBe(3);
    await button(soundLogic,'Muat ulang');await soundLogic.waitForTimeout(500);expect(await soundLogic.evaluate(()=>window.__qaSpeech.length)).toBe(3);
    await mutation(staff,'POST',`/queue/${called.tiketId}/lewati`,()=>button(staff,'Lewati'));
    await mutation(staff,'POST',`/queue/${called.tiketId}/antre-ulang`,()=>button(staff,'Antre Ulang'));
    called=await mutation(staff,'POST','/queue/panggil',()=>button(staff,'Panggil berikutnya'));expect(called.tiketId).toBe(booking.tiket.id);
    await expect.poll(()=>soundLogic.evaluate(()=>window.__qaSpeech.length),{timeout:10000}).toBe(4);
    for(const id of [booking.tiket.id,walkTicket.id]){
      if(id===walkTicket.id){called=await mutation(staff,'POST','/queue/panggil',()=>button(staff,'Panggil berikutnya'));expect(called.tiketId).toBe(id);await expect.poll(()=>soundLogic.evaluate(()=>window.__qaSpeech.length),{timeout:10000}).toBe(5);}
      await mutation(staff,'POST',`/queue/${id}/mulai-pelayanan`,()=>button(staff,'Mulai Pelayanan'));
      await mutation(staff,'POST',`/queue/${id}/selesaikan-pelayanan`,()=>button(staff,'Selesaikan Pelayanan'));
    }
    report.queue=true;await display.bringToFront();await expect(display.getByText('Menunggu: 0',{exact:false}).or(display.getByRole('group',{name:/Menunggu: 0/})).first()).toBeVisible();report.display=true;
    console.log('Demo UI PETUGAS + DISPLAY: PASS (seluruh aksi antrean, dua tiket SELESAI, snapshot realtime)');
    await button(walk,'Muat ulang tiket');await expect(walk.getByRole('checkbox',{name:'SELESAI',exact:true,includeHidden:true})).toBeVisible();await button(appt,'Muat ulang tiket');await expect(appt.getByRole('checkbox',{name:'SELESAI',exact:true,includeHidden:true})).toBeVisible();
    // Reconnect snapshot cannot replay historical announcements.
    const speechBefore=await soundLogic.evaluate(()=>window.__qaSpeech.length);await button(soundLogic,'Muat ulang');await soundLogic.waitForTimeout(500);expect(await soundLogic.evaluate(()=>window.__qaSpeech.length)).toBe(speechBefore);
    report.ttsLogic={requests:await soundLogic.evaluate(()=>window.__qaSpeech),deduplicated:true,engine:'controlled Web Speech test double, not audible synthesis'};
    report.tts={voices,requests:await display.evaluate(()=>window.__qaSpeech),audioEnabled:await display.getByRole('button',{name:'Matikan suara',exact:true}).count()===1};
    const denied=await pageIn(b);await denied.context().clearPermissions();
    await denied.context().addInitScript(()=>{navigator.mediaDevices.getUserMedia=()=>Promise.reject(new DOMException('QA camera denied','NotAllowedError'));});await denied.reload();
    await enter(denied,'Email',f.petugas.email);await enter(denied,'Kata sandi',f.petugas.password);await button(denied,'Masuk');await button(denied,'Pindai kamera');await expect(denied.getByText('Kamera tidak tersedia atau izin ditolak. Tutup lalu tempel payload QR.',{exact:true}).or(denied.locator('[aria-label*="Kamera tidak tersedia"]')).first()).toBeVisible();await button(denied,'Tutup');report.cameraDenied=true;
    for(const [name,page]of[['admin',admin],['patient',walk],['staff',staff],['display',display]]) await page.screenshot({path:path.join(root,`demo-${name}.png`),fullPage:true});
    if(errors.length)throw new Error('Browser runtime: '+errors[0]);
    fs.writeFileSync(path.join(root,'demo-result.json'),JSON.stringify(report,null,2)); console.log('Demo browser final: '+JSON.stringify(report));
  }catch(error){
    fs.writeFileSync(path.join(root,'demo-result.json'),JSON.stringify(report,null,2));
    let message=error.message; for(const secret of [f.displayToken,...qrSecrets,...['admin','petugas','patient1','patient2'].map(k=>f[k].password)]) message=message.replaceAll(secret,'[redacted]'); console.error(message);
    if(current&&!current.isClosed()){console.error('QA controls: '+JSON.stringify(await current.locator('flt-semantics[aria-label]').evaluateAll(nodes=>nodes.map(n=>({role:n.getAttribute('role'),label:n.getAttribute('aria-label')})).filter(n=>!n.label.includes('SQ1.')&&!/[a-f0-9]{64}/i.test(n.label)))));await current.screenshot({path:path.join(root,'demo-failure.png'),fullPage:true});}
    if(publicPage&&!publicPage.isClosed()){await publicPage.bringToFront();await publicPage.screenshot({path:path.join(root,'demo-display-failure.png'),fullPage:true});console.error('QA display snapshot statuses: '+JSON.stringify(report.displaySnapshots?.slice(-6)));}
    throw new Error('Demo browser gagal; lihat diagnostik QA teredaksi.');
  }finally{clearTimeout(watchdog);for(const c of contexts)await c.close().catch(()=>{});for(const b of browsers)await b.close();if(fs.existsSync(videoFile))fs.unlinkSync(videoFile);}
};
module.exports.helpers={enter,button,choose,mutation,nav,card,reveal};
