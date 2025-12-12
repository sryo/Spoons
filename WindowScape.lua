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

-- Drag tracking state
local tilingCount         = 0   -- Counter to distinguish our moves from user drags (handles overlapping tiles)
local pendingReposition   = nil -- Timer for delayed reposition check

-- Border resize state
local borderResizeState   = nil -- { win1, win2, startX/Y, startWeight1, startWeight2, horizontal }
local borderResizeTap     = nil -- eventtap for border resize
local borderResizeZone    = 8   -- pixels from border to trigger resize cursor

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

    -- Check if focused window changed
    local winId = win:id()
    if winId ~= trackedFocusedWinId then
        stopOutlineRefresh()
        return
    end

    if win:isVisible() and not win:isFullScreen() and not isSystem(win) then
        local frame = win:frame()
        updateOutlineFrame(frame)
    else
        if activeWindowOutline then activeWindowOutline:hide() end
    end
end

local function startOutlineRefresh(win)
    stopOutlineRefresh()
    if not win then return end

    trackedFocusedWinId = win:id()
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
        if isAppIncluded(win:application(), win) then
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
    tileWindows()
    local focusedWindow = window.focusedWindow()
    if focusedWindow then
        drawActiveWindowOutline(focusedWindow)
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

    focusedWindow:setFrame(geometry.rect(newFrame), 0)

    -- Update window order - will be recalculated on next tileWindows call
    hs.timer.doAfter(0.1, function()
        focusedWindow:focus()
        updateWindowOrder()
        tileWindows()
        local finalFrame = focusedWindow:frame()
        moveMouseWithWindow(oldFrame, finalFrame)
    end)
end

-- ######## Drag-to-reposition handling ########
local function calculateDropPosition(droppedWin, screenWindows, screenFrame)
    local dropFrame = droppedWin:frame()
    local dropCenterX = dropFrame.x + dropFrame.w / 2
    local dropCenterY = dropFrame.y + dropFrame.h / 2
    local horizontal = (screenFrame.w > screenFrame.h)

    log("Drop position: centerX=" ..
    dropCenterX .. ", centerY=" .. dropCenterY .. ", horizontal=" .. tostring(horizontal))

    local insertIndex = 1
    for i, win in ipairs(screenWindows) do
        local winFrame = win:frame()
        local winCenterX = winFrame.x + winFrame.w / 2
        local winCenterY = winFrame.y + winFrame.h / 2

        log("  Window " .. i .. " (" .. (win:title() or "?") .. "): centerX=" .. winCenterX)

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

    log("Final insertIndex: " .. insertIndex)
    return insertIndex
end

local function handleWindowMoved(win)
    -- Ignore if we're currently tiling (counter > 0 means tiling in progress)
    if tilingCount > 0 then return end
    if not win then return end

    local app = win:application()
    if not isAppIncluded(app, win) then return end
    if win:isFullScreen() then return end

    local sz = win:size()
    if sz and sz.h <= cfg.collapsedWindowHeight then return end

    -- Cancel any pending reposition
    if pendingReposition then
        pendingReposition:stop()
    end

    -- Wait a bit for the drag to finish, then reposition
    pendingReposition = timer.doAfter(0.3, function()
        pendingReposition = nil

        log("Window moved (user drag): " .. (win:title() or "?"))

        local currentSpace = getCurrentSpace()
        local winScreen = win:screen()
        if not winScreen then
            tileWindows()
            return
        end

        local screenFrame = winScreen:frame()
        local screenId = winScreen:id()

        -- Get non-collapsed windows for this screen (excluding the moved window)
        local currentOrder = windowOrderBySpace[currentSpace] or {}
        local otherWindows = {}
        local movedWinInOrder = false

        for _, w in ipairs(currentOrder) do
            if w and not w:isFullScreen() then
                local s = w:screen()
                local wsz = w:size()
                if s and s:id() == screenId and wsz and wsz.h > cfg.collapsedWindowHeight then
                    if w:id() == win:id() then
                        movedWinInOrder = true
                    else
                        table.insert(otherWindows, w)
                    end
                end
            end
        end

        if not movedWinInOrder then
            tileWindows()
            return
        end

        -- Log old order
        local oldTitles = {}
        for _, w in ipairs(otherWindows) do table.insert(oldTitles, w:title() or "?") end
        log("Other windows before insert: " .. table.concat(oldTitles, ", "))

        -- Calculate new position based on where window was dropped
        local newIndex = calculateDropPosition(win, otherWindows, screenFrame)
        newIndex = math.max(1, math.min(newIndex, #otherWindows + 1))

        -- Insert at new position
        table.insert(otherWindows, newIndex, win)

        -- Log new screen order
        local newTitles = {}
        for _, w in ipairs(otherWindows) do table.insert(newTitles, w:title() or "?") end
        log("Screen windows after insert: " .. table.concat(newTitles, ", "))

        -- Rebuild the full order: windows on other screens + collapsed stay in original relative order
        -- but windows on this screen use the new otherWindows order
        local newOrder = {}
        local collapsedOnScreen = {}

        -- First, collect collapsed windows on this screen
        for _, w in ipairs(currentOrder) do
            local wsz = w:size()
            if wsz and wsz.h <= cfg.collapsedWindowHeight then
                local s = w:screen()
                if s and s:id() == screenId then
                    table.insert(collapsedOnScreen, w)
                end
            end
        end

        -- Add windows from other screens (in original order)
        for _, w in ipairs(currentOrder) do
            local s = w:screen()
            if s and s:id() ~= screenId then
                table.insert(newOrder, w)
            end
        end

        -- Add non-collapsed windows on this screen in new order
        for _, w in ipairs(otherWindows) do
            table.insert(newOrder, w)
        end

        -- Add collapsed windows on this screen at the end
        for _, w in ipairs(collapsedOnScreen) do
            table.insert(newOrder, w)
        end

        log("Drag reposition: moved to position " .. newIndex)

        windowOrderBySpace[currentSpace] = newOrder
        tileWindows()
        win:focus()
    end)
end

local function findBorderAtPoint(x, y)
    -- Find if mouse is near a border between two adjacent tiled windows
    local currentSpace = getCurrentSpace()
    local ordered = windowOrderBySpace[currentSpace] or {}

    -- Get non-collapsed windows on the screen containing the point
    local targetScreen = screen.find(geometry.point(x, y))
    if not targetScreen then return nil end

    local screenId = targetScreen:id()
    local screenFrame = targetScreen:frame()
    local horizontal = (screenFrame.w > screenFrame.h)

    local screenWindows = {}
    for _, win in ipairs(ordered) do
        if win and not win:isFullScreen() then
            local s = win:screen()
            local sz = win:size()
            if s and s:id() == screenId and sz and sz.h > cfg.collapsedWindowHeight then
                table.insert(screenWindows, win)
            end
        end
    end

    if #screenWindows < 2 then return nil end

    -- Check borders between adjacent windows
    for i = 1, #screenWindows - 1 do
        local win1 = screenWindows[i]
        local win2 = screenWindows[i + 1]
        local frame1 = win1:frame()
        local frame2 = win2:frame()

        if frame1 and frame2 then
            if horizontal then
                -- Check vertical border (right edge of win1)
                local borderX = frame1.x + frame1.w
                if math.abs(x - borderX) <= borderResizeZone then
                    -- Check if y is within the window height
                    if y >= frame1.y and y <= frame1.y + frame1.h then
                        return { win1 = win1, win2 = win2, horizontal = true, borderPos = borderX }
                    end
                end
            else
                -- Check horizontal border (bottom edge of win1)
                local borderY = frame1.y + frame1.h
                if math.abs(y - borderY) <= borderResizeZone then
                    -- Check if x is within the window width
                    if x >= frame1.x and x <= frame1.x + frame1.w then
                        return { win1 = win1, win2 = win2, horizontal = false, borderPos = borderY }
                    end
                end
            end
        end
    end

    return nil
end

local function handleBorderResize(event)
    local eventType = event:getType()
    local mousePos = mouse.absolutePosition()

    if eventType == eventtap.event.types.leftMouseDown then
        local border = findBorderAtPoint(mousePos.x, mousePos.y)
        if border then
            -- Start border resize
            borderResizeState = {
                win1 = border.win1,
                win2 = border.win2,
                horizontal = border.horizontal,
                startPos = border.horizontal and mousePos.x or mousePos.y,
                startWeight1 = getWindowWeight(border.win1),
                startWeight2 = getWindowWeight(border.win2),
                startSize1 = border.horizontal and border.win1:frame().w or border.win1:frame().h,
                startSize2 = border.horizontal and border.win2:frame().w or border.win2:frame().h
            }
            log("Border resize started between: " ..
            (border.win1:title() or "?") .. " and " .. (border.win2:title() or "?"))
            return true -- Consume the event
        end
    elseif eventType == eventtap.event.types.leftMouseDragged then
        if borderResizeState then
            local currentPos = borderResizeState.horizontal and mousePos.x or mousePos.y
            local delta = currentPos - borderResizeState.startPos

            -- Calculate new sizes
            local totalSize = borderResizeState.startSize1 + borderResizeState.startSize2
            local newSize1 = math.max(50, math.min(totalSize - 50, borderResizeState.startSize1 + delta))
            local newSize2 = totalSize - newSize1

            -- Convert sizes to weights (proportional to original weight/size ratio)
            local ratio1 = borderResizeState.startWeight1 / borderResizeState.startSize1
            local ratio2 = borderResizeState.startWeight2 / borderResizeState.startSize2
            local avgRatio = (ratio1 + ratio2) / 2

            setWindowWeight(borderResizeState.win1, newSize1 * avgRatio)
            setWindowWeight(borderResizeState.win2, newSize2 * avgRatio)

            -- Retile to show the change
            tilingCount = tilingCount + 1
            tileWindowsInternal()
            timer.doAfter(0.05, function()
                tilingCount = tilingCount - 1
                if tilingCount < 0 then tilingCount = 0 end
            end)

            return true -- Consume the event
        end
    elseif eventType == eventtap.event.types.leftMouseUp then
        if borderResizeState then
            log("Border resize ended")
            borderResizeState = nil
            return true -- Consume the event
        end
    end

    return false
end

local function startBorderResizeRecognition()
    if borderResizeTap then
        borderResizeTap:stop()
    end

    borderResizeTap = eventtap.new({
        eventtap.event.types.leftMouseDown,
        eventtap.event.types.leftMouseDragged,
        eventtap.event.types.leftMouseUp
    }, handleBorderResize)
    borderResizeTap:start()
    log("Border resize recognition started")
end

local function stopBorderResizeRecognition()
    if borderResizeTap then
        borderResizeTap:stop()
        borderResizeTap = nil
        log("Border resize recognition stopped")
    end
end

local initialFingerCount    = 0
local gestureStartTime      = 0
local lastActionTime        = 0
local gestureStartThreshold = 0.005
local lastTouchCount        = 0
local initialTouchPositions = {}

local function handleTTTaps(event)
    local eventType = event:getType(true)
    if eventType ~= hs.eventtap.event.types.gesture then
        return false
    end

    local touchDetails = event:getTouchDetails()
    if not touchDetails then return false end
    if touchDetails.pressure then return false end

    local touches = event:getTouches()
    local touchCount = touches and #touches or 0
    local currentTime = hs.timer.secondsSinceEpoch()

    if touchCount == 0 and lastTouchCount <= initialFingerCount then
        if initialFingerCount > 0 then
            log("Gesture ended")
            initialFingerCount    = 0
            gestureStartTime      = 0
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
                            log("Executing: Move window to previous screen")
                            moveWindowToAdjacentScreen("previous")
                        else
                            log("Executing: Move window to next screen")
                            moveWindowToAdjacentScreen("next")
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
    if not cfg.enableTTTaps then
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
    if not cfg.enableTTTaps then return end
    if not ttTaps or not ttTaps:isEnabled() then
        log("TTTaps recognition was stopped, restarting...")
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
        log("All window weights reset to equal")
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
    local newFocusedWindow = window.focusedWindow()
    if newFocusedWindow then
        handleWindowFocused(newFocusedWindow)
    else
        if activeWindowOutline then
            activeWindowOutline:hide()
        end
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
    if cfg.enableTTTaps then
        if ttTaps then
            log("TTTaps recognition is active")
        else
            log("TTTaps recognition is not active")
        end
    else
        log("TTTaps recognition is disabled")
    end
end

hs.timer.doEvery(3600, preventGC) -- Hourly status and cleanup

local initialFocusedWindow = window.focusedWindow()
if initialFocusedWindow then
    drawActiveWindowOutline(initialFocusedWindow)
end

updateWindowOrder()
tileWindows()
bindHotkeys()
startBorderResizeRecognition()

log("WindowScape initialized" ..
    (cfg.enableTTTaps and " with TTTaps recognition" or " without TTTaps recognition") ..
    ", drag-to-reposition, and border resize")

-- Public helper to restart the gesture recognizer manually
function restartWindowScapeTTTaps()
    if cfg.enableTTTaps then
        stopTTTapsRecognition()
        startTTTapsRecognition()
        log("WindowScape TTTaps recognition manually restarted")
    else
        log("TTTaps recognition is disabled, cannot restart")
    end
end
