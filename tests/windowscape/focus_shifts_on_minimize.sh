#!/usr/bin/env bash
# When the focused window is minimized via windowScapeMinimize, focus shifts
# to a sibling non-minimized window. Covers both the focusHistory path and
# the orderedWindows fallback when history doesn't yield a candidate.
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
seed_windows "$APP" 2

# Grab the two window ids.
ids="$(hsx "local ws=hs.application.get('$APP'):allWindows(); return ws[1]:id() .. ',' .. ws[2]:id()")"
id1="${ids%%,*}"
id2="${ids##*,}"

# Focus window 1 and confirm it's the focused window.
hsx "hs.window.get($id1):focus(); return 'ok'" >/dev/null
wait_until "[ \"\$(hsx \"return hs.window.focusedWindow():id() == $id1 and 'yes' or 'no'\")\" = \"yes\" ]" 3 "window1 focused"

# Clear focusHistory so the fallback path is exercised: only window1 in history.
hsx "
  local core = require('WindowScape.core')
  core.focusHistory = { $id1 }
  return 'ok'
" >/dev/null

hsx "windowScapeMinimize(); return 'ok'" >/dev/null

# Snapshot for window1 created.
wait_until "[ \"\$(hsx \"return require('WindowScape.snapshots').getState().windows[$id1] and 'yes' or 'no'\")\" = \"yes\" ]" 5 "snapshot for window1"

# Focus should land on window2.
wait_until "[ \"\$(hsx \"local fw = hs.window.focusedWindow(); return fw and fw:id() == $id2 and 'yes' or 'no'\")\" = \"yes\" ]" 3 "focus shifts to window2"

echo "PASS: focus_shifts_on_minimize"
