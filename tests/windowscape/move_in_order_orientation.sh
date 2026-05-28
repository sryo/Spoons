#!/usr/bin/env bash
# Drives the orientation simulator for operations.moveWindowInOrder. Verifies
# that the swap target is picked by visual position (X on landscape, Y on
# portrait), wraps at edges, only touches the focused screen, and preserves
# collapsed-window slots.

set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

SIM="$(dirname "$0")/_move_in_order_sim.lua"
LOG="/tmp/wsg-mvio-sim.log"

loaded="$(hsx "return package.loaded['WindowScape.operations'] and 'yes' or 'no'")"
if [ "$loaded" != "yes" ]; then
  echo "WindowScape.operations module not loaded in Hammerspoon" >&2
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
  echo "PASS: windowscape_move_in_order_orientation ($result)"
  exit 0
fi

echo "FAIL: windowscape_move_in_order_orientation ($result)"
[ -f "$LOG" ] && cat "$LOG"
exit 1
