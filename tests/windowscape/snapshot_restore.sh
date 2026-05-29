#!/usr/bin/env bash
# WindowScape: restore.writeSync persists currently-minimized snapshots to the
# sidecar; restore.loadSnapshots reattaches them after a fresh state. Across
# hs.reload, the originalFrame stays accurate so a click-to-restore puts the
# window back where it was, not at the off-screen sliver.
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

APP="com.apple.TextEdit"
SIDECAR="$HOME/.hammerspoon/WindowScape_layout.json"
BACKUP="$SIDECAR.test_backup"

[ -f "$SIDECAR" ] && cp "$SIDECAR" "$BACKUP"

teardown() {
  # Drop any rehydrated snapshot before quitting so the canvas doesn't linger.
  hsx "
    local s = require('WindowScape.snapshots')
    for winId in pairs(require('WindowScape.core').snapshotsState.windows) do
      s.cleanupResources(winId)
    end
    return 'ok'
  " >/dev/null 2>&1 || true
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

# Seed a minimized-snapshot entry directly into state. Use a distinctive
# originalFrame so we can verify it round-trips through the sidecar.
hsx "
  local c = require('WindowScape.core')
  local s = c.snapshotsState
  s.windows = {}
  s.order   = {}
  s.windows[$winId] = {
    win           = hs.window.get($winId),
    canvas        = nil,
    originalFrame = { x = 137, y = 251, w = 463, h = 379 },
    snapSize      = { w = 124, h = 80 },
    screenId      = hs.screen.mainScreen():id(),
  }
  table.insert(s.order, $winId)
  require('WindowScape.restore').writeSync()
  return 'ok'
" >/dev/null

[ -f "$SIDECAR" ] || { echo "sidecar not written"; exit 1; }
grep -q '"snapshots"' "$SIDECAR" || { echo "snapshots array missing"; cat "$SIDECAR"; exit 1; }
grep -q "com.apple.TextEdit" "$SIDECAR" || { echo "TextEdit bundleID missing"; cat "$SIDECAR"; exit 1; }
grep -q "137" "$SIDECAR" || { echo "originalFrame.x=137 missing"; cat "$SIDECAR"; exit 1; }

# Wipe the live snapshot state, then loadSnapshots should reattach via createSnapshot.
hsx "
  local s = require('WindowScape.core').snapshotsState
  s.windows = {}
  s.order   = {}
  return 'ok'
" >/dev/null
expect_eq "$(hsx "local s=require('WindowScape.core').snapshotsState; local n=0; for _ in pairs(s.windows) do n=n+1 end; return tostring(n)")" "0" "snapshots cleared before reload"

hsx "require('WindowScape.restore').loadSnapshots(); return 'ok'" >/dev/null

# Rehydrated entry exists with the saved originalFrame.
expect_eq "$(hsx "return require('WindowScape.core').snapshotsState.windows[$winId] and 'yes' or 'no'")" "yes" "winId rehydrated into snapshots.windows"
expect_eq "$(hsx "return tostring(require('WindowScape.core').snapshotsState.windows[$winId].originalFrame.x)")" "137" "originalFrame.x restored"
expect_eq "$(hsx "return tostring(require('WindowScape.core').snapshotsState.windows[$winId].originalFrame.h)")" "379" "originalFrame.h restored"
expect_eq "$(hsx "local s=require('WindowScape.core').snapshotsState; return tostring(s.order[1])")" "$winId" "winId present in snapshots.order"

# isAppIncluded should now exclude this window so updateWindowOrder skips it.
included="$(hsx "
  local c = require('WindowScape.core')
  local win = hs.window.get($winId)
  local app = c.safeGetApplication(win)
  return c.isAppIncluded(app, win) and 'yes' or 'no'
")"
expect_eq "$included" "no" "rehydrated window is excluded from tiling"

echo "PASS: windowscape_snapshot_restore"
