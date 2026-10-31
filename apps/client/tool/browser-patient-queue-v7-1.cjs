/** Actual compiled Flutter, Nest, PostgreSQL and Socket.IO. Only run-live fixtures.
 * QR video is controlled camera input; no REST or socket response is stubbed.
 */
const { chromium, expect: baseExpect } = require("@playwright/test");
const expect = baseExpect.configure({ timeout: 30000 });
const assert = require("node:assert/strict");
const fs = require("node:fs"),
  path = require("node:path");
const { enter, button, cameraVideo } = require("./browser-demo.cjs").helpers;
const { sampleFrames } = require("./motion-profile.cjs");
const api = "http://127.0.0.1:3001/api/v1";
const args = [
  "--disable-background-timer-throttling",
  "--disable-renderer-backgrounding",
  "--disable-backgrounding-occluded-windows",
];
module.exports = async ({ fixture: f }) => {
  const buildRoot = path.resolve(__dirname, "../build");
  const out = process.env.QUEUEB_REALTIME_EVIDENCE_DIR
    ? path.resolve(process.env.QUEUEB_REALTIME_EVIDENCE_DIR)
    : path.join(buildRoot, "v7-1/browser-realtime");
  assert(out.startsWith(buildRoot + path.sep), "Evidence must stay in build");
  fs.mkdirSync(out, { recursive: true });
  const video = path.join(out, "owned-camera.y4m");
  const contexts = [],
    browsers = [],
    cases = [],
    errors = [];
  const profiles = [];
  let cameraPage;
  const mediaFailures = [];
  let staffAuthorization;
  let phase = "fixtures",
    fault = false,
    http5xx = 0;
  const deadline = setTimeout(
    () => browsers.forEach((b) => b.close().catch(() => {})),
    9 * 60000,
  );
  deadline.unref();
  async function request(route, token, body) {
    const r = await fetch(api + route, {
      method: body === undefined ? "GET" : "POST",
      headers: {
        "Content-Type": "application/json",
        ...(token ? { Authorization: "Bearer " + token } : {}),
      },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    assert(r.ok, "Fixture HTTP " + r.status + " " + route);
    return r.json();
  }
  const token = async (key) =>
    (
      await request("/auth/login", null, {
        email: f[key].email,
        kataSandi: f[key].password,
      })
    ).accessToken;
  async function open(browser, key, camera = false) {
    const c = await browser.newContext({
      viewport: { width: camera ? 1366 : 390, height: camera ? 900 : 844 },
    });
    contexts.push(c);
    if (camera) await c.grantPermissions(["camera"]);
    // Serve the exact bundled engine only; API/socket traffic stays untouched.
    const root = path.resolve(__dirname, "../build/web/canvaskit");
    const revision = fs
      .readFileSync(path.join(root, "../flutter_bootstrap.js"), "utf8")
      .match(/engineRevision[^a-f0-9]+([a-f0-9]{40})/)[1];
    await c.route(
      "https://www.gstatic.com/flutter-canvaskit/**",
      async (route) => {
        const parts = new URL(route.request().url()).pathname.split("/");
        assert.equal(parts[2], revision);
        const file = path.resolve(root, parts.slice(3).join("/"));
        assert(file.startsWith(root + path.sep));
        await route.fulfill({
          path: file,
          contentType: file.endsWith(".wasm")
            ? "application/wasm"
            : "text/javascript",
          headers: { "Access-Control-Allow-Origin": "*" },
        });
      },
    );
    const p = await c.newPage();
    if (camera) {
      cameraPage = p;
      p.on("requestfailed", (request) => {
        const url = new URL(request.url());
        if (url.pathname.startsWith("/api/v1/")) return;
        const error = request.failure()?.errorText || "";
        mediaFailures.push({
          host: url.hostname,
          error: /^net::ERR_[A-Z_]+$/.test(error) ? error : "other",
        });
      });
    }
    const stats = {
      reads: 0,
      automaticPosts: 0,
      activeSockets: 0,
      maxSockets: 0,
      opened: 0,
      scopedEvents: 0,
    };
    p.on("pageerror", () => errors.push({ phase, kind: "pageerror" }));
    p.on("console", (m) => {
      if (m.type() === "error" && !(fault && key === "patient1"))
        errors.push({ phase, kind: "console" });
    });
    p.on("response", (r) => {
      if (r.status() >= 500) http5xx++;
      if (new URL(r.url()).pathname === "/api/v1/layanan/antrean" && r.ok())
        stats.reads++;
    });
    p.on("request", (r) => {
      const pathname = new URL(r.url()).pathname;
      if (
        camera &&
        r.method() === "POST" &&
        pathname.startsWith("/api/v1/queue/")
      ) {
        // Keep the already authenticated staff session only in process memory.
        staffAuthorization = r.headers().authorization;
      }
      if (
        !camera &&
        r.method() === "POST" &&
        (pathname === "/api/v1/reservasi" ||
          pathname.endsWith("/qr") ||
          pathname.startsWith("/api/v1/check-in"))
      )
        stats.automaticPosts++;
    });
    p.on("websocket", (ws) => {
      if (new URL(ws.url()).host !== "127.0.0.1:3001") return;
      stats.activeSockets++;
      stats.opened++;
      stats.maxSockets = Math.max(stats.maxSockets, stats.activeSockets);
      ws.on("close", () => stats.activeSockets--);
      ws.on("framereceived", ({ payload }) => {
        if (
          typeof payload === "string" &&
          payload.includes('"jenis":"ANTREAN"')
        )
          stats.scopedEvents++;
      });
    });
    await p.goto("http://127.0.0.1:8080/");
    await p
      .locator("flt-glass-pane")
      .waitFor({ state: "attached", timeout: 90000 });
    await login(p, key);
    return { p, c, stats, key };
  }
  async function login(p, key) {
    await enter(p, "Email", f[key].email);
    await enter(p, "Kata sandi", f[key].password);
    await button(p, "Masuk");
    await expect(
      p.getByRole("textbox", { name: "Email", exact: true }),
    ).toHaveCount(0);
  }
  const card = (client, name = "Pendaftaran") =>
    client.p
      .getByRole("button", { name: new RegExp("^" + name + "\\.") })
      .first();
  const total = (client, n, name) =>
    expect(card(client, name)).toHaveAccessibleName(
      new RegExp("Total check-in hari ini " + n + "\\."),
    );
  const pass = (id) => {
    cases.push({ id, status: "PASS" });
    console.log("V7.1 realtime PASS: " + id);
  };
  async function scan(staff, qr, ticketId) {
    await staff.p.bringToFront();
    const response = staff.p.waitForResponse(
      (r) =>
        r.request().method() === "POST" &&
        new URL(r.url()).pathname === "/api/v1/check-in/auto-antrean",
    );
    await staff.p.getByRole("button", { name: /Pindai QR/ }).click();
    const r = await response;
    assert(r.ok(), "One-Scan HTTP " + r.status());
    const data = await r.json();
    assert.equal(data.tiketId, ticketId);
    await expect(
      staff.p.getByRole("button", { name: "Tutup", exact: true }),
    ).toBeVisible();
    await button(staff.p, "Tutup");
    return data;
  }
  async function command(staff, route, label) {
    await staff.p.bringToFront();
    await expect(
      staff.p.getByRole("button", { name: /Pindai QR/ }),
    ).toBeEnabled();
    const response = staff.p.waitForResponse(
      (r) =>
        r.request().method() === "POST" &&
        new URL(r.url()).pathname === "/api/v1" + route,
    );
    await button(staff.p, label);
    const r = await response;
    assert(r.ok(), "Queue HTTP " + r.status());
    await expect(
      staff.p.getByRole("button", { name: /Pindai QR/ }),
    ).toBeEnabled();
  }
  try {
    const admin = await token("admin");
    f.extraServiceCodes.push("APOTEK");
    await request("/layanan", admin, {
      kode: "APOTEK",
      nama: "Apotek",
      prefixAntrean: "APT",
      durasiDasarMenit: 15,
      modeReservasi: "ANTREAN_HARIAN",
    });
    const tickets = [];
    for (const key of ["patient1", "patient2"]) {
      const t = await token(key);
      const booking = await request("/reservasi", t, {
        layananId: f.serviceId,
        tanggalAntrean: f.date,
      });
      const detail = await request("/tiket/" + booking.id, t);
      const qr = await request("/tiket/" + booking.id + "/qr", t, {});
      tickets.push({
        id: booking.id,
        number: detail.nomorAntrean,
        qr: qr.qrPayload,
      });
    }
    cameraVideo(tickets[0].qr, video);
    const b = await chromium.launch({
      channel: "chrome",
      headless: true,
      args,
    });
    browsers.push(b);
    const a = await open(b, "patient1"),
      other = await open(b, "patient2"),
      c = await open(b, "patient3");
    phase = "initial";
    for (const user of [a, other]) {
      await total(user, 0);
      await expect(card(user)).toHaveAccessibleName(/0 menunggu.*Live/);
    }
    assert.notEqual(tickets[0].number, tickets[1].number);
    await expect(card(a)).toHaveAccessibleName(
      new RegExp("Nomor Antreanmu " + tickets[0].number),
    );
    await expect(card(other)).toHaveAccessibleName(
      new RegExp("Nomor Antreanmu " + tickets[1].number),
    );
    await enter(c.p, "Cari layanan, poli, atau informasi...", "Apotek");
    await total(c, 0, "Apotek");
    pass("A-initial-authoritative-distinct-personal-tickets");
    const camera = await chromium.launch({
      channel: "chrome",
      headless: true,
      args: [
        ...args,
        "--use-fake-device-for-media-stream",
        "--use-file-for-fake-video-capture=" + video,
      ],
    });
    browsers.push(camera);
    const staff = await open(camera, "petugas", true);
    phase = "check-in";
    const before = [a.stats.scopedEvents, other.stats.scopedEvents];
    await scan(staff, tickets[0].qr, tickets[0].id);
    await sampleFrames(
      a.p,
      "patient-authoritative-check-in",
      () => total(a, 1),
      profiles,
    );
    await total(other, 1);
    for (const [i, user] of [a, other].entries()) {
      assert(user.stats.scopedEvents > before[i]);
      await expect(card(user)).toHaveAccessibleName(/1 menunggu/);
    }
    pass("B-staff-camera-commit-two-patients-event-get-no-reload");
    phase = "duplicate";
    const duplicate = await scan(staff, tickets[0].qr, tickets[0].id);
    assert.equal(duplicate.sudahTerdaftar, true);
    await total(a, 1);
    await total(other, 1);
    pass("C-repeated-camera-scan-no-double-count");
    phase = "progression";
    await command(staff, "/queue/panggil", "Panggil berikutnya");
    await expect(card(other)).toHaveAccessibleName(/0 menunggu/);
    await expect(card(other)).toHaveAccessibleName(/Belum ada pelayanan aktif/);
    await command(
      staff,
      "/queue/" + tickets[0].id + "/mulai-pelayanan",
      "Mulai Pelayanan",
    );
    for (const user of [a, other]) {
      await expect(card(user)).toHaveAccessibleName(
        new RegExp("Sedang dilayani: .*" + tickets[0].number),
      );
      await total(user, 1);
    }
    await expect(card(other)).toHaveAccessibleName(
      new RegExp("Nomor Antreanmu " + tickets[1].number),
    );
    pass("D-call-start-serving-separate-personal-ticket-total-unchanged");
    // Capture the compiled V8 UI with distinct, authoritative personal/serving
    // numbers. Viewport changes are read-only and keep the same session owner.
    for (const width of [360, 390, 430, 1366]) {
      await other.p.setViewportSize({
        width,
        height: width >= 768 ? 768 : 844,
      });
      await expect(card(other)).toHaveAccessibleName(
        new RegExp("Nomor Antreanmu " + tickets[1].number),
      );
      await expect(card(other)).toHaveAccessibleName(
        new RegExp("Sedang dilayani: .*" + tickets[0].number),
      );
      await other.p.screenshot({
        path: path.join(out, `home-v8-live-${width}.png`),
      });
    }
    await other.p.setViewportSize({ width: 390, height: 844 });
    await total(c, 0, "Apotek");
    await expect(card(c, "Apotek")).toHaveAccessibleName(/Belum ada tiket/);
    pass("E-other-service-no-count-or-private-ticket-leakage");
    phase = "reconnect";
    fault = true;
    await a.c.setOffline(true);
    f.disconnectPatient(f.patient1.id);
    await expect(card(a)).toHaveAccessibleName(/Data terakhir/);
    // Camera decode + repeated scan were verified above. The reconnect scenario
    // submits one real One-Scan REST request using that SAME staff session, so
    // changing a fake camera file cannot obscure transport reconciliation.
    assert(staffAuthorization?.startsWith("Bearer "));
    const second = await request(
      "/check-in/auto-antrean",
      staffAuthorization.slice(7),
      { qrPayload: tickets[1].qr, loketId: f.roomId },
    );
    assert.equal(second.tiketId, tickets[1].id);
    await total(other, 2);
    await total(a, 1);
    await a.c.setOffline(false);
    await total(a, 2);
    await expect(card(a)).toHaveAccessibleName(/Live/);
    await expect.poll(() => f.patientSocketCount(f.patient1.id)).toBe(1);
    fault = false;
    assert.equal(a.stats.maxSockets, 1);
    await total(c, 0, "Apotek");
    pass("F-transport-loss-reconnect-authoritative-two-no-extra-subscription");
    phase = "logout-account";
    await button(a.p, "Profil pasien");
    await button(a.p, "Keluar Akun");
    await expect(
      a.p.getByRole("textbox", { name: "Email", exact: true }),
    ).toBeVisible();
    await expect.poll(() => f.patientSocketCount(f.patient1.id)).toBe(0);
    await login(a.p, "patient3");
    // Shell branch may retain the profile location requested before logout.
    await a.p.getByRole("tab", { name: "Beranda", exact: true }).click();
    await total(a, 2);
    await expect(card(a)).toHaveAccessibleName(
      /Belum ada tiket untuk hari ini/,
    );
    await expect(card(a)).not.toHaveAccessibleName(
      new RegExp("Nomor Antreanmu " + tickets[0].number),
    );
    pass("G-logout-releases-socket-new-account-no-private-ticket");
    for (const user of [a, other, c]) {
      assert.equal(user.stats.automaticPosts, 0);
      assert(user.stats.reads > 0);
      assert.equal(user.stats.maxSockets, 1);
    }
    assert.equal(http5xx, 0);
    assert.deepEqual(errors, []);
    await other.p.screenshot({ path: path.join(out, "two-check-ins.png") });
    fs.writeFileSync(
      path.join(out, "summary.json"),
      JSON.stringify(
        {
          status: "PASS",
          cases,
          http5xx,
          errors,
          patients: [a, other, c].map((u) => u.stats),
          camera: "controlled Y4M; actual Flutter decoder and One-Scan HTTP",
          offlineMutation: "one real One-Scan REST POST, same staff session",
          reloads: 0,
        },
        null,
        2,
      ),
    );
  } catch (error) {
    const cameraDiagnostics =
      cameraPage && !cameraPage.isClosed()
        ? await cameraPage
            .evaluate(() => {
              const v = document.querySelector("video");
              const labels = [...document.querySelectorAll("[aria-label]")]
                .map((n) => n.getAttribute("aria-label"))
                .join("\n");
              return {
                video: v
                  ? {
                      width: v.videoWidth,
                      height: v.videoHeight,
                      ready: v.readyState,
                      paused: v.paused,
                      time: v.currentTime,
                      tracks: [...(v.srcObject?.getVideoTracks?.() || [])].map(
                        (t) => ({
                          ready: t.readyState,
                          enabled: t.enabled,
                          muted: t.muted,
                        }),
                      ),
                    }
                  : null,
                labels: Object.fromEntries(
                  [
                    "QR Check-in Otomatis",
                    "Kamera tidak tersedia",
                    "kedaluwarsa",
                    "belum tersinkron",
                    "Check-in berhasil",
                  ].map((k) => [k, labels.includes(k)]),
                ),
              };
            })
            .catch(() => null)
        : null;
    fs.writeFileSync(
      path.join(out, "summary.json"),
      JSON.stringify(
        {
          status: "FAIL",
          phase,
          errorType: error.name,
          message: error.message,
          cases,
          http5xx,
          errors,
          cameraDiagnostics,
          mediaFailures,
        },
        null,
        2,
      ),
    );
    console.error("V7.1 realtime failed at " + phase + ": " + error.message);
    throw error;
  } finally {
    if (profiles.length)
      fs.writeFileSync(
        path.join(out, "motion-frame-profile.json"),
        JSON.stringify(profiles, null, 2),
      );
    clearTimeout(deadline);
    for (const c of contexts) await c.close().catch(() => {});
    for (const b of browsers) await b.close().catch(() => {});
    if (fs.existsSync(video)) fs.unlinkSync(video);
  }
};
