/** Contain async EventEmitter callbacks; Node does not await event listeners. */
function eventObservers() {
  const pending = new Set(),
    errors = [],
    closingErrors = [];
  let closing = false;
  return {
    errors,
    closingErrors,
    on(emitter, event, callback) {
      emitter.on(event, (...args) => {
        const work = Promise.resolve()
          .then(() => callback(...args))
          .catch((error) =>
            (closing ? closingErrors : errors).push({
              type: error.name || "Error",
            }),
          )
          .finally(() => pending.delete(work));
        pending.add(work);
      });
    },
    async drain() {
      await Promise.all([...pending]);
    },
    closing() {
      closing = true;
    },
  };
}
module.exports = { eventObservers };
