// Same compiler outputs only; historical QA screenshots in build/web are excluded.
const fs = require("node:fs"),
  path = require("node:path"),
  crypto = require("node:crypto"),
  zlib = require("node:zlib");
const stage = process.argv[2];
if (!["before", "after"].includes(stage)) throw Error("before|after");
const root = path.resolve("apps/client/build/web");
const roots = new Set([
  "main.dart.js",
  "flutter.js",
  "flutter_bootstrap.js",
  "flutter_service_worker.js",
  "index.html",
  "manifest.json",
  "version.json",
  "favicon.png",
]);
const directories = new Set(["assets", "canvaskit", "icons"]);
const files = fs
  .readdirSync(root, { recursive: true })
  .filter((f) => fs.statSync(path.join(root, f)).isFile());
const compiler = files.filter(
  (f) => roots.has(f) || directories.has(f.split(/[\\/]/)[0]),
);
const hash = (b) => crypto.createHash("sha256").update(b).digest("hex");
const js = fs.readFileSync(path.join(root, "main.dart.js"));
const apk = fs.readFileSync(
  "apps/client/build/app/outputs/flutter-apk/app-debug.apk",
);
const report = {
  stage,
  measuredAt: new Date().toISOString(),
  method:
    "uncompressed on-disk compiler Web files; assets/canvaskit/icons + named root files; APK debug lib/main.dart, same QA URL/timezone; gzip9 is computed, not measured network transfer",
  web: {
    bytes: compiler.reduce(
      (n, f) => n + fs.statSync(path.join(root, f)).size,
      0,
    ),
    files: compiler.length,
    mainJsBytes: js.length,
    mainJsSha256: hash(js),
    mainJsGzip9Bytes: zlib.gzipSync(js, { level: 9 }).length,
    excludedHistoricalRootFiles: files.filter((f) => !compiler.includes(f)),
  },
  apk: { bytes: apk.length, sha256: hash(apk) },
};
fs.writeFileSync(
  `docs/frontend/cleanup-evidence/${stage}-artifacts.json`,
  JSON.stringify(report, null, 2) + "\n",
);
console.log(
  JSON.stringify({
    ...report,
    web: {
      ...report.web,
      excludedHistoricalRootFiles:
        report.web.excludedHistoricalRootFiles.length,
    },
  }),
);
