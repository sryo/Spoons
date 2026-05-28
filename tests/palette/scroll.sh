#!/usr/bin/env bash
# Palette: 2-finger / wheel scroll over the canvas moves state.focused, same
# end-effect as up/down arrows. Drives the real dismissTap eventtap via
# synthetic scroll events posted at the mouse cursor positioned over the card.

set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

teardown() {
  hsx "
    local P = package.loaded['Palette']
    if P and P.isOpen() then P.close() end
    return 'ok'
  " >/dev/null 2>&1 || true
  global_teardown
}
trap teardown EXIT

loaded="$(hsx "return package.loaded['Palette'] and 'yes' or 'no'")"
if [ "$loaded" != "yes" ]; then
  echo "Palette module not loaded in Hammerspoon" >&2
  exit 2
fi

# Open the palette and wait for the first draw to populate state.items
# and lastListLayout (needed for hit-testing later).
hsx "package.loaded['Palette'].open(); return 'ok'" >/dev/null
sleep 0.2

items="$(hsx "return tostring(#package.loaded['Palette']._state.items)")"
if [ "$items" -lt "5" ]; then
  echo "FAIL: need >=5 items to scroll (got $items)" >&2
  exit 1
fi

expect_eq "$(hsx "return tostring(package.loaded['Palette']._state.focused)")" "1" "initial focus is row 1"

# Move the cursor to the canvas center so the scroll-inside-frame test passes.
hsx "
  local f = require('Palette.canvas').frame()
  hs.mouse.absolutePosition({x = f.x + f.w/2, y = f.y + f.h/2})
  return 'ok'
" >/dev/null
sleep 0.05

# Three line-based scroll-DOWN events. newScrollEvent({0, -1}, 'line') sets
# DeltaAxis1 = -1; the handler does step = -DeltaAxis1 = +1 (focus advances).
# Inter-event pause prevents the eventtap from coalescing them.
hsx "
  for i = 1, 3 do
    hs.eventtap.event.newScrollEvent({0, -1}, {}, 'line'):post()
    hs.timer.usleep(30000)
  end
  return 'ok'
" >/dev/null

wait_until '[ "$(hsx "return tostring(package.loaded[\"Palette\"]._state.focused)")" = "4" ]' 2 "focus advances to 4"

# One scroll-UP. {0, +1} = upward scroll = DeltaAxis1 = +1 = step = -1 = focus--.
hsx "hs.eventtap.event.newScrollEvent({0, 1}, {}, 'line'):post(); return 'ok'" >/dev/null

wait_until '[ "$(hsx "return tostring(package.loaded[\"Palette\"]._state.focused)")" = "3" ]' 2 "focus retreats to 3"

# Scroll on row 1 with up should saturate (no underflow), not wrap.
hsx "
  package.loaded['Palette']._state.focused = 1
  hs.eventtap.event.newScrollEvent({0, 1}, {}, 'line'):post()
  return 'ok'
" >/dev/null
sleep 0.1

focus_at_top="$(hsx "return tostring(package.loaded['Palette']._state.focused)")"
expect_eq "$focus_at_top" "1" "scroll-up at row 1 saturates"

echo "PASS: palette_scroll"
