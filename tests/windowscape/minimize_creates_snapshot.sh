#!/usr/bin/env bash
# WindowScape: windowScapeMinimize() creates a snapshot entry for the focused
# window. snapshots.getState().windows[winId] is populated, order has one
# entry, and windowScapeIsMinimized reports true.
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

winId="$(hsx "return hs.window.focusedWindow():id()")"

# 2. Minimize via the global helper installed by WindowScape/init.lua.
hsx "windowScapeMinimize(); return 'ok'" >/dev/null

# 3. Snapshot map should now contain this winId.
wait_until "[ \"\$(hsx \"return require('WindowScape.snapshots').getState().windows[$winId] and 'yes' or 'no'\")\" = \"yes\" ]" 5 "snapshot created for winId"

# 4. The snapshot order array should have exactly one entry.
expect_eq "$(hsx "return tostring(#require('WindowScape.snapshots').getState().order)")" "1" "snapshot order has one entry"

# 5. windowScapeIsMinimized should report true for this window.
expect_eq "$(hsx "return windowScapeIsMinimized(hs.window.get($winId)) and 'yes' or 'no'")" "yes" "windowScapeIsMinimized true"

echo "PASS: windowscape_minimize_creates_snapshot"
