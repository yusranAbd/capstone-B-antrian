/** Real local Flutter/Nest/PostgreSQL/Socket.IO QA. No REST/socket stubs.
 * Camera frames and Web Speech are controlled test inputs, not physical proof.
 * run-live.cjs owns every fixture and verifies cleanup. Never persist secrets.
 */
const { chromium, expect: baseExpect } = require("@playwright/test");
const expect = baseExpect.configure({ timeout: 30000 });
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { enter, button, reveal, cameraVideo } =
  require("./browser-demo.cjs").helpers;
const base = "http://127.0.0.1:8080/";
const api = "http://127.0.0.1:3001/api/v1";

module.exports = async function finalQa({ fixture: f, root }) {
  const output = path.resolve(__dirname, "../../../docs/qa/evidence");
  fs.mkdirSync(output, { recursive: true });
  const report = {
    environment: "Chrome headless / local test DB / Asia/Jakarta",
    transport: "real REST + Socket.IO; fake video QR; controlled Web Speech",
    startedAt: new Date().toISOString(),
    scenarios: [],
    layouts: [],
    runtimeErrors: 0,
  };
  const contexts = [],
    browsers = [],
    errors = [];
  const video = path.join(root, "final-qa-camera.y4m");
  let phase = "setup";
  let nativeDiagnosticPage;
  const deadline = setTimeout(
    () => browsers.forEach((b) => b.close().catch(() => {})),
    12 * 60000,
  );
  deadline.unref();
  function pass(id, detail, level = "Browser E2E") {
    report.scenarios.push({ id, status: "PASS", level, detail });
    console.log("Final QA PASS: " + id);
  }
  async function request(
    route,
    body,
    token,
    method = body === undefined ? "GET" : "POST",
    expected,
  ) {
    const r = await fetch(api + route, {
      method,
      headers: {
        "Content-Type": "application/json",
        ...(token ? { Authorization: "Bearer " + token } : {}),
      },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    assert.equal(
      r.status,
      expected ??
        (method === "GET" ? 200 : undefined) ??
        (r.ok ? r.status : 200),
      "QA HTTP " + method + " " + route,
    );
    return r.json();
  }
  async function login(account) {
    return (
      await request("/auth/login", {
        email: f[account].email,
        kataSandi: f[account].password,
      })
    ).accessToken;
  }
  async function open(
    browser,
    account,
    viewport = { width: 1366, height: 900 },
    context,
  ) {
    const c = context || (await browser.newContext({ viewport }));
    if (!context) contexts.push(c);
    const p = await c.newPage();
    p.on("pageerror", () => errors.push("pageerror"));
    await p.goto(base);
    if (account) {
      await enter(p, "Email", f[account].email);
      await enter(p, "Kata sandi", f[account].password);
      await button(p, "Masuk");
      await expect(
        p.getByRole("textbox", { name: "Email", exact: true }),
      ).toHaveCount(0);
    }
    return p;
  }
  async function shot(page, name) {
    await page.bringToFront();
    await page.mouse.move(1, 1);
    await page.screenshot({
      path: path.join(output, name + ".png"),
      animations: "disabled",
    });
  }
  async function layout(page, portal, sizes) {
    for (const [width, height] of sizes) {
      await page.bringToFront();
      await page.setViewportSize({ width, height });
      await expect.poll(() => page.evaluate(() => innerWidth)).toBe(width);
      const metrics = await page.evaluate(() => ({
        horizontal: document.documentElement.scrollWidth > innerWidth,
        vertical: document.documentElement.scrollHeight > innerHeight,
      }));
      assert.equal(metrics.horizontal, false, portal + " document overflow");
      report.layouts.push({ portal, width, height, ...metrics });
      await shot(page, portal + "-" + width);
    }
  }
  async function uiMutation(page, route, action) {
    const wait = page.waitForResponse(
      (r) =>
        r.request().method() === "POST" &&
        new URL(r.url()).pathname === "/api/v1" + route,
    );
    wait.catch(() => {});
    await action();
    const r = await wait;
    assert.ok(r.ok(), "UI mutation HTTP " + r.status());
    return r.json();
  }
  try {
    const adminToken = await login("admin"),
      staffToken = await login("petugas");
    const patientToken = await login("patient1"),
      walkToken = await login("patient2");
    const appointment = await request(
      "/janji-temu",
      { slotPraktikId: f.slotId },
      patientToken,
    );
    assert.ok(appointment.tiket?.id || appointment.tiketId);
    pass(
      "appointment-live",
      "HIBRIDA appointment created by authenticated patient REST; browser booking not asserted here",
      "Backend Integration",
    );
    const b = await chromium.launch({ channel: "chrome", headless: true });
    browsers.push(b);
    phase = "login-layout";
    const admin = await open(b, "admin");
    report.nativeVoiceLanguages = await admin.evaluate(() => [
      ...new Set(speechSynthesis.getVoices().map((v) => v.lang)),
    ]);
    report.physicalSpeakerVerified = false;
    await expect(
      admin.getByText("Poliklinik", { exact: true }).first(),
    ).toBeVisible();
    await layout(admin, "admin", [
      [1366, 900],
      [768, 1024],
    ]);
    await admin.context().close();
    const patient = await open(b, "patient2", { width: 390, height: 844 });
    await layout(patient, "patient", [
      [360, 800],
      [390, 844],
      [412, 915],
      [1280, 900],
    ]);
    await patient.setViewportSize({ width: 390, height: 844 });
    const doctor = await open(b, "doctor");
    await shot(doctor, "doctor-initial");
    const doctorMethods = [];
    doctor.on("request", (r) => {
      if (new URL(r.url()).pathname.includes("/portal-dokter"))
        doctorMethods.push(r.method());
    });
    await expect(
      doctor.locator('[aria-label*="Dashboard Dokter"]').first(),
    ).toBeVisible();
    await expect(
      doctor.getByRole("button", { name: /Tanggal:/ }),
    ).toBeEnabled();
    await layout(doctor, "doctor", [
      [390, 844],
      [1366, 900],
    ]);
    pass(
      "role-login",
      "ADMIN, PASIEN, DOKTER authenticated in distinct browser contexts",
    );
    phase = "patient-booking";
    // Home V6's walk-in list is reserved for auxiliary service codes.
    // The unique HIBRIDA clinic is reached through the existing reservation catalog.
    await patient.getByRole("tab", { name: "Reservasi", exact: true }).click();
    await button(patient, "Buat Reservasi");
    await patient.getByRole("button", { name: /Pilih Poliklinik/ }).click();
    const clinic = patient
      .getByRole("button", { name: /Poli Fixture Flutter/ })
      .or(patient.getByText("Poli Fixture Flutter", { exact: true }))
      .first();
    await reveal(patient, clinic);
    await clinic.click();
    await patient
      .getByRole("button", { name: "Walk-in", exact: true })
      .or(patient.getByRole("radio", { name: "Walk-in", exact: true }))
      .or(patient.getByText("Walk-in", { exact: true }))
      .first()
      .click();
    const reserve = patient.getByRole("button", {
      name: "Reservasi walk-in",
      exact: true,
    });
    await reveal(patient, reserve);
    const walk = await uiMutation(patient, "/reservasi", async () => {
      await reserve.click();
      await button(patient, "Lanjutkan");
    });
    assert.ok(walk.id);
    Object.assign(
      walk,
      await request("/tiket/" + walk.id, undefined, walkToken),
    );
    assert.equal(typeof walk.nomorAntrean, "string");
    pass(
      "patient-booking-ui",
      "Reservasi → Pilih Poliklinik → HIBRIDA walk-in → confirmation → real ticket",
    );
    const walkQr = await request("/tiket/" + walk.id + "/qr", {}, walkToken);
    cameraVideo(walkQr.qrPayload, video);
    phase = "display-pairing";
    const codeB = "QB" + f.unique;
    const clinicB = await request(
      "/layanan",
      {
        kode: codeB,
        nama: "Poli QA B",
        prefixAntrean: "QB",
        durasiDasarMenit: 15,
        modeReservasi: "ANTREAN_HARIAN",
      },
      adminToken,
    );
    f.extraServiceIds.push(clinicB.id);
    phase = "native-audio";
    const nativeContext = await b.newContext({
      viewport: { width: 1280, height: 720 },
    });
    contexts.push(nativeContext);
    await nativeContext.addInitScript(() => {
      window.__nativeSpeech = {
        requested: 0,
        started: 0,
        ended: 0,
        errors: [],
      };
      const speak = speechSynthesis.speak.bind(speechSynthesis);
      // Observe the native engine; original speak/voices/provider remain active.
      speechSynthesis.speak = (u) => {
        window.__nativeSpeech.requested++;
        // flutter_tts reuses one utterance; observers must be per dispatch.
        const start = () => window.__nativeSpeech.started++;
        const cleanup = () => {
          u.removeEventListener("start", start);
          u.removeEventListener("end", end);
          u.removeEventListener("error", error);
        };
        const end = () => {
          window.__nativeSpeech.ended++;
          cleanup();
        };
        const error = (e) => {
          window.__nativeSpeech.errors.push(e.error);
          cleanup();
        };
        u.addEventListener("start", start, { once: true });
        u.addEventListener("end", end, { once: true });
        u.addEventListener("error", error, { once: true });
        return speak(u);
      };
    });
    const nativePage = await open(b, null, undefined, nativeContext);
    nativeDiagnosticPage = nativePage;
    const nativeDevice = await request(
      "/perangkat-display",
      { layananId: f.serviceId, nama: "QA Native Audio" },
      adminToken,
    );
    const nativeCode = (
      await request(
        "/perangkat-display/" + nativeDevice.id + "/aktivasi",
        {},
        adminToken,
      )
    ).kode;
    await button(nativePage, "Masuk ke Public Display");
    await enter(nativePage, "Kode Aktivasi", nativeCode);
    await button(nativePage, "Hubungkan Perangkat");
    await expect(
      nativePage.getByText("Realtime terhubung", { exact: true }),
    ).toBeVisible();
    report.nativeAudio = {
      languages: await nativePage.evaluate(async () => {
        if (!speechSynthesis.getVoices().length)
          await new Promise((resolve) => {
            const timer = setTimeout(resolve, 5000);
            speechSynthesis.addEventListener(
              "voiceschanged",
              () => {
                clearTimeout(timer);
                resolve();
              },
              { once: true },
            );
          });
        return [...new Set(speechSynthesis.getVoices().map((v) => v.lang))];
      }),
      physicalSpeakerVerified: false,
    };
    await button(nativePage, "Aktifkan suara");
    await expect
      .poll(() => nativePage.evaluate(() => window.__nativeSpeech.ended), {
        timeout: 15000,
      })
      .toBe(1);
    await button(nativePage, "Matikan suara");
    await expect(
      nativePage.getByRole("button", { name: "Aktifkan suara", exact: true }),
    ).toBeVisible();
    await button(nativePage, "Aktifkan suara");
    await expect
      .poll(() => nativePage.evaluate(() => window.__nativeSpeech.ended), {
        timeout: 15000,
      })
      .toBe(2);
    report.nativeAudio.callbacks = await nativePage.evaluate(
      () => window.__nativeSpeech,
    );
    assert.deepEqual(report.nativeAudio.callbacks.errors, []);
    await expect(
      nativePage.getByText("Realtime terhubung", { exact: true }),
    ).toBeVisible();
    await button(nativePage, "Matikan suara");
    await nativeContext.close();
    pass(
      "native-audio",
      "Real FlutterTts/native id-ID engine: user-gesture activation, two start/end callbacks, mute/unmute; physical speaker remains unverified",
    );
    phase = "display-pairing";
    const displays = [];
    const shared = await b.newContext({
      viewport: { width: 1280, height: 720 },
    });
    contexts.push(shared);
    const separate = await b.newContext({
      viewport: { width: 1280, height: 720 },
    });
    contexts.push(separate);
    // Controlled utterances record only counts/lang; never patient text.
    const speech = () => {
      window.__qaSpeech = 0;
      let timer;
      const Native = window.SpeechSynthesisUtterance;
      window.SpeechSynthesisUtterance = class extends Native {
        get voice() {
          return this.qaVoice || null;
        }
        set voice(v) {
          this.qaVoice = v;
        }
      };
      speechSynthesis.getVoices = () => [
        {
          lang: "id-ID",
          name: "QA controlled voice",
          voiceURI: "qa-id",
          localService: true,
          default: true,
        },
      ];
      speechSynthesis.cancel = () => clearTimeout(timer);
      speechSynthesis.speak = (u) => {
        window.__qaSpeech++;
        u.dispatchEvent(new Event("start"));
        timer = setTimeout(() => u.dispatchEvent(new Event("end")), 30);
      };
    };
    await shared.addInitScript(speech);
    await separate.addInitScript(speech);
    for (const [index, c] of [shared, separate, shared].entries()) {
      const service = index === 1 ? clinicB.id : f.serviceId;
      const device = await request(
        "/perangkat-display",
        { layananId: service, nama: "QA Monitor " + index },
        adminToken,
      );
      const code = (
        await request(
          "/perangkat-display/" + device.id + "/aktivasi",
          {},
          adminToken,
        )
      ).kode;
      const p = await open(b, null, undefined, c);
      const snapshots = [],
        events = [];
      p.on("response", async (r) => {
        if (
          new URL(r.url()).pathname ===
            "/api/v1/display/" + service + "/snapshot" &&
          r.ok()
        ) {
          const selector = await r.request().headerValue("x-display-device-id");
          const data = await r.json().catch(() => null);
          if (data) snapshots.push({ selector, mode: data.modeNama });
        }
      });
      p.on("websocket", (ws) =>
        ws.on("framereceived", (frame) => {
          if (
            typeof frame.payload === "string" &&
            frame.payload.includes("display:")
          )
            events.push(
              frame.payload.includes("display:ready") ? "ready" : "updated",
            );
        }),
      );
      await button(p, "Masuk ke Public Display");
      await enter(p, "Kode Aktivasi", code);
      await button(p, "Hubungkan Perangkat");
      await expect(
        p.getByText("Realtime terhubung", { exact: true }),
      ).toBeVisible();
      await expect.poll(() => snapshots.length).toBeGreaterThan(0);
      assert.ok(
        snapshots.every((s) => s.selector === device.id && s.mode === "SAMAR"),
      );
      const cookie = (await c.cookies(api)).find(
        (v) => v.name === "queueb_display_" + device.id,
      );
      assert.ok(cookie?.httpOnly && cookie.sameSite === "Strict");
      const readable = await p.evaluate(() => document.cookie);
      assert.equal(readable.includes(cookie.name + "="), false);
      await button(p, "Aktifkan suara");
      displays.push({ p, c, id: device.id, snapshots, events, service });
    }
    const [a, other, c] = displays;
    pass(
      "three-display-pairing",
      "A/C same Chrome context, B separate context; unique tab selectors; HttpOnly + SameSite Strict; masked projection",
    );
    await layout(a.p, "display", [
      [1280, 720],
      [1366, 768],
      [1920, 1080],
    ]);
    phase = "one-scan";
    const camera = await chromium.launch({
      channel: "chrome",
      headless: true,
      args: [
        "--use-fake-device-for-media-stream",
        "--use-file-for-fake-video-capture=" + video,
      ],
    });
    browsers.push(camera);
    const staff = await open(camera, "petugas");
    await staff.context().grantPermissions(["camera"]);
    await expect(
      staff.getByText("Realtime terhubung", { exact: false }).first(),
    ).toBeVisible();
    await layout(staff, "staff", [
      [1366, 900],
      [768, 1024],
      [390, 844],
    ]);
    await staff.setViewportSize({ width: 1366, height: 900 });
    const scanned = await uiMutation(staff, "/check-in/auto-antrean", () =>
      staff.getByRole("button", { name: /Pindai QR/ }).click(),
    );
    assert.equal(scanned.tiketId, walk.id);
    assert.equal(scanned.status, "MENUNGGU");
    report.scanResponse = {
      status: scanned.status,
      alreadyRegistered: scanned.sudahTerdaftar,
    };
    try {
      await expect(
        staff
          .getByText("Check-in berhasil. Pasien masuk antrean.", {
            exact: false,
          })
          .or(
            staff.locator(
              '[aria-label*="Check-in berhasil. Pasien masuk antrean."]',
            ),
          )
          .first(),
      ).toBeVisible();
    } catch (error) {
      report.scanUi = await staff.locator("body").evaluate((body) => {
        const text =
          body.innerText +
          "\n" +
          [...body.querySelectorAll("[aria-label]")]
            .map((n) => n.getAttribute("aria-label") || "")
            .join("\n");
        return Object.fromEntries(
          [
            "Check-in berhasil",
            "Sudah terdaftar",
            "MENUNGGU",
            "belum dapat dipastikan",
            "belum tersinkron",
            "Kamera tidak tersedia",
            "QR Check-in Otomatis",
          ].map((s) => [s, text.includes(s)]),
        );
      });
      console.error(
        "Final QA scan diagnostics: " + JSON.stringify(report.scanUi),
      );
      throw error;
    }
    await button(staff, "Tutup");
    pass(
      "one-scan-camera",
      "Actual Flutter QR decoder → atomic auto-antrean; controlled Y4M camera input, no physical camera claim",
    );
    phase = "queue-commands";
    await doctor.bringToFront();
    const speechCount = (d) => d.p.evaluate(() => window.__qaSpeech);
    const before = await speechCount(a);
    const called = await uiMutation(staff, "/queue/panggil", () =>
      button(staff, "Panggil berikutnya"),
    );
    assert.equal(called.tiketId, walk.id);
    for (const d of [a, c]) {
      await d.p.bringToFront();
      await expect(
        d.p.getByText(walk.nomorAntrean, { exact: true }).first(),
      ).toBeVisible();
      await expect.poll(() => speechCount(d)).toBeGreaterThan(before);
    }
    assert.equal(await speechCount(other), 1); // Activation sample only; no call from clinic A.
    assert.equal(
      await other.p.getByText(walk.nomorAntrean, { exact: true }).count(),
      0,
    );
    await expect(
      doctor
        .getByText("Dipanggil", { exact: true })
        .or(doctor.locator('[aria-label*="Dipanggil"]'))
        .first(),
    ).toBeVisible();
    const count = await speechCount(a);
    await uiMutation(staff, "/queue/" + walk.id + "/panggil-ulang", () =>
      button(staff, "Panggil Ulang"),
    );
    await expect.poll(() => speechCount(a)).toBe(count + 1);
    await uiMutation(staff, "/queue/" + walk.id + "/lewati", () =>
      button(staff, "Lewati"),
    );
    await button(staff, "Aksi " + walk.nomorAntrean);
    await uiMutation(staff, "/queue/" + walk.id + "/antre-ulang", () =>
      staff
        .getByRole("menuitem", { name: "Kembalikan ke Antrean", exact: true })
        .click(),
    );
    await uiMutation(staff, "/queue/panggil", () =>
      button(staff, "Panggil berikutnya"),
    );
    await uiMutation(staff, "/queue/" + walk.id + "/mulai-pelayanan", () =>
      button(staff, "Mulai Pelayanan"),
    );
    await expect(
      doctor
        .getByText("Dilayani", { exact: true })
        .or(doctor.locator('[aria-label*="Dilayani"]'))
        .first(),
    ).toBeVisible();
    await uiMutation(staff, "/queue/" + walk.id + "/selesaikan-pelayanan", () =>
      button(staff, "Selesaikan Pelayanan"),
    );
    const final = await request("/tiket/" + walk.id, undefined, walkToken);
    assert.equal(final.status, "SELESAI");
    await patient.reload();
    // Web deliberately uses MemorySessionStore; reload requires authentication.
    await expect(
      patient.getByRole("textbox", { name: "Email", exact: true }),
    ).toBeVisible();
    const persistedBearer = await patient.evaluate(() =>
      [localStorage, sessionStorage].some((s) =>
        Object.values(s).some((v) =>
          /eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\./.test(v),
        ),
      ),
    );
    assert.equal(persistedBearer, false);
    await enter(patient, "Email", f.patient2.email);
    await enter(patient, "Kata sandi", f.patient2.password);
    await button(patient, "Masuk");
    await expect(
      patient.getByRole("tab", { name: "Beranda", exact: true }),
    ).toBeVisible();
    pass(
      "web-session-policy",
      "Reload returns login; no bearer JWT in Web local/session storage; explicit re-login follows MemorySessionStore contract",
    );
    await patient.getByRole("tab", { name: "Tiket Saya", exact: true }).click();
    await expect(
      patient
        .getByText("Selesai", { exact: true })
        .or(patient.locator('[aria-label*="Selesai"]'))
        .first(),
    ).toBeVisible();
    assert.ok(doctorMethods.length && doctorMethods.every((m) => m === "GET"));
    pass(
      "queue-six-commands",
      "PETUGAS UI CALL/RECALL/SKIP/REQUEUE/START/COMPLETE; live doctor monitoring, patient final SELESAI, scoped display/TTS",
    );
    phase = "appointment-through-complete";
    const appointmentId = appointment.tiket.id;
    const apptQr = await request(
      "/tiket/" + appointmentId + "/qr",
      {},
      patientToken,
    );
    cameraVideo(apptQr.qrPayload, video);
    const checkedAppt = await uiMutation(staff, "/check-in/auto-antrean", () =>
      staff.getByRole("button", { name: /Pindai QR/ }).click(),
    );
    assert.equal(checkedAppt.tiketId, appointmentId);
    assert.equal(checkedAppt.status, "MENUNGGU");
    await expect(
      staff
        .getByText("Check-in berhasil. Pasien masuk antrean.", { exact: false })
        .or(
          staff.locator(
            '[aria-label*="Check-in berhasil. Pasien masuk antrean."]',
          ),
        )
        .first(),
    ).toBeVisible();
    await button(staff, "Tutup");
    while (Date.now() < new Date(f.slotStart).getTime()) {
      await new Promise((resolve) =>
        setTimeout(
          resolve,
          Math.min(30000, new Date(f.slotStart).getTime() - Date.now() + 50),
        ),
      );
    }
    const apptCall = await uiMutation(staff, "/queue/panggil", () =>
      button(staff, "Panggil berikutnya"),
    );
    assert.equal(apptCall.tiketId, appointmentId);
    await uiMutation(
      staff,
      "/queue/" + appointmentId + "/mulai-pelayanan",
      () => button(staff, "Mulai Pelayanan"),
    );
    await uiMutation(
      staff,
      "/queue/" + appointmentId + "/selesaikan-pelayanan",
      () => button(staff, "Selesaikan Pelayanan"),
    );
    assert.equal(
      (await request("/tiket/" + appointmentId, undefined, patientToken))
        .status,
      "SELESAI",
    );
    const appointmentPatient = await open(b, "patient1", {
      width: 390,
      height: 844,
    });
    await appointmentPatient
      .getByRole("tab", { name: "Tiket Saya", exact: true })
      .click();
    await expect(
      appointmentPatient
        .getByText("Selesai", { exact: true })
        .or(appointmentPatient.locator('[aria-label*="Selesai"]'))
        .first(),
    ).toBeVisible();
    await shot(appointmentPatient, "patient-appointment-complete");
    await appointmentPatient.context().close();
    pass(
      "appointment-through-complete",
      "Real patient REST booking → second decoded QR → PETUGAS UI CALL/START/COMPLETE at actual slot start → patient UI SELESAI",
    );
    assert.equal(other.events.filter((e) => e === "updated").length, 0);
    assert.ok(
      displays.every((d) => d.snapshots.every((s) => s.selector === d.id)),
    );
    await button(a.p, "Layar penuh");
    await expect
      .poll(() => a.p.evaluate(() => document.fullscreenElement !== null))
      .toBe(true);
    await button(a.p, "Keluar fullscreen");
    await expect
      .poll(() => a.p.evaluate(() => document.fullscreenElement === null))
      .toBe(true);
    pass(
      "fullscreen",
      "Actual Chrome fullscreen enter/exit after user gesture; no physical monitor claim",
    );
    phase = "reconnect-rotate-revoke";
    const spoken = await speechCount(a);
    await button(a.p, "Muat ulang");
    assert.equal(await speechCount(a), spoken);
    const readyBefore = a.events.filter((e) => e === "ready").length;
    assert.equal(f.disconnectDisplay(a.id), 1);
    await expect
      .poll(() => a.events.filter((e) => e === "ready").length)
      .toBeGreaterThan(readyBefore);
    for (const d of displays) {
      await d.p.bringToFront();
      await expect(
        d.p.getByText("Realtime terhubung", { exact: true }),
      ).toBeVisible();
    }
    assert.equal(await speechCount(a), spoken);
    pass(
      "short-reconnect",
      "Server closes only A Engine.IO transport; actual new display:ready observed; B/C remain connected; refresh/reconnect silent",
    );
    const rotated = (
      await request("/perangkat-display/" + a.id + "/aktivasi", {}, adminToken)
    ).kode;
    await a.p.bringToFront();
    await expect(
      a.p.getByText("Akses display ditolak", { exact: true }),
    ).toBeVisible();
    for (const d of [other, c]) {
      await d.p.bringToFront();
      await expect(
        d.p.getByText("Realtime terhubung", { exact: true }),
      ).toBeVisible();
    }
    await button(a.p, "Ganti perangkat");
    await enter(a.p, "Kode Aktivasi", rotated);
    await button(a.p, "Hubungkan Perangkat");
    await expect(
      a.p.getByText("Realtime terhubung", { exact: true }),
    ).toBeVisible();
    await request(
      "/perangkat-display/" + a.id + "/nonaktifkan",
      {},
      adminToken,
    );
    await expect(
      a.p.getByText("Akses display ditolak", { exact: true }),
    ).toBeVisible();
    for (const d of [other, c]) {
      await d.p.bringToFront();
      await expect(
        d.p.getByText("Realtime terhubung", { exact: true }),
      ).toBeVisible();
    }
    pass(
      "rotate-revoke-active",
      "Active Socket.IO session A invalidated without API refresh; B/C remain connected; A re-pairs before revoke",
    );
    await shot(c.p, "display-final");
    await shot(staff, "staff-final");
    await shot(doctor, "doctor-final");
    assert.equal(errors.length, 0);
    pass("runtime", "No uncaught browser pageerror across tested portals");
  } catch (error) {
    if (
      phase === "native-audio" &&
      nativeDiagnosticPage &&
      !nativeDiagnosticPage.isClosed()
    ) {
      report.nativeAudio.callbacks = await nativeDiagnosticPage.evaluate(
        () => window.__nativeSpeech,
      );
      console.error(
        "Final QA native diagnostics: " +
          JSON.stringify(report.nativeAudio.callbacks),
      );
    }
    // Playwright errors may contain typed credentials/codes/QR. Emit only phase/type.
    report.scenarios.push({
      id: phase,
      status: "FAIL",
      level: "Browser E2E",
      detail:
        "Assertion/action failed (" +
        error.name +
        "); no secret-bearing diagnostics persisted",
    });
    console.error("Final QA failed phase: " + phase + " / " + error.name);
    // Local-only structural diagnostics: no input values, no arbitrary DOM dump.
    if (process.env.QA_CONTROL_DIAGNOSTICS === "true")
      console.error(
        error.stack
          ?.split("\n")
          .filter((l) => l.includes("browser-final-e2e.cjs"))
          .join("\n"),
      );
    throw new Error("Final browser QA failed in " + phase);
  } finally {
    clearTimeout(deadline);
    report.runtimeErrors = errors.length;
    report.finishedAt = new Date().toISOString();
    fs.writeFileSync(
      path.join(output, "browser-final.json"),
      JSON.stringify(report, null, 2) + "\n",
    );
    for (const c of contexts) await c.close().catch(() => {});
    for (const b of browsers) await b.close().catch(() => {});
    if (fs.existsSync(video)) fs.unlinkSync(video);
  }
};
