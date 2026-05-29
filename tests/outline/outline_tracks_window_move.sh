#!/usr/bin/env bash
# Moving the focused window updates the outline canvas to match the new frame.
# Covers both the event-driven path (windowMoved → outline.draw) and the
# polling path that follows.
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
wait_until "[ \"\$(hsx \"local i=dofile('$PEEK'); return tostring(i.showing())\")\" = \"true\" ]" 3 "outline visible"

# Move the window by a known delta.
hsx "
  local w = hs.window.get($winId)
  local f = w:frame()
  w:setTopLeft({x = f.x + 80, y = f.y + 60})
  return 'ok'
" >/dev/null

# Wait up to 500 ms for the outline canvas to catch up. Outline is fully
# inset: canvas frame equals window frame.
wait_until "[ \"\$(hsx \"
  local i = dofile('$PEEK')
  local of = i.frame()
  local wf = hs.window.get($winId):frame()
  if not of or not wf then return 'no' end
  local d = math.max(math.abs(of.x-wf.x), math.abs(of.y-wf.y), math.abs(of.w-wf.w), math.abs(of.h-wf.h))
  return d <= 1 and 'yes' or 'no'
\")\" = \"yes\" ]" 1 "outline catches new frame within 500ms" 0.05

echo "PASS: outline_tracks_window_move"
