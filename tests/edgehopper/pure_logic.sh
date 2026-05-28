#!/usr/bin/env bash
# Unit-sim tests for EdgeHopper's pure logic (edge detection, corner exclusion,
# multi-monitor adjacency, wrap positioning, pressure decay). Complements the
# integration tests in this directory that drive real mouse movement.

set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

run_lua_sim "edgehopper_pure_logic" \
    "$(dirname "$0")/_pure_logic_sim.lua" \
    "/tmp/edgehopper-sim.log"
