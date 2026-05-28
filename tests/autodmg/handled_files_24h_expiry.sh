#!/usr/bin/env bash
# AutoDMG: handledFiles entries older than 24 h are cleared on the next
# scanDownloadsFolder() pass (triggered by a real FS event in ~/Downloads).
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

TEST_FILE="$HOME/Downloads/.autodmg_test_$$"
TRIGGER_FILE="$HOME/Downloads/.autodmg_trigger_$$"

teardown() {
  rm -f "$TRIGGER_FILE" "$TEST_FILE" >/dev/null 2>&1 || true
  hsx "require('AutoDMG').handledFiles['$TEST_FILE'] = nil; return 'ok'" >/dev/null 2>&1 || true
  global_teardown
}
trap teardown EXIT

# 1. Seed a stale handledFiles entry (timestamp > 86400 s ago).
hsx "require('AutoDMG').handledFiles['$TEST_FILE'] = os.time() - 100000; return 'ok'" >/dev/null
expect_eq "$(hsx "return require('AutoDMG').handledFiles['$TEST_FILE'] and 'present' or 'absent'")" "present" "stale entry set"

# 2. Touch a real file in ~/Downloads to fire the pathwatcher, which kicks the
#    0.5 s debounce. The next scanDownloadsFolder() pass drops stale entries.
touch "$TRIGGER_FILE"

# 3. The stale entry should be gone within a few seconds.
wait_until "[ \"\$(hsx \"return require('AutoDMG').handledFiles['$TEST_FILE'] and 'still' or 'cleared'\")\" = \"cleared\" ]" 3 "stale handledFiles entry cleared"

echo "PASS: autodmg_handled_files_24h_expiry"
