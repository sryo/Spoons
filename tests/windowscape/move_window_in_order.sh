#!/usr/bin/env bash
# WindowScape: operations.moveWindowInOrder('forward') swaps the focused
# window's position in core.windowOrderBySpace without changing focus.
# Reverse with 'backward' restores the original order.
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

APP="com.apple.TextEdit"

teardown() {
  steve quit "$APP" >/dev/null 2>&1 || true
  global_teardown
}
trap teardown EXIT

# 1. Clean slate + two windows.
windowscape_reset
launch_app "$APP"
seed_windows "$APP" 2

# 2. Refresh per-space order, capture ids and the current space.
hsx "require('WindowScape.core').updateWindowOrder(); return 'ok'" >/dev/null
space="$(hsx "return require('WindowScape.core').getCurrentSpace()")"
ids="$(hsx "local s=require('WindowScape.core').getCurrentSpace(); local o=require('WindowScape.core').windowOrderBySpace[s]; return o[1] .. ',' .. o[2]")"
id1="${ids%,*}"
id2="${ids#*,}"

# 3. Focus window1 so it is the one we move.
hsx "hs.window.get($id1):focus(); return 'ok'" >/dev/null
wait_until "[ \"\$(hsx \"return hs.window.focusedWindow():id()\")\" = \"$id1\" ]" 3 "starting focus is window1"

# 4. Forward: window1 should swap into slot 2, window2 takes slot 1.
hsx "require('WindowScape.operations').moveWindowInOrder('forward'); return 'ok'" >/dev/null
wait_until "[ \"\$(hsx \"return require('WindowScape.core').windowOrderBySpace[$space][1]\")\" = \"$id2\" ]" 3 "order[1] is now window2"
expect_eq "$(hsx "return hs.window.focusedWindow():id()")" "$id1" "focused window unchanged (still window1)"

# 5. Backward: order restored.
hsx "require('WindowScape.operations').moveWindowInOrder('backward'); return 'ok'" >/dev/null
wait_until "[ \"\$(hsx \"return require('WindowScape.core').windowOrderBySpace[$space][1]\")\" = \"$id1\" ]" 3 "order restored"

echo "PASS: windowscape_move_window_in_order"
