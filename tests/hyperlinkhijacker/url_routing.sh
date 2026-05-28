#!/usr/bin/env bash
# Unit-sim tests for HyperlinkHijacker URL routing and chooser ordering.

set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

run_lua_sim "hyperlinkhijacker" \
    "$(dirname "$0")/_url_routing_sim.lua" \
    "/tmp/hyperlinkhijacker-sim.log"
