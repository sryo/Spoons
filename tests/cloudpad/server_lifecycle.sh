#!/usr/bin/env bash
# CloudPad: stop() makes isRunning() false; start() brings it back with a
# http://...:<port> URL. Direct-state, no HTTP traffic.
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

# Capture original state so we can restore it after the test.
was_running=$(hsx "return require('CloudPad').isRunning() and 'yes' or 'no'")

teardown() {
  if [ "${was_running:-yes}" = "yes" ]; then
    hsx "if not require('CloudPad').isRunning() then require('CloudPad').start({port=1984}) end; return 'ok'" >/dev/null 2>&1 || true
  fi
  global_teardown
}
trap teardown EXIT

# 1. If currently running, stop and verify isRunning() flips to false.
if [ "$was_running" = "yes" ]; then
  hsx "require('CloudPad').stop(); return 'ok'" >/dev/null
  wait_until "[ \"\$(hsx \"return require('CloudPad').isRunning() and 'yes' or 'no'\")\" = \"no\" ]" 3 "CloudPad stopped (initial)"
fi

# 2. Start and verify isRunning() flips to true.
hsx "require('CloudPad').start({port=1984}); return 'ok'" >/dev/null
wait_until "[ \"\$(hsx \"return require('CloudPad').isRunning() and 'yes' or 'no'\")\" = \"yes\" ]" 3 "CloudPad running"

# 3. URL should match http://...:1984.
url=$(hsx "return tostring(require('CloudPad').url)")
if ! echo "$url" | grep -qE '^http://.+:1984$'; then
  echo "FAIL: URL does not match http://...:1984, got: $url" >&2
  exit 1
fi

# 4. Stop again and verify isRunning() flips back to false.
hsx "require('CloudPad').stop(); return 'ok'" >/dev/null
wait_until "[ \"\$(hsx \"return require('CloudPad').isRunning() and 'yes' or 'no'\")\" = \"no\" ]" 3 "CloudPad stopped"

echo "PASS: cloudpad_server_lifecycle"
