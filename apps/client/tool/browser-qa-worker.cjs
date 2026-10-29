/** Keep Playwright/fixture video work outside the Nest/Prisma event loop.
 * Credentials travel through IPC only. Parent acknowledges fixture ownership.
 */
const { fork } = require("node:child_process");
function runBrowserWorker(fixture, workerFile = __filename) {
  return new Promise((resolve, reject) => {
    const child = fork(workerFile, [], { silent: true, windowsHide: true });
    child.stdout.on("data", (b) => process.stdout.write(b));
    child.stderr.on("data", (b) => process.stderr.write(b));
    child.on("message", (message) => {
      if (message.type !== "rpc") return;
      try {
        let value;
        if (
          message.method === "disconnectDisplay" &&
          /^[0-9a-f-]{36}$/i.test(message.args?.[0])
        )
          value = fixture.disconnectDisplay(message.args[0]);
        else if (
          message.method === "ownServices" &&
          Array.isArray(message.args) &&
          message.args.every((id) => /^[0-9a-f-]{36}$/i.test(id))
        ) {
          fixture.extraServiceIds.push(...message.args);
          value = true;
        } else throw Error("RPC denied");
        child.send({ type: "rpc-result", id: message.id, value });
      } catch {
        child.send({ type: "rpc-result", id: message.id, failed: true });
      }
    });
    child.once("error", reject);
    child.once("close", (code) =>
      code === 0
        ? resolve()
        : reject(
            Object.assign(new Error("Browser worker failed"), {
              code: "BROWSER_WORKER_FAILED",
              exitCode: code,
            }),
          ),
    );
    child.send({
      type: "start",
      fixture: Object.fromEntries(
        Object.entries(fixture).filter(([, v]) => typeof v !== "function"),
      ),
    });
  });
}
async function worker(fixture) {
  let sequence = 0;
  const waiting = new Map(),
    ownership = [];
  process.on("message", (message) => {
    if (message.type !== "rpc-result") return;
    const pending = waiting.get(message.id);
    if (!pending) return;
    clearTimeout(pending.timer);
    waiting.delete(message.id);
    message.failed
      ? pending.reject(Error("Parent RPC denied"))
      : pending.resolve(message.value);
  });
  const rpc = (method, args) =>
    new Promise((resolve, reject) => {
      const id = ++sequence,
        timer = setTimeout(() => {
          waiting.delete(id);
          reject(Error("Parent RPC deadline"));
        }, 10000);
      waiting.set(id, { resolve, reject, timer });
      process.send({ type: "rpc", id, method, args });
    });
  fixture.disconnectDisplay = (id) => rpc("disconnectDisplay", [id]);
  fixture.extraServiceIds = new Proxy(fixture.extraServiceIds, {
    get(target, key) {
      if (key !== "push") return Reflect.get(target, key);
      return (...ids) => {
        const length = Array.prototype.push.apply(target, ids);
        ownership.push(rpc("ownServices", ids));
        return length;
      };
    },
  });
  let failed = false;
  try {
    await require("./browser-smoke.cjs")(fixture);
  } catch (error) {
    failed = true;
    console.error("Browser worker: " + (error.code || error.name));
  } finally {
    await Promise.all(ownership);
    process.exitCode = failed ? 1 : 0;
    process.disconnect();
  }
}
module.exports = { runBrowserWorker };
if (require.main === module)
  process.once("message", (message) => {
    if (message.type !== "start") throw Error("Start required");
    worker(message.fixture).catch(() => {
      process.exitCode = 1;
      process.disconnect();
    });
  });
