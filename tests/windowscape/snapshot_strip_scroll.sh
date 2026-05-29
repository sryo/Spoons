#!/usr/bin/env bash
# WindowScape: snapshot strip overflows when there are more snapshots than fit;
# updateLayout clamps the per-screen scroll offset to the overflow range, and
# the first snapshot's topLeft shifts by the offset along the strip's axis.
# Direct-state test: inject fake canvas entries into snapshots.windows.
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

teardown() { global_teardown; }
trap teardown EXIT

windowscape_reset

# Build 20 oversized fake snapshots on the main screen, then run updateLayout
# with a huge requested offset and read back the clamped value plus the topLeft
# of the first snapshot.
result="$(hsx "
  local canvas = require('hs.canvas')
  local snap   = require('WindowScape.snapshots')
  local s      = snap.getState()
  snap.clearAll()
  local scr   = hs.screen.mainScreen()
  local sid   = scr:id()
  local frame = scr:frame()
  local isLandscape = frame.w > frame.h
  local size  = { w = 100, h = 100 }
  local N     = 20
  for i = 1, N do
    local c = canvas.new({ x = -1000, y = -1000, w = size.w, h = size.h })
    s.windows[1000 + i] = { canvas = c, screenId = sid, snapSize = size }
    table.insert(s.order, 1000 + i)
  end

  snap.setStripScrollOffset(sid, 1e9)
  snap.updateLayout()

  local PADDING = 8
  local GAP     = 4
  local contentLen = N * (isLandscape and size.h or size.w) + (N - 1) * GAP
  local visibleLen = (isLandscape and frame.h or frame.w) - PADDING * 2
  local expectedMax = math.max(0, contentLen - visibleLen)

  local clamped = snap.getStripScrollOffsets()[sid]
  local first = s.windows[1001].canvas:topLeft()

  local axisOk
  if isLandscape then
    axisOk = math.abs(first.y - (frame.y + PADDING - clamped)) < 0.5
  else
    axisOk = math.abs(first.x - (frame.x + PADDING - clamped)) < 0.5
  end

  -- Cleanup the fake canvases so they don't linger.
  for i = 1, N do
    local entry = s.windows[1000 + i]
    if entry and entry.canvas then entry.canvas:delete() end
    s.windows[1000 + i] = nil
  end
  s.order = {}

  return string.format('clamped=%d expectedMax=%d axisOk=%s', clamped, expectedMax, tostring(axisOk))
")"

echo "$result"
expected_max="$(echo "$result" | sed -nE 's/.*expectedMax=([0-9]+).*/\1/p')"
clamped="$(echo "$result" | sed -nE 's/.*clamped=([0-9]+).*/\1/p')"
axis_ok="$(echo "$result" | sed -nE 's/.*axisOk=(true|false).*/\1/p')"

expect_eq "$clamped" "$expected_max" "huge offset clamped to maxOffset"
expect_eq "$axis_ok" "true" "first snapshot topLeft shifted by clamped offset"

# Test 2: setting offset to 0 puts the first snapshot at the home edge.
result2="$(hsx "
  local canvas = require('hs.canvas')
  local snap   = require('WindowScape.snapshots')
  local s      = snap.getState()
  snap.clearAll()
  local scr   = hs.screen.mainScreen()
  local sid   = scr:id()
  local frame = scr:frame()
  local isLandscape = frame.w > frame.h
  local size  = { w = 100, h = 100 }
  for i = 1, 4 do
    local c = canvas.new({ x = -1000, y = -1000, w = size.w, h = size.h })
    s.windows[2000 + i] = { canvas = c, screenId = sid, snapSize = size }
    table.insert(s.order, 2000 + i)
  end

  snap.setStripScrollOffset(sid, 0)
  snap.updateLayout()
  local first = s.windows[2001].canvas:topLeft()
  local PADDING = 8
  local atHomeEdge
  if isLandscape then
    atHomeEdge = math.abs(first.y - (frame.y + PADDING)) < 0.5
  else
    atHomeEdge = math.abs(first.x - (frame.x + PADDING)) < 0.5
  end

  for i = 1, 4 do
    local entry = s.windows[2000 + i]
    if entry and entry.canvas then entry.canvas:delete() end
    s.windows[2000 + i] = nil
  end
  s.order = {}

  return tostring(atHomeEdge)
")"
expect_eq "$result2" "true" "offset=0 anchors first snapshot at the strip's home edge"

echo "PASS: windowscape_snapshot_strip_scroll"
