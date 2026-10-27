// ADMIN-only visual/interaction QA. Synthetic HTTP fixtures; no database.
const fs = require("node:fs"),
  path = require("node:path"),
  http = require("node:http");
const { randomUUID, createHash } = require("node:crypto"),
  assert = require("node:assert/strict");
const { chromium, expect: baseExpect } = require("@playwright/test");
const expect = baseExpect.configure({ timeout: 30000 });
module.exports = async ({
  build,
  output,
  engineRoot,
  fontFile,
  baseline = false,
}) => {
  fs.mkdirSync(output, { recursive: true });
  const report = {
    mode: baseline
      ? "Baseline ADMIN Chrome capture, synthetic data"
      : "Real Chrome release Flutter, synthetic ADMIN API, no database",
    buildSha256: createHash("sha256")
      .update(fs.readFileSync(path.join(build, "main.dart.js")))
      .digest("hex"),
    states: {},
    viewports: [],
    errors: [],
  };
  const id = randomUUID(),
    roomId = randomUUID(),
    doctorId = randomUUID(),
    practiceId = randomUUID(),
    slotId = randomUUID(),
    staffId = randomUUID(),
    deviceId = randomUUID();
  const today = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Jakarta",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
  const clinic = {
    id,
    nama: "Poli Anak",
    kode: "ANAK",
    prefixAntrean: "AN",
    aktif: true,
    modeReservasi: "HIBRIDA",
    durasiDasarMenit: 15,
    kapasitasHarian: 24,
  };
  const unused = {
    ...clinic,
    id: randomUUID(),
    nama: "Poli QA Belum Digunakan",
    kode: "QA99",
    prefixAntrean: "QA",
  };
  const room = {
    id: roomId,
    nama: "Ruang Anak 1",
    kode: "AN01",
    lokasi: "Lantai 1",
    aktif: true,
    layananId: id,
    layanan: clinic,
  };
  const doctor = {
    id: doctorId,
    nama: "dr. Sindi Rohmawati Setyana",
    kode: "DR001",
    spesialisasi: "Anak",
    aktif: true,
    fotoProfil: null,
    penggunaId: null,
    dokterLayanan: [
      { id: randomUUID(), layananId: id, layanan: clinic, aktif: true },
    ],
  };
  const daily = {
    id: randomUUID(),
    hari: "SENIN",
    jamBuka: "08:00",
    jamTutup: "16:00",
    kapasitasHarian: 24,
    aktif: true,
    layananId: id,
    layanan: clinic,
  };
  const practice = {
    id: practiceId,
    tanggal: today,
    mulaiPada: today + "T01:00:00Z",
    selesaiPada: today + "T09:00:00Z",
    aktif: true,
    loketId: roomId,
    loket: room,
    dokterLayanan: {
      id: doctor.dokterLayanan[0].id,
      dokterId: doctorId,
      dokter: doctor,
      layananId: id,
      layanan: clinic,
    },
  };
  const slot = {
    id: slotId,
    mulaiPada: today + "T01:00:00Z",
    selesaiPada: today + "T01:30:00Z",
    kapasitas: 2,
    jumlahJanjiTemu: 0,
    sisaKapasitas: 2,
    tersedia: true,
    aktif: true,
    jadwalPraktikId: practiceId,
  };
  const staff = {
    id: staffId,
    nama: "Siti Rahma QA",
    email: "staff@fixture.local",
    peran: "PETUGAS",
    aktif: true,
  };
  const assignment = {
    id: randomUUID(),
    petugasId: staffId,
    petugas: staff,
    loketId: roomId,
    loket: room,
    tanggalMulai: today,
    tanggalSelesai: null,
    aktif: true,
  };
  const device = {
    id: deviceId,
    nama: "TV Poli Anak",
    aktif: true,
    layananId: id,
    layanan: clinic,
    terakhirAktifPada: null,
  };
  const store = {
    "/layanan": [clinic, unused],
    "/dokter": [doctor],
    "/loket": [room],
    "/jadwal-layanan": [daily],
    "/jadwal-praktik": [practice],
    "/slot-praktik": [slot],
    "/akun-petugas": [staff],
    "/penugasan-petugas": [assignment],
    "/perangkat-display": [device],
  };
  const auth = {
    accessToken: "fixture-admin-only",
    refreshToken: "fixture-refresh-only",
    user: {
      id: randomUUID(),
      nama: "Administrator QA",
      peran: "ADMIN",
      email: "fixture@test.local",
      aktif: true,
    },
  };
  const requests = [];
  let base, browser, page;
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
        requests.push({
          method: req.method,
          path: p,
          query: Object.fromEntries(u.searchParams),
        });
        if (p === "/auth/login") {
          assert.equal(body.email, "fixture@test.local");
          assert.equal(body.kataSandi, "fixture-only");
          return send(auth);
        }
        if (p === "/auth/refresh") return send(auth);
        if (p === "/auth/logout") return send({ ok: true });
        if (req.headers.authorization !== "Bearer " + auth.accessToken)
          return send({}, 401);
        if (p === "/auth/me") return send(auth.user);
        if (req.method === "GET" && store[p]) return send(store[p]);
        if (p === "/layanan/" + unused.id && req.method === "PATCH") {
          Object.assign(unused, body);
          return send(unused);
        }
        if (p === "/layanan/" + unused.id && req.method === "DELETE") {
          unused.aktif = false;
          return send(unused);
        }
        if (
          p === "/layanan/" + unused.id + "/permanen" &&
          req.method === "DELETE"
        ) {
          store["/layanan"] = store["/layanan"].filter(
            (c) => c.id !== unused.id,
          );
          return send({ dihapus: true });
        }
        if (p.endsWith("/permanen"))
          return send(
            { message: "Data masih digunakan; gunakan Nonaktifkan." },
            409,
          );
        return send({ message: "Unsupported fixture operation" }, 404);
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
          "http://localhost:3000/api/v1",
          "http://127.0.0.1:3003/api/v1",
          "http://localhost:3001/api/v1",
        ];
        const define = defines.find((v) => source.includes(v));
        assert.ok(define, "Expected local QA API define absent");
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
  try {
    await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
    base = "http://127.0.0.1:" + server.address().port;
    browser = await chromium.launch({ channel: "chrome", headless: true });
    report.chrome = browser.version();
    const context = await browser.newContext({
      viewport: { width: 1366, height: 768 },
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
    const text = (value) =>
      page.getByText(value).or(page.getByLabel(value)).last();
    const press = (name) =>
      page
        .getByRole("button", {
          name: new RegExp("^" + name + "$"),
          includeHidden: true,
        })
        .click();
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
    await page.goto(base, { waitUntil: "domcontentloaded" });
    await page
      .locator("flt-glass-pane")
      .waitFor({ state: "attached", timeout: 60000 });
    await expect
      .poll(async () => {
        const p = page.locator("flt-semantics-placeholder");
        if (await p.count()) await p.evaluate((el) => el.click());
        return page.getByRole("button", { name: "Masuk", exact: true }).count();
      })
      .toBe(1);
    await type("Email", "fixture@test.local");
    await type("Kata sandi", "fixture-only");
    await press("Masuk");
    async function nav(name) {
      if (page.viewportSize().width < 960) await press("Menu administrasi");
      await page
        .getByRole("button", { name, exact: true })
        .or(page.getByRole("tab", { name, exact: true }))
        .first()
        .click();
    }
    async function menu(label) {
      await page.waitForTimeout(300);
      const button = page
        .getByRole("cell")
        .filter({ hasText: /^Aksi / })
        .or(page.getByRole("button", { name: /^Aksi / }))
        .first();
      await button.waitFor({ state: "visible" });
      let box = await button.boundingBox();
      if (box.x + 44 > page.viewportSize().width) {
        const table = await page.getByRole("table").first().boundingBox();
        await page.mouse.move(
          page.viewportSize().width / 2,
          Math.min(page.viewportSize().height - 40, box.y + box.height / 2),
        );
        for (
          let attempt = 0;
          attempt < 4 &&
          (await button.boundingBox()).x + 44 > page.viewportSize().width;
          attempt++
        ) {
          await page.mouse.wheel(1200, 0);
          await page.waitForTimeout(250);
        }
        await expect
          .poll(async () => (await button.boundingBox()).x + 44)
          .toBeLessThan(page.viewportSize().width);
        box = await button.boundingBox();
      }
      await button.click({
        position: { x: Math.min(44, box.width / 2), y: box.height / 2 },
      });
      await expect(text(label)).toBeVisible();
    }
    await nav("Dokter");
    await expect(text(doctor.nama)).toBeVisible();
    await page.mouse.move(0, 0);
    await page.waitForTimeout(1000);
    if (baseline) {
      await page.screenshot({
        path: path.join(output, "doctor-before-1366x768.png"),
      });
      report.success = true;
      fs.writeFileSync(
        path.join(output, "report.json"),
        JSON.stringify(report, null, 2),
      );
      return report;
    }
    await expect(text("Administrator QA")).toHaveCount(0);
    await expect(text("Zona pelayanan: Asia/Jakarta")).toHaveCount(0);
    for (const [width, height] of [
      [1366, 768],
      [1920, 1080],
      [768, 1024],
      [390, 844],
    ]) {
      await page.setViewportSize({ width, height });
      await page.waitForTimeout(200);
      await page.mouse.move(0, 0);
      const metrics = await page.evaluate(() => ({
        width: innerWidth,
        height: innerHeight,
        scrollWidth: document.scrollingElement.scrollWidth,
      }));
      assert.equal(metrics.width, metrics.scrollWidth);
      report.viewports.push(metrics);
      await page.screenshot({
        path: path.join(output, `doctor-after-${width}x${height}.png`),
      });
      await menu("Ubah profil");
      await text("Ubah profil").click();
      await expect(text("Ubah Dokter")).toBeVisible();
      await press("Kembali");
    }
    report.states.responsiveDoctorMenus = true;
    await page.setViewportSize({ width: 1366, height: 768 });
    await page.waitForTimeout(200);
    await page.screenshot({
      path: path.join(output, "header-admin.png"),
      clip: { x: 0, y: 0, width: 1366, height: 52 },
    });
    for (const [module, label] of [
      ["Poliklinik", "Hapus"],
      ["Dokter", "Hubungkan poliklinik"],
      ["Ruang & loket", "Ubah"],
      ["Jadwal praktik", "Ubah"],
      ["Penugasan petugas", "Nonaktifkan akun"],
      ["Manajemen Display", "Kode aktivasi / rotasi"],
    ]) {
      await nav(module);
      if (module === "Ruang & loket")
        await page.getByRole("button", { name: /^Poli Anak / }).click();
      await menu(label);
      await page.mouse.click(page.viewportSize().width / 2, 26);
      await page.waitForTimeout(100);
      if (module === "Jadwal praktik") {
        await expect(text("Dari tanggal (YYYY-MM-DD)")).toHaveCount(0);
        await expect(text("Sampai tanggal (YYYY-MM-DD)")).toHaveCount(0);
        await page.screenshot({
          path: path.join(output, "practice-schedules.png"),
        });
      }
      if (module === "Penugasan petugas") {
        await page
          .getByRole("tab", { name: "Penugasan Loket", exact: true })
          .click();
        await menu("Ubah");
        await page.mouse.click(page.viewportSize().width / 2, 26);
        await page.waitForTimeout(100);
      }
    }
    await nav("Jam & kapasitas poli");
    await page.getByRole("button", { name: /^Poli Anak / }).click();
    await menu("Ubah");
    await page.mouse.click(page.viewportSize().width / 2, 26);
    await page.waitForTimeout(100);
    await nav("Slot konsultasi");
    await page.getByRole("button", { name: /^Poli Anak / }).click();
    await page
      .getByRole("button", { name: new RegExp("^" + doctor.nama) })
      .click();
    await page.getByRole("button", { name: new RegExp("^" + today) }).click();
    await menu("Ubah");
    await page.mouse.click(page.viewportSize().width / 2, 26);
    await page.waitForTimeout(100);
    await expect(text("Dari tanggal (YYYY-MM-DD)")).toHaveCount(0);
    await expect(text("Sampai tanggal (YYYY-MM-DD)")).toHaveCount(0);
    await page.screenshot({
      path: path.join(output, "consultation-slots.png"),
    });
    report.states.allModuleMenus = true;
    report.states.noDateRangeFilters = true;
    await nav("Poliklinik");
    await type("Cari nama atau kode", "Belum Digunakan");
    await menu("Ubah");
    await text("Ubah").click();
    await type("Nama", "Poli QA Diperbarui");
    await press("Simpan");
    await expect.poll(() => unused.nama).toBe("Poli QA Diperbarui");
    await type("Cari nama atau kode", "Diperbarui");
    await menu("Nonaktifkan");
    await text("Nonaktifkan").click();
    await press("Lanjutkan");
    await expect.poll(() => unused.aktif).toBe(false);
    await menu("Hapus");
    await text("Hapus").click();
    await type("Konfirmasi kode/nama", "QA99");
    await press("Hapus Permanen");
    await expect.poll(() => store["/layanan"].length).toBe(1);
    await expect(text("0 dari 1 data")).toBeVisible();
    report.states.editDeactivateDeleteRetainsSearch = true;
    await page
      .getByRole("button", { name: /Profil (akun|Saya)/ })
      .or(page.getByRole("button", { name: "Profil Saya", exact: true }))
      .first()
      .click();
    await expect(text("Profil Saya")).toBeVisible();
    await page.getByRole("button", { name: /^(Back|Kembali)$/ }).click();
    await press("Keluar akun");
    await expect(
      page.getByRole("button", { name: "Masuk", exact: true }),
    ).toBeVisible();
    report.states.profileAndLogout = true;
    assert.deepEqual(report.errors, []);
    report.success = true;
    fs.writeFileSync(
      path.join(output, "report.json"),
      JSON.stringify(report, null, 2),
    );
    return report;
  } catch (e) {
    report.error = e.message;
    report.requests = requests;
    if (page) {
      report.roles = await page
        .locator("[role]")
        .evaluateAll((nodes) =>
          nodes.map((n) => ({
            role: n.getAttribute("role"),
            label: n.getAttribute("aria-label"),
            text: n.innerText,
          })),
        )
        .catch(() => []);
      report.labels = await page
        .locator("[aria-label]")
        .evaluateAll((nodes) => nodes.map((n) => n.getAttribute("aria-label")))
        .catch(() => []);
      report.bodyText = await page
        .locator("body")
        .innerText()
        .catch(() => "");
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
    if (server.listening) await new Promise((resolve) => server.close(resolve));
  }
};
