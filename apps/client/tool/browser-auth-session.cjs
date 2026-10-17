/** Compiled Flutter Web auth regression. Controlled HTTP responses; no database/server writes. */
const {chromium,expect:baseExpect}=require('@playwright/test');
const expect=baseExpect.configure({timeout:20000});
const {enter,button,reveal}=require('./browser-demo.cjs').helpers;
const fs=require('node:fs'),path=require('node:path'),http=require('node:http');
const assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../build/web');
const report={transport:'compiled Flutter Web + controlled HTTP; no database',roles:[],rotation:false,logoutWarning:false,webMemoryOnly:false,reloadRequiresLogin:false};
let step='build preflight';
const token=()=>['e30',Buffer.from(JSON.stringify({exp:Math.floor(Date.now()/1000)+3600})).toString('base64url'),'test-only'].join('.');
(async()=>{
  const compiled=fs.readFileSync(path.join(root,'main.dart.js'),'utf8');
  assert.ok(compiled.includes('http://127.0.0.1:3001/api/v1'),'Build Web QA API 3001 required');
  const server=http.createServer((req,res)=>{
    const pathname=new URL(req.url,'http://localhost').pathname;
    const file=path.resolve(root,'.'+(pathname==='/'?'/index.html':decodeURIComponent(pathname)));
    if(!file.startsWith(root+path.sep)){res.writeHead(403);res.end();return;}
    fs.readFile(file,(err,data)=>{if(err){res.writeHead(404);res.end();return;}
      res.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.wasm':'application/wasm','.json':'application/json'})[path.extname(file)]||'application/octet-stream');res.end(data);});
  });
  await new Promise(resolve=>server.listen(8080,'127.0.0.1',resolve));
  let browser,lastPage;
  const errors=[];
  try{
    browser=await chromium.launch({channel:process.env.FLUTTER_BROWSER_CHANNEL||'msedge',headless:true});
    for(const role of ['ADMIN','PETUGAS','USER']){
      step=role+' login';const context=await browser.newContext({viewport:{width:role==='USER'?390:1440,height:1000}});
      let access=token(),refresh='controlled-refresh-old',rotations=0,expired=false,logoutFails=false,meReads=0;
      const identity={id:'controlled-account',nama:'Fixture sesi',email:'session@test.local',peran:role};
      // Every API request is intercepted, including unsupported endpoints. None reaches a database.
      await context.route('**/api/v1/**',async route=>{
        const r=route.request(),url=new URL(r.url());assert.equal(url.origin,'http://127.0.0.1:3001');
        const p=url.pathname.slice('/api/v1'.length);let status=200,body=[];
        if(p==='/auth/login')body={accessToken:access,refreshToken:refresh,user:{...identity,peran:'USER'}};
        else if(p==='/auth/refresh'){
          assert.equal(r.postDataJSON().refreshToken,refresh);rotations++;access=token()+rotations;refresh='controlled-refresh-'+rotations;expired=false;
          body={accessToken:access,refreshToken:refresh,user:identity};
        }else if(p==='/auth/logout'){
          assert.equal(r.postDataJSON().refreshToken,refresh);status=logoutFails?503:200;body={message:logoutFails?'Controlled network failure':'Logout berhasil'};
        }else if(expired || r.headers().authorization!=='Bearer '+access){status=401;body={message:'Expired'};}
        else if(p==='/auth/me'){meReads++;body=identity;}
        await route.fulfill({status,contentType:'application/json',body:JSON.stringify(body)});
      });
      // Auth QA owns HTTP responses; never connect its synthetic JWT to a live Socket.IO server.
      await context.routeWebSocket(/\/socket.io\//,socket=>socket.close());
      const page=lastPage=await context.newPage();page.on('pageerror',e=>errors.push(e.message));
      await page.goto('http://127.0.0.1:8080');await enter(page,'Email','session@test.local');await enter(page,'Kata sandi','controlled-password');await button(page,'Masuk');
      await expect(page.getByRole('button',{name:'Profil akun',exact:true})).toBeVisible();
      if(role==='ADMIN')await expect(page.getByRole('button',{name:'Tambah',exact:true})).toBeVisible();
      if(role==='PETUGAS')await expect(page.getByText('Panel petugas',{exact:true})).toBeVisible();
      if(role==='USER'){
        step='USER refresh';
        await page.getByRole('tab',{name:'Tiket Saya',exact:true}).click();expired=true;
        await button(page,'Muat ulang tiket');await expect.poll(()=>rotations).toBe(1);
        await expect(page.getByRole('button',{name:'Profil akun',exact:true})).toBeVisible();report.rotation=true;
        logoutFails=true;
      }
      step=role+' browser storage';assert.deepEqual(await page.evaluate(()=>({local:Object.keys(localStorage),session:Object.keys(sessionStorage)})),{local:[],session:[]});
      step=role+' logout';
      const logoutResponse=page.waitForResponse(r=>new URL(r.url()).pathname==='/api/v1/auth/logout');
      await button(page,'Keluar akun');assert.equal((await logoutResponse).status(),logoutFails?503:200);
      await expect(page.getByRole('textbox',{name:'Email',exact:true})).toBeVisible();
      if(role==='USER'){
        step='USER logout warning';const notice=page.getByText(/Sesi lokal sudah dihapus/).or(page.locator('[aria-label*="Sesi lokal sudah dihapus"],[aria-valuetext*="Sesi lokal sudah dihapus"]'));
        await reveal(page,notice,true);
        await expect(notice.last()).toBeVisible();report.logoutWarning=true;
      }
      const before=meReads;await page.reload();await expect(page.getByRole('textbox',{name:'Email',exact:true})).toBeVisible();assert.equal(meReads,before);
      report.roles.push(role);await context.close();console.log('Web auth '+role+': PASS');
    }
    assert.equal(errors.length,0,'Browser runtime errors');report.webMemoryOnly=true;report.reloadRequiresLogin=true;
    console.log('Web session QA: '+JSON.stringify(report));
    fs.writeFileSync(path.join(root,'auth-session-qa.json'),JSON.stringify(report,null,2));
  }catch(e){
    if(lastPage&&!lastPage.isClosed()){
      await lastPage.screenshot({path:path.join(root,'auth-session-failure.png')}).catch(()=>{});
      console.error('QA notice nodes: '+await lastPage.locator('[aria-label*="Sesi lokal"]').count());
      console.error('QA notice semantics: '+JSON.stringify(await lastPage.locator('[aria-label],flt-semantics').evaluateAll(nodes=>nodes.map(n=>({tag:n.tagName,role:n.getAttribute('role'),label:n.getAttribute('aria-label'),text:n.textContent?.trim()})).filter(n=>[n.label,n.text].some(v=>v?.includes('Sesi lokal'))))));
    }
    throw e;
  }finally{await browser?.close();await new Promise(resolve=>server.close(resolve));}
})().catch(()=>{console.error('Web session QA gagal pada '+step+'; tidak mencetak token atau kredensial.');process.exitCode=1;});
