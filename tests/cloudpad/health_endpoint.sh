#!/usr/bin/env bash
# CloudPad: GET /health returns 200 with JSON containing "ok":true and a
# version key.
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

# 2. Fetch /health.
body=$(http_get "$url/health")

# 3. Body must contain ok:true and a version key.
if ! echo "$body" | grep -q '"ok":true\|"ok": true'; then
  echo "FAIL: missing ok:true, got: $body" >&2
  exit 1
fi
if ! echo "$body" | grep -q 'version'; then
  echo "FAIL: missing version key, got: $body" >&2
  exit 1
fi

echo "PASS: cloudpad_health_endpoint"
