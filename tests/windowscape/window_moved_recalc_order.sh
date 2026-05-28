#!/usr/bin/env bash
# WindowScape: after a programmatic setFrame() plus events.handleWindowMoved,
# windowOrderBySpace[space][1] reflects the new spatial order (leftmost-first).
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

# 3. Move window2 into a leftmost-third frame and notify WindowScape.
#    Height must stay above cfg.collapsedWindowHeight (12) so the move
#    is treated as a real move, not a collapse.
hsx "
  local w = hs.window.get($id2)
  local f = hs.screen.mainScreen():frame()
  w:setFrame({x = f.x + 10, y = f.y + 50, w = math.floor(f.w / 3), h = math.floor(f.h / 2)})
  require('WindowScape.events').handleWindowMoved(w)
  return 'ok'
" >/dev/null

# 4. Sanity: window2 is not collapsed.
expect_eq "$(hsx "return hs.window.get($id2):frame().h > 12 and 'yes' or 'no'")" "yes" "window2 not collapsed"

# 5. window2 should be promoted to order[1]; total length stays at 2.
wait_until "[ \"\$(hsx \"return require('WindowScape.core').windowOrderBySpace[$space][1]\")\" = \"$id2\" ]" 3 "window2 promoted to order[1]"
wait_until "[ \"\$(hsx \"return #require('WindowScape.core').windowOrderBySpace[$space]\")\" = \"2\" ]" 3 "order length still 2"

# Silence the unused warning for id1 in shells that flag it.
: "$id1"

echo "PASS: windowscape_window_moved_recalc_order"
