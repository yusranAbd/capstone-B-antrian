/** Real local integration; fixed actions, one page at a time. Counts and CDP
 * post-GC JS heap are observations, not Dart/wasm/GPU/Android heap or FPS claims.
 * No request bodies/headers, patient data, QR, cookies or tokens are persisted.
 */
const { chromium, expect: baseExpect } = require("@playwright/test");
const expect = baseExpect.configure({ timeout: 30000 });
const assert = require("node:assert/strict"),
  fs = require("node:fs"),
  path = require("node:path");
const { enter, button } = require("./browser-demo.cjs").helpers;
const api = "http://127.0.0.1:3001/api/v1";
module.exports = async function benchmark({ fixture: f }) {
  const output = path.resolve(process.env.QUEUEB_QA_EVIDENCE_DIR || "");
  if (
    !process.env.QUEUEB_QA_EVIDENCE_DIR ||
    !output.startsWith(path.resolve(__dirname, "../../..") + path.sep)
  )
    throw Error("Explicit repository evidence folder required");
  const report = {
    environment: "Chrome headless release / local test DB / Asia/Jakarta",
    startedAt: new Date().toISOString(),
    method:
      "one context per portal; API method+path counters; two viewport changes; CDP Performance.getMetrics after HeapProfiler.collectGarbage; one sample, no FPS/native heap/causal leak claim",
    portals: [],
  };
  const browser = await chromium.launch({
    channel: "chrome",
    headless: true,
    args: ["--disable-background-timer-throttling"],
  });
  let phase = "start";
  async function post(route, body, token) {
    const r = await fetch(api + route, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(token ? { Authorization: "Bearer " + token } : {}),
      },
      body: JSON.stringify(body),
    });
    assert.ok(r.ok, "Benchmark fixture POST failed");
    return r.json();
  }
  try {
    const admin = (
      await post("/auth/login", {
        email: f.admin.email,
        kataSandi: f.admin.password,
      })
    ).accessToken;
    for (const [portal, account, namespace] of [
      ["admin", "admin", null],
      ["patient", "patient1", "patient"],
      ["staff", "petugas", "queue"],
      ["doctor", "doctor", "doctor"],
      ["display", null, "display"],
    ]) {
      phase = portal;
      const context = await browser.newContext({
        viewport: { width: 1366, height: 900 },
      });
      try {
        const page = await context.newPage(),
          counts = {},
          pending = new Set(),
          errors = [];
        page.on("pageerror", () => errors.push(true));
        page.on("request", (r) => {
          const u = new URL(r.url());
          if (!u.pathname.startsWith("/api/v1/")) return;
          pending.add(r);
          const key =
            r.method() +
            " " +
            u.pathname.replace(
              /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi,
              ":id",
            );
          counts[key] = (counts[key] || 0) + 1;
        });
        for (const event of ["requestfinished", "requestfailed"])
          page.on(event, (r) => pending.delete(r));
        const start = Date.now();
        await page.goto("http://127.0.0.1:8080/");
        if (account) {
          await enter(page, "Email", f[account].email);
          await enter(page, "Kata sandi", f[account].password);
          await button(page, "Masuk");
          await expect(
            page.getByRole("textbox", { name: "Email", exact: true }),
          ).toHaveCount(0);
          if (portal === "admin")
            await expect(
              page.getByText("Dashboard", { exact: true }).first(),
            ).toBeVisible();
          if (portal === "patient")
            await expect(
              page.getByRole("tab", { name: "Beranda", exact: true }),
            ).toBeVisible();
          if (portal === "staff")
            await expect(
              page.getByRole("button", { name: /Pindai QR/ }),
            ).toBeEnabled();
          if (portal === "doctor")
            await expect(
              page.getByRole("button", { name: /Tanggal:/ }),
            ).toBeEnabled();
        } else {
          const device = await post(
            "/perangkat-display",
            { layananId: f.serviceId, nama: "Cleanup Benchmark" },
            admin,
          );
          const code = (
            await post(
              "/perangkat-display/" + device.id + "/aktivasi",
              {},
              admin,
            )
          ).kode;
          await button(page, "Masuk ke Public Display");
          await enter(page, "Kode Aktivasi", code);
          await button(page, "Hubungkan Perangkat");
          await expect(
            page.getByText("Realtime terhubung", { exact: true }),
          ).toBeVisible();
        }
        await expect.poll(() => pending.size).toBe(0);
        await page.waitForTimeout(500); // Fixed settling interval, identical both samples.
        await expect.poll(() => pending.size).toBe(0);
        const readyMs = Date.now() - start;
        const client = await context.newCDPSession(page);
        await client.send("Performance.enable");
        const sample = async () => {
          await client.send("HeapProfiler.collectGarbage");
          const m = await client.send("Performance.getMetrics");
          return Object.fromEntries(
            m.metrics
              .filter((v) =>
                [
                  "JSHeapUsedSize",
                  "JSHeapTotalSize",
                  "Nodes",
                  "Documents",
                  "LayoutCount",
                  "RecalcStyleCount",
                ].includes(v.name),
              )
              .map((v) => [v.name, v.value]),
          );
        };
        const before = await sample(),
          requestsBefore = structuredClone(counts),
          socketsBefore = f.socketCounts();
        const expected = Object.fromEntries(
          ["queue", "patient", "doctor", "display"].map((n) => [
            n,
            n === namespace ? 1 : 0,
          ]),
        );
        await expect.poll(() => f.socketCounts()).toEqual(expected);
        for (const size of [
          { width: 1280, height: 900 },
          { width: 1366, height: 900 },
        ]) {
          await page.setViewportSize(size);
          await page.waitForTimeout(250);
        }
        await expect.poll(() => pending.size).toBe(0);
        const after = await sample();
        assert.equal(errors.length, 0);
        const extra = Object.fromEntries(
          Object.entries(counts)
            .map(([k, v]) => [k, v - (requestsBefore[k] || 0)])
            .filter(([, v]) => v),
        );
        report.portals.push({
          portal,
          readyMs,
          requests: counts,
          extraRequestsDuringTwoResizes: extra,
          heapBeforeResize: before,
          heapAfterResize: after,
          serverSocketsBeforeResize: socketsBefore,
          serverSocketsAfterResize: f.socketCounts(),
          runtimeErrors: errors.length,
        });
      } finally {
        await context.close();
      }
      await expect
        .poll(() => Object.values(f.socketCounts()).reduce((n, v) => n + v, 0))
        .toBe(0);
      console.log("Cleanup benchmark PASS: " + portal);
    }
    report.finalSocketCounts = f.socketCounts();
    report.status = "PASS";
  } catch (error) {
    report.status = "FAIL";
    report.failedPhase = phase;
    report.errorType = error.name;
    report.diagnosticCode = error.cause?.code || error.code;
    report.sourceFrames = error.stack
      ?.split("\n")
      .filter((l) => l.includes("browser-cleanup-benchmark.cjs:"));
    throw Error("Cleanup benchmark failed in " + phase);
  } finally {
    report.finishedAt = new Date().toISOString();
    fs.mkdirSync(output, { recursive: true });
    fs.writeFileSync(
      path.join(output, "runtime-metrics.json"),
      JSON.stringify(report, null, 2) + "\n",
    );
    await browser.close();
  }
};
