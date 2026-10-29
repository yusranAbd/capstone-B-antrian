/** Instrumentation on an explicitly selected emulator. run-live owns DB cleanup.
 * Temporary loopback fixture endpoint; never writes credentials/QR to disk.
 */
const http = require("node:http"),
  fs = require("node:fs"),
  path = require("node:path");
const { spawn, execFileSync } = require("node:child_process");
module.exports = async function androidFinal(f, clientPath) {
  const device = process.env.FLUTTER_ANDROID_DEVICE;
  const sdk = process.env.FLUTTER_SDK_ROOT;
  const adb = process.env.ADB_PATH;
  if (!/^emulator-\d+$/.test(device || "") || !sdk || !adb)
    throw Error("Explicit emulator, Flutter SDK and ADB paths required");
  const dart = path.join(
    sdk,
    "bin/cache/dart-sdk/bin",
    process.platform === "win32" ? "dart.exe" : "dart",
  );
  const flutter = path.join(sdk, "bin/cache/flutter_tools.snapshot");
  if (!fs.existsSync(dart) || !fs.existsSync(flutter))
    throw Error("Flutter SDK unavailable");
  const runAdb = (args) =>
    execFileSync(adb, ["-s", device, ...args], {
      encoding: "utf8",
      windowsHide: true,
    }).trim();
  if (
    runAdb(["get-state"]) !== "device" ||
    runAdb(["shell", "getprop", "sys.boot_completed"]) !== "1"
  )
    throw Error("Emulator not ready");
  const selectedDevice = JSON.parse(
    execFileSync(
      dart,
      [flutter, "--no-version-check", "devices", "--machine"],
      { cwd: clientPath, encoding: "utf8", windowsHide: true },
    ),
  ).find((d) => d.id === device);
  if (!selectedDevice?.isSupported)
    throw Error("Selected emulator is unsupported by this Flutter SDK");
  const report = {
    environment: "Android emulator / real local NestJS + PostgreSQL test",
    startedAt: new Date().toISOString(),
    android: runAdb(["shell", "getprop", "ro.build.version.release"]),
    sdk: runAdb(["shell", "getprop", "ro.build.version.sdk"]),
    abi: runAdb(["shell", "getprop", "ro.product.cpu.abi"]),
    model: runAdb(["shell", "getprop", "ro.product.model"]),
    physicalCameraVerified: false,
    physicalDeviceVerified: false,
    uiLogoutVerified: false,
  };
  const accounts = Object.fromEntries(
    ["admin", "doctor", "petugas", "patient1", "patient2"].map((k) => [
      k,
      f[k],
    ]),
  );
  const server = http.createServer((req, res) => {
    if (req.method === "GET" && req.url === "/fixture") {
      res.setHeader("Content-Type", "application/json");
      res.setHeader("Cache-Control", "no-store");
      res.end(JSON.stringify(accounts));
    } else {
      res.writeHead(404);
      res.end();
    }
  });
  const owned = [];
  try {
    const existing = runAdb(["reverse", "--list"]);
    for (const port of [3001, 3002]) {
      if (existing.includes("tcp:" + port + " "))
        throw Error("Existing ADB mapping; refuse to overwrite");
      runAdb(["reverse", "tcp:" + port, "tcp:" + port]);
      owned.push(port);
    }
    await new Promise((resolve, reject) => {
      server.once("error", reject);
      server.listen(3002, "127.0.0.1", resolve);
    });
    const args = [
      flutter,
      "--no-version-check",
      "test",
      "integration_test/final_qa_smoke_test.dart",
      "--no-pub",
      "-d",
      device,
      "--dart-define=API_BASE_URL=http://127.0.0.1:3001/api/v1",
      "--dart-define=SERVICE_TIME_ZONE=Asia/Jakarta",
      "--reporter",
      "expanded",
    ];
    const start = Date.now();
    const result = await new Promise((resolve, reject) => {
      const child = spawn(dart, args, {
        cwd: clientPath,
        env: process.env,
        windowsHide: true,
        stdio: ["ignore", "pipe", "pipe"],
      });
      let output = "";
      child.stdout.on("data", (v) => (output += v));
      child.stderr.on("data", (v) => (output += v));
      child.once("error", reject);
      child.once("exit", (code) => resolve({ code: code ?? 1, output }));
    });
    report.exit = result.code;
    report.seconds = Number(((Date.now() - start) / 1000).toFixed(1));
    report.summary = result.output
      .split(/\r?\n/)
      .filter(
        (l) => l.includes("Final Android QA ") || /All tests passed!/.test(l),
      );
    report.compilerDiagnostics = result.output
      .split(/\r?\n/)
      .filter((l) =>
        /^integration_test\/final_qa_smoke_test\.dart:\d+:\d+: Error:/.test(l),
      );
    report.finishedAt = new Date().toISOString();
    const output = path.resolve(clientPath, "../../docs/qa/evidence");
    fs.mkdirSync(output, { recursive: true });
    fs.writeFileSync(
      path.join(output, "android-final.json"),
      JSON.stringify(report, null, 2) + "\n",
    );
    console.log("Final Android QA result: " + JSON.stringify(report));
    if (result.code !== 0)
      throw Error(
        "Android instrumentation failed; raw secret-bearing diagnostics discarded",
      );
  } finally {
    if (server.listening) await new Promise((resolve) => server.close(resolve));
    for (const port of owned) runAdb(["reverse", "--remove", "tcp:" + port]);
  }
};
