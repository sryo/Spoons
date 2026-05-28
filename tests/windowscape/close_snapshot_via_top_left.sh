#!/usr/bin/env bash
# WindowScape: clicking the top-left 20x20 region of a snapshot canvas
# closes the window AND removes the snapshot entry from the state.
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

APP="com.apple.TextEdit"

teardown() {
  steve quit "$APP" >/dev/null 2>&1 || true
  global_teardown
}
trap teardown EXIT

# 1. Clean slate + one focused window.
windowscape_reset
launch_app "$APP"
seed_single_window_app "$APP"

hsx "hs.application.get('$APP'):mainWindow():focus(); return 'ok'" >/dev/null
wait_until "[ \"\$(hsx \"local w=hs.window.focusedWindow(); return w and w:application():bundleID() == '$APP' and 'yes' or 'no'\")\" = \"yes\" ]" 3 "TextEdit window focused"

winId="$(hsx "return hs.window.focusedWindow():id()")"

# 2. Minimize via the global helper.
hsx "windowScapeMinimize(); return 'ok'" >/dev/null

# 3. Wait for snapshot to be fully created.
wait_until "[ \"\$(hsx \"return require('WindowScape.snapshots').getState().windows[$winId] and 'yes' or 'no'\")\" = \"yes\" ]" 5 "snapshot present"
wait_until "[ \"\$(hsx \"return require('WindowScape.snapshots').getState().isCreating and 'yes' or 'no'\")\" = \"no\" ]" 5 "snapshot creation completed"

# 4. Read the canvas frame as a CSV "x,y,w,h".
frame="$(hsx "local f=require('WindowScape.snapshots').getState().windows[$winId].canvas:frame(); return string.format('%d,%d,%d,%d', f.x, f.y, f.w, f.h)")"
IFS=',' read -r cx cy cw ch <<< "$frame"

if [ -z "${cx:-}" ] || [ -z "${cy:-}" ]; then
  echo "failed to parse canvas frame: '$frame'" >&2
  exit 1
fi

# 5. Click 4 px inside the top-left corner (within the 20x20 close hit-area).
target_x=$((cx + 4))
target_y=$((cy + 4))
hsx "hs.mouse.absolutePosition({x=$target_x, y=$target_y}); return 'ok'" >/dev/null
sleep 0.05
hsx "hs.eventtap.leftClick({x=$target_x, y=$target_y}); return 'ok'" >/dev/null

# 6. The snapshot entry should be removed and the order array drained.
wait_until "[ \"\$(hsx \"return require('WindowScape.snapshots').getState().windows[$winId] and 'present' or 'gone'\")\" = \"gone\" ]" 3 "snapshot entry removed"
wait_until "[ \"\$(hsx \"return tostring(#require('WindowScape.snapshots').getState().order)\")\" = \"0\" ]" 3 "snapshot order empty"

echo "PASS: windowscape_close_snapshot_via_top_left"
