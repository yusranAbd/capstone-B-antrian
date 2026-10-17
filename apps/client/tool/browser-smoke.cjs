const {chromium, expect} = require('@playwright/test');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

module.exports = async function browserSmoke(fixture) {
  async function enter(page, name, value) {
    const input = page.getByRole('textbox', {name, exact:true});
    await input.click();
    await input.pressSequentially(value, {delay: 8});
    await expect.poll(async () => (await input.inputValue()) === value).toBe(true);
  }
  const root = path.resolve(__dirname, '../build/web');
  const libRoot = path.resolve(__dirname,'../lib');
  const sourceTime = Math.max(...fs.readdirSync(libRoot,{recursive:true}).filter(file=>file.endsWith('.dart')).map(file=>fs.statSync(path.join(libRoot,file)).mtimeMs));
  const buildDeadline = Date.now() + 5 * 60_000;
  while (!fs.existsSync(path.join(root, 'main.dart.js')) || fs.statSync(path.join(root, 'main.dart.js')).mtimeMs < sourceTime) {
    if (Date.now() > buildDeadline) throw new Error('Build Flutter Web terbaru belum tersedia. Jalankan build sebelum smoke browser.');
    await new Promise(resolve => setTimeout(resolve, 1000));
  }
  // Fail before opening a browser: the compiled UI must not write to development.
  if (!fs.readFileSync(path.join(root,'main.dart.js'),'utf8').includes('http://127.0.0.1:3001/api/v1')) {
    throw new Error('QA Web wajib dibangun dengan API_BASE_URL=http://127.0.0.1:3001/api/v1; browser tidak dibuka.');
  }
  const mime = {'.html':'text/html', '.js':'text/javascript', '.json':'application/json', '.wasm':'application/wasm', '.css':'text/css'};
  const server = http.createServer((req, res) => {
    const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    const target = path.resolve(root, '.' + (pathname === '/' ? '/index.html' : pathname));
    if (!(target === root || target.startsWith(root + path.sep))) {res.writeHead(403);res.end();return;}
    fs.readFile(target, (error, data) => {
      if(error) {res.writeHead(404);res.end();return;}
      res.setHeader('Content-Type', mime[path.extname(target)] || 'application/octet-stream');
      res.setHeader('Cache-Control', 'no-store');res.end(data);
    });
  });
  await new Promise(resolve => server.listen(8080, '127.0.0.1', resolve));
  let browser, lastPage;
  try {
    if (fixture.doctorSchedule) return await require('./browser-doctor-schedule.cjs')({fixture, root});
    if (fixture.realtimeAdmin) return await require('./browser-realtime-admin.cjs')({fixture, root});
    if (fixture.adminSchedules) return await require('./browser-admin-schedules.cjs')({fixture, root});
    if (fixture.demoFull) return await require('./browser-demo.cjs')({fixture, root});
    browser = await chromium.launch({channel: process.env.FLUTTER_BROWSER_CHANNEL || 'msedge', headless: true});
    for (const [account, heading] of [['admin','Poliklinik'], ['petugas','Panel petugas'], ['patient1','Poliklinik & Dokter']]) {
      const context = await browser.newContext({viewport: {width: account === 'patient1' ? 390 : 1365, height: 1000}});
      const page = lastPage = await context.newPage();
      const errors = []; page.on('pageerror', error => errors.push(error.message));
      await page.goto('http://127.0.0.1:8080/');
      await enter(page, 'Email', fixture[account].email);
      await enter(page, 'Kata sandi', fixture[account].password);
      await page.getByRole('button', {name: 'Masuk', exact: true}).click();
      if (account === 'patient1') await page.getByRole('tab',{name:'Pendaftaran',exact:true}).click();
      if (account === 'patient1') await expect(page.getByText('Poliklinik & Dokter', {exact:true})).toBeVisible({timeout:15000});
      else await expect(page.getByText(heading, {exact: false}).first()).toBeVisible({timeout: 15000});
      if (account === 'petugas') await expect(page.getByText('Realtime terhubung', {exact:false})).toBeVisible({timeout: 15000});
      if (account === 'patient1') { await page.getByRole('tab', {name:'Tiket Saya', exact:true}).click(); await expect(page.getByRole('button', {name:'Lihat tiket / QR', exact:true}).first()).toBeVisible(); }
      if (errors.length) throw new Error('Runtime browser error: ' + errors[0]);
      await page.screenshot({path:path.join(root, `qa-${account}.png`), fullPage:true});
      await context.close();
      console.log(`Browser Flutter ${account}: PASS`);
    }
    const context = await browser.newContext(); const page = lastPage = await context.newPage();
    await page.goto('http://127.0.0.1:8080/');
    await page.getByRole('button', {name:'Buka Public Display', exact:true}).click();
    await enter(page, 'ID layanan', fixture.serviceId);
    await enter(page, 'Token perangkat', fixture.displayToken);
    await page.getByRole('button', {name:'Hubungkan display', exact:true}).click();
    await expect(page.getByText('Poli Fixture Flutter', {exact:true})).toBeVisible();
    await expect(page.getByText('Realtime terhubung', {exact:false})).toBeVisible({timeout:15000});
    await page.screenshot({path:path.join(root,'qa-display.png'),fullPage:true});
    await context.close(); console.log('Browser Flutter display: PASS');
  } catch (error) {
    let message = error.message.replaceAll(fixture.displayToken, '[redacted]');
    for (const key of ['admin','petugas','patient1','patient2']) message = message.replaceAll(fixture[key].password, '[redacted]');
    console.error(message);
    if (lastPage && !lastPage.isClosed()) console.error('Label semantics QA: ' + JSON.stringify(await lastPage.locator('flt-semantics[aria-label]').evaluateAll(nodes => nodes.map(node => ({role:node.getAttribute('role'),label:node.getAttribute('aria-label')})))));
    if (lastPage && !lastPage.isClosed()) await lastPage.screenshot({path:path.join(root,'qa-failure.png'),fullPage:true}).catch(()=>{});
    throw error;
  } finally {await browser?.close(); await new Promise(resolve => server.close(resolve));}
};
