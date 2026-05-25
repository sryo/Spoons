// Keyboard layers, sticky modifiers (tap = one-shot, double-tap = locked),
// adaptive bigram-weighted hit-test on the main letter layer. Sends `key`,
// `text`, or click events via the transport.
(function () {
  const ADAPTIVE_WEIGHT = 2.0;
  const DOUBLE_TAP_MS = 320;
  const KEY_REPEAT_DELAY = 350;
  const KEY_REPEAT_RATE = 40;

  const state = {
    layer: "main",
    oneShotMods: new Set(),
    lockedMods: new Set(),
    lastModTap: new Map(), // mod -> ts
    prevChar: null,
    pressed: new Map(), // touchId -> { key, repeatTimer }
  };

  const layers = {
    main: document.querySelector('.layer.main'),
    symbols: document.querySelector('.layer.symbols'),
    media: document.querySelector('.layer.media'),
  };

  function send(evt) { window.CloudPadTransport.send(evt); }

  function activeMods() {
    const out = [];
    for (const m of state.lockedMods) out.push(m);
    for (const m of state.oneShotMods) if (!state.lockedMods.has(m)) out.push(m);
    return out;
  }

  function clearOneShots() {
    if (state.oneShotMods.size === 0) return;
    state.oneShotMods.clear();
    refreshModUI();
  }

  function refreshModUI() {
    document.querySelectorAll('.key.mod[data-mod]').forEach((btn) => {
      const m = btn.dataset.mod;
      btn.classList.toggle('active', state.oneShotMods.has(m) && !state.lockedMods.has(m));
      btn.classList.toggle('locked', state.lockedMods.has(m));
    });
  }

  function switchLayer(name) {
    if (!layers[name]) return;
    state.layer = name;
    Object.entries(layers).forEach(([n, el]) => {
      if (el) el.classList.toggle('active', n === name);
    });
  }

  function adaptiveHitTest(touch, container) {
    if (!window.CloudPadBigrams || !state.prevChar) return null;
    const followers = window.CloudPadBigrams[state.prevChar] || {};
    const keys = container.querySelectorAll('.key.adaptive');
    if (keys.length === 0) return null;
    let best = null;
    let bestScore = Infinity;
    let avgSize = 0;
    keys.forEach((k) => {
      const r = k.getBoundingClientRect();
      avgSize += (r.width + r.height) * 0.5;
    });
    avgSize /= keys.length;
    keys.forEach((k) => {
      const r = k.getBoundingClientRect();
      const cx = r.left + r.width / 2;
      const cy = r.top + r.height / 2;
      const d = Math.hypot(touch.clientX - cx, touch.clientY - cy);
      const inside = touch.clientX >= r.left && touch.clientX <= r.right &&
                     touch.clientY >= r.top && touch.clientY <= r.bottom;
      const p = followers[k.dataset.key] || 0;
      const weight = 1 + p * ADAPTIVE_WEIGHT;
      let score = d / avgSize / weight;
      if (inside) score *= 0.5;
      if (score < bestScore) {
        bestScore = score;
        best = k;
      }
    });
    // Cap: if the best key is far away, fall back to default hit-testing.
    if (bestScore > 1.5) return null;
    return best;
  }

  function resolveKey(touch) {
    let el = document.elementFromPoint(touch.clientX, touch.clientY);
    if (el && !el.classList.contains('key')) el = el.closest('.key');
    if (!el) return null;

    if (state.layer === 'main' && el.classList.contains('adaptive')) {
      const adapt = adaptiveHitTest(touch, layers.main);
      if (adapt) return adapt;
    }
    return el;
  }

  function emitKey(el) {
    if (el.dataset.layerSwitch) {
      switchLayer(el.dataset.layerSwitch);
      return;
    }
    if (el.dataset.mod) {
      const m = el.dataset.mod;
      const now = Date.now();
      const lastTap = state.lastModTap.get(m) || 0;
      if (now - lastTap < DOUBLE_TAP_MS) {
        // Double-tap: toggle lock
        if (state.lockedMods.has(m)) {
          state.lockedMods.delete(m);
          state.oneShotMods.delete(m);
        } else {
          state.lockedMods.add(m);
          state.oneShotMods.add(m);
        }
      } else {
        if (state.oneShotMods.has(m)) {
          state.oneShotMods.delete(m);
          state.lockedMods.delete(m);
        } else {
          state.oneShotMods.add(m);
        }
      }
      state.lastModTap.set(m, now);
      refreshModUI();
      return;
    }
    if (el.dataset.mouse) {
      const map = {
        leftclick: { t: "click", button: "left", count: 1 },
        rightclick: { t: "click", button: "right", count: 1 },
        middleclick: { t: "click", button: "middle", count: 1 },
        scrollup: { t: "scroll", dx: 0, dy: -40, phase: "continue" },
        scrolldown: { t: "scroll", dx: 0, dy: 40, phase: "continue" },
      };
      const evt = map[el.dataset.mouse];
      if (evt) send(evt);
      return;
    }
    if (el.dataset.text) {
      send({ t: "text", s: el.dataset.text });
      return;
    }
    if (el.dataset.key) {
      const mods = activeMods();
      // Shift maps to data-shift display, alt to data-alt. The Mac handles
      // case/symbol output via the real modifier — we just send the base key.
      send({ t: "key", key: el.dataset.key, mods: mods });
      // Track last char for adaptive layout
      const k = el.dataset.key;
      if (k.length === 1 && /[a-z]/i.test(k)) {
        state.prevChar = k.toLowerCase();
      } else if (k === "space" || k === "return") {
        state.prevChar = null;
      }
      clearOneShots();
    }
  }

  function highlightLabel(el) {
    if (!el || !el.dataset.key) return;
    const shift = state.oneShotMods.has('shift') || state.lockedMods.has('shift');
    const alt = state.oneShotMods.has('alt') || state.lockedMods.has('alt');
    if (shift && el.dataset.shift) el.textContent = el.dataset.shift;
    else if (alt && el.dataset.alt) el.textContent = el.dataset.alt;
  }

  function onTouchStart(e) {
    // Ignore touches that initiate a drag — pointer.js handles those before
    // we ever fire a key. But for short taps, we react on touchstart so
    // typing feels instant.
    for (const t of e.changedTouches) {
      const el = resolveKey(t);
      if (!el) continue;
      el.classList.add('active');
      state.pressed.set(t.identifier, { el, x0: t.clientX, y0: t.clientY });

      // Start a repeat timer for typeable keys
      if (el.dataset.key && !el.dataset.mod && !el.dataset.layerSwitch) {
        const repeatTimer = setTimeout(function rep() {
          send({ t: "key", key: el.dataset.key, mods: activeMods(), repeat: true });
          state.pressed.get(t.identifier).repeatTimer = setTimeout(rep, KEY_REPEAT_RATE);
        }, KEY_REPEAT_DELAY);
        state.pressed.get(t.identifier).repeatTimer = repeatTimer;
      }
    }
  }

  function onTouchEnd(e) {
    for (const t of e.changedTouches) {
      const rec = state.pressed.get(t.identifier);
      if (!rec) continue;
      if (rec.repeatTimer) clearTimeout(rec.repeatTimer);
      rec.el.classList.remove('active');
      const drift = Math.hypot(t.clientX - rec.x0, t.clientY - rec.y0);
      if (drift < 16) emitKey(rec.el);
      state.pressed.delete(t.identifier);
    }
  }

  function onTouchCancel(e) {
    for (const t of e.changedTouches) {
      const rec = state.pressed.get(t.identifier);
      if (!rec) continue;
      if (rec.repeatTimer) clearTimeout(rec.repeatTimer);
      rec.el.classList.remove('active');
      state.pressed.delete(t.identifier);
    }
  }

  document.querySelectorAll('.keyboard').forEach((kb) => {
    kb.addEventListener('touchstart', onTouchStart, { passive: true });
    kb.addEventListener('touchend', onTouchEnd, { passive: true });
    kb.addEventListener('touchcancel', onTouchCancel, { passive: true });
  });

  // Re-render labels on every modifier change
  const origRefresh = refreshModUI;
  refreshModUI = function () {
    origRefresh();
    document.querySelectorAll('.layer.active .key[data-key]').forEach((k) => {
      const baseLabel = k.dataset.key;
      const friendly = { backspace: "⌫", delete: "⌦", space: "␣", return: "↵", escape: "⎋", tab: "⇥" };
      let label = friendly[baseLabel] || baseLabel;
      const shift = state.oneShotMods.has('shift') || state.lockedMods.has('shift');
      const alt = state.oneShotMods.has('alt') || state.lockedMods.has('alt');
      if (shift && k.dataset.shift) label = k.dataset.shift;
      else if (alt && k.dataset.alt) label = k.dataset.alt;
      k.textContent = label;
    });
  };

  window.CloudPadKeyboard = { switchLayer };
})();
