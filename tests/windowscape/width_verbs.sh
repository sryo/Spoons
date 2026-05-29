#!/usr/bin/env bash
# WindowScape: operations.grow / shrink step by cfg.widthStep with min/max clamp;
# cycleWidth resets the focused window's weight to cfg.widthDefault without
# touching siblings (Ctrl+Cmd+0 already clears the whole table).
# Direct-state test: call operations API, no key synthesis.
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

APP="com.apple.TextEdit"

teardown() {
  steve quit "$APP" >/dev/null 2>&1 || true
  global_teardown
}
trap teardown EXIT

windowscape_reset
launch_app "$APP"
seed_single_window_app "$APP"

winId="$(hsx "return hs.application.get('$APP'):mainWindow():id()")"

# Start from a known weight of 1.0.
hsx "require('WindowScape.core').windowWeights = {}; return 'ok'" >/dev/null

step="$(hsx "return string.format('%.2f', require('WindowScape.config').cfg.widthStep)")"
expect_eq "$step" "0.25" "cfg.widthStep default is 0.25"

# grow x2 = 1.0 + 0.25 + 0.25 = 1.50
hsx "local o=require('WindowScape.operations'); o.grow(); o.grow(); return 'ok'" >/dev/null
expect_eq "$(hsx "return string.format('%.2f', require('WindowScape.tiler').getWindowWeight(hs.window.get($winId)))")" "1.50" "weight = 1.50 after 2 grows"

# shrink x1 = 1.50 - 0.25 = 1.25
hsx "require('WindowScape.operations').shrink(); return 'ok'" >/dev/null
expect_eq "$(hsx "return string.format('%.2f', require('WindowScape.tiler').getWindowWeight(hs.window.get($winId)))")" "1.25" "weight = 1.25 after shrink"

# cycleWidth resets to widthDefault (1.0).
hsx "require('WindowScape.operations').cycleWidth(); return 'ok'" >/dev/null
expect_eq "$(hsx "return string.format('%.2f', require('WindowScape.tiler').getWindowWeight(hs.window.get($winId)))")" "1.00" "weight reset to 1.00 after cycleWidth"

# Hammer shrink past widthMin; should clamp at 0.25, not crash through tiler's 0.1 floor.
hsx "local o=require('WindowScape.operations'); for _=1,30 do o.shrink() end; return 'ok'" >/dev/null
expect_eq "$(hsx "return string.format('%.2f', require('WindowScape.tiler').getWindowWeight(hs.window.get($winId)))")" "0.25" "weight clamped at widthMin=0.25"

# Hammer grow past widthMax; should clamp at 8.0.
hsx "local o=require('WindowScape.operations'); for _=1,100 do o.grow() end; return 'ok'" >/dev/null
expect_eq "$(hsx "return string.format('%.2f', require('WindowScape.tiler').getWindowWeight(hs.window.get($winId)))")" "8.00" "weight clamped at widthMax=8.00"

echo "PASS: windowscape_width_verbs"
