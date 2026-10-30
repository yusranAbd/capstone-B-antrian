/** Focused patient smoke; run-live owns guarded unique fixtures and cleanup. */
const { chromium, expect: baseExpect } = require("@playwright/test");
const expect = baseExpect.configure({ timeout: 30000 });
const { enter } = require("./browser-demo.cjs").helpers;
const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");

module.exports = async ({
  fixture,
  output = path.resolve(__dirname, "../build/animate-pilot/browser"),
  prepareContext,
}) => {
  fs.mkdirSync(output, { recursive: true });
  const browser = await chromium.launch({
    channel: process.env.FLUTTER_BROWSER_CHANNEL || "chrome",
    headless: true,
  });
  const cases = [];
  let phase = "login";
  try {
    for (const reduced of [false, true]) {
      phase = "engine-startup";
      const context = await browser.newContext({
        viewport: { width: 390, height: 844 },
        reducedMotion: reduced ? "reduce" : "no-preference",
      });
      if (prepareContext) await prepareContext(context);
      const page = await context.newPage();
      try {
        await page.bringToFront();
        const requests = [],
          errors = [],
          serverErrors = [];
        let patientSockets = 0,
          closedSockets = 0;
        page.on("websocket", (socket) => {
          const url = new URL(socket.url());
          if (url.host === "127.0.0.1:3001" && url.pathname === "/socket.io/") {
            patientSockets++;
            socket.on("close", () => closedSockets++);
          }
        });
        page.on("pageerror", (e) => errors.push(e.name));
        page.on("request", (r) => {
          const url = new URL(r.url());
          if (url.pathname.startsWith("/api/v1/"))
            requests.push({ method: r.method(), path: url.pathname });
        });
        page.on("response", (r) => {
          if (r.status() >= 500) serverErrors.push(r.status());
        });
        await page.goto("http://127.0.0.1:8080/");
        // Engine/CDN initialization precedes all application assertions.
        await page
          .locator("flt-glass-pane")
          .waitFor({ state: "attached", timeout: 90000 });
        phase = "login";
        assert.equal(
          await page.evaluate(
            () => matchMedia("(prefers-reduced-motion: reduce)").matches,
          ),
          reduced,
        );
        const account = fixture[reduced ? "patient2" : "patient1"];
        for (const [name, value] of [
          ["Email", account.email],
          ["Kata sandi", account.password],
        ]) {
          // Existing helper accepts Flutter's label plus focus-time hint text.
          await enter(page, name, value);
        }
        await page.getByRole("button", { name: "Masuk", exact: true }).click();
        await expect(page).toHaveURL(/#\/patient$/);
        await expect.poll(() => patientSockets).toBe(1);
        phase = "reservation-catalog";
        await page.getByRole("tab", { name: "Reservasi", exact: true }).click();
        await page
          .getByRole("button", { name: "Buat Reservasi", exact: true })
          .click();
        await page.getByRole("button", { name: /Pilih Poliklinik/ }).click();
        const clinic = page
          .getByRole("button", { name: /Poli Fixture Flutter/ })
          .or(page.getByText("Poli Fixture Flutter", { exact: true }))
          .first();
        await clinic.scrollIntoViewIfNeeded();
        await clinic.click();
        await page
          .getByRole("button", { name: "Walk-in", exact: true })
          .or(page.getByRole("radio", { name: "Walk-in", exact: true }))
          .or(page.getByText("Walk-in", { exact: true }))
          .first()
          .click();
        const reserve = page.getByRole("button", {
          name: "Reservasi walk-in",
          exact: true,
        });
        await reserve.scrollIntoViewIfNeeded();
        await reserve.click();
        phase = "explicit-confirmation";
        assert.equal(
          requests.filter(
            (r) => r.method === "POST" && r.path === "/api/v1/reservasi",
          ).length,
          0,
        );
        const committed = page.waitForResponse(
          (r) =>
            r.request().method() === "POST" &&
            new URL(r.url()).pathname === "/api/v1/reservasi",
        );
        await page
          .getByRole("button", { name: "Lanjutkan", exact: true })
          .click();
        const response = await committed;
        phase = "confirmed-ticket";
        assert.equal(response.status(), 201);
        const ticket = await response.json();
        assert.equal(ticket.status, "DIPESAN");
        await expect(page).toHaveURL(/#\/patient\/tickets$/);
        await expect(
          page
            .getByRole("button", { name: "Lihat Tiket / QR", exact: true })
            .first(),
        ).toBeVisible();
        // This engine exposes unfocused SelectableText as an empty disabled
        // textarea. Assert its surface here; review the captured text visually.
        // Flutter widget tests compare the actual notice's semantics to baseline.
        await expect(
          page.getByRole("textbox", { disabled: true }),
        ).toBeVisible();
        // Wait only the finite effect window using real frame timestamps.
        await page.evaluate(
          () =>
            new Promise((resolve) => {
              const end = performance.now() + 220;
              const frame = (t) =>
                t >= end ? resolve() : requestAnimationFrame(frame);
              requestAnimationFrame(frame);
            }),
        );
        await page.screenshot({
          path: path.join(
            output,
            reduced ? "patient-reduced.png" : "patient-normal.png",
          ),
        });
        for (const [label, destination] of [
          ["Beranda", ""],
          ["Reservasi", "/reservations"],
          ["Tiket Saya", "/tickets"],
          ["Janji Temu", "/appointments"],
          ["Profil", "/profile"],
        ]) {
          phase = "navigation-" + label;
          await page.getByRole("tab", { name: label, exact: true }).click();
          await expect(page).toHaveURL(
            new RegExp("#/patient" + destination + "$"),
          );
        }
        phase = "logout";
        assert.equal(patientSockets, 1);
        await page
          .getByRole("button", { name: "Keluar Akun", exact: true })
          .click();
        await expect(page).toHaveURL(/#\/login\?from=\/patient\/profile$/);
        await expect.poll(() => closedSockets).toBe(1);
        const posts = requests.filter(
          (r) => r.method === "POST" && r.path === "/api/v1/reservasi",
        ).length;
        const qrPosts = requests.filter(
          (r) => r.method === "POST" && r.path.endsWith("/qr"),
        ).length;
        assert.equal(posts, 1);
        assert.equal(qrPosts, 0);
        assert.equal(errors.length, 0);
        assert.equal(serverErrors.length, 0);
        cases.push({
          reducedMotion: reduced,
          status: "PASS",
          bookingPosts: posts,
          qrPosts,
          navigationTabs: 5,
          runtimeErrors: errors.length,
          http5xx: serverErrors.length,
          socketConnections: patientSockets,
          socketClosures: closedSockets,
        });
      } catch (error) {
        await page
          .screenshot({
            path: path.join(output, "failure-diagnostic.png"),
            mask: [
              page.locator(
                'input[type="password"], input[placeholder="nama@email.com"]',
              ),
            ],
          })
          .catch(() => {});
        if (phase === "confirmed-ticket") {
          fs.writeFileSync(
            path.join(output, "failure-semantics.txt"),
            require("./recovery-observer.cjs").scrub(
              await page.locator("body").ariaSnapshot(),
            ),
          );
        }
        if (phase === "login" || phase === "engine-startup") {
          await page
            .screenshot({
              path: path.join(output, "login-diagnostic.png"),
              mask: [page.locator("input, textarea")],
            })
            .catch(() => {});
          fs.writeFileSync(
            path.join(output, "startup.json"),
            JSON.stringify(
              {
                phase,
                errorType: error.name,
                glassPanes: await page.locator("flt-glass-pane").count(),
                textboxes: await page.getByRole("textbox").count(),
              },
              null,
              2,
            ),
          );
        }
        throw error;
      } finally {
        await context.close();
      }
    }
    fs.writeFileSync(
      path.join(output, "summary.json"),
      JSON.stringify(
        { environment: "real guarded NestJS/PostgreSQL test + browser", cases },
        null,
        2,
      ) + "\n",
    );
    console.log(
      "Patient motion browser: PASS (normal/reduced, explicit booking, five tabs, logout)",
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
    console.error("Patient motion browser failed phase: " + phase);
    throw error;
  } finally {
    await browser.close();
  }
};
