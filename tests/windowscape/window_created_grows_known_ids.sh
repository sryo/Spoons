#!/usr/bin/env bash
# WindowScape: opening a new TextEdit window registers the new winId in
# core.lastKnownWindowIds (which the events module uses to detect creates).
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

APP="com.apple.TextEdit"

teardown() {
  steve quit "$APP" >/dev/null 2>&1 || true
  global_teardown
}
trap teardown EXIT

# 1. Clean slate + baseline window.
windowscape_reset
launch_app "$APP"
seed_single_window_app "$APP"

baseline_id="$(hsx "return hs.application.get('$APP'):mainWindow():id()")"
before="$(hsx "local n=0; for _ in pairs(require('WindowScape.core').lastKnownWindowIds) do n=n+1 end; return n")"

# 2. Spawn a second window via cmd+n.
hsx "hs.application.get('$APP'):activate(); hs.eventtap.keyStroke({'cmd'}, 'n'); return 'ok'" >/dev/null
wait_window_count "$APP" 2 5

# 3. The new (non-baseline) window's id should land in lastKnownWindowIds.
wait_until "[ \"\$(hsx \"local c=require('WindowScape.core'); for _,w in ipairs(hs.application.get('$APP'):allWindows()) do if w:id() ~= $baseline_id and c.lastKnownWindowIds[w:id()] then return 'yes' end end; return 'no'\")\" = \"yes\" ]" 5 "new window id registered in lastKnownWindowIds"

# 4. The set should have grown by at least one entry.
now="$(hsx "local n=0; for _ in pairs(require('WindowScape.core').lastKnownWindowIds) do n=n+1 end; return n")"
if ! [ "$now" -gt "$before" ]; then
  echo "expected lastKnownWindowIds count to grow: before=$before now=$now" >&2
  exit 1
fi

echo "PASS: windowscape_window_created_grows_known_ids"
