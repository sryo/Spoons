-- This script defines hot corners with their actions and messages.

local hotCorners = {
    topLeft = {
        action = function() hs.window.focusedWindow():close() end,
        message = function()
            local window = hs.window.focusedWindow()
            return "Close " .. (window and window:title() or "Window")
        end
    },
    topRight = {
        action = function() hs.eventtap.keyStroke({"ctrl", "cmd"}, "F") end,
        message = function()
            local window = hs.window.focusedWindow()
            return "Toggle Fullscreen for " .. (window and window:title() or "Window")
        end
    },
    bottomRight = {
        action = function() hs.window.focusedWindow():minimize() end,
        message = function()
            local window = hs.window.focusedWindow()
            return "Minimize " .. (window and window:title() or "Window")
        end
    },
}

local lastTooltipTime = 0
local lastCorner = nil

local screenSize = hs.screen.mainScreen():fullFrame()
function checkForHotCorner(x, y)
    return (x <= 4 and y <= 4 and "topLeft") or (x >= screenSize.w - 4 and y <= 4 and "topRight") or (x >= screenSize.w - 4 and y >= screenSize.h - 4 and "bottomRight")
end

function showTooltip(corner)
    local currentTime = hs.timer.secondsSinceEpoch()
    if currentTime - lastTooltipTime >= 1 then
        hs.alert.show(hotCorners[corner].message(), 1)
        lastTooltipTime = currentTime
    end
end

mouseEventTap = hs.eventtap.new({hs.eventtap.event.types.mouseMoved}, function(event)
    local point = hs.mouse.getAbsolutePosition()
    lastCorner = checkForHotCorner(point.x, point.y)
    if lastCorner then showTooltip(lastCorner) end
end):start()

cornerEventTap = hs.eventtap.new({hs.eventtap.event.types.leftMouseDown}, function(event)
    if lastCorner then
        hotCorners[lastCorner].action()
        return true
    end
    return false
end):start()
