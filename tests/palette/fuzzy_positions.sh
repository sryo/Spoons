#!/usr/bin/env bash
# Verifies the new matcher returns matched character indices that the canvas
# bolding code consumes.

set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

SIM="$(dirname "$0")/_fuzzy_positions_sim.lua"
LOG="/tmp/palette-fuzzy-positions.log"

run_lua_sim "palette_fuzzy_positions" "$SIM" "$LOG"
