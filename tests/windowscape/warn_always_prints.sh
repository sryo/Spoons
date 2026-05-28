#!/usr/bin/env bash
# core.warn must print regardless of cfg.debugLogging. Captures print output
# via a temporary global override so the assertion is robust whether or not
# the writer reaches Hammerspoon's in-memory console buffer.
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

teardown() {
  hsx "require('WindowScape.config').cfg.debugLogging = false; return 'ok'" >/dev/null 2>&1 || true
  global_teardown
}
trap teardown EXIT

marker="ws_warn_marker_$$"

# debugLogging off; capture print; call warn; restore print.
captured=$(hsx "
  require('WindowScape.config').cfg.debugLogging = false
  local lines = {}
  local original_print = print
  _G.print = function(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[i] = tostring((select(i, ...))) end
    table.insert(lines, table.concat(parts, '\t'))
  end
  local ok, err = pcall(function() require('WindowScape.core').warn('$marker') end)
  _G.print = original_print
  if not ok then return 'pcall-error: ' .. tostring(err) end
  return table.concat(lines, '|||')
")

# Marker must appear in the captured output.
case "$captured" in
  *"$marker"*) ;;
  *) echo "FAIL: marker not present. captured=[$captured]" >&2; exit 1 ;;
esac

# Format: line should include the [WindowScape] prefix.
case "$captured" in
  *"[WindowScape] $marker"*) ;;
  *) echo "FAIL: missing [WindowScape] prefix. captured=[$captured]" >&2; exit 1 ;;
esac

echo "PASS: warn_always_prints"
