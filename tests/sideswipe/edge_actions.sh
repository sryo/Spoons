#!/usr/bin/env bash
# Unit-sim tests for SideSwipe edge sliders, value mapping, and audio device targeting.

set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

run_lua_sim "sideswipe" \
    "$(dirname "$0")/_edge_actions_sim.lua" \
    "/tmp/sideswipe-sim.log"
