#!/usr/bin/env bash
# WindowScape: closing a window prunes its winId from core.windowWeights and
# core.windowLastScreen via tiler.pruneStaleWeights, which fires on the
# windowDestroyed filter.
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

APP="com.apple.TextEdit"

teardown() {
  steve quit "$APP" >/dev/null 2>&1 || true
  global_teardown
}
trap teardown EXIT

# 1. Clean slate + one window.
windowscape_reset
launch_app "$APP"
seed_single_window_app "$APP"

winId="$(hsx "return hs.application.get('$APP'):mainWindow():id()")"

# 2. Plant a non-default weight + a windowLastScreen entry for this winId.
hsx "
  local t = require('WindowScape.tiler')
  local c = require('WindowScape.core')
  local w = hs.window.get($winId)
  t.setWindowWeight(w, 1.7)
  local scr = w:screen()
  if scr then c.windowLastScreen[$winId] = scr:id() end
  return 'ok'
" >/dev/null

expect_eq "$(hsx "return tostring(require('WindowScape.core').windowWeights[$winId])")" "1.7" "weight set before close"
expect_eq "$(hsx "return require('WindowScape.core').windowLastScreen[$winId] and 'present' or 'absent'")" "present" "windowLastScreen set before close"

# 3. Close the window.
hsx "hs.window.get($winId):close(); return 'ok'" >/dev/null
wait_window_count "$APP" 0 5

# 4. Both maps should drop the entry once pruneStaleWeights runs.
wait_until "[ \"\$(hsx \"return require('WindowScape.core').windowWeights[$winId] and 'present' or 'absent'\")\" = \"absent\" ]" 5 "weight pruned"
wait_until "[ \"\$(hsx \"return require('WindowScape.core').windowLastScreen[$winId] and 'present' or 'absent'\")\" = \"absent\" ]" 5 "windowLastScreen pruned"

echo "PASS: windowscape_window_destroyed_prunes_weights"
