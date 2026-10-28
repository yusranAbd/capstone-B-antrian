/** Real Chrome + Flutter + Socket.IO transport, with synthetic HTTP/socket fixtures.
 * Never connects to a database or accepts real credentials. */
const fs = require("node:fs");
const path = require("node:path");
const http = require("node:http");
const { randomUUID, createHash } = require("node:crypto");
const assert = require("node:assert/strict");
const { chromium, expect: baseExpect } = require("@playwright/test");
const { Server } = require("socket.io");
const expect = baseExpect.configure({ timeout: 30000 });
module.exports = async ({
  build,
  output,
  engineRoot,
  fontFile,
  baseline = false,
  compact = false,
  cameraVideo,
}) => {
  fs.mkdirSync(output, { recursive: true });
  const report = {
    mode: "Synthetic API/Socket.IO fixtures; real Chrome release rendering, no database",
    buildSha256: createHash("sha256")
      .update(fs.readFileSync(path.join(build, "main.dart.js")))
      .digest("hex"),
    compact,
    states: {},
    viewports: [],
    errors: [],
  };
  const ids = Array.from({ length: 8 }, randomUUID),
    rooms = ids.slice(0, 2),
    clinics = ids.slice(2, 4);
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-GB", {
      timeZone: "Asia/Jakarta",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    })
      .formatToParts(new Date())
      .map((p) => [p.type, p.value]),
  );
  const today = `${parts.year}-${parts.month}-${parts.day}`;
  const room = (i) => ({
    id: rooms[i],
    kode: i ? "BU01" : "AN01",
    nama: i ? "Ruang Bedah 1" : "Ruang Anak 1",
    aktif: true,
    layanan: {
      id: clinics[i],
      nama: i ? "Bedah Umum" : "Anak",
      kode: i ? "BEDAH" : "ANAK",
      aktif: true,
    },
  });
  const patients = [
    ["Andi Pratama", "Budi Saputra", "Citra Lestari"].map((nama, i) => ({
      tiketId: randomUUID(),
      nomorAntrean: `AN-00${i + 1}`,
      namaPasien: nama,
      status: ["MENUNGGU", "DILEWATI", "CHECK_IN"][i],
      priority: i,
      checkInPada: `${today}T02:12:00Z`,
      loketId: rooms[0],
    })),
    [
      {
        tiketId: randomUUID(),
        nomorAntrean: "BD-001",
        namaPasien: "Pasien Bedah QA",
        status: "MENUNGGU",
        priority: 1,
        checkInPada: `${today}T02:15:00Z`,
        loketId: rooms[1],
      },
    ],
  ];
  const qrTicket = {
    tiketId: randomUUID(),
    nomorAntrean: "AN-004",
    namaPasien: "Pasien QR QA",
    status: "DIPESAN",
    priority: 4,
    checkInPada: `${today}T02:20:00Z`,
    loketId: rooms[0],
  };
  patients[0].push(qrTicket);
  const requests = [],
    joins = [0, 0];
  let page;
  let seq = 10,
    base,
    browser;
  function snapshot(i) {
    const waiting = patients[i]
      .filter((t) => t.status === "MENUNGGU")
      .sort((a, b) => a.priority - b.priority);
    const extra = patients[i].filter((t) =>
      ["DILEWATI", "CHECK_IN"].includes(t.status),
    );
    const list = [...waiting, ...extra].map((t) => ({
      ...t,
      bisaAntreUlang: t.status === "DILEWATI",
      bisaMasukAntrean: t.status === "CHECK_IN",
    }));
    return {
      versiSkema: 1,
      tanggalPelayanan: today,
      diperolehPada: new Date().toISOString(),
      menunggu: { total: waiting.length, tiket: waiting },
      daftarPasien: {
        total: list.length,
        ditampilkan: list.length,
        tiket: list,
      },
      loket: [
        {
          ...room(i),
          tiketAktif: patients[i].filter((t) =>
            ["DIPANGGIL", "DILAYANI"].includes(t.status),
          ),
        },
      ],
    };
  }
  const auth = {
    accessToken: "fixture-access-only",
    refreshToken: "fixture-refresh-only",
    user: {
      id: ids[7],
      peran: "PETUGAS",
      nama: "Petugas QA",
      email: "fixture@test.local",
    },
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
        const p = u.pathname.replace("/api/v1", "");
        let raw = "";
        for await (const chunk of req) raw += chunk;
        const body = raw ? JSON.parse(raw) : {};
        requests.push({
          method: req.method,
          path: p,
          room: u.searchParams.get("loketId") || body.loketId,
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
        if (p === "/penugasan-petugas")
          return send(
            rooms.map((id, i) => ({
              id,
              aktif: true,
              loketId: id,
              tanggalMulai: today,
              tanggalSelesai: null,
              loket: room(i),
            })),
          );
        if (p === "/jadwal-praktik")
          return send(
            rooms.flatMap((id, i) =>
              (compact ? [0, 1] : [0]).map((doctorIndex) => ({
                id: doctorIndex ? ids[i + 6] : id,
                loketId: id,
                loket: room(i),
                tanggal: today,
                aktif: true,
                mulaiPada: today + (doctorIndex ? "T06:00:00Z" : "T01:00:00Z"),
                selesaiPada:
                  today + (doctorIndex ? "T09:00:00Z" : "T04:00:00Z"),
                dokterLayanan: {
                  layanan: room(i).layanan,
                  dokter: {
                    id: ids[i + 4],
                    nama: doctorIndex
                      ? i
                        ? "dr. Ratih Candrakirana, Sp.B"
                        : "dr. Bagas Wicaksana, Sp.A"
                      : i
                        ? "dr. Dokter Bedah QA"
                        : "dr. Sindi Fixture",
                    spesialisasi: i ? "Bedah Umum" : "Anak",
                    fotoProfil: null,
                  },
                },
              })),
            ),
          );
        if (p === "/queue/snapshot") {
          const i = rooms.indexOf(u.searchParams.get("loketId"));
          return i < 0 ? send({}, 403) : send(snapshot(i));
        }
        if (
          req.method === "POST" &&
          (p.startsWith("/queue/") || p === "/check-in/auto-antrean")
        ) {
          const i = rooms.indexOf(body.loketId);
          if (i < 0) return send({}, 403);
          let ticket, action;
          if (p === "/check-in/auto-antrean") {
            assert.equal(body.qrPayload, "SQ1." + "A".repeat(43));
            ticket = qrTicket;
            action = "ENQUEUE";
            ticket.status = "MENUNGGU";
            ticket.priority = ++seq;
          } else if (p === "/queue/panggil") {
            ticket = patients[i]
              .filter((t) => t.status === "MENUNGGU")
              .sort((a, b) => a.priority - b.priority)[0];
            if (!ticket) return send({}, 404);
            ticket.status = "DIPANGGIL";
            action = "CALL";
          } else {
            const [, , id, op] = p.split("/");
            ticket = patients[i].find((t) => t.tiketId === id);
            if (!ticket) return send({}, 404);
            const rule = {
              "panggil-ulang": ["DIPANGGIL", "DIPANGGIL", "RECALL"],
              lewati: ["DIPANGGIL", "DILEWATI", "SKIP"],
              "antre-ulang": ["DILEWATI", "MENUNGGU", "REQUEUE"],
              masuk: ["CHECK_IN", "MENUNGGU", "ENQUEUE"],
              "mulai-pelayanan": ["DIPANGGIL", "DILAYANI", "START"],
              "selesaikan-pelayanan": ["DILAYANI", "SELESAI", "COMPLETE"],
            }[op];
            if (!rule || ticket.status !== rule[0]) return send({}, 409);
            ticket.status = rule[1];
            action = rule[2];
            if (["REQUEUE", "ENQUEUE"].includes(action))
              ticket.priority = ++seq;
          }
          ns.to(clinics[i]).emit("queue:updated", {
            versiSkema: 1,
            peristiwaId: randomUUID(),
            aksi: action,
            layananId: clinics[i],
            loketId: rooms[i],
            tiketId: ticket.tiketId,
            nomorAntrean: ticket.nomorAntrean,
            status: ticket.status,
          });
          return send({ ...ticket, namaPoliklinik: room(i).layanan.nama });
        }
        return send({}, 404);
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
  const io = new Server(server),
    ns = io.of("/queue");
  ns.use((socket, next) =>
    socket.handshake.auth.token === auth.accessToken
      ? next()
      : next(new Error("Unauthorized fixture")),
  );
  ns.on("connection", (socket) =>
    socket.on("queue:join", (data, ack) => {
      const i = clinics.indexOf(data.layananId);
      if (i < 0) return ack({ ok: false });
      socket.join(clinics[i]);
      joins[i]++;
      ack({ ok: true });
    }),
  );
  try {
    await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
    base = "http://127.0.0.1:" + server.address().port;
    browser = await chromium.launch({
      channel: "chrome",
      headless: true,
      args: cameraVideo
        ? [
            "--use-fake-device-for-media-stream",
            "--use-file-for-fake-video-capture=" + path.resolve(cameraVideo),
          ]
        : [],
    });
    report.chrome = browser.version();
    const context = await browser.newContext({
      viewport: { width: 1366, height: 768 },
      serviceWorkers: "block",
      permissions: cameraVideo ? ["camera"] : [],
    });
    await context.route("**/*", async (route) => {
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
      // mobile_scanner's pinned ZXing reader is required for the real camera
      // fixture on desktop browsers without native BarcodeDetector support.
      if (
        cameraVideo &&
        ["cdn.jsdelivr.net", "fastly.jsdelivr.net"].includes(u.hostname) &&
        u.pathname.startsWith("/npm/zxing-wasm@3.1.3/")
      ) {
        // Fetch the identical pinned asset through the CDN hostname reachable
        // from this QA host; the package's alternate Fastly host may time out.
        const response = await fetch("https://cdn.jsdelivr.net" + u.pathname, {
          signal: AbortSignal.timeout(15000),
        });
        assert.ok(response.ok, "Pinned camera decoder unavailable");
        return route.fulfill({
          body: Buffer.from(await response.arrayBuffer()),
          contentType: u.pathname.endsWith(".wasm")
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
          name:
            name === "Pindai QR" ? /Pindai QR/ : new RegExp("^" + name + "$"),
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
        if (
          await page.getByRole("button", { name: "Masuk", exact: true }).count()
        )
          return 1;
        if (await p.count()) await p.click({ timeout: 1000 }).catch(() => {});
        return page.getByRole("button", { name: "Masuk", exact: true }).count();
      })
      .toBe(1);
    await type("Email", "fixture@test.local");
    await type("Kata sandi", "fixture-only");
    await press("Masuk");
    await expect(text("Daftar antrean poli")).toBeVisible();
    if (baseline) {
      await expect(text("Panel petugas")).toBeVisible();
      report.mode =
        "Baseline Portal PETUGAS V3 Chrome capture only, synthetic data";
      for (const [width, height] of [
        [1366, 768],
        [390, 844],
      ]) {
        await page.setViewportSize({ width, height });
        await page.waitForTimeout(150);
        await page.screenshot({
          path: path.join(output, "staff-" + width + "x" + height + ".png"),
        });
      }
      report.success = true;
      fs.writeFileSync(
        path.join(output, "report.json"),
        JSON.stringify(report, null, 2),
      );
      return report;
    }
    await expect(text("dr. Sindi Fixture")).toBeVisible();
    await expect.poll(() => joins[0]).toBeGreaterThan(0);
    report.states.loginAndSchedule = true;
    for (const [width, height] of compact
      ? [
          [1280, 640],
          [1280, 720],
          [1366, 768],
          [1440, 900],
          [1920, 1080],
          [768, 1024],
          [320, 740],
          [375, 812],
          [414, 896],
        ]
      : [
          [1366, 768],
          [1440, 900],
          [1920, 1080],
          [768, 1024],
          [375, 812],
          [390, 844],
        ]) {
      await page.setViewportSize({ width, height });
      await page.waitForTimeout(150);
      const metrics = await page.evaluate(() => ({
        width: innerWidth,
        height: innerHeight,
        scrollWidth: document.scrollingElement.scrollWidth,
      }));
      assert.equal(metrics.width, metrics.scrollWidth);
      if (width >= 1000 && height >= 720) {
        for (const value of ["Panggil berikutnya", "Pindai QR"]) {
          const control = page.getByRole("button", {
            name: value,
            exact: value !== "Pindai QR",
          });
          await expect
            .poll(
              async () => {
                const b = await control.boundingBox();
                return b !== null && b.y + b.height <= height;
              },
              { message: value + " must fit viewport" },
            )
            .toBe(true);
        }
        for (const value of ["AN-001", "AN-002", "AN-003"]) {
          await expect
            .poll(
              async () => {
                const b = await text(value).boundingBox();
                return b !== null && b.y + b.height <= height;
              },
              { message: value + " must fit viewport" },
            )
            .toBe(true);
        }
      }
      report.viewports.push({
        ...metrics,
        desktopControlsFit: width >= 1000 && height >= 720 ? true : undefined,
      });
      await page.screenshot({
        path: path.join(output, `staff-${width}x${height}.png`),
      });
    }
    await page.setViewportSize({ width: 1366, height: 768 });
    await page.waitForTimeout(150);
    await type("Cari nomor", "Budi");
    await expect(text("AN-001")).toHaveCount(0);
    await expect(text("AN-002")).toBeVisible();
    await type("Cari nomor", "");
    report.states.patientSearch = true;
    await press("Panggil berikutnya");
    await expect(
      page.getByRole("button", { name: "Panggil Ulang", exact: true }),
    ).toBeVisible();
    await press("Panggil Ulang");
    await press("Lewati");
    await expect.poll(() => patients[0][0].status).toBe("DILEWATI");
    async function rowAction(number, name) {
      await page
        .getByRole("button", {
          name: new RegExp("Aksi " + number),
          includeHidden: true,
        })
        .click();
      await text(name).click();
    }
    await rowAction("AN-001", "Kembalikan ke Antrean");
    await expect.poll(() => patients[0][0].status).toBe("MENUNGGU");
    await expect(page.getByLabel(/\nAN-001\n/)).toHaveCount(1);
    report.states.skipRequeueNoDuplicate = true;
    await press("Panggil berikutnya");
    await press("Mulai Pelayanan");
    await press("Selesaikan Pelayanan");
    await expect(
      page.getByRole("button", { name: "Panggil berikutnya", exact: true }),
    ).toBeVisible();
    report.states.callRecallStartComplete = true;
    await rowAction("AN-003", "Masuk Antrean");
    await expect.poll(() => patients[0][2].status).toBe("MENUNGGU");
    report.states.legacyCheckInRow = true;
    await expect(page.getByRole("button", { name: /Pindai QR/ })).toBeEnabled();
    await expect(text("Input Manual")).toHaveCount(0);
    await press("Pindai QR");
    await expect(text("QR Check-in Otomatis")).toBeVisible();
    if (cameraVideo) {
      await expect
        .poll(() => qrTicket.status, { timeout: 60000 })
        .toBe("MENUNGGU");
      await expect(text("AN-004 · MENUNGGU")).toBeVisible();
      await page.waitForTimeout(1200); // Repeated video frames must stay deduplicated.
      assert.equal(
        requests.filter((r) => r.path === "/check-in/auto-antrean").length,
        1,
      );
      assert.equal(
        requests.filter(
          (r) => r.path === "/queue/" + qrTicket.tiketId + "/masuk",
        ).length,
        0,
      );
      report.states.oneScanCameraFixture = true;
    } else {
      await expect(
        text("Kamera tidak tersedia atau izin ditolak."),
      ).toBeVisible();
      report.states.cameraUnavailableGuidance = true;
    }
    await page.screenshot({ path: path.join(output, "scan-dialog.png") });
    await press("Tutup");
    report.states.nativeScanFabAndNoManualInput = true;
    async function changeRoom(from, to) {
      await text(from).click();
      await text(to).click();
    }
    await changeRoom("Ruang Anak 1 · Anak", "Ruang Bedah 1 · Bedah Umum");
    await expect(text("dr. Dokter Bedah QA")).toBeVisible();
    await expect(text("Pasien Bedah QA")).toBeVisible();
    await expect(text("Andi Pratama")).toHaveCount(0);
    await expect(text("AN-004 · MENUNGGU")).toHaveCount(0);
    report.states.roomIsolation = true;
    await changeRoom("Ruang Bedah 1 · Bedah Umum", "Ruang Anak 1 · Anak");
    await expect(text("dr. Sindi Fixture")).toBeVisible();
    const before = joins[0];
    for (const socket of ns.sockets.values())
      if (socket.rooms.has(clinics[0])) socket.conn.close();
    await expect.poll(() => joins[0]).toBeGreaterThan(before);
    const snapshots = requests.filter(
      (r) => r.path === "/queue/snapshot" && r.room === rooms[0],
    ).length;
    await fetch(
      base + "/api/v1/queue/" + patients[0][1].tiketId + "/antre-ulang",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: "Bearer " + auth.accessToken,
        },
        body: JSON.stringify({ loketId: rooms[0] }),
      },
    );
    await expect
      .poll(
        () =>
          requests.filter(
            (r) => r.path === "/queue/snapshot" && r.room === rooms[0],
          ).length,
      )
      .toBeGreaterThan(snapshots);
    await expect(text("Dilewati")).toHaveCount(0);
    report.states.reconnectAndRealtimeSnapshot = true;
    if (compact) {
      await page.getByLabel("Profil petugas", { exact: true }).click();
      await expect(text("Profil Saya")).toBeVisible();
      await press("Keluar Akun");
      await expect(
        page.getByRole("button", { name: "Masuk", exact: true }),
      ).toBeVisible();
      report.states.directProfileAndAccountLogout = true;
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
    report.joins = joins;
    report.today = today;
    if (page) {
      if (cameraVideo)
        report.cameraDiagnostics = await page
          .evaluate(async () => {
            const v = document.querySelector("video");
            const info = {
              nativeDetector: typeof BarcodeDetector,
              wasmReader: typeof window.ZXingWASM,
              video: v
                ? {
                    width: v.videoWidth,
                    height: v.videoHeight,
                    paused: v.paused,
                    ready: v.readyState,
                  }
                : null,
            };
            if (v && window.ZXingWASM) {
              const c = document.createElement("canvas");
              c.width = v.videoWidth;
              c.height = v.videoHeight;
              const ctx = c.getContext("2d");
              ctx.drawImage(v, 0, 0);
              try {
                const r = await Promise.race([
                  window.ZXingWASM.readBarcodes(
                    ctx.getImageData(0, 0, c.width, c.height),
                    { formats: ["QRCode"], tryHarder: true },
                  ),
                  new Promise((_, reject) =>
                    setTimeout(() => reject(new Error("decode timeout")), 5000),
                  ),
                ]);
                info.decode = r.map((x) => ({
                  format: x.format,
                  valid: x.isValid,
                  expected: x.text === "SQ1." + "A".repeat(43),
                }));
              } catch (e) {
                info.decodeError = e.message;
              }
            }
            return info;
          })
          .catch((e) => ({ error: e.message }));
      report.text = await page
        .locator("body")
        .innerText()
        .catch(() => "closed");
      report.labels = await page
        .locator("[aria-label]")
        .evaluateAll((nodes) => nodes.map((n) => n.getAttribute("aria-label")))
        .catch(() => []);
      await page
        .screenshot({ path: path.join(output, "failed.png") })
        .catch(() => {});
    }
    report.success = false;
    report.error = e.message;
    fs.writeFileSync(
      path.join(output, "report.json"),
      JSON.stringify(report, null, 2),
    );
    throw e;
  } finally {
    if (browser) await browser.close();
    await new Promise((resolve) => io.close(resolve));
    if (server.listening) await new Promise((resolve) => server.close(resolve));
  }
};
