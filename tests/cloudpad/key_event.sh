#!/usr/bin/env bash
# CloudPad: POST /events with a key payload sends a keystroke that reaches the
# focused app. We verify by reading TextEdit's text area via AX.
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

APP="com.apple.TextEdit"

teardown() {
  steve quit "$APP" >/dev/null 2>&1 || true
  global_teardown
}
trap teardown EXIT

# 1. CloudPad must be running.
hsx "if not require('CloudPad').isRunning() then require('CloudPad').start({port=1984}) end; return 'ok'" >/dev/null
url=$(hsx "return require('CloudPad').url")
wait_until "http_get '$url/health' >/dev/null 2>&1" 3 "/health responsive"

# 2. Launch TextEdit, focus it, clear any content.
launch_app "$APP"
seed_single_window_app "$APP"
hsx "hs.application.get('$APP'):mainWindow():focus(); return 'ok'" >/dev/null
sleep 0.2
hsx "hs.eventtap.keyStroke({'cmd'}, 'a'); hs.timer.usleep(100000); hs.eventtap.keyStroke({}, 'delete'); return 'ok'" >/dev/null
sleep 0.2

# 3. Post a single key event ('a' with no mods).
body=$(http_post_json "$url/events" '{"events":[{"t":"key","key":"a","mods":[]}]}')

# 4. Server reports drained.
if ! echo "$body" | grep -q '"drained":1\|"drained": 1'; then
  echo "FAIL: drained:1 expected, got: $body" >&2
  exit 1
fi

# 5. TextEdit's AXValue should be exactly "a" (ignoring whitespace).
wait_until '
  cur=$(hsx "
    local app = hs.application.get(\"com.apple.TextEdit\")
    if not app then return \"\" end
    local win = app:focusedWindow() or app:mainWindow()
    if not win then return \"\" end
    local ax = hs.axuielement.windowElement(win)
    local function find(el)
      if not el then return nil end
      local role = el:attributeValue(\"AXRole\")
      if role == \"AXTextArea\" or role == \"AXTextField\" then
        return el:attributeValue(\"AXValue\")
      end
      local kids = el:attributeValue(\"AXChildren\")
      if kids then for _,k in ipairs(kids) do local v=find(k); if v then return v end end end
      return nil
    end
    return tostring(find(ax) or \"\")
  ")
  [ "$(echo -n "$cur" | tr -d "[:space:]")" = "a" ]
' 3 "TextEdit contains a"

echo "PASS: cloudpad_key_event"
