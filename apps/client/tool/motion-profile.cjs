// Opt-in profiling of the guarded compiled test app. No app state, API calls,
// tokens, DOM content or patient labels are collected. This is browser rAF,
// not Flutter UI/raster timing and not a physical-device FPS certification.
const assert = require("node:assert/strict");

function frameSummary(intervals) {
  const sorted = intervals.slice().sort((a, b) => a - b);
  const percentile = (p) =>
    sorted.length
      ? Number(
          sorted[
            Math.min(sorted.length - 1, Math.ceil(sorted.length * p) - 1)
          ].toFixed(2),
        )
      : null;
  return {
    intervals: sorted.length,
    p50Ms: percentile(0.5),
    p95Ms: percentile(0.95),
    maxMs: percentile(1),
    frameBudgetMs: 16.7,
    overBudget: sorted.filter((v) => v > 16.7).length,
    over25Ms: sorted.filter((v) => v > 25).length,
  };
}

async function sampleFrames(page, scenario, action, reports) {
  if (process.env.QUEUEB_MOTION_PROFILE !== "1") return action();
  assert.equal(
    new URL(page.url()).origin,
    "http://127.0.0.1:8080",
    "Profile URL denied",
  );
  await page.bringToFront();
  const started = Date.now();
  const sample = page.evaluate(
    () =>
      new Promise((resolve) => {
        const intervals = [],
          longTasks = [];
        let last,
          begin,
          raf,
          timer,
          done = false,
          observer;
        const finish = () => {
          if (done) return;
          done = true;
          cancelAnimationFrame(raf);
          clearTimeout(timer);
          observer?.disconnect();
          resolve({
            intervals,
            longTasks,
            visibility: document.visibilityState,
          });
        };
        if (PerformanceObserver.supportedEntryTypes.includes("longtask")) {
          observer = new PerformanceObserver((list) => {
            for (const entry of list.getEntries())
              longTasks.push(entry.duration);
          });
          observer.observe({ entryTypes: ["longtask"] });
        }
        const frame = (now) => {
          begin ??= now;
          if (last !== undefined) intervals.push(now - last);
          last = now;
          if (now - begin >= 1200) finish();
          else raf = requestAnimationFrame(frame);
        };
        timer = setTimeout(finish, 2200); // Bounded fallback for a suspended test tab.
        raf = requestAnimationFrame(frame);
      }),
  );
  // The existing action runs exactly once; awaiting metrics never resubmits it.
  const [measurement, operation] = await Promise.allSettled([
    sample,
    Promise.resolve().then(action),
  ]);
  if (measurement.status === "fulfilled") {
    reports.push({
      scenario,
      ...frameSummary(measurement.value.intervals),
      longTaskDurationsMs: measurement.value.longTasks.map((v) =>
        Number(v.toFixed(2)),
      ),
      visibility: measurement.value.visibility,
      elapsedMs: Date.now() - started,
      actionStatus: operation.status === "fulfilled" ? "PASS" : "FAIL",
      method:
        "1200ms browser rAF around existing action; includes host/API waits; not Flutter raster timing",
    });
  }
  if (operation.status === "rejected") throw operation.reason;
  if (measurement.status === "rejected") throw measurement.reason;
  return operation.value;
}

module.exports = { sampleFrames, frameSummary };
