#!/usr/bin/env bash
# outline.draw on a focused standard window creates a visible canvas whose
# frame matches the window's frame within a couple of pixels.
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

hsx "
  local w = hs.window.get($winId)
  require('WindowScape.outline').draw(w)
  return 'ok'
" >/dev/null

wait_until "[ \"\$(hsx \"local i=dofile('$PEEK'); return tostring(i.showing())\")\" = \"true\" ]" 3 "outline canvas showing"

# The outline is fully inset within the window: the canvas frame matches the
# window frame exactly. Allow 1 px for rounding.
diff="$(hsx "
  local i  = dofile('$PEEK')
  local of = i.frame()
  local wf = hs.window.get($winId):frame()
  if not of or not wf then return 'no-frame' end
  local d = math.max(math.abs(of.x-wf.x), math.abs(of.y-wf.y), math.abs(of.w-wf.w), math.abs(of.h-wf.h))
  return tostring(math.floor(d))
")"

if [ "$diff" = "no-frame" ] || [ "$diff" -gt 1 ]; then
  echo "FAIL: outline canvas frame does not match window frame; diff=$diff px"
  exit 1
fi

expect_eq "$(hsx "local i=dofile('$PEEK'); return tostring(i.refreshTimerRunning())")" "true" "refresh timer running"

echo "PASS: outline_draws_for_focused_window"
