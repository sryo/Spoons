#!/usr/bin/env bash
# CloudPad: POST /events with a move payload moves the cursor. The accelerator
# makes the actual delta non-linear, so we just assert the cursor moved right.
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

teardown() {
  global_teardown
}
trap teardown EXIT

# 1. Make sure CloudPad is running, then grab its URL.
hsx "if not require('CloudPad').isRunning() then require('CloudPad').start({port=1984}) end; return 'ok'" >/dev/null
url=$(hsx "return require('CloudPad').url")
wait_until "http_get '$url/health' >/dev/null 2>&1" 3 "/health responsive"

# 2. Park the cursor at a known position.
hsx "hs.mouse.absolutePosition({x=500, y=500}); return 'ok'" >/dev/null
sleep 0.05
start_x=$(hsx "return math.floor(hs.mouse.absolutePosition().x)")
expect_eq "$start_x" "500" "cursor parked at x=500"

# 3. Send a single move event with positive dx.
body=$(http_post_json "$url/events" '{"events":[{"t":"move","dx":50,"dy":0}]}')

# 4. Server must report it drained the one event.
if ! echo "$body" | grep -q '"drained":1\|"drained": 1'; then
  echo "FAIL: expected drained:1, got: $body" >&2
  exit 1
fi

# 5. Cursor should have moved to the right.
sleep 0.2
end_x=$(hsx "return math.floor(hs.mouse.absolutePosition().x)")
if [ "$end_x" -le "$start_x" ]; then
  echo "FAIL: cursor did not move right. start=$start_x end=$end_x" >&2
  exit 1
fi

echo "PASS: cloudpad_mouse_move_event"
