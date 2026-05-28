#!/usr/bin/env bash
# EdgeHopper: a single mouseMoved event with a large negative deltaX at the
# left edge wraps the cursor to the right side of the screen.
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

teardown() {
  global_teardown
}
trap teardown EXIT

# 1. Capture main screen frame.
frame=$(hsx "local f=hs.screen.mainScreen():frame(); return string.format('%d,%d,%d,%d', f.x, f.y, f.w, f.h)")
IFS=',' read -r sx sy sw sh <<< "$frame"

# 2. Position cursor at the left edge, vertically centered.
start_x=$((sx + 2))
start_y=$((sy + sh / 2))
hsx "hs.mouse.absolutePosition({x=$start_x, y=$start_y}); return 'ok'" >/dev/null
sleep 0.05

# 3. Synthesise a single strong leftward push (deltaX = -350, beyond the 300 px threshold).
hsx "
  local e = hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.mouseMoved, {x=$start_x, y=$start_y})
  e:setProperty(hs.eventtap.event.properties.mouseEventDeltaX, -350)
  e:setProperty(hs.eventtap.event.properties.mouseEventDeltaY, 0)
  e:post()
  return 'posted'
" >/dev/null
sleep 0.1

# 4. Cursor should now be near the right edge (within WRAP_OFFSET, i.e. ~25 px in).
end_x=$(hsx "return math.floor(hs.mouse.absolutePosition().x)")
threshold=$((sx + sw - 50))
if [ "$end_x" -lt "$threshold" ]; then
  echo "FAIL: cursor did not wrap to right edge. end_x=$end_x, expected > $threshold" >&2
  exit 1
fi

echo "PASS: edgehopper_single_strong_push_wraps"
