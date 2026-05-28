#!/usr/bin/env bash
# WindowScape: when a snapshot's screenId is no longer valid,
# snapshots.updateLayout() reassigns it to a valid (main) screen and
# keeps the canvas object alive.
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

hsx "hs.application.get('$APP'):mainWindow():focus(); return 'ok'" >/dev/null
wait_until "[ \"\$(hsx \"local w=hs.window.focusedWindow(); return w and w:application():bundleID() == '$APP' and 'yes' or 'no'\")\" = \"yes\" ]" 3 "TextEdit window focused"

# 2. Minimize via the global helper installed by WindowScape/init.lua.
hsx "windowScapeMinimize(); return 'ok'" >/dev/null

# 3. Wait until the snapshot is fully created (isCreating == false) and
#    capture the winId from the order array.
wait_until "[ \"\$(hsx \"return require('WindowScape.snapshots').getState().isCreating and 'yes' or 'no'\")\" = \"no\" ]" 5 "snapshot creation completed"
wait_until "[ \"\$(hsx \"return tostring(#require('WindowScape.snapshots').getState().order)\")\" = \"1\" ]" 5 "snapshot order populated"

winId="$(hsx "return require('WindowScape.snapshots').getState().order[1]")"
if [ -z "${winId:-}" ] || [ "$winId" = "nil" ]; then
  echo "failed to capture snapshot winId" >&2
  exit 1
fi

mainId="$(hsx "return hs.screen.mainScreen():id()")"

# 4. Corrupt the snapshot's screenId so it no longer matches any real screen.
hsx "require('WindowScape.snapshots').getState().windows[$winId].screenId = -99999; return 'ok'" >/dev/null

# 5. Trigger relayout: this should detect the invalid screenId and reassign.
hsx "require('WindowScape.snapshots').updateLayout(); return 'ok'" >/dev/null

# 6. Assertions: screenId now points at the main screen and canvas is alive.
expect_eq "$(hsx "return tostring(require('WindowScape.snapshots').getState().windows[$winId].screenId)")" "$mainId" "snapshot screenId reassigned to main screen"
expect_eq "$(hsx "return require('WindowScape.snapshots').getState().windows[$winId].canvas and 'alive' or 'nil'")" "alive" "canvas object still alive"

echo "PASS: windowscape_snapshot_reassigns_screen_on_invalid_id"
