#!/usr/bin/env bash
# WindowScape: tiler.setWindowWeight(win, w) updates core.windowWeights for
# the focused window and clamps the stored value to >= 0.1.
# Direct-state test: mutate state via the tiler API, no key synthesis.
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

APP="com.apple.TextEdit"

teardown() {
  steve quit "$APP" >/dev/null 2>&1 || true
  global_teardown
}
trap teardown EXIT

# 1. Clean slate + single window.
windowscape_reset
launch_app "$APP"
seed_single_window_app "$APP"

winId="$(hsx "return hs.application.get('$APP'):mainWindow():id()")"

# 2. Ensure weights table starts empty so the default 1.0 path is exercised.
hsx "require('WindowScape.core').windowWeights = {}; return 'ok'" >/dev/null

# 3. Increase weight by 0.3 from the default 1.0 -> 1.3.
result1="$(hsx "local t=require('WindowScape.tiler'); local w=hs.window.get($winId); t.setWindowWeight(w, t.getWindowWeight(w) + 0.3); return string.format('%.1f', t.getWindowWeight(w))")"
expect_eq "$result1" "1.3" "weight = 1.3 after +0.3"
expect_eq "$(hsx "return string.format('%.1f', require('WindowScape.core').windowWeights[$winId])")" "1.3" "windowWeights table reflects 1.3"

# 4. Decrease by 2.0; should clamp to 0.1 (not -0.7).
result2="$(hsx "local t=require('WindowScape.tiler'); local w=hs.window.get($winId); t.setWindowWeight(w, t.getWindowWeight(w) - 2.0); return string.format('%.1f', t.getWindowWeight(w))")"
expect_eq "$result2" "0.1" "weight clamped to 0.1"
expect_eq "$(hsx "return string.format('%.1f', require('WindowScape.core').windowWeights[$winId])")" "0.1" "windowWeights table reflects 0.1"

echo "PASS: windowscape_weight_increase_decrease"
