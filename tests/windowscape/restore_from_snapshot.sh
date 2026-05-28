#!/usr/bin/env bash
# WindowScape: snapshots.restoreFromSnapshot(winId) clears the snapshot entry
# and animates the window back to its pre-minimize frame (within 5 px).
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

APP="com.apple.TextEdit"

teardown() {
  steve quit "$APP" >/dev/null 2>&1 || true
  global_teardown
}
trap teardown EXIT

# 1. Clean slate + one focused window.
windowscape_reset
launch_app "$APP"
seed_single_window_app "$APP"

# 2. Focus + capture pre-minimize frame (id, x, y, w, h) as one CSV.
csv="$(hsx "local w=hs.application.get('$APP'):mainWindow(); w:focus(); local f=w:frame(); return string.format('%d,%d,%d,%d,%d', w:id(), math.floor(f.x), math.floor(f.y), math.floor(f.w), math.floor(f.h))")"
IFS=',' read -r winId orig_x orig_y orig_w orig_h <<< "$csv"

if [ -z "${winId:-}" ] || [ -z "${orig_x:-}" ]; then
  echo "failed to parse pre-minimize frame CSV: '$csv'" >&2
  exit 1
fi

# 3. Minimize and confirm the snapshot is in place.
hsx "windowScapeMinimize(); return 'ok'" >/dev/null
wait_until "[ \"\$(hsx \"return require('WindowScape.snapshots').getState().windows[$winId] and 'yes' or 'no'\")\" = \"yes\" ]" 5 "snapshot present before restore"

# 4. Restore.
hsx "require('WindowScape.snapshots').restoreFromSnapshot($winId); return 'ok'" >/dev/null

# 5. Snapshot entry removed + order array drained.
wait_until "[ \"\$(hsx \"return require('WindowScape.snapshots').getState().windows[$winId] and 'yes' or 'no'\")\" = \"no\" ]" 5 "snapshot entry removed"
expect_eq "$(hsx "return tostring(#require('WindowScape.snapshots').getState().order)")" "0" "snapshot order empty"

# 6. Restored frame should match the pre-minimize frame within 5 px.
wait_until "[ \"\$(hsx \"local w=hs.window.get($winId); if not w then return 'no' end; local f=w:frame(); if math.abs(f.x - $orig_x) <= 5 and math.abs(f.y - $orig_y) <= 5 and math.abs(f.w - $orig_w) <= 5 and math.abs(f.h - $orig_h) <= 5 then return 'yes' else return 'no' end\")\" = \"yes\" ]" 5 "frame restored within 5px"

echo "PASS: windowscape_restore_from_snapshot"
