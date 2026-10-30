/** Real compiled UI + guarded Nest/PostgreSQL test fixtures; no REST/socket stubs. */
const { chromium, expect: baseExpect } = require("@playwright/test");
const expect = baseExpect.configure({ timeout: 30000 });
const assert = require("node:assert/strict"),
  fs = require("node:fs"),
  path = require("node:path");
const { enter, button } = require("./browser-demo.cjs").helpers;
module.exports = async ({ fixture: f }) => {
  const out = path.resolve(
    __dirname,
    "../build/home-v7/browser-" + (f.homeV7Before ? "before" : "after"),
  );
  fs.mkdirSync(out, { recursive: true });
  const root = path.resolve(__dirname, "../build/web/canvaskit");
  const revision = fs
    .readFileSync(path.resolve(root, "../flutter_bootstrap.js"), "utf8")
    .match(/engineRevision[^a-f0-9]+([a-f0-9]{40})/)[1];
  const base = "http://127.0.0.1:8080/",
    api = "http://127.0.0.1:3001/api/v1";
  let browser,
    phase = "fixtures";
  const cases = [];
  async function request(route, token, body) {
    const r = await fetch(api + route, {
      method: body ? "POST" : "GET",
      headers: {
        "Content-Type": "application/json",
        ...(token ? { Authorization: "Bearer " + token } : {}),
      },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
    assert(r.ok, "Fixture HTTP " + r.status);
    return r.json();
  }
  try {
    const admin = (
      await request("/auth/login", null, {
        email: f.admin.email,
        kataSandi: f.admin.password,
      })
    ).accessToken;
    const codes = [
      "PENDAFTARAN",
      "REGISTRASI",
      "ADMINISTRASI",
      "APOTEK",
      "APOTIK",
    ];
    const existing = await request("/layanan", admin);
    assert(
      !existing.some((row) => codes.includes(row.kode)),
      "Reserved QA service codes already exist; do not modify existing records",
    );
    for (const [i, code] of codes.entries()) {
      f.extraServiceCodes.push(code);
      await request("/layanan", admin, {
        kode: code,
        nama:
          code === "PENDAFTARAN"
            ? "Pendaftaran"
            : code === "APOTEK"
              ? "Apotek"
              : code[0] + code.slice(1).toLowerCase(),
        prefixAntrean: "HV" + String.fromCharCode(65 + i),
        durasiDasarMenit: 15,
        modeReservasi: "ANTREAN_HARIAN",
        deskripsi: code.startsWith("APOT")
          ? "Layanan Farmasi"
          : "Layanan Administrasi",
      });
    }
    browser = await chromium.launch({ channel: "chrome", headless: true });
    for (const reduced of f.homeV7Before ? [false] : [false, true]) {
      const context = await browser.newContext({
        viewport: { width: 390, height: 844 },
        reducedMotion: reduced ? "reduce" : "no-preference",
      });
      await context.route(
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
      const page = await context.newPage();
      let errors = 0,
        consoleErrors = 0,
        http5xx = 0,
        sockets = 0,
        closed = 0;
      const writes = [];
      page.on("pageerror", () => errors++);
      page.on("console", (message) => {
        if (message.type() === "error") consoleErrors++;
      });
      page.on("response", (r) => {
        if (r.status() >= 500) http5xx++;
      });
      page.on("request", (r) => {
        const p = new URL(r.url()).pathname;
        if (
          r.method() === "POST" &&
          (p === "/api/v1/reservasi" || p.endsWith("/qr"))
        )
          writes.push(p);
      });
      page.on("websocket", (ws) => {
        const u = new URL(ws.url());
        if (u.host === "127.0.0.1:3001" && u.pathname === "/socket.io/") {
          sockets++;
          ws.on("close", () => closed++);
        }
      });
      try {
        phase = "login";
        await page.goto(base);
        await page
          .locator("flt-glass-pane")
          .waitFor({ state: "attached", timeout: 90000 });
        await enter(page, "Email", f.patient1.email);
        await enter(page, "Kata sandi", f.patient1.password);
        await button(page, "Masuk");
        await expect(page).toHaveURL(/#\/patient$/);
        await expect.poll(() => sockets).toBe(1);
        const registration = page
          .getByRole("button", { name: /Pendaftaran/ })
          .first();
        await expect(registration).toBeVisible();
        await page.screenshot({
          path: path.join(
            out,
            reduced ? "home-reduced.png" : "home-normal.png",
          ),
        });
        if (f.homeV7Before) {
          cases.push({ status: "CAPTURED", mode: "baseline", errors, http5xx });
          continue;
        }
        phase = "initial-chrome";
        const greeting = page.getByRole("group", { name: /^Selamat datang,/ });
        const tickets = page.getByRole("tab", {
          name: "Tiket Saya",
          exact: true,
        });
        await expect(greeting).toBeVisible();
        await expect(tickets).toBeVisible();
        phase = "programmatic-scroll";
        // Inspect the actual semantics scroll container rather than guessing an ID.
        const scrollHandle = await page.evaluateHandle(
          () =>
            [...document.querySelectorAll("flt-semantics")]
              .filter((element) => {
                const r = element.getBoundingClientRect();
                const overflow = element.querySelector(
                  ":scope > flt-semantics-scroll-overflow",
                );
                return (
                  overflow &&
                  overflow.clientHeight > element.clientHeight + 100 &&
                  element.clientHeight > 150 &&
                  element.scrollHeight > element.clientHeight + 100 &&
                  r.right > 0 &&
                  r.left < innerWidth &&
                  r.bottom > 0 &&
                  r.top < innerHeight
                );
              })
              .sort((a, b) => a.clientHeight - b.clientHeight)[0],
        );
        const scrollElement = scrollHandle.asElement();
        assert(
          scrollElement,
          "Actual Web semantics scroll container is required",
        );
        const jumped = await scrollElement.evaluate((element) => {
          const before = element.scrollTop;
          element.scrollTop = before + 60;
          return element.scrollTop > before;
        });
        assert(jumped, "Programmatic scroll must actually move content");
        await page.waitForTimeout(550);
        await expect(greeting).toBeVisible();
        await expect(tickets).toBeVisible();
        await scrollElement.evaluate((element) => {
          element.scrollTop = 0;
        });
        await scrollHandle.dispose();
        phase = "small-scroll";
        await page.mouse.move(180, 570);
        await page.mouse.wheel(0, 2);
        await page.waitForTimeout(300);
        await expect(greeting).toBeVisible();
        await expect(tickets).toBeVisible();
        phase = "scroll";
        await page.mouse.wheel(0, 420);
        await expect(greeting).not.toBeVisible();
        await expect(tickets).not.toBeVisible();
        await page.screenshot({
          path: path.join(
            out,
            reduced ? "hidden-reduced.png" : "hidden-normal.png",
          ),
        });
        await page.mouse.wheel(0, -280);
        await expect(greeting).toBeVisible();
        await expect(tickets).toBeVisible();
        await page.mouse.wheel(0, -1800);
        await expect(registration).toBeVisible();
        phase = "card";
        await registration.click();
        await expect(page).toHaveURL(/#\/patient\/reservations\/new/);
        assert.equal(writes.length, 0);
        await page.goBack();
        await expect(page).toHaveURL(/#\/patient$/);
        await expect(greeting).toBeVisible();
        phase = "avatar";
        await button(page, "Profil pasien");
        await expect(page).toHaveURL(/#\/patient\/profile$/);
        await page.goBack();
        await expect(page).toHaveURL(/#\/patient$/);
        phase = "tabs";
        for (const [label, url] of [
          ["Tiket Saya", "/tickets"],
          ["Reservasi", "/reservations"],
          ["Beranda", ""],
        ]) {
          await page.getByRole("tab", { name: label, exact: true }).click();
          await expect(page).toHaveURL(new RegExp("#/patient" + url + "$"));
        }
        phase = "notification";
        await button(page, "Notifikasi");
        await expect(
          page
            .getByText("Notifikasi belum tersedia.", { exact: false })
            .or(page.getByLabel(/Notifikasi belum tersedia/))
            .first(),
        ).toBeVisible();
        await button(page, "Tutup");
        await button(page, "Profil pasien");
        await button(page, "Keluar Akun");
        await expect
          .poll(() => new URL(page.url().split("#")[1], base).pathname)
          .toBe("/login");
        await expect.poll(() => closed).toBe(1);
        assert.equal(writes.length, 0);
        assert.equal(sockets, 1);
        assert.equal(errors, 0);
        assert.equal(consoleErrors, 0);
        assert.equal(http5xx, 0);
        cases.push({
          status: "PASS",
          reducedMotion: reduced,
          realScrollDownUp: true,
          programmaticScrollIgnored: true,
          smallScrollIgnored: true,
          cardInitialPosts: 0,
          bookingOrQrPosts: 0,
          sockets,
          closedSockets: closed,
          errors,
          consoleErrors,
          http5xx,
        });
      } catch (error) {
        fs.writeFileSync(
          path.join(out, "failure-a11y.txt"),
          await page
            .locator("body")
            .ariaSnapshot()
            .catch(() => "Snapshot unavailable"),
        );
        await page
          .screenshot({
            path: path.join(out, "failure.png"),
            mask: [page.locator("input,textarea")],
          })
          .catch(() => {});
        throw error;
      } finally {
        await context.close();
      }
    }
    fs.writeFileSync(
      path.join(out, "summary.json"),
      JSON.stringify(
        { status: f.homeV7Before ? "BASELINE_CAPTURED" : "PASS", cases },
        null,
        2,
      ) + "\n",
    );
    console.log(
      "Home V7 browser: " +
        (f.homeV7Before
          ? "BASELINE CAPTURED"
          : "PASS normal/reduced scroll +card +profile +tabs +logout"),
    );
  } catch (error) {
    fs.writeFileSync(
      path.join(out, "summary.json"),
      JSON.stringify(
        { status: "FAIL", phase, errorType: error.name, cases },
        null,
        2,
      ) + "\n",
    );
    console.error("Home V7 browser phase: " + phase);
    throw error;
  } finally {
    await browser?.close();
  }
};
