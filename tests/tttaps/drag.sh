#!/usr/bin/env bash
# Drives the TTTaps drag recognizer through synthetic event sequences.

set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

SIM="$(dirname "$0")/_drag_sim.lua"
LOG="/tmp/tttaps-drag-sim.log"

loaded="$(hsx "return package.loaded['TTTaps'] and 'yes' or 'no'")"
if [ "$loaded" != "yes" ]; then
  echo "TTTaps module not loaded in Hammerspoon" >&2
  exit 2
fi

run_lua_sim "tttaps_drag" "$SIM" "$LOG"
