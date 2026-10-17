/** Compiled Flutter against real NestJS; caller validates local test DB and cleans owned fixtures. */
const {chromium,expect:baseExpect}=require('@playwright/test');
const expect=baseExpect.configure({timeout:25000});
const {enter,button,choose,mutation,reveal}=require('./browser-demo.cjs').helpers;
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');

module.exports=async function doctorSchedule({fixture:f,root}) {
  const screenshots=path.resolve(__dirname,'../../../docs/frontend/images');
  fs.mkdirSync(screenshots,{recursive:true});
  const report={database:'127.0.0.1:5433/capstone_antrean_test',transport:'compiled Flutter Web → NestJS existing API',widths:[],fullSlotDisabled:false,appointment:false,distinctIds:false,ownedTicket:false};
  async function post(route,body,token){
    const response=await fetch('http://127.0.0.1:3001/api/v1'+route,{method:'POST',headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:JSON.stringify(body)});
    assert.ok(response.ok,route+' HTTP '+response.status);return response.json();
  }
  const admin=await post('/auth/login',{email:f.admin.email,kataSandi:f.admin.password});
  const patient=await post('/auth/login',{email:f.patient1.email,kataSandi:f.patient1.password});
  const fullStart=new Date(new Date(f.slotStart).getTime()+20*60000);
  const full=await post('/slot-praktik',{jadwalPraktikId:f.scheduleId,mulaiPada:fullStart.toISOString(),selesaiPada:new Date(fullStart.getTime()+15*60000).toISOString(),kapasitas:1},admin.accessToken);
  await post('/janji-temu',{slotPraktikId:full.id},patient.accessToken);
  const browser=await chromium.launch({channel:process.env.FLUTTER_BROWSER_CHANNEL||'msedge',headless:true});
  let page;const errors=[];
  try{
    const context=await browser.newContext({viewport:{width:375,height:1000}});
    page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));
    await page.goto('http://127.0.0.1:8080/');
    await enter(page,'Email',f.patient2.email);await enter(page,'Kata sandi',f.patient2.password);await button(page,'Masuk');
    await page.getByRole('tab',{name:'Pendaftaran',exact:true}).click();
    await choose(page,'Poliklinik','Poli Fixture Flutter');
    await enter(page,'Cari poliklinik atau dokter','Poli Fixture Flutter');
    await reveal(page,page.getByRole('button',{name:'Lihat Jadwal',exact:true}));
    await expect(page.getByRole('button',{name:'Lihat Jadwal',exact:true})).toBeEnabled();
    for(const width of [320,375,414,768]){
      await page.setViewportSize({width,height:1000});await page.mouse.wheel(0,-5000);await page.waitForTimeout(200);
      await page.screenshot({path:path.join(screenshots,`doctor-schedule-web-${width}.png`)});
      report.widths.push(width);
    }
    await page.setViewportSize({width:375,height:1000});
    await button(page,'Lihat Jadwal');
    await expect(page.getByRole('button',{name:'Lihat slot',exact:true})).toBeEnabled();
    await page.screenshot({path:path.join(screenshots,'doctor-schedule-detail-web.png')});
    await button(page,'Lihat slot');
    const fullButton=page.getByRole('button',{name:/Penuh.*Sisa slot 0/});
    await reveal(page,fullButton);await expect(fullButton).toBeDisabled();report.fullSlotDisabled=true;
    const available=page.getByRole('button',{name:/Tersedia.*Sisa slot 2/});
    await reveal(page,available);await available.click();
    await page.screenshot({path:path.join(screenshots,'doctor-schedule-slot-web.png')});
    await button(page,'Booking janji temu');
    const bookingResponse=page.waitForResponse(r=>r.request().method()==='POST'&&new URL(r.url()).pathname==='/api/v1/janji-temu');
    bookingResponse.catch(()=>{});
    const appointment=await mutation(page,'POST','/janji-temu',()=>button(page,'Lanjutkan'));
    report.bookingHttpStatus=(await bookingResponse).status();assert.equal(report.bookingHttpStatus,201);
    assert.equal(appointment.slotPraktikId,f.slotId);assert.ok(appointment.tiket?.id);assert.notEqual(appointment.id,appointment.tiket.id);
    await expect(page.getByRole('button',{name:'Lihat tiket / QR',exact:true})).toBeEnabled();
    await page.screenshot({path:path.join(screenshots,'doctor-schedule-booked-web.png')});
    report.appointment=true;report.distinctIds=true;report.ownedTicket=true;
    assert.equal(errors.length,0,'Browser runtime errors');
    fs.writeFileSync(path.resolve(__dirname,'../../../docs/frontend/doctor-schedule-web-qa.json'),JSON.stringify(report,null,2)+'\n');
    console.log('Doctor schedule Web: PASS '+JSON.stringify(report));
  }catch(e){
    if(page&&!page.isClosed()){
      await page.screenshot({path:path.join(root,'doctor-schedule-failure.png')}).catch(()=>{});
      console.error('Doctor QA semantics: '+JSON.stringify(await page.locator('[aria-label]').evaluateAll(ns=>ns.map(n=>({role:n.getAttribute('role'),label:n.getAttribute('aria-label')})))));
    }
    throw e;
  }finally{await browser.close();}
};
