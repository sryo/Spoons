-- This script defines hot corners with their actions for managing the currently selected window.

local showTooltips = true -- set this to false to improve performance if necessary.

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

local function isDesktop()
    local window = hs.window.focusedWindow()
    return window and window:role() == "AXScrollArea"
end

local hotCorners = {
    topLeft = {
        action = function()
            local window = hs.window.focusedWindow()
            if not window or isDesktop() then return "No action" end
            local title, message = getWindowTitle("Closed")
            window:close()
            -- Switch to the next window
            local nextWindow = hs.window.orderedWindows()[2]
            if nextWindow then nextWindow:focus() end
            return message
        end,
        message = function()
            local _, message = getWindowTitle("Close")
            return message
        end
    },
    topRight = {
        action = function()
            local window = hs.window.focusedWindow()
            if not window or isDesktop() then return "No action" end
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
            local window = hs.window.focusedWindow()
            if not window or isDesktop() then return "No action" end
            local title, message = getWindowTitle("Minimized")
            window:minimize()
            return message
        end,
        message = function()
            local _, message = getWindowTitle("Minimize")
            return message
        end
    },
    bottomLeft = {
        action = function()
            local app = hs.application.frontmostApplication()
            if not app then return "No action" end
            local appName, message = getAppName("Killed")
            app:kill()
            return message
        end,
        message = function()
            local _, message = getAppName("Kill")
            return message
        end
    }
}

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

local lastTooltipCorner = nil

function showTooltip(corner)
    if corner ~= lastTooltipCorner then
        hs.alert.show(hotCorners[corner].message(), 1)
        lastTooltipCorner = corner
    end
end

if showTooltips then
    mouseEventTap = hs.eventtap.new({hs.eventtap.event.types.mouseMoved}, function(event)
        local point = hs.mouse.getAbsolutePosition()
        lastCorner = checkForHotCorner(point.x, point.y)
        if lastCorner and not isDesktop() then showTooltip(lastCorner) end
    end):start()
end

cornerEventTap = hs.eventtap.new({hs.eventtap.event.types.leftMouseDown}, function(event)
    if lastCorner and not isDesktop() then
        local message = hotCorners[lastCorner].action()
        hs.alert.show(message, 1)
        return true
    end
    return false
end):start()
