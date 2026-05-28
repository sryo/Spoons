#!/usr/bin/env bash
# Drives the WindowScape gesture recognizer through synthetic event sequences
# via _gestures_sim.lua. No physical trackpad input needed: the Lua simulator
# constructs mock gesture events and feeds them straight to the handler through
# its _test hooks.

set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

SIM="$(dirname "$0")/_gestures_sim.lua"
LOG="/tmp/wsg-gesture-sim.log"

# Sanity: WindowScape.gestures must be loaded in the live Hammerspoon.
loaded="$(hsx "return package.loaded['WindowScape.gestures'] and 'yes' or 'no'")"
if [ "$loaded" != "yes" ]; then
  echo "WindowScape.gestures module not loaded in Hammerspoon" >&2
  exit 2
fi

rm -f "$LOG"
result="$(hsx "return dofile('$SIM')")"

if [ -z "$result" ] || [[ ! "$result" =~ ^[0-9]+/[0-9]+$ ]]; then
  echo "FAIL: simulator returned unexpected output: '$result'"
  [ -f "$LOG" ] && cat "$LOG"
  exit 1
fi

passed="${result%%/*}"
total="${result##*/}"

if [ "$passed" = "$total" ]; then
  echo "PASS: windowscape_gestures ($result)"
  exit 0
fi

echo "FAIL: windowscape_gestures ($result)"
[ -f "$LOG" ] && cat "$LOG"
exit 1
