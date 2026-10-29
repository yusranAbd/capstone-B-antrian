const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { observe, errorDetails } = require("./recovery-observer.cjs");
const { hasServerFailure } = require("./recovery-observer.cjs");
test("driver timing retains promise/error identity, restores methods and discards SQL/parameters", async () => {
  const { observePg } = require("./recovery-observer.cjs");
  let release;
  const result = new Promise((resolve) => {
    release = resolve;
  });
  class Client {
    query() {
      return result;
    }
  }
  const failure = Object.assign(new Error("private-value"), { code: "53300" });
  const rejected = Promise.reject(failure);
  rejected.catch(() => {});
  class Pool {
    connect() {
      return rejected;
    }
  }
  const original = Client.prototype.query;
  const observer = observePg({ Client, Pool });
  try {
    assert.equal(
      new Client().query({
        text: "SELECT 'private-sql'",
        values: ["private-value"],
      }),
      result,
    );
    release({ rows: ["private-row"] });
    await result;
    assert.equal(new Pool().connect(), rejected);
    await assert.rejects(rejected, (error) => error === failure);
    assert.equal(observer.report.queries.length, 1);
    assert.equal(observer.report.acquisitions[0].errorCode, "53300");
    assert.equal(JSON.stringify(observer.report).includes("private"), false);
  } finally {
    observer.stop();
  }
  assert.equal(Client.prototype.query, original);
});
test("passing UI scenarios cannot mask HTTP 500/503 or a caught P2028", () => {
  for (const status of [500, 503])
    assert.equal(
      hasServerFailure({ requests: [{ status }], transactions: [] }),
      true,
    );
  assert.equal(
    hasServerFailure({
      requests: [{ status: 200 }],
      transactions: [{ queries: [{ error: { code: "P2028" } }] }],
    }),
    true,
  );
  assert.equal(
    hasServerFailure({
      requests: [{ status: 401 }, { status: 200 }],
      transactions: [],
    }),
    false,
  );
});
test("teardown drain waits for an admitted transaction without retrying it", async () => {
  process.env.QUEUEB_QA_EVIDENCE_DIR = path.resolve(
    __dirname,
    "../build/recovery-observer-test",
  );
  let release,
    entered,
    calls = 0;
  const gate = new Promise((resolve) => {
    release = resolve;
  });
  const start = new Promise((resolve) => {
    entered = resolve;
  });
  const client = {
    $transaction: async (callback) => {
      calls++;
      return callback({});
    },
  };
  const observer = observe(client);
  const operation = client.$transaction(async () => {
    entered();
    await gate;
    return "committed";
  });
  await start;
  let drained = false;
  const drain = observer.drain().then(() => {
    drained = true;
  });
  await Promise.resolve();
  assert.equal(drained, false);
  release();
  assert.equal(await operation, "committed");
  await drain;
  assert.equal(calls, 1);
  assert.equal(drained, true);
  observer.finish();
});
test("observer preserves callback result, delegate binding, transaction options and error identity without storing arguments", async () => {
  const dir = path.resolve(__dirname, "../build/recovery-observer-test");
  process.env.QUEUEB_QA_EVIDENCE_DIR = dir;
  const options = { isolationLevel: "RepeatableRead", timeout: 5000 };
  const args = { where: { email: "private@example.test" } };
  let calls = 0;
  const failure = Object.assign(
    new Error("Transaction API error: expired after 5001 ms"),
    {
      code: "P2028",
      meta: { error: "5000 ms budget; 5001 ms elapsed", password: "secret" },
    },
  );
  const delegate = {
    async findMany(value) {
      assert.equal(this, delegate);
      assert.equal(value, args);
      calls++;
      if (calls === 2) throw failure;
      return [1];
    },
  };
  const prisma = {
    async $transaction(callback, config) {
      assert.equal(config, options);
      return callback({ tiketAntrean: delegate });
    },
  };
  const observer = observe(prisma);
  observer.phase("browser");
  try {
    assert.deepEqual(
      await prisma.$transaction(
        (tx) => tx.tiketAntrean.findMany(args),
        options,
      ),
      [1],
    );
    await assert.rejects(
      prisma.$transaction((tx) => tx.tiketAntrean.findMany(args), options),
      (error) => error === failure,
    );
  } finally {
    observer.finish();
  }
  const text = fs.readFileSync(path.join(dir, "transactions.json"), "utf8"),
    report = JSON.parse(text);
  assert.equal(calls, 2);
  assert.equal(report.transactions.length, 2);
  assert.equal(report.transactions[1].error.code, "P2028");
  assert.equal(
    report.transactions[1].queries[0].operation,
    "tiketAntrean.findMany",
  );
  assert.equal(text.includes("private@example.test"), false);
  assert.equal(text.includes("password"), false);
});
test("error diagnostics redact connection strings, JWT, QR, email, ids and invocation arguments", () => {
  const e = Object.assign(
    new Error(
      "Invalid invocation({ password: 'secret' })\nTransaction API error: expired postgres://user:password@127.0.0.1/db",
    ),
    {
      code: "P2028",
      meta: {
        error:
          "Transaction closed for a@test.local 11111111-1111-4111-8111-111111111111",
      },
    },
  );
  const output = JSON.stringify(errorDetails(e));
  assert.ok(output.includes("expired"));
  for (const privateValue of ["password", "secret", "a@test.local", "11111111"])
    assert.equal(output.includes(privateValue), false);
});
