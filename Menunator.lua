-- This script stops the menu bar and dock from reappearing when you move your mouse close.

local killMenu = true           -- prevent the menu bar from appearing
local killDock = true           -- prevent the dock from appearing
local onlyFullscreen = true     -- but only on fullscreen spaces
local buffer = 4                -- increase if you still manage to activate them

hs.hotkey.bind({"cmd", "alt", "ctrl"}, "D", function()
    if ev_tap:isEnabled() then
      ev_tap:stop()
      hs.alert.show("Menunator OFF: They live!")
    else
      ev_tap:start()
      hs.alert.show("Menunator ON: They're dead.")
    end
  end)

function getDockPosition()
    local handle = io.popen("defaults read com.apple.dock orientation")
    local result = handle:read("*a")
    handle:close()
    return result:gsub("^%s*(.-)%s*$", "%1")
end

local dockPos = getDockPosition()

ev_tap = hs.eventtap.new({hs.eventtap.event.types.mouseMoved}, function(e)
    local win = hs.window.focusedWindow()
    local screenFrame = win:screen():fullFrame()
    local screenHeight = screenFrame.h
    local screenWidth = screenFrame.w

    if onlyFullscreen and win and win:isFullScreen() then
        if killMenu and e:location().y < buffer then
            hs.console.printStyledtext("🔪🍔 Menu bar killed")
            return true
        elseif killDock then
            if dockPos == "bottom" and (screenHeight - e:location().y) < buffer then
                hs.console.printStyledtext("🔪🚢 Dock killed")
                return true
            elseif dockPos == "left" and e:location().x < buffer then
                hs.console.printStyledtext("🔪🚢 Dock killed")
                return true
            elseif dockPos == "right" and (screenWidth - e:location().x) < buffer then
                hs.console.printStyledtext("🔪🚢 Dock killed")
                return true
            end
        end
    end
    return false
end):start()
