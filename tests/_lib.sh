#!/usr/bin/env bash
# Shared helpers for tests under ~/.hammerspoon/tests/.
# Source from any test: source "$(dirname "$0")/../_lib.sh"

HS_BIN="${HS_BIN:-/usr/local/bin/hs}"

# -- Core primitives -----------------------------------------------------------

hsx() {
  # Wrap the user's Lua in a function so `return` works, and have the wrapper
  # return a sentinel-bracketed string. `hs -c` only echoes the chunk's return
  # value to stdout (io.write is dropped), so the sentinels reliably identify
  # our payload even when concurrent event handlers print noise.
  #
  # `|| true` keeps `set -e` happy when `hs -c` exits non-zero (e.g. with a
  # "receive timeout" on a long-running chunk: the Lua still completes inside
  # Hammerspoon; we just don't get a return value for that call).
  local out
  out="$("$HS_BIN" -c "local _v = (function() $1 end)(); return '<<<HSX>>>' .. tostring(_v) .. '<<<END>>>'" 2>&1)" || true
  printf '%s' "$out" | grep -oE '<<<HSX>>>.*<<<END>>>' | head -n1 | sed -e 's/^<<<HSX>>>//' -e 's/<<<END>>>$//'
}

expect_eq() {
  if [ "$1" != "$2" ]; then
    echo "assertion failed: $3: got '$1', want '$2'" >&2
    return 1
  fi
}

# wait_until <expr> <timeout-secs> <label> [<interval-secs>]
# Polls <expr> until it returns 0 or <timeout> elapses. Default interval 0.1s.
wait_until() {
  local expr="$1" timeout="$2" label="$3" interval="${4:-0.1}"
  local elapsed=0 max_ticks
  max_ticks="$(awk -v t="$timeout" -v i="$interval" 'BEGIN{ printf "%d", t / i }')"
  while ! eval "$expr"; do
    if [ "$elapsed" -ge "$max_ticks" ]; then
      echo "timeout after ${timeout}s waiting for: $label" >&2
      return 1
    fi
    sleep "$interval"
    elapsed=$((elapsed + 1))
  done
}

teardown_quit() {
  steve quit "$1" >/dev/null 2>&1 || true
}

# -- Lua sim runner ------------------------------------------------------------

# run_lua_sim <name> <sim_lua_path> <log_path>
# Drives a unit-sim Lua file via `hsx` and reports PASS/FAIL based on its
# "N/M" return value. On failure, dumps the sim's log.
run_lua_sim() {
  local name="$1" sim="$2" log="$3"
  rm -f "$log"
  local result
  result="$(hsx "return dofile('$sim')")"
  if [ -z "$result" ] || ! [[ "$result" =~ ^[0-9]+/[0-9]+$ ]]; then
    echo "FAIL: $name (unexpected output: '$result')"
    [ -f "$log" ] && cat "$log"
    return 1
  fi
  local passed="${result%%/*}" total="${result##*/}"
  if [ "$passed" = "$total" ]; then
    echo "PASS: $name ($result)"
    return 0
  fi
  echo "FAIL: $name ($result)"
  [ -f "$log" ] && cat "$log"
  return 1
}

# -- App / window setup --------------------------------------------------------

# launch_app <bundle-id> [<unused>]
# Launch app via steve, wait until hs.application.get(bundle) is registered.
# Always resolve by bundle id (localized app names break the lookup).
launch_app() {
  local bundle="$1"
  steve launch "$bundle" >/dev/null 2>&1 || true
  wait_until "[ \"\$(hsx \"return hs.application.get('$bundle') and 'yes' or 'no'\")\" = \"yes\" ]" 5 "app '$bundle' registered"
}

# window_count <bundle-id-or-name>
window_count() {
  hsx "local a=hs.application.get('$1'); return a and #a:allWindows() or 0"
}

# wait_window_count <app> <n> [<timeout>]
wait_window_count() {
  local app="$1" want="$2" timeout="${3:-5}"
  wait_until "[ \"\$(window_count '$app')\" = \"$want\" ]" "$timeout" "$app window count = $want"
}

# seed_windows <bundle-id-or-name> <count>
# Drive the app to have exactly <count> windows. Closes extras, opens missing.
# Multiple short hsx calls beats one long one because hs CLI has a short
# receive timeout for blocking Lua chunks.
seed_windows() {
  local app="$1" want="$2"
  # Activate the app so cmd+n is delivered to it.
  hsx "local a=hs.application.get('$app'); if a then a:activate() end; return 'ok'" >/dev/null
  # Close any windows beyond the target count.
  hsx "
    local a = hs.application.get('$app')
    if not a then return 'no-app' end
    local wins = a:allWindows()
    for i = $want + 1, #wins do wins[i]:close() end
    return tostring(#a:allWindows())
  " >/dev/null
  # Open new windows one at a time until we hit the target.
  local have
  have="$(window_count "$app")"
  while [ "$have" -lt "$want" ]; do
    hsx "hs.application.get('$app'):activate(); hs.eventtap.keyStroke({'cmd'}, 'n'); return 'ok'" >/dev/null
    sleep 0.15
    local new_count
    new_count="$(window_count "$app")"
    if [ "$new_count" = "$have" ]; then
      sleep 0.25
      new_count="$(window_count "$app")"
    fi
    have="$new_count"
  done
  wait_window_count "$app" "$want" 5
}

# seed_single_window_app <app>
seed_single_window_app() {
  seed_windows "$1" 1
}

# -- Input synthesis -----------------------------------------------------------

# click_with_modifier <mod> <x> <y>
# Hold modifier ('shift','cmd','alt','ctrl'), leftClick(x,y), release.
click_with_modifier() {
  local mod="$1" x="$2" y="$3"
  hsx "
    hs.eventtap.event.newKeyEvent('$mod', true):post()
    hs.timer.usleep(50000)
    hs.mouse.absolutePosition({x=$x, y=$y})
    hs.timer.usleep(20000)
    hs.eventtap.leftClick({x=$x, y=$y})
    hs.timer.usleep(20000)
    hs.eventtap.event.newKeyEvent('$mod', false):post()
    return 'ok'
  " >/dev/null
}

# -- HTTP (for CloudPad tests) -------------------------------------------------

http_get() {
  curl -sS -m 5 "$1"
}

http_post_json() {
  curl -sS -m 5 -X POST -H 'Content-Type: application/json' -d "$2" "$1"
}

# -- State reset --------------------------------------------------------------

# windowscape_reset
# Exit fullscreen, clear snapshots, reset weights/focusHistory/tilingCount.
windowscape_reset() {
  hsx "
    local ok, core = pcall(require, 'WindowScape.core')
    if not ok then return 'no-core' end
    local _, snap = pcall(require, 'WindowScape.snapshots')
    local _, fs   = pcall(require, 'WindowScape.fullscreen')
    if fs and fs.getState and fs.getState().active then fs.exit() end
    if snap and snap.clearAll then snap.clearAll() end
    core.windowWeights = {}
    core.focusHistory  = {}
    core.tilingCount   = 0
    return 'ok'
  " >/dev/null
}

# global_teardown
# Call in every test's teardown() before steve quit.
global_teardown() {
  windowscape_reset
  hsx "
    -- Release any held modifiers (in case a test crashed mid-modifier)
    for _, m in ipairs({'shift','cmd','alt','ctrl'}) do
      hs.eventtap.event.newKeyEvent(m, false):post()
    end
    -- Recenter cursor so next test starts from neutral position
    local s = hs.screen.mainScreen():frame()
    hs.mouse.absolutePosition({x = s.x + s.w/2, y = s.y + s.h/2})
    if hs.console and hs.console.clearConsole then hs.console.clearConsole() end
    return 'ok'
  " >/dev/null 2>&1 || true
}

# -- Diagnostics --------------------------------------------------------------

dump_diagnostics() {
  local label="${1:-diagnostics}"
  {
    echo "[DIAGNOSTICS: $label]"
    echo "  focused window:  $(hsx "local w=hs.window.focusedWindow(); return w and (w:title()..' ['..(w:application():name() or '?')..']') or 'none'" 2>/dev/null)"
    echo "  mouse position:  $(hsx "local p=hs.mouse.absolutePosition(); return string.format('%d,%d', p.x, p.y)" 2>/dev/null)"
    echo "  ws fullscreen:   $(hsx "local ok,fs=pcall(require,'WindowScape.fullscreen'); return ok and fs.getState().active and 'yes' or 'no'" 2>/dev/null)"
    echo "  ws snapshots:    $(hsx "local ok,s=pcall(require,'WindowScape.snapshots'); return ok and #s.getState().order or '?'" 2>/dev/null)"
    echo "  screens:         $(hsx "return #hs.screen.allScreens()" 2>/dev/null)"
  } >&2
}
