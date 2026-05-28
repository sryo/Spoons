#!/usr/bin/env bash
# Unit-sim tests for ZXNav's chord state machine (space+key remapping,
# modifier rejection, multi-key tracking, space pass-through).

set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

run_lua_sim "zxnav_chord_remap" \
    "$(dirname "$0")/_chord_remap_sim.lua" \
    "/tmp/zxnav-sim.log"
