local hotCorners = {
    topLeft = {
        action = function()
            local window = hs.window.focusedWindow()
            local title = window and window:title() or "Window"
            window:close()
            return "Closed " .. title
        end,
        message = "Close current window"
    },
    topRight = {
        action = function()
            local window = hs.window.focusedWindow()
            local title = window and window:title() or "Window"
            hs.eventtap.keyStroke({"ctrl", "cmd"}, "F")
            return "Toggled Fullscreen for " .. title
        end,
        message = "Toggle Fullscreen for current window"
    },
    bottomRight = {
        action = function()
            local window = hs.window.focusedWindow()
            local title = window and window:title() or "Window"
            window:minimize()
            return "Minimized " .. title
        end,
        message = "Minimize current window"
    },
    bottomLeft = {
        action = function()
            local app = hs.application.frontmostApplication()
            local appName = app and app:name() or "App"
            app:kill()
            return "Killed " .. appName
        end,
        message = "Kill current application"
    }
}

local lastCorner = nil
local lastTooltipTime = 0

local screenSize = hs.screen.mainScreen():currentMode()

function updateScreenSize()
    screenSize = hs.screen.mainScreen():currentMode()
end

updateScreenSize()

local screenWatcher = hs.screen.watcher.newWithActiveScreen(updateScreenSize)
screenWatcher:start()

function checkForHotCorner(x, y)
    return (x <= 4 and y <= 4 and "topLeft") or (x >= screenSize.w - 4 and y <= 4 and "topRight") or 
           (x >= screenSize.w - 4 and y >= screenSize.h - 4 and "bottomRight") or 
           (x <= 4 and y >= screenSize.h - 4 and "bottomLeft")
end

function showTooltip(corner)
    local currentTime = hs.timer.secondsSinceEpoch()
    if currentTime - lastTooltipTime >= 1 then
        hs.alert.show(hotCorners[corner].message, 1)
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
        local message = hotCorners[lastCorner].action()
        hs.alert.show(message, 1)
        return true
    end
    return false
end):start()
