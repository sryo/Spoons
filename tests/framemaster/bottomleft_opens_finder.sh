#!/usr/bin/env bash
# FrameMaster: clicking the bottom-left hot corner (no modifier) opens a new
# Finder window via AppleScript.
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

before=0

teardown() {
  hsx "
    local f = hs.application.get('com.apple.finder')
    if f then
      f:activate()
      hs.timer.usleep(150000)
      local wins = f:allWindows()
      if #wins > $before then
        wins[1]:close()
      end
    end
    return 'ok'
  " >/dev/null 2>&1 || true
  global_teardown
}
trap teardown EXIT

# 1. Capture initial Finder window count (Finder is system-managed, usually running).
before=$(window_count "com.apple.finder")
before=${before:-0}

# 2. Capture screen frame.
frame=$(hsx "local f=hs.screen.mainScreen():frame(); return string.format('%d,%d,%d,%d', f.x, f.y, f.w, f.h)")
IFS=',' read -r sx sy sw sh <<< "$frame"

# 3. Warp to bottom-left corner (0, sh-1) and click. FrameMaster runs the
#    bottomLeft action (new Finder window via AppleScript).
hsx "hs.mouse.absolutePosition({x=$((sx + 1)), y=$((sy + sh - 1))}); return 'ok'" >/dev/null
sleep 0.05
hsx "local p=hs.mouse.absolutePosition(); hs.eventtap.leftClick(p); return 'ok'" >/dev/null

# 4. Finder window count should grow.
wait_until "[ \"\$(window_count 'com.apple.finder')\" -gt \"$before\" ]" 5 "Finder window count grew"

echo "PASS: framemaster_bottomleft_opens_finder"
