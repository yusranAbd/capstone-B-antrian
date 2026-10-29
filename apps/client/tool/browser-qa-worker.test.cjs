const test = require("node:test"),
  assert = require("node:assert/strict"),
  fs = require("node:fs"),
  path = require("node:path");
const { runBrowserWorker } = require("./browser-qa-worker.cjs");
test("worker exit waits for ownership/reconnect ACK; denied RPC cannot register unrelated ids", async () => {
  const file = path.resolve(__dirname, "../build/recovery-ipc-fixture.cjs"),
    id = "11111111-1111-4111-8111-111111111111";
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(
    file,
    `process.once('message',()=>{process.send({type:'rpc',id:1,method:'ownServices',args:['invalid']});process.on('message',m=>{if(m.id===1){if(!m.failed)process.exit(9);process.send({type:'rpc',id:2,method:'ownServices',args:['${id}']});}if(m.id===2)process.send({type:'rpc',id:3,method:'disconnectDisplay',args:['${id}']});if(m.id===3){process.exitCode=m.value===1?1:9;process.disconnect();}});});`,
  );
  const fixture = {
    extraServiceIds: [],
    disconnectDisplay(value) {
      assert.equal(value, id);
      return 1;
    },
  };
  try {
    await assert.rejects(runBrowserWorker(fixture, file), {
      code: "BROWSER_WORKER_FAILED",
      exitCode: 1,
    });
    assert.deepEqual(fixture.extraServiceIds, [id]);
  } finally {
    fs.rmSync(file, { force: true });
  }
});
