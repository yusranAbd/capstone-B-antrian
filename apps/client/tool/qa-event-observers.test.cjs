const test = require("node:test"),
  assert = require("node:assert/strict");
const { EventEmitter } = require("node:events");
const { eventObservers } = require("./qa-event-observers.cjs");
test("a rejected async response observer is recorded and drained instead of killing fixture cleanup", async () => {
  const group = eventObservers(),
    events = new EventEmitter();
  let cleaned = false;
  group.on(events, "response", async () => {
    throw Object.assign(new Error("private response body"), {
      name: "TargetClosedError",
    });
  });
  try {
    events.emit("response");
    await group.drain();
    assert.deepEqual(group.errors, [{ type: "TargetClosedError" }]);
  } finally {
    cleaned = true;
  }
  assert.equal(cleaned, true);
  assert.equal(JSON.stringify(group.errors).includes("private"), false);
});
test("late page-close errors remain observed after shutdown without being unhandled", async () => {
  const group = eventObservers(),
    events = new EventEmitter();
  group.on(events, "response", async () => {
    throw Error("closed");
  });
  group.closing();
  events.emit("response");
  await group.drain();
  assert.deepEqual(group.errors, []);
  assert.deepEqual(group.closingErrors, [{ type: "Error" }]);
});
