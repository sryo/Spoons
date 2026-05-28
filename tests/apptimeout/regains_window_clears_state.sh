#!/usr/bin/env bash
# AppTimeout: once an app is in windowlessApps and regains a window,
# the next scan tick clears its entry.
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

APP="com.apple.TextEdit"

NAME=""

teardown() {
  if [ -n "$NAME" ]; then
    hsx "require('AppTimeout').windowlessApps['$NAME'] = nil; return 'ok'" >/dev/null 2>&1 || true
  fi
  steve quit "$APP" >/dev/null 2>&1 || true
  global_teardown
}
trap teardown EXIT

# 1. Baseline.
windowscape_reset
launch_app "$APP"
seed_single_window_app "$APP"

NAME="$(hsx "return hs.application.get('$APP'):name()")"
if [ -z "$NAME" ]; then
  echo "could not resolve localized name for $APP" >&2
  exit 1
fi

# 2. Drive TextEdit into the windowless state, same path as test 1.
hsx "local a=hs.application.get('$APP'); for _,w in ipairs(a:allWindows()) do w:close() end; return 'ok'" >/dev/null
wait_window_count "$APP" 0 5
hsx "hs.application.launchOrFocus('Finder'); return 'ok'" >/dev/null
sleep 0.5
wait_until "[ \"\$(hsx \"return require('AppTimeout').windowlessApps['$NAME'] and 'yes' or 'no'\")\" = \"yes\" ]" 12 "windowlessApps has entry" 0.5

# 3. Reopen a TextEdit window via cmd+n.
hsx "hs.application.get('$APP'):activate(); hs.eventtap.keyStroke({'cmd'}, 'n'); return 'ok'" >/dev/null
wait_window_count "$APP" 1 5

# 4. The next scan tick (within ~12 s) should clear the entry.
wait_until "[ \"\$(hsx \"return require('AppTimeout').windowlessApps['$NAME'] and 'still' or 'cleared'\")\" = \"cleared\" ]" 12 "windowlessApps entry cleared" 0.5

echo "PASS: apptimeout_regains_window_clears_state"
