#!/usr/bin/env bash
# Toggling the focused app's listed status flips the outline stroke color
# between cfg.outlineColor (included) and cfg.outlineColorPinned (excluded).
# Project default: exclusionMode = true, so listed = excluded.
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"
source "$(dirname "$0")/_textedit_window.sh"

PEEK="$(dirname "$0")/_introspect.lua"
APP="com.apple.TextEdit"

teardown() {
  # Restore the app to its default unlisted state.
  hsx "
    local ok, core = pcall(require, 'WindowScape.core')
    if ok and core.listedApps then core.listedApps['$APP'] = nil end
    return 'ok'
  " >/dev/null 2>&1 || true
  steve quit "$APP" >/dev/null 2>&1 || true
  global_teardown
}
trap teardown EXIT

windowscape_reset

# Make sure TextEdit is unlisted (defaults to included since exclusionMode=true).
hsx "require('WindowScape.core').listedApps['$APP'] = nil; return 'ok'" >/dev/null

winId="$(setup_textedit_window "$APP")"

hsx "
  local w = hs.window.get($winId)
  require('WindowScape.outline').draw(w)
  return 'ok'
" >/dev/null

wait_until "[ \"\$(hsx \"local i=dofile('$PEEK'); return tostring(i.showing())\")\" = \"true\" ]" 3 "outline visible"
sleep 0.35  # allow color animation to settle

unpinned="$(hsx "
  local i = dofile('$PEEK')
  local c = i.strokeColor()
  if not c then return 'no-color' end
  return string.format('%.2f,%.2f,%.2f', c.red or 0, c.green or 0, c.blue or 0)
")"

# List TextEdit → excluded → pinned color.
hsx "
  local core = require('WindowScape.core')
  core.listedApps['$APP'] = true
  require('WindowScape.outline').draw(hs.window.get($winId))
  return 'ok'
" >/dev/null

sleep 0.35

pinned="$(hsx "
  local i = dofile('$PEEK')
  local c = i.strokeColor()
  if not c then return 'no-color' end
  return string.format('%.2f,%.2f,%.2f', c.red or 0, c.green or 0, c.blue or 0)
")"

if [ "$unpinned" = "$pinned" ]; then
  echo "FAIL: outline color did not change on pin toggle ($unpinned)"
  exit 1
fi

want_unpinned="$(hsx "
  local c = require('WindowScape.config').cfg.outlineColor
  return string.format('%.2f,%.2f,%.2f', c.red or 0, c.green or 0, c.blue or 0)
")"
want_pinned="$(hsx "
  local c = require('WindowScape.config').cfg.outlineColorPinned
  return string.format('%.2f,%.2f,%.2f', c.red or 0, c.green or 0, c.blue or 0)
")"

expect_eq "$unpinned" "$want_unpinned" "unpinned color matches cfg.outlineColor"
expect_eq "$pinned" "$want_pinned" "pinned color matches cfg.outlineColorPinned"

echo "PASS: outline_color_updates_on_pin_toggle"
