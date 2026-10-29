/** Test-only transaction diagnostics. Never logs arguments, bindings or rows. */
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const { AsyncLocalStorage } = require("node:async_hooks");
const { monitorEventLoopDelay } = require("node:perf_hooks");
const os = require("node:os");
const root = path.resolve(__dirname, "../../..");
function observePg(pg, context) {
  const report = { queries: [], acquisitions: [] };
  const originals = [];
  function instrument(prototype, method, records, describe) {
    const original = prototype[method];
    function wrapped(...args) {
      // The adapter uses promise overloads. Leave callback/stream overloads alone.
      if (args.some((arg) => typeof arg === "function"))
        return original.apply(this, args);
      const start = performance.now();
      const record = {
        at: Date.now(),
        requestId: context?.getStore()?.id,
        ...describe.call(this, args),
      };
      const result = original.apply(this, args);
      if (result && typeof result.then === "function") {
        records.push(record);
        result.then(
          () => {
            record.durationMs = Math.round(performance.now() - start);
          },
          (error) => {
            record.durationMs = Math.round(performance.now() - start);
            record.errorCode = /^[A-Z0-9]{5}$/.test(error.code || "")
              ? error.code
              : "other";
          },
        );
      }
      return result;
    }
    prototype[method] = wrapped;
    originals.push(() => {
      if (prototype[method] === wrapped) prototype[method] = original;
    });
  }
  instrument(pg.Client.prototype, "query", report.queries, function (args) {
    const sql = typeof args[0] === "string" ? args[0] : args[0]?.text;
    return {
      backendPid: this.processID,
      operation: (sql || "").match(/^\s*(\w+)/)?.[1]?.toUpperCase(),
      queryHash: crypto
        .createHash("sha256")
        .update(sql || "")
        .digest("hex")
        .slice(0, 16),
    };
  });
  instrument(pg.Pool.prototype, "connect", report.acquisitions, function () {
    return {
      total: this.totalCount,
      idle: this.idleCount,
      waiting: this.waitingCount,
    };
  });
  return { report, stop: () => originals.forEach((restore) => restore()) };
}
function scrub(value) {
  return String(value)
    .replace(/postgres(?:ql)?:\/\/[^\s'"`]+/gi, "<database-url>")
    .replace(/\beyJ[\w-]+\.[\w-]+\.[\w-]+/g, "<jwt>")
    .replace(/\bSQ1\.[\w-]+/g, "<qr>")
    .replace(/[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}/gi, "<email>")
    .replace(/[0-9a-f]{8}-[0-9a-f-]{27,}/gi, "<id>");
}
function errorDetails(error) {
  const message = String(error.message || "");
  const marker = message.search(/Transaction (?:API error|already closed):/);
  return {
    name: error.name,
    code: error.code,
    // Invocation arguments preceding the transaction message are omitted.
    message:
      marker >= 0
        ? scrub(message.slice(marker))
        : "Non-transaction error; arguments omitted",
    meta: Object.fromEntries(
      Object.entries(error.meta || {})
        .filter(([k]) =>
          ["modelName", "error", "timeout", "maxWait", "code"].includes(k),
        )
        .map(([k, v]) => [k, scrub(v)]),
    ),
    stack: String(error.stack || "")
      .split("\n")
      .filter(
        (line) =>
          /^\s+at /.test(line) &&
          /(?:apps[\\/]api[\\/]dist|recovery-observer\.cjs)/.test(line),
      )
      .map(scrub),
  };
}
function outputDirectory() {
  const output = path.resolve(process.env.QUEUEB_QA_EVIDENCE_DIR || "");
  if (
    !process.env.QUEUEB_QA_EVIDENCE_DIR ||
    !output.startsWith(root + path.sep)
  )
    throw Error("Explicit repository evidence directory required");
  fs.mkdirSync(output, { recursive: true });
  return output;
}
function observe(prisma) {
  const { defer, finalize } = require(
    path.join(root, "apps/api/node_modules/rxjs"),
  );
  const transactions = new Set(),
    handlers = new Set();
  const context = new AsyncLocalStorage();
  const driver = observePg(
    require(path.join(root, "apps/api/node_modules/pg")),
    context,
  );
  const lag = monitorEventLoopDelay({ resolution: 20 });
  lag.enable();
  const report = {
    transactions: [],
    requests: [],
    maxActiveRequests: 0,
    phase: "setup",
    driver: driver.report,
    resources: [],
  };
  let previousCpu = process.cpuUsage(),
    previousTime = performance.now();
  const resourceTimer = setInterval(() => {
    const now = performance.now(),
      cpu = process.cpuUsage(),
      memory = process.memoryUsage();
    report.resources.push({
      at: Date.now(),
      intervalMs: Math.round(now - previousTime),
      serverCpuPercent: Math.round(
        (cpu.user - previousCpu.user + cpu.system - previousCpu.system) /
          ((now - previousTime) * 10),
      ),
      freeHostMiB: Math.round(os.freemem() / 1048576),
      rssMiB: Math.round(memory.rss / 1048576),
    });
    previousCpu = cpu;
    previousTime = now;
  }, 1000);
  resourceTimer.unref();
  let phase = "setup",
    active = 0,
    sequence = 0;
  const original = prisma.$transaction.bind(prisma);
  prisma.$transaction = async (callback, options) => {
    if (typeof callback !== "function") return original(callback, options);
    const started = performance.now();
    const record = {
      at: Date.now(),
      id: ++sequence,
      phase,
      request: context.getStore(),
      options: options || { timeout: "Prisma default" },
      site: new Error().stack
        .split("\n")
        .filter((l) => /apps[\\/]api[\\/]dist/.test(l))
        .map(scrub),
      queries: [],
    };
    report.transactions.push(record);
    const delegateCache = new Map();
    const proxy = (tx) =>
      new Proxy(tx, {
        get(target, key) {
          const value = Reflect.get(target, key);
          const wrap =
            (owner, method, fn) =>
            (...args) => {
              const q = {
                operation: String(method),
                startedMs: Math.round(performance.now() - started),
              };
              record.queries.push(q);
              const start = performance.now();
              // Return the same outcome/error; no retry and no transaction option override.
              return Promise.resolve()
                .then(() => fn.apply(owner, args))
                .then(
                  (result) => {
                    q.durationMs = Math.round(performance.now() - start);
                    return result;
                  },
                  (error) => {
                    q.durationMs = Math.round(performance.now() - start);
                    q.error = errorDetails(error);
                    throw error;
                  },
                );
            };
          if (typeof value === "function") return wrap(target, key, value);
          if (
            !value ||
            typeof value !== "object" ||
            String(key).startsWith("$")
          )
            return value;
          if (!delegateCache.has(key))
            delegateCache.set(
              key,
              new Proxy(value, {
                get(model, operation) {
                  const fn = Reflect.get(model, operation);
                  return typeof fn === "function"
                    ? wrap(model, `${String(key)}.${String(operation)}`, fn)
                    : fn;
                },
              }),
            );
          return delegateCache.get(key);
        },
      });
    let operation;
    try {
      operation = original((tx) => callback(proxy(tx)), options);
      transactions.add(operation);
      return await operation;
    } catch (error) {
      record.error = errorDetails(error);
      throw error;
    } finally {
      transactions.delete(operation);
      record.durationMs = Math.round(performance.now() - started);
    }
  };
  return {
    interceptor: {
      intercept(_context, next) {
        let done;
        const ticket = new Promise((resolve) => {
          done = resolve;
        });
        handlers.add(ticket);
        return defer(() => next.handle()).pipe(
          finalize(() => {
            handlers.delete(ticket);
            done();
          }),
        );
      },
    },
    async drain() {
      while (transactions.size || handlers.size)
        await Promise.allSettled([...transactions, ...handlers]);
    },
    middleware(req, res, next) {
      const request = {
        at: Date.now(),
        id: report.requests.length + 1,
        method: req.method,
        path: scrub(req.path),
        phase,
      };
      const start = performance.now();
      report.requests.push(request);
      active++;
      report.maxActiveRequests = Math.max(report.maxActiveRequests, active);
      res.once("close", () => {
        active--;
        request.status = res.statusCode;
        request.durationMs = Math.round(performance.now() - start);
      });
      context.run(request, next);
    },
    phase(value) {
      phase = value;
    },
    finish() {
      clearInterval(resourceTimer);
      driver.stop();
      lag.disable();
      report.eventLoopDelayMs = {
        max: lag.max / 1e6,
        mean: lag.mean / 1e6,
        p99: lag.percentile(99) / 1e6,
      };
      report.pendingAtFinish = active;
      fs.writeFileSync(
        path.join(outputDirectory(), "transactions.json"),
        JSON.stringify(report, null, 2) + "\n",
      );
      return report;
    },
  };
}
async function readDatabase(url, name) {
  const { Client } = require(path.join(root, "apps/api/node_modules/pg"));
  const target = new URL(`postgresql://127.0.0.1:5433/${name}`);
  target.username = url.username;
  target.password = url.password;
  if (!["capstone_antrean", "capstone_antrean_test"].includes(name))
    throw Error("DB denied");
  const client = new Client({
    connectionString: target.toString(),
    application_name: "queueb_recovery_readonly",
  });
  await client.connect();
  try {
    await client.query("BEGIN READ ONLY");
    const identity = (
      await client.query(
        "SELECT current_database() db, inet_server_port() port, current_setting('transaction_read_only') readonly",
      )
    ).rows[0];
    if (
      identity.db !== name ||
      ![5432, 5433].includes(identity.port) ||
      identity.readonly !== "on"
    )
      throw Error("Wrong read-only target");
    const tables = (
      await client.query(
        "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename",
      )
    ).rows;
    const fingerprint = {};
    for (const { tablename: table } of tables) {
      if (!/^[a-z_]+$/.test(table)) throw Error("Bad identifier");
      fingerprint[table] = (
        await client.query(
          `SELECT count(*)::int count, md5(string_agg(md5(row_to_json(t)::text), ',' ORDER BY md5(row_to_json(t)::text))) digest FROM "${table}" t`,
        )
      ).rows[0];
    }
    const settings = (
      await client.query(
        "SELECT name, setting FROM pg_settings WHERE name IN ('statement_timeout','lock_timeout','idle_in_transaction_session_timeout','max_connections') ORDER BY name",
      )
    ).rows;
    const connections = (
      await client.query(
        "SELECT state, wait_event_type, wait_event, count(*)::int count FROM pg_stat_activity WHERE datname=current_database() AND pid<>pg_backend_pid() GROUP BY state,wait_event_type,wait_event",
      )
    ).rows;
    await client.query("ROLLBACK");
    return { identity, fingerprint, settings, connections };
  } finally {
    await client.end();
  }
}
async function preflight(stage) {
  if (!["before", "after"].includes(stage)) throw Error("before|after");
  require(path.join(root, "apps/api/node_modules/dotenv")).config({
    path: path.join(root, ".env"),
    quiet: true,
  });
  const url = new URL(process.env.DATABASE_URL);
  if (!["127.0.0.1", "localhost"].includes(url.hostname))
    throw Error("Local source required");
  const output = outputDirectory();
  const databases = {};
  for (const name of ["capstone_antrean", "capstone_antrean_test"])
    databases[name] = await readDatabase(url, name);
  const baseline = require(
    path.join(root, "docs/frontend/cleanup-evidence/before-source.json"),
  );
  const protectedHashes = Object.fromEntries(
    Object.keys(baseline.protectedHashes).map((p) => [
      p,
      crypto
        .createHash("sha256")
        .update(fs.readFileSync(path.join(root, p)))
        .digest("hex"),
    ]),
  );
  const report = {
    measuredAt: new Date().toISOString(),
    databases,
    protectedHashes,
  };
  if (stage === "after") {
    const before = JSON.parse(
      fs.readFileSync(path.join(output, "safety-before.json")),
    );
    report.databasesUnchanged = Object.keys(databases).every(
      (n) =>
        JSON.stringify(before.databases[n].fingerprint) ===
        JSON.stringify(databases[n].fingerprint),
    );
    report.protectedUnchanged =
      JSON.stringify(before.protectedHashes) ===
      JSON.stringify(protectedHashes);
  }
  const file = path.join(output, `safety-${stage}.json`);
  if (stage === "before" && fs.existsSync(file))
    throw Error("Preserve preflight baseline");
  fs.writeFileSync(file, JSON.stringify(report, null, 2) + "\n");
  console.log(
    JSON.stringify({
      stage,
      databases: Object.keys(databases),
      databasesUnchanged: report.databasesUnchanged,
      protectedUnchanged: report.protectedUnchanged,
    }),
  );
}
function hasServerFailure(report) {
  return (
    report.requests.some((r) => r.status >= 500) ||
    report.transactions.some(
      (t) =>
        t.error?.code === "P2028" ||
        t.queries.some((q) => q.error?.code === "P2028"),
    )
  );
}
module.exports = {
  observe,
  observePg,
  errorDetails,
  scrub,
  readDatabase,
  hasServerFailure,
};
async function watch() {
  require(path.join(root, "apps/api/node_modules/dotenv")).config({
    path: path.join(root, ".env"),
    quiet: true,
  });
  const source = new URL(process.env.DATABASE_URL),
    target = new URL("postgresql://127.0.0.1:5433/capstone_antrean_test");
  if (!["localhost", "127.0.0.1"].includes(source.hostname))
    throw Error("Local source required");
  target.username = source.username;
  target.password = source.password;
  const { Client } = require(path.join(root, "apps/api/node_modules/pg"));
  const db = new Client({
    connectionString: target.toString(),
    application_name: "queueb_recovery_sampler",
  });
  const samples = [];
  await db.connect();
  try {
    await db.query("SET default_transaction_read_only=on");
    const identity = (
      await db.query(
        "SELECT current_database() db, inet_server_port() port, current_setting('transaction_read_only') readonly",
      )
    ).rows[0];
    if (
      identity.db !== "capstone_antrean_test" ||
      ![5432, 5433].includes(identity.port) ||
      identity.readonly !== "on"
    )
      throw Error("Sampler target denied");
    const end = Date.now() + 120000;
    while (Date.now() < end) {
      const rows = (
        await db.query(
          "SELECT pid,state,wait_event_type,wait_event,EXTRACT(EPOCH FROM clock_timestamp()-xact_start)*1000 xact_ms,EXTRACT(EPOCH FROM clock_timestamp()-query_start)*1000 query_ms,query FROM pg_stat_activity WHERE datname=current_database() AND pid<>pg_backend_pid()",
        )
      ).rows;
      samples.push({
        at: Date.now(),
        connections: rows.map(({ query, ...r }) => ({
          ...r,
          queryHash: crypto
            .createHash("sha256")
            .update(query || "")
            .digest("hex")
            .slice(0, 16),
          operation: (query || "").match(/^\s*(\w+)/)?.[1],
          tables: [
            ...new Set(
              (query || "").match(
                /\b(?:tiket_antrean|peristiwa_antrean|jadwal_praktik|pengguna|loket|layanan|perangkat_tampilan|penugasan_petugas)\b/g,
              ) || [],
            ),
          ],
        })),
      });
      await new Promise((resolve) => setTimeout(resolve, 500));
    }
    fs.writeFileSync(
      path.join(outputDirectory(), "postgres-samples.json"),
      JSON.stringify(
        {
          identity,
          method:
            "Read-only 500ms sampling; query text/values discarded, only operation/table/hash retained",
          samples,
        },
        null,
        2,
      ) + "\n",
    );
  } finally {
    await db.end();
  }
}
if (require.main === module)
  (process.argv[2] === "watch" ? watch() : preflight(process.argv[2])).catch(
    (e) => {
      console.error(e.code || e.name);
      process.exitCode = 1;
    },
  );
