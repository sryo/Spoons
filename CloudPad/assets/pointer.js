// Touch handling: enter mouse mode on drag, send smoothed deltas, two-finger
// scroll with momentum, three-finger long-press for right-click, double-tap
// for double-click. Screenshot poll only runs in mouse mode.
(function () {
  const ENTER_THRESHOLD = 5;
  const LONG_PRESS_MS = 500;
  const DOUBLE_TAP_MS = 280;
  const TAP_MAX_DRIFT = 8;

  const state = {
    mouseMode: false,
    touches: new Map(),
    pendingTap: null,
    pendingTapTimer: null,
    scrollVelX: 0,
    scrollVelY: 0,
    momentumTimer: null,
    longPressTimer: null,
    twoFingerStart: null,
    smoothX: 0,
    smoothY: 0,
  };

  const localCursor = () => document.getElementById("local-cursor");
  const screenshotEl = () => document.getElementById("screenshot");
  const serverCursor = () => document.getElementById("server-cursor");

  function send(evt) {
    window.CloudPadTransport.send(evt);
  }

  function enterMouseMode(touch) {
    if (state.mouseMode) return;
    state.mouseMode = true;
    document.body.classList.add("mouse-mode");
    const c = localCursor();
    c.style.left = touch.clientX + "px";
    c.style.top = touch.clientY + "px";
    send({ t: "mode", mode: "mouse" });
    startScreenshotLoop();
  }

  function exitMouseMode() {
    if (!state.mouseMode) return;
    state.mouseMode = false;
    document.body.classList.remove("mouse-mode");
    send({ t: "mode", mode: "keyboard" });
    stopScreenshotLoop();
    stopMomentum();
  }

  // Screenshot poll
  let pollState = { busy: false, timer: null };
  function startScreenshotLoop() {
    if (pollState.timer) return;
    const tick = () => {
      if (!state.mouseMode) return;
      if (pollState.busy) {
        pollState.timer = setTimeout(tick, 500);
        return;
      }
      pollState.busy = true;
      fetch("/screenshot", { cache: "no-store" })
        .then((r) => Promise.all([
          r.blob(),
          parseFloat(r.headers.get("X-Cursor-Pct-X")),
          parseFloat(r.headers.get("X-Cursor-Pct-Y")),
        ]))
        .then(([blob, px, py]) => {
          const el = screenshotEl();
          const url = URL.createObjectURL(blob);
          el.style.backgroundImage = `url(${url})`;
          if (el.dataset.lastUrl) URL.revokeObjectURL(el.dataset.lastUrl);
          el.dataset.lastUrl = url;
          if (!isNaN(px) && !isNaN(py)) {
            const cur = serverCursor();
            cur.style.left = (px * 100) + "%";
            cur.style.top = (py * 100) + "%";
          }
        })
        .catch(() => {})
        .finally(() => {
          pollState.busy = false;
          if (state.mouseMode) pollState.timer = setTimeout(tick, 500);
        });
    };
    tick();
  }
  function stopScreenshotLoop() {
    clearTimeout(pollState.timer);
    pollState.timer = null;
    pollState.busy = false;
  }

  // Momentum scroll
  function stopMomentum() {
    if (state.momentumTimer) {
      clearInterval(state.momentumTimer);
      state.momentumTimer = null;
    }
    state.scrollVelX = 0;
    state.scrollVelY = 0;
  }
  function startMomentum() {
    stopMomentum();
    if (Math.hypot(state.scrollVelX, state.scrollVelY) < 0.5) return;
    state.momentumTimer = setInterval(() => {
      state.scrollVelX *= 0.92;
      state.scrollVelY *= 0.92;
      if (Math.hypot(state.scrollVelX, state.scrollVelY) < 0.3) {
        send({ t: "scroll", dx: 0, dy: 0, phase: "end" });
        stopMomentum();
        return;
      }
      send({ t: "scroll", dx: state.scrollVelX, dy: state.scrollVelY, phase: "momentum" });
    }, 16);
  }

  // Touch lifecycle on the pointer surface (the whole document while in mouse mode,
  // and the keyboard layers while not — but pointer-driven moves only happen here).
  function onTouchStart(e) {
    const t = e.changedTouches[0];
    const now = Date.now();

    if (e.touches.length === 1 && !state.mouseMode) {
      // Could be tap-to-enter-mouse-mode candidate (only when starting on the keyboard
      // surface, not directly on a key — keyboard handles its own taps).
      const el = document.elementFromPoint(t.clientX, t.clientY);
      if (el && el.closest(".key")) return; // let keyboard handle it
      state.touches.set(t.identifier, { x0: t.clientX, y0: t.clientY, x: t.clientX, y: t.clientY, t: now });
      return;
    }

    if (state.mouseMode) {
      // Track all touches.
      for (const touch of e.changedTouches) {
        state.touches.set(touch.identifier, { x0: touch.clientX, y0: touch.clientY, x: touch.clientX, y: touch.clientY, t: now });
      }
      stopMomentum();

      if (e.touches.length === 2) {
        state.twoFingerStart = now;
      }
      if (e.touches.length === 3) {
        clearTimeout(state.longPressTimer);
        state.longPressTimer = setTimeout(() => {
          send({ t: "click", button: "right", count: 1 });
          state.longPressTimer = null;
        }, LONG_PRESS_MS);
      }
    }
  }

  function onTouchMove(e) {
    if (!state.mouseMode) {
      // Pre-mouse-mode: detect drag-to-enter on a single finger.
      const t = e.changedTouches[0];
      const data = state.touches.get(t.identifier);
      if (!data) return;
      data.x = t.clientX;
      data.y = t.clientY;
      const dist = Math.hypot(t.clientX - data.x0, t.clientY - data.y0);
      if (e.touches.length === 1 && dist > ENTER_THRESHOLD) {
        enterMouseMode(t);
      }
      return;
    }

    e.preventDefault();
    const c = localCursor();

    if (e.touches.length === 1) {
      const t = e.touches[0];
      const data = state.touches.get(t.identifier);
      if (!data) return;
      let dx = t.clientX - data.x;
      let dy = t.clientY - data.y;
      data.x = t.clientX;
      data.y = t.clientY;

      // EMA smoothing on raw deltas
      state.smoothX = state.smoothX * 0.5 + dx * 0.5;
      state.smoothY = state.smoothY * 0.5 + dy * 0.5;

      send({ t: "move", dx: state.smoothX, dy: state.smoothY });

      c.style.left = t.clientX + "px";
      c.style.top = t.clientY + "px";
      if (state.longPressTimer) {
        clearTimeout(state.longPressTimer);
        state.longPressTimer = null;
      }
    } else if (e.touches.length === 2) {
      const t = e.touches[0];
      const data = state.touches.get(t.identifier);
      if (!data) return;
      const dx = t.clientX - data.x;
      const dy = t.clientY - data.y;
      data.x = t.clientX;
      data.y = t.clientY;
      state.scrollVelX = dx;
      state.scrollVelY = dy;
      send({ t: "scroll", dx: dx, dy: dy, phase: "continue" });
    }
  }

  function onTouchEnd(e) {
    const now = Date.now();
    const lifted = e.changedTouches[0];
    const data = lifted ? state.touches.get(lifted.identifier) : null;
    if (lifted) state.touches.delete(lifted.identifier);

    if (state.longPressTimer) {
      clearTimeout(state.longPressTimer);
      state.longPressTimer = null;
    }

    if (state.mouseMode) {
      // If the lift leaves zero touches, that's an exit point. A short tap
      // with no drift is a left click; back-to-back is a double-click.
      if (e.touches.length === 0) {
        if (data) {
          const drift = Math.hypot(data.x - data.x0, data.y - data.y0);
          const dur = now - data.t;
          if (drift < TAP_MAX_DRIFT && dur < LONG_PRESS_MS) {
            if (state.pendingTap && (now - state.pendingTap) < DOUBLE_TAP_MS) {
              clearTimeout(state.pendingTapTimer);
              state.pendingTap = null;
              state.pendingTapTimer = null;
              send({ t: "click", button: "left", count: 2 });
            } else {
              state.pendingTap = now;
              state.pendingTapTimer = setTimeout(() => {
                send({ t: "click", button: "left", count: 1 });
                state.pendingTap = null;
                state.pendingTapTimer = null;
              }, DOUBLE_TAP_MS);
            }
          }
        }
        // Was a two-finger scroll? Kick off momentum.
        if (state.twoFingerStart && Math.hypot(state.scrollVelX, state.scrollVelY) > 1.0) {
          send({ t: "scroll", dx: 0, dy: 0, phase: "end" });
          startMomentum();
        }
        state.twoFingerStart = null;
        exitMouseMode();
      }
    }
  }

  // Attach passive: false where we call preventDefault.
  document.addEventListener("touchstart", onTouchStart, { passive: false });
  document.addEventListener("touchmove", onTouchMove, { passive: false });
  document.addEventListener("touchend", onTouchEnd, { passive: false });
  document.addEventListener("touchcancel", onTouchEnd, { passive: false });

  window.CloudPadPointer = { exitMouseMode };
})();
