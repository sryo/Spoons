#!/usr/bin/env bash
# Drives the WanderFocus focus-decision sim with mocked hs.mouse/window/AX.

set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

SIM="$(dirname "$0")/_focus_sim.lua"
LOG="/tmp/wanderfocus-focus-sim.log"

loaded="$(hsx "return package.loaded['WanderFocus'] and 'yes' or 'no'")"
if [ "$loaded" != "yes" ]; then
  echo "WanderFocus module not loaded in Hammerspoon" >&2
  exit 2
fi

run_lua_sim "wanderfocus_focus" "$SIM" "$LOG"
