#!/usr/bin/env bash
# After IDLE_TICKS of stillness the refresh timer drops from the FAST interval
# to the SLOW interval. A frame change brings it back to FAST.
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"
source "$(dirname "$0")/_textedit_window.sh"

PEEK="$(dirname "$0")/_introspect.lua"
APP="com.apple.TextEdit"

teardown() {
  steve quit "$APP" >/dev/null 2>&1 || true
  global_teardown
}
trap teardown EXIT

windowscape_reset
winId="$(setup_textedit_window "$APP")"

hsx "require('WindowScape.outline').draw(hs.window.get($winId)); return 'ok'" >/dev/null

wait_until "[ \"\$(hsx \"local i=dofile('$PEEK'); return tostring(i.refreshTimerRunning())\")\" = \"true\" ]" 3 "refresh timer running"

# Right after draw, interval should be FAST (0.033).
expect_eq "$(hsx "local i=dofile('$PEEK'); return string.format('%.3f', i.refreshInterval() or 0)")" "0.033" "starts on FAST interval"

# Leave the window alone long enough for IDLE_TICKS * FAST + slack.
sleep 0.8

expect_eq "$(hsx "local i=dofile('$PEEK'); return string.format('%.3f', i.refreshInterval() or 0)")" "0.200" "drops to SLOW interval after stillness"

# Nudge the window; the next tick should snap us back to FAST.
hsx "
  local w = hs.window.get($winId)
  local f = w:frame()
  w:setTopLeft({x = f.x + 30, y = f.y + 30})
  return 'ok'
" >/dev/null

# Worst-case lag is one SLOW tick (200 ms) + animation slack.
wait_until "[ \"\$(hsx \"local i=dofile('$PEEK'); return string.format('%.3f', i.refreshInterval() or 0)\")\" = \"0.033\" ]" 2 "returns to FAST on motion" 0.05

echo "PASS: outline_idle_backoff_slows_timer"
