/** Execute relevant realtime suites against validated local test DB; never migrate/reset. */
const path = require('node:path');
const {spawn} = require('node:child_process');
const api = path.resolve(__dirname,'..');
require(path.join(api,'node_modules/dotenv')).config({path:path.resolve(api,'../../.env'),quiet:true});
const {Client} = require(path.join(api,'node_modules/pg'));
(async()=>{
  const source=new URL(process.env.DATABASE_URL);
  if(!['postgres:','postgresql:'].includes(source.protocol)||!['localhost','127.0.0.1'].includes(source.hostname))throw Error('Sumber bukan PostgreSQL lokal');
  source.hostname='127.0.0.1';source.port='5433';source.pathname='/capstone_antrean_test';
  const client=new Client({connectionString:source.toString()});await client.connect();
  try {
    async function snapshot(){
      await client.query('BEGIN READ ONLY');
      try {
        if((await client.query('SELECT current_database() AS db')).rows[0].db!=='capstone_antrean_test')throw Error('Target salah');
        const tables=(await client.query("SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename <> '_prisma_migrations' ORDER BY tablename")).rows;
        const state={};
        for(const {tablename:t}of tables){if(!/^[a-z_]+$/.test(t))throw Error('Identifier tidak sah');state[t]=(await client.query('SELECT id::text, md5(row_to_json(t)::text) AS hash FROM "'+t+'" t ORDER BY id')).rows;}
        return state;
      } finally {await client.query('ROLLBACK');}
    }
    const before=await snapshot();console.log('E2E realtime tervalidasi: 127.0.0.1:5433/capstone_antrean_test');
    const code=await new Promise((resolve,reject)=>{
      const child=spawn(process.execPath,['--experimental-vm-modules','node_modules/jest/bin/jest.js','--config','test/jest-e2e.json','--runInBand',
        'patient-realtime.e2e-spec','realtime-room.e2e-spec','display-realtime.e2e-spec','socket-origin.e2e-spec'],
        {cwd:api,stdio:'inherit',windowsHide:true,env:{...process.env,DATABASE_URL:source.toString(),SERVICE_TIME_ZONE:'Asia/Jakarta',CORS_ALLOWED_ORIGINS:'http://localhost:5173,http://127.0.0.1:8080'}});
      child.once('error',reject);child.once('exit',c=>resolve(c??1));
    });
    const after=await snapshot(), preserved=JSON.stringify(before)===JSON.stringify(after);
    console.log(JSON.stringify({recordExisting:Object.values(before).reduce((n,rows)=>n+rows.length,0),dataExistingDanCleanupSesuai:preserved}));
    process.exitCode=preserved?code:1;
  } finally {await client.end();}
})().catch(e=>{console.error('E2E realtime gagal: '+(e.code||e.name));process.exitCode=1;});
