#!/usr/bin/env bash
# TextEdit's standard document window has no toolbar (no AXToolbar child),
# so getCornerRadius returns 16. Applied via outline.draw.
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

wait_until "[ \"\$(hsx \"local i=dofile('$PEEK'); return tostring(i.showing())\")\" = \"true\" ]" 3 "outline visible"

expect_eq "$(hsx "local i=dofile('$PEEK'); return tostring(i.appliedCornerRadius())")" "16" "TextEdit window radius = 16"
expect_eq "$(hsx "local i=dofile('$PEEK'); return tostring(i.radius())")" "16" "canvas element xRadius = 16"

echo "PASS: outline_corner_radius_for_no_toolbar"
