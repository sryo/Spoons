-- WindowScape: https://github.com/sryo/Spoons/blob/main/WindowScape.lua
-- This script automatically tiles windows.

local spacesOk, spaces = pcall(require, "hs.spaces")
if not spacesOk then
    -- Create stub module and inject into package cache so other modules use it too
    spaces = {
        focusedSpace = function() return 1 end,
        windowSpaces = function(win) return { 1 } end,
        allSpaces = function() return { ["Main"] = { 1 } } end,
        watcher = { new = function(callback) return { start = function() end } end },
        activeSpaces = function() return { 1 } end,
        spaceType = function(spaceID) return "user" end,
        spacesForScreen = function(screenID) return { 1 } end,
        moveWindowToSpace = function(win, spaceID) end,
        gotoSpace = function(spaceID) end,
    }
    package.loaded["hs.spaces"] = spaces
    print("[WindowScape] hs.spaces unavailable (Dock disabled?), using single-space mode")
end

local window              = require("hs.window")
local screen              = require("hs.screen")
local geometry            = require("hs.geometry")
local drawing             = require("hs.drawing")
local mouse               = require("hs.mouse")
local eventtap            = require("hs.eventtap")
local timer               = require("hs.timer")
local json                = require("hs.json")
local hotkey              = require("hs.hotkey")
local canvas              = require("hs.canvas")
local axuielement         = require("hs.axuielement")
local menubar             = require("hs.menubar")

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
local outlineHideCounter  = 0 -- Counter to prevent hiding on momentary visibility glitches

-- Drag tracking state
local tilingCount         = 0   -- Counter to distinguish our moves from user drags (handles overlapping tiles)
local pendingReposition   = nil -- Timer for delayed reposition check


local listedApps          = {} -- bundleIDs or app names
local listPath            = hs.configdir .. "/WindowScape_apps.json"

local windowOrderBySpace  = {}
local windowWeights       = {} -- windowId -> weight (default 1.0)

-- Simulated fullscreen state
local simulatedFullscreen = {
    active = false,
    window = nil,
    hiddenWindows = {},    -- Windows we hid when entering fullscreen
    savedWeights = {},     -- Backup of weights before fullscreen
    zoomOverlays = {},     -- Canvas overlays on zoom buttons
    minimizeOverlays = {}, -- Canvas overlays on minimize buttons
}

-- Snapshot thumbnails for "minimized" windows
local windowSnapshots     = {
    windows = {},       -- winId -> { win, canvas, originalFrame }
    container = nil,    -- Canvas container for all thumbnails
    isCreating = false, -- Prevent re-entrancy during snapshot creation
}

-- Forward declarations for functions used in timer callbacks
local createZoomOverlay
local createMinimizeOverlay
local updateButtonOverlays
local updateButtonOverlaysWithRetry
local showSnapshotContextMenu

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

    -- Exclude windows that are hidden via snapshots (alpha=0)
    local winId = win:id()
    if winId and windowSnapshots.windows[winId] then return false end

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

-- Snapshot layout helpers (needed before tileWindowsInternal)
local snapshotPadding = 8
local snapshotGap = 4

local function getSnapshotSize()
    local scr = screen.mainScreen()
    local frame = scr:frame()
    local isLandscape = frame.w > frame.h

    if isLandscape then
        -- Column on right side
        return { w = 120, h = 80 }
    else
        -- Row at bottom
        return { w = 80, h = 60 }
    end
end

-- Get the reserved area for snapshots (returns nil if no snapshots)
local function getSnapshotReservedArea(scr)
    local count = 0
    for _ in pairs(windowSnapshots.windows) do count = count + 1 end
    if count == 0 then return nil end

    local frame = scr:frame()
    local isLandscape = frame.w > frame.h
    local snapSize = getSnapshotSize()

    if isLandscape then
        -- Reserve column on right
        return {
            x = frame.x + frame.w - snapSize.w - snapshotPadding * 2,
            y = frame.y,
            w = snapSize.w + snapshotPadding * 2,
            h = frame.h
        }
    else
        -- Reserve row at bottom
        return {
            x = frame.x,
            y = frame.y + frame.h - snapSize.h - snapshotPadding * 2,
            w = frame.w,
            h = snapSize.h + snapshotPadding * 2
        }
    end
end

-- Get adjusted screen frame excluding snapshot area
local function getAdjustedScreenFrame(scr)
    local frame = scr:frame()
    local reserved = getSnapshotReservedArea(scr)

    if not reserved then return frame end

    local isLandscape = frame.w > frame.h
    if isLandscape then
        -- Reduce width
        return {
            x = frame.x,
            y = frame.y,
            w = frame.w - reserved.w,
            h = frame.h
        }
    else
        -- Reduce height
        return {
            x = frame.x,
            y = frame.y,
            w = frame.w,
            h = frame.h - reserved.h
        }
    end
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
        local screenFrame = getAdjustedScreenFrame(scr) -- Excludes snapshot area
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
    -- Don't tile if in simulated fullscreen or during snapshot creation
    if simulatedFullscreen.active then return end
    if windowSnapshots.isCreating then return end
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
        return -- Don't stop refresh here, handleWindowFocused will restart it for the new window
    end

    local isVisible = win:isVisible()
    local isFullScreen = win:isFullScreen()
    local isSys = isSystem(win)

    local condResult = isVisible and not isFullScreen and not isSys
    if condResult then
        outlineHideCounter = 0 -- Reset counter on success
        local frame = win:frame()
        if frame then
            updateOutlineFrame(frame)
        end
    else
        -- Only hide after multiple consecutive failures (handles momentary visibility glitches)
        outlineHideCounter = outlineHideCounter + 1
        if outlineHideCounter >= 10 then -- ~160ms at 60fps
            if activeWindowOutline then activeWindowOutline:hide() end
        end
    end
end

local function startOutlineRefresh(win)
    stopOutlineRefresh()
    if not win then return end

    trackedFocusedWinId = win:id()
    outlineHideCounter = 0 -- Reset counter
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

local function getZoomButtonRect(win)
    if not win then return nil end
    local axWin = axuielement.windowElement(win)
    if not axWin then return nil end

    local zoomButton = axWin:attributeValue("AXZoomButton")
    if not zoomButton then return nil end

    local pos = zoomButton:attributeValue("AXPosition")
    local size = zoomButton:attributeValue("AXSize")
    if not (pos and size) then return nil end

    return { x = pos.x, y = pos.y, w = size.w, h = size.h }
end

local function clearZoomOverlays()
    for _, overlay in pairs(simulatedFullscreen.zoomOverlays) do
        if overlay then overlay:delete() end
    end
    simulatedFullscreen.zoomOverlays = {}
end

local function clearMinimizeOverlays()
    for _, overlay in pairs(simulatedFullscreen.minimizeOverlays) do
        if overlay then overlay:delete() end
    end
    simulatedFullscreen.minimizeOverlays = {}
end


local function updateSnapshotLayout()
    local scr = screen.mainScreen()
    local frame = scr:frame()
    local isLandscape = frame.w > frame.h
    local snapSize = getSnapshotSize()

    local count = 0
    for _ in pairs(windowSnapshots.windows) do count = count + 1 end
    if count == 0 then return end

    local i = 0
    for winId, data in pairs(windowSnapshots.windows) do
        if data.canvas then
            local x, y
            if isLandscape then
                -- Stack vertically on right edge
                x = frame.x + frame.w - snapSize.w - snapshotPadding
                y = frame.y + snapshotPadding + i * (snapSize.h + snapshotGap)
            else
                -- Stack horizontally at bottom
                x = frame.x + snapshotPadding + i * (snapSize.w + snapshotGap)
                y = frame.y + frame.h - snapSize.h - snapshotPadding
            end
            data.canvas:topLeft({ x = x, y = y })
            i = i + 1
        end
    end
end

local function restoreFromSnapshot(winId)
    local data = windowSnapshots.windows[winId]
    if not data then return end

    local win = data.win
    if not win or not win:application() then
        -- Window no longer exists, just clean up
        if data.canvas then
            data.canvas:delete()
        end
        windowSnapshots.windows[winId] = nil
        updateSnapshotLayout()
        return
    end

    -- Get current thumbnail frame for animation start
    local startFrame = data.canvas:frame()
    local targetFrame = data.originalFrame

    -- Take a snapshot of the thumbnail for animation
    local snapshot = win:snapshot()
    if not snapshot then
        -- Fallback: just restore without animation
        win:setFrame(geometry.rect(targetFrame), 0)
        win:focus()
        if data.canvas then
            data.canvas:delete()
        end
        windowSnapshots.windows[winId] = nil
        updateSnapshotLayout()
        -- Delay tiling to ensure window is fully restored
        timer.doAfter(0.1, function()
            updateWindowOrder()
            tileWindows()
            updateButtonOverlaysWithRetry()
        end)
        return
    end

    -- Hide the original thumbnail
    data.canvas:hide()

    -- Create animation canvas at thumbnail position
    local animCanvas = canvas.new(startFrame)
    animCanvas:appendElements({
        type = "image",
        image = snapshot,
        frame = { x = 0, y = 0, w = "100%", h = "100%" },
        imageScaling = "scaleToFit",
    })
    animCanvas:level(canvas.windowLevels.popUpMenu)
    animCanvas:show()

    -- Animate to window position
    local steps = 12
    local currentStep = 0
    local animTimer
    animTimer = timer.doEvery(0.016, function()
        currentStep = currentStep + 1
        local t = currentStep / steps
        -- Ease out cubic
        local ease = 1 - math.pow(1 - t, 3)

        local newX = startFrame.x + (targetFrame.x - startFrame.x) * ease
        local newY = startFrame.y + (targetFrame.y - startFrame.y) * ease
        local newW = startFrame.w + (targetFrame.w - startFrame.w) * ease
        local newH = startFrame.h + (targetFrame.h - startFrame.h) * ease

        animCanvas:frame({ x = newX, y = newY, w = newW, h = newH })

        if currentStep >= steps then
            animTimer:stop()
            animCanvas:delete()

            -- Now restore the actual window
            win:setFrame(geometry.rect(targetFrame), 0)
            win:focus()

            if data.canvas then
                data.canvas:delete()
            end
            windowSnapshots.windows[winId] = nil

            updateSnapshotLayout()
            -- Delay tiling to ensure window is fully restored
            timer.doAfter(0.1, function()
                updateWindowOrder()
                tileWindows()
                updateButtonOverlaysWithRetry()
            end)
        end
    end)
end

local function createSnapshot(win)
    if not win then return end
    if windowSnapshots.isCreating then return end -- Prevent re-entrancy

    local winId = win:id()
    if not winId then return end
    if windowSnapshots.windows[winId] then return end -- Already snapshotted

    windowSnapshots.isCreating = true

    -- Take snapshot before minimizing
    local snapshot = win:snapshot()
    if not snapshot then
        -- Can't create snapshot, abort (minimize doesn't work without Dock anyway)
        windowSnapshots.isCreating = false
        print("[WindowScape] Could not take snapshot of window, aborting minimize")
        return
    end

    local winFrame = win:frame()
    local snapSize = getSnapshotSize()
    local scr = screen.mainScreen()
    local scrFrame = scr:frame()
    local isLandscape = scrFrame.w > scrFrame.h

    -- Calculate target position for the thumbnail
    local count = 0
    for _ in pairs(windowSnapshots.windows) do count = count + 1 end

    local targetX, targetY
    if isLandscape then
        targetX = scrFrame.x + scrFrame.w - snapSize.w - snapshotPadding
        targetY = scrFrame.y + snapshotPadding + count * (snapSize.h + snapshotGap)
    else
        targetX = scrFrame.x + snapshotPadding + count * (snapSize.w + snapshotGap)
        targetY = scrFrame.y + scrFrame.h - snapSize.h - snapshotPadding
    end

    -- Create animation canvas at window's current position
    local animCanvas = canvas.new(winFrame)
    animCanvas:appendElements({
        type = "image",
        image = snapshot,
        frame = { x = 0, y = 0, w = "100%", h = "100%" },
        imageScaling = "scaleToFit",
    })
    animCanvas:level(canvas.windowLevels.floating)
    animCanvas:show()

    -- Hide the window by shrinking and moving it past bottom-right of screen (minimize doesn't work without Dock)
    -- The window is excluded from tiling via the isAppIncluded check
    win:setFrame(geometry.rect({ x = scrFrame.x + scrFrame.w + 100, y = scrFrame.y + scrFrame.h + 100, w = 1, h = 1 }), 0)

    -- Animate to thumbnail position
    local steps = 12
    local currentStep = 0
    local animTimer
    animTimer = timer.doEvery(0.016, function()
        currentStep = currentStep + 1
        local t = currentStep / steps
        -- Ease out cubic
        local ease = 1 - math.pow(1 - t, 3)

        local newX = winFrame.x + (targetX - winFrame.x) * ease
        local newY = winFrame.y + (targetY - winFrame.y) * ease
        local newW = winFrame.w + (snapSize.w - winFrame.w) * ease
        local newH = winFrame.h + (snapSize.h - winFrame.h) * ease

        animCanvas:frame({ x = newX, y = newY, w = newW, h = newH })

        if currentStep >= steps then
            animTimer:stop()
            animCanvas:delete()

            -- Create the final thumbnail
            local snapshotCanvas = canvas.new({ x = targetX, y = targetY, w = snapSize.w, h = snapSize.h })

            -- Add border
            snapshotCanvas:appendElements({
                type = "rectangle",
                action = "fill",
                fillColor = { white = 0.2, alpha = 0.9 },
                roundedRectRadii = { xRadius = 6, yRadius = 6 },
            })

            -- Add the window snapshot image
            snapshotCanvas:appendElements({
                type = "image",
                image = snapshot,
                frame = { x = 2, y = 2, w = snapSize.w - 4, h = snapSize.h - 4 },
                imageScaling = "scaleToFit",
            })

            -- Add close button indicator (small X in corner)
            snapshotCanvas:appendElements({
                type = "circle",
                action = "fill",
                center = { x = snapSize.w - 10, y = 10 },
                radius = 6,
                fillColor = { red = 0.8, green = 0.2, blue = 0.2, alpha = 0.8 },
            })

            -- Add app icon in bottom-left corner
            local app = win:application()
            if app then
                local appIcon = app:bundleID() and hs.image.imageFromAppBundle(app:bundleID())
                if appIcon then
                    local iconSize = 20
                    snapshotCanvas:appendElements({
                        type = "image",
                        image = appIcon,
                        frame = { x = 4, y = snapSize.h - iconSize - 4, w = iconSize, h = iconSize },
                        imageScaling = "scaleToFit",
                    })
                end
            end

            snapshotCanvas:level(canvas.windowLevels.popUpMenu)
            snapshotCanvas:clickActivating(false)
            snapshotCanvas:canvasMouseEvents(true, true, false, false)

            snapshotCanvas:mouseCallback(function(c, msg, id, x, y)
                if msg == "mouseDown" then
                    -- Check for right-click
                    local buttons = mouse.getButtons()
                    if buttons.right then
                        showSnapshotContextMenu(winId, windowSnapshots.windows[winId])
                        return
                    end
                elseif msg == "mouseUp" then
                    -- Only handle left-click
                    local buttons = mouse.getButtons()
                    if buttons.right then return end

                    -- Check if clicked on close button (top-right corner)
                    if x > snapSize.w - 20 and y < 20 then
                        -- Close the window
                        if win and win:application() then
                            win:close()
                        end
                        if windowSnapshots.windows[winId] then
                            windowSnapshots.windows[winId].canvas:delete()
                            windowSnapshots.windows[winId] = nil
                            updateSnapshotLayout()
                            updateWindowOrder()
                            tileWindows()
                        end
                    else
                        -- Restore the window
                        restoreFromSnapshot(winId)
                    end
                end
            end)

            snapshotCanvas:show()

            windowSnapshots.windows[winId] = {
                win = win,
                canvas = snapshotCanvas,
                originalFrame = winFrame,
            }

            windowSnapshots.isCreating = false

            -- Retile to account for reserved snapshot area
            updateSnapshotLayout()
            updateWindowOrder()
            tileWindows()

            -- Recreate button overlays
            updateButtonOverlaysWithRetry()
        end
    end)
end

local function clearAllSnapshots()
    for winId, data in pairs(windowSnapshots.windows) do
        if data.canvas then
            data.canvas:delete()
        end
    end
    windowSnapshots.windows = {}
end

local function restoreAllSnapshots()
    local winIds = {}
    for winId, _ in pairs(windowSnapshots.windows) do
        table.insert(winIds, winId)
    end
    for _, winId in ipairs(winIds) do
        restoreFromSnapshot(winId)
    end
end

local function closeAllSnapshots()
    for winId, data in pairs(windowSnapshots.windows) do
        if data.win and data.win:application() then
            data.win:close()
        end
        if data.canvas then
            data.canvas:delete()
        end
    end
    windowSnapshots.windows = {}
    updateSnapshotLayout()
    updateWindowOrder()
    tileWindows()
    updateButtonOverlaysWithRetry()
end

showSnapshotContextMenu = function(winId, data)
    local menuItems = {
        {
            title = "Restore",
            fn = function()
                restoreFromSnapshot(winId)
            end
        },
        {
            title = "Close",
            fn = function()
                if data.win and data.win:application() then
                    data.win:close()
                end
                if windowSnapshots.windows[winId] then
                    windowSnapshots.windows[winId].canvas:delete()
                    windowSnapshots.windows[winId] = nil
                    updateSnapshotLayout()
                    updateWindowOrder()
                    tileWindows()
                end
            end
        },
        { title = "-" }, -- Separator
        {
            title = "Restore All",
            fn = function()
                restoreAllSnapshots()
            end
        },
        {
            title = "Close All",
            fn = function()
                closeAllSnapshots()
            end
        },
    }

    local menu = menubar.new(false)
    menu:setMenu(menuItems)
    menu:popupMenu(mouse.absolutePosition(), true)
    -- Clean up after a delay
    timer.doAfter(0.1, function()
        menu:delete()
    end)
end

local function getMinimizeButtonRect(win)
    if not win then return nil end
    local axWin = axuielement.windowElement(win)
    if not axWin then return nil end

    local minimizeButton = axWin:attributeValue("AXMinimizeButton")
    if not minimizeButton then return nil end

    local pos = minimizeButton:attributeValue("AXPosition")
    local size = minimizeButton:attributeValue("AXSize")
    if not (pos and size) then return nil end

    return { x = pos.x, y = pos.y, w = size.w, h = size.h }
end

local function exitSimulatedFullscreen()
    if not simulatedFullscreen.active then return end
    log("Exiting simulated fullscreen")

    simulatedFullscreen.active = false

    -- Restore saved weights
    if simulatedFullscreen.savedWeights then
        for winId, weight in pairs(simulatedFullscreen.savedWeights) do
            windowWeights[winId] = weight
        end
        simulatedFullscreen.savedWeights = {}
    end

    -- Show hidden windows by restoring their frames
    for _, data in ipairs(simulatedFullscreen.hiddenWindows) do
        if data.win and data.win:application() and data.frame then
            data.win:setFrame(geometry.rect(data.frame), 0)
        end
    end
    simulatedFullscreen.hiddenWindows = {}

    -- Clear the fullscreen window reference
    simulatedFullscreen.window = nil

    -- Clear overlays
    clearZoomOverlays()
    clearMinimizeOverlays()

    -- Re-tile and show outline
    updateWindowOrder()
    tileWindows()

    local focused = window.focusedWindow()
    if focused then
        drawActiveWindowOutline(focused)
    end

    -- Recreate button overlays for all visible windows
    updateButtonOverlaysWithRetry()
end

local function enterSimulatedFullscreen(win)
    if not win then return end
    if simulatedFullscreen.active then
        exitSimulatedFullscreen()
        return
    end

    log("Entering simulated fullscreen for: " .. (win:title() or "untitled"))

    local winScreen = win:screen()
    if not winScreen then return end
    local screenFrame = winScreen:frame()

    -- Save current weights before fullscreen
    simulatedFullscreen.savedWeights = {}
    for winId, weight in pairs(windowWeights) do
        simulatedFullscreen.savedWeights[winId] = weight
    end

    simulatedFullscreen.active = true
    simulatedFullscreen.window = win
    simulatedFullscreen.hiddenWindows = {}

    -- Hide outline
    stopOutlineRefresh()
    if activeWindowOutline then activeWindowOutline:hide() end

    -- Clear button overlays during fullscreen
    clearZoomOverlays()
    clearMinimizeOverlays()

    -- Hide all other windows on this space by moving them off-screen
    local currentSpace = getCurrentSpace()
    for _, otherWin in ipairs(window.visibleWindows()) do
        if otherWin:id() ~= win:id() then
            local okSpaces = spaces.windowSpaces(otherWin)
            if okSpaces and hs.fnutils.contains(okSpaces, currentSpace) then
                local app = otherWin:application()
                if app and isAppIncluded(app, otherWin) then
                    local originalFrame = otherWin:frame()
                    table.insert(simulatedFullscreen.hiddenWindows, { win = otherWin, frame = originalFrame })
                    -- Hide past bottom-right of screen
                    otherWin:setFrame(
                    geometry.rect({ x = screenFrame.x + screenFrame.w + 100, y = screenFrame.y + screenFrame.h + 100, w = 1, h = 1 }),
                        0)
                end
            end
        end
    end

    -- Maximize the window to fill screen
    win:setFrame(geometry.rect(screenFrame), 0)
    win:focus()

    -- Create overlays for the fullscreen window so user can exit or minimize
    timer.doAfter(0.1, function()
        if not simulatedFullscreen.active then return end
        local winId = win:id()
        if not winId then return end

        -- Clear any stale overlays first
        clearZoomOverlays()
        clearMinimizeOverlays()

        local zoomOverlay = createZoomOverlay(win)
        local minimizeOverlay = createMinimizeOverlay(win)

        if zoomOverlay then
            simulatedFullscreen.zoomOverlays[winId] = zoomOverlay
            log("Created zoom overlay for fullscreen window")
        else
            log("Failed to create zoom overlay for fullscreen window")
        end

        if minimizeOverlay then
            simulatedFullscreen.minimizeOverlays[winId] = minimizeOverlay
            log("Created minimize overlay for fullscreen window")
        else
            log("Failed to create minimize overlay for fullscreen window")
        end
    end)
end

createZoomOverlay = function(win)
    if not win then return nil end
    local winId = win:id()
    if not winId then return nil end

    local rect = getZoomButtonRect(win)
    if not rect then return nil end

    -- Make overlay slightly larger for easier clicking
    local padding = 4
    local overlayFrame = {
        x = rect.x - padding,
        y = rect.y - padding,
        w = rect.w + padding * 2,
        h = rect.h + padding * 2
    }

    local overlay = canvas.new(overlayFrame)
    overlay:appendElements({
        type = "rectangle",
        action = "fill",
        fillColor = { alpha = 0.01 }, -- Nearly invisible but clickable
        roundedRectRadii = { xRadius = 5, yRadius = 5 },
    })
    overlay:level(canvas.windowLevels.popUpMenu)
    overlay:clickActivating(false)
    overlay:canvasMouseEvents(true, true, false, false)

    overlay:mouseCallback(function(c, msg, id, x, y)
        if msg == "mouseUp" then
            if simulatedFullscreen.active and simulatedFullscreen.window and
                simulatedFullscreen.window:id() == winId then
                exitSimulatedFullscreen()
            else
                enterSimulatedFullscreen(win)
            end
        end
    end)

    overlay:show()
    return overlay
end

createMinimizeOverlay = function(win)
    if not win then return nil end
    local winId = win:id()
    if not winId then return nil end

    local rect = getMinimizeButtonRect(win)
    if not rect then return nil end

    -- Make overlay slightly larger for easier clicking
    local padding = 4
    local overlayFrame = {
        x = rect.x - padding,
        y = rect.y - padding,
        w = rect.w + padding * 2,
        h = rect.h + padding * 2
    }

    local overlay = canvas.new(overlayFrame)
    overlay:appendElements({
        type = "rectangle",
        action = "fill",
        fillColor = { alpha = 0.01 }, -- Nearly invisible but clickable
        roundedRectRadii = { xRadius = 5, yRadius = 5 },
    })
    overlay:level(canvas.windowLevels.popUpMenu)
    overlay:clickActivating(false)
    overlay:canvasMouseEvents(true, true, false, false)

    overlay:mouseCallback(function(c, msg, id, x, y)
        if msg == "mouseUp" then
            createSnapshot(win)
        end
    end)

    overlay:show()
    return overlay
end

local overlayUpdateTimer = nil

updateButtonOverlays = function()
    -- Don't update overlays if in simulated fullscreen or during snapshot creation
    if simulatedFullscreen.active then return end
    if windowSnapshots.isCreating then return end

    local currentSpace = getCurrentSpace()
    local activeWinIds = {}

    for _, win in ipairs(window.visibleWindows()) do
        local okSpaces = spaces.windowSpaces(win)
        local app = win:application()
        if okSpaces and hs.fnutils.contains(okSpaces, currentSpace) and
            app and isAppIncluded(app, win) and not win:isFullScreen() then
            local winId = win:id()
            if winId then
                activeWinIds[winId] = true

                local zoomRect = getZoomButtonRect(win)
                local minimizeRect = getMinimizeButtonRect(win)

                -- Update existing zoom overlay position, or create new one
                if zoomRect then
                    local padding = 4
                    local newFrame = {
                        x = zoomRect.x - padding,
                        y = zoomRect.y - padding,
                        w = zoomRect.w + padding * 2,
                        h = zoomRect.h + padding * 2
                    }
                    if simulatedFullscreen.zoomOverlays[winId] then
                        -- Just move existing overlay (avoids mouse state issues)
                        simulatedFullscreen.zoomOverlays[winId]:frame(newFrame)
                    else
                        -- Create new overlay
                        simulatedFullscreen.zoomOverlays[winId] = createZoomOverlay(win)
                    end
                end

                -- Update existing minimize overlay position, or create new one
                if minimizeRect then
                    local padding = 4
                    local newFrame = {
                        x = minimizeRect.x - padding,
                        y = minimizeRect.y - padding,
                        w = minimizeRect.w + padding * 2,
                        h = minimizeRect.h + padding * 2
                    }
                    if simulatedFullscreen.minimizeOverlays[winId] then
                        -- Just move existing overlay (avoids mouse state issues)
                        simulatedFullscreen.minimizeOverlays[winId]:frame(newFrame)
                    else
                        -- Create new overlay
                        simulatedFullscreen.minimizeOverlays[winId] = createMinimizeOverlay(win)
                    end
                end
            end
        end
    end

    -- Clean up overlays for windows that no longer exist
    for winId, overlay in pairs(simulatedFullscreen.zoomOverlays) do
        if not activeWinIds[winId] then
            overlay:delete()
            simulatedFullscreen.zoomOverlays[winId] = nil
        end
    end
    for winId, overlay in pairs(simulatedFullscreen.minimizeOverlays) do
        if not activeWinIds[winId] then
            overlay:delete()
            simulatedFullscreen.minimizeOverlays[winId] = nil
        end
    end
end

-- Debounced version to prevent rapid updates
local function updateButtonOverlaysDebounced()
    if overlayUpdateTimer then
        overlayUpdateTimer:stop()
    end
    overlayUpdateTimer = timer.doAfter(0.05, function()
        overlayUpdateTimer = nil
        updateButtonOverlays()
    end)
end

-- Update overlays with retries (AX elements need time to become available)
updateButtonOverlaysWithRetry = function()
    -- Multiple retries with increasing delays for reliable overlay creation
    timer.doAfter(0.1, function() updateButtonOverlays() end)
    timer.doAfter(0.3, function() updateButtonOverlays() end)
    timer.doAfter(0.6, function() updateButtonOverlays() end)
    timer.doAfter(1.0, function() updateButtonOverlays() end)
end


-- Periodic overlay refresh to keep them in sync (handles edge cases)
local overlayRefreshTimer = timer.doEvery(0.5, function()
    if not simulatedFullscreen.active and not windowSnapshots.isCreating then
        updateButtonOverlays()
    end
end)

-- Alias for backwards compatibility
local function updateZoomOverlays()
    updateButtonOverlays()
end

-- Check if fullscreen window lost focus - exit fullscreen if so
local function checkFullscreenFocus()
    if not simulatedFullscreen.active then return end

    local focused = window.focusedWindow()
    if not focused then
        exitSimulatedFullscreen()
        return
    end

    -- If focused window is different from fullscreen window, exit
    if simulatedFullscreen.window and focused:id() ~= simulatedFullscreen.window:id() then
        exitSimulatedFullscreen()
    end
end

local function handleWindowFocused(win)
    -- Check if we should exit simulated fullscreen due to focus change
    checkFullscreenFocus()

    -- Skip normal handling if in simulated fullscreen or during snapshot
    if simulatedFullscreen.active then return end
    if windowSnapshots.isCreating then return end

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
        -- Update overlays when focus changes (with retry for AX element availability)
        updateButtonOverlaysWithRetry()
    else
        if activeWindowOutline then
            activeWindowOutline:hide()
        end
    end
end

local function handleWindowEvent()
    -- Skip if in simulated fullscreen, during snapshot creation, or already tiling
    if simulatedFullscreen.active then return end
    if windowSnapshots.isCreating then return end
    if tilingCount > 0 then return end

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

    -- Update button overlays after windows are positioned (with retry for AX element availability)
    updateButtonOverlaysWithRetry()
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

    -- Skip during fullscreen, snapshot creation, or our own tiling to prevent loops
    if simulatedFullscreen.active then return end
    if windowSnapshots.isCreating then return end
    if tilingCount > 0 then return end

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
    local wasResized = sizeDiff > 20 -- threshold for resize detection

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


local initialFingerCount         = 0
local gestureStartTime           = 0
local lastActionTime             = 0
local gestureStartThreshold      = 0.15 -- Time to let all initial fingers settle before detecting +1
local lastTouchCount             = 0
local initialTouchIdentities     = {} -- Store touch identities instead of positions

-- Double-tap detection
local lastTapTime                = 0
local lastTapFingerCount         = 0
local doubleTapThreshold         = 0.35  -- Max time between taps for double-tap
local actionPerformedThisGesture = false -- Track if +1 action was performed
local fingersAddedDuringSettling = false -- Track if more fingers were added during settling (indicates failed +1)

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
        -- Only count as tap if: no +1 action performed AND fingers weren't added during settling
        if initialFingerCount == 3 and not actionPerformedThisGesture and not fingersAddedDuringSettling then
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
            initialFingerCount     = 0
            gestureStartTime       = 0
            initialTouchIdentities = {}
        end
        actionPerformedThisGesture = false
        fingersAddedDuringSettling = false
        lastTouchCount = 0
        return false
    end

    if initialFingerCount == 0 then
        if touchCount == 2 or touchCount == 3 or touchCount == 4 then
            initialFingerCount = touchCount
            gestureStartTime = currentTime
            initialTouchIdentities = {}
            for i = 1, touchCount do
                initialTouchIdentities[touches[i].identity] = true
            end
        end
    elseif touchCount > initialFingerCount and touchCount <= 4 and gestureStartTime and (currentTime - gestureStartTime < gestureStartThreshold) then
        -- More fingers added during settling period - update initial count
        -- Only mark as "not a tap" if we went from 2→3 (likely a fast 2+1 attempt)
        -- Going 1→3 is probably just a sloppy 3-finger tap, allow it
        if initialFingerCount == 2 and touchCount == 3 then
            fingersAddedDuringSettling = true
        end
        initialFingerCount = touchCount
        gestureStartTime = currentTime
        initialTouchIdentities = {}
        for i = 1, touchCount do
            initialTouchIdentities[touches[i].identity] = true
        end
    elseif touchCount >= initialFingerCount and gestureStartTime then
        if touchCount == initialFingerCount + 1 and currentTime - gestureStartTime > gestureStartThreshold then
            local additionalFingerPosition
            for i = 1, touchCount do
                -- Find the finger whose identity wasn't in the initial set
                if not initialTouchIdentities[touches[i].identity] then
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
                    actionPerformedThisGesture = true
                end
            end
        end
    end

    lastTouchCount = touchCount
    return false -- Don't consume event, let other taps receive it
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

    -- Toggle simulated fullscreen
    hotkey.bind(cfg.mods, "F", function()
        local win = window.focusedWindow()
        if simulatedFullscreen.active then
            exitSimulatedFullscreen()
        elseif win then
            enterSimulatedFullscreen(win)
        end
    end)

    if cfg.enableTTTaps then
        startTTTapsRecognition()
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

-- Right-click eventtap for snapshot context menus
local snapshotRightClickTap = eventtap.new({ eventtap.event.types.rightMouseDown }, function(e)
    local pos = mouse.absolutePosition()

    -- Check if click is within any snapshot
    for winId, data in pairs(windowSnapshots.windows) do
        if data.canvas then
            local frame = data.canvas:frame()
            if pos.x >= frame.x and pos.x <= frame.x + frame.w and
                pos.y >= frame.y and pos.y <= frame.y + frame.h then
                -- Show context menu
                showSnapshotContextMenu(winId, data)
                return true -- Consume the event
            end
        end
    end

    return false -- Let event pass through
end)
snapshotRightClickTap:start()

-- Keep alive & status ping
local function preventGC()
    pruneStaleSpaces()  -- Clean up stale space entries
    pruneStaleWeights() -- Clean up weights for closed windows
    -- Reference ttTaps to prevent garbage collection
    if ttTaps and not ttTaps:isEnabled() then
        log("TTTaps was disabled, restarting...")
        startTTTapsRecognition()
    end
end

hs.timer.doEvery(60, preventGC) -- Check every minute for GC'd eventtaps

local initialFocusedWindow = window.focusedWindow()
if initialFocusedWindow then
    drawActiveWindowOutline(initialFocusedWindow)
end

updateWindowOrder()
tileWindows()
bindHotkeys()
updateZoomOverlays()

log("WindowScape initialized" ..
    (cfg.enableTTTaps and " with TTTaps recognition" or " without TTTaps recognition") ..
    " and simulated fullscreen")

-- Public helper to restart the gesture recognizer manually
function restartWindowScapeTTTaps()
    if cfg.enableTTTaps then
        stopTTTapsRecognition()
        startTTTapsRecognition()
    end
end
