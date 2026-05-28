#!/usr/bin/env bash
# FrameMaster: clicking the bottom-right hot corner (no modifier) minimizes
# the focused window via WindowScape (or native window:minimize()).
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

APP="com.apple.TextEdit"
winId=""

teardown() {
  if [ -n "$winId" ]; then
    hsx "local w=hs.window.get($winId); if w and w:isMinimized() then w:unminimize() end; return 'ok'" >/dev/null 2>&1 || true
  fi
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

# 3. Sanity check: window starts not minimized.
expect_eq "$(hsx "return hs.window.get($winId):isMinimized() and 'yes' or 'no'")" "no" "window not minimized initially"

# 4. Warp to bottom-right corner (sw-1, sh-1) and click. FrameMaster intercepts
#    and runs the bottomRight action (minimize).
hsx "hs.mouse.absolutePosition({x=$((sx + sw - 1)), y=$((sy + sh - 1))}); return 'ok'" >/dev/null
sleep 0.05
hsx "local p=hs.mouse.absolutePosition(); hs.eventtap.leftClick(p); return 'ok'" >/dev/null

# 5. Window should be minimized within a few seconds.
wait_until "[ \"\$(hsx \"local w=hs.window.get($winId); return (w and w:isMinimized()) and 'yes' or 'no'\")\" = \"yes\" ]" 3 "window minimized"

# 6. App is still running (minimize, not quit).
expect_eq "$(hsx "return hs.application.get('$APP') and 'yes' or 'no'")" "yes" "TextEdit still running"

echo "PASS: framemaster_bottomright_minimizes_window"
