#!/usr/bin/env bash
# outline.draw early-exits via isSnapshotted when the window is minimized
# through WindowScape's snapshot path.
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
wait_until "[ \"\$(hsx \"local i=dofile('$PEEK'); return tostring(i.showing())\")\" = \"true\" ]" 3 "outline visible pre-snapshot"

hsx "hs.window.get($winId):focus(); windowScapeMinimize(); return 'ok'" >/dev/null
wait_until "[ \"\$(hsx \"return require('WindowScape.snapshots').getState().windows[$winId] and 'yes' or 'no'\")\" = \"yes\" ]" 5 "snapshot created"

# Force the draw path to re-evaluate; the snapshot guard should hide the outline.
hsx "
  local w = hs.window.get($winId)
  if w then require('WindowScape.outline').draw(w) end
  return 'ok'
" >/dev/null

wait_until "[ \"\$(hsx \"local i=dofile('$PEEK'); return tostring(i.showing())\")\" = \"false\" ]" 3 "outline hides for snapshotted window"

echo "PASS: outline_hides_for_snapshotted_window"
