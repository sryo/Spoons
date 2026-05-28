#!/usr/bin/env bash
# WindowScape: operations.focusAdjacentWindow('forward') focuses the next
# window in the space's order and pushes its id to core.focusHistory[1]
# after the 0.05 s focus debounce. Reverse with 'backward'.
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

# 2. Refresh the per-space order so we know the canonical sequence.
hsx "require('WindowScape.core').updateWindowOrder(); return 'ok'" >/dev/null

# 3. Capture the first two ids in the order WindowScape tracks them.
ids="$(hsx "local s=require('WindowScape.core').getCurrentSpace(); local o=require('WindowScape.core').windowOrderBySpace[s]; return o[1] .. ',' .. o[2]")"
id1="${ids%,*}"
id2="${ids#*,}"

# 4. Focus window1 as our starting point.
hsx "hs.window.get($id1):focus(); return 'ok'" >/dev/null
wait_until "[ \"\$(hsx \"return hs.window.focusedWindow():id()\")\" = \"$id1\" ]" 3 "starting focus is window1"

# 5. Forward: window1 -> window2.
hsx "require('WindowScape.operations').focusAdjacentWindow('forward'); return 'ok'" >/dev/null
wait_until "[ \"\$(hsx \"return hs.window.focusedWindow():id()\")\" = \"$id2\" ]" 3 "focused window is window2"
wait_until "[ \"\$(hsx \"return require('WindowScape.core').focusHistory[1]\")\" = \"$id2\" ]" 2 "focusHistory[1] = window2" 0.1

# 6. Backward: window2 -> window1.
hsx "require('WindowScape.operations').focusAdjacentWindow('backward'); return 'ok'" >/dev/null
wait_until "[ \"\$(hsx \"return hs.window.focusedWindow():id()\")\" = \"$id1\" ]" 3 "back to window1"
wait_until "[ \"\$(hsx \"return require('WindowScape.core').focusHistory[1]\")\" = \"$id1\" ]" 2 "focusHistory[1] = window1"

echo "PASS: windowscape_focus_adjacent_updates_history"
