#!/usr/bin/env bash
# EdgeHopper: holding shift bypasses the wrap. The same strong push that
# would wrap normally must leave the cursor near its original position.
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

teardown() {
  # Defensive: ensure shift is released even if the test crashed mid-modifier.
  hsx "hs.eventtap.event.newKeyEvent('shift', false):post(); return 'r'" >/dev/null 2>&1 || true
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

# 3. Press shift down.
hsx "hs.eventtap.event.newKeyEvent('shift', true):post(); return 'down'" >/dev/null
sleep 0.05

# 4. Synthesise the strong leftward push while shift is held.
hsx "
  local e = hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.mouseMoved, {x=$start_x, y=$start_y})
  e:setProperty(hs.eventtap.event.properties.mouseEventDeltaX, -350)
  e:setProperty(hs.eventtap.event.properties.mouseEventDeltaY, 0)
  e:post()
  return 'posted'
" >/dev/null
sleep 0.1

# 5. Release shift.
hsx "hs.eventtap.event.newKeyEvent('shift', false):post(); return 'up'" >/dev/null

# 6. Cursor should still be near the original start_x (no wrap).
end_x=$(hsx "return math.floor(hs.mouse.absolutePosition().x)")
if [ "$end_x" -gt "$((start_x + 50))" ]; then
  echo "FAIL: cursor wrapped despite shift held. end_x=$end_x, expected near $start_x" >&2
  exit 1
fi

echo "PASS: edgehopper_shift_held_blocks_wrap"
