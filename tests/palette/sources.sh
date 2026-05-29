#!/usr/bin/env bash
# Covers calc, shellrunner, and files sources. Hits the modules with synthetic
# queries and asserts their emitted items.

set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

SIM="$(dirname "$0")/_sources_sim.lua"
LOG="/tmp/palette-sources.log"

run_lua_sim "palette_sources" "$SIM" "$LOG"
