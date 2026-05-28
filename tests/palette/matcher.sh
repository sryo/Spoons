#!/usr/bin/env bash
# Runs the deterministic matcher tests (Palette.matcher.rank) via
# _matcher_sim.lua. Stubs recents.score to isolate ranking behaviour.

set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

SIM="$(dirname "$0")/_matcher_sim.lua"
LOG="/tmp/palette-matcher.log"

loaded="$(hsx "return package.loaded['Palette.matcher'] and 'yes' or 'no'")"
if [ "$loaded" != "yes" ]; then
  echo "Palette.matcher not loaded in Hammerspoon" >&2
  exit 2
fi

rm -f "$LOG"
result="$(hsx "return dofile('$SIM')")"

if [ -z "$result" ] || [[ ! "$result" =~ ^[0-9]+/[0-9]+$ ]]; then
  echo "FAIL: simulator returned unexpected output: '$result'"
  [ -f "$LOG" ] && cat "$LOG"
  exit 1
fi

passed="${result%%/*}"
total="${result##*/}"

if [ "$passed" = "$total" ]; then
  echo "PASS: palette_matcher ($result)"
  exit 0
fi

echo "FAIL: palette_matcher ($result)"
[ -f "$LOG" ] && cat "$LOG"
exit 1
