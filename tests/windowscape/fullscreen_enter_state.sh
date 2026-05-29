#!/usr/bin/env bash
# WindowScape: fullscreen.enter(win) flips state.active, stashes other windows
# as hiddenWindows, and saves their weights into savedWeights.
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

APP="com.apple.TextEdit"

teardown() {
  steve quit "$APP" >/dev/null 2>&1 || true
  global_teardown
}
trap teardown EXIT

# 1. Reset state, launch app, open two windows and capture ids.
windowscape_reset
launch_app "$APP"
ids="$(seed_two_window_ids "$APP")"
id1="${ids%%,*}"
id2="${ids##*,}"

# 3. Set window2's weight to 1.4 so we can verify savedWeights captures it.
hsx "local t=require('WindowScape.tiler'); t.setWindowWeight(hs.window.get($id2), 1.4); return 'ok'" >/dev/null

# 4. Focus window1 so it is the one going fullscreen.
hsx "hs.window.get($id1):focus(); return 'ok'" >/dev/null
sleep 0.15

# 5. Enter fullscreen on window1.
hsx "require('WindowScape.fullscreen').enter(hs.window.get($id1)); return 'ok'" >/dev/null

# 6. Assertions.
wait_until "[ \"\$(hsx \"return require('WindowScape.fullscreen').getState().active and 'yes' or 'no'\")\" = \"yes\" ]" 3 "fullscreen active"

expect_eq "$(hsx "return require('WindowScape.fullscreen').getState().window:id()")" "$id1" "fullscreen window is window1"
expect_eq "$(hsx "return #require('WindowScape.fullscreen').getState().hiddenWindows")" "1" "one window hidden"
expect_eq "$(hsx "return tostring(require('WindowScape.fullscreen').getState().savedWeights[$id2])")" "1.4" "saved weight for window2"

echo "PASS: fullscreen_enter_state"
