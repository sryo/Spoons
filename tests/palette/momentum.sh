#!/usr/bin/env bash
# Palette: continuous (trackpad) scroll events with a momentum phase keep
# stepping focus after fingers lift. Any keystroke during the glide aborts
# further momentum.

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

hsx "package.loaded['Palette'].open(); return 'ok'" >/dev/null
sleep 0.2

items="$(hsx "return tostring(#package.loaded['Palette']._state.items)")"
if [ "$items" -lt "5" ]; then
  echo "FAIL: need >=5 items (got $items)" >&2
  exit 1
fi

# Park cursor over the canvas so dismissTap routes the events through the
# inside-card path.
hsx "
  local f = require('Palette.canvas').frame()
  hs.mouse.absolutePosition({x = f.x + f.w/2, y = f.y + f.h/2})
  return 'ok'
" >/dev/null
sleep 0.05

# 1) Momentum events advance focus. Post a small burst of momentum-phase
# pixel scrolls each carrying 24px of downward delta (one row's worth at
# scrollStepPx). Expect focus to climb from 1 toward 4.
hsx "
  package.loaded['Palette']._state.focused = 1
  local props = hs.eventtap.event.properties
  for i = 1, 3 do
    local e = hs.eventtap.event.newScrollEvent({0, 0}, {}, 'pixel')
    e:setProperty(props.scrollWheelEventIsContinuous, 1)
    e:setProperty(props.scrollWheelEventMomentumPhase, 2)
    e:setProperty(props.scrollWheelEventPointDeltaAxis1, -24)
    e:post()
    hs.timer.usleep(20000)
  end
  return 'ok'
" >/dev/null

wait_until '[ "$(hsx "return tostring(package.loaded[\"Palette\"]._state.focused)")" = "4" ]' 2 "momentum scroll steps focus"

# 2) A keypress during the glide cancels further momentum. Reset focus to
# mid-list, send a momentum event (steps once), simulate a keypress on the
# dismissTap path by calling the right-arrow handler on the open keys tap,
# then send another momentum event and assert focus did NOT advance.
hsx "
  local s = package.loaded['Palette']._state
  s.focused = 3
  local props = hs.eventtap.event.properties
  local function pulse()
    local e = hs.eventtap.event.newScrollEvent({0, 0}, {}, 'pixel')
    e:setProperty(props.scrollWheelEventIsContinuous, 1)
    e:setProperty(props.scrollWheelEventMomentumPhase, 2)
    e:setProperty(props.scrollWheelEventPointDeltaAxis1, -24)
    e:post()
  end
  pulse()
  hs.timer.usleep(30000)
  -- A real keystroke routes through the keys eventtap, which calls
  -- handlers.onAnyKey before dispatching. Posting a synthetic keyDown does
  -- the same thing.
  hs.eventtap.event.newKeyEvent({}, 'left', true):post()
  hs.timer.usleep(20000)
  pulse()
  hs.timer.usleep(30000)
  return tostring(s.focused)
" >/dev/null

# Focus stepped once from the first pulse (to row 4), the keypress canceled
# the glide, so the second pulse is dropped — still at 4.
focus_after_cancel="$(hsx "return tostring(package.loaded['Palette']._state.focused)")"
expect_eq "$focus_after_cancel" "4" "keypress cancels in-flight glide"

echo "PASS: palette_momentum"
