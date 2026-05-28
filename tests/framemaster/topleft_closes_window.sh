#!/usr/bin/env bash
# FrameMaster: clicking the top-left hot corner (0,0) closes the focused
# window via cmd+W (and quits the app if no windows remain).
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

APP="com.apple.TextEdit"

teardown() {
  steve quit "$APP" >/dev/null 2>&1 || true
  global_teardown
}
trap teardown EXIT

# 1. Launch TextEdit and seed exactly one window.
launch_app "$APP"
seed_single_window_app "$APP"

# 2. Sanity check.
expect_eq "$(window_count "$APP")" "1" "TextEdit window count before hot-corner trigger"

# 3. Warp the mouse to (0,0) so FrameMaster sees the top-left corner.
hsx "hs.mouse.absolutePosition({x=0, y=0}); return 'ok'" >/dev/null
sleep 0.05

# 4. Synthesize a left click at the current mouse position. FrameMaster's
#    cornerClick eventtap intercepts and runs the topLeft action (cmd+W).
hsx "local p=hs.mouse.absolutePosition(); hs.eventtap.leftClick(p); return 'ok'" >/dev/null

# 5. The window should be gone within a few seconds.
wait_window_count "$APP" 0 5

echo "PASS: framemaster_topleft_closes_window"
