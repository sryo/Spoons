// Batched POST transport. Coalesces high-frequency move/scroll events into
// an 8ms flush bucket; low-frequency events flush immediately.
(function () {
  const FLUSH_MS = 8;
  const queue = [];
  let seq = 0;
  let flushTimer = null;
  let inFlight = false;

  function flush() {
    flushTimer = null;
    if (inFlight) {
      // Re-arm; previous batch still in flight, will retry on next idle.
      flushTimer = setTimeout(flush, FLUSH_MS);
      return;
    }
    if (queue.length === 0) return;

    const batch = { v: 1, seq: ++seq, events: queue.splice(0) };
    inFlight = true;
    fetch("/events", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(batch),
      keepalive: true,
    }).catch(() => {}).finally(() => {
      inFlight = false;
      if (queue.length > 0 && !flushTimer) {
        flushTimer = setTimeout(flush, FLUSH_MS);
      }
    });
  }

  function arm() {
    if (!flushTimer) flushTimer = setTimeout(flush, FLUSH_MS);
  }

  function coalesceLast(t) {
    if (queue.length === 0) return null;
    const last = queue[queue.length - 1];
    if (last && last.t === t) return last;
    return null;
  }

  function send(evt) {
    if (evt.t === "move" || evt.t === "scroll") {
      const last = coalesceLast(evt.t);
      if (last) {
        last.dx = (last.dx || 0) + (evt.dx || 0);
        last.dy = (last.dy || 0) + (evt.dy || 0);
        if (evt.phase) last.phase = evt.phase;
        arm();
        return;
      }
      queue.push(evt);
      arm();
      return;
    }
    queue.push(evt);
    if (flushTimer) clearTimeout(flushTimer);
    flushTimer = setTimeout(flush, 0);
  }

  window.CloudPadTransport = { send };
})();
