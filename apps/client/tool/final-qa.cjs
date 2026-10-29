/** Reproducible QA entry point: no seed/migration, no development DB writes.
 * node tool/final-qa.cjs unit|backend|browser|android [backend-suite]
 * Build API and Web (API_BASE_URL=http://127.0.0.1:3001/api/v1) beforehand.
 * Output is an allowlisted summary; raw test errors may contain credentials.
 */
const path = require("node:path");
const fs = require("node:fs");
const { spawn } = require("node:child_process");
const api = path.resolve(__dirname, "../../api");
const output = path.resolve(__dirname, "../../../docs/qa/evidence");
const mode = process.argv[2];
const suite = process.argv[3];
if (suite && (mode !== "backend" || !/^[a-z0-9-]+$/.test(suite)))
  throw Error("Invalid QA suite");
if (!["unit", "backend", "browser", "android"].includes(mode))
  throw Error("Use unit|backend|browser|android");
require(path.join(api, "node_modules/dotenv")).config({
  path: path.resolve(api, "../../.env"),
  quiet: true,
});
const source = new URL(process.env.DATABASE_URL);
if (
  !["postgres:", "postgresql:"].includes(source.protocol) ||
  !["localhost", "127.0.0.1"].includes(source.hostname)
)
  throw Error("Local PostgreSQL required");
// Build a new URL: source search parameters must not override host/database.
const target = new URL("postgresql://127.0.0.1:5433/capstone_antrean_test");
target.username = source.username;
target.password = source.password;
const env = {
  ...process.env,
  DATABASE_URL:
    mode === "unit"
      ? "postgresql://invalid:invalid@127.0.0.1:1/blocked_unit_test"
      : target.toString(),
  SERVICE_TIME_ZONE: "Asia/Jakarta",
  NODE_ENV: "test",
};
if (mode !== "unit") {
  env.DISPLAY_PATIENT_NAME_MODE = "SAMAR";
  env.DISPLAY_FULL_NAMES_APPROVED = "false";
}
async function guard() {
  const { Client } = require(path.join(api, "node_modules/pg"));
  const db = new Client({
    connectionString: target.toString(),
    connectionTimeoutMillis: 5000,
  });
  try {
    await db.connect();
    await db.query("BEGIN READ ONLY");
    const actual = (
      await db.query(
        "SELECT current_database() AS db, inet_server_port() AS port",
      )
    ).rows[0];
    if (
      actual.db !== "capstone_antrean_test" ||
      ![5432, 5433].includes(actual.port)
    )
      throw Error("Wrong database");
    const applied = new Set(
      (
        await db.query(
          "SELECT migration_name FROM _prisma_migrations WHERE finished_at IS NOT NULL AND rolled_back_at IS NULL",
        )
      ).rows.map((r) => r.migration_name),
    );
    if (
      fs
        .readdirSync(path.join(api, "prisma/migrations"), {
          withFileTypes: true,
        })
        .some((d) => d.isDirectory() && !applied.has(d.name))
    )
      throw Error("Pending migration; stop without changing schema");
    await db.query("ROLLBACK");
  } finally {
    await db.end();
  }
}
async function run(args, cwd) {
  const start = Date.now();
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, args, {
      cwd,
      env,
      windowsHide: true,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let text = "";
    child.stdout.on("data", (b) => (text += b));
    child.stderr.on("data", (b) => (text += b));
    child.once("error", reject);
    child.once("exit", (code) => {
      const clean = text.replace(/\x1b\[[0-9;]*m/g, "");
      const lines = clean.split(/\r?\n/);
      const summary = lines.filter((l) =>
        /^(Test Suites:|Tests:|Time:|# tests |# pass |# fail |Target tervalidasi:|Target integrasi Flutter tervalidasi:|Final QA PASS:|Final QA failed phase:|Integrasi Flutter gagal:)/.test(
          l,
        ),
      );
      if (process.env.QA_CONTROL_DIAGNOSTICS === "true") {
        summary.push(
          ...lines.filter((l) => l.startsWith("Final QA native diagnostics:")),
        );
        summary.push(
          ...lines.filter((l) => l.startsWith("Final QA scan diagnostics:")),
        );
        summary.push(
          ...lines.filter((l) =>
            /^\s+at .*browser-final-e2e\.cjs:\d+:\d+\)?$/.test(l),
          ),
        );
      }
      const suites = lines
        .filter((l) =>
          /^(PASS|FAIL) (test\/|src\/)[a-zA-Z0-9_./-]+\.(spec|e2e-spec)\.ts/.test(
            l,
          ),
        )
        .map((l) => l.split(/\s+\(/)[0]);
      const fingerprints = lines
        .filter((l) => /^\{"(recordExisting|dataExisting)":/.test(l))
        .map((l) => JSON.parse(l));
      resolve({
        command: ["node", ...args].join(" "),
        exit: code ?? 1,
        seconds: Number(((Date.now() - start) / 1000).toFixed(1)),
        summary,
        suites,
        fingerprints,
      });
    });
  });
}
(async () => {
  if (mode !== "unit") await guard();
  fs.mkdirSync(output, { recursive: true });
  const report = {
    mode,
    startedAt: new Date().toISOString(),
    target:
      mode === "unit"
        ? "dummy localhost port 1 (no database)"
        : "127.0.0.1:5433/capstone_antrean_test",
    results: [],
  };
  const commands =
    mode === "unit"
      ? [
          [
            ["--test", "--test-reporter=tap", "tool/development-data.test.cjs"],
            api,
          ],
          [
            [
              "--experimental-vm-modules",
              "node_modules/jest/bin/jest.js",
              "--runInBand",
            ],
            api,
          ],
        ]
      : mode === "backend"
        ? [
            [
              [
                "test/run-doctor-portal.cjs",
                suite ? "--suite=" + suite : "--all",
              ],
              api,
            ],
          ]
        : [
            [
              [
                path.join(__dirname, "run-live.cjs"),
                mode === "android" ? "--final-android-qa" : "--final-e2e-qa",
              ],
              path.resolve(__dirname, ".."),
            ],
          ];
  for (const [args, cwd] of commands) {
    const result = await run(args, cwd);
    report.results.push(result);
    console.log(JSON.stringify(result));
  }
  report.finishedAt = new Date().toISOString();
  fs.writeFileSync(
    path.join(output, mode + (suite ? "-" + suite : "") + "-execution.json"),
    JSON.stringify(report, null, 2) + "\n",
  );
  process.exitCode = report.results.some((r) => r.exit !== 0) ? 1 : 0;
})().catch((error) => {
  console.error("Guarded final QA failed: " + (error.code || error.name));
  process.exitCode = 1;
});
