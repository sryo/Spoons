-- WindowScape: https://github.com/sryo/Spoons/blob/main/WindowScape.lua
-- This script automatically tiles windows.

local window              = require("hs.window")
local screen              = require("hs.screen")
local geometry            = require("hs.geometry")
local drawing             = require("hs.drawing")
local spaces              = require("hs.spaces")
local mouse               = require("hs.mouse")
local eventtap            = require("hs.eventtap")
local timer               = require("hs.timer")
local json                = require("hs.json")
local hotkey              = require("hs.hotkey")

local cfg                 = {
    outlineColor          = { red = .1, green = .3, blue = .9, alpha = 0.8 },
    outlineThickness      = 16,
    tileGap               = 0,
    collapsedWindowHeight = 12,
    mods                  = { "ctrl", "cmd" },
    screenMods            = { "ctrl", "cmd", "option" },
    enableTTTaps          = true,
    -- true = apps in list are EXCLUDED from tiling (deny list)
    -- false = apps in list are INCLUDED for tiling (allow list)
    exclusionMode         = true,
    -- Debounce for bursty window events
    eventDebounceSeconds  = 0.075,
}

local activeWindowOutline = nil
local ttTaps              = nil
local outlineRefreshTimer = nil
local lastOutlineFrame    = nil
local trackedFocusedWinId = nil
local outlineHideCounter  = 0    -- Counter to prevent hiding on momentary visibility glitches

-- Drag tracking state
local tilingCount         = 0   -- Counter to distinguish our moves from user drags (handles overlapping tiles)
local pendingReposition   = nil -- Timer for delayed reposition check


local listedApps          = {}  -- bundleIDs or app names
local listPath            = hs.configdir .. "/WindowScape_apps.json"

local windowOrderBySpace  = {}
local windowWeights       = {} -- windowId -> weight (default 1.0)

local function log(message)
    -- Debug logging enabled
    print(os.date("%Y-%m-%d %H:%M:%S") .. " [WindowScape] " .. message)
end

local function getCurrentSpace()
    return spaces.focusedSpace()
end

-- Prune windowOrderBySpace to remove stale space entries
local function pruneStaleSpaces()
    local allSpaces = spaces.allSpaces()
    if not allSpaces then return end

    -- Build set of valid space IDs
    local validSpaces = {}
    for _, screenSpaces in pairs(allSpaces) do
        for _, spaceId in ipairs(screenSpaces) do
            validSpaces[spaceId] = true
        end
    end

    -- Remove entries for spaces that no longer exist
    for spaceId in pairs(windowOrderBySpace) do
        if not validSpaces[spaceId] then
            windowOrderBySpace[spaceId] = nil
            log("Pruned stale space: " .. tostring(spaceId))
        end
    end
end

local function saveList()
    -- Remove existing file first (hs.json.write doesn't overwrite)
    os.remove(listPath)
    local ok, err = json.write(listedApps, listPath, true)
    if not ok then log("Failed to save app list: " .. tostring(err)) end
end

local function loadList()
    listedApps = json.read(listPath) or {}
    if next(listedApps) == nil then
        -- Default: don't tile Hammerspoon itself
        listedApps["org.hammerspoon.Hammerspoon"] = true
        saveList()
    end
end
loadList()

local function isAppIncluded(app, win)
    -- Returns true if the window should be tiled
    if not (app and win) then return false end
    if not win:isStandard() then return false end

    local bundleID = app:bundleID()
    local appName  = app:name()
    local listed   = (bundleID and listedApps[bundleID]) or (appName and listedApps[appName])

    if cfg.exclusionMode then
        -- Deny list: listed apps are excluded; others are included
        return not listed
    else
        -- Allow list: only listed apps are included
        return listed == true
    end
end

local function updateWindowOrder()
    local currentSpace = getCurrentSpace()
    local currentWindows = {}

    -- Use screen order to get a consistent ordering basis
    local allScreens = screen.allScreens()
    local byScreen = {}
    for _, scr in ipairs(allScreens) do
        byScreen[scr:id()] = {}
    end

    for _, win in ipairs(window.visibleWindows()) do
        local okSpaces  = spaces.windowSpaces(win)
        local app       = win:application()
        local winScreen = win:screen()
        if okSpaces and winScreen and not win:isFullScreen() and isAppIncluded(app, win) then
            if hs.fnutils.contains(okSpaces, currentSpace) then
                table.insert(byScreen[winScreen:id()], win)
            end
        end
    end

    -- Flatten by screen order
    for _, scr in ipairs(allScreens) do
        for _, w in ipairs(byScreen[scr:id()]) do
            table.insert(currentWindows, w)
        end
    end

    local newOrder = {}

    if windowOrderBySpace[currentSpace] then
        -- Preserve previous ordering where possible
        for _, win in ipairs(windowOrderBySpace[currentSpace]) do
            if hs.fnutils.contains(currentWindows, win) then
                table.insert(newOrder, win)
            end
        end
    end

    -- Add any newcomers
    for _, win in ipairs(currentWindows) do
        if not hs.fnutils.contains(newOrder, win) then
            table.insert(newOrder, win)
        end
    end

    windowOrderBySpace[currentSpace] = newOrder
end

local function getCollapsedWindows(wins)
    local collapsed = {}
    for _, win in ipairs(wins) do
        local s = win:size()
        if s and s.h <= cfg.collapsedWindowHeight then
            table.insert(collapsed, win)
        end
    end
    return collapsed
end

-- Get weight for a window (default 1.0)
local function getWindowWeight(win)
    if not win then return 1.0 end
    local winId = win:id()
    if not winId then return 1.0 end
    return windowWeights[winId] or 1.0
end

-- Set weight for a window
local function setWindowWeight(win, weight)
    if not win then return end
    local winId = win:id()
    if not winId then return end
    windowWeights[winId] = math.max(0.1, weight) -- Minimum 0.1 to prevent invisible windows
end

-- Clean up weights for closed windows
local function pruneStaleWeights()
    local validIds = {}
    for _, win in ipairs(window.allWindows()) do
        local winId = win:id()
        if winId then validIds[winId] = true end
    end
    for winId in pairs(windowWeights) do
        if not validIds[winId] then
            windowWeights[winId] = nil
        end
    end
end

-- Distribute space according to weights
local function distributeWeighted(total, gaps, windows)
    if #windows == 0 then return {} end

    local totalWeight = 0
    for _, win in ipairs(windows) do
        totalWeight = totalWeight + getWindowWeight(win)
    end

    local avail = total - math.max(#windows - 1, 0) * gaps
    local sizes = {}
    local allocated = 0

    for i, win in ipairs(windows) do
        local weight = getWindowWeight(win)
        if i == #windows then
            -- Last window gets remaining space to avoid pixel drift
            sizes[i] = avail - allocated
        else
            sizes[i] = math.floor(avail * weight / totalWeight)
            allocated = allocated + sizes[i]
        end
    end

    return sizes
end

-- Legacy function for collapsed windows (equal distribution)
local function distributeEven(total, gaps, count)
    -- Returns base, remainder where each item gets base, and last gets +remainder
    if count <= 0 then return 0, 0 end
    local avail = total - math.max(count - 1, 0) * gaps
    local base  = math.floor(avail / count)
    local rem   = avail - base * count
    return base, rem
end

local function tileWindowsInternal()
    updateWindowOrder()
    local currentSpace = getCurrentSpace()
    local allScreens = screen.allScreens()

    for _, scr in ipairs(allScreens) do
        local screenFrame = scr:frame()
        local screenId = scr:id()

        -- Collect windows for this screen from the persisted order
        local screenWindows = {}
        local ordered = windowOrderBySpace[currentSpace] or {}
        for _, win in ipairs(ordered) do
            if win and not win:isFullScreen() then
                local s = win:screen()
                if s and s:id() == screenId then
                    table.insert(screenWindows, win)
                end
            end
        end

        if #screenWindows == 0 then
            goto continue
        end

        local collapsedWins = getCollapsedWindows(screenWindows)
        local nonCollapsedWins = {}
        for _, w in ipairs(screenWindows) do
            local sz = w:size()
            if sz and sz.h > cfg.collapsedWindowHeight then
                table.insert(nonCollapsedWins, w)
            end
        end

        local numCollapsed    = #collapsedWins
        local numNonCollapsed = #nonCollapsedWins
        local horizontal      = (screenFrame.w > screenFrame.h)

        if horizontal then
            local collapsedAreaHeight = (numCollapsed > 0) and (cfg.collapsedWindowHeight + cfg.tileGap) or 0
            local mainAreaHeight      = screenFrame.h - collapsedAreaHeight

            -- Non-collapsed main area, tiled horizontally with weights
            if numNonCollapsed > 0 then
                local widths = distributeWeighted(screenFrame.w, cfg.tileGap, nonCollapsedWins)
                local x = screenFrame.x
                for i, win in ipairs(nonCollapsedWins) do
                    local newFrame = { x = x, y = screenFrame.y, w = widths[i], h = mainAreaHeight }
                    win:setFrame(geometry.rect(newFrame), 0)
                    x = x + widths[i] + cfg.tileGap
                end
            end

            -- Collapsed strip at the bottom, tiled horizontally (equal distribution)
            if numCollapsed > 0 then
                local baseW, remW = distributeEven(screenFrame.w, cfg.tileGap, numCollapsed)
                local collapsedX = screenFrame.x
                local collapsedY = screenFrame.y + mainAreaHeight
                for i, win in ipairs(collapsedWins) do
                    local w = baseW + ((i == numCollapsed) and remW or 0)
                    local newFrame = { x = collapsedX, y = collapsedY, w = w, h = cfg.collapsedWindowHeight }
                    win:setFrame(geometry.rect(newFrame), 0)
                    collapsedX = collapsedX + w + cfg.tileGap
                end
            end
        else
            -- Vertical monitor layout: non-collapsed stacked vertically, collapsed stacked below
            local collapsedAreaHeight = 0
            if numCollapsed > 0 then
                collapsedAreaHeight = (cfg.collapsedWindowHeight + cfg.tileGap) * numCollapsed - cfg.tileGap
            end
            local mainAreaHeight = screenFrame.h - collapsedAreaHeight

            -- Non-collapsed main area, full width, distributed heights with weights
            if numNonCollapsed > 0 then
                local heights = distributeWeighted(mainAreaHeight, cfg.tileGap, nonCollapsedWins)
                local y = screenFrame.y
                for i, win in ipairs(nonCollapsedWins) do
                    local newFrame = { x = screenFrame.x, y = y, w = screenFrame.w, h = heights[i] }
                    win:setFrame(geometry.rect(newFrame), 0)
                    y = y + heights[i] + cfg.tileGap
                end
            end

            -- Collapsed area: each its own row
            if numCollapsed > 0 then
                local collapsedX = screenFrame.x
                local collapsedY = screenFrame.y + mainAreaHeight
                for _, win in ipairs(collapsedWins) do
                    local newFrame = { x = collapsedX, y = collapsedY, w = screenFrame.w, h = cfg.collapsedWindowHeight }
                    win:setFrame(geometry.rect(newFrame), 0)
                    collapsedY = collapsedY + cfg.collapsedWindowHeight + cfg.tileGap
                end
            end
        end

        ::continue::
    end
end

local function tileWindows()
    tilingCount = tilingCount + 1
    tileWindowsInternal()
    -- Decrement after a brief delay to allow windowMoved events to fire
    timer.doAfter(0.1, function()
        tilingCount = tilingCount - 1
        if tilingCount < 0 then tilingCount = 0 end
    end)
end

local function isSystem(win)
    return win and (win:role() == "AXScrollArea" or win:subrole() == "AXSystemDialog")
end

local function stopOutlineRefresh()
    if outlineRefreshTimer then
        outlineRefreshTimer:stop()
        outlineRefreshTimer = nil
    end
end

local function framesEqual(f1, f2)
    if not f1 or not f2 then return false end
    return f1.x == f2.x and f1.y == f2.y and f1.w == f2.w and f1.h == f2.h
end

local function updateOutlineFrame(frame)
    if not frame then return end
    if framesEqual(frame, lastOutlineFrame) then return end

    local adjustedFrame = { x = frame.x, y = frame.y, w = frame.w, h = frame.h }

    if not activeWindowOutline then
        activeWindowOutline = drawing.rectangle(geometry.rect(adjustedFrame))
        activeWindowOutline:setStrokeColor(cfg.outlineColor)
        activeWindowOutline:setFill(false)
        activeWindowOutline:setStrokeWidth(cfg.outlineThickness)
        activeWindowOutline:setRoundedRectRadii(cfg.outlineThickness / 2, cfg.outlineThickness / 2)
        activeWindowOutline:setLevel(drawing.windowLevels.floating)
    else
        activeWindowOutline:setFrame(geometry.rect(adjustedFrame))
    end

    lastOutlineFrame = adjustedFrame
    activeWindowOutline:show()
end

local function refreshOutline()
    local win = window.focusedWindow()
    if not win then
        if activeWindowOutline then activeWindowOutline:hide() end
        stopOutlineRefresh()
        return
    end

    -- Check if focused window changed - if so, just return and let handleWindowFocused deal with it
    local winId = win:id()
    if winId ~= trackedFocusedWinId then
        return  -- Don't stop refresh here, handleWindowFocused will restart it for the new window
    end

    local isVisible = win:isVisible()
    local isFullScreen = win:isFullScreen()
    local isSys = isSystem(win)

    local condResult = isVisible and not isFullScreen and not isSys
    if condResult then
        outlineHideCounter = 0  -- Reset counter on success
        local frame = win:frame()
        if frame then
            updateOutlineFrame(frame)
        end
    else
        -- Only hide after multiple consecutive failures (handles momentary visibility glitches)
        outlineHideCounter = outlineHideCounter + 1
        if outlineHideCounter >= 10 then  -- ~160ms at 60fps
            if activeWindowOutline then activeWindowOutline:hide() end
        end
    end
end

local function startOutlineRefresh(win)
    stopOutlineRefresh()
    if not win then return end

    trackedFocusedWinId = win:id()
    outlineHideCounter = 0  -- Reset counter
    -- Poll at 60fps during potential drag operations
    outlineRefreshTimer = timer.doEvery(0.016, refreshOutline)
end

local function drawActiveWindowOutline(win)
    if win and win:isVisible() and not win:isFullScreen() and not isSystem(win) then
        local frame = win:frame()
        if not frame then return end

        trackedFocusedWinId = win:id()
        updateOutlineFrame(frame)
        startOutlineRefresh(win)
    else
        trackedFocusedWinId = nil
        lastOutlineFrame = nil
        stopOutlineRefresh()
        if activeWindowOutline then
            activeWindowOutline:hide()
        end
    end
end

local function handleWindowFocused(win)
    if win and win:isVisible() and not win:isFullScreen() and not isSystem(win) then
        -- Only trigger tiling if not already tiling (prevent cascade from setFrame focus shifts)
        if tilingCount == 0 and isAppIncluded(win:application(), win) then
            tileWindows()
            -- Restore focus if setFrame caused it to shift to another window
            local currentFocus = window.focusedWindow()
            if currentFocus and currentFocus:id() ~= win:id() then
                win:focus()
            end
        end
        drawActiveWindowOutline(win)
    else
        if activeWindowOutline then
            activeWindowOutline:hide()
        end
    end
end

local function handleWindowEvent()
    local focusedWindow = window.focusedWindow()
    updateWindowOrder()
    tileWindows()
    -- Restore focus if setFrame caused it to shift during tiling
    if focusedWindow and focusedWindow:isVisible() then
        local currentFocus = window.focusedWindow()
        if currentFocus and currentFocus:id() ~= focusedWindow:id() then
            focusedWindow:focus()
        end
        drawActiveWindowOutline(focusedWindow)
    elseif window.focusedWindow() then
        drawActiveWindowOutline(window.focusedWindow())
    end
end

local function toggleFocusedWindowInList()
    local focusedWindow = window.focusedWindow()
    if not focusedWindow then return end
    if focusedWindow:isFullScreen() then return end

    local focusedApp = focusedWindow:application()
    if not focusedApp then return end

    local bundleID = focusedApp:bundleID()
    local appName  = focusedApp:name()

    if (bundleID and listedApps[bundleID]) or (appName and listedApps[appName]) then
        if bundleID then listedApps[bundleID] = nil end
        if appName then listedApps[appName] = nil end
    else
        if bundleID then
            listedApps[bundleID] = true
        elseif appName then
            listedApps[appName] = true
        end
    end

    saveList()
    updateWindowOrder()
    tileWindows()
end

local function moveMouseWithWindow(oldFrame, newFrame)
    if not (oldFrame and newFrame) then return end
    local mousePos = mouse.absolutePosition()
    if geometry.isPointInRect(mousePos, oldFrame) then
        local relX = (mousePos.x - oldFrame.x) / oldFrame.w
        local relY = (mousePos.y - oldFrame.y) / oldFrame.h
        local newX = newFrame.x + (relX * newFrame.w)
        local newY = newFrame.y + (relY * newFrame.h)
        mouse.absolutePosition({ x = newX, y = newY })
    end
end

local function moveWindowInOrder(direction)
    local currentSpace = getCurrentSpace()
    local focusedWindow = window.focusedWindow()
    if not focusedWindow then
        updateWindowOrder()
        return
    end

    local currentOrder = windowOrderBySpace[currentSpace] or {}
    local focusedIndex
    local nonCollapsedWindows = {}

    for _, win in ipairs(currentOrder) do
        local sz = win:size()
        if sz and sz.h > cfg.collapsedWindowHeight then
            table.insert(nonCollapsedWindows, win)
        end
    end

    for i, win in ipairs(nonCollapsedWindows) do
        if win:id() == focusedWindow:id() then
            focusedIndex = i
            break
        end
    end

    if not focusedIndex then
        updateWindowOrder()
        return
    end

    local newIndex
    if direction == "forward" then
        newIndex = (focusedIndex < #nonCollapsedWindows) and (focusedIndex + 1) or 1
    else
        newIndex = (focusedIndex > 1) and (focusedIndex - 1) or #nonCollapsedWindows
    end

    table.remove(nonCollapsedWindows, focusedIndex)
    table.insert(nonCollapsedWindows, newIndex, focusedWindow)

    local newOrder = {}
    local ncIdx = 1
    for _, win in ipairs(currentOrder) do
        local sz = win:size()
        if sz and sz.h <= cfg.collapsedWindowHeight then
            table.insert(newOrder, win)
        else
            table.insert(newOrder, nonCollapsedWindows[ncIdx])
            ncIdx = ncIdx + 1
        end
    end

    local oldFrame = focusedWindow:frame()
    windowOrderBySpace[currentSpace] = newOrder
    tileWindows()
    focusedWindow:focus()
    local newFrame = focusedWindow:frame()
    moveMouseWithWindow(oldFrame, newFrame)
    drawActiveWindowOutline(focusedWindow)
end

local function focusAdjacentWindow(direction)
    local currentSpace = getCurrentSpace()
    local focusedWindow = window.focusedWindow()
    local currentOrder = windowOrderBySpace[currentSpace] or {}

    -- Get non-collapsed windows on current screen
    local focusedScreen = focusedWindow and focusedWindow:screen()
    local screenWindows = {}

    for _, win in ipairs(currentOrder) do
        local sz = win:size()
        local winScreen = win:screen()
        if sz and sz.h > cfg.collapsedWindowHeight then
            -- If we have a focused window, only consider windows on same screen
            if not focusedScreen or (winScreen and winScreen:id() == focusedScreen:id()) then
                table.insert(screenWindows, win)
            end
        end
    end

    if #screenWindows == 0 then return end

    -- Find current focused index
    local focusedIndex = 0
    if focusedWindow then
        for i, win in ipairs(screenWindows) do
            if win:id() == focusedWindow:id() then
                focusedIndex = i
                break
            end
        end
    end

    -- Calculate target index
    local targetIndex
    if direction == "forward" or direction == "next" then
        targetIndex = (focusedIndex % #screenWindows) + 1
    else
        targetIndex = focusedIndex > 1 and (focusedIndex - 1) or #screenWindows
    end

    local targetWin = screenWindows[targetIndex]
    if targetWin then
        local oldFrame = focusedWindow and focusedWindow:frame()
        local newFrame = targetWin:frame()

        targetWin:focus()
        drawActiveWindowOutline(targetWin)

        -- Move mouse to center of new window
        if newFrame then
            local centerX = newFrame.x + newFrame.w / 2
            local centerY = newFrame.y + newFrame.h / 2
            mouse.absolutePosition({ x = centerX, y = centerY })
        end
    end
end

local function moveWindowToAdjacentScreen(direction)
    local focusedWindow = window.focusedWindow()
    if not focusedWindow then
        log("No focused window; cannot move to adjacent screen")
        return
    end

    local oldFrame = focusedWindow:frame()
    local currentScreen = focusedWindow:screen()
    if not currentScreen then
        log("No screen for focused window; cannot move to adjacent screen")
        return
    end

    local allScreens = screen.allScreens()
    if #allScreens < 2 then
        log("Only one screen available; cannot move window")
        return
    end

    -- Find current screen index
    local currentScreenIndex
    for i, scr in ipairs(allScreens) do
        if scr:id() == currentScreen:id() then
            currentScreenIndex = i
            break
        end
    end

    if not currentScreenIndex then
        log("Current screen not found in screen list")
        return
    end

    -- Calculate target screen (wrap around)
    local targetScreenIndex
    if direction == "next" then
        targetScreenIndex = (currentScreenIndex % #allScreens) + 1
    else
        targetScreenIndex = ((currentScreenIndex - 2 + #allScreens) % #allScreens) + 1
    end

    local targetScreen = allScreens[targetScreenIndex]
    if not targetScreen then
        log("Target screen not resolved; aborting move")
        return
    end

    -- Move window to target screen, preserving relative position
    local targetFrame = targetScreen:frame()
    local oldScreenFrame = currentScreen:frame()

    -- Calculate relative position within old screen
    local relX = (oldFrame.x - oldScreenFrame.x) / oldScreenFrame.w
    local relY = (oldFrame.y - oldScreenFrame.y) / oldScreenFrame.h
    local relW = oldFrame.w / oldScreenFrame.w
    local relH = oldFrame.h / oldScreenFrame.h

    -- Apply to new screen
    local newFrame = {
        x = targetFrame.x + (relX * targetFrame.w),
        y = targetFrame.y + (relY * targetFrame.h),
        w = relW * targetFrame.w,
        h = relH * targetFrame.h
    }

    -- Hide outline during transition to prevent it showing on old screen
    stopOutlineRefresh()
    if activeWindowOutline then activeWindowOutline:hide() end

    focusedWindow:setFrame(geometry.rect(newFrame), 0)

    -- Update window order - will be recalculated on next tileWindows call
    hs.timer.doAfter(0.15, function()
        focusedWindow:focus()
        updateWindowOrder()
        tileWindows()
        local finalFrame = focusedWindow:frame()
        moveMouseWithWindow(oldFrame, finalFrame)
        drawActiveWindowOutline(focusedWindow)
    end)
end

-- ######## Drag-to-reposition handling ########
local function calculateDropPosition(droppedWin, screenWindows, screenFrame)
    local dropFrame = droppedWin:frame()
    local dropCenterX = dropFrame.x + dropFrame.w / 2
    local dropCenterY = dropFrame.y + dropFrame.h / 2
    local horizontal = (screenFrame.w > screenFrame.h)

    local insertIndex = 1
    for i, win in ipairs(screenWindows) do
        local winFrame = win:frame()
        local winCenterX = winFrame.x + winFrame.w / 2
        local winCenterY = winFrame.y + winFrame.h / 2

        if horizontal then
            if dropCenterX > winCenterX then
                insertIndex = i + 1
            end
        else
            if dropCenterY > winCenterY then
                insertIndex = i + 1
            end
        end
    end

    return insertIndex
end

local function handleWindowMoved(win)
    if not win then return end

    local app = win:application()
    if not isAppIncluded(app, win) then return end
    if win:isFullScreen() then return end

    local sz = win:size()
    if sz and sz.h <= cfg.collapsedWindowHeight then return end

    -- Capture current frame immediately
    local capturedFrame = win:frame()
    if not capturedFrame then return end

    local winScreen = win:screen()
    if not winScreen then return end

    local currentSpace = getCurrentSpace()
    local screenFrame = winScreen:frame()
    local screenId = winScreen:id()
    local horizontal = (screenFrame.w > screenFrame.h)

    -- Get all non-collapsed windows for this screen
    local currentOrder = windowOrderBySpace[currentSpace] or {}
    local screenWindows = {}

    for _, w in ipairs(currentOrder) do
        if w and not w:isFullScreen() then
            local s = w:screen()
            local wsz = w:size()
            if s and s:id() == screenId and wsz and wsz.h > cfg.collapsedWindowHeight then
                table.insert(screenWindows, w)
            end
        end
    end

    if #screenWindows == 0 then return end

    -- Calculate what size this window "should" have based on current weights
    local totalWeight = 0
    for _, w in ipairs(screenWindows) do
        totalWeight = totalWeight + getWindowWeight(w)
    end

    local totalGaps = math.max(#screenWindows - 1, 0) * cfg.tileGap
    local availableSpace = horizontal and (screenFrame.w - totalGaps) or (screenFrame.h - totalGaps)
    local expectedSize = availableSpace * getWindowWeight(win) / totalWeight
    local actualSize = horizontal and capturedFrame.w or capturedFrame.h

    -- Check if this was a resize (size changed significantly)
    local sizeDiff = math.abs(actualSize - expectedSize)
    local wasResized = sizeDiff > 20  -- threshold for resize detection

    -- Always process resizes (user dragging border), but skip moves during programmatic tiling
    if wasResized and #screenWindows >= 2 then
        -- Find index of this window in screen order
        local winIndex = nil
        for i, w in ipairs(screenWindows) do
            if w:id() == win:id() then
                winIndex = i
                break
            end
        end
        if not winIndex then return end

        -- Calculate expected position based on weights to determine which edge was dragged
        local expectedPos = horizontal and screenFrame.x or screenFrame.y
        for i = 1, winIndex - 1 do
            local w = screenWindows[i]
            local wWeight = getWindowWeight(w)
            local wSize = math.floor(availableSpace * wWeight / totalWeight)
            expectedPos = expectedPos + wSize + cfg.tileGap
        end

        local actualPos = horizontal and capturedFrame.x or capturedFrame.y
        local positionMoved = math.abs(actualPos - expectedPos) > 10

        -- Determine which edge was dragged and find adjacent window
        local adjacentWin = nil
        if positionMoved then
            -- Left/top edge was dragged - affect previous window
            if winIndex > 1 then
                adjacentWin = screenWindows[winIndex - 1]
            end
        else
            -- Right/bottom edge was dragged - affect next window
            if winIndex < #screenWindows then
                adjacentWin = screenWindows[winIndex + 1]
            end
        end

        if adjacentWin then
            -- Calculate size change and transfer weight only to/from adjacent window
            local oldWeight = getWindowWeight(win)
            local adjOldWeight = getWindowWeight(adjacentWin)
            local combinedWeight = oldWeight + adjOldWeight

            local newWeight = (actualSize / availableSpace) * totalWeight
            newWeight = math.max(0.2, math.min(newWeight, combinedWeight - 0.2))

            local adjNewWeight = combinedWeight - newWeight
            adjNewWeight = math.max(0.2, adjNewWeight)

            setWindowWeight(win, newWeight)
            setWindowWeight(adjacentWin, adjNewWeight)
        end

        -- Cancel any pending reposition since this was a resize
        if pendingReposition then
            pendingReposition:stop()
            pendingReposition = nil
        end

        tileWindows()
        return
    end

    -- For moves (not resizes), use delayed handling with debounce
    if pendingReposition then
        pendingReposition:stop()
    end

    pendingReposition = timer.doAfter(0.3, function()
        pendingReposition = nil

        -- Re-fetch current state since time has passed
        local space = getCurrentSpace()
        local order = windowOrderBySpace[space] or {}
        local scrn = win:screen()
        if not scrn then
            tileWindows()
            return
        end

        local scrFrame = scrn:frame()
        local scrId = scrn:id()

        local scrnWindows = {}
        for _, w in ipairs(order) do
            if w and not w:isFullScreen() then
                local s = w:screen()
                local wsz = w:size()
                if s and s:id() == scrId and wsz and wsz.h > cfg.collapsedWindowHeight then
                    table.insert(scrnWindows, w)
                end
            end
        end

        local otherWindows = {}
        local movedWinInOrder = false

        for _, w in ipairs(scrnWindows) do
            if w:id() == win:id() then
                movedWinInOrder = true
            else
                table.insert(otherWindows, w)
            end
        end

        if not movedWinInOrder then
            tileWindows()
            return
        end

        -- Find current index in screen windows
        local currentIndex = 0
        for i, w in ipairs(scrnWindows) do
            if w:id() == win:id() then
                currentIndex = i
                break
            end
        end

        local newIndex = calculateDropPosition(win, otherWindows, scrFrame)
        newIndex = math.max(1, math.min(newIndex, #otherWindows + 1))

        -- If position changed, update the order
        if newIndex ~= currentIndex then
            table.insert(otherWindows, newIndex, win)

            local newOrder = {}
            local collapsedOnScreen = {}

            for _, w in ipairs(order) do
                local wsz = w:size()
                if wsz and wsz.h <= cfg.collapsedWindowHeight then
                    local s = w:screen()
                    if s and s:id() == scrId then
                        table.insert(collapsedOnScreen, w)
                    end
                end
            end

            for _, w in ipairs(order) do
                local s = w:screen()
                if s and s:id() ~= scrId then
                    table.insert(newOrder, w)
                end
            end

            for _, w in ipairs(otherWindows) do
                table.insert(newOrder, w)
            end

            for _, w in ipairs(collapsedOnScreen) do
                table.insert(newOrder, w)
            end

            windowOrderBySpace[space] = newOrder
        end

        -- Always retile to snap window back to position
        tileWindows()
    end)
end


local initialFingerCount    = 0
local gestureStartTime      = 0
local lastActionTime        = 0
local gestureStartThreshold = 0.15  -- Time to let all initial fingers settle before detecting +1
local lastTouchCount        = 0
local initialTouchPositions = {}

-- Double-tap detection
local lastTapTime           = 0
local lastTapFingerCount    = 0
local doubleTapThreshold    = 0.35  -- Max time between taps for double-tap

local function handleTTTaps(event)
    local eventType = event:getType(true)
    if eventType ~= hs.eventtap.event.types.gesture then
        return false
    end

    local touches = event:getTouches()
    local touchCount = touches and #touches or 0
    local currentTime = hs.timer.secondsSinceEpoch()

    local touchDetails = event:getTouchDetails()
    if not touchDetails then return false end
    if touchDetails.pressure then return false end

    if touchCount == 0 then
        -- All fingers lifted - check for double-tap
        if initialFingerCount == 3 then
            if lastTapFingerCount == 3 and (currentTime - lastTapTime) < doubleTapThreshold then
                -- Double tap detected!
                if currentTime - lastActionTime > 0.3 then
                    toggleFocusedWindowInList()
                    lastActionTime = currentTime
                end
                lastTapTime = 0
                lastTapFingerCount = 0
            else
                -- Record this tap for potential double-tap
                lastTapTime = currentTime
                lastTapFingerCount = 3
            end
        end

        if initialFingerCount > 0 then
            initialFingerCount    = 0
            gestureStartTime      = 0
            initialTouchPositions = {}
        end
        lastTouchCount = 0
        return false
    end

    if initialFingerCount == 0 then
        if touchCount == 2 or touchCount == 3 or touchCount == 4 then
            initialFingerCount = touchCount
            gestureStartTime = currentTime
            for i = 1, touchCount do
                initialTouchPositions[i] = touches[i].normalizedPosition.x
            end
        end
    elseif touchCount > initialFingerCount and touchCount <= 4 and gestureStartTime and (currentTime - gestureStartTime < gestureStartThreshold) then
        -- More fingers added during settling period - update initial count
        initialFingerCount = touchCount
        gestureStartTime = currentTime
        initialTouchPositions = {}
        for i = 1, touchCount do
            initialTouchPositions[i] = touches[i].normalizedPosition.x
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
                    if initialFingerCount == 2 then
                        -- 2+1: Focus previous/next window
                        if side == "left" then
                            focusAdjacentWindow("backward")
                        else
                            focusAdjacentWindow("forward")
                        end
                    elseif initialFingerCount == 3 then
                        -- 3+1: Move window in tiling order
                        if side == "left" then
                            moveWindowInOrder("backward")
                        else
                            moveWindowInOrder("forward")
                        end
                    elseif initialFingerCount == 4 then
                        -- 4+1: Move window to adjacent screen
                        if side == "left" then
                            moveWindowToAdjacentScreen("previous")
                        else
                            moveWindowToAdjacentScreen("next")
                        end
                    end
                    lastActionTime = currentTime
                end
            end
        end
    end

    lastTouchCount = touchCount
    return false  -- Don't consume event, let other taps receive it
end

local function startTTTapsRecognition()
    if not cfg.enableTTTaps then return end

    if ttTaps then
        ttTaps:stop()
    end

    ttTaps = eventtap.new({ eventtap.event.types.gesture }, handleTTTaps)
    ttTaps:start()
end

local function stopTTTapsRecognition()
    if ttTaps then
        ttTaps:stop()
        ttTaps = nil
    end
end

local function checkTTTapsRecognition()
    if not cfg.enableTTTaps then return end
    if not ttTaps or not ttTaps:isEnabled() then
        startTTTapsRecognition()
    end
end

-- ############################
-- ######## Bindings ##########
-- ############################
local function bindHotkeys()
    -- List toggle (use "," for layout safety instead of "<")
    hotkey.bind(cfg.mods, ",", function()
        toggleFocusedWindowInList()
    end)

    hotkey.bind(cfg.mods, "Left", function()
        moveWindowInOrder("backward")
    end)
    hotkey.bind(cfg.mods, "Right", function()
        moveWindowInOrder("forward")
    end)
    hotkey.bind(cfg.screenMods, "Left", function()
        moveWindowToAdjacentScreen("previous")
    end)
    hotkey.bind(cfg.screenMods, "Right", function()
        moveWindowToAdjacentScreen("next")
    end)

    -- Reset all window weights to equal
    hotkey.bind(cfg.mods, "0", function()
        windowWeights = {}
        tileWindows()
    end)

    if cfg.enableTTTaps then
        startTTTapsRecognition()
        hs.timer.doEvery(300, checkTTTapsRecognition) -- Check every 5 minutes
    end
end

local function handleWindowDestroyed(_)
    pruneStaleWeights() -- Clean up weights for the destroyed window
    updateWindowOrder()
    tileWindows()
    -- Don't call handleWindowFocused here - the windowFocused event subscription
    -- will fire naturally when macOS focuses a new window, avoiding double-handling
    -- that can cause focus flickering
    if not window.focusedWindow() and activeWindowOutline then
        activeWindowOutline:hide()
    end
end

local eventDebounce = nil
local function debouncedHandleWindowEvent()
    if eventDebounce then
        eventDebounce:stop()
    end
    eventDebounce = hs.timer.doAfter(cfg.eventDebounceSeconds, function()
        handleWindowEvent()
        eventDebounce = nil
    end)
end

window.filter.default:subscribe({
    window.filter.windowCreated,
    window.filter.windowHidden,
    window.filter.windowUnhidden,
    window.filter.windowMinimized,
    window.filter.windowUnminimized,
    window.filter.windowsChanged
}, debouncedHandleWindowEvent)

-- Separate handler for windowMoved to support drag-to-reposition
window.filter.default:subscribe(window.filter.windowMoved, handleWindowMoved)

window.filter.default:subscribe(window.filter.windowDestroyed, handleWindowDestroyed)
window.filter.default:subscribe(window.filter.windowFocused, handleWindowFocused)


spaces.watcher.new(function(_)
    handleWindowEvent()
end):start()

-- Keep alive & status ping
local function preventGC()
    pruneStaleSpaces()  -- Clean up stale space entries
    pruneStaleWeights() -- Clean up weights for closed windows
end

hs.timer.doEvery(3600, preventGC) -- Hourly status and cleanup

local initialFocusedWindow = window.focusedWindow()
if initialFocusedWindow then
    drawActiveWindowOutline(initialFocusedWindow)
end

updateWindowOrder()
tileWindows()
bindHotkeys()

log("WindowScape initialized" ..
    (cfg.enableTTTaps and " with TTTaps recognition" or " without TTTaps recognition") ..
    " and drag-to-reposition")

-- Public helper to restart the gesture recognizer manually
function restartWindowScapeTTTaps()
    if cfg.enableTTTaps then
        stopTTTapsRecognition()
        startTTTapsRecognition()
    end
end
