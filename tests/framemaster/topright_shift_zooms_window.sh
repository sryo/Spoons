#!/usr/bin/env bash
# FrameMaster: shift+click at the top-right hot corner toggles window zoom
# (window:toggleZoom()), changing the window frame.
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

APP="com.apple.TextEdit"

teardown() {
  steve quit "$APP" >/dev/null 2>&1 || true
  global_teardown
}
trap teardown EXIT

# 1. Clean WindowScape state, launch TextEdit, seed one window.
windowscape_reset
launch_app "$APP"
seed_single_window_app "$APP"

# 2. Capture window id and screen frame.
winId=$(hsx "return hs.application.get('$APP'):mainWindow():id()")
frame=$(hsx "local f=hs.screen.mainScreen():frame(); return string.format('%d,%d,%d,%d', f.x, f.y, f.w, f.h)")
IFS=',' read -r sx sy sw sh <<< "$frame"

# 3. Let the window settle, then capture its initial frame.
sleep 0.3
init_frame=$(hsx "local f=hs.window.get($winId):frame(); return string.format('%d,%d,%d,%d', math.floor(f.x), math.floor(f.y), math.floor(f.w), math.floor(f.h))")

# 4. Shift+click at top-right corner (sw-1, 0). FrameMaster runs toggleZoom.
click_with_modifier shift "$((sx + sw - 1))" "$((sy + 1))"

# 5. Wait for the frame to change.
wait_until "
  cur=\$(hsx \"local f=hs.window.get($winId):frame(); return string.format('%d,%d,%d,%d', math.floor(f.x), math.floor(f.y), math.floor(f.w), math.floor(f.h))\")
  [ \"\$cur\" != \"$init_frame\" ]
" 3 "window frame changed after shift+click"

echo "PASS: framemaster_topright_shift_zooms_window"
