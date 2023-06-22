local function getWindowTitle(cornerAction)
    local window = hs.window.focusedWindow()
    local title = window and window:title() or "Window"
    return title, cornerAction .. " " .. title
end

local function getAppName(cornerAction)
    local app = hs.application.frontmostApplication()
    local appName = app and app:name() or "App"
    return appName, cornerAction .. " " .. appName
end

local hotCorners = {
    topLeft = {
        action = function()
            local title, message = getWindowTitle("Closed")
            hs.window.focusedWindow():close()
            return message
        end,
        message = function()
            local _, message = getWindowTitle("Close")
            return message
        end
    },
    topRight = {
        action = function()
            local title, message = getWindowTitle("Toggled Fullscreen for")
            hs.eventtap.keyStroke({"ctrl", "cmd"}, "F")
            return message
        end,
        message = function()
            local _, message = getWindowTitle("Toggle Fullscreen for")
            return message
        end
    },
    bottomRight = {
        action = function()
            local title, message = getWindowTitle("Minimized")
            hs.window.focusedWindow():minimize()
            return message
        end,
        message = function()
            local _, message = getWindowTitle("Minimize")
            return message
        end
    },
    bottomLeft = {
        action = function()
            local appName, message = getAppName("Killed")
            hs.application.frontmostApplication():kill()
            return message
        end,
        message = function()
            local _, message = getAppName("Kill")
            return message
        end
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
        local message = hotCorners[lastCorner].action()
        hs.alert.show(message, 1)
        return true
    end
    return false
end):start()
