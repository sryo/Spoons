-- This script stops the menu bar and dock from appearing when you move your mouse close.

local killMenu = true           -- prevent the menu bar from appearing
local killDock = true           -- prevent the dock from appearing
local onlyFullscreen = true     -- but only on fullscreen spaces
local buffer = 4                -- increase if you still manage to activate them

ev_tap = hs.eventtap.new({hs.eventtap.event.types.mouseMoved}, function(e)
    local win = hs.window.focusedWindow()
    local screenHeight = win:screen():fullFrame().h
    if onlyFullscreen and win and win:isFullScreen() then
        if killMenu and e:location().y < buffer then
            hs.console.printStyledtext("🔪🍔 Menu bar killed")
            return true
        elseif killDock and (screenHeight - e:location().y) < buffer then
            hs.console.printStyledtext("🔪🚢 Dock killed")
            return true
        end
    end
    return false
end):start()
