/** P0 acceptance through compiled Flutter and a real, isolated NestJS server. */
const {chromium, expect: baseExpect} = require('@playwright/test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {enter, button, choose, mutation} = require('./browser-demo.cjs').helpers;
const expect = baseExpect.configure({timeout:25000});

module.exports = async function adminP0({fixture:f, root}) {
  const output = path.resolve(__dirname, '../../../docs/frontend/images/admin-p0');
  fs.mkdirSync(output, {recursive:true});
  const browser = await chromium.launch({channel:process.env.FLUTTER_BROWSER_CHANNEL || 'msedge', headless:true});
  const context = await browser.newContext({viewport:{width:1366,height:768}});
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  // Register owned IDs even when a later UI assertion fails.
  page.on('response', async r => {
    if (r.request().method() !== 'POST' || !r.ok()) return;
    const route = new URL(r.url()).pathname;
    if (route === '/api/v1/akun-petugas') {
      const a = await r.json(); f.extraUserIds.push(a.id);
    } else if (route === '/api/v1/dokter') {
      const d = await r.json(); f.extraDoctorIds.push(d.id);
    } else if (/^\/api\/v1\/dokter\/[^/]+\/akun$/.test(route)) {
      const d = await r.json(); f.extraUserIds.push(d.akun.id);
    }
  });
  async function navigate(name) {
    await page.getByRole('button',{name,exact:true}).or(page.getByRole('tab',{name,exact:true})).first().click();
  }
  async function search(label, value) { await enter(page,label,value); }
  async function semanticText(text) {
    await expect.poll(() => page.locator('flt-semantics[aria-label]').evaluateAll(
      (nodes, target) => nodes.some(n => (n.getAttribute('aria-label') || '').includes(target)), text)).toBe(true);
  }
  try {
    await page.goto('http://127.0.0.1:8080/');
    console.log('P0 browser: login ADMIN');
    await enter(page,'Email',f.admin.email); await enter(page,'Kata sandi',f.admin.password);
    await mutation(page,'POST','/auth/login',()=>button(page,'Masuk'));
    await expect(page.getByRole('button',{name:'Profil akun',exact:true})).toBeVisible();
    await navigate('Penugasan petugas');
    console.log('P0 browser: create account');
    await button(page,'Tambah akun PETUGAS');
    await enter(page,'Nama petugas','Siti Rahma — Loket Poli');
    const staffEmail = `loket-${f.unique.toLowerCase()}@test.local`;
    await enter(page,'Email login',staffEmail); await enter(page,'Kata sandi awal',f.petugas.password);
    const staff = await mutation(page,'POST','/akun-petugas',()=>button(page,'Buat akun PETUGAS'));
    assert.equal(staff.peran,'PETUGAS');
    await search('Cari nama atau email petugas',staffEmail);
    await expect(page.getByRole('button',{name:'Nonaktifkan akun',exact:true})).toBeEnabled();
    await button(page,'Nonaktifkan akun');
    await mutation(page,'PATCH',`/akun-petugas/${staff.id}`,()=>button(page,'Lanjutkan'));
    await expect(page.getByRole('button',{name:'Aktifkan akun',exact:true})).toBeEnabled();
    await button(page,'Aktifkan akun');
    await mutation(page,'PATCH',`/akun-petugas/${staff.id}`,()=>button(page,'Lanjutkan'));
    await expect(page.getByRole('button',{name:'Nonaktifkan akun',exact:true})).toBeEnabled();
    await page.screenshot({path:path.join(output,'01-akun-petugas.png')});
    console.log('P0 browser: account lifecycle PASS');

    await page.getByRole('tab',{name:'Penugasan Loket',exact:true}).click();
    await button(page,'Tambah');
    const staffChoice = page.getByRole('textbox',{name:/Petugas \(nama \/ email\)/}).or(page.getByRole('combobox',{name:/Petugas \(nama \/ email\)/})).first();
    await staffChoice.click(); await staffChoice.fill(staffEmail);
    await page.getByRole('menuitem',{name:new RegExp(staffEmail)}).or(page.getByRole('option',{name:new RegExp(staffEmail)})).or(page.getByRole('button',{name:new RegExp(staffEmail)})).last().click();
    await choose(page,'Ruang / loket',f.roomName);
    await page.getByRole('textbox',{name:'Tanggal mulai (YYYY-MM-DD)',exact:true}).click();
    await button(page,'OKE');
    const assignment = await mutation(page,'POST','/penugasan-petugas',()=>button(page,'Simpan'));
    assert.equal(assignment.petugasId,staff.id); assert.equal(assignment.loketId,f.roomId);
    await search('Cari nama atau kode',staffEmail);
    await semanticText('BERLAKU');
    await page.setViewportSize({width:1440,height:900});
    await page.screenshot({path:path.join(output,'02-penugasan-loket.png')});
    console.log('P0 browser: assignment PASS');

    await navigate('Dokter'); await button(page,'Tambah');
    await enter(page,'Kode',`P0${f.unique}`); await enter(page,'Nama','dr. Rani Permatasari');
    await enter(page,'Spesialisasi','Penyakit Dalam');
    const doctor = await mutation(page,'POST','/dokter',()=>button(page,'Simpan'));
    await search('Cari dokter atau spesialisasi','dr. Rani');
    await expect(page.getByRole('button',{name:'Hubungkan poliklinik',exact:true})).toBeEnabled();
    await button(page,'Hubungkan poliklinik');
    await choose(page,'Poliklinik untuk dihubungkan',f.serviceCode);
    await mutation(page,'POST',`/dokter/${doctor.id}/layanan`,()=>button(page,'Hubungkan'));
    await button(page,'Tutup');
    await button(page,'Buat akun login');
    await enter(page,'Email dokter',`dokter-${f.unique.toLowerCase()}@test.local`);
    await enter(page,'Kata sandi awal',f.petugas.password);
    await mutation(page,'POST',`/dokter/${doctor.id}/akun`,()=>button(page,'Buat akun DOKTER'));
    await semanticText('Akun aktif');
    await page.screenshot({path:path.join(output,'03-manajemen-dokter.png')});
    console.log('P0 browser: doctor provisioning PASS');
    await page.setViewportSize({width:768,height:1024});
    await expect(page.getByRole('button',{name:'Menu administrasi',exact:true})).toBeVisible();
    await page.screenshot({path:path.join(output,'04-dokter-tablet.png')});
    assert.deepEqual(errors,[]);
    fs.writeFileSync(path.join(root,'qa-admin-p0.json'),JSON.stringify({accounts:true,status:true,assignment:true,doctorProvisioning:true,desktop:['1366x768','1440x900'],tablet:'768x1024',runtimeErrors:errors.length},null,2));
    console.log('ADMIN P0 browser: account create/disable/reactivate, name/email selection, assignment and doctor provisioning PASS; 4 screenshots.');
  } catch (error) {
    let message = String(error.message || error.name);
    for (const key of ['admin','petugas','patient1','patient2']) message = message.split(f[key].password).join('[redacted]');
    console.error(message.replace(/eyJ[A-Za-z0-9_.-]+/g,'[redacted]'));
    await page.screenshot({path:path.join(root,'qa-admin-p0-failure.png')}).catch(()=>{});
    throw error;
  } finally {
    await browser.close();
  }
};
