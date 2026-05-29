#!/usr/bin/env bash
# outline.hide() immediately hides the canvas. Verifies the explicit hide
# path used by snapshot/fullscreen flows in events.lua.
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"
source "$(dirname "$0")/_textedit_window.sh"

PEEK="$(dirname "$0")/_introspect.lua"
APP="com.apple.TextEdit"

teardown() {
  steve quit "$APP" >/dev/null 2>&1 || true
  global_teardown
}
trap teardown EXIT

windowscape_reset
winId="$(setup_textedit_window "$APP")"

hsx "
  local w = hs.window.get($winId)
  require('WindowScape.outline').draw(w)
  return 'ok'
" >/dev/null

wait_until "[ \"\$(hsx \"local i=dofile('$PEEK'); return tostring(i.showing())\")\" = \"true\" ]" 3 "outline visible before hide"

# Call hide() and check it took effect within the same hs -c call so events.lua
# can't race in and re-show it.
showing_after_hide="$(hsx "
  require('WindowScape.outline').hide()
  local i = dofile('$PEEK')
  return tostring(i.showing())
")"
expect_eq "$showing_after_hide" "false" "outline hidden after hide()"

echo "PASS: outline_hides_on_focus_loss"
