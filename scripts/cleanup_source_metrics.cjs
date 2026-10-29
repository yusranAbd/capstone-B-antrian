// Read-only working-tree measurement of Git-tracked Flutter Dart source.
const fs = require("node:fs"),
  crypto = require("node:crypto"),
  { execFileSync } = require("node:child_process");
const stage = process.argv[2];
if (!["before", "after"].includes(stage)) throw Error("before|after");
const files = execFileSync(
  "git",
  [
    "ls-files",
    "apps/client/lib",
    "apps/client/test",
    "apps/client/integration_test",
  ],
  { encoding: "utf8" },
)
  .trim()
  .split(/\r?\n/)
  .filter((p) => p.endsWith(".dart"));
function measure(paths) {
  return paths.reduce(
    (result, p) => {
      const bytes = fs.readFileSync(p),
        text = bytes.toString("utf8");
      result.files++;
      result.bytes += bytes.length;
      const lines = text.replace(/\r\n/g, "\n").split("\n");
      result.physicalLines += lines.length - (lines.at(-1) === "" ? 1 : 0);
      return result;
    },
    { files: 0, physicalLines: 0, bytes: 0 },
  );
}
const protectedFiles = [
  "README.md",
  "apps/client/lib/src/doctor_dashboard.dart",
  "apps/client/lib/src/doctor_visual.dart",
  "apps/client/test/doctor_visual_refresh_test.dart",
];
const report = {
  head: execFileSync("git", ["rev-parse", "HEAD"], { encoding: "utf8" }).trim(),
  measuredAt: new Date().toISOString(),
  scope:
    "git ls-files lib/test/integration_test; actual working-tree bytes; physical lines normalized CRLF, terminal empty line excluded",
  all: measure(files),
  production: measure(files.filter((p) => p.startsWith("apps/client/lib/"))),
  tests: measure(files.filter((p) => p.startsWith("apps/client/test/"))),
  integrationTests: measure(
    files.filter((p) => p.startsWith("apps/client/integration_test/")),
  ),
  protectedHashes: Object.fromEntries(
    protectedFiles.map((p) => [
      p,
      crypto.createHash("sha256").update(fs.readFileSync(p)).digest("hex"),
    ]),
  ),
  files,
};
const destination = `docs/frontend/cleanup-evidence/${stage}-source.json`;
if (stage === "before" && fs.existsSync(destination))
  throw Error("Preserve existing before baseline");
fs.writeFileSync(destination, JSON.stringify(report, null, 2) + "\n");
console.log(JSON.stringify({ ...report, files: files.length }));
