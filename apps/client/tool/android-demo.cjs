/** Android instrumentation against the existing isolated fixture. No production server routes. */
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const {spawn, execFileSync} = require('node:child_process');

module.exports = async function androidDemo(fixture, clientPath, prepareSlot) {
  const device = process.env.FLUTTER_ANDROID_DEVICE;
  if (!device || !/^[A-Za-z0-9._:-]+$/.test(device)) throw new Error('FLUTTER_ANDROID_DEVICE wajib diisi dengan ID perangkat adb');
  const adb = process.env.ADB_PATH || path.join(process.env.LOCALAPPDATA, 'Android/sdk/platform-tools/adb.exe');
  const output = path.join(clientPath, 'build/android-screenshots');
  fs.mkdirSync(output, {recursive:true});
  const names = new Set(['01-login','02-beranda','03-poliklinik-dokter','04-booking-slot','05-tiket-qr','06-petugas','07-detail-dokter']);
  const server = http.createServer(async (req,res) => {
    try {
      if (req.method === 'GET' && req.url === '/fixture') {
        await prepareSlot(); // Compilation must not consume the booking window.
        res.setHeader('Content-Type','application/json'); res.end(JSON.stringify(fixture));return;
      }
      const name = req.url.replace('/capture/','');
      if (req.method === 'POST' && names.has(name)) {
        const chunks=[];let length=0;
        for await (const chunk of req) {length+=chunk.length;if(length>8*1024*1024)throw new Error('Screenshot terlalu besar');chunks.push(chunk);}
        fs.writeFileSync(path.join(output,name+'.png'),Buffer.concat(chunks));res.writeHead(201);res.end();return;
      }
      res.writeHead(404);res.end();
    } catch (error) {console.error('Harness Android: '+error.message);res.writeHead(500);res.end();}
  });
  const owned=[]; let grant;
  try {
    const existing=execFileSync(adb,['-s',device,'reverse','--list'],{encoding:'utf8',windowsHide:true});
    for(const port of [3001,3002]) {
      if(existing.includes(`tcp:${port} `))throw new Error('Port adb reverse sudah digunakan; jangan timpa pemetaan existing');
      execFileSync(adb,['-s',device,'reverse',`tcp:${port}`,`tcp:${port}`],{windowsHide:true});owned.push(port);
    }
    await new Promise(resolve=>server.listen(3002,'127.0.0.1',resolve));
    // Grant only this application's camera permission for the requested device QA.
    grant=setInterval(()=>{try {
      execFileSync(adb,['-s',device,'shell','pm','grant','id.queueb.queueb_client','android.permission.CAMERA'],{windowsHide:true,stdio:'ignore'});
      clearInterval(grant);
    } catch (_) {}},3000);
    const args=['test','integration_test/mobile_flow_test.dart','-d',device,'--dart-define=API_BASE_URL=http://127.0.0.1:3001/api/v1','--dart-define=SERVICE_TIME_ZONE=Asia/Jakarta','--reporter','expanded'];
    const code=await new Promise((resolve,reject)=>{
      const windows=process.platform==='win32';
      const child=spawn(windows?'cmd.exe':'flutter',windows?['/d','/s','/c','flutter '+args.join(' ')]:args,{cwd:clientPath,stdio:'inherit',windowsHide:true});
      child.once('error',reject);child.once('exit',value=>resolve(value??1));
    });
    if(code!==0)throw new Error('Pengujian Android gagal');
    console.log('Android fisik: PASS; tujuh screenshot tersimpan di build/android-screenshots');
  } finally {
    clearInterval(grant);
    await new Promise(resolve=>server.close(resolve));
    for(const port of owned)execFileSync(adb,['-s',device,'reverse','--remove',`tcp:${port}`],{windowsHide:true});
  }
};
