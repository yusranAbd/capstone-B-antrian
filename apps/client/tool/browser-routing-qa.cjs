/** Routing assertions against the existing isolated live fixture. Never exports credentials/IDs. */
const assert = require("node:assert/strict");
const { expect: baseExpect } = require("@playwright/test");
const expect = baseExpect.configure({ timeout: 30000 });
const { enter, button } = require("./browser-demo.cjs").helpers;
const { randomUUID } = require("node:crypto");
const base = "http://127.0.0.1:8080/";
const api = "http://127.0.0.1:3001/api/v1";
const admin = [
  "/admin",
  "/admin/polyclinics",
  "/admin/doctors",
  "/admin/rooms",
  "/admin/service-hours",
  "/admin/practice-schedules",
  "/admin/consultation-slots",
  "/admin/staff-assignments",
  "/admin/displays",
  "/admin/profile",
];
const patient = [
  "/patient",
  "/patient/reservations",
  "/patient/tickets",
  "/patient/appointments",
  "/patient/profile",
];

module.exports = async ({ browser, fixture, displayPage, displayId }) => {
  const report = {
    status: "RUNNING",
    checks: [],
    runtimeErrors: 0,
    http5xx: 0,
    nonAuthMutations: 0,
    requestCounts: {},
    physicalDeviceVerified: false,
  };
  const contexts = [];
  let activePage;
  function pass(id) {
    report.checks.push({ id, status: "PASS" });
  }
  function watch(p) {
    p.on("pageerror", () => report.runtimeErrors++);
    p.on("response", (r) => {
      if (r.url().startsWith(api) && r.status() >= 500) report.http5xx++;
    });
    p.on("request", (r) => {
      if (!r.url().startsWith(api)) return;
      const method = r.method();
      report.requestCounts[method] = (report.requestCounts[method] || 0) + 1;
      if (
        !["GET", "OPTIONS"].includes(method) &&
        !r.url().startsWith(api + "/auth/")
      )
        report.nonAuthMutations++;
    });
  }
  async function page() {
    const context = await browser.newContext({
      viewport: { width: 1366, height: 900 },
    });
    contexts.push(context);
    const p = await context.newPage();
    watch(p);
    return p;
  }
  async function signIn(p, role) {
    await enter(p, "Email", fixture[role].email);
    await enter(p, "Kata sandi", fixture[role].password);
    await button(p, "Masuk");
    await expect(
      p.getByRole("textbox", { name: "Email", exact: true }),
    ).toHaveCount(0);
  }
  async function tab(p, name) {
    await p.bringToFront();
    await p.getByRole("tab", { name, exact: true }).click();
  }
  // Canvas text can be represented by an exact accessibility label rather
  // than a DOM text node. Flutter may merge a heading/name into a larger
  // group or image label; the visible label must still contain that UI value.
  function text(p, value) {
    return p
      .getByText(value, { exact: true })
      .or(p.getByLabel(value, { exact: false }))
      .first();
  }
  async function location(p, path) {
    await expect
      .poll(() => new URL(p.url()).hash.slice(1), { timeout: 30000 })
      .toBe(path);
  }
  async function cold(p, path, role) {
    activePage = p;
    report.lastAction =
      role +
      " cold " +
      path.split("?")[0].replace(/[0-9a-f]{8}-[0-9a-f-]{27,}/gi, "<id>");
    await p.goto(base + "#" + path);
    await p.reload(); // Web account store is deliberately memory-only.
    await expect(
      p.getByRole("textbox", { name: "Email", exact: true }),
    ).toBeVisible();
    const beforeLogin = new URL(p.url()).hash.slice(1);
    assert.equal(new URL(beforeLogin, base).pathname, "/login");
    await signIn(p, role);
    await location(p, path);
  }
  try {
    const a = await page();
    for (const path of admin) await cold(a, path, "admin");
    pass("T01-T02-T07: ten ADMIN locations cold auth/role routing");
    await a.goto(base + "#/admin/polyclinics");
    await location(a, "/admin/polyclinics");
    await a.goto(base + "#/admin/doctors");
    await location(a, "/admin/doctors");
    await a.goBack();
    await location(a, "/admin/polyclinics");
    await a.goForward();
    await location(a, "/admin/doctors");
    pass("T08-T29: ADMIN browser Back/Forward");
    await a.goto(base + "#/patient");
    await location(a, "/forbidden");
    await expect(
      a.getByText("Halaman tidak dapat diakses oleh akun ini.", {
        exact: true,
      }),
    ).toBeVisible();
    pass("T28: cross-role protected destination rejected");
    await a.context().close();

    const p = await page();
    await cold(p, "/patient/reservations/new", "patient1");
    pass("T12: cold booking is navigation without mutation");
    const destinations = [
      "Beranda",
      "Reservasi",
      "Tiket Saya",
      "Janji Temu",
      "Profil",
    ];
    for (let i = 0; i < destinations.length; i++) {
      await tab(p, destinations[i]);
      await location(p, patient[i]);
    }
    await tab(p, "Reservasi");
    await location(p, "/patient/reservations");
    await p.goto(base + "#/patient/reservations/new");
    await location(p, "/patient/reservations/new");
    await tab(p, "Reservasi");
    await location(p, "/patient/reservations");
    pass("T10-T12: five branch URLs and reservation retap");
    await cold(
      p,
      `/patient/reservations/doctors/${fixture.doctorId}?clinic=${fixture.serviceId}`,
      "patient1",
    );
    await expect(text(p, "Detail Dokter")).toBeVisible();
    await expect(
      p.getByRole("button", { name: "Buat Janji Temu", exact: true }),
    ).toBeVisible();
    await expect(text(p, "Dokter Fixture Flutter")).toBeVisible();
    pass("T13: doctor cold GET hydration");
    const auth = await fetch(api + "/auth/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        email: fixture.patient1.email,
        kataSandi: fixture.patient1.password,
      }),
    });
    assert.equal(auth.ok, true);
    const token = (await auth.json()).accessToken;
    const visits = await fetch(api + "/tiket/saya", {
      headers: { Authorization: "Bearer " + token },
    });
    assert.equal(visits.status, 200);
    const tickets = await visits.json();
    assert.equal(Array.isArray(tickets) && tickets.length > 0, true);
    await cold(p, "/patient/tickets/" + tickets[0].id, "patient1");
    await expect(
      p.getByRole("button", { name: "Lihat tiket & QR", exact: true }),
    ).toBeVisible();
    assert.equal(report.nonAuthMutations, 0);
    pass("T13-T14: own ticket cold GET, no automatic QR POST");
    await p.goto(base + "#/patient/tickets/" + randomUUID());
    report.lastAction = "missing ticket accessible error";
    await expect(
      text(p, "Tiket tidak tersedia atau tidak dapat diakses."),
    ).toBeVisible();
    pass("T06-T13: missing ticket safe error");
    await p.goto(base + "#/missing?token=queueb-routing-echo-probe");
    await expect(text(p, "Halaman tidak tersedia.")).toBeVisible();
    await expect(
      p
        .getByText("queueb-routing-echo-probe", { exact: false })
        .or(p.getByLabel("queueb-routing-echo-probe", { exact: false })),
    ).toHaveCount(0);
    pass("T06: unknown location does not echo query");
    await p.context().close();

    for (const [role, home] of [
      ["petugas", "/staff"],
      ["doctor", "/doctor"],
    ]) {
      const q = await page();
      await cold(q, home + "/profile", role);
      await expect(text(q, "Profil Saya")).toBeVisible();
      await q.goBack(); // actual browser history, separate from Android branch policy
      await q.goto(base + "#" + home);
      await location(q, home);
      await q.context().close();
    }
    pass("T19-T20: staff/doctor cold profile URLs");

    const d = await page();
    await d.goto(base + "#/register");
    await expect(
      d.getByRole("textbox", { name: "Nama lengkap", exact: true }),
    ).toBeVisible();
    await d.goto(base + "#/session");
    await location(d, "/login");
    await d.goto(base + "#/forbidden");
    await expect(
      d.getByText("Halaman tidak dapat diakses oleh akun ini.", {
        exact: true,
      }),
    ).toBeVisible();
    pass("T02-T03-T06: public register, ready session, forbidden routes");
    await d.goto(base + "#/display");
    await location(d, "/display");
    await expect(
      d.getByRole("textbox", { name: "Kode Aktivasi", exact: true }),
    ).toBeVisible();
    await d.reload();
    await location(d, "/display");
    await expect(
      d.getByRole("textbox", { name: "Email", exact: true }),
    ).toHaveCount(0);
    const pathResponse = await d.request.get(base + "patient/reservations");
    assert.equal(pathResponse.status(), 404);
    pass("T21-T29-T30: hash display cold/reload; path hosting stays 404");
    await d.goto(
      base + "#/login?from=" + encodeURIComponent("https://example.invalid/"),
    );
    await signIn(d, "patient1");
    await location(d, "/patient");
    pass("T05: browser unsafe return rejected");
    await d.goto(base + "#/login?from=%FF");
    await location(d, "/forbidden");
    await expect(
      text(d, "Halaman tidak dapat diakses oleh akun ini."),
    ).toBeVisible();
    pass("T05-T06: malformed UTF-8 query rejected safely");
    assert.equal(report.nonAuthMutations, 0);
    assert.equal(report.http5xx, 0);
    assert.equal(report.runtimeErrors, 0);
    if (displayPage) {
      const context = displayPage.context();
      const independent = await context.newPage();
      watch(independent);
      await independent.goto(base + "#/display");
      await expect(
        independent.getByRole("textbox", {
          name: "Kode Aktivasi",
          exact: true,
        }),
      ).toBeVisible();
      await independent.close();
      const opened = context.waitForEvent("page");
      await displayPage.evaluate(() => window.open(location.href, "_blank"));
      const clone = await opened;
      watch(clone);
      await expect(
        clone.getByText("Realtime terhubung", { exact: true }),
      ).toBeVisible();
      const cookies = await context.cookies(api);
      assert.equal(
        cookies.some(
          (c) => c.name === "queueb_display_" + displayId && c.httpOnly,
        ),
        true,
      );
      await clone.close();
      pass(
        "T24: independent tab empty; opener copies selector; named cookie stays HttpOnly",
      );
      await displayPage.bringToFront();
      await button(displayPage, "Layar penuh");
      await expect
        .poll(() => displayPage.evaluate(() => !!document.fullscreenElement))
        .toBe(true);
      await button(displayPage, "Keluar fullscreen");
      await expect
        .poll(() => displayPage.evaluate(() => !!document.fullscreenElement))
        .toBe(false);
      pass("T27: live display fullscreen enter/exit");
    }
    report.status = "PASS";
    return report;
  } catch (error) {
    report.status = "FAIL";
    report.safeProbe = await activePage
      ?.evaluate(() => {
        const text =
          document.body.innerText +
          "\n" +
          [...document.querySelectorAll("[aria-label]")]
            .map((n) => n.getAttribute("aria-label"))
            .join("\n");
        return Object.fromEntries(
          [
            "Detail Dokter",
            "Buat Janji Temu",
            "Pilih Jadwal Praktik",
            "Kembali ke reservasi",
            "Pilihan tidak tersedia.",
            "Halaman tidak dapat diakses",
            "Email",
            "Dokter Fixture Flutter",
            "Memuat data pelayanan",
            "Tiket tidak tersedia atau tidak dapat diakses.",
          ].map((label) => [label, text.includes(label)]),
        );
      })
      .catch(() => null);
    error.routingReport = report;
    throw error;
  } finally {
    for (const c of contexts) await c.close().catch(() => {});
  }
};
