#!/usr/bin/env bash
# WanderFocus: start() wires a mouseMoved eventtap whose debounced timer
# actually calls _focusWindowUnderCursor, and stop() tears it down. We
# instrument the function rather than depend on real window-focus changes
# because real apps (TextEdit, Notes, etc.) have AXTextArea focused elements
# that legitimately trigger the typing gate.

set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

teardown() {
  hsx "
    if package.loaded['WanderFocus'] then
      local W = require('WanderFocus')
      if W._origFocus then
        W._focusWindowUnderCursor = W._origFocus
        W._origFocus = nil
      end
      W._testCalls = nil
      W.cfg.mode = 'autoraise'
      if not W._mouseWatcher then W.start() end
    end
    return 'ok'
  " >/dev/null 2>&1 || true
  global_teardown
}
trap teardown EXIT

loaded="$(hsx "return package.loaded['WanderFocus'] and 'yes' or 'no'")"
if [ "$loaded" != "yes" ]; then
  echo "WanderFocus not loaded in Hammerspoon" >&2
  exit 2
fi

# Replace _focusWindowUnderCursor with a counter. Restart so the new closure
# captured by the eventtap's hs.timer.doAfter call actually picks up the stub.
hsx "
  local W = require('WanderFocus')
  if W._mouseWatcher then W.stop() end
  W._origFocus = W._focusWindowUnderCursor
  W._testCalls = 0
  W._focusWindowUnderCursor = function() W._testCalls = W._testCalls + 1 end
  W.cfg.mode = 'autoraise'
  W.start()
  return 'ok'
" >/dev/null

# Park the cursor in a known position.
hsx "
  local sf = hs.screen.mainScreen():frame()
  hs.mouse.absolutePosition({ x = sf.x + 100, y = sf.y + 100 })
  return 'ok'
" >/dev/null
sleep 0.05

# Snapshot the counter, then synthesise a mouseMoved.
before="$(hsx "return tostring(require('WanderFocus')._testCalls)")"
hsx "
  local sf = hs.screen.mainScreen():frame()
  local x, y = sf.x + 300, sf.y + 300
  hs.mouse.absolutePosition({ x = x, y = y })
  hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.mouseMoved, { x = x, y = y }):post()
  return 'ok'
" >/dev/null

# Eventtap reschedules the debounced timer (wanderDelay 0.2 s). Give 1.5 s slack.
wait_until "[ \"\$(hsx \"return tostring(require('WanderFocus')._testCalls)\")\" != \"$before\" ]" 1.5 "mouseMoved eventtap fired _focusWindowUnderCursor" 0.05

# stop() must immediately suppress further calls.
hsx "require('WanderFocus').stop(); return 'ok'" >/dev/null
mid="$(hsx "return tostring(require('WanderFocus')._testCalls)")"
hsx "
  local sf = hs.screen.mainScreen():frame()
  local x, y = sf.x + 500, sf.y + 400
  hs.mouse.absolutePosition({ x = x, y = y })
  hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.mouseMoved, { x = x, y = y }):post()
  return 'ok'
" >/dev/null
sleep 0.4
after="$(hsx "return tostring(require('WanderFocus')._testCalls)")"
expect_eq "$after" "$mid" "stop() prevents further _focusWindowUnderCursor calls"

echo "PASS: wanderfocus_eventtap_wiring"
