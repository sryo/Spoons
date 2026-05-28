#!/usr/bin/env bash
# Palette: single left-click on a list row runs that row's default verb.
# Drives the real dismissTap eventtap by posting a leftClick at the screen
# coordinates of row 2 (resolved via canvas.hitTestRow).

set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

teardown() {
  hsx "
    local P = package.loaded['Palette']
    if P then
      if P.isOpen() then P.close() end
      local b = rawget(_G, '_paletteVerbBackup')
      if b and P.verbs[b.id] then P.verbs[b.id].run = b.run end
      _G._paletteVerbBackup  = nil
      _G._paletteClickRecord = nil
    end
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

# Open palette and wait for first draw (which populates lastListLayout).
hsx "package.loaded['Palette'].open(); return 'ok'" >/dev/null
sleep 0.2

items="$(hsx "return tostring(#package.loaded['Palette']._state.items)")"
if [ "$items" -lt "2" ]; then
  echo "FAIL: need >=2 items, got $items" >&2
  exit 1
fi

# Stub row 2's default verb. The stub records the item id and skips the real
# side-effect (which would activate an app, focus a menu, etc).
stub_info="$(hsx "
  local P = package.loaded['Palette']
  local item = P._state.items[2]
  local vid  = item.defaultVerb or 'activate'
  local verb = P.verbs[vid]
  if not verb then return 'no-verb' end
  _G._paletteVerbBackup  = { id = vid, run = verb.run }
  _G._paletteClickRecord = nil
  verb.run = function(it, _, _ctx)
    _G._paletteClickRecord = it and it.id or '<no-item>'
    return true
  end
  return string.format('%s:::%s', vid, tostring(item.id))
")"
if [ "$stub_info" = "no-verb" ] || [ -z "$stub_info" ]; then
  echo "FAIL: could not stub row 2's verb (got '$stub_info')" >&2
  exit 1
fi
expected_id="${stub_info##*:::}"

# Resolve row 2's screen coordinates by probing canvas.hitTestRow. Scanning
# beats hardcoding because listY depends on whether the breadcrumb is shown.
coords="$(hsx "
  local canvas = require('Palette.canvas')
  local f = canvas.frame()
  for y = 0, math.floor(f.h - 1), 2 do
    if canvas.hitTestRow({x = 50, y = y}) == 2 then
      return string.format('%d,%d', math.floor(f.x + 60), math.floor(f.y + y + 10))
    end
  end
  return 'no-row'
")"
if [ "$coords" = "no-row" ]; then
  echo "FAIL: hitTestRow could not locate row 2" >&2
  exit 1
fi
IFS=',' read -r cx cy <<< "$coords"

# Move the cursor onto the row, then leftClick. dismissTap should hit-test,
# set state.focused = 2, and call activateFocused (which closes the palette).
hsx "
  hs.mouse.absolutePosition({x = $cx, y = $cy})
  hs.timer.usleep(50000)
  hs.eventtap.leftClick({x = $cx, y = $cy})
  return 'ok'
" >/dev/null

wait_until '[ "$(hsx "return package.loaded[\"Palette\"].isOpen() and \"yes\" or \"no\"")" = "no" ]' 3 "palette closes after row click"

recorded="$(hsx "return tostring(rawget(_G, '_paletteClickRecord'))")"
expect_eq "$recorded" "$expected_id" "verb stub received row 2's item id"

echo "PASS: palette_clicktarget"
