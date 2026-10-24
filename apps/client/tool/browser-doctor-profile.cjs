/** P1 acceptance against compiled Flutter and real NestJS on an isolated test DB. */
const { chromium, expect: baseExpect } = require('@playwright/test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { enter, button, mutation, reveal } = require('./browser-demo.cjs').helpers;
const expect = baseExpect.configure({ timeout: 25000 });

module.exports = async function doctorProfile({ fixture: f, root }) {
  const output = path.resolve(__dirname, '../../../docs/frontend/images/doctor-profile-p1');
  fs.mkdirSync(output, { recursive: true });
  const browser = await chromium.launch({ channel: process.env.FLUTTER_BROWSER_CHANNEL || 'msedge', headless: true });
  const admin = await browser.newPage({ viewport: { width: 1366, height: 900 } });
  const patient = await browser.newPage({ viewport: { width: 414, height: 1000 } });
  const errors = [], media = [];
  for (const page of [admin, patient]) {
    page.on('pageerror', e => errors.push(e.message));
    page.on('response', r => { if (new URL(r.url()).pathname.includes('/media/dokter/')) media.push({ status: r.status(), type: r.headers()['content-type'] }); });
  }
  async function semantic(page, text) {
    await expect.poll(() => page.locator('[aria-label], flt-semantics').evaluateAll((nodes, target) => nodes.some(n => (n.getAttribute('aria-label') || n.textContent || '').includes(target)), text)).toBe(true);
  }
  async function login(page, account) {
    await page.goto('http://127.0.0.1:8080/');
    await enter(page, 'Email', account.email); await enter(page, 'Kata sandi', account.password);
    await mutation(page, 'POST', '/auth/login', () => button(page, 'Masuk'));
  }
  async function selectPhoto(page, label) {
    const chooser = page.waitForEvent('filechooser');
    chooser.catch(() => {});
    await button(page, label);
    // QA-only sample is actually uploaded/normalized by the API. Production UI
    // never reads this bundled illustration as a professional doctor photo.
    await (await chooser).setFiles(path.resolve(__dirname, '../assets/illustrations/doctor_avatar.png'));
    await expect(page.getByRole('button', { name: 'Ganti Foto', exact: true })).toBeEnabled();
  }
  async function edit() {
    const semanticButton = admin.getByRole('button', { name: /Aksi profil dokter/ });
    if (await semanticButton.count()) await semanticButton.last().click();
    else {
      // Flutter's web table semantics can omit nested custom cells. Use the
      // visible Aksi column geometry and the single fixture row (112px high).
      const header = await admin.getByRole('columnheader', {name:'Aksi',exact:true}).boundingBox();
      assert.ok(header, 'Aksi column is visible');
      await admin.mouse.click(header.x + header.width / 2, header.y + header.height + 56);
    }
    await admin.getByRole('menuitem', { name: 'Ubah profil', exact: true })
      .or(admin.locator('flt-semantics[aria-label="Ubah profil"]')).last().click();
  }
  try {
    await login(admin, f.admin);
    await button(admin, 'Dokter');
    await enter(admin, 'Cari dokter atau spesialisasi', 'Dokter Fixture Flutter');
    await edit();
    await enter(admin, 'Tentang Dokter (opsional)', 'Profil profesional dokter untuk pengujian P1. Informasi ini dikelola oleh ADMIN dan ditampilkan kepada pasien sebelum memilih jadwal praktik.');
    await selectPhoto(admin, 'Upload Foto');
    await admin.screenshot({ path: path.join(output, '01-admin-profil-dokter.png') });
    const uploaded = await mutation(admin, 'POST', `/dokter/${f.doctorId}/foto`, () => button(admin, 'Simpan'));
    assert.match(uploaded.fotoProfil, /^\/media\/dokter\/[0-9a-f-]+\.webp$/);
    await semantic(admin, 'Data disimpan.');
    await expect.poll(() => media.some(m => m.status === 200 && m.type.includes('image/webp'))).toBe(true);

    await login(patient, f.patient1);
    await patient.getByRole('tab', { name: 'Pendaftaran', exact: true }).click();
    await semantic(patient, 'Poliklinik & Dokter');
    await patient.getByRole('button', { name: /Poli Fixture Flutter/ }).first().click();
    await reveal(patient, patient.getByRole('button', { name: 'Lihat Detail Dokter', exact: true }));
    await expect(patient.getByRole('button', { name: 'Lihat Detail Dokter', exact: true })).toBeEnabled();
    await expect(patient.locator('[aria-label*="Memuat jadwal praktik"]')).toHaveCount(0);
    await patient.screenshot({ path: path.join(output, '02-pasien-daftar-dokter.png') });
    await button(patient, 'Lihat Detail Dokter');
    await semantic(patient, 'Tentang Dokter');
    await semantic(patient, 'Profil profesional dokter untuk pengujian P1.');
    await patient.mouse.wheel(0, -5000); await patient.waitForTimeout(250);
    await patient.screenshot({ path: path.join(output, '03-pasien-detail-dokter.png') });
    const booking = patient.getByRole('button', { name: 'Buat Janji Temu', exact: true });
    await reveal(patient, booking); await expect(booking).toBeEnabled();
    await booking.click();
    await expect(patient.getByRole('button', { name: 'Lihat slot', exact: true })).toBeEnabled();

    await edit(); await selectPhoto(admin, 'Ganti Foto');
    const replacement = await mutation(admin, 'POST', `/dokter/${f.doctorId}/foto`, () => button(admin, 'Simpan'));
    assert.notEqual(replacement.fotoProfil, uploaded.fotoProfil);
    await semantic(admin, 'Data disimpan.');
    await edit(); await button(admin, 'Hapus Foto');
    await mutation(admin, 'DELETE', `/dokter/${f.doctorId}/foto`, () => button(admin, 'Simpan'));
    await semantic(admin, 'Data disimpan.');
    assert.deepEqual(errors, []);
    fs.writeFileSync(path.join(root, 'qa-doctor-profile.json'), JSON.stringify({ upload: true, replace: true, remove: true, biography: true, patientList: true, patientDetail: true, bookingNavigation: true, mediaLoaded: media.filter(m => m.status === 200).length, runtimeErrors: errors.length }, null, 2));
    console.log('Doctor Profile P1 browser: upload/replace/remove, biography, patient list/detail, media and booking navigation PASS; 3 screenshots.');
  } catch (error) {
    let message = String(error.message || error.name);
    for (const key of ['admin', 'petugas', 'patient1', 'patient2']) message = message.split(f[key].password).join('[redacted]');
    console.error(message.replace(/eyJ[A-Za-z0-9_.-]+/g, '[redacted]'));
    console.error('QA action semantics: ' + JSON.stringify(await admin.locator('[aria-label]').evaluateAll(nodes => nodes.map(n => ({role:n.getAttribute('role'),label:n.getAttribute('aria-label')})).filter(n => /Aksi|Ubah profil/.test(n.label || '')))));
    await admin.screenshot({ path: path.join(root, 'qa-doctor-profile-admin-failure.png') }).catch(() => {});
    await patient.screenshot({ path: path.join(root, 'qa-doctor-profile-patient-failure.png') }).catch(() => {});
    throw new Error('Doctor Profile browser failed; see redacted QA report.');
  } finally { await browser.close(); }
};
