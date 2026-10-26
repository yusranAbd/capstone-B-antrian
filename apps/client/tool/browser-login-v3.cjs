/** Chrome visual/interaction QA. API responses are test doubles; no database writes. */
const { chromium, expect } = require("@playwright/test");
const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");

module.exports = async ({ webUrl, output, engineRoot, fontFile }) => {
  const origin = new URL(webUrl);
  assert.ok(["localhost", "127.0.0.1"].includes(origin.hostname));
  fs.mkdirSync(output, { recursive: true });
  const browser = await chromium.launch({ channel: "chrome", headless: true });
  const report = {
    browser: browser.version(),
    api: "controlled HTTP fixtures; not live account login",
    viewports: [],
    states: {},
    errors: [],
  };
  let page, releaseLogin;
  const loginGate = new Promise((resolve) => {
    releaseLogin = resolve;
  });
  let loginCalls = 0,
    registerCalls = 0;
  try {
    const context = await browser.newContext({
      viewport: { width: 1366, height: 768 },
      serviceWorkers: "block",
    });
    await context.route("**/*", async (route) => {
      const request = route.request(),
        u = new URL(request.url());
      if (u.pathname.startsWith("/api/v1/")) {
        const headers = {
          "Access-Control-Allow-Origin": origin.origin,
          "Access-Control-Allow-Credentials": "true",
          "Access-Control-Allow-Headers":
            "content-type,authorization,x-display-device-id",
          "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
        };
        if (request.method() === "OPTIONS")
          return route.fulfill({ status: 204, headers });
        if (u.pathname.endsWith("/auth/login")) {
          loginCalls++;
          const body = request.postDataJSON();
          assert.equal(body.email, "fixture@test.local");
          assert.equal(body.kataSandi, "fixture-only");
          await loginGate;
          return route.fulfill({
            status: 401,
            headers,
            contentType: "application/json",
            body: JSON.stringify({ message: "Email atau kata sandi salah." }),
          });
        }
        if (u.pathname.endsWith("/auth/register")) {
          registerCalls++;
          assert.equal(request.postDataJSON().nama, "Pasien Fixture");
          assert.equal(request.postDataJSON().peran, undefined);
          return route.fulfill({
            status: 201,
            headers,
            contentType: "application/json",
            body: "{}",
          });
        }
        return route.fulfill({
          status: 401,
          headers,
          contentType: "application/json",
          body: "{}",
        });
      }
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
      return u.origin === origin.origin ? route.continue() : route.abort();
    });
    page = await context.newPage();
    page.on("pageerror", (e) => report.errors.push(e.message));
    page.on("console", (m) => {
      if (m.type() === "error" && !/401/.test(m.text()))
        report.errors.push(m.text());
    });
    await page.goto(webUrl, { waitUntil: "domcontentloaded" });
    await page
      .locator("flt-glass-pane")
      .waitFor({ state: "attached", timeout: 60000 });
    await expect
      .poll(
        async () => {
          const placeholder = page.locator("flt-semantics-placeholder");
          if (await placeholder.count())
            await placeholder.evaluate((el) => el.click());
          return page
            .getByRole("button", {
              includeHidden: true,
              name: "Masuk",
              exact: true,
            })
            .count();
        },
        { timeout: 30000 },
      )
      .toBe(1);
    for (const [width, height] of [
      [1366, 768],
      [1440, 900],
      [1920, 1080],
      [768, 1024],
      [360, 800],
      [390, 844],
    ]) {
      await page.setViewportSize({ width, height });
      await page.waitForTimeout(150);
      const actions = [
        "Masuk",
        "Masuk ke Public Display",
        "Pasien baru? Daftar",
      ];
      for (const name of actions) {
        const button = page.getByRole("button", {
          includeHidden: true,
          name,
          exact: true,
        });
        await expect(button).toBeVisible();
        const box = await button.boundingBox();
        assert.ok(
          box.y >= 0 &&
            box.y + box.height <= height &&
            box.x >= 0 &&
            box.x + box.width <= width,
          name + " outside viewport",
        );
      }
      const dimensions = await page.evaluate(() => ({
        width: innerWidth,
        height: innerHeight,
        scrollWidth: document.scrollingElement.scrollWidth,
        scrollHeight: document.scrollingElement.scrollHeight,
      }));
      assert.equal(dimensions.width, dimensions.scrollWidth);
      assert.equal(dimensions.height, dimensions.scrollHeight);
      report.viewports.push({
        ...dimensions,
        noScroll: true,
        actionsVisible: true,
      });
      await page.screenshot({
        path: path.join(output, "login-" + width + "x" + height + ".png"),
        animations: "disabled",
      });
    }
    const text = (value) =>
      page
        .getByText(value, { exact: true })
        .or(page.getByLabel(value, { exact: true }))
        .last();
    const press = (name) =>
      page
        .getByRole("button", { includeHidden: true, name, exact: true })
        .click();
    async function type(name, value) {
      const field = page
        .getByRole("textbox", { includeHidden: true, name: new RegExp(name) })
        .first();
      await field.click();
      await field.press("ControlOrMeta+A");
      await field.press("Backspace");
      await field.pressSequentially(value, { delay: 5 });
      await field.press("Tab");
    }
    await press("Masuk");
    await expect(
      text("Masukkan email yang valid.", { exact: true }),
    ).toBeVisible();
    await expect(
      text("Kata sandi wajib diisi.", { exact: true }),
    ).toBeVisible();
    report.states.validation = true;
    await type("Email", "fixture@test.local");
    await type("Kata sandi", "fixture-only");
    await press("Tampilkan kata sandi");
    const nativePassword = page.locator('input[aria-label="Kata sandi"]');
    await expect(nativePassword).toHaveAttribute("type", "text");
    // Flutter's tooltip can temporarily duplicate the accessible button name.
    // Target its rendered semantic label and assert the actual native input type.
    await page
      .locator('[role="button"]')
      .filter({ hasText: "Sembunyikan kata sandi" })
      .click();
    await expect(nativePassword).toHaveAttribute("type", "password");
    report.states.passwordToggle = true;
    const submitBox = await page
      .getByRole("button", { name: "Masuk", exact: true })
      .boundingBox();
    await press("Masuk");
    await expect.poll(() => loginCalls).toBe(1);
    // Disabled Flutter controls may lose the button role in the semantics DOM.
    // Repeated physical clicks must still produce exactly one login request.
    await page.mouse.click(
      submitBox.x + submitBox.width / 2,
      submitBox.y + submitBox.height / 2,
    );
    await page.mouse.click(
      submitBox.x + submitBox.width / 2,
      submitBox.y + submitBox.height / 2,
    );
    assert.equal(loginCalls, 1);
    await page.screenshot({ path: path.join(output, "login-loading.png") });
    releaseLogin();
    await expect(
      text("Email atau kata sandi salah.", { exact: true }),
    ).toBeVisible();
    assert.equal(loginCalls, 1);
    report.states.loadingAndError = true;
    await page.screenshot({ path: path.join(output, "login-error.png") });
    await press("Pasien baru? Daftar");
    await type("Nama lengkap", "Pasien Fixture");
    await press("Daftar pasien");
    await expect(
      text("Akun pasien dibuat. Silakan masuk.", { exact: true }),
    ).toBeVisible();
    assert.equal(registerCalls, 1);
    report.states.registration = true;
    await press("Masuk ke Public Display");
    await expect(
      text("Aktivasi Public Display", { exact: true }),
    ).toBeVisible();
    report.states.publicDisplay = true;
    assert.deepEqual(report.errors, []);
    report.success = true;
    fs.writeFileSync(
      path.join(output, "report.json"),
      JSON.stringify(report, null, 2),
    );
    return report;
  } catch (e) {
    if (page) {
      report.labels = await page
        .locator("[aria-label]")
        .evaluateAll((nodes) => nodes.map((n) => n.getAttribute("aria-label")));
      report.visibleText = await page.locator("body").innerText();
      report.buttons = await page
        .locator('[role="button"]')
        .evaluateAll((nodes) =>
          nodes.map((n) => ({
            label: n.getAttribute("aria-label"),
            text: n.textContent,
          })),
        );
      report.inputs = await page.locator("input").evaluateAll((nodes) =>
        nodes.map((n) => ({
          label: n.getAttribute("aria-label"),
          type: n.type,
          length: n.value.length,
        })),
      );
      await page
        .screenshot({ path: path.join(output, "failed-state.png") })
        .catch(() => {});
    }
    report.error = e.message;
    report.success = false;
    fs.writeFileSync(
      path.join(output, "report.json"),
      JSON.stringify(report, null, 2),
    );
    throw e;
  } finally {
    releaseLogin();
    await browser.close();
  }
};
