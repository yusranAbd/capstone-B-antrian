/** Two independent compiled Flutter clients, real API and uniquely owned test fixtures. */
const {chromium, expect: baseExpect} = require('@playwright/test');
const expect = baseExpect.configure({timeout:20000});
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {io} = require('../../api/node_modules/socket.io-client');
const {enter, button, choose, mutation, nav, reveal} = require('./browser-demo.cjs').helpers;
const apiBase='http://127.0.0.1:3001/api/v1';
const escape=value=>value.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
const localMinute=value=>new Date(value.getTime()+7*3600000).toISOString().slice(0,16);
const card=(page,title)=>page.getByRole('group',{name:new RegExp('^'+escape(title)+'(?:\\s|$)')}).first();

module.exports=async function realtimeAdmin({fixture:f,root}) {
  const browsers=[],contexts=[],secrets=[f.displayToken,...['admin','petugas','patient1','patient2'].map(k=>f[k].password)];
  const errors=[], report={transitions:[],catalog:[],isolation:false,reconnect:false,resume:false,admin:[]};
  let current,observer;
  const watchdog=setTimeout(()=>browsers.forEach(b=>b.close().catch(()=>{})),15*60000);watchdog.unref();
  async function browser(){const b=await chromium.launch({channel:process.env.FLUTTER_BROWSER_CHANNEL||'msedge',headless:true});browsers.push(b);return b;}
  async function login(b,key,viewport={width:1440,height:1100}){
    const context=await b.newContext({viewport});contexts.push(context);const page=await context.newPage();current=page;
    const obs=observe(page);page.on('pageerror',e=>errors.push(e.message));await page.goto('http://127.0.0.1:8080/');
    await enter(page,'Email',f[key].email);await enter(page,'Kata sandi',f[key].password);
    const value=await mutation(page,'POST','/auth/login',()=>button(page,'Masuk'));secrets.push(value.accessToken,value.refreshToken);
    await expect(page.getByRole('button',{name:'Profil akun',exact:true})).toBeVisible();
    return {page,context,token:value.accessToken,obs};
  }
  async function request(token,method,route,body,status=200){
    const r=await fetch(apiBase+route,{method,headers:{'Content-Type':'application/json',Authorization:`Bearer ${token}`},...(body?{body:JSON.stringify(body)}:{})});
    assert.equal(r.status,status,`${method} ${route}`);return r.json();
  }
  async function expand(page,title){
    await page.bringToFront();const b=page.getByRole('button',{name:new RegExp('^'+escape(title)+'(?:\\s|$)')}).first();
    await reveal(page,b);if(await b.count())await b.click();
  }
  async function save(page,method,route){
    const r=await mutation(page,method,route,()=>button(page,'Simpan'));
    await expect(page.getByRole('alertdialog')).toHaveCount(0);
    await expect(page.getByRole('button',{name:'Tambah',exact:true})).toBeEnabled();return r;
  }
  function observe(page){
    const events=[],reads=[],ready=[];
    page.on('websocket',socket=>socket.on('framereceived',({payload})=>{
      const s=String(payload);if(s.includes('patient:ready'))ready.push(Date.now());
      if(s.includes('patient:updated'))events.push({at:Date.now(),kind:s.includes('KATALOG')?'KATALOG':'TIKET'});
    }));
    page.on('response',async r=>{if(r.request().method()==='GET' && /\/api\/v1\/tiket\/[^/]+$/.test(new URL(r.url()).pathname)){
      const value=await r.json().catch(()=>({}));reads.push({at:Date.now(),status:value.status,id:value.id});
    }});
    return {events,reads,ready};
  }
  async function status(page,obs,ticket,status,action,label=status){
    current=page;const start=Date.now(),count=obs.events.length;await action();await page.bringToFront();
    await expect.poll(()=>obs.reads.filter(r=>r.at>=start&&r.id===ticket&&r.status===status).length,{timeout:15000}).toBeGreaterThan(0);
    await expect(page.getByRole('checkbox',{name:status.replaceAll('_',' '),exact:true,includeHidden:true}).last()).toBeVisible();
    assert.ok(obs.events.length>count || obs.ready.some(t=>t>=start),'Socket event/ready required, not the 30-second fallback');
    report.transitions.push({action:label,status,latencyMs:Date.now()-start,manualRefresh:false});
    console.log(`USER automatic ${label} -> ${status}: PASS`);
  }
  try{
    const operatorBrowser=await browser(),patientBrowser=await browser();
    const a=await login(operatorBrowser,'admin');const admin=a.page;
    let start;
    if(!f.adminLayoutOnly){
    const pc=await patientBrowser.newContext({viewport:{width:390,height:1000}});contexts.push(pc);
    // Chromium's offline switch alone can leave an established WebSocket alive.
    // Close the native transport as a network interruption, without touching app state.
    await pc.addInitScript(()=>{const Native=window.WebSocket;window.__qaSockets=[];window.WebSocket=class extends Native{constructor(...args){super(...args);window.__qaSockets.push(this);}};});
    const patient=await pc.newPage();const obs=observe(patient);current=patient;
    await patient.goto('http://127.0.0.1:8080/');await enter(patient,'Email',f.patient1.email);await enter(patient,'Kata sandi',f.patient1.password);await button(patient,'Masuk');
    await expect(patient.getByText('Realtime terhubung',{exact:true})).toBeVisible();
    await patient.getByRole('tab',{name:'Pendaftaran',exact:true}).click();
    f.serviceName='Poli Fixture Flutter Realtime '+f.unique;
    await card(admin,'Poli Fixture Flutter').getByRole('button',{name:'Ubah',exact:true}).click();
    await enter(admin,'Nama',f.serviceName);await save(admin,'PATCH',`/layanan/${f.serviceId}`);
    await patient.bringToFront();await expect(patient.getByText(f.serviceName,{exact:false}).first()).toBeVisible({timeout:15000});report.catalog.push('poliklinik');
    await choose(patient,'Poliklinik',f.serviceName);
    await nav(admin,'Dokter');await card(admin,'Dokter Fixture Flutter').getByRole('button',{name:'Ubah',exact:true}).click();
    f.doctorName='Dokter Fixture Flutter Realtime '+f.unique;await enter(admin,'Nama',f.doctorName);await save(admin,'PATCH',`/dokter/${f.doctorId}`);
    await patient.bringToFront();await expect(patient.getByText(f.doctorName,{exact:false}).first()).toBeVisible({timeout:15000});report.catalog.push('dokter');
    await patient.getByRole('button',{name:'Walk-in',exact:true}).last().click();await button(patient,'Reservasi walk-in');
    const ticket=await mutation(patient,'POST','/reservasi',()=>button(patient,'Lanjutkan'));
    await button(patient,'Lihat tiket / QR');const qr=await mutation(patient,'POST',`/tiket/${ticket.id}/qr`,()=>button(patient,'Terbitkan QR'));secrets.push(qr.qrPayload);
    const otherLogin=await request('', 'POST','/auth/login',{email:f.patient2.email,kataSandi:f.patient2.password});secrets.push(otherLogin.accessToken,otherLogin.refreshToken);
    const otherEvents=[];observer=io('http://127.0.0.1:3001/patient',{transports:['websocket'],auth:{token:otherLogin.accessToken},forceNew:true});observer.on('patient:updated',e=>otherEvents.push(e));
    await new Promise((resolve,reject)=>{observer.once('patient:ready',resolve);observer.once('connect_error',()=>reject(new Error('Observer USER2 rejected')));});
    await request(otherLogin.accessToken,'GET',`/tiket/${ticket.id}`,null,404);
    const s=await login(operatorBrowser,'petugas');const staff=s.page;
    await expect(staff.getByText('Realtime terhubung',{exact:false})).toBeVisible();
    await enter(staff,'Payload QR (SQ1…)',qr.qrPayload);
    await status(patient,obs,ticket.id,'CHECK_IN',()=>mutation(staff,'POST','/check-in',()=>button(staff,'Check-In')));
    await status(patient,obs,ticket.id,'MENUNGGU',()=>mutation(staff,'POST',`/queue/${ticket.id}/masuk`,()=>button(staff,'Masuk Antrean')),'ENQUEUE');
    await status(patient,obs,ticket.id,'DIPANGGIL',async()=>{const r=await mutation(staff,'POST','/queue/panggil',()=>button(staff,'Panggil berikutnya'));assert.equal(r.tiketId,ticket.id);},'CALL');
    await patient.screenshot({path:path.join(root,'patient-realtime-call.png')});
    await status(patient,obs,ticket.id,'DIPANGGIL',()=>mutation(staff,'POST',`/queue/${ticket.id}/panggil-ulang`,()=>button(staff,'Panggil Ulang')),'RECALL');
    const readyBefore=obs.ready.length;await pc.setOffline(true);
    await patient.evaluate(()=>window.__qaSockets.forEach(s=>s.close(4000,'QA network interruption')));
    await mutation(staff,'POST',`/queue/${ticket.id}/lewati`,()=>button(staff,'Lewati'));
    const offlineAt=Date.now();await pc.setOffline(false);await patient.bringToFront();
    await expect.poll(()=>obs.ready.length,{timeout:20000}).toBeGreaterThan(readyBefore);
    await expect.poll(()=>obs.reads.some(r=>r.at>=offlineAt&&r.status==='DILEWATI')).toBe(true);
    report.reconnect=true;report.transitions.push({action:'SKIP + offline/reconnect',status:'DILEWATI',manualRefresh:false});
    const cdp=await pc.newCDPSession(patient);await cdp.send('Page.setWebLifecycleState',{state:'frozen'});
    await mutation(staff,'POST',`/queue/${ticket.id}/antre-ulang`,()=>button(staff,'Antre Ulang'));
    const resumeAt=Date.now();await cdp.send('Page.setWebLifecycleState',{state:'active'});await patient.bringToFront();
    await expect.poll(()=>obs.reads.some(r=>r.at>=resumeAt&&r.status==='MENUNGGU')).toBe(true);report.resume=true;
    report.transitions.push({action:'REQUEUE + frozen/resume',status:'MENUNGGU',manualRefresh:false});
    await status(patient,obs,ticket.id,'DIPANGGIL',()=>mutation(staff,'POST','/queue/panggil',()=>button(staff,'Panggil berikutnya')),'CALL after REQUEUE');
    await status(patient,obs,ticket.id,'DILAYANI',()=>mutation(staff,'POST',`/queue/${ticket.id}/mulai-pelayanan`,()=>button(staff,'Mulai Pelayanan')),'START');
    await status(patient,obs,ticket.id,'SELESAI',()=>mutation(staff,'POST',`/queue/${ticket.id}/selesaikan-pelayanan`,()=>button(staff,'Selesaikan Pelayanan')),'COMPLETE');
    await patient.screenshot({path:path.join(root,'patient-realtime-complete.png')});
    assert.equal(otherEvents.filter(e=>e.jenis==='TIKET').length,0);report.isolation=true;
    await pc.close();

    // External owned HTTP writes, while a second Flutter USER is already open,
    // prove booking/cancellation updates arrive independently of button handlers.
    const p2=await login(patientBrowser,'patient2',{width:390,height:1000});const obs2=p2.obs;
    await p2.page.getByRole('tab',{name:'Tiket Saya',exact:true}).click();
    start=new Date(Math.ceil(Date.now()/60000)*60000+2*60000);
    await request(a.token,'PATCH',`/slot-praktik/${f.slotId}`,{mulaiPada:start.toISOString(),selesaiPada:new Date(start.getTime()+15*60000).toISOString()});
    const booking=await request(otherLogin.accessToken,'POST','/janji-temu',{slotPraktikId:f.slotId},201);
    await p2.page.bringToFront();await expect(p2.page.getByRole('checkbox',{name:'DIPESAN',exact:true}).first()).toBeVisible({timeout:15000});
    await button(p2.page,'Lihat tiket / QR');
    await status(p2.page,obs2,booking.tiket.id,'DIBATALKAN',()=>request(otherLogin.accessToken,'POST',`/janji-temu/${booking.id}/batalkan`,{},201),'Appointment cancellation');
    report.transitions.push({action:'External appointment booking',status:'DIPESAN',manualRefresh:false});
    await p2.context.close();observer.disconnect();observer=null;
    }else{
      f.serviceName='Poli Fixture Flutter Realtime '+f.unique;f.doctorName='Dokter Fixture Flutter Realtime '+f.unique;
      await request(a.token,'PATCH',`/layanan/${f.serviceId}`,{nama:f.serviceName});
      await request(a.token,'PATCH',`/dokter/${f.doctorId}`,{nama:f.doctorName});
      start=new Date(f.slotStart);await button(admin,'Muat ulang');
      await expect(admin.getByRole('button',{name:'Tambah',exact:true})).toBeEnabled();
    }

    current=admin;await admin.bringToFront();
    await nav(admin,'Poliklinik');await enter(admin,'Cari nama atau kode',f.serviceCode);await choose(admin,'Status data','Aktif');
    await expect(card(admin,f.serviceName)).toBeVisible();report.admin.push('Poliklinik search/status/edit');
    for(const title of ['Manajemen jadwal','Manajemen petugas'])await expand(admin,title);
    await admin.screenshot({path:path.join(root,'admin-category-navigation.png')});
    await nav(admin,'Dokter');await enter(admin,'Cari dokter atau spesialisasi',f.doctorName);await choose(admin,'Filter poliklinik',f.serviceName);await choose(admin,'Status data','Aktif');await expect(card(admin,f.doctorName)).toBeVisible();
    await button(admin,'Tambah');const extraName='Dokter Realtime Tambahan '+f.unique;
    await enter(admin,'Kode','DR'+f.unique);await enter(admin,'Nama',extraName);await enter(admin,'Spesialisasi','Umum');
    const extra=await save(admin,'POST','/dokter');f.extraDoctorIds.push(extra.id);
    await choose(admin,'Filter poliklinik','Semua poliklinik');await enter(admin,'Cari dokter atau spesialisasi',extraName);
    await card(admin,extraName).getByRole('button',{name:'Nonaktifkan',exact:true}).click();await mutation(admin,'DELETE',`/dokter/${extra.id}`,()=>button(admin,'Lanjutkan'));
    await choose(admin,'Status data','Nonaktif');await expect(card(admin,extraName)).toBeVisible();report.admin.push('Dokter search/clinic/status/create/deactivate');
    await nav(admin,'Ruang & loket');await choose(admin,'Filter poliklinik',f.serviceName);await enter(admin,'Cari nama atau kode','Ruang Fixture');await expand(admin,f.serviceName);
    await card(admin,'Ruang Fixture').getByRole('button',{name:'Ubah',exact:true}).click();await enter(admin,'Lokasi','Lantai QA realtime');await save(admin,'PATCH',`/loket/${f.roomId}`);
    await admin.screenshot({path:path.join(root,'admin-room-groups.png')});report.admin.push('Ruang grouping/search/clinic/edit');
    await nav(admin,'Jadwal praktik');await choose(admin,'Filter poliklinik',f.serviceName);await choose(admin,'Filter dokter',f.doctorName);await enter(admin,'Dari tanggal',f.date);await enter(admin,'Sampai tanggal',f.date);
    await expand(admin,f.serviceName);await expand(admin,f.doctorName);await expand(admin,f.date);
    const editPractice=admin.getByRole('button',{name:'Ubah',exact:true});await reveal(admin,editPractice);await editPractice.click();
    await enter(admin,'Selesai (YYYY-MM-DDTHH:mm)',f.date+'T23:58');
    // Existing Hospital rule: sessions with slots are immutable, including when empty.
    const conflict=admin.waitForResponse(r=>r.request().method()==='PATCH'&&new URL(r.url()).pathname===`/api/v1/jadwal-praktik/${f.scheduleId}`);
    await button(admin,'Simpan');assert.equal((await conflict).status(),409);await button(admin,'Kembali');
    await button(admin,'Tambah');await choose(admin,'Dokter & poliklinik',f.doctorName);await choose(admin,'Ruang / loket','Ruang Fixture');
    // Fixture operating hours cover today's weekday; next week uses the same valid day.
    const tomorrow=new Date(new Date(f.date+'T00:00:00Z').getTime()+7*86400000).toISOString().slice(0,10);
    await enter(admin,'Tanggal pelayanan (YYYY-MM-DD)',tomorrow);await enter(admin,'Mulai (YYYY-MM-DDTHH:mm)',tomorrow+'T00:00');await enter(admin,'Selesai (YYYY-MM-DDTHH:mm)',tomorrow+'T23:59');
    const emptySession=await save(admin,'POST','/jadwal-praktik');await enter(admin,'Sampai tanggal',tomorrow);await expand(admin,tomorrow);
    const emptyCard=card(admin,tomorrow);await emptyCard.getByRole('button',{name:'Ubah',exact:true}).click();await enter(admin,'Selesai (YYYY-MM-DDTHH:mm)',tomorrow+'T23:58');await save(admin,'PATCH',`/jadwal-praktik/${emptySession.id}`);
    await admin.screenshot({path:path.join(root,'admin-practice-groups.png')});
    await emptyCard.getByRole('button',{name:'Nonaktifkan',exact:true}).click();await mutation(admin,'DELETE',`/jadwal-praktik/${emptySession.id}`,()=>button(admin,'Lanjutkan'));
    await choose(admin,'Status data','Nonaktif');await expect(emptyCard).toBeVisible();report.admin.push('Praktik clinic/doctor/date/grouping/create/edit/deactivate + existing slot conflict 409');
    await nav(admin,'Slot konsultasi');await choose(admin,'Filter poliklinik',f.serviceName);await choose(admin,'Filter dokter',f.doctorName);await enter(admin,'Dari tanggal',f.date);await enter(admin,'Sampai tanggal',f.date);
    await expand(admin,f.serviceName);await expand(admin,f.doctorName);await expand(admin,f.date);
    await expect(admin.getByRole('button',{name:'Muat ulang slot',exact:true})).toBeVisible();
    await button(admin,'Tambah');await choose(admin,'Sesi praktik',f.date+' · '+f.doctorName);
    const newStart=new Date(start.getTime()+30*60000);
    await enter(admin,'Mulai (YYYY-MM-DDTHH:mm)',localMinute(newStart));await enter(admin,'Selesai (YYYY-MM-DDTHH:mm)',localMinute(new Date(newStart.getTime()+15*60000)));await enter(admin,'Kapasitas slot','3');
    const slot=await save(admin,'POST','/slot-praktik');
    const slotTitle=f.date+' '+localMinute(newStart).split('T')[1];
    const slotCard=card(admin,slotTitle);const slotEdit=slotCard.getByRole('button',{name:'Ubah',exact:true});await reveal(admin,slotEdit);await slotEdit.click();await enter(admin,'Kapasitas slot','4');await save(admin,'PATCH',`/slot-praktik/${slot.id}`);
    const deactivate=slotCard.getByRole('button',{name:'Nonaktifkan',exact:true});await reveal(admin,deactivate);await deactivate.click();await mutation(admin,'DELETE',`/slot-praktik/${slot.id}`,()=>button(admin,'Lanjutkan'));
    await choose(admin,'Status data','Nonaktif');await expect(slotCard).toBeVisible();await admin.screenshot({path:path.join(root,'admin-slot-groups.png')});report.admin.push('Slot lazy loading/grouping/filters/create/edit/deactivate');
    await nav(admin,'Penugasan petugas');await choose(admin,'Filter poliklinik',f.serviceName);await enter(admin,'Cari nama atau kode','Fixture Flutter petugas');await expand(admin,f.serviceName);
    const assignment=card(admin,'Fixture Flutter petugas');await assignment.getByRole('button',{name:'Ubah',exact:true}).click();await save(admin,'PATCH',`/penugasan-petugas/${f.assignmentId}`);
    await assignment.getByRole('button',{name:'Nonaktifkan',exact:true}).click();await mutation(admin,'DELETE',`/penugasan-petugas/${f.assignmentId}`,()=>button(admin,'Lanjutkan'));
    await choose(admin,'Status data','Nonaktif');await expect(assignment).toBeVisible();await admin.screenshot({path:path.join(root,'admin-assignment-groups.png')});report.admin.push('Penugasan grouping/search/clinic/edit/deactivate');
    assert.equal(errors.length,0,errors.join('\n'));report.flutterClients=f.adminLayoutOnly?1:2;report.physicalAndroid=false;
    console.log('Realtime/admin browser: '+JSON.stringify(report));
  }catch(e){
    let message=e.message;for(const secret of secrets.filter(Boolean))message=message.replaceAll(secret,'[redacted]');console.error(message);
    if(current&&!current.isClosed()){
      console.error('QA labels: '+JSON.stringify(await current.locator('flt-semantics[aria-label]').evaluateAll(nodes=>nodes.map(n=>({role:n.getAttribute('role'),label:n.getAttribute('aria-label')})).filter(n=>!n.label.includes('SQ1.')&&!/[a-f0-9]{64}/i.test(n.label)))));
      await current.screenshot({path:path.join(root,'realtime-admin-failure.png')}).catch(()=>{});
    }
    throw new Error('Realtime/admin QA gagal; diagnostik teredaksi tersedia.');
  }finally{
    fs.writeFileSync(path.join(root,'realtime-admin-result.json'),JSON.stringify(report,null,2));
    clearTimeout(watchdog);observer?.disconnect();for(const c of contexts)await c.close().catch(()=>{});for(const b of browsers)await b.close().catch(()=>{});
  }
};
