#!/usr/bin/env bash
# Runs Palette.textbuffer caret-math tests via _textbuffer_sim.lua.

set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

SIM="$(dirname "$0")/_textbuffer_sim.lua"
LOG="/tmp/palette-textbuffer.log"

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
  echo "PASS: palette_textbuffer ($result)"
  exit 0
fi

echo "FAIL: palette_textbuffer ($result)"
[ -f "$LOG" ] && cat "$LOG"
exit 1
