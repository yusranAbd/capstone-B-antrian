const { test } = require("node:test");
const assert = require("node:assert/strict");
const { sampleFrames, frameSummary } = require("./motion-profile.cjs");
test("profiling reports observed intervals without converting missing data to 60FPS", () => {
  assert.equal(frameSummary([]).p95Ms, null);
  const input = [16, 50, 17, 16];
  assert.deepEqual(frameSummary(input), {
    intervals: 4,
    p50Ms: 16,
    p95Ms: 50,
    maxMs: 50,
    frameBudgetMs: 16.7,
    overBudget: 2,
    over25Ms: 1,
  });
  assert.deepEqual(input, [16, 50, 17, 16]);
});
test("disabled profiling preserves a single action/result without touching the browser", async () => {
  const before = process.env.QUEUEB_MOTION_PROFILE;
  delete process.env.QUEUEB_MOTION_PROFILE;
  try {
    let calls = 0;
    assert.equal(await sampleFrames(null, "test", () => ++calls, []), 1);
    assert.equal(calls, 1);
  } finally {
    if (before === undefined) delete process.env.QUEUEB_MOTION_PROFILE;
    else process.env.QUEUEB_MOTION_PROFILE = before;
  }
});
test("profiling rejects an unverified origin before any action", async () => {
  const before = process.env.QUEUEB_MOTION_PROFILE;
  process.env.QUEUEB_MOTION_PROFILE = "1";
  try {
    let calls = 0;
    await assert.rejects(
      sampleFrames(
        { url: () => "https://example.test/" },
        "test",
        () => ++calls,
        [],
      ),
      /Profile URL denied/,
    );
    assert.equal(calls, 0);
  } finally {
    if (before === undefined) delete process.env.QUEUEB_MOTION_PROFILE;
    else process.env.QUEUEB_MOTION_PROFILE = before;
  }
});
