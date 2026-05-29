#!/usr/bin/env bash
# outline.draw(win) early-exits when the window is fullscreen and hides the
# active canvas. Exiting fullscreen restores it.
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"
source "$(dirname "$0")/_textedit_window.sh"

PEEK="$(dirname "$0")/_introspect.lua"
APP="com.apple.TextEdit"

teardown() {
  hsx "
    local ok, fs = pcall(require, 'WindowScape.fullscreen')
    if ok and fs.getState and fs.getState().active then fs.exit() end
    return 'ok'
  " >/dev/null 2>&1 || true
  steve quit "$APP" >/dev/null 2>&1 || true
  global_teardown
}
trap teardown EXIT

windowscape_reset
winId="$(setup_textedit_window "$APP")"

hsx "require('WindowScape.outline').draw(hs.window.get($winId)); return 'ok'" >/dev/null
wait_until "[ \"\$(hsx \"local i=dofile('$PEEK'); return tostring(i.showing())\")\" = \"true\" ]" 3 "outline initially visible"

hsx "require('WindowScape.fullscreen').enter(hs.window.get($winId)); return 'ok'" >/dev/null

# Simulated fullscreen is synchronous; outline should hide promptly.
wait_until "[ \"\$(hsx \"local i=dofile('$PEEK'); return tostring(i.showing())\")\" = \"false\" ]" 3 "outline hidden in fullscreen"

hsx "require('WindowScape.fullscreen').exit(); return 'ok'" >/dev/null
hsx "require('WindowScape.outline').draw(hs.window.get($winId)); return 'ok'" >/dev/null

wait_until "[ \"\$(hsx \"local i=dofile('$PEEK'); return tostring(i.showing())\")\" = \"true\" ]" 3 "outline returns after fullscreen exit"

echo "PASS: outline_hides_for_fullscreen"
