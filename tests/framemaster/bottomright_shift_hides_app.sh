#!/usr/bin/env bash
# FrameMaster: shift+click at the bottom-right hot corner hides the focused
# application (app:hide()).
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

APP="com.apple.TextEdit"

teardown() {
  hsx "local a=hs.application.get('$APP'); if a then a:activate() end; return 'ok'" >/dev/null 2>&1 || true
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

# 3. Sanity check: app starts visible.
expect_eq "$(hsx "return hs.application.get('$APP'):isHidden() and 'yes' or 'no'")" "no" "app not hidden initially"

# 4. Shift+click at bottom-right corner (sw-1, sh-1). FrameMaster runs app:hide().
click_with_modifier shift "$((sx + sw - 1))" "$((sy + sh - 1))"

# 5. App should be hidden within a few seconds.
wait_until "[ \"\$(hsx \"return hs.application.get('$APP'):isHidden() and 'yes' or 'no'\")\" = \"yes\" ]" 3 "app hidden"

# 6. App is still running (hidden, not quit).
expect_eq "$(hsx "return hs.application.get('$APP') and 'yes' or 'no'")" "yes" "app still running"

echo "PASS: framemaster_bottomright_shift_hides_app"
