#!/usr/bin/env bash
# EdgeHopper: inside a screen corner (within 10 px of both edges) the wrap
# is suppressed so hot-corner actions remain reachable. A strong leftward
# push at the top-left must not move the cursor.
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

teardown() {
  global_teardown
}
trap teardown EXIT

# 1. Capture main screen frame.
frame=$(hsx "local f=hs.screen.mainScreen():frame(); return string.format('%d,%d,%d,%d', f.x, f.y, f.w, f.h)")
IFS=',' read -r sx sy sw sh <<< "$frame"

# 2. Position cursor at the top-left corner, within 10 px of both edges.
corner_x=$((sx + 5))
corner_y=$((sy + 5))
hsx "hs.mouse.absolutePosition({x=$corner_x, y=$corner_y}); return 'ok'" >/dev/null
sleep 0.05

# 3. Synthesise a strong leftward push from the corner.
hsx "
  local e = hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.mouseMoved, {x=$corner_x, y=$corner_y})
  e:setProperty(hs.eventtap.event.properties.mouseEventDeltaX, -350)
  e:setProperty(hs.eventtap.event.properties.mouseEventDeltaY, 0)
  e:post()
  return 'posted'
" >/dev/null
sleep 0.1

# 4. Cursor should remain near the corner (no wrap).
end_x=$(hsx "return math.floor(hs.mouse.absolutePosition().x)")
end_y=$(hsx "return math.floor(hs.mouse.absolutePosition().y)")
if [ "$end_x" -gt "$((corner_x + 50))" ] || [ "$end_y" -gt "$((corner_y + 50))" ]; then
  echo "FAIL: cursor moved unexpectedly from corner. end=($end_x,$end_y), expected near ($corner_x,$corner_y)" >&2
  exit 1
fi

echo "PASS: edgehopper_corner_avoidance_blocks_wrap"
