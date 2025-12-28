-- WindowScape: https://github.com/sryo/Spoons/blob/main/WindowScape.lua
-- This script automatically tiles windows.

local spacesOk, spaces = pcall(require, "hs.spaces")
if not spacesOk then
    -- Stub for missing hs.spaces
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

local cfg                 = {
    outlineColor          = { red = .1, green = .3, blue = .9, alpha = 0.8 },
    outlineColorPinned    = { red = .9, green = .6, blue = .1, alpha = 0.8 },
    outlineColorPseudo    = { red = .6, green = .1, blue = .9, alpha = 0.8 },
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
    eventDebounceSeconds  = 0.2, -- Increased to allow tab switch events to settle
    -- Animation settings
    enableAnimations      = true,
    animationDuration     = 0.15, -- seconds
    animationFPS          = 60,
    -- Layout mode: "weighted" (default), "dwindle", "master"
    layoutMode            = "weighted",
    -- Master layout settings
    masterRatio           = 0.55,   -- Master window takes 55% of space
    masterPosition        = "left", -- "left", "right", "top", "bottom"
    -- Debug logging (toggle with Ctrl+Cmd+D)
    debugLogging          = false,
}

local activeWindowOutline = nil
local ttTaps              = nil
local outlineRefreshTimer = nil
local lastOutlineFrame    = nil
local trackedFocusedWinId = nil
local outlineHideCounter  = 0 -- Counter to prevent hiding on momentary visibility glitches

-- Drag tracking state
local tilingCount         = 0   -- Counter to distinguish our moves from user drags (handles overlapping tiles)
local tilingStartTime     = 0   -- Timestamp when tilingCount was last incremented (for stuck detection)
local pendingReposition   = nil -- Timer for delayed reposition check


local listedApps          = {} -- bundleIDs or app names
local listPath            = hs.configdir .. "/WindowScape_apps.json"

local windowOrderBySpace  = {}
local windowWeights       = {} -- windowId -> weight (default 1.0)
local pseudoWindows       = {} -- windowId -> { preferredW, preferredH } (windows that maintain aspect ratio)
local windowLastScreen    = {} -- windowId -> screenId (tracks which screen each window was last on)

-- Focus history for "focus last" behavior
local focusHistory        = {} -- array of winIds, most recent first
local focusHistoryMax     = 10 -- keep last N focused windows

-- Track window IDs and frames to detect actual window creation/destruction vs tab switches
local lastKnownWindowIds  = {} -- Set of window IDs from last tile
local lastKnownWindowFrames = {} -- winId -> {app, frame} for detecting tab switches

-- Animation state
local activeAnimations    = {} -- winId -> { timer, startFrame, targetFrame, startTime }

-- Simulated fullscreen state
local simulatedFullscreen = {
    active = false,
    window = nil,
    hiddenWindows = {},    -- Windows we hid when entering fullscreen
    savedWeights = {},     -- Backup of weights before fullscreen
    zoomOverlays = {},     -- Canvas overlays on zoom buttons
    minimizeOverlays = {}, -- Canvas overlays on minimize buttons
    pinOverlays = {},      -- Canvas overlays on pin buttons
    closeOverlays = {},    -- Canvas overlays on close buttons
}

-- Snapshot thumbnails for "minimized" windows
local windowSnapshots     = {
    windows = {},        -- winId -> { win, canvas, originalFrame }
    order = {},          -- Array of winIds in order of minimization
    container = nil,     -- Canvas container for all thumbnails
    isCreating = false,  -- Prevent re-entrancy during snapshot creation
    isCreatingStart = 0, -- Timestamp when isCreating was set true (for stuck detection)
}

-- Focus the previously focused window (skipping minimized/hidden windows)
local function focusPreviousWindow(excludeWinId)
    for _, winId in ipairs(focusHistory) do
        if winId ~= excludeWinId then
            -- Check if window still exists and is visible
            local win = hs.window.get(winId)
            if win and win:isVisible() and not windowSnapshots.windows[winId] then
                win:focus()
                return true
            end
        end
    end
    return false
end

-- Forward declarations for functions used in timer callbacks
local createZoomOverlay
local createMinimizeOverlay
local createPinOverlay
local createCloseOverlay
local updateButtonOverlays
local updateButtonOverlaysWithRetry
local showSnapshotContextMenu
local hideSnapshotTooltip
local snapshotTooltipCurrentWinId

local function log(message)
    if cfg.debugLogging then
        print(os.date("%Y-%m-%d %H:%M:%S") .. " [WindowScape] " .. message)
    end
end

-- Parabolic easing function (ease-out cubic, like Hypr)
local function easeOutCubic(t)
    return 1 - math.pow(1 - t, 3)
end

-- Interpolate between two values
local function lerp(a, b, t)
    return a + (b - a) * t
end

-- Interpolate between two colors
local function lerpColor(c1, c2, t)
    return {
        red = lerp(c1.red or 0, c2.red or 0, t),
        green = lerp(c1.green or 0, c2.green or 0, t),
        blue = lerp(c1.blue or 0, c2.blue or 0, t),
        alpha = lerp(c1.alpha or 1, c2.alpha or 1, t),
    }
end

-- Cancel any running animation for a window
local function cancelAnimation(winId)
    if activeAnimations[winId] then
        if activeAnimations[winId].timer then
            activeAnimations[winId].timer:stop()
        end
        activeAnimations[winId] = nil
    end
end

-- Animated setFrame with parabolic easing
local function animatedSetFrame(win, targetFrame, onComplete)
    if not win then return end
    local winId = win:id()
    if not winId then
        win:setFrame(geometry.rect(targetFrame), 0)
        if onComplete then onComplete() end
        return
    end

    -- Cancel any existing animation for this window
    cancelAnimation(winId)

    -- If animations disabled, just set immediately
    if not cfg.enableAnimations then
        win:setFrame(geometry.rect(targetFrame), 0)
        if onComplete then onComplete() end
        return
    end

    local startFrame = win:frame()
    if not startFrame then
        win:setFrame(geometry.rect(targetFrame), 0)
        if onComplete then onComplete() end
        return
    end

    -- Skip animation if frames are nearly identical
    local dx = math.abs(startFrame.x - targetFrame.x)
    local dy = math.abs(startFrame.y - targetFrame.y)
    local dw = math.abs(startFrame.w - targetFrame.w)
    local dh = math.abs(startFrame.h - targetFrame.h)
    if dx < 2 and dy < 2 and dw < 2 and dh < 2 then
        win:setFrame(geometry.rect(targetFrame), 0)
        if onComplete then onComplete() end
        return
    end

    local startTime = timer.secondsSinceEpoch()
    local duration = cfg.animationDuration
    local interval = 1 / cfg.animationFPS

    local animTimer
    animTimer = timer.doEvery(interval, function()
        local elapsed = timer.secondsSinceEpoch() - startTime
        local t = math.min(elapsed / duration, 1)
        local ease = easeOutCubic(t)

        local currentFrame = {
            x = lerp(startFrame.x, targetFrame.x, ease),
            y = lerp(startFrame.y, targetFrame.y, ease),
            w = lerp(startFrame.w, targetFrame.w, ease),
            h = lerp(startFrame.h, targetFrame.h, ease),
        }

        win:setFrame(geometry.rect(currentFrame), 0)

        if t >= 1 then
            animTimer:stop()
            activeAnimations[winId] = nil
            -- Ensure final frame is exact
            win:setFrame(geometry.rect(targetFrame), 0)
            if onComplete then onComplete() end
        end
    end)

    activeAnimations[winId] = {
        timer = animTimer,
        startFrame = startFrame,
        targetFrame = targetFrame,
        startTime = startTime,
    }
end

-- Cancel all running animations
local function cancelAllAnimations()
    for winId, _ in pairs(activeAnimations) do
        cancelAnimation(winId)
    end
end

-- Safe wrapper for win:application() to avoid "Unable to fetch NSRunningApplication" errors
-- when the window's process has terminated but the window object still exists
local function safeGetApplication(win)
    if not win then return nil end
    local ok, app = pcall(function() return win:application() end)
    if ok and app then
        return app
    end
    return nil
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
    if not (app and win) then return false end
    if not win:isStandard() then return false end

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
        local app       = safeGetApplication(win)
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

local function getWindowWeight(win)
    if not win then return 1.0 end
    local winId = win:id()
    if not winId then return 1.0 end
    return windowWeights[winId] or 1.0
end

local function setWindowWeight(win, weight)
    if not win then return end
    local winId = win:id()
    if not winId then return end
    windowWeights[winId] = math.max(0.1, weight) -- Minimum 0.1 to prevent invisible windows
end

-- Clean up weights and focus history for closed windows
local function pruneStaleWeights()
    local validIds = {}
    for _, win in ipairs(window.allWindows()) do
        local winId = win:id()
        if winId then validIds[winId] = true end
    end
    -- Prune weights
    for winId in pairs(windowWeights) do
        if not validIds[winId] then
            windowWeights[winId] = nil
        end
    end
    -- Prune focus history
    for i = #focusHistory, 1, -1 do
        if not validIds[focusHistory[i]] then
            table.remove(focusHistory, i)
        end
    end
    -- Prune pseudo windows
    for winId in pairs(pseudoWindows) do
        if not validIds[winId] then
            pseudoWindows[winId] = nil
        end
    end
    -- Prune window screen tracking
    for winId in pairs(windowLastScreen) do
        if not validIds[winId] then
            windowLastScreen[winId] = nil
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

-- Snapshot column/row width
local snapshotColumnWidth = 140

-- Calculate snapshot size for a window - fills available width, height based on aspect ratio
local function getSnapshotSizeForWindow(winFrame)
    local w = snapshotColumnWidth - snapshotPadding * 2
    if not winFrame or winFrame.w <= 0 or winFrame.h <= 0 then
        return { w = w, h = math.floor(w * 0.66) } -- Default 3:2 aspect
    end

    local aspectRatio = winFrame.w / winFrame.h
    local h = math.floor(w / aspectRatio)

    -- Clamp height to reasonable bounds
    h = math.max(h, 30)
    h = math.min(h, 200)

    return { w = w, h = h }
end

-- Default snapshot size (used as fallback)
local function getSnapshotSize()
    return { w = snapshotColumnWidth - snapshotPadding * 2, h = 80 }
end

-- Get the reserved area for snapshots (returns nil if no snapshots on this screen)
local function getSnapshotReservedArea(scr)
    if #windowSnapshots.order == 0 then return nil end

    -- Check if any snapshots belong to this screen and calculate max height
    local scrId = scr:id()
    local maxSnapshotHeight = 0
    local hasSnapshotsOnScreen = false
    for _, winId in ipairs(windowSnapshots.order) do
        local data = windowSnapshots.windows[winId]
        if data and data.screenId == scrId then
            hasSnapshotsOnScreen = true
            local snapSize = data.snapSize or getSnapshotSize()
            if snapSize.h > maxSnapshotHeight then
                maxSnapshotHeight = snapSize.h
            end
        end
    end

    if not hasSnapshotsOnScreen then return nil end

    local frame = scr:frame()
    local isLandscape = frame.w > frame.h

    if isLandscape then
        -- Reserve column on right
        return {
            x = frame.x + frame.w - snapshotColumnWidth,
            y = frame.y,
            w = snapshotColumnWidth,
            h = frame.h
        }
    else
        -- Reserve row at bottom based on actual snapshot height
        local rowHeight = maxSnapshotHeight + snapshotPadding * 2
        return {
            x = frame.x,
            y = frame.y + frame.h - rowHeight,
            w = frame.w,
            h = rowHeight
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

-- Apply pseudotiling: center window within its tile slot if it has preferred size
local function applyPseudoTiling(win, tileFrame)
    local winId = win:id()
    if not winId or not pseudoWindows[winId] then
        return tileFrame
    end

    local pref = pseudoWindows[winId]
    local prefW = math.min(pref.preferredW, tileFrame.w)
    local prefH = math.min(pref.preferredH, tileFrame.h)

    -- Center within tile
    return {
        x = tileFrame.x + (tileFrame.w - prefW) / 2,
        y = tileFrame.y + (tileFrame.h - prefH) / 2,
        w = prefW,
        h = prefH,
    }
end

-- Dwindle layout: binary split each new window into smallest tile
local function tileDwindle(screenFrame, windows, horizontal)
    if #windows == 0 then return end

    -- First window takes full space
    local frames = {}
    frames[1] = { x = screenFrame.x, y = screenFrame.y, w = screenFrame.w, h = screenFrame.h }

    -- Each subsequent window splits the last tile
    for i = 2, #windows do
        local lastFrame = frames[i - 1]
        local splitHorizontal = (i % 2 == 0) == horizontal -- Alternate split direction

        if splitHorizontal then
            local halfW = math.floor((lastFrame.w - cfg.tileGap) / 2)
            frames[i - 1] = { x = lastFrame.x, y = lastFrame.y, w = halfW, h = lastFrame.h }
            frames[i] = {
                x = lastFrame.x + halfW + cfg.tileGap,
                y = lastFrame.y,
                w = lastFrame.w - halfW - cfg.tileGap,
                h =
                    lastFrame.h
            }
        else
            local halfH = math.floor((lastFrame.h - cfg.tileGap) / 2)
            frames[i - 1] = { x = lastFrame.x, y = lastFrame.y, w = lastFrame.w, h = halfH }
            frames[i] = {
                x = lastFrame.x,
                y = lastFrame.y + halfH + cfg.tileGap,
                w = lastFrame.w,
                h = lastFrame.h -
                    halfH - cfg.tileGap
            }
        end
    end

    -- Apply frames with animation and pseudotiling
    for i, win in ipairs(windows) do
        local finalFrame = applyPseudoTiling(win, frames[i])
        animatedSetFrame(win, finalFrame)
    end
end

-- Master-stack layout: one master window + stack of secondary windows
local function tileMaster(screenFrame, windows, horizontal)
    if #windows == 0 then return end

    local masterWin = windows[1]
    local stackWins = {}
    for i = 2, #windows do
        table.insert(stackWins, windows[i])
    end

    local masterFrame, stackFrame

    -- Determine master position based on config and orientation
    local masterLeft = (cfg.masterPosition == "left") or (cfg.masterPosition == "top")
    local masterHorizontal = (cfg.masterPosition == "left") or (cfg.masterPosition == "right")

    if horizontal then
        -- Landscape: master on left/right, stack on opposite side
        local masterW = math.floor(screenFrame.w * cfg.masterRatio)
        local stackW = screenFrame.w - masterW - cfg.tileGap

        if masterLeft then
            masterFrame = { x = screenFrame.x, y = screenFrame.y, w = masterW, h = screenFrame.h }
            stackFrame = { x = screenFrame.x + masterW + cfg.tileGap, y = screenFrame.y, w = stackW, h = screenFrame.h }
        else
            stackFrame = { x = screenFrame.x, y = screenFrame.y, w = stackW, h = screenFrame.h }
            masterFrame = { x = screenFrame.x + stackW + cfg.tileGap, y = screenFrame.y, w = masterW, h = screenFrame.h }
        end
    else
        -- Portrait: master on top/bottom, stack below/above
        local masterH = math.floor(screenFrame.h * cfg.masterRatio)
        local stackH = screenFrame.h - masterH - cfg.tileGap

        if masterLeft then
            masterFrame = { x = screenFrame.x, y = screenFrame.y, w = screenFrame.w, h = masterH }
            stackFrame = { x = screenFrame.x, y = screenFrame.y + masterH + cfg.tileGap, w = screenFrame.w, h = stackH }
        else
            stackFrame = { x = screenFrame.x, y = screenFrame.y, w = screenFrame.w, h = stackH }
            masterFrame = { x = screenFrame.x, y = screenFrame.y + stackH + cfg.tileGap, w = screenFrame.w, h = masterH }
        end
    end

    -- Set master window
    local finalMasterFrame = applyPseudoTiling(masterWin, masterFrame)
    animatedSetFrame(masterWin, finalMasterFrame)

    -- Stack windows vertically (landscape) or horizontally (portrait)
    if #stackWins > 0 then
        if horizontal then
            -- Stack vertically
            local stackItemH = math.floor((stackFrame.h - (#stackWins - 1) * cfg.tileGap) / #stackWins)
            local y = stackFrame.y
            for i, win in ipairs(stackWins) do
                local h = (i == #stackWins) and (stackFrame.y + stackFrame.h - y) or stackItemH
                local frame = { x = stackFrame.x, y = y, w = stackFrame.w, h = h }
                local finalFrame = applyPseudoTiling(win, frame)
                animatedSetFrame(win, finalFrame)
                y = y + h + cfg.tileGap
            end
        else
            -- Stack horizontally
            local stackItemW = math.floor((stackFrame.w - (#stackWins - 1) * cfg.tileGap) / #stackWins)
            local x = stackFrame.x
            for i, win in ipairs(stackWins) do
                local w = (i == #stackWins) and (stackFrame.x + stackFrame.w - x) or stackItemW
                local frame = { x = x, y = stackFrame.y, w = w, h = stackFrame.h }
                local finalFrame = applyPseudoTiling(win, frame)
                animatedSetFrame(win, finalFrame)
                x = x + w + cfg.tileGap
            end
        end
    end
end

-- Weighted layout (original behavior with animations)
local function tileWeighted(screenFrame, nonCollapsedWins, collapsedWins, horizontal)
    local numCollapsed = #collapsedWins
    local numNonCollapsed = #nonCollapsedWins

    if horizontal then
        local collapsedAreaHeight = (numCollapsed > 0) and (cfg.collapsedWindowHeight + cfg.tileGap) or 0
        local mainAreaHeight = screenFrame.h - collapsedAreaHeight

        -- Non-collapsed main area, tiled horizontally with weights
        if numNonCollapsed > 0 then
            local widths = distributeWeighted(screenFrame.w, cfg.tileGap, nonCollapsedWins)
            local x = screenFrame.x
            for i, win in ipairs(nonCollapsedWins) do
                local tileFrame = { x = x, y = screenFrame.y, w = widths[i], h = mainAreaHeight }
                local finalFrame = applyPseudoTiling(win, tileFrame)
                animatedSetFrame(win, finalFrame)
                x = x + widths[i] + cfg.tileGap
            end
        end

        -- Collapsed strip at the bottom
        if numCollapsed > 0 then
            local baseW, remW = distributeEven(screenFrame.w, cfg.tileGap, numCollapsed)
            local collapsedX = screenFrame.x
            local collapsedY = screenFrame.y + mainAreaHeight
            for i, win in ipairs(collapsedWins) do
                local w = baseW + ((i == numCollapsed) and remW or 0)
                local newFrame = { x = collapsedX, y = collapsedY, w = w, h = cfg.collapsedWindowHeight }
                animatedSetFrame(win, newFrame)
                collapsedX = collapsedX + w + cfg.tileGap
            end
        end
    else
        -- Vertical monitor layout
        local collapsedAreaHeight = 0
        if numCollapsed > 0 then
            collapsedAreaHeight = (cfg.collapsedWindowHeight + cfg.tileGap) * numCollapsed - cfg.tileGap
        end
        local mainAreaHeight = screenFrame.h - collapsedAreaHeight

        -- Non-collapsed main area, distributed heights with weights
        if numNonCollapsed > 0 then
            local heights = distributeWeighted(mainAreaHeight, cfg.tileGap, nonCollapsedWins)
            local y = screenFrame.y
            for i, win in ipairs(nonCollapsedWins) do
                local tileFrame = { x = screenFrame.x, y = y, w = screenFrame.w, h = heights[i] }
                local finalFrame = applyPseudoTiling(win, tileFrame)
                animatedSetFrame(win, finalFrame)
                y = y + heights[i] + cfg.tileGap
            end
        end

        -- Collapsed area
        if numCollapsed > 0 then
            local collapsedX = screenFrame.x
            local collapsedY = screenFrame.y + mainAreaHeight
            for _, win in ipairs(collapsedWins) do
                local newFrame = { x = collapsedX, y = collapsedY, w = screenFrame.w, h = cfg.collapsedWindowHeight }
                animatedSetFrame(win, newFrame)
                collapsedY = collapsedY + cfg.collapsedWindowHeight + cfg.tileGap
            end
        end
    end
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
                    -- Track which screen this window is on
                    local winId = win:id()
                    if winId then
                        windowLastScreen[winId] = screenId
                    end
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

        local horizontal = (screenFrame.w > screenFrame.h)

        -- Choose layout mode
        if cfg.layoutMode == "dwindle" then
            tileDwindle(screenFrame, nonCollapsedWins, horizontal)
            -- Handle collapsed windows in dwindle mode (just stack at bottom/right)
            if #collapsedWins > 0 then
                local baseW, remW = distributeEven(screenFrame.w, cfg.tileGap, #collapsedWins)
                local collapsedX = screenFrame.x
                local collapsedY = screenFrame.y + screenFrame.h - cfg.collapsedWindowHeight
                for i, win in ipairs(collapsedWins) do
                    local w = baseW + ((i == #collapsedWins) and remW or 0)
                    animatedSetFrame(win, { x = collapsedX, y = collapsedY, w = w, h = cfg.collapsedWindowHeight })
                    collapsedX = collapsedX + w + cfg.tileGap
                end
            end
        elseif cfg.layoutMode == "master" then
            tileMaster(screenFrame, nonCollapsedWins, horizontal)
            -- Handle collapsed windows in master mode
            if #collapsedWins > 0 then
                local baseW, remW = distributeEven(screenFrame.w, cfg.tileGap, #collapsedWins)
                local collapsedX = screenFrame.x
                local collapsedY = screenFrame.y + screenFrame.h - cfg.collapsedWindowHeight
                for i, win in ipairs(collapsedWins) do
                    local w = baseW + ((i == #collapsedWins) and remW or 0)
                    animatedSetFrame(win, { x = collapsedX, y = collapsedY, w = w, h = cfg.collapsedWindowHeight })
                    collapsedX = collapsedX + w + cfg.tileGap
                end
            end
        else
            -- Default: weighted layout
            tileWeighted(screenFrame, nonCollapsedWins, collapsedWins, horizontal)
        end

        ::continue::
    end
end

local tilingDelayTimer = nil

local function tileWindows()
    -- Don't tile if in simulated fullscreen or during snapshot creation
    if simulatedFullscreen.active then return end
    if windowSnapshots.isCreating then return end

    -- Cancel any running animations before starting new tile
    cancelAllAnimations()

    -- Cancel pending tilingCount decrement
    if tilingDelayTimer then
        tilingDelayTimer:stop()
        tilingDelayTimer = nil
    end

    tilingCount = 1 -- Reset to 1 instead of incrementing (prevents runaway count)
    tilingStartTime = timer.secondsSinceEpoch()
    local ok, err = pcall(tileWindowsInternal)
    if not ok then
        log("Error in tileWindowsInternal: " .. tostring(err))
    end
    -- Decrement after a brief delay to allow windowMoved events to fire
    -- Extend delay slightly for animations
    local delay = cfg.enableAnimations and (cfg.animationDuration + 0.1) or 0.15
    tilingDelayTimer = timer.doAfter(delay, function()
        tilingCount = 0
        tilingDelayTimer = nil
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

local function getOutlineColorForWindow(win)
    if not win then return cfg.outlineColor end
    local winId = win:id()
    if not winId then return cfg.outlineColor end

    -- Check if app is excluded from tiling (app-level only)
    local app = safeGetApplication(win)
    local isExcluded = app and not isAppIncluded(app, win)

    if isExcluded then
        return cfg.outlineColorPinned
    elseif pseudoWindows[winId] then
        return cfg.outlineColorPseudo
    end
    return cfg.outlineColor
end

-- Current outline color for animation
local currentOutlineColor = nil
local targetOutlineColor = nil
local outlineColorAnimTimer = nil

local function animateOutlineColor(targetColor)
    if not activeWindowOutline then return end
    if not targetColor then return end

    -- Check if target color is same as current target (avoid restarting same animation)
    if targetOutlineColor then
        local targetDiff = math.abs((targetOutlineColor.red or 0) - (targetColor.red or 0)) +
            math.abs((targetOutlineColor.green or 0) - (targetColor.green or 0)) +
            math.abs((targetOutlineColor.blue or 0) - (targetColor.blue or 0))
        if targetDiff < 0.01 then
            return -- Already animating to this color
        end
    end

    -- Stop existing animation
    if outlineColorAnimTimer then
        outlineColorAnimTimer:stop()
        outlineColorAnimTimer = nil
    end

    if not currentOutlineColor then
        currentOutlineColor = targetColor
        targetOutlineColor = targetColor
        activeWindowOutline:setStrokeColor(currentOutlineColor)
        return
    end

    -- Check if colors are already equal
    local colorDiff = math.abs((currentOutlineColor.red or 0) - (targetColor.red or 0)) +
        math.abs((currentOutlineColor.green or 0) - (targetColor.green or 0)) +
        math.abs((currentOutlineColor.blue or 0) - (targetColor.blue or 0))
    if colorDiff < 0.01 then
        currentOutlineColor = targetColor
        targetOutlineColor = targetColor
        activeWindowOutline:setStrokeColor(currentOutlineColor)
        return
    end

    targetOutlineColor = targetColor

    local startColor = {
        red = currentOutlineColor.red,
        green = currentOutlineColor.green,
        blue = currentOutlineColor.blue,
        alpha = currentOutlineColor.alpha
    }
    local startTime = timer.secondsSinceEpoch()
    local duration = 0.15 -- Faster animation

    outlineColorAnimTimer = timer.doEvery(0.016, function()
        local elapsed = timer.secondsSinceEpoch() - startTime
        local t = math.min(elapsed / duration, 1)
        local ease = easeOutCubic(t)

        currentOutlineColor = lerpColor(startColor, targetOutlineColor, ease)
        if activeWindowOutline then
            activeWindowOutline:setStrokeColor(currentOutlineColor)
        end

        if t >= 1 then
            outlineColorAnimTimer:stop()
            outlineColorAnimTimer = nil
        end
    end)
end

local function updateOutlineFrame(frame, win)
    if not frame then return end

    local adjustedFrame = { x = frame.x, y = frame.y, w = frame.w, h = frame.h }
    local targetColor = getOutlineColorForWindow(win)

    if not activeWindowOutline then
        log("CREATE outline at " .. adjustedFrame.x .. "," .. adjustedFrame.y)
        activeWindowOutline = drawing.rectangle(geometry.rect(adjustedFrame))
        currentOutlineColor = targetColor
        activeWindowOutline:setStrokeColor(currentOutlineColor)
        activeWindowOutline:setFill(false)
        activeWindowOutline:setStrokeWidth(cfg.outlineThickness)
        activeWindowOutline:setRoundedRectRadii(cfg.outlineThickness / 2, cfg.outlineThickness / 2)
        activeWindowOutline:setLevel(drawing.windowLevels.floating)
    else
        local framesMatch = framesEqual(adjustedFrame, lastOutlineFrame)
        if not framesMatch then
            local currentFrame = activeWindowOutline:frame()
            log("MOVING outline from " .. math.floor(currentFrame.x) .. "," .. math.floor(currentFrame.y) ..
                " to " .. math.floor(adjustedFrame.x) .. "," .. math.floor(adjustedFrame.y))
            activeWindowOutline:hide()
            activeWindowOutline:setFrame(geometry.rect(adjustedFrame))
        end
        animateOutlineColor(targetColor)
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
            updateOutlineFrame(frame, win)
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
    log("drawOutline: " .. (win and win:title() or "nil") .. " id:" .. tostring(win and win:id()))
    if win and win:isVisible() and not win:isFullScreen() and not isSystem(win) then
        local frame = win:frame()
        if not frame then return end

        trackedFocusedWinId = win:id()
        log("outline frame: " .. frame.x .. "," .. frame.y .. " " .. frame.w .. "x" .. frame.h)
        updateOutlineFrame(frame, win)
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
    local ok, result = pcall(function()
        local axWin = axuielement.windowElement(win)
        if not axWin then return nil end

        local zoomButton = axWin:attributeValue("AXZoomButton")
        if not zoomButton then return nil end

        local pos = zoomButton:attributeValue("AXPosition")
        local size = zoomButton:attributeValue("AXSize")
        if not (pos and size) then return nil end

        return { x = pos.x, y = pos.y, w = size.w, h = size.h }
    end)
    return ok and result or nil
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

local function clearPinOverlays()
    for _, overlay in pairs(simulatedFullscreen.pinOverlays) do
        if overlay then overlay:delete() end
    end
    simulatedFullscreen.pinOverlays = {}
end

local function clearCloseOverlays()
    for _, overlay in pairs(simulatedFullscreen.closeOverlays) do
        if overlay then overlay:delete() end
    end
    simulatedFullscreen.closeOverlays = {}
end

-- Remove a winId from the snapshot order list
local function removeFromSnapshotOrder(winId)
    -- Hide tooltip if it was showing for this snapshot
    if snapshotTooltipCurrentWinId == winId then
        hideSnapshotTooltip()
    end
    for i, id in ipairs(windowSnapshots.order) do
        if id == winId then
            table.remove(windowSnapshots.order, i)
            return
        end
    end
end

-- Snapshot Tooltip

local snapshotTooltipCanvas = nil
local snapshotTooltipFadeTimer = nil
local snapshotTooltipHideTimer = nil
snapshotTooltipCurrentWinId = nil -- forward declared

local function truncateMiddle(input, maxLength)
    maxLength = maxLength or 40
    if #input > maxLength then
        local partLen = math.floor(maxLength / 2)
        input = input:sub(1, partLen - 2) .. '...' .. input:sub(-partLen)
    end
    return input
end

local function initSnapshotTooltip()
    if snapshotTooltipCanvas then return end
    snapshotTooltipCanvas = canvas.new({ x = 0, y = 0, w = 1, h = 1 })
    snapshotTooltipCanvas:level(canvas.windowLevels._MaximumWindowLevelKey)
    snapshotTooltipCanvas:appendElements({
        type = "rectangle",
        action = "fill",
        roundedRectRadii = { xRadius = 4, yRadius = 4 },
        fillColor = { white = 0, alpha = 0.75 }
    })
    snapshotTooltipCanvas:appendElements({
        type = "text",
        text = "",
        textLineBreak = "wordWrap",
        frame = { x = 0, y = 0, w = "100%", h = "100%" }
    })
    snapshotTooltipCanvas:behavior("canJoinAllSpaces")
end

local function showSnapshotTooltip(winId, snapFrame)
    local data = windowSnapshots.windows[winId]
    if not data or not data.win then
        return
    end

    local title = data.win:title() or "Untitled"
    local app = safeGetApplication(data.win)
    local appName = app and app:name() or ""

    -- Format: Two lines - App name (bold) and Window title
    local message
    if appName ~= "" and title ~= "" and appName ~= title then
        message = appName .. "\n" .. title
    elseif appName ~= "" then
        message = appName
    else
        message = title
    end

    initSnapshotTooltip()

    if snapshotTooltipFadeTimer then
        snapshotTooltipFadeTimer:stop()
        snapshotTooltipFadeTimer = nil
    end
    if snapshotTooltipHideTimer then
        snapshotTooltipHideTimer:stop()
        snapshotTooltipHideTimer = nil
    end

    local fontSize = 12
    local padding = 8
    local maxWidth = 180

    -- Truncate each line if too long
    local lines = {}
    for line in message:gmatch("[^\n]+") do
        if #line > 30 then
            line = line:sub(1, 27) .. "..."
        end
        table.insert(lines, line)
    end
    local truncatedMessage = table.concat(lines, "\n")

    local styledMessage = hs.styledtext.new(truncatedMessage, {
        font = { size = fontSize },
        color = { white = 1, alpha = 1 },
        paragraphStyle = { alignment = "center" },
        shadow = {
            offset = { h = -1, w = 0 },
            blurRadius = 2,
            color = { alpha = 1 }
        }
    })

    local textSize = hs.drawing.getTextDrawingSize(styledMessage)
    local tooltipW = math.min(textSize.w, maxWidth) + padding * 2
    local tooltipH = textSize.h + padding

    -- Position tooltip centered vertically on the snapshot, to the left
    local tooltipX = snapFrame.x - tooltipW - 8
    local tooltipY = snapFrame.y + (snapFrame.h - tooltipH) / 2

    -- Ensure tooltip stays on screen
    local scr = screen.mainScreen()
    local scrFrame = scr:frame()

    -- If tooltip would go off left edge, show on right side of snapshot
    if tooltipX < scrFrame.x then
        tooltipX = snapFrame.x + snapFrame.w + 8
    end

    -- Clamp vertical position
    if tooltipY < scrFrame.y then tooltipY = scrFrame.y + 4 end
    if tooltipY + tooltipH > scrFrame.y + scrFrame.h then
        tooltipY = scrFrame.y + scrFrame.h - tooltipH - 4
    end

    local tooltipFrame = { x = tooltipX, y = tooltipY, w = tooltipW, h = tooltipH }
    snapshotTooltipCanvas:frame(tooltipFrame)
    snapshotTooltipCanvas:elementAttribute(1, "fillColor", { white = 0, alpha = 0.75 })
    snapshotTooltipCanvas:elementAttribute(2, "text", styledMessage)
    snapshotTooltipCanvas:alpha(1)
    snapshotTooltipCanvas:show()

    snapshotTooltipCurrentWinId = winId
end

hideSnapshotTooltip = function()
    if not snapshotTooltipCanvas then return end

    if snapshotTooltipFadeTimer then
        snapshotTooltipFadeTimer:stop()
        snapshotTooltipFadeTimer = nil
    end

    local fadeOutDuration = 0.125
    local fadeOutStep = 0.025
    local fadeOutAlphaStep = fadeOutStep / fadeOutDuration
    local currentAlpha = snapshotTooltipCanvas:alpha()

    local function fade()
        currentAlpha = currentAlpha - fadeOutAlphaStep
        if currentAlpha > 0 then
            snapshotTooltipCanvas:alpha(currentAlpha)
            snapshotTooltipFadeTimer = timer.doAfter(fadeOutStep, fade)
        else
            snapshotTooltipCanvas:hide()
            snapshotTooltipFadeTimer = nil
            snapshotTooltipCurrentWinId = nil
        end
    end

    fade()
end

-- Button Tooltip

local buttonTooltipCanvas = nil
local buttonTooltipHideTimer = nil

local function showButtonTooltip(text, x, y)
    if not buttonTooltipCanvas then
        buttonTooltipCanvas = canvas.new({ x = 0, y = 0, w = 1, h = 1 })
        buttonTooltipCanvas:level(canvas.windowLevels._MaximumWindowLevelKey)
        buttonTooltipCanvas:appendElements({
            type = "rectangle",
            action = "fill",
            roundedRectRadii = { xRadius = 4, yRadius = 4 },
            fillColor = { white = 0, alpha = 0.8 }
        })
        buttonTooltipCanvas:appendElements({
            type = "text",
            text = "",
            textLineBreak = "clip",
            frame = { x = 0, y = 0, w = "100%", h = "100%" }
        })
    end

    if buttonTooltipHideTimer then
        buttonTooltipHideTimer:stop()
        buttonTooltipHideTimer = nil
    end

    local fontSize = 12
    local styledText = hs.styledtext.new(text, {
        font = { size = fontSize },
        color = { white = 1, alpha = 1 },
        paragraphStyle = { alignment = "center" },
    })

    local textSize = hs.drawing.getTextDrawingSize(styledText)
    local padding = 6
    local tooltipW = textSize.w + padding * 2
    local tooltipH = textSize.h + 2

    -- Position below the button
    local tooltipX = x - tooltipW / 2
    local tooltipY = y + 20

    -- Clamp tooltip to screen bounds
    local mouseScreen = hs.mouse.getCurrentScreen()
    if mouseScreen then
        local scrFrame = mouseScreen:frame()
        -- Clamp X
        if tooltipX < scrFrame.x then
            tooltipX = scrFrame.x
        elseif tooltipX + tooltipW > scrFrame.x + scrFrame.w then
            tooltipX = scrFrame.x + scrFrame.w - tooltipW
        end
        -- Clamp Y
        if tooltipY + tooltipH > scrFrame.y + scrFrame.h then
            tooltipY = y - tooltipH - 5 -- Show above button instead
        end
    end

    buttonTooltipCanvas:frame({ x = tooltipX, y = tooltipY, w = tooltipW, h = tooltipH })
    buttonTooltipCanvas:elementAttribute(2, "text", styledText)
    buttonTooltipCanvas:show()

    buttonTooltipHideTimer = timer.doAfter(2, function()
        if buttonTooltipCanvas then
            buttonTooltipCanvas:hide()
        end
        buttonTooltipHideTimer = nil
    end)
end

local function hideButtonTooltip()
    if buttonTooltipHideTimer then
        buttonTooltipHideTimer:stop()
        buttonTooltipHideTimer = nil
    end
    if buttonTooltipCanvas then
        buttonTooltipCanvas:hide()
    end
end

local function updateSnapshotLayout()
    if #windowSnapshots.order == 0 then return end

    -- Group snapshots by screen
    local snapshotsByScreen = {}
    for _, winId in ipairs(windowSnapshots.order) do
        local data = windowSnapshots.windows[winId]
        if data and data.canvas and data.screenId then
            if not snapshotsByScreen[data.screenId] then
                snapshotsByScreen[data.screenId] = {}
            end
            table.insert(snapshotsByScreen[data.screenId], { winId = winId, data = data })
        end
    end

    -- Layout snapshots for each screen
    for _, scr in ipairs(screen.allScreens()) do
        local scrId = scr:id()
        local screenSnapshots = snapshotsByScreen[scrId]
        if screenSnapshots and #screenSnapshots > 0 then
            local frame = scr:frame()
            local isLandscape = frame.w > frame.h

            local currentY = frame.y + snapshotPadding
            local currentX = frame.x + snapshotPadding

            for _, item in ipairs(screenSnapshots) do
                local data = item.data
                local snapSize = data.snapSize or getSnapshotSize()
                local x, y
                if isLandscape then
                    -- Stack vertically on right edge
                    x = frame.x + frame.w - snapshotColumnWidth + snapshotPadding
                    y = currentY
                    currentY = currentY + snapSize.h + snapshotGap
                else
                    -- Stack horizontally at bottom
                    x = currentX
                    y = frame.y + frame.h - snapSize.h - snapshotPadding
                    currentX = currentX + snapSize.w + snapshotGap
                end
                data.canvas:topLeft({ x = x, y = y })
            end
        end
    end
end

-- Refresh snapshot images to reflect current window content
-- After initial refreshes, slow down to save CPU
local snapshotRefreshCount = 0
local snapshotSlowRefreshInterval = 10 -- After 10 fast refreshes, slow down

local function refreshSnapshots()
    local ok, err = pcall(function()
        if windowSnapshots.isCreating then return end

        local count = 0
        for _ in pairs(windowSnapshots.windows) do count = count + 1 end

        if count == 0 then
            snapshotRefreshCount = 0
            return
        end

        -- After initial fast refreshes, only refresh every 10th call (every 5 seconds)
        snapshotRefreshCount = snapshotRefreshCount + 1
        if snapshotRefreshCount > snapshotSlowRefreshInterval then
            if snapshotRefreshCount % 10 ~= 0 then
                return
            end
        end

        for winId, data in pairs(windowSnapshots.windows) do
            if data and data.canvas then
                -- Use snapshotForID with keepTransparency=true to capture off-screen windows
                local newSnapshot = hs.window.snapshotForID(winId, true)
                if newSnapshot then
                    data.canvas[2].image = newSnapshot
                end
            end
        end
    end)
    if not ok then
        print("[WindowScape] refreshSnapshots error: " .. tostring(err))
    end
end

-- Timer to periodically refresh snapshots (every 0.5 seconds)
-- Store in windowSnapshots table to prevent garbage collection
windowSnapshots.refreshTimer = timer.doEvery(0.5, refreshSnapshots)

local function restoreFromSnapshot(winId)
    local data = windowSnapshots.windows[winId]
    if not data then return end

    local win = data.win
    if not win or not safeGetApplication(win) then
        -- Window no longer exists, just clean up
        if data.dragTap then
            data.dragTap:stop()
        end
        if data.canvas then
            data.canvas:delete()
        end
        windowSnapshots.windows[winId] = nil
        removeFromSnapshotOrder(winId)
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
        if data.dragTap then
            data.dragTap:stop()
        end
        if data.canvas then
            data.canvas:delete()
        end
        windowSnapshots.windows[winId] = nil
        removeFromSnapshotOrder(winId)
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
    animCanvas:level(canvas.windowLevels.floating)
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

            if data.dragTap then
                data.dragTap:stop()
            end
            if data.canvas then
                data.canvas:delete()
            end
            windowSnapshots.windows[winId] = nil
            removeFromSnapshotOrder(winId)

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
    windowSnapshots.isCreatingStart = timer.secondsSinceEpoch()

    local winFrame = win:frame()
    local scr = win:screen() or screen.mainScreen() -- Use window's screen, fallback to main
    local scrFrame = scr:frame()
    local scrId = scr:id()

    -- Take snapshot before hiding - this can be slow
    local snapshot = win:snapshot()
    if not snapshot then
        windowSnapshots.isCreating = false
        print("[WindowScape] Could not take snapshot of window, aborting minimize")
        return
    end

    local snapSize = getSnapshotSizeForWindow(winFrame)

    -- Add placeholder to snapshot order BEFORE hiding/retiling so space gets reserved
    windowSnapshots.windows[winId] = {
        win = win,
        canvas = nil, -- Will be set after animation
        originalFrame = winFrame,
        snapSize = snapSize,
        screenId = scrId, -- Store which screen this snapshot belongs to
    }
    table.insert(windowSnapshots.order, winId)

    -- Hide the window IMMEDIATELY after snapshot (before any calculations)
    win:setFrame(
        geometry.rect({
            x = scrFrame.x + scrFrame.w + 100,
            y = scrFrame.y + scrFrame.h + 100,
            w = winFrame.w,
            h = winFrame.h
        }),
        0)

    -- Immediately retile and focus previous window (don't wait for animation)
    -- Use tileWindowsInternal directly since isCreating flag would block tileWindows()
    updateWindowOrder()
    tileWindowsInternal()
    focusPreviousWindow(winId)

    -- Draw outline for newly focused window immediately
    local newFocused = window.focusedWindow()
    if newFocused and newFocused:id() ~= winId then
        drawActiveWindowOutline(newFocused)
    end
    local isLandscape = scrFrame.w > scrFrame.h

    -- Calculate target position by summing existing snapshot heights/widths on the SAME screen
    local targetX, targetY
    if isLandscape then
        targetX = scrFrame.x + scrFrame.w - snapshotColumnWidth + snapshotPadding
        targetY = scrFrame.y + snapshotPadding
        -- Add heights of existing snapshots on the same screen (excluding current one)
        for _, existingWinId in ipairs(windowSnapshots.order) do
            if existingWinId ~= winId then
                local data = windowSnapshots.windows[existingWinId]
                if data and data.snapSize and data.screenId == scrId then
                    targetY = targetY + data.snapSize.h + snapshotGap
                end
            end
        end
    else
        targetY = scrFrame.y + scrFrame.h - snapSize.h - snapshotPadding
        targetX = scrFrame.x + snapshotPadding
        -- Add widths of existing snapshots on the same screen (excluding current one)
        for _, existingWinId in ipairs(windowSnapshots.order) do
            if existingWinId ~= winId then
                local data = windowSnapshots.windows[existingWinId]
                if data and data.snapSize and data.screenId == scrId then
                    targetX = targetX + data.snapSize.w + snapshotGap
                end
            end
        end
    end

    -- Create animation canvas at window's current position
    local animCanvas = canvas.new(winFrame)
    animCanvas:appendElements({
        type = "image",
        image = snapshot,
        frame = { x = 0, y = 0, w = "100%", h = "100%" },
        imageScaling = "scaleProportionally",
    })
    animCanvas:level(canvas.windowLevels.floating)
    animCanvas:show()

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
                imageScaling = "scaleProportionally",
            })

            -- Add close button indicator (small X in left corner)
            snapshotCanvas:appendElements({
                type = "circle",
                action = "fill",
                center = { x = 10, y = 10 },
                radius = 6,
                fillColor = { red = 0.8, green = 0.2, blue = 0.2, alpha = 0.8 },
            })

            -- Add app icon in bottom-center
            local app = safeGetApplication(win)
            if app then
                local appIcon = app:bundleID() and hs.image.imageFromAppBundle(app:bundleID())
                if appIcon then
                    local iconSize = 32
                    snapshotCanvas:appendElements({
                        type = "image",
                        image = appIcon,
                        frame = { x = (snapSize.w - iconSize) / 2, y = snapSize.h - iconSize - 4, w = iconSize, h = iconSize },
                        imageScaling = "scaleToFit",
                    })
                end
            end

            snapshotCanvas:level(canvas.windowLevels.floating)
            snapshotCanvas:clickActivating(false)
            snapshotCanvas:canvasMouseEvents(true, true, true, true) -- Enable enter/exit events

            -- Store state for zoom animation
            local zoomScale = 1.1
            local isZoomed = false
            local zoomAnimTimer = nil

            -- Smooth zoom animation using canvas transformation
            local function animateZoom(canv, fromScale, toScale, duration)
                if zoomAnimTimer then zoomAnimTimer:stop() end

                local startTime = timer.secondsSinceEpoch()
                local fps = 60
                local interval = 1 / fps
                local data = windowSnapshots.windows[winId]
                if not data then return end

                -- Get the base position (unzoomed center)
                local baseX = data.baseX or canv:frame().x
                local baseY = data.baseY or canv:frame().y

                zoomAnimTimer = timer.doEvery(interval, function()
                    local elapsed = timer.secondsSinceEpoch() - startTime
                    local t = math.min(elapsed / duration, 1)
                    local ease = easeOutCubic(t)
                    local currentScale = lerp(fromScale, toScale, ease)

                    -- Calculate new size and position to keep centered
                    local newW = data.snapSize.w * currentScale
                    local newH = data.snapSize.h * currentScale
                    local offsetX = (data.snapSize.w - newW) / 2
                    local offsetY = (data.snapSize.h - newH) / 2

                    canv:frame({
                        x = baseX + offsetX,
                        y = baseY + offsetY,
                        w = newW,
                        h = newH
                    })

                    -- Scale all internal elements proportionally
                    canv:transformation(hs.canvas.matrix.scale(currentScale))

                    if t >= 1 then
                        zoomAnimTimer:stop()
                        zoomAnimTimer = nil
                    end
                end)
            end

            -- Drag state for this snapshot
            local isDragging = false
            local dragStartMousePos = nil
            local dragStartCanvasFrame = nil
            local dragThreshold = 5 -- Pixels to move before considering it a drag

            snapshotCanvas:mouseCallback(function(c, msg, id, x, y)
                if msg == "mouseEnter" then
                    -- Show tooltip on hover (only if not dragging)
                    if not isDragging then
                        local snapFrame = c:frame()
                        showSnapshotTooltip(winId, snapFrame)
                        -- Zoom in animation
                        if not isZoomed then
                            isZoomed = true
                            local data = windowSnapshots.windows[winId]
                            if data then
                                -- Store base position before zooming
                                local currentFrame = c:frame()
                                data.baseX = currentFrame.x
                                data.baseY = currentFrame.y
                                animateZoom(c, 1.0, zoomScale, 0.1)
                            end
                        end
                    end
                elseif msg == "mouseExit" then
                    -- Hide tooltip when leaving (only if not dragging)
                    if not isDragging then
                        hideSnapshotTooltip()
                        -- Zoom out animation
                        if isZoomed then
                            isZoomed = false
                            animateZoom(c, zoomScale, 1.0, 0.1)
                        end
                    end
                elseif msg == "mouseDown" then
                    -- Check for right-click
                    local buttons = mouse.getButtons()
                    if buttons.right then
                        showSnapshotContextMenu(winId, windowSnapshots.windows[winId])
                        return
                    end
                    -- Start potential drag
                    dragStartMousePos = mouse.absolutePosition()
                    dragStartCanvasFrame = c:frame()
                    isDragging = false -- Will become true once we exceed threshold
                elseif msg == "mouseUp" then
                    local wasDragging = isDragging
                    local mousePos = mouse.absolutePosition()

                    -- Reset drag state
                    isDragging = false
                    dragStartMousePos = nil
                    dragStartCanvasFrame = nil

                    -- Hide tooltip on click
                    hideSnapshotTooltip()

                    if wasDragging then
                        -- Drag ended - check which screen the snapshot is now on
                        local canvasFrame = c:frame()
                        local centerX = canvasFrame.x + canvasFrame.w / 2
                        local centerY = canvasFrame.y + canvasFrame.h / 2

                        -- Find which screen contains the center of the snapshot
                        local targetScreen = nil
                        for _, scr in ipairs(screen.allScreens()) do
                            local scrFrame = scr:frame()
                            if centerX >= scrFrame.x and centerX < scrFrame.x + scrFrame.w and
                                centerY >= scrFrame.y and centerY < scrFrame.y + scrFrame.h then
                                targetScreen = scr
                                break
                            end
                        end

                        -- Update screenId if dropped on a different screen
                        local data = windowSnapshots.windows[winId]
                        if data and targetScreen then
                            local newScreenId = targetScreen:id()
                            if data.screenId ~= newScreenId then
                                data.screenId = newScreenId
                                -- Also update the original frame to restore to the new screen
                                local newScreenFrame = targetScreen:frame()
                                data.originalFrame = {
                                    x = newScreenFrame.x + (newScreenFrame.w - data.originalFrame.w) / 2,
                                    y = newScreenFrame.y + (newScreenFrame.h - data.originalFrame.h) / 2,
                                    w = data.originalFrame.w,
                                    h = data.originalFrame.h
                                }
                            end
                        end

                        -- Re-layout all snapshots and retile windows
                        updateSnapshotLayout()
                        tileWindows()
                    else
                        -- It was a click, not a drag
                        local buttons = mouse.getButtons()
                        if buttons.right then return end

                        -- Check if clicked on close button (top-left corner)
                        if x < 20 and y < 20 then
                            -- Close the window
                            if win and safeGetApplication(win) then
                                win:close()
                            end
                            if windowSnapshots.windows[winId] then
                                if windowSnapshots.windows[winId].dragTap then
                                    windowSnapshots.windows[winId].dragTap:stop()
                                end
                                if windowSnapshots.windows[winId].canvas then
                                    windowSnapshots.windows[winId].canvas:delete()
                                end
                                windowSnapshots.windows[winId] = nil
                                removeFromSnapshotOrder(winId)
                                updateSnapshotLayout()
                                updateWindowOrder()
                                tileWindows()
                            end
                        else
                            -- Restore the window
                            restoreFromSnapshot(winId)
                        end
                    end
                end
            end)

            -- Separate drag tracking using eventtap (since canvas doesn't get mouseDragged reliably)
            local dragTap = nil
            dragTap = eventtap.new({ eventtap.event.types.leftMouseDragged }, function(e)
                if not dragStartMousePos or not dragStartCanvasFrame then return false end

                local currentPos = mouse.absolutePosition()
                local dx = currentPos.x - dragStartMousePos.x
                local dy = currentPos.y - dragStartMousePos.y

                -- Check if we've exceeded drag threshold
                if not isDragging and (math.abs(dx) > dragThreshold or math.abs(dy) > dragThreshold) then
                    isDragging = true
                    -- Cancel zoom animation when drag starts
                    if isZoomed then
                        isZoomed = false
                        if zoomAnimTimer then
                            zoomAnimTimer:stop()
                            zoomAnimTimer = nil
                        end
                        -- Reset to normal size
                        local data = windowSnapshots.windows[winId]
                        if data then
                            snapshotCanvas:frame({
                                x = dragStartCanvasFrame.x,
                                y = dragStartCanvasFrame.y,
                                w = data.snapSize.w,
                                h = data.snapSize.h
                            })
                            snapshotCanvas:transformation(hs.canvas.matrix.identity())
                        end
                    end
                    hideSnapshotTooltip()
                end

                if isDragging then
                    -- Move the canvas with the mouse
                    local data = windowSnapshots.windows[winId]
                    if data then
                        snapshotCanvas:topLeft({
                            x = dragStartCanvasFrame.x + dx,
                            y = dragStartCanvasFrame.y + dy
                        })
                    end
                end

                return false -- Don't consume the event
            end)

            -- Start the drag tap when canvas is created
            dragTap:start()

            snapshotCanvas:show()

            -- Update the placeholder with the actual canvas and store the drag tap
            if windowSnapshots.windows[winId] then
                windowSnapshots.windows[winId].canvas = snapshotCanvas
                windowSnapshots.windows[winId].dragTap = dragTap
            end

            windowSnapshots.isCreating = false

            -- Update snapshot layout and button overlays (retile already done)
            updateSnapshotLayout()
            updateButtonOverlaysWithRetry()

            -- Ensure outline is visible for focused window
            local focused = window.focusedWindow()
            if focused then
                drawActiveWindowOutline(focused)
            end
        end
    end)
end

local function clearAllSnapshots()
    for winId, data in pairs(windowSnapshots.windows) do
        if data.dragTap then
            data.dragTap:stop()
        end
        if data.canvas then
            data.canvas:delete()
        end
    end
    windowSnapshots.windows = {}
    windowSnapshots.order = {}
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
        if data.win and safeGetApplication(data.win) then
            data.win:close()
        end
        if data.dragTap then
            data.dragTap:stop()
        end
        if data.canvas then
            data.canvas:delete()
        end
    end
    windowSnapshots.windows = {}
    windowSnapshots.order = {}
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
                if data.win and safeGetApplication(data.win) then
                    data.win:close()
                end
                if windowSnapshots.windows[winId] then
                    if windowSnapshots.windows[winId].dragTap then
                        windowSnapshots.windows[winId].dragTap:stop()
                    end
                    if windowSnapshots.windows[winId].canvas then
                        windowSnapshots.windows[winId].canvas:delete()
                    end
                    windowSnapshots.windows[winId] = nil
                    removeFromSnapshotOrder(winId)
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

    local menu = hs.menubar.new(false)
    menu:setMenu(menuItems)
    menu:popupMenu(mouse.absolutePosition(), true)
    -- Clean up after a delay
    timer.doAfter(0.1, function()
        menu:delete()
    end)
end

local function getMinimizeButtonRect(win)
    if not win then return nil end
    local ok, result = pcall(function()
        local axWin = axuielement.windowElement(win)
        if not axWin then return nil end

        local minimizeButton = axWin:attributeValue("AXMinimizeButton")
        if not minimizeButton then return nil end

        local pos = minimizeButton:attributeValue("AXPosition")
        local size = minimizeButton:attributeValue("AXSize")
        if not (pos and size) then return nil end

        return { x = pos.x, y = pos.y, w = size.w, h = size.h }
    end)
    return ok and result or nil
end

local function getCloseButtonRect(win)
    if not win then return nil end
    local ok, result = pcall(function()
        local axWin = axuielement.windowElement(win)
        if not axWin then return nil end

        local closeButton = axWin:attributeValue("AXCloseButton")
        if not closeButton then return nil end

        local pos = closeButton:attributeValue("AXPosition")
        local size = closeButton:attributeValue("AXSize")
        if not (pos and size) then return nil end

        return { x = pos.x, y = pos.y, w = size.w, h = size.h }
    end)
    return ok and result or nil
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

    for _, data in ipairs(simulatedFullscreen.hiddenWindows) do
        if data.win and safeGetApplication(data.win) and data.frame then
            data.win:setFrame(geometry.rect(data.frame), 0)
        end
    end
    simulatedFullscreen.hiddenWindows = {}
    simulatedFullscreen.window = nil

    clearCloseOverlays()
    clearZoomOverlays()
    clearMinimizeOverlays()
    clearPinOverlays()

    updateWindowOrder()
    tileWindows()

    local focused = window.focusedWindow()
    if focused then
        drawActiveWindowOutline(focused)
    end

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
    clearCloseOverlays()
    clearZoomOverlays()
    clearMinimizeOverlays()
    clearPinOverlays()

    -- Hide all other windows on this space by moving them off-screen
    local currentSpace = getCurrentSpace()
    for _, otherWin in ipairs(window.visibleWindows()) do
        if otherWin:id() ~= win:id() then
            local okSpaces = spaces.windowSpaces(otherWin)
            if okSpaces and hs.fnutils.contains(okSpaces, currentSpace) then
                local app = safeGetApplication(otherWin)
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

    -- Check if window actually filled the screen (some apps like IINA maintain aspect ratio)
    -- If not, center the window
    timer.doAfter(0.05, function()
        if not simulatedFullscreen.active then return end
        local actualFrame = win:frame()
        if not actualFrame then return end

        -- If window is smaller than screen, center it
        if actualFrame.w < screenFrame.w or actualFrame.h < screenFrame.h then
            local centeredX = screenFrame.x + (screenFrame.w - actualFrame.w) / 2
            local centeredY = screenFrame.y + (screenFrame.h - actualFrame.h) / 2
            win:setFrame(geometry.rect({
                x = centeredX,
                y = centeredY,
                w = actualFrame.w,
                h = actualFrame.h
            }), 0)
        end
    end)

    -- Create overlays for the fullscreen window so user can exit or minimize
    timer.doAfter(0.15, function()
        if not simulatedFullscreen.active then return end
        local winId = win:id()
        if not winId then return end

        -- Clear any stale overlays first
        clearCloseOverlays()
        clearZoomOverlays()
        clearMinimizeOverlays()
        clearPinOverlays()

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
    overlay:level(canvas.windowLevels.floating)
    overlay:clickActivating(false)
    overlay:canvasMouseEvents(true, true, true, true)

    overlay:mouseCallback(function(c, msg, id, x, y)
        local frame = c:frame()
        local centerX = frame.x + frame.w / 2
        local centerY = frame.y + frame.h / 2

        if msg == "mouseEnter" then
            c:elementAttribute(1, "fillColor", { green = 0.6, alpha = 0.3 })
            showButtonTooltip("Fullscreen", centerX, centerY)
        elseif msg == "mouseExit" then
            c:elementAttribute(1, "fillColor", { alpha = 0.01 })
            hideButtonTooltip()
        elseif msg == "mouseDown" then
            c:elementAttribute(1, "fillColor", { green = 0.8, alpha = 0.5 })
        elseif msg == "mouseUp" then
            hideButtonTooltip()

            local currentWin = hs.window.get(winId)
            if not currentWin then return end

            if simulatedFullscreen.active and simulatedFullscreen.window and
                simulatedFullscreen.window:id() == winId then
                exitSimulatedFullscreen()
            else
                enterSimulatedFullscreen(currentWin)
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
    overlay:level(canvas.windowLevels.floating)
    overlay:clickActivating(false)
    overlay:canvasMouseEvents(true, true, true, true)

    overlay:mouseCallback(function(c, msg, id, x, y)
        local frame = c:frame()
        local centerX = frame.x + frame.w / 2
        local centerY = frame.y + frame.h / 2

        if msg == "mouseEnter" then
            c:elementAttribute(1, "fillColor", { red = 0.9, green = 0.6, alpha = 0.3 })
            showButtonTooltip("Minimize", centerX, centerY)
        elseif msg == "mouseExit" then
            c:elementAttribute(1, "fillColor", { alpha = 0.01 })
            hideButtonTooltip()
        elseif msg == "mouseDown" then
            c:elementAttribute(1, "fillColor", { red = 0.9, green = 0.6, alpha = 0.5 })
        elseif msg == "mouseUp" then
            hideButtonTooltip()
            createSnapshot(win)
        end
    end)

    overlay:show()
    return overlay
end

-- Helper to update pin overlay appearance based on state
local function updatePinOverlayAppearance(overlay, isPinned)
    if not overlay then return end
    -- Use elementAttribute to properly update the canvas element
    -- Element 1 is the hover highlight, element 2 is the main circle indicator
    local newColor = isPinned
        and { red = 0.9, green = 0.6, blue = 0.1, alpha = 0.9 } -- Orange when pinned
        or { red = 0.3, green = 0.3, blue = 0.3, alpha = 0.6 }  -- Gray when unpinned
    overlay:elementAttribute(2, "fillColor", newColor)
end

-- Helper to calculate pin button frame for a window
local function getPinButtonFrame(win)
    if not win then return nil end

    local winFrame = win:frame()
    if not winFrame then return nil end

    -- Try to get actual titlebar height from close button position
    local titlebarHeight = 28 -- Default macOS titlebar height
    local ok, _ = pcall(function()
        local axWin = axuielement.windowElement(win)
        if axWin then
            local closeButton = axWin:attributeValue("AXCloseButton")
            if closeButton then
                local pos = closeButton:attributeValue("AXPosition")
                if pos then
                    -- Titlebar is roughly twice the distance from top to close button center
                    titlebarHeight = (pos.y - winFrame.y + 7) * 2
                end
            end
        end
    end)

    local buttonSize = 14
    local buttonMargin = 12

    return {
        x = winFrame.x + winFrame.w - buttonSize - buttonMargin,
        y = winFrame.y + (titlebarHeight - buttonSize) / 2,
        w = buttonSize,
        h = buttonSize
    }
end

createPinOverlay = function(win)
    if not win then return nil end
    local winId = win:id()
    if not winId then return nil end

    local rect = getPinButtonFrame(win)
    if not rect then return nil end

    local app = safeGetApplication(win)
    -- App is "excluded" if in exclusion list (app-level only now)
    local isExcluded = app and not isAppIncluded(app, win)

    -- Make overlay slightly larger for easier clicking (same as other buttons)
    local padding = 4
    local overlayFrame = {
        x = rect.x - padding,
        y = rect.y - padding,
        w = rect.w + padding * 2,
        h = rect.h + padding * 2
    }

    local overlay = canvas.new(overlayFrame)
    -- Element 1: hover highlight rectangle (same style as close/minimize/fullscreen)
    overlay:appendElements({
        type = "rectangle",
        action = "fill",
        fillColor = { alpha = 0.01 }, -- Nearly invisible but clickable
        roundedRectRadii = { xRadius = 5, yRadius = 5 },
    })
    -- Element 2: Circle indicator
    local baseColor = isExcluded
        and { red = 0.9, green = 0.6, blue = 0.1, alpha = 0.9 } -- Orange when excluded
        or { red = 0.3, green = 0.3, blue = 0.3, alpha = 0.6 }  -- Gray when included
    local centerX = overlayFrame.w / 2
    local centerY = overlayFrame.h / 2
    local radius = rect.w / 2
    overlay:appendElements({
        type = "circle",
        action = "fill",
        center = { x = centerX, y = centerY },
        radius = radius,
        fillColor = baseColor,
    })
    -- Element 3: Pin icon (vertical line) - centered in circle
    overlay:appendElements({
        type = "segments",
        action = "stroke",
        strokeColor = { white = 1, alpha = 0.9 },
        strokeWidth = 1.5,
        coordinates = {
            { x = centerX, y = centerY - radius + 2 },
            { x = centerX, y = centerY + radius - 2 },
        },
    })
    -- Element 4: Pin icon (horizontal line at top) - centered in circle
    overlay:appendElements({
        type = "segments",
        action = "stroke",
        strokeColor = { white = 1, alpha = 0.9 },
        strokeWidth = 1.5,
        coordinates = {
            { x = centerX - radius + 3, y = centerY - radius + 4 },
            { x = centerX + radius - 3, y = centerY - radius + 4 },
        },
    })

    overlay:level(canvas.windowLevels.floating)
    overlay:clickActivating(false)
    overlay:canvasMouseEvents(true, true, true, true)

    overlay:mouseCallback(function(c, msg, id, x, y)
        local frame = c:frame()
        local centerX = frame.x + frame.w / 2
        local centerY = frame.y + frame.h / 2

        -- Re-fetch window by ID to get current excluded state
        local currentWin = hs.window.get(winId)
        local currentApp = currentWin and safeGetApplication(currentWin)
        local currentlyExcluded = currentApp and not isAppIncluded(currentApp, currentWin)

        if msg == "mouseEnter" then
            -- Show highlight on hover (same style as other buttons)
            local hoverColor = currentlyExcluded
                and { red = 0.9, green = 0.6, blue = 0.1, alpha = 0.3 }
                or { red = 0.5, green = 0.5, blue = 0.5, alpha = 0.3 }
            c:elementAttribute(1, "fillColor", hoverColor)
            local tooltipText = currentlyExcluded and "Include in Tiling" or "Exclude from Tiling"
            showButtonTooltip(tooltipText, centerX, centerY)
        elseif msg == "mouseExit" then
            c:elementAttribute(1, "fillColor", { alpha = 0.01 })
            hideButtonTooltip()
        elseif msg == "mouseDown" then
            -- Press feedback - brighter highlight
            local pressColor = currentlyExcluded
                and { red = 0.9, green = 0.6, blue = 0.1, alpha = 0.5 }
                or { red = 0.5, green = 0.5, blue = 0.5, alpha = 0.5 }
            c:elementAttribute(1, "fillColor", pressColor)
        elseif msg == "mouseUp" then
            hideButtonTooltip()

            if not currentWin then return end

            -- Toggle app-level exclusion (same as double 3-finger tap)
            local clickedApp = safeGetApplication(currentWin)
            if not clickedApp then return end

            local bundleID = clickedApp:bundleID()
            local appName = clickedApp:name()
            local wasExcluded = (bundleID and listedApps[bundleID]) or (appName and listedApps[appName])

            if wasExcluded then
                -- Remove from exclusion list (include in tiling)
                if bundleID then listedApps[bundleID] = nil end
                if appName then listedApps[appName] = nil end
                log("Included app in tiling: " .. (appName or bundleID or "unknown"))
            else
                -- Add to exclusion list (exclude from tiling)
                if bundleID then
                    listedApps[bundleID] = true
                elseif appName then
                    listedApps[appName] = true
                end
                log("Excluded app from tiling: " .. (appName or bundleID or "unknown"))
            end

            saveList()
            -- Hide outline BEFORE retiling to avoid duplicate
            stopOutlineRefresh()
            if activeWindowOutline then activeWindowOutline:hide() end
            -- Retile windows
            updateWindowOrder()
            tileWindows()
            -- Update all button overlays (appearance will be updated for all windows of this app)
            updateButtonOverlaysWithRetry()
            -- Update outline color AFTER tiling to ensure correct state
            timer.doAfter(0.1, function()
                local focusedWin = window.focusedWindow()
                if focusedWin then
                    drawActiveWindowOutline(focusedWin)
                end
            end)
        end
    end)

    overlay:show()
    return overlay
end

createCloseOverlay = function(win)
    if not win then return nil end
    local winId = win:id()
    if not winId then return nil end

    local rect = getCloseButtonRect(win)
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
    overlay:level(canvas.windowLevels.floating)
    overlay:clickActivating(false)
    overlay:canvasMouseEvents(true, true, true, true)

    overlay:mouseCallback(function(c, msg, id, x, y)
        local frame = c:frame()
        local centerX = frame.x + frame.w / 2
        local centerY = frame.y + frame.h / 2

        if msg == "mouseEnter" then
            c:elementAttribute(1, "fillColor", { red = 0.9, green = 0.2, blue = 0.2, alpha = 0.3 })
            showButtonTooltip("Close", centerX, centerY)
        elseif msg == "mouseExit" then
            c:elementAttribute(1, "fillColor", { alpha = 0.01 })
            hideButtonTooltip()
        elseif msg == "mouseDown" then
            c:elementAttribute(1, "fillColor", { red = 1.0, green = 0.3, blue = 0.3, alpha = 0.5 })
        elseif msg == "mouseUp" then
            hideButtonTooltip()

            local currentWin = hs.window.get(winId)
            if not currentWin then return end

            -- Close the window - handleWindowEvent will update everything
            currentWin:close()
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
    local activeWinIds = {}      -- Windows included in tiling (for zoom/minimize overlays)
    local allStandardWinIds = {} -- All standard windows (for pin overlays)
    local focusedWin = window.focusedWindow()
    local focusedWinId = focusedWin and focusedWin:id()

    for _, win in ipairs(window.visibleWindows()) do
        local okSpaces = spaces.windowSpaces(win)
        local app = safeGetApplication(win)
        local winId = win:id()

        if not winId then goto continue end
        if not okSpaces or not hs.fnutils.contains(okSpaces, currentSpace) then goto continue end
        if win:isFullScreen() then goto continue end

        -- Check if this is a standard window (for pin overlay)
        local isStandard = win:isStandard() and app
        -- Check if window is collapsed (too small for pin button)
        local sz = win:size()
        local isCollapsed = sz and sz.h <= cfg.collapsedWindowHeight

        -- Only show pin overlay on focused window
        if isStandard and not isCollapsed and winId == focusedWinId then
            allStandardWinIds[winId] = true

            -- Update pin overlay for focused window only
            local pinRect = getPinButtonFrame(win)
            if pinRect then
                -- App is "excluded" if in exclusion list (app-level only)
                local isExcluded = app and not isAppIncluded(app, win)
                local padding = 4
                local pinFrame = {
                    x = pinRect.x - padding,
                    y = pinRect.y - padding,
                    w = pinRect.w + padding * 2,
                    h = pinRect.h + padding * 2
                }
                if simulatedFullscreen.pinOverlays[winId] then
                    simulatedFullscreen.pinOverlays[winId]:frame(pinFrame)
                    -- Update appearance based on whether window is excluded from tiling
                    updatePinOverlayAppearance(simulatedFullscreen.pinOverlays[winId], isExcluded)
                else
                    local newOverlay = createPinOverlay(win)
                    if newOverlay then
                        simulatedFullscreen.pinOverlays[winId] = newOverlay
                        updatePinOverlayAppearance(newOverlay, isExcluded)
                    end
                end
            end
        end

        -- Only process zoom/minimize/close overlays for windows included in tiling
        if app and isAppIncluded(app, win) then
            activeWinIds[winId] = true

            local closeRect = getCloseButtonRect(win)
            local zoomRect = getZoomButtonRect(win)
            local minimizeRect = getMinimizeButtonRect(win)

            -- Update existing close overlay position, or create new one
            if closeRect then
                local padding = 4
                local newFrame = {
                    x = closeRect.x - padding,
                    y = closeRect.y - padding,
                    w = closeRect.w + padding * 2,
                    h = closeRect.h + padding * 2
                }
                if simulatedFullscreen.closeOverlays[winId] then
                    simulatedFullscreen.closeOverlays[winId]:frame(newFrame)
                else
                    local newOverlay = createCloseOverlay(win)
                    if newOverlay then
                        simulatedFullscreen.closeOverlays[winId] = newOverlay
                    end
                end
            end

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
                    simulatedFullscreen.zoomOverlays[winId]:frame(newFrame)
                else
                    local newOverlay = createZoomOverlay(win)
                    if newOverlay then
                        simulatedFullscreen.zoomOverlays[winId] = newOverlay
                    end
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
                    simulatedFullscreen.minimizeOverlays[winId]:frame(newFrame)
                else
                    local newOverlay = createMinimizeOverlay(win)
                    if newOverlay then
                        simulatedFullscreen.minimizeOverlays[winId] = newOverlay
                    end
                end
            end
        end

        ::continue::
    end

    -- Clean up overlays for windows that no longer exist
    for winId, overlay in pairs(simulatedFullscreen.closeOverlays) do
        if not activeWinIds[winId] then
            overlay:delete()
            simulatedFullscreen.closeOverlays[winId] = nil
        end
    end
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
    for winId, overlay in pairs(simulatedFullscreen.pinOverlays) do
        if not allStandardWinIds[winId] then
            overlay:delete()
            simulatedFullscreen.pinOverlays[winId] = nil
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


-- Periodic overlay refresh to keep them in sync (handles edge cases like autohiding sidebars)
-- Store in simulatedFullscreen to prevent garbage collection
simulatedFullscreen.overlayRefreshTimer = timer.doEvery(0.5, function()
    if not simulatedFullscreen.active and not windowSnapshots.isCreating then
        updateButtonOverlays()
    end
end)

-- Alias for backwards compatibility
local function updateZoomOverlays()
    updateButtonOverlays()
end

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

local focusDebounceTimer = nil
local lastKnownFocusedId = nil

-- Backup focus polling - catches focus changes that don't fire windowFocused events
local focusPollTimer = nil

local function focusPollCallback()
    local win = window.focusedWindow()
    if not win then return end
    local winId = win:id()
    if winId and winId ~= lastKnownFocusedId then
        lastKnownFocusedId = winId
        if win:isVisible() and not win:isFullScreen() and not isSystem(win) then
            drawActiveWindowOutline(win)
        end
    end
end

local function startFocusPollTimer()
    if focusPollTimer then
        focusPollTimer:stop()
    end
    focusPollTimer = timer.doEvery(0.1, focusPollCallback)
    -- Store global reference to prevent garbage collection
    _G.WindowScapeFocusPollTimer = focusPollTimer
    _G.WindowScapeFocusPollCallback = focusPollCallback
end

local function handleWindowFocused(win)
    log("windowFocused: " .. (win and win:title() or "nil") .. " id:" .. tostring(win and win:id()))
    -- Check if we should exit simulated fullscreen due to focus change
    checkFullscreenFocus()

    -- Skip normal handling if in simulated fullscreen or during snapshot
    if simulatedFullscreen.active then return end
    if windowSnapshots.isCreating then return end

    -- Debounce rapid focus changes (Terminal fires multiple events quickly)
    if focusDebounceTimer then
        focusDebounceTimer:stop()
    end

    focusDebounceTimer = timer.doAfter(0.05, function()
        focusDebounceTimer = nil
        -- Get the ACTUAL focused window now, after settling
        local actualWin = window.focusedWindow()
        if not actualWin then return end
        lastKnownFocusedId = actualWin:id()  -- Update so poll doesn't double-trigger

        if actualWin:isVisible() and not actualWin:isFullScreen() and not isSystem(actualWin) then
            -- Track focus history
            local winId = actualWin:id()
            if winId then
                -- Remove this window from history if it exists
                for i = #focusHistory, 1, -1 do
                    if focusHistory[i] == winId then
                        table.remove(focusHistory, i)
                    end
                end
                -- Add to front
                table.insert(focusHistory, 1, winId)
                -- Trim to max size
                while #focusHistory > focusHistoryMax do
                    table.remove(focusHistory)
                end
            end

            drawActiveWindowOutline(actualWin)
            updateButtonOverlaysWithRetry()
        else
            if activeWindowOutline then
                activeWindowOutline:hide()
            end
        end
    end)
end

local function handleWindowEvent()
    -- Skip if in simulated fullscreen, during snapshot creation, or already tiling
    if simulatedFullscreen.active then return end
    if windowSnapshots.isCreating then return end
    if tilingCount > 0 then return end

    -- Check if the set of tiled windows actually changed
    -- This filters out tab switches which fire windowCreated but don't change the window set
    local currentSpace = getCurrentSpace()
    local currentWindowIds = {}
    local currentWindowData = {} -- winId -> {app, frame}

    for _, win in ipairs(window.visibleWindows()) do
        local okSpaces = spaces.windowSpaces(win)
        local app = safeGetApplication(win)
        local winId = win:id()
        if winId and okSpaces and hs.fnutils.contains(okSpaces, currentSpace) and
           not win:isFullScreen() and isAppIncluded(app, win) then
            currentWindowIds[winId] = true
            local frame = win:frame()
            local appId = app and (app:bundleID() or app:name()) or "unknown"
            currentWindowData[winId] = { app = appId, frame = frame }
        end
    end

    -- Find new and removed windows
    local newWindows = {}
    local removedWindows = {}

    for winId in pairs(currentWindowIds) do
        if not lastKnownWindowIds[winId] then
            table.insert(newWindows, winId)
        end
    end

    for winId in pairs(lastKnownWindowIds) do
        if not currentWindowIds[winId] then
            table.insert(removedWindows, winId)
        end
    end

    -- Check if new windows are just tab switches
    -- Method 1: Same app window added and removed (regardless of position)
    -- Method 2: New window overlaps with existing window from same app
    local isTabSwitch = false

    -- Method 1: If adding AND removing windows from the same app, it's a tab switch
    if #newWindows > 0 and #removedWindows > 0 then
        for _, newId in ipairs(newWindows) do
            local newData = currentWindowData[newId]
            if newData then
                for _, oldId in ipairs(removedWindows) do
                    local oldData = lastKnownWindowFrames[oldId]
                    if oldData and oldData.app == newData.app then
                        -- Same app adding and removing - definitely a tab switch
                        isTabSwitch = true
                        break
                    end
                end
            end
            if isTabSwitch then break end
        end
    end

    -- Method 2: Check if new window overlaps with existing window from same app (stale old tab)
    if not isTabSwitch and #newWindows > 0 then
        for _, newId in ipairs(newWindows) do
            local newData = currentWindowData[newId]
            if newData then
                for existingId, existingData in pairs(currentWindowData) do
                    if existingId ~= newId and existingData.app == newData.app then
                        -- Same app, different window - check if frames overlap significantly
                        local frameDiff = math.abs(newData.frame.x - existingData.frame.x) +
                                         math.abs(newData.frame.y - existingData.frame.y) +
                                         math.abs(newData.frame.w - existingData.frame.w) +
                                         math.abs(newData.frame.h - existingData.frame.h)
                        if frameDiff < 500 then
                            isTabSwitch = true
                            break
                        end
                    end
                end
            end
            if isTabSwitch then break end
        end
    end

    -- Update tracking
    lastKnownWindowIds = currentWindowIds
    lastKnownWindowFrames = currentWindowData

    if isTabSwitch then
        return
    end

    if #newWindows == 0 and #removedWindows == 0 then
        return
    end

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

    local focusedApp = safeGetApplication(focusedWindow)
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
    -- Update outline color for focused window
    drawActiveWindowOutline(focusedWindow)
    updateButtonOverlaysWithRetry()
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

-- Drag-to-reposition handling
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
    local winId = win:id()

    -- Skip during fullscreen or snapshot creation
    if simulatedFullscreen.active then return end
    if windowSnapshots.isCreating then return end

    -- Skip newly created windows - they're handled by handleWindowEvent
    -- This prevents tab switches from triggering extra retiles via windowMoved
    if winId and not lastKnownWindowIds[winId] then
        return
    end

    -- Always update outline for the focused window, even during tiling
    local focusedWin = window.focusedWindow()
    if focusedWin and focusedWin:id() == winId then
        drawActiveWindowOutline(focusedWin)
    end

    -- Skip tiling logic during our own tiling to prevent loops
    if tilingCount > 0 then return end

    -- Skip if THIS window is currently being animated (but allow others)
    if winId and activeAnimations[winId] then return end

    local app = safeGetApplication(win)
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
    local screenFrame = getAdjustedScreenFrame(winScreen) -- Use adjusted frame to match tiling
    local screenId = winScreen:id()
    local horizontal = (screenFrame.w > screenFrame.h)

    -- Check if window moved to a different screen
    local previousScreenId = windowLastScreen[winId]
    if previousScreenId and previousScreenId ~= screenId then
        -- Window changed screens - trigger full retile immediately
        if pendingReposition then
            pendingReposition:stop()
            pendingReposition = nil
        end
        windowLastScreen[winId] = screenId -- Update tracking
        updateWindowOrder()
        tileWindows()
        return
    end

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

    -- Also detect cross-axis resize (vertical in landscape, horizontal in portrait)
    -- These should trigger immediate retile to snap back to proper size
    local collapsedAreaHeight = (#getCollapsedWindows(screenWindows) > 0) and (cfg.collapsedWindowHeight + cfg.tileGap) or
        0
    local expectedCrossSize = horizontal
        and (screenFrame.h - collapsedAreaHeight)
        or screenFrame.w
    local actualCrossSize = horizontal and capturedFrame.h or capturedFrame.w
    local crossSizeDiff = math.abs(actualCrossSize - expectedCrossSize)
    local wasCrossResized = crossSizeDiff > 20

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

    -- Cross-axis resize (e.g., vertical resize in landscape mode)
    -- Just retile immediately to snap back to proper size, no weight adjustment
    if wasCrossResized then
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
local initialTouchIdentities     = {}   -- Store touch identities instead of positions

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
        updateButtonOverlaysWithRetry()
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

    -- Force retile (reset stuck flags and retile)
    hotkey.bind(cfg.mods, "R", function()
        log("Force retile triggered")
        tilingCount = 0
        windowSnapshots.isCreating = false
        updateWindowOrder()
        tileWindows()
        updateButtonOverlaysWithRetry()
    end)

    -- Split ratio adjustment (+/- like Hypr)
    hotkey.bind(cfg.mods, "=", function()
        local win = window.focusedWindow()
        if not win then return end
        local currentWeight = getWindowWeight(win)
        setWindowWeight(win, currentWeight + 0.1)
        tileWindows()
        updateButtonOverlaysWithRetry()
        log("Increased weight to " .. string.format("%.1f", getWindowWeight(win)))
    end)

    hotkey.bind(cfg.mods, "-", function()
        local win = window.focusedWindow()
        if not win then return end
        local currentWeight = getWindowWeight(win)
        setWindowWeight(win, currentWeight - 0.1)
        tileWindows()
        updateButtonOverlaysWithRetry()
        log("Decreased weight to " .. string.format("%.1f", getWindowWeight(win)))
    end)

    -- Master ratio adjustment (in master layout)
    hotkey.bind(cfg.mods, "]", function()
        cfg.masterRatio = math.min(cfg.masterRatio + 0.05, 0.9)
        tileWindows()
        updateButtonOverlaysWithRetry()
        log("Master ratio: " .. string.format("%.0f%%", cfg.masterRatio * 100))
    end)

    hotkey.bind(cfg.mods, "[", function()
        cfg.masterRatio = math.max(cfg.masterRatio - 0.05, 0.1)
        tileWindows()
        updateButtonOverlaysWithRetry()
        log("Master ratio: " .. string.format("%.0f%%", cfg.masterRatio * 100))
    end)

    -- Cycle layout modes
    hotkey.bind(cfg.mods, "L", function()
        local modes = { "weighted", "dwindle", "master" }
        local currentIndex = 1
        for i, mode in ipairs(modes) do
            if mode == cfg.layoutMode then
                currentIndex = i
                break
            end
        end
        local nextIndex = (currentIndex % #modes) + 1
        cfg.layoutMode = modes[nextIndex]
        tileWindows()
        updateButtonOverlaysWithRetry()
        log("Layout mode: " .. cfg.layoutMode)
    end)

    -- Toggle pseudotiling for focused window
    hotkey.bind(cfg.mods, "P", function()
        local win = window.focusedWindow()
        if not win then return end
        local winId = win:id()
        if not winId then return end

        if pseudoWindows[winId] then
            -- Remove from pseudo
            pseudoWindows[winId] = nil
            log("Disabled pseudotiling for " .. (win:title() or "untitled"))
        else
            -- Add to pseudo with current size as preferred
            local frame = win:frame()
            pseudoWindows[winId] = {
                preferredW = frame.w,
                preferredH = frame.h,
            }
            log("Enabled pseudotiling for " .. (win:title() or "untitled"))
        end
        tileWindows()
        updateButtonOverlaysWithRetry()
        drawActiveWindowOutline(win) -- Update outline color
    end)

    -- Toggle animations
    hotkey.bind(cfg.mods, "A", function()
        cfg.enableAnimations = not cfg.enableAnimations
        if not cfg.enableAnimations then
            cancelAllAnimations()
        end
        log("Animations: " .. (cfg.enableAnimations and "enabled" or "disabled"))
    end)

    -- Toggle debug logging (Ctrl+Cmd+D)
    hotkey.bind(cfg.mods, "D", function()
        cfg.debugLogging = not cfg.debugLogging
        print("[WindowScape] Debug logging: " .. (cfg.debugLogging and "ON" or "OFF"))
    end)

    -- Show what Hammerspoon thinks is focused (Ctrl+Cmd+F)
    hotkey.bind(cfg.mods, "F", function()
        local win = window.focusedWindow()
        if win then
            local frame = win:frame()
            print("[WindowScape] HS thinks focused: " .. (win:title() or "nil") .. " id:" .. tostring(win:id()) .. " at " .. frame.x .. "," .. frame.y)
        else
            print("[WindowScape] HS thinks no window is focused")
        end
        print("[WindowScape] lastKnownFocusedId: " .. tostring(lastKnownFocusedId))
    end)

    if cfg.enableTTTaps then
        startTTTapsRecognition()
    end
end

local function handleWindowDestroyed(win)
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
local function debouncedHandleWindowEvent(win, appName, eventName)
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
    -- Note: windowsChanged removed - it fires on title changes (e.g., terminal tab switches)
    -- which caused unnecessary retiling. The specific events above cover actual window changes.
}, debouncedHandleWindowEvent)

-- Separate handler for windowMoved to support drag-to-reposition
window.filter.default:subscribe(window.filter.windowMoved, handleWindowMoved)

window.filter.default:subscribe(window.filter.windowDestroyed, handleWindowDestroyed)
window.filter.default:subscribe(window.filter.windowFocused, handleWindowFocused)

-- Prevent accidental minimization: since we use off-screen storage instead of true minimize,
-- any window that gets truly minimized bypassed our overlay and should be unminimized
window.filter.default:subscribe(window.filter.windowMinimized, function(win)
    if not win then return end
    local winId = win:id()
    if not winId then return end

    -- If this window is in our snapshot system, it shouldn't be minimized (we use off-screen storage)
    -- If it's not in our snapshot system, it was minimized via the actual button - recover it
    if not windowSnapshots.windows[winId] then
        log("Recovering accidentally minimized window: " .. (win:title() or "untitled"))
        timer.doAfter(0.1, function()
            if win and win:isMinimized() then
                win:unminimize()
                win:focus()
                -- Re-tile after recovery
                timer.doAfter(0.2, function()
                    updateWindowOrder()
                    tileWindows()
                    updateButtonOverlaysWithRetry()
                end)
            end
        end)
    end
end)

spaces.watcher.new(function(_)
    -- Hide outline immediately on space switch to prevent lingering
    if activeWindowOutline then
        activeWindowOutline:hide()
    end
    stopOutlineRefresh()
    -- Then handle the window event which will redraw outline for new space
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

    -- Watchdog: reset stuck flags that block tiling
    local now = timer.secondsSinceEpoch()
    local stuckThreshold = 5 -- seconds

    if tilingCount > 0 and (now - tilingStartTime) > stuckThreshold then
        log("Watchdog: tilingCount stuck at " ..
            tilingCount .. " for " .. math.floor(now - tilingStartTime) .. "s, resetting")
        tilingCount = 0
    end

    if windowSnapshots.isCreating and (now - windowSnapshots.isCreatingStart) > stuckThreshold then
        log("Watchdog: isCreating stuck for " .. math.floor(now - windowSnapshots.isCreatingStart) .. "s, resetting")
        windowSnapshots.isCreating = false
    end

    -- Reference ttTaps to prevent garbage collection
    if ttTaps and not ttTaps:isEnabled() then
        log("TTTaps was disabled, restarting...")
        startTTTapsRecognition()
    end

    -- Reference focusPollTimer to prevent garbage collection
    if focusPollTimer and not focusPollTimer:running() then
        log("Focus poll timer stopped, restarting...")
        startFocusPollTimer()
    end
end

hs.timer.doEvery(10, preventGC) -- Check every 10 seconds for stuck flags and GC'd eventtaps

local initialFocusedWindow = window.focusedWindow()
if initialFocusedWindow then
    drawActiveWindowOutline(initialFocusedWindow)
    lastKnownFocusedId = initialFocusedWindow:id()
end

-- Start the focus poll timer (defined at module scope to prevent GC)
startFocusPollTimer()

-- Initialize the known window set before first tile
local currentSpace = getCurrentSpace()
for _, win in ipairs(window.visibleWindows()) do
    local okSpaces = spaces.windowSpaces(win)
    local app = safeGetApplication(win)
    local winId = win:id()
    if winId and okSpaces and hs.fnutils.contains(okSpaces, currentSpace) and
       not win:isFullScreen() and isAppIncluded(app, win) then
        lastKnownWindowIds[winId] = true
    end
end

updateWindowOrder()
tileWindows()
bindHotkeys()
updateZoomOverlays()

log("WindowScape initialized" ..
    " [layout:" .. cfg.layoutMode .. "]" ..
    (cfg.enableAnimations and " [animations]" or "") ..
    (cfg.enableTTTaps and " [TTTaps]" or ""))

-- Public helper to restart the gesture recognizer manually
function restartWindowScapeTTTaps()
    if cfg.enableTTTaps then
        stopTTTapsRecognition()
        startTTTapsRecognition()
    end
end

-- Public helper to cycle layout mode
function cycleWindowScapeLayout()
    local modes = { "weighted", "dwindle", "master" }
    local currentIndex = 1
    for i, mode in ipairs(modes) do
        if mode == cfg.layoutMode then
            currentIndex = i
            break
        end
    end
    local nextIndex = (currentIndex % #modes) + 1
    cfg.layoutMode = modes[nextIndex]
    tileWindows()
    return cfg.layoutMode
end

-- FrameMaster Integration
-- Global API for FrameMaster to use WindowScape's custom minimize/fullscreen

-- Toggle simulated fullscreen for the focused window
-- Returns: message string describing what happened
function windowScapeToggleFullscreen()
    local win = window.focusedWindow()
    if not win then return "No window" end

    if simulatedFullscreen.active and simulatedFullscreen.window and
        simulatedFullscreen.window:id() == win:id() then
        exitSimulatedFullscreen()
        return "Exited Fullscreen for " .. (win:title() or "Window")
    else
        enterSimulatedFullscreen(win)
        return "Entered Fullscreen for " .. (win:title() or "Window")
    end
end

-- Check if a window is in simulated fullscreen
function windowScapeIsFullscreen(win)
    if not win then return false end
    return simulatedFullscreen.active and simulatedFullscreen.window and
        simulatedFullscreen.window:id() == win:id()
end

-- Create a snapshot (minimize) for the focused window
-- Returns: message string describing what happened
function windowScapeMinimize()
    local win = window.focusedWindow()
    if not win then return "No window" end

    local title = win:title() or "Window"
    createSnapshot(win)
    return "Minimized " .. title
end

-- Check if a window is minimized via snapshots
function windowScapeIsMinimized(win)
    if not win then return false end
    local winId = win:id()
    return winId and windowSnapshots.windows[winId] ~= nil
end
