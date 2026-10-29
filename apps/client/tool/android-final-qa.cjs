/** Instrumentation on an explicitly selected emulator. run-live owns DB cleanup.
 * Temporary loopback fixture endpoint; never writes credentials/QR to disk.
 */
const http = require("node:http"),
  fs = require("node:fs"),
  path = require("node:path");
const { spawn, execFileSync, execFile } = require("node:child_process");
const crypto = require("node:crypto");
function sourceFingerprint(clientPath) {
  const files = [];
  function visit(dir) {
    for (const e of fs.readdirSync(path.join(clientPath, dir), {
      withFileTypes: true,
    })) {
      const f = path.join(dir, e.name);
      if (e.isDirectory()) visit(f);
      else if (f.endsWith(".dart")) files.push(f);
    }
  }
  visit("lib");
  files.push(
    "integration_test/final_qa_smoke_test.dart",
    "android/app/src/main/AndroidManifest.xml",
    "pubspec.lock",
  );
  const hash = crypto.createHash("sha256");
  for (const f of files.sort()) {
    hash.update(f.replaceAll(path.sep, "/"));
    hash.update(fs.readFileSync(path.join(clientPath, f)));
  }
  return hash.digest("hex");
}
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
  // The outer guarded runner has prepared its unique database fixtures before
  // reaching this hook. A local QA bootstrap can now boot the owned emulator,
  // keeping boot pressure out of the fixture's write transactions.
  if (process.env.QUEUEB_ANDROID_BOOTSTRAP_PS1) {
    const bootstrap = path.resolve(process.env.QUEUEB_ANDROID_BOOTSTRAP_PS1);
    const pwsh = process.env.QUEUEB_QA_PWSH;
    if (
      bootstrap !==
        path.resolve(clientPath, "build/start-routing-emulator.ps1") ||
      !pwsh ||
      path.basename(pwsh).toLowerCase() !== "pwsh.exe" ||
      !fs.existsSync(pwsh)
    )
      throw Error("Invalid owned QA emulator bootstrap");
    await new Promise((resolve, reject) => {
      const boot = spawn(pwsh, ["-NoProfile", "-File", bootstrap], {
        cwd: clientPath,
        windowsHide: true,
        // The emulator outlives this bootstrap. Do not wait for descendants
        // to close inherited output pipes after PowerShell has already exited.
        stdio: "ignore",
      });
      const timeout = setTimeout(() => {
        boot.kill();
        reject(
          Object.assign(Error("QA bootstrap timed out"), {
            code: "QA_EMULATOR_BOOTSTRAP_TIMEOUT",
          }),
        );
      }, 600000);
      boot.once("error", () => {
        clearTimeout(timeout);
        reject(
          Object.assign(Error("QA bootstrap could not start"), {
            code: "QA_EMULATOR_BOOTSTRAP_FAILED",
          }),
        );
      });
      boot.once("exit", (code) => {
        clearTimeout(timeout);
        if (code === 0) resolve();
        else
          reject(
            Object.assign(Error("QA bootstrap failed"), {
              code: "QA_EMULATOR_BOOTSTRAP_FAILED",
            }),
          );
      });
    });
  }
  const runAdb = (args) =>
    execFileSync(adb, ["-s", device, ...args], {
      encoding: "utf8",
      windowsHide: true,
    }).trim();
  const runAdbAsync = (args) =>
    new Promise((resolve, reject) => {
      execFile(
        adb,
        ["-s", device, ...args],
        { encoding: "utf8", windowsHide: true, timeout: 15000 },
        (error, stdout) => (error ? reject(error) : resolve(stdout.trim())),
      );
    });
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
    fixturesPreparedBeforeEmulator: !!process.env.QUEUEB_ANDROID_BOOTSTRAP_PS1,
  };
  fs.writeFileSync(
    path.join(clientPath, "build/routing-android-progress.json"),
    JSON.stringify(
      {
        startedAt: report.startedAt,
        status: "STARTING",
        markers: [],
        diagnostics: [],
      },
      null,
      2,
    ) + "\n",
  );
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
    let args = [
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
    if (process.env.QUEUEB_ANDROID_PREBUILT_APK) {
      const apk = path.resolve(process.env.QUEUEB_ANDROID_PREBUILT_APK);
      if (!apk.startsWith(path.resolve(clientPath, "build") + path.sep))
        throw Error("Prebuilt APK must stay in client/build");
      const metadata = JSON.parse(fs.readFileSync(apk + ".json", "utf8"));
      const sha256 = crypto
        .createHash("sha256")
        .update(fs.readFileSync(apk))
        .digest("hex");
      if (
        metadata.target !== "integration_test/final_qa_smoke_test.dart" ||
        metadata.sha256 !== sha256 ||
        metadata.sourceFingerprint !== sourceFingerprint(clientPath) ||
        report.abi !== "x86_64"
      )
        throw Error("Prebuilt QA APK target/source/ABI mismatch");
      report.runner = "flutter drive / prebuilt integration APK";
      report.prebuilt = { sha256, bytes: fs.statSync(apk).size };
      args = [
        flutter,
        "--no-version-check",
        "drive",
        "--no-pub",
        "--driver=test_driver/final_qa_driver.dart",
        "--target=integration_test/final_qa_smoke_test.dart",
        "--use-application-binary=" + apk,
        "-d",
        device,
      ];
    } else report.runner = "flutter test / integration_test";
    const start = Date.now();
    const pendingControls = new Set();
    const result = await new Promise((resolve, reject) => {
      const child = spawn(dart, args, {
        cwd: clientPath,
        env: process.env,
        windowsHide: true,
        stdio: ["ignore", "pipe", "pipe"],
      });
      let output = "",
        control = "",
        progressCount = 0,
        diagnosticCount = 0,
        backSequence = 0,
        cameraGranted = false,
        backgroundRequested = false;
      const consume = (v, stream) => {
        output += v;
        try {
          const markers = [
            ...output.matchAll(
              /Final Android QA (?:phase|PASS|request): [a-z0-9-]+(?: \d+)?/g,
            ),
          ].map((m) => m[0]);
          const diagnostics = [
            ...output.matchAll(/Final Android QA diagnostic: [a-z0-9=,-]+/g),
          ].map((m) => m[0]);
          if (
            markers.length > progressCount ||
            diagnostics.length > diagnosticCount
          ) {
            progressCount = markers.length;
            diagnosticCount = diagnostics.length;
            fs.writeFileSync(
              path.join(clientPath, "build/routing-android-progress.json"),
              JSON.stringify(
                {
                  startedAt: report.startedAt,
                  status: "RUNNING",
                  markers,
                  diagnostics,
                },
                null,
                2,
              ) + "\n",
            );
          }
          control = (control + v).slice(-4096);
          if (
            !backgroundRequested &&
            control.includes("Final Android QA request: background-resume")
          ) {
            backgroundRequested = true;
            const work = (async () => {
              await runAdbAsync([
                "shell",
                "am",
                "start",
                "-W",
                "-a",
                "android.intent.action.MAIN",
                "-c",
                "android.intent.category.HOME",
              ]);
              await runAdbAsync([
                "shell",
                "am",
                "start",
                "-W",
                "-n",
                "id.queueb.queueb_client/.MainActivity",
              ]);
              report.backgroundResumeInputs = 1;
            })()
              .catch((error) => {
                report.controlErrors ??= [];
                report.controlErrors.push(error.code || error.name);
                child.kill();
              })
              .finally(() => pendingControls.delete(work));
            pendingControls.add(work);
          }
          if (
            !cameraGranted &&
            control.includes("Final Android QA phase: petugas")
          ) {
            runAdb([
              "shell",
              "pm",
              "grant",
              "id.queueb.queueb_client",
              "android.permission.CAMERA",
            ]);
            cameraGranted = true;
            report.cameraPermissionGrantedInQaEmulator = true;
          }
          for (const match of control.matchAll(
            /Final Android QA request: system-back (\d+)/g,
          )) {
            const sequence = Number(match[1]);
            if (sequence <= backSequence) continue;
            if (
              control.includes(
                "Final Android QA diagnostic: after-" + sequence + "-",
              )
            ) {
              throw Object.assign(
                Error(
                  "Back control arrived after the application wait completed",
                ),
                { code: "QA_LATE_BACK_SIGNAL" },
              );
            }
            backSequence = sequence;
            const receivedAt = new Date().toISOString();
            const work = (async () => {
              const ime = await runAdbAsync([
                "shell",
                "dumpsys",
                "input_method",
              ]);
              // dumpsys also contains historical clients. Use the first
              // current-state field rather than any true value in the dump.
              const imeCurrent =
                ime.match(/\bmInputShown=(true|false)\b/) ||
                ime.match(/\bmIsInputViewShown=(true|false)\b/);
              const activity = await runAdbAsync([
                "shell",
                "dumpsys",
                "activity",
                "activities",
              ]);
              const readFocus = async () => {
                const windows = await runAdbAsync([
                  "shell",
                  "dumpsys",
                  "window",
                ]);
                const lines = windows
                  .split(/\r?\n/)
                  .filter(
                    (l) =>
                      l.includes("mCurrentFocus=") ||
                      l.includes("mFocusedWindow="),
                  );
                const current =
                  lines.find((l) => l.includes("id.queueb.queueb_client")) ||
                  lines[0] ||
                  "";
                return { lines, current };
              };
              let focused = await readFocus();
              const initiallyFocused = focused.current.includes(
                "id.queueb.queueb_client",
              );
              let focusPolls = 0;
              if (!initiallyFocused) {
                // A completed widget pump does not establish Android window
                // focus. Bring this owned QA activity forward and wait for the
                // actual WindowManager state before sending a hardware key.
                await runAdbAsync([
                  "shell",
                  "am",
                  "start",
                  "-W",
                  "-n",
                  "id.queueb.queueb_client/.MainActivity",
                ]);
                const deadline = Date.now() + 12000;
                while (
                  !focused.current.includes("id.queueb.queueb_client") &&
                  Date.now() < deadline
                ) {
                  await new Promise((resolve) => setTimeout(resolve, 500));
                  focused = await readFocus();
                  focusPolls++;
                }
              }
              const { lines: focusLines, current: focus } = focused;
              report.systemBackDiagnostics ??= [];
              const diagnostic = {
                sequence,
                markerStream: stream,
                receivedAt,
                imeShown: imeCurrent?.[1] === "true",
                imeMetadataAvailable: !!imeCurrent,
                appResumed: activity
                  .split(/\r?\n/)
                  .some(
                    (l) =>
                      /mResumedActivity|topResumedActivity/.test(l) &&
                      l.includes("id.queueb.queueb_client"),
                  ),
                appWindowFocused: focus.includes("id.queueb.queueb_client"),
                focusMetadataAvailable: focusLines.length > 0,
                initiallyFocused,
                focusPolls,
                focusTarget:
                  focus.match(/[a-zA-Z][a-zA-Z0-9_.]+\/[a-zA-Z0-9_.$]+/)?.[0] ||
                  (focus.includes("=null") ? "null" : "unclassified"),
                systemOverlay:
                  [
                    "Autofill",
                    "SaveUi",
                    "Keyguard",
                    "NotificationShade",
                    "InputMethod",
                  ].find((s) => focus.includes(s)) || null,
              };
              report.systemBackDiagnostics.push(diagnostic);
              if (!focusLines.length)
                throw Object.assign(
                  Error("Android focus metadata unavailable"),
                  { code: "QA_FOCUS_METADATA_UNAVAILABLE" },
                );
              if (!focus.includes("id.queueb.queueb_client"))
                throw Object.assign(
                  Error("QA application window is not focused"),
                  { code: "QA_WINDOW_NOT_FOCUSED" },
                );
              await runAdbAsync(["shell", "input", "keyevent", "4"]);
              report.systemBackInputs = Math.max(
                report.systemBackInputs || 0,
                sequence,
              );
              diagnostic.injectedAt = new Date().toISOString();
            })()
              .catch((error) => {
                report.controlErrors ??= [];
                report.controlErrors.push(error.code || error.name);
                child.kill();
              })
              .finally(() => pendingControls.delete(work));
            pendingControls.add(work);
          }
        } catch (error) {
          report.controlErrors ??= [];
          report.controlErrors.push(error.code || error.name);
          child.kill();
        }
      };
      child.stdout.on("data", (v) => consume(v, "stdout"));
      child.stderr.on("data", (v) => consume(v, "stderr"));
      child.once("error", reject);
      child.once("exit", (code) => resolve({ code: code ?? 1, output }));
    });
    await Promise.all([...pendingControls]);
    report.uiLogoutVerified = result.output.includes(
      "Final Android QA PASS: nested-profile-ui-logout",
    );
    report.cameraControllerRunningVerified =
      result.output.includes(
        "Final Android QA camera-state: running-before-pause",
      ) &&
      result.output.includes(
        "Final Android QA camera-state: running-after-resume",
      );
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
    report.failureSignatures = [
      "Android QA condition not reached",
      "A Timeout occurred",
      "TestFailure",
      "Lost connection to device",
      "Gradle task assembleDebug failed",
      "Gradle build daemon disappeared",
      "OutOfMemoryError",
      "Error connecting to the service protocol",
      "Error waiting for a debug connection",
      "Failed to install",
    ].filter((value) => result.output.includes(value));
    report.finishedAt = new Date().toISOString();
    fs.writeFileSync(
      path.join(clientPath, "build/routing-android-progress.json"),
      JSON.stringify(
        {
          startedAt: report.startedAt,
          status: result.code === 0 ? "PASS" : "FAIL",
          summary: report.summary,
          controlErrors: report.controlErrors,
        },
        null,
        2,
      ) + "\n",
    );
    const output = path.resolve(
      process.env.QUEUEB_QA_EVIDENCE_DIR ||
        path.resolve(clientPath, "../../docs/qa/evidence"),
    );
    if (!output.startsWith(path.resolve(clientPath, "../..") + path.sep))
      throw Error("QA evidence must stay inside repository");
    fs.mkdirSync(output, { recursive: true });
    fs.writeFileSync(
      path.join(output, "android-final.json"),
      JSON.stringify(report, null, 2) + "\n",
    );
    console.log("Final Android QA result: " + JSON.stringify(report));
    if (result.code !== 0 || report.controlErrors?.length)
      throw Error(
        "Android instrumentation failed; raw secret-bearing diagnostics discarded",
      );
  } finally {
    if (server.listening) await new Promise((resolve) => server.close(resolve));
    for (const port of owned) runAdb(["reverse", "--remove", "tcp:" + port]);
  }
};
module.exports.sourceFingerprint = sourceFingerprint;
