#!/usr/bin/env bash
# Sources from outline tests. Provides setup_textedit_window which leaves
# exactly one standard, non-dialog TextEdit window parked away from screen
# edges, focused, and returns its hs.window id on stdout.

# Requires _lib.sh to already be sourced (hsx, wait_until, launch_app).

setup_textedit_window() {
  local bundle="${1:-com.apple.TextEdit}"

  launch_app "$bundle"
  # TextEdit often launches with an "Abrir" / "Open" dialog and zero document
  # windows. Drive it to exactly one standard untitled doc.
  hsx "
    local app = hs.application.get('$bundle')
    if not app then return 'no-app' end
    app:activate()
    -- Close any non-standard windows (Abrir/open dialog, etc.)
    for _, w in ipairs(app:allWindows()) do
      if not w:isStandard() then w:close() end
    end
    hs.timer.usleep(200000)
    -- Close extras past the first standard window.
    local std = {}
    for _, w in ipairs(app:allWindows()) do
      if w:isStandard() then table.insert(std, w) end
    end
    for i = 2, #std do std[i]:close() end
    if #std == 0 then
      hs.eventtap.keyStroke({'cmd'}, 'n')
      hs.timer.usleep(500000)
    end
    return 'ok'
  " >/dev/null

  # Wait until at least one standard window exists.
  wait_until "[ \"\$(hsx \"
    local app = hs.application.get('$bundle')
    if not app then return 'no' end
    for _, w in ipairs(app:allWindows()) do
      if w:isStandard() then return 'yes' end
    end
    return 'no'
  \")\" = \"yes\" ]" 5 "standard TextEdit window exists"

  # Park it away from edges, focus, return id.
  hsx "
    local app = hs.application.get('$bundle')
    local target
    for _, w in ipairs(app:allWindows()) do
      if w:isStandard() then target = w; break end
    end
    if not target then return 'no-std' end
    local sf = hs.screen.mainScreen():frame()
    target:setFrame({x = sf.x + 200, y = sf.y + 200, w = 400, h = 300})
    target:focus()
    return tostring(target:id())
  "
}
