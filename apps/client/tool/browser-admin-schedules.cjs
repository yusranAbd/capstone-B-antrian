/** Focused ADMIN QA against real NestJS + isolated PostgreSQL fixtures. */
const {chromium, expect: baseExpect} = require('@playwright/test');
const expect = baseExpect.configure({timeout:25000});
const path = require('node:path');
const fs = require('node:fs');
const assert = require('node:assert/strict');
const escape = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const apiBase = 'http://127.0.0.1:3001/api/v1';

module.exports = async function adminSchedules({fixture:f, root}) {
  const browser = await chromium.launch({channel:process.env.FLUTTER_BROWSER_CHANNEL || 'msedge',headless:true});
  const context = await browser.newContext({viewport:{width:1440,height:1160}});
  const page = await context.newPage();
  const errors=[], writes=[];
  const code='N'+f.unique;
  let token, clinicId;
  page.on('pageerror', e => errors.push(e.message));
  page.on('request', r => {if(r.method()==='POST' && r.url().endsWith('/jadwal-layanan')) writes.push(r.postDataJSON());});
  async function reveal(locator) {
    if(await locator.count())return;
    await page.mouse.move(1100,700);await page.mouse.wheel(0,-6000);await page.waitForTimeout(100);
    for(let i=0;i<12;i++){if(await locator.count())return;await page.mouse.wheel(0,350);await page.waitForTimeout(100);}
  }
  async function enter(name,value) {
    await page.bringToFront();
    const input=page.getByRole('textbox',{name:new RegExp(escape(name)),includeHidden:true});
    await reveal(input);await input.click();await input.press('ControlOrMeta+A');await input.press('Backspace');
    await input.pressSequentially(value,{delay:5});await input.press('Tab');
    await expect.poll(()=>input.inputValue()).toBe(value);
  }
  async function button(name) {
    await page.bringToFront();
    const b=page.getByRole('button',{name,exact:true,includeHidden:true}).first();await reveal(b);await b.click();
  }
  async function choose(label, option) {
    const scope = await page.getByRole('dialog').count() ? page.getByRole('dialog') : page;
    const name=new RegExp('^'+escape(label)+'(?:\\s|$)');
    const b=scope.getByRole('button',{name}).or(scope.getByRole('combobox',{name})).first();
    await b.click();
    await page.getByRole('menuitem',{name:new RegExp(escape(option))})
      .or(page.getByRole('option',{name:new RegExp(escape(option))}))
      .or(page.getByText(option,{exact:false})).last().click();
  }
  async function request(method,route,body,status=200) {
    const res=await fetch(apiBase+route,{method,headers:{'Content-Type':'application/json',Authorization:`Bearer ${token}`},...(body?{body:JSON.stringify(body)}:{})});
    assert.equal(res.status,status,`${method} ${route} status`);return res.json();
  }
  async function response(method, route, status, action) {
    const pending=page.waitForResponse(r=>r.request().method()===method && new URL(r.url()).pathname==='/api/v1'+route,{timeout:30000});pending.catch(()=>{});
    await action();const r=await pending;assert.equal(r.status(),status,`UI ${method} ${route}`);return r.json();
  }
  async function bulk() {await button('Tambah');await choose('Poliklinik',code);}
  async function hasNotice(value) {
    await page.bringToFront();
    // ADMIN notices have an explicit live semantic label; readonly input values
    // are included for SDKs that expose SelectableText through that surface.
    return page.locator('input,textarea,flt-semantics').evaluateAll((nodes,text)=>
      nodes.some(n=>n.value===text || n.textContent?.trim()===text || n.getAttribute('aria-label')===text),value);
  }
  async function summary(created,skipped,failed) {
    const value=`${created} berhasil · ${skipped} dilewati · ${failed} gagal/belum terverifikasi`;
    await page.bringToFront();await page.mouse.move(720,650);
    for(let i=0;i<10 && !await hasNotice(value);i++){await page.mouse.wheel(0,250);await page.waitForTimeout(150);}
    await expect.poll(()=>hasNotice(value)).toBe(true);
  }
  async function currentSchedules() {return (await request('GET','/jadwal-layanan')).filter(r=>r.layananId===clinicId);}
  function dayRow(day) {return page.getByRole('group',{name:new RegExp('^'+escape(day)+'(?:\\s|$)')}).first();}
  async function clinicSummary(active) {
    const name=new RegExp('^'+escape('Saraf (Neurologi)')+'\\s+'+active+' hari aktif');
    await expect(page.getByRole('group',{name}).or(page.getByRole('button',{name}))).toBeVisible();
  }
  try {
    await page.goto('http://127.0.0.1:8080/');
    await enter('Email',f.admin.email);await enter('Kata sandi',f.admin.password);
    const login=await response('POST','/auth/login',200,()=>button('Masuk'));token=login.accessToken;
    assert.ok(!(await request('GET','/layanan')).some(row=>row.kode===code),'Kode fixture harus belum ada');
    f.extraServiceCodes.push(code); // Before POST; uncertain commits are also cleaned.
    await expect(page.getByRole('button',{name:'Tambah',exact:true})).toBeEnabled();
    await button('Tambah');await enter('Kode',code);await enter('Nama','Saraf (Neurologi)');await enter('Prefix antrean','SF');await enter('Durasi dasar (menit)','25');
    const clinic=await response('POST','/layanan',201,()=>button('Simpan'));clinicId=clinic.id;
    assert.equal(clinic.durasiDasarMenit,25);assert.equal(clinic.modeReservasi,'HIBRIDA');
    await expect(page.getByRole('dialog')).toHaveCount(0);
    await expect(page.getByRole('button',{name:'Tambah',exact:true})).toBeEnabled();
    await button('Tambah');await enter('Kode',code);await enter('Nama','Saraf (Neurologi)');await enter('Prefix antrean','SF');await enter('Durasi dasar (menit)','25');
    await response('POST','/layanan',409,()=>button('Simpan'));
    await expect.poll(()=>hasNotice('Kode layanan sudah digunakan')).toBe(true);await button('Kembali');
    const invalid=await request('POST','/layanan',{kode:'V'+f.unique,nama:'Validasi Durasi',prefixAntrean:'SF',durasiDasarMenit:0,modeReservasi:'HIBRIDA'},400);
    assert.ok(Array.isArray(invalid.message));
    console.log('ADMIN Poliklinik: PASS (durasi 25, HIBRIDA, HTTP 409 duplikat, HTTP 400 validasi)');
    await page.getByRole('button',{name:/^Jam & kapasitas poli(?:\s|$)/}).click();
    await expect(page.getByRole('button',{name:'Tambah',exact:true})).toBeEnabled();
    await enter('Cari poliklinik','Saraf');
    const collapsed=page.getByRole('button',{name:/^Saraf \(Neurologi\)(?:\s|$)/});
    if(await collapsed.count()) await collapsed.click();
    await bulk();
    await page.screenshot({path:path.join(root,'admin-bulk-form.png')});
    await button('Simpan Jadwal Terpilih');await summary(5,0,0);
    assert.equal(writes.length,5);await button('Tutup & muat ulang');
    await clinicSummary(5);
    assert.equal((await currentSchedules()).length,5);
    await page.screenshot({path:path.join(root,'admin-grouped-schedules.png')});
    await bulk();await button('Simpan Jadwal Terpilih');await summary(0,5,0);assert.equal(writes.length,5);await button('Tutup & muat ulang');
    console.log('ADMIN bulk: PASS (lima hari, urutan Senin–Jumat, existing dilewati tanpa POST ulang)');
    // Inject one HTTP fault; other requests and reconciliation use the real API.
    let injected=false;
    await page.route('**/api/v1/jadwal-layanan',async route=>{
      const r=route.request();
      if(!injected && r.method()==='POST' && r.postDataJSON().hari==='SABTU'){
        injected=true;await route.fulfill({status:503,contentType:'application/json',body:JSON.stringify({message:'Simulasi gangguan koneksi QA'})});
      } else await route.continue();
    });
    await bulk();await button('Pilih Semua');await button('Simpan Jadwal Terpilih');await summary(1,5,1);
    assert.ok(injected);assert.equal(writes.length,7);await button('Tutup & muat ulang');
    let saved=await currentSchedules();assert.equal(saved.length,6);assert.ok(!saved.some(r=>r.hari==='SABTU'));
    await page.unroute('**/api/v1/jadwal-layanan');
    await bulk();await button('Pilih Semua');await button('Simpan Jadwal Terpilih');await summary(1,6,0);assert.equal(writes.length,8);await button('Tutup & muat ulang');
    saved=await currentSchedules();assert.equal(saved.length,7);
    console.log('ADMIN partial failure: PASS (1 berhasil/5 dilewati/1 belum terverifikasi; percobaan baru hanya mengirim hari yang belum ada)');
    const monday=saved.find(r=>r.hari==='SENIN');
    await dayRow('Senin').getByRole('button',{name:'Ubah',exact:true}).click();
    await enter('Jam tutup (HH:mm)','17:00');await enter('Kapasitas harian','30');
    await response('PATCH',`/jadwal-layanan/${monday.id}`,200,()=>button('Simpan'));
    await expect(page.getByRole('dialog')).toHaveCount(0);
    await expect(page.getByRole('button',{name:'Tambah',exact:true})).toBeEnabled();
    await dayRow('Senin').getByRole('button',{name:'Nonaktifkan',exact:true}).click();
    await response('DELETE',`/jadwal-layanan/${monday.id}`,200,()=>button('Lanjutkan'));
    await expect(page.getByRole('button',{name:'Tambah',exact:true})).toBeEnabled();
    saved=await currentSchedules();assert.equal(saved.length,7);const inactive=saved.find(r=>r.id===monday.id);assert.equal(inactive.aktif,false);assert.equal(inactive.kapasitasHarian,30);assert.equal(inactive.jamTutup.slice(11,16),'17:00');
    await bulk();await button('Simpan Jadwal Terpilih');await summary(0,5,0);assert.equal(writes.length,8);await button('Tutup & muat ulang');
    await button('Muat ulang');await clinicSummary(6);
    await page.reload();await enter('Email',f.admin.email);await enter('Kata sandi',f.admin.password);await button('Masuk');
    await expect(page.getByRole('button',{name:'Tambah',exact:true})).toBeEnabled();
    await page.getByRole('button',{name:/^Jam & kapasitas poli(?:\s|$)/}).click();
    await expect(page.getByRole('button',{name:'Tambah',exact:true})).toBeEnabled();await enter('Cari poliklinik',code);
    await clinicSummary(6);
    assert.equal((await currentSchedules()).length,7);
    console.log('ADMIN edit/nonaktif/refresh: PASS (ID tetap, 7 record utuh, nonaktif dilewati, login ulang konsisten)');
    assert.equal(errors.length,0,'Flutter runtime errors');
    fs.writeFileSync(path.join(root,'admin-qa-report.json'),JSON.stringify({poliklinik:true,duplicate:true,validation:true,fiveDays:true,existingDays:true,partialFailure:true,edit:true,softDeactivate:true,persistence:true,postSchedules:writes.length,runtimeErrors:errors.length},null,2));
  } catch (e) {
    const message=e.message.replaceAll(f.admin.password,'[redacted]').replaceAll(token||'NEVER_MATCH','[redacted]');
    console.error(message);
    console.error('ADMIN semantics: '+JSON.stringify(await page.locator('flt-semantics[aria-label]').evaluateAll(nodes=>nodes.map(n=>({role:n.getAttribute('role'),label:n.getAttribute('aria-label')})))));
    fs.writeFileSync(path.join(root,'admin-qa-dom.json'),JSON.stringify(await page.locator('input,textarea,flt-semantics').evaluateAll(nodes=>nodes.map(n=>({tag:n.tagName,role:n.getAttribute('role'),label:n.getAttribute('aria-label'),text:n.textContent?.slice(0,180),value:n.type==='password'?'[redacted]':n.value}))),null,2));
    await page.screenshot({path:path.join(root,'admin-qa-failure.png')}).catch(()=>{});
    throw new Error('QA ADMIN gagal; lihat diagnosis tersanitasi di atas');
  } finally {await browser.close();}
};
