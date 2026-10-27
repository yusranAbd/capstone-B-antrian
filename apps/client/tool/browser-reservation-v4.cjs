// Real release Flutter in Chrome; synthetic API + Socket.IO only, no database.
const fs = require("node:fs"),
  path = require("node:path"),
  http = require("node:http");
const { randomUUID, createHash } = require("node:crypto"),
  assert = require("node:assert/strict");
const { chromium, expect: baseExpect } = require("@playwright/test");
const { Server } = require("socket.io");
const expect = baseExpect.configure({ timeout: 30000 });
module.exports = async ({
  build,
  output,
  engineRoot,
  fontFile,
  patientV5 = false,
  patientFocus = false,
  finalExperience = false,
}) => {
  fs.mkdirSync(output, { recursive: true });
  const report = {
    buildSha256: createHash("sha256")
      .update(fs.readFileSync(path.join(build, "main.dart.js")))
      .digest("hex"),
    testedAt: new Date().toISOString(),
    mode: "Real Chrome release Flutter; synthetic HTTP/Socket.IO, no database or real credentials",
    states: {},
    viewports: [],
    errors: [],
  };
  const ids = Array.from({ length: 9 }, randomUUID);
  const today = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Jakarta",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
  const shift = (days) => {
    const d = new Date(today + "T00:00:00Z");
    d.setUTCDate(d.getUTCDate() + days);
    return d.toISOString().slice(0, 10);
  };
  const tomorrow = shift(1),
    yesterday = shift(-1);
  const clinics = [
    {
      id: ids[0],
      nama: "Penyakit Dalam",
      kode: "PD",
      prefixAntrean: "PD",
      aktif: true,
      modeReservasi: "HIBRIDA",
    },
    {
      id: ids[1],
      nama: "Poli Walk-in",
      kode: "UM",
      prefixAntrean: "UM",
      aktif: true,
      modeReservasi: "ANTREAN_HARIAN",
    },
  ];
  const doctor = {
    id: ids[2],
    nama: "dr. Indah Suci Permatasari, Sp.PD",
    spesialisasi: "Penyakit Dalam",
    aktif: true,
    fotoProfil: null,
    dokterLayanan: [
      {
        id: ids[3],
        layananId: clinics[0].id,
        layanan: clinics[0],
        aktif: true,
      },
    ],
  };
  const schedule = {
    id: ids[4],
    aktif: true,
    tanggal: tomorrow,
    mulaiPada: tomorrow + "T01:00:00Z",
    selesaiPada: tomorrow + "T05:00:00Z",
    loket: {
      id: ids[5],
      kode: "PD01",
      nama: "Ruang Penyakit Dalam 1",
      aktif: true,
    },
    dokterLayanan: {
      id: ids[3],
      dokterId: doctor.id,
      dokter: doctor,
      layananId: clinics[0].id,
      layanan: clinics[0],
      aktif: true,
    },
  };
  const slot = {
    id: ids[6],
    aktif: true,
    tersedia: true,
    sisaKapasitas: 2,
    mulaiPada: tomorrow + "T02:00:00Z",
    selesaiPada: tomorrow + "T02:30:00Z",
    jadwalPraktik: schedule,
  };
  const tickets = [
    {
      id: randomUUID(),
      nomorAntrean: "PD-032",
      status: "DIPESAN",
      tanggalPelayanan: today,
      layanan: clinics[0],
    },
    {
      id: randomUUID(),
      nomorAntrean: "PD-014",
      status: "SELESAI",
      tanggalPelayanan: yesterday,
      layanan: clinics[0],
    },
    {
      id: randomUUID(),
      nomorAntrean: "UM-001",
      status: "MENUNGGU",
      tanggalPelayanan: today,
      layanan: clinics[1],
    },
  ];
  function appt(t) {
    return {
      id: randomUUID(),
      tiket: { ...t },
      slotPraktik: {
        ...slot,
        mulaiPada: t.tanggalPelayanan + "T03:00:00Z",
        selesaiPada: t.tanggalPelayanan + "T03:30:00Z",
        jadwalPraktik: { ...schedule, tanggal: t.tanggalPelayanan },
      },
    };
  }
  const appointments = tickets.slice(0, 2).map(appt),
    requests = [];
  const auth = {
    accessToken: "fixture-patient-only",
    refreshToken: "fixture-refresh-only",
    user: {
      id: ids[8],
      nama: "Gilang QA",
      email: "fixture@test.local",
      peran: "USER",
    },
  };
  let base,
    browser,
    page,
    sequence = 0,
    connections = 0;
  function invalidate() {
    ns.emit("patient:updated", {
      eventId: randomUUID(),
      versiSkema: 1,
      jenis: "TIKET",
      terjadiPada: new Date().toISOString(),
    });
  }
  const server = http.createServer(async (req, res) => {
    const u = new URL(req.url, base || "http://127.0.0.1");
    const send = (d, code = 200) => {
      res.writeHead(code, {
        "Content-Type": "application/json",
        "Cache-Control": "no-store",
      });
      res.end(JSON.stringify(d));
    };
    try {
      if (u.pathname.startsWith("/api/v1/")) {
        const p = u.pathname.replace("/api/v1", "");
        let raw = "";
        for await (const chunk of req) raw += chunk;
        const body = raw ? JSON.parse(raw) : {};
        requests.push({ method: req.method, path: p });
        if (p === "/auth/login") {
          assert.equal(body.email, "fixture@test.local");
          assert.equal(body.kataSandi, "fixture-only");
          return send(auth);
        }
        if (p === "/auth/refresh") return send(auth);
        if (p === "/auth/logout") return send({ ok: true });
        if (req.headers.authorization !== "Bearer " + auth.accessToken)
          return send({}, 401);
        if (p === "/auth/me") {
          if (req.method === "PATCH")
            auth.user = { ...auth.user, nama: body.nama };
          return send(auth.user);
        }
        if (p === "/layanan") return send(clinics);
        if (p === "/dokter") return send([doctor]);
        if (p === "/jadwal-praktik")
          return send(
            u.searchParams.get("layananId") === clinics[1].id ? [] : [schedule],
          );
        if (p === "/slot-praktik") return send([slot]);
        if (p === "/tiket/saya") return send(tickets);
        if (p === "/janji-temu" && req.method === "GET")
          return send(appointments);
        if (p.startsWith("/tiket/")) {
          const t = tickets.find((t) => t.id === p.split("/")[2]);
          if (!t) return send({}, 404);
          if (p.endsWith("/qr")) {
            if (t.status !== "DIPESAN" || t.tanggalPelayanan !== today)
              return send({ message: "QR tidak sah" }, 409);
            return send({
              tiketId: t.id,
              qrPayload: "SQ1." + "A".repeat(43),
              berlakuHingga: new Date(Date.now() + 600000).toISOString(),
            });
          }
          return send(t);
        }
        if (p.endsWith("/batalkan")) {
          const a = appointments.find((a) => a.id === p.split("/")[2]);
          const t = tickets.find((t) => t.id === a?.tiket.id);
          if (!t) return send({}, 404);
          if (t.status !== "DIPESAN")
            return send({ message: "Status berubah" }, 409);
          t.status = "DIBATALKAN";
          invalidate();
          return send({ ...a, tiket: t }, 201);
        }
        if (
          req.method === "POST" &&
          ["/reservasi", "/janji-temu"].includes(p)
        ) {
          const isAppt = p === "/janji-temu";
          assert.deepEqual(
            body,
            isAppt
              ? { slotPraktikId: slot.id }
              : { layananId: clinics[1].id, tanggalAntrean: today },
          );
          const t = {
            id: randomUUID(),
            nomorAntrean:
              (isAppt ? "PD-" : "UM-") +
              String(40 + ++sequence).padStart(3, "0"),
            status: "DIPESAN",
            tanggalPelayanan: isAppt ? tomorrow : today,
            layanan: clinics[isAppt ? 0 : 1],
          };
          tickets.push(t);
          if (isAppt) {
            const a = appt(t);
            appointments.push(a);
            invalidate();
            return send({ ...a, tiket: t }, 201);
          }
          invalidate();
          return send(t, 201);
        }
        return send({ message: "Fixture route unknown" }, 404);
      }
      let file = path.resolve(build, "." + decodeURIComponent(u.pathname));
      if (file === path.resolve(build)) file = path.join(file, "index.html");
      if (!file.startsWith(path.resolve(build) + path.sep)) {
        res.writeHead(403);
        return res.end();
      }
      let bytes = fs.readFileSync(file);
      if (file.endsWith("main.dart.js")) {
        const source = bytes.toString();
        const defines = [
          "https://api.queueb.invalid/api/v1",
          "http://localhost:3000/api/v1",
          "http://127.0.0.1:3003/api/v1",
          "http://localhost:3001/api/v1",
        ];
        const define = defines.find((v) => source.includes(v));
        assert.ok(define, "Expected isolated QA API define absent");
        bytes = Buffer.from(source.replaceAll(define, base + "/api/v1"));
      }
      const mime = {
        ".html": "text/html",
        ".js": "text/javascript",
        ".json": "application/json",
        ".wasm": "application/wasm",
        ".png": "image/png",
        ".webp": "image/webp",
        ".ttf": "font/ttf",
        ".otf": "font/otf",
      };
      res.writeHead(200, {
        "Content-Type": mime[path.extname(file)] || "application/octet-stream",
        "Cache-Control": "no-store",
      });
      res.end(bytes);
    } catch (e) {
      report.errors.push("Fixture server: " + e.message);
      if (!res.headersSent) send({}, 500);
      else res.end();
    }
  });
  const io = new Server(server),
    ns = io.of("/patient");
  ns.use((socket, next) =>
    socket.handshake.auth.token === auth.accessToken
      ? next()
      : next(new Error("Unauthorized fixture")),
  );
  ns.on("connection", (socket) => {
    connections++;
    socket.emit("patient:ready", { versiSkema: 1 });
  });
  try {
    await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
    base = "http://127.0.0.1:" + server.address().port;
    browser = await chromium.launch({ channel: "chrome", headless: true });
    report.chrome = browser.version();
    const context = await browser.newContext({
      viewport: { width: 390, height: 844 },
      serviceWorkers: "block",
    });
    await context.route("**/*", (route) => {
      const u = new URL(route.request().url());
      if (u.hostname === "fonts.gstatic.com")
        return route.fulfill({
          body: fs.readFileSync(fontFile),
          contentType: "font/ttf",
          headers: { "Access-Control-Allow-Origin": "*" },
        });
      if (
        u.hostname === "www.gstatic.com" &&
        u.pathname.startsWith("/flutter-canvaskit/")
      ) {
        const file = path.resolve(
          engineRoot,
          u.pathname.split("/").slice(3).join("/"),
        );
        assert.ok(file.startsWith(path.resolve(engineRoot) + path.sep));
        return route.fulfill({
          body: fs.readFileSync(file),
          contentType: file.endsWith(".wasm")
            ? "application/wasm"
            : "text/javascript",
          headers: { "Access-Control-Allow-Origin": "*" },
        });
      }
      return u.origin === base ? route.continue() : route.abort();
    });
    page = await context.newPage();
    page.on("pageerror", (e) => report.errors.push(e.message));
    const perf = await context.newCDPSession(page);
    await perf.send("Performance.enable");
    async function memorySample() {
      const raw = await perf.send("Performance.getMetrics");
      const metrics = Object.fromEntries(
        raw.metrics.map((m) => [m.name, m.value]),
      );
      return {
        jsHeapMiB: +(metrics.JSHeapUsedSize / 1024 / 1024).toFixed(2),
        taskSeconds: metrics.TaskDuration,
        nodes: metrics.Nodes,
        activeSockets: ns.sockets.size,
      };
    }
    const text = (value) =>
      page.getByText(value).or(page.getByLabel(value)).last();
    // Flutter's generated semantics can temporarily omit an accessible name
    // after engine reload. Match the exact rendered button text as fallback.
    const button = (name) =>
      page
        .getByRole("button", { name, exact: true, includeHidden: true })
        .or(
          page.locator('[role="button"]').filter({
            hasText: new RegExp(
              "^" + name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "$",
            ),
          }),
        )
        .last();
    const press = (name) => button(name).click();
    async function type(name, value) {
      const field = page
        .getByRole("textbox", { name: new RegExp(name), includeHidden: true })
        .first();
      await field.click();
      await field.press("ControlOrMeta+A");
      await field.press("Backspace");
      await field.pressSequentially(value, { delay: 3 });
      await field.press("Tab");
    }
    async function reservations() {
      const nav = page.getByLabel(patientV5 ? "Reservasi" : "Pendaftaran", {
        exact: true,
      });
      // Navigation remains disabled while the existing booking reconciles REST.
      // Retry only this read-only tab selection, never a booking/cancel POST.
      await expect
        .poll(async () => {
          if (await text("Reservasi Saya").count()) return true;
          await nav.click();
          return false;
        })
        .toBe(true);
      await expect(text("Reservasi Saya")).toBeVisible();
      await expect(
        page.getByRole("button", { name: "Muat ulang reservasi", exact: true }),
      ).toBeEnabled();
    }
    await page.goto(base, { waitUntil: "domcontentloaded" });
    await page
      .locator("flt-glass-pane")
      .waitFor({ state: "attached", timeout: 60000 });
    await expect
      .poll(
        async () => {
          const p = page.locator("flt-semantics-placeholder");
          if (await p.count()) await p.evaluate((el) => el.click());
          return button("Masuk").count();
        },
        { timeout: 90000 },
      )
      .toBe(1);
    if (finalExperience) {
      for (const [width, height] of [
        [320, 568],
        [390, 844],
        [1366, 768],
        [1920, 1080],
      ]) {
        await page.setViewportSize({ width, height });
        await page.waitForTimeout(250);
        const widthActual = await page.evaluate(
          () => document.scrollingElement.scrollWidth,
        );
        assert.equal(widthActual, width);
        await page.screenshot({
          path: path.join(output, `login-${width}.png`),
        });
      }
      await page.setViewportSize({ width: 390, height: 844 });
      await press("Pasien baru? Daftar");
      await page.screenshot({ path: path.join(output, "register-390.png") });
      await press("Sudah punya akun? Masuk");
    }
    await type("Email", "fixture@test.local");
    await type("Kata sandi", "fixture-only");
    await press("Masuk");
    await expect(page.getByRole("progressbar")).toHaveCount(0);
    await expect.poll(() => ns.sockets.size).toBe(1);
    report.performance = { initial: await memorySample() };
    if (patientV5) {
      for (const [width, height] of [
        [390, 844],
        [320, 568],
      ]) {
        await page.setViewportSize({ width, height });
        for (const [label, name] of [
          ["Beranda", "home"],
          ["Reservasi", "reservations"],
          ["Tiket Saya", "tickets"],
          ["Janji Temu", "appointments"],
          ["Profil", "profile"],
        ]) {
          await page.getByLabel(label, { exact: true }).click();
          await expect(page.getByRole("progressbar")).toHaveCount(0);
          await page.mouse.move(1, 1);
          await page.waitForTimeout(1200);
          if (label === "Profil")
            await expect(text("Profil Saya")).toBeVisible();
          const metrics = await page.evaluate(() => ({
            width: innerWidth,
            height: innerHeight,
            scrollWidth: document.scrollingElement.scrollWidth,
          }));
          assert.equal(metrics.width, metrics.scrollWidth);
          await page.screenshot({
            path: path.join(output, `after-${name}-${width}.png`),
          });
          if (patientFocus) {
            await expect(
              page.getByRole("button", {
                name: "Aktivitas tiket",
                exact: true,
              }),
            ).toHaveCount(name === "home" ? 1 : 0);
            if (name !== "profile") {
              await expect(text("Gilang QA")).toHaveCount(0);
              await expect(text("Selamat datang,")).toHaveCount(0);
            }
            const canScroll = await page.evaluate(() =>
              [...document.querySelectorAll("flt-semantics")].some(
                (el) =>
                  getComputedStyle(el).overflowY === "scroll" &&
                  el.scrollHeight > el.clientHeight + 128,
              ),
            );
            (report.scrollCases ??= []).push({ page: name, width, canScroll });
            if (canScroll) {
              await page.mouse.move(width / 2, height / 2);
              await page.mouse.wheel(0, 150);
              await page.waitForTimeout(650);
              await expect(
                page.getByLabel("Beranda", { exact: true }),
              ).not.toBeVisible();
              await page.screenshot({
                path: path.join(output, `scrolled-${name}-${width}.png`),
              });
              await page.mouse.wheel(0, -90);
              await expect(
                page.getByLabel("Beranda", { exact: true }),
              ).toBeVisible();
              await page.mouse.wheel(0, -5000);
              await page.waitForTimeout(650);
            }
          }
        }
      }
      report.states.fiveDestinationsAndProfile = true;
      if (patientFocus) {
        report.states.headerRemovedExceptHomeNotification = true;
        report.states.chromeHidesOnWheelDownAndReturnsOnWheelUp = true;
      }
      await page.getByLabel("Beranda", { exact: true }).click();
      await expect(
        page.getByRole("button", { name: /Profil akun/ }),
      ).toHaveCount(0);
      report.states.noHeaderProfile = true;
      // Additional appointment fixture: do not relabel the real walk-in as a doctor visit.
      const walk = tickets.find((t) => t.nomorAntrean === "UM-001");
      const oldStatus = walk.status;
      walk.status = "SELESAI";
      invalidate();
      await expect(text("PD-032")).toBeVisible();
      for (const [width, height] of [
        [390, 844],
        [320, 568],
      ]) {
        await page.setViewportSize({ width, height });
        await page.mouse.move(1, 1);
        await page.waitForTimeout(700);
        await page.screenshot({
          path: path.join(output, `after-home-appointment-${width}.png`),
        });
      }
      walk.status = oldStatus;
      invalidate();
      await expect(text("UM-001")).toBeVisible();
      report.states.appointmentAndWalkInHome = true;
    }
    if (finalExperience) {
      await page.setViewportSize({ width: 390, height: 844 });
      await page.getByLabel("Beranda", { exact: true }).click();
      await page
        .getByRole("button", { name: /Detail Dokter/ })
        .last()
        .click();
      await expect(
        page.getByRole("button", { name: "Buat Janji Temu", exact: true }),
      ).toBeVisible();
      await page.screenshot({
        path: path.join(output, "doctor-detail-390.png"),
      });
      report.states.doctorDetail = true;
    }
    await reservations();
    await expect(text("Reservasi Saya")).toBeVisible();
    await expect(
      page.getByRole("button", { name: "Muat ulang reservasi", exact: true }),
    ).toBeEnabled();
    await page.mouse.move(0, 0);
    await page.waitForTimeout(1800);
    await expect.poll(() => connections).toBeGreaterThan(0);
    for (const [width, height] of [
      [320, 568],
      [375, 812],
      [360, 800],
      [390, 844],
      [412, 915],
      [768, 1024],
      [1366, 768],
      [1920, 1080],
    ]) {
      await page.setViewportSize({ width, height });
      await page.waitForTimeout(150);
      const metrics = await page.evaluate(() => ({
        width: innerWidth,
        height: innerHeight,
        scrollWidth: document.scrollingElement.scrollWidth,
      }));
      assert.equal(metrics.width, metrics.scrollWidth);
      await expect(
        page.getByRole("button", { name: "Buat Reservasi", exact: true }),
      ).toBeVisible();
      report.viewports.push(metrics);
      await page.screenshot({
        path: path.join(output, `reservations-${width}x${height}.png`),
      });
    }
    await page.setViewportSize({ width: 390, height: 844 });
    await page.getByLabel("Dipesan", { exact: true }).click();
    await expect(text("PD-032")).toBeVisible();
    await press("Buka Tiket");
    await expect(text("Tiket PD-032")).toBeVisible();
    await expect
      .poll(
        () =>
          requests.filter(
            (r) =>
              r.method === "POST" &&
              r.path === "/tiket/" + tickets[0].id + "/qr",
          ).length,
      )
      .toBe(1);
    await page.screenshot({ path: path.join(output, "correct-ticket-qr.png") });
    assert.ok(
      requests.some(
        (r) =>
          r.method === "POST" && r.path === "/tiket/" + tickets[0].id + "/qr",
      ),
    );
    await press("Tutup");
    report.states.openCorrectTicketQr = true;
    await press("Batalkan Reservasi");
    await expect(text("Batalkan reservasi?")).toBeVisible();
    await press("Ya, Batalkan");
    await page.getByLabel("Dibatalkan", { exact: true }).click();
    await expect(text("PD-032")).toBeVisible();
    await expect(
      page.getByRole("button", { name: "Batalkan Reservasi", exact: true }),
    ).toHaveCount(0);
    report.states.serverCancellation = true;
    await page.getByLabel("Semua", { exact: true }).click();
    await press("Buat Reservasi");
    for (const choice of ["Cari Dokter", "Pilih Poliklinik", "Jadwal Terdekat"])
      await expect(text(choice)).toBeVisible();
    await page.screenshot({ path: path.join(output, "create-sheet.png") });
    await text("Cari Dokter").click();
    await expect(text(doctor.nama)).toBeVisible();
    await page.screenshot({ path: path.join(output, "choose-doctor.png") });
    await press("Pilih Jadwal");
    await press("Lihat slot");
    await text("Sisa slot 2").click();
    if (finalExperience)
      await page.screenshot({ path: path.join(output, "booking-390.png") });
    await press("Lanjutkan");
    if (finalExperience)
      await page.screenshot({
        path: path.join(output, "confirmation-390.png"),
      });
    await press("Konfirmasi Janji Temu");
    await expect.poll(() => tickets.length).toBe(4);
    assert.equal(
      requests.filter((r) => r.method === "POST" && r.path === "/janji-temu")
        .length,
      1,
    );
    report.states.doctorBooking = true;
    await reservations();
    await press("Buat Reservasi");
    await text("Pilih Poliklinik").click();
    await text("Poli Walk-in").click();
    await type("Tanggal pelayanan", today);
    await press("Reservasi walk-in");
    await press("Lanjutkan");
    await expect.poll(() => tickets.length).toBe(5);
    assert.equal(
      requests.filter((r) => r.method === "POST" && r.path === "/reservasi")
        .length,
      1,
    );
    report.states.walkInBooking = true;
    await reservations();
    await press("Buat Reservasi");
    await text("Jadwal Terdekat").click();
    await expect(text("Slot tersedia")).toBeVisible();
    await press("Pilih Jadwal");
    await expect(
      page.getByRole("button", { name: "Lanjutkan", exact: true }),
    ).toBeEnabled();
    report.states.nearestActualSlot = true;
    await reservations();
    await page.getByLabel("Semua", { exact: true }).click();
    const before = connections;
    for (const socket of ns.sockets.values()) socket.conn.close();
    await expect.poll(() => connections).toBeGreaterThan(before);
    const reads = requests.filter((r) => r.path === "/tiket/saya").length;
    tickets[2].status = "DILEWATI";
    invalidate();
    await expect
      .poll(() => requests.filter((r) => r.path === "/tiket/saya").length)
      .toBeGreaterThan(reads);
    await expect(text("Dilewati")).toBeVisible();
    report.states.realtimeAndReconnect = true;
    await page.reload({ waitUntil: "domcontentloaded" });
    await expect
      .poll(
        async () => {
          const p = page.locator("flt-semantics-placeholder");
          if (await p.count()) await p.evaluate((el) => el.click());
          return button("Masuk").count();
        },
        { timeout: 90000 },
      )
      .toBe(1);
    // Existing Web policy is memory-only; Android secure persistence is unchanged.
    await type("Email", "fixture@test.local");
    await type("Kata sandi", "fixture-only");
    await press("Masuk");
    await reservations();
    await expect(text("Reservasi Saya")).toBeVisible();
    report.states.reloadAndLoginAgain = true;
    if (finalExperience) {
      await page.getByLabel("Profil", { exact: true }).click();
      await type("Nama lengkap", "Gilang QA Terverifikasi");
      await press("Simpan Perubahan");
      await expect.poll(() => auth.user.nama).toBe("Gilang QA Terverifikasi");
      report.states.profileSaved = true;
      await press("Keluar Akun");
      await expect(button("Masuk")).toBeVisible();
      await type("Email", "fixture@test.local");
      await type("Kata sandi", "fixture-only");
      await press("Masuk");
      await expect(page.getByLabel("Beranda", { exact: true })).toBeVisible();
      await expect.poll(() => ns.sockets.size).toBe(1);
      report.states.logoutAndLoginAgain = true;
    }
    report.performance.afterFlows = await memorySample();
    report.performance.navigationCycles = [];
    if (finalExperience) {
      for (let round = 0; round < 3; round++) {
        for (const label of [
          "Beranda",
          "Reservasi",
          "Tiket Saya",
          "Janji Temu",
          "Profil",
        ]) {
          const target = page.getByLabel(label, { exact: true });
          if (!(await target.isVisible())) {
            await page.mouse.move(195, 422);
            await page.mouse.wheel(0, -5000);
            await expect(target).toBeVisible();
          }
          await target.click();
          await page.waitForTimeout(350);
        }
        report.performance.navigationCycles.push(await memorySample());
      }
      await page.waitForTimeout(5000);
      report.performance.afterIdle = await memorySample();
      assert.equal(ns.sockets.size, 1);
      report.states.navigationResourceCheck = true;
    }
    assert.deepEqual(report.errors, []);
    report.success = true;
    fs.writeFileSync(
      path.join(output, "report.json"),
      JSON.stringify(report, null, 2),
    );
    return report;
  } catch (e) {
    report.requests = requests;
    report.error = e.stack || e.message;
    if (page) {
      report.roles = await page
        .locator("[role]")
        .evaluateAll((nodes) =>
          nodes.map((n) => ({
            role: n.getAttribute("role"),
            label: n.getAttribute("aria-label"),
            text: n.innerText,
            disabled: n.getAttribute("aria-disabled"),
          })),
        )
        .catch(() => []);
      report.bodyText = await page
        .locator("body")
        .innerText()
        .catch(() => "");
      report.labels = await page
        .locator("[aria-label]")
        .evaluateAll((nodes) => nodes.map((n) => n.getAttribute("aria-label")))
        .catch(() => []);
      await page
        .screenshot({ path: path.join(output, "failed.png") })
        .catch(() => {});
    }
    fs.writeFileSync(
      path.join(output, "failed.json"),
      JSON.stringify(report, null, 2),
    );
    throw e;
  } finally {
    if (browser) await browser.close();
    await new Promise((resolve) => io.close(resolve));
    if (server.listening) await new Promise((resolve) => server.close(resolve));
  }
};
