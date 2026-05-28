#!/usr/bin/env bash
# WindowScape: operations.moveWindowToAdjacentScreen('next') moves the
# focused window to the next screen and the window appears in the
# destination space's windowOrderBySpace entry.
# Skipped if fewer than 2 screens are attached.
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

# 0. Skip if not a multi-screen setup. Done BEFORE any setup so we don't
#    leave state behind on single-screen machines.
screens="$(hsx "return #hs.screen.allScreens()")"
if [ -z "${screens:-}" ] || [ "$screens" -lt 2 ]; then
  echo "SKIP: requires 2+ screens (found ${screens:-0})"
  exit 0
fi

APP="com.apple.TextEdit"

teardown() {
  # Try to move the window back to the original screen before quitting.
  if [ -n "${winId:-}" ]; then
    hsx "local w=hs.window.get($winId); if w then w:focus(); require('WindowScape.operations').moveWindowToAdjacentScreen('previous') end; return 'ok'" >/dev/null 2>&1 || true
  fi
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
screenAId="$(hsx "return hs.window.get($winId):screen():id()")"

if [ -z "${winId:-}" ] || [ -z "${screenAId:-}" ]; then
  echo "failed to capture winId/screenAId" >&2
  exit 1
fi

# 2. Action: ask WindowScape to move the focused window to the next screen.
hsx "hs.window.get($winId):focus(); require('WindowScape.operations').moveWindowToAdjacentScreen('next'); return 'ok'" >/dev/null

# 3. The window should now report a different screen id.
wait_until "[ \"\$(hsx \"local w=hs.window.get($winId); return w and (w:screen():id() ~= $screenAId) and 'moved' or 'same'\")\" = \"moved\" ]" 3 "window moved to a different screen"

# 4. The window should appear in the destination space's order array.
on_list="$(hsx "local w = hs.window.get($winId); local scr = w:screen(); local newSpace = require('WindowScape.core').spaces.activeSpaceOnScreen(scr) or require('WindowScape.core').getCurrentSpace(); local order = require('WindowScape.core').windowOrderBySpace[newSpace] or {}; for _, id in ipairs(order) do if id == $winId then return 'in' end end; return 'out'")"
expect_eq "$on_list" "in" "winId is in destination space's order"

echo "PASS: windowscape_move_window_to_adjacent_screen"
