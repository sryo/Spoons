#!/usr/bin/env bash
# Diagnostic capture of Muse HUD text + cursor behaviour, character by character.
#
# Run:    bash ~/.hammerspoon/tests/_muse_text_cursor_capture.sh
# String: MUSE_TEST_STRING='hello world' bash _muse_text_cursor_capture.sh
# Slower: MUSE_STEP_DELAY=0.25 bash _muse_text_cursor_capture.sh
#
# Outputs:
#   /tmp/muse-text-cursor-test.json   per-character records (JSON)
#   /tmp/muse-text-cursor-test.txt    human-readable summary table
#   /tmp/muse-test-NNN.png            HUD screenshot per character (NNN = index)
#
# Muse is a Hammerspoon-owned canvas — it doesn't need a host app. The synthetic
# keystrokes are consumed by Muse's input eventtap before they reach whatever
# happens to be focused.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

RUNNER="$(dirname "$0")/_muse_text_cursor_runner.lua"
OUT_JSON="/tmp/muse-text-cursor-test.json"
OUT_SUMMARY="/tmp/muse-text-cursor-test.txt"
DONE_FLAG="/tmp/muse-text-cursor-test.done"
TEST_STRING="${MUSE_TEST_STRING:-the quick brown fox jumps over the lazy dog 123!}"
STEP_DELAY="${MUSE_STEP_DELAY:-0.12}"
INPUT_FILE="/tmp/muse-text-cursor-input.txt"

teardown() {
  # Close the HUD if the runner was interrupted mid-flight.
  "$HS_BIN" -c "local M=package.loaded['Muse']; if not M or not M.start then return end; local function up(fn) local i=1 while true do local n,v=debug.getupvalue(fn,i); if not n then return nil end if n=='close' then return v end if n=='onFlags' then local j=1 while true do local nn,vv=debug.getupvalue(v,j); if not nn then break end if nn=='close' then return vv end j=j+1 end end i=i+1 end end; local cl=up(M.start); if cl then pcall(cl) end" >/dev/null 2>&1 || true
  rm -f "$INPUT_FILE"
}
trap teardown EXIT

# Sanity: Muse must be loaded.
loaded="$("$HS_BIN" -c "return package.loaded['Muse'] and 'yes' or 'no'" 2>/dev/null | tail -n1)"
if [ "$loaded" != "yes" ]; then
  echo "Muse module is not loaded in Hammerspoon. Reload after enabling require('Muse')." >&2
  exit 1
fi

rm -f "$OUT_JSON" "$OUT_SUMMARY" "$DONE_FLAG"
# /tmp/muse-test-NNN.png cleaned by the Lua runner itself.

# Pass the test string via a file (avoids bash-quoting-into-Lua headaches with
# punctuation or non-ASCII characters).
printf '%s' "$TEST_STRING" > "$INPUT_FILE"

"$HS_BIN" -c "do local f=io.open('$INPUT_FILE','r'); local s=f:read('*a'); f:close(); _G.MUSE_TEST={ testString=s, stepDelay=$STEP_DELAY } end; dofile('$RUNNER')" >/dev/null

# Wait for the runner. Budget: per-step delay × chars, with generous slack for
# capture overhead and the final JSON/summary write.
char_count=$(awk -v s="$TEST_STRING" 'BEGIN{print length(s)}')
budget=$(awk -v c="$char_count" -v d="$STEP_DELAY" 'BEGIN{print int(c*(d+0.10) + 15)}')
wait_until "[ -f \"$DONE_FLAG\" ]" "$budget" "muse runner to finish"

echo
cat "$OUT_SUMMARY"
echo
echo "JSON:        $OUT_JSON"
echo "Summary:     $OUT_SUMMARY"
echo "Screenshots: /tmp/muse-test-*.png  ($((char_count + 1)) frames)"
echo "PASS: muse_text_cursor_capture"
