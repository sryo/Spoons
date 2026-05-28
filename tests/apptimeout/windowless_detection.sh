#!/usr/bin/env bash
# AppTimeout: when an app has zero visible windows and is not frontmost,
# the next 10 s scan tick records it in windowlessApps (localized app name key).
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

APP="com.apple.TextEdit"

# Resolved at runtime once the app is up; cleared in teardown.
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

# 2. Resolve the localized app name (key used inside AppTimeout).
NAME="$(hsx "return hs.application.get('$APP'):name()")"
if [ -z "$NAME" ]; then
  echo "could not resolve localized name for $APP" >&2
  exit 1
fi

# 3. Pre-state: not yet tracked as windowless.
expect_eq "$(hsx "return require('AppTimeout').windowlessApps['$NAME'] and 'present' or 'absent'")" "absent" "not yet windowless"

# 4. Close every TextEdit window.
hsx "local a=hs.application.get('$APP'); for _,w in ipairs(a:allWindows()) do w:close() end; return 'ok'" >/dev/null
wait_window_count "$APP" 0 5

# 5. Focus Finder so TextEdit is not frontmost; the scan only flags non-frontmost apps.
hsx "hs.application.launchOrFocus('Finder'); return 'ok'" >/dev/null
sleep 0.5

# 6. Within ~12 s the AppTimeout scan tick should record the entry.
wait_until "[ \"\$(hsx \"return require('AppTimeout').windowlessApps['$NAME'] and 'yes' or 'no'\")\" = \"yes\" ]" 12 "AppTimeout flagged TextEdit as windowless" 0.5

echo "PASS: apptimeout_windowless_detection"
