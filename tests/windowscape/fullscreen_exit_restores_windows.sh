#!/usr/bin/env bash
# WindowScape: fullscreen.exit() clears state.active/window, restores hidden
# windows back to the tile grid, and restores their saved weights.
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

APP="com.apple.TextEdit"

teardown() {
  steve quit "$APP" >/dev/null 2>&1 || true
  global_teardown
}
trap teardown EXIT

# 1. Reset state, launch app, open two windows.
windowscape_reset
launch_app "$APP"
seed_windows "$APP" 2

# 2. Capture window ids in :allWindows() order.
ids="$(hsx "local ws=hs.application.get('$APP'):allWindows(); return ws[1]:id() .. ',' .. ws[2]:id()")"
id1="${ids%%,*}"
id2="${ids##*,}"

# 3. Set window2's weight to 1.4.
hsx "local t=require('WindowScape.tiler'); t.setWindowWeight(hs.window.get($id2), 1.4); return 'ok'" >/dev/null

# 4. Focus window1 and enter fullscreen.
hsx "hs.window.get($id1):focus(); return 'ok'" >/dev/null
sleep 0.15
hsx "require('WindowScape.fullscreen').enter(hs.window.get($id1)); return 'ok'" >/dev/null

# 5. Wait until fullscreen is active before exiting.
wait_until "[ \"\$(hsx \"return require('WindowScape.fullscreen').getState().active and 'yes' or 'no'\")\" = \"yes\" ]" 3 "fullscreen active before exit"

# 6. Exit fullscreen.
hsx "require('WindowScape.fullscreen').exit(); return 'ok'" >/dev/null

# 7. Assertions.
wait_until "[ \"\$(hsx \"return require('WindowScape.fullscreen').getState().active and 'yes' or 'no'\")\" = \"no\" ]" 3 "fullscreen inactive"

expect_eq "$(hsx "return require('WindowScape.fullscreen').getState().window and 'set' or 'nil'")" "nil" "fullscreen.window cleared"
expect_eq "$(hsx "return #require('WindowScape.fullscreen').getState().hiddenWindows")" "0" "no hidden windows after exit"
expect_eq "$(hsx "return tostring(require('WindowScape.core').windowWeights[$id2])")" "1.4" "window2 weight restored"

# 8. Window2 should be back on the main screen (x within main screen bounds).
expect_eq "$(hsx "local f=hs.window.get($id2):frame(); local s=hs.screen.mainScreen():frame(); return (f.x >= s.x and f.x < s.x + s.w) and 'on' or 'off'")" "on" "window2 back on screen"

echo "PASS: fullscreen_exit_restores_windows"
