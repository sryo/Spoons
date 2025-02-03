-- WindowScape: https://github.com/sryo/Spoons/blob/main/WindowScape.lua
-- This script automatically tiles windows.

local window = require("hs.window")
local screen = require("hs.screen")
local geometry = require("hs.geometry")
local drawing = require("hs.drawing")
local spaces = require("hs.spaces")
local mouse = require("hs.mouse")
local eventtap = require("hs.eventtap")
local timer = require("hs.timer")

local activeWindowOutline = nil
local outlineColor = { red = .1, green = .3, blue = .9, alpha = 0.8 }
local outlineThickness = 16
local tileGap = 0
local collapsedWindowHeight = 12
local mods = { "ctrl", "cmd" }
local spaceMods = { "ctrl", "cmd", "option" }
local enableTTTaps = true

local whitelistMode = false -- Set to true to tile only the windows in the whitelist

local whitelistedApps = {}
local whitelistFile = "whitelist.txt"

local windowOrderBySpace = {}

local function log(message)
    --print(os.date("%Y-%m-%d %H:%M:%S") .. " [WindowScape] " .. message)
end

local ttTaps

local function saveWhitelistToFile()
    local file = io.open(whitelistFile, "w")
    for app in pairs(whitelistedApps) do
        file:write(app .. "\n")
    end
    file:close()
end

local function loadWhitelistFromFile()
    local file = io.open(whitelistFile, "r")
    if not file then
        whitelistedApps["org.hammerspoon.Hammerspoon"] = true
        saveWhitelistToFile()
        return
    end
    for line in file:lines() do
        whitelistedApps[line] = true
    end
    file:close()
end

loadWhitelistFromFile()

local function isAppWhitelisted(app, win)
    local bundleID = app and app:bundleID()
    local appName = app:name()
    local isInWhitelist = whitelistedApps[bundleID] or whitelistedApps[appName]

    return win:isStandard() and ((whitelistMode and isInWhitelist) or (not whitelistMode and not isInWhitelist))
end

local function getScreenOrientation()
    local mainScreen = screen.mainScreen()
    local mainScreenSize = mainScreen:frame().size

    if mainScreenSize.w > mainScreenSize.h then
        return "horizontal"
    else
        return "vertical"
    end
end

local function getCurrentSpace()
    return spaces.focusedSpace()
end

local function getVisibleWindows()
    local visibleWindows = {}
    local currentSpace = getCurrentSpace()
    local allScreens = screen.allScreens()
    local windowsByScreen = {}

    for _, scr in ipairs(allScreens) do
        windowsByScreen[scr:id()] = {}
    end

    for _, win in ipairs(window.visibleWindows()) do
        if spaces.windowSpaces(win) and
            hs.fnutils.contains(spaces.windowSpaces(win), currentSpace) and
            not win:isFullScreen() and
            isAppWhitelisted(win:application(), win) then
            local winScreen = win:screen()
            if winScreen then
                local screenId = winScreen:id()
                table.insert(windowsByScreen[screenId], win)
            end
        end
    end

    for _, scr in ipairs(allScreens) do
        local screenId = scr:id()
        local screenWindows = windowsByScreen[screenId]

        if windowOrderBySpace[currentSpace] then
            local orderedScreenWindows = {}
            for _, orderedWin in ipairs(windowOrderBySpace[currentSpace]) do
                if hs.fnutils.contains(screenWindows, orderedWin) then
                    table.insert(orderedScreenWindows, orderedWin)
                end
            end
            for _, win in ipairs(screenWindows) do
                if not hs.fnutils.contains(orderedScreenWindows, win) then
                    table.insert(orderedScreenWindows, win)
                end
            end
            screenWindows = orderedScreenWindows
        end

        for _, win in ipairs(screenWindows) do
            table.insert(visibleWindows, win)
        end
    end

    return visibleWindows
end

local function updateWindowOrder()
    local currentSpace = getCurrentSpace()
    local currentWindows = getVisibleWindows()
    local newOrder = {}

    if windowOrderBySpace[currentSpace] then
        for _, win in ipairs(windowOrderBySpace[currentSpace]) do
            if hs.fnutils.contains(currentWindows, win) then
                table.insert(newOrder, win)
            end
        end
    end

    for _, win in ipairs(currentWindows) do
        if not hs.fnutils.contains(newOrder, win) then
            table.insert(newOrder, win)
        end
    end

    windowOrderBySpace[currentSpace] = newOrder
end

local function getCollapsedWindows(visibleWindows)
    local collapsedWindows = {}
    for _, win in ipairs(visibleWindows) do
        if win:size().h <= collapsedWindowHeight then
            table.insert(collapsedWindows, win)
        end
    end
    return collapsedWindows
end

local function tileWindows()
    updateWindowOrder()
    local currentSpace = getCurrentSpace()
    local allScreens = screen.allScreens()

    for _, scr in ipairs(allScreens) do
        local screenFrame = scr:frame()
        local screenWindows = {}

        for _, win in ipairs(windowOrderBySpace[currentSpace] or {}) do
            if win:screen():id() == scr:id() then
                table.insert(screenWindows, win)
            end
        end

        if #screenWindows == 0 then
            goto continue
        end

        local orientation = screenFrame.w > screenFrame.h and "horizontal" or "vertical"

        screenWindows = hs.fnutils.filter(screenWindows, function(win)
            return not win:isFullScreen()
        end)

        local collapsedWindows = getCollapsedWindows(screenWindows)
        local nonCollapsedWindows = #screenWindows - #collapsedWindows

        -- Calculate tile dimensions based on screen orientation
        local tileWidth, tileHeight
        if orientation == "horizontal" then
            tileWidth = (screenFrame.w - (nonCollapsedWindows - 1) * tileGap) / nonCollapsedWindows
            tileHeight = screenFrame.h - (#collapsedWindows > 0 and collapsedWindowHeight + tileGap or 0)
        else
            tileWidth = screenFrame.w
            tileHeight = (screenFrame.h - (#collapsedWindows > 0 and (#collapsedWindows * (collapsedWindowHeight + tileGap) - tileGap) or 0) - (nonCollapsedWindows - 1) * tileGap) /
                nonCollapsedWindows
        end

        local nonCollapsedWinX, nonCollapsedWinY = screenFrame.x, screenFrame.y
        local collapsedWinX = screenFrame.x
        local collapsedWinY = orientation == "horizontal"
            and screenFrame.y + screenFrame.h - collapsedWindowHeight
            or screenFrame.y + screenFrame.h - (#collapsedWindows * (collapsedWindowHeight + tileGap))

        for _, win in ipairs(screenWindows) do
            local isCollapsed = win:size().h <= collapsedWindowHeight
            local newFrame

            if isCollapsed then
                newFrame = {
                    x = collapsedWinX,
                    y = collapsedWinY,
                    w = orientation == "horizontal" and tileWidth or screenFrame.w,
                    h = collapsedWindowHeight
                }
                if orientation == "horizontal" then
                    collapsedWinX = collapsedWinX + tileWidth + tileGap
                else
                    collapsedWinY = collapsedWinY + collapsedWindowHeight + tileGap
                end
            else
                newFrame = {
                    x = nonCollapsedWinX,
                    y = nonCollapsedWinY,
                    w = tileWidth,
                    h = tileHeight
                }
                if orientation == "horizontal" then
                    nonCollapsedWinX = nonCollapsedWinX + tileWidth + tileGap
                else
                    nonCollapsedWinY = nonCollapsedWinY + tileHeight + tileGap
                end
            end

            win:setFrame(geometry.rect(newFrame), 0)
        end

        ::continue::
    end
end

local function isSystem(win)
    return win and (win:role() == "AXScrollArea" or win:subrole() == "AXSystemDialog")
end

local function getTargetScreen(x, y)
    for _, scr in ipairs(screen.allScreens()) do
        local frame = scr:frame()
        if x >= frame.x and x < frame.x + frame.w and
            y >= frame.y and y < frame.y + frame.h then
            return scr
        end
    end
    return nil
end

local function drawActiveWindowOutline(win)
    if win and win:isVisible() and not win:isFullScreen() and not isSystem(win) then
        local frame = win:frame()
        local adjustedFrame = {
            x = frame.x,
            y = frame.y,
            w = frame.w,
            h = frame.h
        }

        if not activeWindowOutline then
            activeWindowOutline = drawing.rectangle(geometry.rect(adjustedFrame))
            activeWindowOutline:setStrokeColor(outlineColor)
            activeWindowOutline:setFill(false)
            activeWindowOutline:setStrokeWidth(outlineThickness)
            activeWindowOutline:setRoundedRectRadii(outlineThickness / 2, outlineThickness / 2)
            activeWindowOutline:setLevel(drawing.windowLevels.floating)
        else
            activeWindowOutline:setFrame(geometry.rect(adjustedFrame))
        end

        activeWindowOutline:show()
    else
        if activeWindowOutline then
            activeWindowOutline:hide()
        end
    end
end

local function handleWindowFocused(win)
    if win and win:isVisible() and not win:isFullScreen() and not isSystem(win) then
        if isAppWhitelisted(win:application(), win) then
            tileWindows()
        end
        drawActiveWindowOutline(win)
    else
        if activeWindowOutline then
            activeWindowOutline:hide()
        end
    end
end

local function handleWindowEvent()
    updateWindowOrder()
    hs.timer.doAfter(0.1, function()
        tileWindows()
        local focusedWindow = window.focusedWindow()
        if focusedWindow then
            drawActiveWindowOutline(focusedWindow)
        end
    end)
end

local function toggleFocusedWindowInWhitelist()
    local focusedWindow = window.focusedWindow()
    if focusedWindow:isFullScreen() then
        return
    end

    local focusedApp = focusedWindow:application()
    local bundleID = focusedApp:bundleID()
    local appName = focusedApp:name()

    if whitelistedApps[bundleID] or whitelistedApps[appName] then
        whitelistedApps[bundleID] = nil
        whitelistedApps[appName] = nil
    else
        whitelistedApps[bundleID] = true
    end

    saveWhitelistToFile()
    updateWindowOrder()
    tileWindows()
end

local function moveMouseWithWindow(oldFrame, newFrame)
    local mousePos = mouse.getAbsolutePosition()
    if geometry.isPointInRect(mousePos, oldFrame) then
        local relX = (mousePos.x - oldFrame.x) / oldFrame.w
        local relY = (mousePos.y - oldFrame.y) / oldFrame.h
        local newX = newFrame.x + (relX * newFrame.w)
        local newY = newFrame.y + (relY * newFrame.h)
        mouse.setAbsolutePosition({ x = newX, y = newY })
    end
end

local function moveWindowInOrder(direction)
    local currentSpace = getCurrentSpace()
    local focusedWindow = window.focusedWindow()
    local currentOrder = windowOrderBySpace[currentSpace] or {}
    local focusedIndex
    local nonCollapsedWindows = {}

    for i, win in ipairs(currentOrder) do
        if win:size().h > collapsedWindowHeight then
            table.insert(nonCollapsedWindows, win)
            if win:id() == focusedWindow:id() then
                focusedIndex = #nonCollapsedWindows
            end
        end
    end

    if not focusedIndex then
        updateWindowOrder()
        return
    end

    local newIndex
    if direction == "forward" then
        newIndex = focusedIndex < #nonCollapsedWindows and focusedIndex + 1 or 1
    else -- backward
        newIndex = focusedIndex > 1 and focusedIndex - 1 or #nonCollapsedWindows
    end

    table.remove(nonCollapsedWindows, focusedIndex)
    table.insert(nonCollapsedWindows, newIndex, focusedWindow)

    local newOrder = {}
    local nonCollapsedIndex = 1
    for _, win in ipairs(currentOrder) do
        if win:size().h <= collapsedWindowHeight then
            table.insert(newOrder, win)
        else
            table.insert(newOrder, nonCollapsedWindows[nonCollapsedIndex])
            nonCollapsedIndex = nonCollapsedIndex + 1
        end
    end

    local oldFrame = focusedWindow:frame()
    windowOrderBySpace[currentSpace] = newOrder
    tileWindows()
    focusedWindow:focus()
    local newFrame = focusedWindow:frame()
    moveMouseWithWindow(oldFrame, newFrame)
end

local function moveWindowToAdjacentSpace(direction)
    local focusedWindow = window.focusedWindow()
    if not focusedWindow then return end

    local oldFrame = focusedWindow:frame()
    local currentScreen = focusedWindow:screen()
    local currentSpace = getCurrentSpace()

    local screenSpaces = spaces.allSpaces()[currentScreen:getUUID()]
    if not screenSpaces then return end

    local currentSpaceIndex = hs.fnutils.indexOf(screenSpaces, currentSpace)
    if not currentSpaceIndex then return end

    local targetSpaceIndex
    if direction == "next" then
        targetSpaceIndex = currentSpaceIndex % #screenSpaces + 1
    else
        targetSpaceIndex = (currentSpaceIndex - 2 + #screenSpaces) % #screenSpaces + 1
    end

    local targetSpace = screenSpaces[targetSpaceIndex]

    -- Update window orders
    local currentIndex = hs.fnutils.indexOf(windowOrderBySpace[currentSpace], focusedWindow)
    if currentIndex then
        table.remove(windowOrderBySpace[currentSpace], currentIndex)
    end

    if not windowOrderBySpace[targetSpace] then
        windowOrderBySpace[targetSpace] = {}
    end

    spaces.moveWindowToSpace(focusedWindow, targetSpace)
    table.insert(windowOrderBySpace[targetSpace], focusedWindow)

    hs.timer.doAfter(0.2, function()
        if focusedWindow:isVisible() then
            focusedWindow:focus()
            local newFrame = focusedWindow:frame()
            moveMouseWithWindow(oldFrame, newFrame)
        end

        hs.timer.doAfter(0.2, tileWindows)
    end)
end

local initialFingerCount = 0
local gestureStartTime = 0
local lastActionTime = 0
local gestureStartThreshold = 0.005
local lastTouchCount = 0
local initialTouchPositions = {}

local function handleTTTaps(event)
    local eventType = event:getType(true)

    if eventType ~= hs.eventtap.event.types.gesture then
        return false
    end

    local touchDetails = event:getTouchDetails()
    if not touchDetails then
        return false
    end

    if touchDetails.pressure then
        return false
    end

    local touches = event:getTouches()
    local touchCount = touches and #touches or 0
    local currentTime = hs.timer.secondsSinceEpoch()

    if touchCount == 0 and lastTouchCount <= initialFingerCount then
        if initialFingerCount > 0 then
            log("Gesture ended")
            initialFingerCount = 0
            gestureStartTime = 0
            initialTouchPositions = {}
        end
        lastTouchCount = 0
        return false
    end

    if initialFingerCount == 0 then
        if touchCount == 3 or touchCount == 4 then
            initialFingerCount = touchCount
            gestureStartTime = currentTime
            for i = 1, touchCount do
                initialTouchPositions[i] = touches[i].normalizedPosition.x
            end
            log("Gesture started with " .. initialFingerCount .. " fingers")
        end
    elseif touchCount >= initialFingerCount and gestureStartTime then
        if touchCount == initialFingerCount + 1 and currentTime - gestureStartTime > gestureStartThreshold then
            local additionalFingerPosition
            for i = 1, touchCount do
                local found = false
                for j = 1, initialFingerCount do
                    if initialTouchPositions[j] and math.abs(touches[i].normalizedPosition.x - initialTouchPositions[j]) < 0.1 then
                        found = true
                        break
                    end
                end
                if not found then
                    additionalFingerPosition = touches[i].normalizedPosition.x
                    break
                end
            end

            if additionalFingerPosition then
                local side = additionalFingerPosition <= 0.5 and "left" or "right"

                if currentTime - lastActionTime > 0.5 then
                    log(initialFingerCount .. "-finger gesture detected, additional finger on the " .. side)

                    if initialFingerCount == 3 then
                        if side == "left" then
                            log("Executing: Move window to previous position in order")
                            moveWindowInOrder("backward")
                        else
                            log("Executing: Move window to next position in order")
                            moveWindowInOrder("forward")
                        end
                    elseif initialFingerCount == 4 then
                        if side == "left" then
                            log("Executing: Move window to adjacent space on the left")
                            moveWindowToAdjacentSpace("previous")
                        else
                            log("Executing: Move window to adjacent space on the right")
                            moveWindowToAdjacentSpace("next")
                        end
                    end

                    lastActionTime = currentTime
                end
            end
        end
    elseif touchCount < initialFingerCount then

        log("Finger(s) lifted, but gesture continues")
    end

    lastTouchCount = touchCount
    return true
end

local function startTTTapsRecognition()
    if not enableTTTaps then
        log("TTTaps recognition is disabled")
        return
    end

    if ttTaps then
        ttTaps:stop()
    end

    ttTaps = eventtap.new({ eventtap.event.types.gesture }, handleTTTaps)
    ttTaps:start()
    log("TTTaps recognition started")
end

local function stopTTTapsRecognition()
    if ttTaps then
        ttTaps:stop()
        ttTaps = nil
        log("TTTaps recognition stopped")
    end
end

local function checkTTTapsRecognition()
    if not enableTTTaps then
        return
    end

    if not ttTaps or not ttTaps:isEnabled() then
        log("TTTaps recognition was stopped, restarting...")
        startTTTapsRecognition()
    end
end

local initialFocusedWindow = window.focusedWindow()
if initialFocusedWindow then
    drawActiveWindowOutline(initialFocusedWindow)
end

local function bindHotkeys()
    hs.hotkey.bind(mods, "<", function()
        toggleFocusedWindowInWhitelist()
    end)
    hs.hotkey.bind(mods, "Left", function()
        moveWindowInOrder("backward")
    end)
    hs.hotkey.bind(mods, "Right", function()
        moveWindowInOrder("forward")
    end)
    hs.hotkey.bind(spaceMods, "Left", function()
        moveWindowToAdjacentSpace("previous")
    end)
    hs.hotkey.bind(spaceMods, "Right", function()
        moveWindowToAdjacentSpace("next")
    end)

    if enableTTTaps then
        startTTTapsRecognition()
        hs.timer.doEvery(300, checkTTTapsRecognition) -- Check every 5 minutes
    end
end

local function handleWindowDestroyed(win)
    updateWindowOrder()
    tileWindows()
    local newFocusedWindow = window.focusedWindow()
    if newFocusedWindow then
        handleWindowFocused(newFocusedWindow)
    else
        if activeWindowOutline then
            activeWindowOutline:hide()
        end
    end
end

window.filter.default:subscribe({
    window.filter.windowCreated,
    window.filter.windowHidden,
    window.filter.windowUnhidden,
    window.filter.windowMinimized,
    window.filter.windowUnminimized,
    window.filter.windowMoved,
    window.filter.windowsChanged
}, handleWindowEvent)

window.filter.default:subscribe(window.filter.windowDestroyed, handleWindowDestroyed)
window.filter.default:subscribe(window.filter.windowFocused, handleWindowFocused)

spaces.watcher.new(function(space)
    handleWindowEvent()
end):start()

local function preventGC()
    if enableTTTaps then
        if ttTaps then
            log("TTTaps recognition is active")
        else
            log("TTTaps recognition is not active")
        end
    else
        log("TTTaps recognition is disabled")
    end
end

hs.timer.doEvery(3600, preventGC) -- Run every hour to keep the script alive and log status

updateWindowOrder()
tileWindows()
bindHotkeys()

log("WindowScape initialized" ..
    (enableTTTaps and " with TTTaps recognition" or " without TTTaps recognition") .. " and auto-focus enabled")

function restartWindowScapeTTTaps()
    if enableTTTaps then
        stopTTTapsRecognition()
        startTTTapsRecognition()
        log("WindowScape TTTaps recognition manually restarted")
    else
        log("TTTaps recognition is disabled, cannot restart")
    end
end
