#!/usr/bin/env bash
# Live ZXNav trace: drive the running ZXNav eventtap with N key sequences
# against TextEdit and print, per scenario, the input → actual-text it
# produced. Goal: surface every case where a stray space character leaks.
#
# Run directly to watch the trace live:
#   bash tests/zxnav/space_leak.sh
#
# Or via the suite (use -v so the trace prints on success):
#   bash tests/run.sh -v tests/zxnav/space_leak.sh
#
# Exit code: 0 if every scenario matched its expectation, 1 otherwise.

set -uo pipefail
source "$(dirname "$0")/../_lib.sh"

APP="com.apple.TextEdit"
GAP="${GAP:-0.05}"      # delay between individual CGEvent posts
SETTLE="${SETTLE:-0.30}" # post-sequence wait so the deferred space timer in ZXNav can fire

teardown() {
  hsx "local ok,m=pcall(require,'ZXNav'); if ok and m.kill then m.kill() end; return 'ok'" >/dev/null 2>&1 || true
  steve quit "$APP" >/dev/null 2>&1 || true
  global_teardown
}
trap teardown EXIT

# --- ZXNav must be running -----------------------------------------------------

state=$(hsx "
  local ok, m = pcall(require, 'ZXNav')
  if not ok then return 'no-module' end
  if not m._downWatcher or not m._downWatcher.isEnabled or not m._downWatcher:isEnabled() then
    if m.start then m.start() end
    return 'started'
  end
  return 'already-running'
")
echo "ZXNav: $state"
if [ "$state" = "no-module" ]; then
  echo "FAIL: ZXNav module not loadable" >&2
  exit 1
fi

# --- TextEdit setup ------------------------------------------------------------

launch_app "$APP"
seed_single_window_app "$APP"
hsx "hs.application.get('$APP'):mainWindow():focus(); return 'ok'" >/dev/null
sleep 0.3

# --- Helpers -------------------------------------------------------------------

# post <key-name> <down|up>
post() {
  local key="$1" dir="$2" bool="false"
  [ "$dir" = "down" ] && bool="true"
  hsx "hs.eventtap.event.newKeyEvent({}, '$key', $bool):post(); return 'ok'" >/dev/null
}

clear_doc() {
  osascript -e "tell application \"TextEdit\" to set text of document 1 to \"\"" >/dev/null 2>&1 || true
  sleep 0.1
}

read_doc() {
  hsx "
    local app = hs.application.get('$APP')
    if not app then return '' end
    local win = app:focusedWindow() or app:mainWindow()
    if not win then return '' end
    local ax = hs.axuielement.windowElement(win)
    local function find(el)
      if not el then return nil end
      local role = el:attributeValue('AXRole')
      if role == 'AXTextArea' or role == 'AXTextField' then
        return el:attributeValue('AXValue')
      end
      local kids = el:attributeValue('AXChildren')
      if kids then for _,k in ipairs(kids) do local v=find(k); if v then return v end end end
      return nil
    end
    return tostring(find(ax) or '')
  "
}

PASS=0
FAIL=0
LEAKS=()

# row <id> <label> <sequence> <mode> <expected-or-flag> <actual>
# mode = "exact" | "trailing" | "no-trailing"
row() {
  local id="$1" label="$2" seq="$3" mode="$4" want="$5" got="$6"
  local qgot verdict
  qgot=$(printf '%q' "$got")
  case "$mode" in
    exact)
      if [ "$got" = "$want" ]; then verdict="PASS"; PASS=$((PASS+1))
      else verdict="FAIL — wanted $(printf '%q' "$want")"; FAIL=$((FAIL+1)); LEAKS+=("[$id] $label"); fi ;;
    no-trailing)
      if [[ "$got" == *" " ]]; then verdict="FAIL — trailing space leaked"; FAIL=$((FAIL+1)); LEAKS+=("[$id] $label")
      else verdict="PASS"; PASS=$((PASS+1)); fi ;;
    trailing)
      if [[ "$got" == *" " ]]; then verdict="PASS"; PASS=$((PASS+1))
      else verdict="FAIL — expected trailing space"; FAIL=$((FAIL+1)); LEAKS+=("[$id] $label"); fi ;;
  esac
  printf '[%s] %s\n    sequence: %s\n    actual:   %s\n    %s\n\n' "$id" "$label" "$seq" "$qgot" "$verdict"
}

# --- Scenarios -----------------------------------------------------------------

# 1. Baseline: a lone space tap should produce a space.
clear_doc
post space down; sleep $GAP
post space up;   sleep $SETTLE
row 1 "tap space alone" "v space ^ space" "exact" " " "$(read_doc)"

# 2. Baseline: two quick spaces.
clear_doc
post space down; sleep $GAP
post space up;   sleep $GAP
post space down; sleep $GAP
post space up;   sleep $SETTLE
row 2 "two quick spaces" "v sp ^ sp v sp ^ sp" "exact" "  " "$(read_doc)"

# 3. Mapped nav (B = Left arrow) on empty doc: no character should be typed.
clear_doc
post space down; sleep $GAP
post b down;     sleep $GAP
post b up;       sleep $GAP
post space up;   sleep $SETTLE
row 3 "space+B (mapped Left) on empty doc" "v sp v b ^ b ^ sp" "exact" "" "$(read_doc)"

# 4-6. Hold space, tap UNMAPPED key(s). Expects a trailing space: ZXNav no
# longer cancels the lone-space synthesis on non-mapped keys, because doing so
# ate spaces during fast typing where the next letter's keyDown overlaps with
# space still held. Trade-off: intentional "space + unmapped" produces both.
clear_doc
post space down; sleep $GAP
post a down;     sleep $GAP
post a up;       sleep $GAP
post space up;   sleep $SETTLE
row 4 "space + unmapped 'a'" "v sp v a ^ a ^ sp" "trailing" "" "$(read_doc)"

# 5. Hold space, tap UNMAPPED digit '1'.
clear_doc
post space down; sleep $GAP
post 1 down;     sleep $GAP
post 1 up;       sleep $GAP
post space up;   sleep $SETTLE
row 5 "space + unmapped '1'" "v sp v 1 ^ 1 ^ sp" "trailing" "" "$(read_doc)"

# 6. Hold space, tap TWO unmapped letters.
clear_doc
post space down; sleep $GAP
post a down;     sleep $GAP
post a up;       sleep $GAP
post q down;     sleep $GAP
post q up;       sleep $GAP
post space up;   sleep $SETTLE
row 6 "space + 'a' + 'q' (both unmapped)" "v sp v a ^ a v q ^ q ^ sp" "trailing" "" "$(read_doc)"

# 7. Release space BEFORE the mapped key — asymmetric STOP/GO at lines 426/430.
clear_doc
post space down; sleep $GAP
post b down;     sleep $GAP
post space up;   sleep $GAP
post b up;       sleep $SETTLE
row 7 "space+B, release space first" "v sp v b ^ sp ^ b" "no-trailing" "" "$(read_doc)"

# 8. Release mapped key BEFORE space — the canonical clean path.
clear_doc
post space down; sleep $GAP
post b down;     sleep $GAP
post b up;       sleep $GAP
post space up;   sleep $SETTLE
row 8 "space+B, release B first (clean path)" "v sp v b ^ b ^ sp" "exact" "" "$(read_doc)"

# 9. Pre-type 'hello', use space+Z (Home) to move cursor, space+M (FwdDel) to drop 'h'.
clear_doc
hsx "hs.eventtap.keyStrokes('hello'); return 'ok'" >/dev/null
sleep 0.20
post space down; sleep $GAP
post z down;     sleep $GAP
post z up;       sleep $GAP
post space up;   sleep $SETTLE
post space down; sleep $GAP
post m down;     sleep $GAP
post m up;       sleep $GAP
post space up;   sleep $SETTLE
got=$(read_doc)
# TextEdit may auto-capitalize start-of-line; accept ello / Ello.
if [ "$got" = "ello" ] || [ "$got" = "Ello" ]; then
  row 9 "hello + space+Z (Home) + space+M (FwdDel)" "v sp v z ^ z ^ sp v sp v m ^ m ^ sp" "exact" "$got" "$got"
else
  row 9 "hello + space+Z (Home) + space+M (FwdDel)" "v sp v z ^ z ^ sp v sp v m ^ m ^ sp" "exact" "ello" "$got"
fi

# 10. Cmd+Space: ZXNav's handleKeyDown early-returns when other modifiers are
#     held (line 332). Spotlight (or whatever Cmd+Space is bound to) may open;
#     we dismiss with Escape and verify TextEdit's content didn't grow a space.
clear_doc
hsx "
  hs.eventtap.event.newKeyEvent({'cmd'}, 'space', true):post()
  hs.timer.usleep(50000)
  hs.eventtap.event.newKeyEvent({'cmd'}, 'space', false):post()
  return 'ok'
" >/dev/null
sleep 0.4
hsx "hs.eventtap.keyStroke({}, 'escape'); return 'ok'" >/dev/null
sleep 0.2
hsx "local a=hs.application.get('$APP'); if a then a:activate() end; return 'ok'" >/dev/null
sleep 0.2
row 10 "Cmd+Space (other modifier held)" "v cmd+sp ^ cmd+sp" "no-trailing" "" "$(read_doc)"

# --- Summary -------------------------------------------------------------------

echo "── summary ──"
echo "$PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  printf 'leaks:\n'
  for l in "${LEAKS[@]}"; do printf '  %s\n' "$l"; done
  exit 1
fi
