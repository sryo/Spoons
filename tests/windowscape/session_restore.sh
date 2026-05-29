#!/usr/bin/env bash
# WindowScape: restore.writeSync persists windowOrderBySpace + per-window
# weights to WindowScape_layout.json; restore.load reapplies weights to live
# windows matched by bundleID.
# Direct-state test: inject the window into windowOrderBySpace ourselves so
# the test is independent of the user's app exclusion list.
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

APP="com.apple.TextEdit"
SIDECAR="$HOME/.hammerspoon/WindowScape_layout.json"
BACKUP="$SIDECAR.test_backup"

[ -f "$SIDECAR" ] && cp "$SIDECAR" "$BACKUP"

teardown() {
  steve quit "$APP" >/dev/null 2>&1 || true
  rm -f "$SIDECAR"
  [ -f "$BACKUP" ] && mv "$BACKUP" "$SIDECAR"
  global_teardown
}
trap teardown EXIT

windowscape_reset
rm -f "$SIDECAR"
launch_app "$APP"
seed_single_window_app "$APP"

winId="$(hsx "return hs.application.get('$APP'):mainWindow():id()")"

# Inject TextEdit into the current space's order, give it a distinct weight,
# and persist. Bypasses updateWindowOrder's app-exclusion filter.
hsx "
  local c = require('WindowScape.core')
  local t = require('WindowScape.tiler')
  local r = require('WindowScape.restore')
  local win = hs.window.get($winId)
  c.windowWeights = {}
  c.windowOrderBySpace = {}
  c.windowOrderBySpace[c.getCurrentSpace()] = { win }
  t.setWindowWeight(win, 1.75)
  r.writeSync()
  return 'ok'
" >/dev/null

[ -f "$SIDECAR" ] || { echo "sidecar not written at $SIDECAR"; exit 1; }
grep -q "com.apple.TextEdit" "$SIDECAR" || { echo "bundleID missing"; cat "$SIDECAR"; exit 1; }
grep -q "1.75" "$SIDECAR" || { echo "weight 1.75 missing"; cat "$SIDECAR"; exit 1; }

# Clear weights, then load should restore 1.75.
hsx "require('WindowScape.core').windowWeights = {}; return 'ok'" >/dev/null
expect_eq "$(hsx "return string.format('%.2f', require('WindowScape.tiler').getWindowWeight(hs.window.get($winId)))")" "1.00" "weight cleared before load"

hsx "
  local c = require('WindowScape.core')
  local win = hs.window.get($winId)
  c.windowOrderBySpace = {}
  c.windowOrderBySpace[c.getCurrentSpace()] = { win }
  require('WindowScape.restore').load()
  return 'ok'
" >/dev/null
expect_eq "$(hsx "return string.format('%.2f', require('WindowScape.tiler').getWindowWeight(hs.window.get($winId)))")" "1.75" "weight restored to 1.75 from sidecar"

echo "PASS: windowscape_session_restore"
