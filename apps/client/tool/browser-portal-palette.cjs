/** Palette rendering QA: real Chrome/release Flutter, synthetic HTTP/socket data.
 * Never reads environment credentials, contacts a database or writes real data. */
const fs = require("node:fs"),
  path = require("node:path"),
  http = require("node:http");
const assert = require("node:assert/strict");
const { randomUUID, createHash } = require("node:crypto");
const { chromium, expect: baseExpect } = require("@playwright/test");
const { Server } = require("socket.io");
const expect = baseExpect.configure({ timeout: 60000 });
module.exports = async ({ build, output, engineRoot, fontFile }) => {
  fs.mkdirSync(output, { recursive: true });
  const report = {
    mode: "Chrome release rendering, synthetic HTTP/Socket.IO, no database",
    buildSha256: createHash("sha256")
      .update(fs.readFileSync(path.join(build, "main.dart.js")))
      .digest("hex"),
    viewports: [],
    errors: [],
    states: {},
  };
  const clinic = {
    id: randomUUID(),
    nama: "Anak",
    kode: "ANAK",
    aktif: true,
    modeReservasi: "HIBRIDA",
  };
  const room = {
    id: randomUUID(),
    kode: "AN01",
    nama: "Ruang Anak QA",
    aktif: true,
    layananId: clinic.id,
    layanan: clinic,
  };
  const doctor = {
    id: randomUUID(),
    nama: "dr. Dokter QA",
    spesialisasi: "Anak",
    aktif: true,
    kode: "DR-QA",
  };
  doctor.dokterLayanan = [
    { id: randomUUID(), layananId: clinic.id, layanan: clinic, aktif: true },
  ];
  const today = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Jakarta",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
  const session = {
    id: randomUUID(),
    tanggal: today,
    aktif: true,
    mulaiPada: today + "T00:00:00+07:00",
    selesaiPada: today + "T23:59:59+07:00",
    loket: room,
    loketId: room.id,
    ruang: room,
    poliklinik: clinic,
    dokterLayanan: { dokter: doctor, layanan: clinic },
  };
  const called = {
    tiketId: randomUUID(),
    nomorAntrean: "AN-001",
    status: "DIPANGGIL",
    dipanggilPada: new Date().toISOString(),
  };
  const waiting = {
    tiketId: randomUUID(),
    nomorAntrean: "AN-002",
    status: "MENUNGGU",
    layakDipanggil: true,
  };
  const device = {
    id: randomUUID(),
    layananId: clinic.id,
    nama: "TV QA",
    aktif: true,
  };
  const displaySnapshot = {
    versiSkema: 1,
    layanan: clinic,
    tanggalPelayanan: today,
    loket: [{ ...room, tiketAktif: [called] }],
    totalMenunggu: 1,
    menunggu: [{ ...waiting, namaPasien: "A." }],
    totalAntrianPasien: 2,
    antrianPasien: [
      { ...waiting, namaPasien: "A." },
      {
        tiketId: randomUUID(),
        nomorAntrean: "AN-003",
        namaPasien: "B.",
        status: "DILEWATI",
      },
    ],
    pengumumanTerakhir: {
      peristiwaId: randomUUID(),
      aksi: "CALL",
      nomorAntrean: "AN-001",
      kodeLoket: "AN01",
      teks: "Nomor antrean AN-001, silakan menuju loket AN01.",
    },
  };
  let base,
    browser,
    paired = false;
  let currentPage;
  const users = {};
  const catalog = {
    "/layanan": [clinic],
    "/dokter": [doctor],
    "/loket": [room],
    "/jadwal-praktik": [session],
    "/jadwal-layanan": [],
    "/penugasan-petugas": [],
    "/perangkat-display": [device],
    "/akun-petugas": [],
  };
  const server = http.createServer(async (req, res) => {
    const u = new URL(req.url, base || "http://127.0.0.1");
    const send = (data, status = 200) => {
      res.writeHead(status, {
        "Content-Type": "application/json",
        "Cache-Control": "no-store",
      });
      res.end(JSON.stringify(data));
    };
    try {
      if (u.pathname.startsWith("/api/v1/")) {
        const p = u.pathname.slice("/api/v1".length);
        if (p === "/auth/login") {
          let raw = "";
          for await (const chunk of req) raw += chunk;
          const body = JSON.parse(raw),
            role = body.email.split("@")[0].toUpperCase();
          assert.ok(["ADMIN", "DOKTER"].includes(role));
          assert.equal(body.kataSandi, "fixture-only");
          const token = "fixture-" + role;
          users[token] = {
            id: randomUUID(),
            peran: role,
            nama: role === "ADMIN" ? "Administrator QA" : doctor.nama,
            email: body.email,
            aktif: true,
          };
          return send({
            accessToken: token,
            refreshToken: token + "-refresh",
            user: users[token],
          });
        }
        if (p === "/display/pairing") {
          let raw = "";
          for await (const chunk of req) raw += chunk;
          assert.equal(JSON.parse(raw).kode, "123456789012");
          paired = true;
          res.setHeader(
            "Set-Cookie",
            "qa_display=fixture-only; Path=/; HttpOnly; SameSite=Strict",
          );
          return send(device);
        }
        if (p === "/display/sesi") return paired ? send(device) : send({}, 401);
        if (p === `/display/${clinic.id}/snapshot`)
          return paired ? send(displaySnapshot) : send({}, 401);
        const user =
          users[(req.headers.authorization || "").replace("Bearer ", "")];
        if (!user) return send({}, 401);
        if (req.method !== "GET") return send({}, 405);
        if (p === "/auth/me") return send(user);
        if (catalog[p]) return send(catalog[p]);
        if (p === "/portal-dokter/profil")
          return send({ ...doctor, poliklinik: [clinic] });
        if (p === "/portal-dokter/jadwal") return send([session]);
        if (p === "/portal-dokter/janji-temu")
          return send([
            {
              ...called,
              poliklinik: clinic,
              ruang: room,
              mulaiPada: session.mulaiPada,
              selesaiPada: session.selesaiPada,
            },
          ]);
        if (p === "/portal-dokter/antrean/snapshot")
          return send({
            sesi: session,
            ruang: room,
            poliklinik: clinic,
            totalMenunggu: 1,
            aktif: [called],
            menunggu: [waiting],
          });
        return send({}, 404);
      }
      let file = path.resolve(build, "." + decodeURIComponent(u.pathname));
      if (file === path.resolve(build)) file = path.join(file, "index.html");
      assert.ok(file.startsWith(path.resolve(build) + path.sep));
      let bytes = fs.readFileSync(file);
      if (file.endsWith("main.dart.js")) {
        const source = bytes.toString();
        assert.ok(source.includes("http://localhost:3000/api/v1"));
        bytes = Buffer.from(
          source.replaceAll("http://localhost:3000/api/v1", base + "/api/v1"),
        );
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
      report.errors.push("Fixture: " + e.message);
      if (!res.headersSent) send({}, 500);
      else res.end();
    }
  });
  const io = new Server(server);
  for (const ns of ["doctor", "display"])
    io.of("/" + ns).on("connection", (s) =>
      s.emit(ns + ":ready", { versiSkema: 1, layananId: clinic.id }),
    );
  try {
    await new Promise((r) => server.listen(0, "127.0.0.1", r));
    base = "http://127.0.0.1:" + server.address().port;
    browser = await chromium.launch({ channel: "chrome", headless: true });
    report.chrome = browser.version();
    for (const role of ["ADMIN", "DOKTER", "DISPLAY"]) {
      paired = false;
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
          const f = path.resolve(
            engineRoot,
            u.pathname.split("/").slice(3).join("/"),
          );
          assert.ok(f.startsWith(path.resolve(engineRoot) + path.sep));
          return route.fulfill({
            body: fs.readFileSync(f),
            contentType: f.endsWith(".wasm")
              ? "application/wasm"
              : "text/javascript",
            headers: { "Access-Control-Allow-Origin": "*" },
          });
        }
        return u.origin === base ? route.continue() : route.abort();
      });
      const page = await context.newPage();
      currentPage = page;
      process.stdout.write("Rendering " + role + "\n");
      page.on("pageerror", (e) => report.errors.push(role + ": " + e.message));
      page.on("console", (m) => {
        if (/overflowed by|RenderFlex/i.test(m.text()))
          report.errors.push(role + ": " + m.text());
      });
      await page.goto(base + (role === "DISPLAY" ? "/#/display" : ""), {
        waitUntil: "domcontentloaded",
      });
      await page.locator("flt-glass-pane").waitFor({ state: "attached" });
      const button = (name) =>
        page.getByRole("button", { name, exact: true, includeHidden: true });
      const input = (label) =>
        page
          .getByRole("textbox", {
            name: new RegExp(label),
            includeHidden: true,
          })
          .first();
      async function type(label, value) {
        const field = input(label);
        await field.click();
        await field.press("ControlOrMeta+A");
        await field.press("Backspace");
        await field.pressSequentially(value, { delay: 3 });
        await field.press("Tab");
      }
      await expect
        .poll(async () => {
          const p = page.locator("flt-semantics-placeholder");
          if (await p.count()) await p.evaluate((e) => e.click());
          return input(role === "DISPLAY" ? "Kode Aktivasi" : "Email").count();
        })
        .toBe(1);
      if (role === "DISPLAY") {
        await type("Kode Aktivasi", "123456789012");
        await page
          .getByRole("button", {
            name: /Aktivasi|Hubungkan|Aktifkan/,
            includeHidden: true,
          })
          .first()
          .click();
        await expect(
          page
            .getByText("AN-001", { exact: true })
            .or(page.getByLabel("AN-001", { exact: true }))
            .first(),
        ).toBeVisible();
        await expect(
          page
            .getByText("Menunggu", { exact: true })
            .or(page.getByLabel("Menunggu", { exact: true }))
            .first(),
        ).toBeVisible();
        await expect(
          page
            .getByText("Dilewati", { exact: true })
            .or(page.getByLabel("Dilewati", { exact: true }))
            .first(),
        ).toBeVisible();
        report.states.displayPatientStatuses = true;
        report.states.displayPairedAndCall = true;
      } else {
        await type("Email", role.toLowerCase() + "@fixture.local");
        await type("Kata sandi", "fixture-only");
        await button("Masuk").click();
        const heading =
          role === "ADMIN"
            ? page
                .getByText("Dashboard", { exact: true })
                .or(page.getByLabel("Dashboard", { exact: true }))
                .first()
            : page
                .getByLabel(/^Dashboard Dokter(?:\n|$)/)
                .or(page.getByText("Dashboard Dokter", { exact: true }))
                .first();
        await expect(heading).toBeVisible();
      }
      await expect(page.getByRole("progressbar")).toHaveCount(0);
      for (const size of [
        { width: 1280, height: 720 },
        { width: 1366, height: 768 },
        { width: 1920, height: 1080 },
      ]) {
        await page.setViewportSize(size);
        await page.mouse.move(0, 0);
        await page.waitForTimeout(600);
        const metrics = await page.evaluate(() => ({
          width: innerWidth,
          scrollWidth: document.scrollingElement.scrollWidth,
          height: innerHeight,
          scrollHeight: document.scrollingElement.scrollHeight,
        }));
        assert.equal(metrics.scrollWidth, size.width);
        if (role === "DISPLAY") assert.equal(metrics.scrollHeight, size.height);
        report.viewports.push({ role, ...size, ...metrics });
        await page.screenshot({
          path: path.join(output, role.toLowerCase() + `-${size.width}.png`),
        });
      }
      report.states[role.toLowerCase() + "Rendered"] = true;
      await context.close();
    }
    assert.deepEqual(report.errors, []);
    report.success = true;
    fs.writeFileSync(
      path.join(output, "report.json"),
      JSON.stringify(report, null, 2),
    );
    return report;
  } catch (error) {
    report.failure = error.stack || error.message;
    if (currentPage) {
      report.bodyText = await currentPage
        .locator("body")
        .innerText()
        .catch(() => "");
      report.labels = await currentPage
        .locator("[aria-label]")
        .evaluateAll((nodes) => nodes.map((n) => n.getAttribute("aria-label")))
        .catch(() => []);
      await currentPage
        .screenshot({ path: path.join(output, "failed.png") })
        .catch(() => {});
    }
    fs.writeFileSync(
      path.join(output, "failed.json"),
      JSON.stringify(report, null, 2),
    );
    throw error;
  } finally {
    if (browser) await browser.close();
    await new Promise((r) => io.close(r));
    if (server.listening) await new Promise((r) => server.close(r));
  }
};
