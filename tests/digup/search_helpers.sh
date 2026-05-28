#!/usr/bin/env bash
# Unit-sim tests for DigUp's pure search helpers (extractSnippet, etc.).
# Deeper integration (DB roundtrip, capture pixel-diff, OCR queue) is left
# for separate tests when needed.

set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

run_lua_sim "digup_search_helpers" \
    "$(dirname "$0")/_search_helpers_sim.lua" \
    "/tmp/digup-sim.log"
