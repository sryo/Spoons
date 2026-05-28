#!/usr/bin/env bash
# WindowScape: tiler.tileWindows() recovers from a stuck tilingCount: even when
# core.tilingCount has been left > 0 by a previous interrupted pass, calling
# tileWindows() runs to completion, resets tilingCount to 0, and the single
# window ends up filling the adjusted screen frame.
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

APP="com.apple.TextEdit"

teardown() {
  steve quit "$APP" >/dev/null 2>&1 || true
  global_teardown
}
trap teardown EXIT

# 1. Reset state, launch app, open one window.
windowscape_reset
launch_app "$APP"
seed_single_window_app "$APP"

# 2. Capture the window id.
winId="$(hsx "return hs.application.get('$APP'):mainWindow():id()")"

# 3. Force tilingCount > 0 to simulate a previously interrupted tile pass.
hsx "require('WindowScape.core').tilingCount = 3; return 'ok'" >/dev/null

# 4. Trigger a force-retile.
hsx "require('WindowScape.tiler').tileWindows(); return 'ok'" >/dev/null

# 5. tilingCount should drop back to 0 once the pass completes.
wait_until "[ \"\$(hsx \"return require('WindowScape.core').tilingCount\")\" = \"0\" ]" 3 "tilingCount reset to 0"

# 6. Window frame should match the adjusted screen frame within 5 px on each axis.
wait_until "[ \"\$(hsx \"local w=hs.window.get($winId); local scr=w:screen(); local target=require('WindowScape.snapshots').getAdjustedScreenFrame(scr); local actual=w:frame(); local dx=math.abs(actual.x - target.x); local dy=math.abs(actual.y - target.y); local dw=math.abs(actual.w - target.w); local dh=math.abs(actual.h - target.h); return (dx <= 5 and dy <= 5 and dw <= 5 and dh <= 5) and 'fits' or 'mismatch'\")\" = \"fits\" ]" 3 "window fills adjusted screen frame"

echo "PASS: force_retile_resets_count"
