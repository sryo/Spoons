#!/usr/bin/env bash
# core.log is silent when cfg.debugLogging is false, prints when true.
# Captures the global print() to make the assertion independent of whether
# the writer reaches Hammerspoon's in-memory console buffer.
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

teardown() {
  hsx "require('WindowScape.config').cfg.debugLogging = false; return 'ok'" >/dev/null 2>&1 || true
  global_teardown
}
trap teardown EXIT

marker_off="ws_log_off_$$"
marker_on="ws_log_on_$$"

run_capture() {
  # $1: marker, $2: 'true'|'false' for debugLogging
  local m="$1" flag="$2"
  hsx "
    require('WindowScape.config').cfg.debugLogging = $flag
    local lines = {}
    local original_print = print
    _G.print = function(...)
      local parts = {}
      for i = 1, select('#', ...) do parts[i] = tostring((select(i, ...))) end
      table.insert(lines, table.concat(parts, '\t'))
    end
    local ok, err = pcall(function() require('WindowScape.core').log('$m') end)
    _G.print = original_print
    if not ok then return 'pcall-error: ' .. tostring(err) end
    return table.concat(lines, '|||')
  "
}

# Phase A: debugLogging=false, marker must NOT be captured.
captured_off=$(run_capture "$marker_off" "false")
case "$captured_off" in
  *"$marker_off"*) echo "FAIL: log fired when debugLogging=false. captured=[$captured_off]" >&2; exit 1 ;;
  *) ;;
esac

# Phase B: debugLogging=true, marker MUST be captured.
captured_on=$(run_capture "$marker_on" "true")
case "$captured_on" in
  *"$marker_on"*) ;;
  *) echo "FAIL: log silent when debugLogging=true. captured=[$captured_on]" >&2; exit 1 ;;
esac

echo "PASS: log_gated_by_debug_flag"
