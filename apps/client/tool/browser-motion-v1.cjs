/** Real guarded test fixtures only. No REST/socket stubs or speech changes. */
const { chromium, expect: baseExpect } = require("@playwright/test");
const expect = baseExpect.configure({ timeout: 30000 });
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { enter, button } = require("./browser-demo.cjs").helpers;
const { sampleFrames } = require("./motion-profile.cjs");
const base = "http://127.0.0.1:8080/";
const api = "http://127.0.0.1:3001/api/v1";

module.exports = async ({ fixture: f }) => {
  const buildRoot = path.resolve(__dirname, "../build");
  const output = process.env.QUEUEB_MOTION_EVIDENCE_DIR
    ? path.resolve(process.env.QUEUEB_MOTION_EVIDENCE_DIR)
    : path.join(buildRoot, "motion-v1/browser");
  assert(
    output.startsWith(buildRoot + path.sep),
    "Evidence must stay in build",
  );
  fs.mkdirSync(output, { recursive: true });
  const cases = [];
  const profiles = [];
  let browser;
  let phase = "patient-pilot";
  const engineRoot = path.resolve(__dirname, "../build/web/canvaskit");
  const bootstrap = fs.readFileSync(
    path.resolve(__dirname, "../build/web/flutter_bootstrap.js"),
    "utf8",
  );
  const engineVersion = bootstrap.match(
    /engineRevision[^a-f0-9]+([a-f0-9]{40})/,
  )?.[1];
  assert(engineVersion, "Compiled engine revision required");
  const engineAssets = new Set();
  async function prepareContext(context) {
    // Serve the identical SDK engine files already emitted by this Web build.
    // REST, Socket.IO, fonts and application scripts remain untouched.
    await context.route(
      "https://www.gstatic.com/flutter-canvaskit/**",
      async (route) => {
        const parts = new URL(route.request().url()).pathname.split("/");
        assert.equal(
          parts[2],
          engineVersion,
          "Engine revision must match this build",
        );
        const suffix = parts.slice(3).join("/");
        const file = path.resolve(engineRoot, suffix);
        assert(
          file.startsWith(engineRoot + path.sep) && fs.existsSync(file),
          "Bundled engine asset required",
        );
        engineAssets.add(suffix);
        await route.fulfill({
          path: file,
          contentType: file.endsWith(".wasm")
            ? "application/wasm"
            : "text/javascript",
          headers: { "Access-Control-Allow-Origin": "*" },
        });
      },
    );
  }
  async function request(
    route,
    token,
    body,
    method = body === undefined ? "GET" : "POST",
  ) {
    const response = await fetch(api + route, {
      method,
      headers: {
        "Content-Type": "application/json",
        ...(token ? { Authorization: "Bearer " + token } : {}),
      },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    assert(response.ok, "Fixture HTTP " + response.status);
    return response.json();
  }
  async function login(account) {
    return (
      await request("/auth/login", null, {
        email: f[account].email,
        kataSandi: f[account].password,
      })
    ).accessToken;
  }
  async function open(role, reduced) {
    const context = await browser.newContext({
      viewport: { width: 1440, height: 900 },
      reducedMotion: reduced ? "reduce" : "no-preference",
    });
    await prepareContext(context);
    const page = await context.newPage();
    const trace = {
      requests: [],
      errors: 0,
      http5xx: 0,
      sockets: 0,
      closedSockets: 0,
    };
    page.on("request", (r) => {
      const u = new URL(r.url());
      if (u.pathname.startsWith("/api/v1/"))
        trace.requests.push({ method: r.method(), path: u.pathname });
    });
    page.on("pageerror", () => trace.errors++);
    page.on("response", (r) => {
      if (r.status() >= 500) trace.http5xx++;
    });
    page.on("websocket", (socket) => {
      const u = new URL(socket.url());
      if (u.host === "127.0.0.1:3001" && u.pathname === "/socket.io/") {
        trace.sockets++;
        socket.on("close", () => trace.closedSockets++);
      }
    });
    try {
      await page.goto(base);
      await page
        .locator("flt-glass-pane")
        .waitFor({ state: "attached", timeout: 90000 });
      assert.equal(
        await page.evaluate(
          () => matchMedia("(prefers-reduced-motion: reduce)").matches,
        ),
        reduced,
      );
      await enter(page, "Email", f[role].email);
      await enter(page, "Kata sandi", f[role].password);
      await button(page, "Masuk");
      await expect(page).toHaveURL(
        new RegExp(
          "#/" +
            { petugas: "staff", admin: "admin", doctor: "doctor" }[role] +
            "$",
        ),
      );
      return { page, context, trace };
    } catch (error) {
      await page
        .screenshot({
          path: path.join(
            output,
            "startup-" + role + "-" + (reduced ? "reduced" : "normal") + ".png",
          ),
          mask: [page.locator("input,textarea")],
        })
        .catch(() => {});
      fs.writeFileSync(
        path.join(output, "startup-" + role + ".json"),
        JSON.stringify(
          {
            errorType: error.name,
            engineAttached: await page.locator("flt-glass-pane").count(),
            runtimeErrors: trace.errors,
            http5xx: trace.http5xx,
          },
          null,
          2,
        ),
      );
      await context.close();
      throw error;
    }
  }
  async function mutation(page, method, route, action, queue = false) {
    if (queue)
      await expect(
        page.getByRole("button", { name: /Pindai QR/ }),
      ).toBeEnabled();
    const result = page.waitForResponse(
      (r) =>
        r.request().method() === method &&
        new URL(r.url()).pathname === "/api/v1" + route,
    );
    result.catch(() => {});
    await action();
    const response = await result;
    assert(response.ok(), "UI HTTP " + response.status());
    if (queue)
      await expect(
        page.getByRole("button", { name: /Pindai QR/ }),
      ).toBeEnabled();
    return response.json();
  }
  async function screenshot(page, name) {
    // A finite presentation window, not a sleep for API readiness.
    await page.evaluate(
      () =>
        new Promise((resolve) => {
          const end = performance.now() + 220;
          const frame = (t) =>
            t >= end ? resolve() : requestAnimationFrame(frame);
          requestAnimationFrame(frame);
        }),
    );
    await page.screenshot({ path: path.join(output, name + ".png") });
  }
  async function logout(page, from) {
    await button(page, "Keluar Akun");
    await expect
      .poll(() => {
        const location = new URL(page.url().split("#")[1], base);
        return [location.pathname, location.searchParams.get("from")];
      })
      .toEqual(["/login", from]);
  }
  async function adminAction(page, name, action) {
    // Match the named fixture row; DataTable may expose its action as a cell.
    const label = new RegExp(
      "^Aksi " + name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"),
    );
    const control = page
      .getByRole("cell")
      .filter({ hasText: label })
      .or(page.getByRole("button", { name: label }))
      .or(page.getByLabel(label))
      .first();
    const viewport = page.viewportSize();
    const tableLocator = page.getByRole("table").first();
    const table = (await tableLocator.count())
      ? await tableLocator.boundingBox()
      : null;
    await page.mouse.move(
      viewport.width * 0.7,
      table
        ? Math.min(viewport.height - 50, table.y + 100)
        : viewport.height * 0.45,
    );
    for (let i = 0; i < 4; i++) {
      const box = (await control.count()) ? await control.boundingBox() : null;
      if (box && box.x >= 0 && box.x + box.width <= viewport.width) break;
      await page.mouse.wheel(1200, 0);
      await page.evaluate(
        () => new Promise((resolve) => requestAnimationFrame(() => resolve())),
      );
    }
    await expect(control).toBeVisible();
    await control.click();
    await page.getByRole("menuitem", { name: action, exact: true }).click();
  }
  try {
    await require("./browser-patient-motion.cjs")({
      fixture: f,
      output: path.join(output, "patient"),
      prepareContext,
    });
    cases.push({ portal: "PASIEN", status: "PASS", modes: 2 });
    browser = await chromium.launch({
      channel: process.env.FLUTTER_BROWSER_CHANNEL || "chrome",
      headless: true,
    });
    phase = "fixture-auth";
    const staffToken = await login("petugas");
    for (const reduced of [false, true]) {
      phase = "staff-setup";
      const token = await login(reduced ? "patient2" : "patient1");
      const tickets = await request("/tiket/saya", token);
      const ticket = tickets.find(
        (t) =>
          (t.layananId || t.layanan?.id) === f.serviceId &&
          t.status === "DIPESAN",
      );
      assert(ticket, "Unique patient fixture booking must exist");
      const qr = await request("/tiket/" + ticket.id + "/qr", token, {});
      await request("/check-in/auto-antrean", staffToken, {
        qrPayload: qr.qrPayload,
        loketId: f.roomId,
      });
      const { page, context, trace } = await open("petugas", reduced);
      try {
        phase = "staff-six-commands";
        await sampleFrames(
          page,
          reduced ? "staff-idle-reduced" : "staff-idle-normal",
          async () => {},
          profiles,
        );
        const command = (route, action) =>
          route === "/queue/panggil"
            ? sampleFrames(
                page,
                reduced ? "staff-call-reduced" : "staff-call-normal",
                () => mutation(page, "POST", route, action, true),
                profiles,
              )
            : mutation(page, "POST", route, action, true);
        assert.equal(
          (
            await command("/queue/panggil", () =>
              button(page, "Panggil berikutnya"),
            )
          ).status,
          "DIPANGGIL",
        );
        await command("/queue/" + ticket.id + "/panggil-ulang", () =>
          button(page, "Panggil Ulang"),
        );
        await expect(
          page.getByRole("textbox", { disabled: true }),
        ).toBeVisible();
        await screenshot(page, "staff-" + (reduced ? "reduced" : "normal"));
        await command("/queue/" + ticket.id + "/lewati", () =>
          button(page, "Lewati"),
        );
        await command("/queue/" + ticket.id + "/antre-ulang", async () => {
          await button(page, "Aksi " + ticket.nomorAntrean);
          await page
            .getByRole("menuitem", {
              name: "Kembalikan ke Antrean",
              exact: true,
            })
            .click();
        });
        await command("/queue/panggil", () =>
          button(page, "Panggil berikutnya"),
        );
        await command("/queue/" + ticket.id + "/mulai-pelayanan", () =>
          button(page, "Mulai Pelayanan"),
        );
        assert.equal(
          (
            await command("/queue/" + ticket.id + "/selesaikan-pelayanan", () =>
              button(page, "Selesaikan Pelayanan"),
            )
          ).status,
          "SELESAI",
        );
        phase = "staff-profile";
        await button(page, /Petugas pelayanan/);
        await expect(page).toHaveURL(/#\/staff\/profile$/);
        await page.goBack();
        await expect(page).toHaveURL(/#\/staff$/);
        await button(page, /Petugas pelayanan/);
        await logout(page, "/staff/profile");
        await expect.poll(() => trace.closedSockets).toBe(1);
        assert.equal(
          trace.requests.filter(
            (r) => r.method === "POST" && r.path.startsWith("/api/v1/queue/"),
          ).length,
          7,
        );
        assert.equal(trace.sockets, 1);
        assert.equal(trace.errors, 0);
        assert.equal(trace.http5xx, 0);
        cases.push({
          portal: "PETUGAS",
          reducedMotion: reduced,
          status: "PASS",
          commands: 6,
          queuePosts: 7,
          sockets: 1,
          socketsClosed: 1,
          errors: 0,
          http5xx: 0,
        });
      } finally {
        await context.close();
      }
    }
    for (const reduced of [false, true]) {
      phase = "admin-navigation";
      const { page, context, trace } = await open("admin", reduced);
      try {
        const modules = [
          ["Dashboard", ""],
          ["Poliklinik", "/polyclinics"],
          ["Dokter", "/doctors"],
          ["Ruang & loket", "/rooms"],
          ["Jam & kapasitas poli", "/service-hours"],
          ["Jadwal praktik", "/practice-schedules"],
          ["Slot konsultasi", "/consultation-slots"],
          ["Penugasan petugas", "/staff-assignments"],
          ["Manajemen Display", "/displays"],
        ];
        for (const [label, destination] of modules) {
          await button(page, label);
          await expect(page).toHaveURL(
            new RegExp("#/admin" + destination + "$"),
          );
        }
        await page.goBack();
        await expect(page).toHaveURL(/#\/admin\/staff-assignments$/);
        await page.goForward();
        await expect(page).toHaveURL(/#\/admin\/displays$/);
        await button(page, "Poliklinik");
        const code = ("MV" + f.unique + (reduced ? "R" : "N")).slice(0, 20);
        f.extraServiceCodes.push(code); // Register cleanup before any UI write.
        const name = "Motion " + (reduced ? "Reduced" : "Normal") + " Clinic";
        phase = "admin-create";
        await button(page, "Tambah");
        for (const [label, value] of [
          ["Kode", code],
          ["Nama", name],
          ["Prefix antrean", reduced ? "MR" : "MN"],
        ])
          await enter(page, label, value);
        const created = await mutation(page, "POST", "/layanan", () =>
          button(page, "Simpan"),
        );
        assert.equal(created.nama, name);
        await expect(
          page
            .getByLabel("Data disimpan.", { exact: true })
            .or(page.getByText("Data disimpan.", { exact: true }))
            .first(),
        ).toBeVisible();
        phase = "admin-update";
        await adminAction(page, name, "Ubah");
        await enter(page, "Nama", name + " Updated");
        await mutation(page, "PATCH", "/layanan/" + created.id, () =>
          button(page, "Simpan"),
        );
        await expect(
          page
            .getByLabel("Data disimpan.", { exact: true })
            .or(page.getByText("Data disimpan.", { exact: true }))
            .first(),
        ).toBeVisible();
        await screenshot(page, "admin-" + (reduced ? "reduced" : "normal"));
        phase = "admin-deactivate";
        await adminAction(page, name + " Updated", "Nonaktifkan");
        await mutation(page, "DELETE", "/layanan/" + created.id, () =>
          button(page, "Lanjutkan"),
        );
        await expect(
          page
            .getByLabel("Data dinonaktifkan.", { exact: true })
            .or(page.getByText("Data dinonaktifkan.", { exact: true }))
            .first(),
        ).toBeVisible();
        phase = "admin-delete";
        await adminAction(page, name + " Updated", "Hapus");
        await enter(page, "Konfirmasi kode/nama", code);
        await mutation(
          page,
          "DELETE",
          "/layanan/" + created.id + "/permanen",
          () => button(page, "Hapus Permanen"),
        );
        await expect(
          page
            .getByLabel("Data berhasil dihapus permanen.", { exact: true })
            .or(
              page.getByText("Data berhasil dihapus permanen.", {
                exact: true,
              }),
            )
            .first(),
        ).toBeVisible();
        await button(page, "Profil Saya");
        await expect(page).toHaveURL(/#\/admin\/profile$/);
        await logout(page, "/admin/profile");
        assert.equal(
          trace.requests.filter(
            (r) =>
              ["POST", "PATCH", "DELETE"].includes(r.method) &&
              r.path.startsWith("/api/v1/layanan"),
          ).length,
          4,
        );
        assert.equal(trace.sockets, 0);
        assert.equal(trace.errors, 0);
        assert.equal(trace.http5xx, 0);
        cases.push({
          portal: "ADMIN",
          reducedMotion: reduced,
          status: "PASS",
          modules: 9,
          crudWrites: 4,
          sockets: 0,
          errors: 0,
          http5xx: 0,
        });
      } catch (error) {
        await page
          .screenshot({
            path: path.join(output, "admin-failure.png"),
            mask: [page.locator("input,textarea")],
          })
          .catch(() => {});
        fs.writeFileSync(
          path.join(output, "admin-semantics.txt"),
          require("./recovery-observer.cjs").scrub(
            await page.locator("body").ariaSnapshot(),
          ),
        );
        throw error;
      } finally {
        await context.close();
      }
    }
    phase = "doctor-monitoring";
    const { page, context, trace } = await open("doctor", false);
    try {
      await expect(
        page.locator('[aria-label*="Dashboard Dokter"]').first(),
      ).toBeVisible();
      await expect(
        page.getByRole("button", { name: /Tanggal:/ }),
      ).toBeEnabled();
      await screenshot(page, "doctor-unchanged");
      await page.goto(base + "#/doctor/profile");
      await expect(page).toHaveURL(/#\/doctor\/profile$/);
      await page.goBack();
      await expect(page).toHaveURL(/#\/doctor$/);
      assert(trace.requests.some((r) => r.path.includes("/portal-dokter")));
      assert(
        trace.requests
          .filter((r) => r.path.includes("/portal-dokter"))
          .every((r) => r.method === "GET"),
      );
      await page.goto(base + "#/doctor/profile");
      await logout(page, "/doctor/profile");
      assert.equal(trace.sockets, 1);
      assert.equal(trace.errors, 0);
      assert.equal(trace.http5xx, 0);
      await expect.poll(() => trace.closedSockets).toBe(1);
      cases.push({
        portal: "DOKTER",
        status: "PASS",
        newMotion: false,
        monitoringMutations: 0,
        sockets: 1,
        errors: 0,
        http5xx: 0,
      });
    } finally {
      await context.close();
    }
    fs.writeFileSync(
      path.join(output, "summary.json"),
      JSON.stringify(
        {
          status: "PASS",
          cases,
          display:
            process.env.QUEUEB_MOTION_PROFILE === "1"
              ? "separate compiled final-E2E Display coverage"
              : "unchanged; covered by Flutter regression",
        },
        null,
        2,
      ) + "\n",
    );
    console.log(
      "Motion V1 browser PASS: patient2 +staff2 +admin2 +doctor1; real guarded test backend",
    );
  } catch (error) {
    fs.writeFileSync(
      path.join(output, "summary.json"),
      JSON.stringify(
        { status: "FAIL", phase, errorType: error.name, cases },
        null,
        2,
      ) + "\n",
    );
    console.error("Motion V1 browser failed phase: " + phase);
    throw error;
  } finally {
    if (profiles.length)
      fs.writeFileSync(
        path.join(output, "motion-frame-profile.json"),
        JSON.stringify(profiles, null, 2),
      );
    await browser?.close();
  }
};
