-- Take control of your Mac's 'hot corners', menu bar, and dock.

local killMenu = true           -- prevent the menu bar from appearing
local killDock = true           -- prevent the dock from appearing
local onlyFullscreen = true     -- but only on fullscreen spaces
local buffer = 4                -- increase if you still manage to activate them
local showTooltips = true       -- set this to false to improve performance if necessary.

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

local function getDockPosition()
    local handle = io.popen("defaults read com.apple.dock orientation")
    local result = handle:read("*a")
    handle:close()
    return result:gsub("^%s*(.-)%s*$", "%1")
end

local dockPos = getDockPosition()

local hotCorners = {
    topLeft = {
        action = function()
            local window = hs.window.focusedWindow()
            if not window or isDesktop() then return "No action" end
            local title, message = getWindowTitle("Closed")
            window:close()
            local nextWindow = hs.window.orderedWindows()[2]
            if nextWindow then 
                print("Focusing next window") 
                nextWindow:focus() 
            else 
                print("Focusing desktop") 
            end
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
            if not window or isDesktop() or window:isFullScreen() then return "No action" end
            local title, message = getWindowTitle("Minimized")
            window:minimize()
            return message
        end,
        message = function()
            local window = hs.window.focusedWindow()
            if not window or isDesktop() or window:isFullScreen() then return "" end
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

local screenSize = nil

function setupScreen()
    local function updateScreenSize()
        screenSize = hs.screen.mainScreen():currentMode()
    end

    updateScreenSize()

    local screenWatcher = hs.screen.watcher.newWithActiveScreen(updateScreenSize)
    screenWatcher:start()

    local loginWatcher = hs.caffeinate.watcher.new(function(event)
        if event == hs.caffeinate.watcher.screensDidUnlock or event == hs.caffeinate.watcher.systemDidWake then
            print("Screen unlocked or system woke up")
            updateScreenSize()
        end
    end)
    loginWatcher:start()

    local wakeWatcher = hs.screen.watcher.new(function(event)
        if event == hs.screen.watcher.screenDidWake then
            print("Screen woke up")
            updateScreenSize()
        end
    end)
    wakeWatcher:start()
end

setupScreen()

function checkForHotCorner(x, y)
    updateScreenSize()
    return ((x <= 1 and y <= buffer) and "topLeft") or 
           ((x >= screenSize.w - 1 and y <= buffer) and "topRight") or 
           ((x >= screenSize.w - 1 and y >= screenSize.h - buffer) and "bottomRight") or 
           ((x <= 1 and y >= screenSize.h - buffer) and "bottomLeft")
end

function showTooltip(corner)
    if corner ~= lastTooltipCorner or hs.timer.secondsSinceEpoch() - lastTooltipTime >= 1 then
        local message = hotCorners[corner].message()
        if message ~= "" then
            hs.alert.show(message, 1)
            lastTooltipTime = hs.timer.secondsSinceEpoch()
            lastTooltipCorner = corner
        end
    end
end

cornerEventTap = hs.eventtap.new({hs.eventtap.event.types.leftMouseDown}, function(event)
    if lastCorner and not isDesktop() then
        print("Clicked in corner: " .. lastCorner)
        local message = hotCorners[lastCorner].action()
        hs.alert.show(message, 1)
        return true
    end
    return false
end):start()

if showTooltips then
    tooltipEventTap = hs.eventtap.new({hs.eventtap.event.types.mouseMoved}, function(event)
        local point = hs.mouse.getAbsolutePosition()
        lastCorner = checkForHotCorner(point.x, point.y)
        if lastCorner and not isDesktop() then 
            print("Hit corner: " .. lastCorner) 
            showTooltip(lastCorner) 
        end

        local win = hs.window.focusedWindow()
        local screenFrame = win and win:screen():fullFrame()
        local screenHeight = screenFrame and screenFrame.h
        local screenWidth = screenFrame and screenFrame.w

        if onlyFullscreen and win and win:isFullScreen() then
            if killMenu and event:location().y < buffer and (event:location().x > buffer and event:location().x < screenWidth - buffer) then
                print("Preventing menubar from appearing")
                return true
            elseif killDock then
                if dockPos == "bottom" and (screenHeight - event:location().y) < buffer and (event:location().x > buffer and event:location().x < screenWidth - buffer) then
                    print("Preventing dock from appearing")
                    return true
                elseif dockPos == "left" and event:location().x < buffer and (event:location().y > buffer and event:location().y < screenHeight - buffer) then
                    print("Preventing dock from appearing bottomLeft")
                    return true
                elseif dockPos == "right" and (screenWidth - event:location().x) < buffer and (event:location().y > buffer and event:location().y < screenHeight - buffer) then
                    print("Preventing dock from appearing bottomRight")
                    return true
                end
            end
        end

        return false
    end):start()
end

cornerClickEventTap = hs.eventtap.new({hs.eventtap.event.types.leftMouseDown}, function(event)
    local point = hs.mouse.getAbsolutePosition()
    lastCorner = checkForHotCorner(point.x, point.y)
    if lastCorner and not isDesktop() then
        print("Clicked in corner: " .. lastCorner)
        local message = hotCorners[lastCorner].action()
        hs.alert.show(message, 1)
        return true
    end
    return false
end):start()
