#!/usr/bin/env bash
# Unit-sim tests for MenuMaestro's usage-data layer, priority scoring, and
# shortcut glyph rendering.

set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

run_lua_sim "menumaestro_usage_data" \
    "$(dirname "$0")/_usage_data_sim.lua" \
    "/tmp/menumaestro-sim.log"
