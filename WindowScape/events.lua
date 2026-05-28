-- WindowScape event plumbing: window-filter subscriptions, focus polling,
-- spaces/screen watchers, right-click eventtap, watchdog timer.
-- All long-lived hs handles (watchers, taps, timers) are stored on module-level
-- locals so they survive GC.

local window   = require("hs.window")
local screen   = require("hs.screen")
local eventtap = require("hs.eventtap")
local mouse    = require("hs.mouse")
local timer    = require("hs.timer")
local fnutils  = require("hs.fnutils")

local M = {}

local cfg
local core, tiler, snapshots, fullscreen, outline, animation, operations

-- Long-lived handles — keep references so Hammerspoon doesn't GC them.
local spacesWatcher
local screenWatcher
local rightClickTap
local watchdogTimer
local focusPollTimer
local focusDebounceTimer
local pendingWindowEvent
local eventDebounce
local screenChangeDebounce

local lastKnownFocusedId
local drawActiveWindowOutline

function M.init(config, deps)
    cfg            = config
    core           = deps.core
    tiler          = deps.tiler
    snapshots      = deps.snapshots
    fullscreen     = deps.fullscreen
    outline        = deps.outline
    animation      = deps.animation
    operations     = deps.operations

    drawActiveWindowOutline = outline.draw
end

-- Filter `order` to windows currently on `screenId`. When includeCollapsed is
-- false, also skips windows whose size is at-or-below the collapsed threshold.
local function getScreenWindows(order, screenId, includeCollapsed)
    local out = {}
    for _, w in ipairs(order) do
        if w and not w:isFullScreen() then
            local s = w:screen()
            if s and s:id() == screenId then
                if includeCollapsed then
                    table.insert(out, w)
                else
                    local wsz = w:size()
                    if wsz and wsz.h > cfg.collapsedWindowHeight then
                        table.insert(out, w)
                    end
                end
            end
        end
    end
    return out
end

-- True if the new windows look like Chrome/Terminal tab-switches: same app,
-- nearly identical frame (within 50px summed) as one of the removed windows.
local function isTabSwitch(newWindows, removedWindows, currentWindowData)
    if #newWindows == 0 or #removedWindows == 0 then return false end
    for _, newId in ipairs(newWindows) do
        local newData = currentWindowData[newId]
        if newData and newData.frame then
            for _, oldId in ipairs(removedWindows) do
                local oldData = core.lastKnownWindowFrames[oldId]
                if oldData and oldData.app == newData.app and oldData.frame then
                    local frameDiff = math.abs(newData.frame.x - oldData.frame.x) +
                                      math.abs(newData.frame.y - oldData.frame.y) +
                                      math.abs(newData.frame.w - oldData.frame.w) +
                                      math.abs(newData.frame.h - oldData.frame.h)
                    if frameDiff < 50 then return true end
                end
            end
        end
    end
    return false
end

-- Focus the previously focused window, skipping minimized / hidden ones.
function M.focusPreviousWindow(excludeWinId)
    for _, winId in ipairs(core.focusHistory) do
        if winId ~= excludeWinId then
            local win = window.get(winId)
            if win and win:isVisible() and not snapshots.isMinimized(winId) then
                win:focus()
                return true
            end
        end
    end
    return false
end

local function checkFullscreenFocus()
    local fsState = core.fullscreenState
    if not fsState or not fsState.active then return end

    local focused = window.focusedWindow()
    if not focused then
        fullscreen.exit()
        return
    end

    if fsState.window and focused:id() ~= fsState.window:id() then
        fullscreen.exit()
    end
end

local function focusPollCallback()
    local win = window.focusedWindow()
    if not win then return end
    local winId = win:id()
    if winId and winId ~= lastKnownFocusedId then
        lastKnownFocusedId = winId
        if win:isVisible() and not win:isFullScreen() and not core.isSystem(win) then
            drawActiveWindowOutline(win)
        end
    end
end

local function startFocusPollTimer()
    if focusPollTimer then focusPollTimer:stop() end
    focusPollTimer = timer.doEvery(0.1, focusPollCallback)
    -- Globals defeat Hammerspoon's eager GC of timer closures.
    _G.WindowScapeFocusPollTimer = focusPollTimer
    _G.WindowScapeFocusPollCallback = focusPollCallback
end
M.startFocusPollTimer = startFocusPollTimer

local function handleWindowFocused(win)
    checkFullscreenFocus()

    if core.fullscreenState and core.fullscreenState.active then return end
    if core.snapshotsState and core.snapshotsState.isCreating then return end

    if focusDebounceTimer then focusDebounceTimer:stop() end

    focusDebounceTimer = timer.doAfter(0.05, function()
        focusDebounceTimer = nil
        local actualWin = window.focusedWindow()
        if not actualWin then return end
        lastKnownFocusedId = actualWin:id()

        if actualWin:isVisible() and not actualWin:isFullScreen() and not core.isSystem(actualWin) then
            local winId = actualWin:id()
            if winId then
                for i = #core.focusHistory, 1, -1 do
                    if core.focusHistory[i] == winId then
                        table.remove(core.focusHistory, i)
                    end
                end
                table.insert(core.focusHistory, 1, winId)
                while #core.focusHistory > core.focusHistoryMax do
                    table.remove(core.focusHistory)
                end
            end

            drawActiveWindowOutline(actualWin)
            fullscreen.updateButtonOverlaysWithRetry()
        else
            outline.hide()
        end
    end)
end
M.handleWindowFocused = handleWindowFocused

local function handleWindowEvent()
    if core.fullscreenState and core.fullscreenState.active then return end
    if core.snapshotsState and core.snapshotsState.isCreating then return end
    if core.tilingCount > 0 then
        if pendingWindowEvent then pendingWindowEvent:stop() end
        local retryDelay = cfg.enableAnimations and (cfg.animationDuration + 0.15) or 0.2
        pendingWindowEvent = timer.doAfter(retryDelay, function()
            pendingWindowEvent = nil
            handleWindowEvent()
        end)
        return
    end

    local currentWindowIds = {}
    local currentWindowData = {}

    for _, scr in ipairs(screen.allScreens()) do
        local screenSpace = core.spaces.activeSpaceOnScreen(scr) or core.getCurrentSpace()
        for _, win in ipairs(window.visibleWindows()) do
            local okSpaces = core.spaces.windowSpaces(win)
            local app = core.safeGetApplication(win)
            local winId = win:id()
            if winId and okSpaces and fnutils.contains(okSpaces, screenSpace) and
               not win:isFullScreen() and core.isAppIncluded(app, win) then
                currentWindowIds[winId] = true
                local frame = win:frame()
                local appId = app and (app:bundleID() or app:name()) or "unknown"
                currentWindowData[winId] = { app = appId, frame = frame }
            end
        end
    end

    local newWindows = {}
    local removedWindows = {}

    for winId in pairs(currentWindowIds) do
        if not core.lastKnownWindowIds[winId] then
            table.insert(newWindows, winId)
        end
    end

    for winId in pairs(core.lastKnownWindowIds) do
        if not currentWindowIds[winId] then
            table.insert(removedWindows, winId)
        end
    end

    local tabSwitch = isTabSwitch(newWindows, removedWindows, currentWindowData)

    core.lastKnownWindowIds = currentWindowIds
    core.lastKnownWindowFrames = currentWindowData

    if tabSwitch then return end
    if #newWindows == 0 and #removedWindows == 0 then return end

    local focusedWindow = window.focusedWindow()
    core.updateWindowOrder()
    tiler.tileWindows()
    if focusedWindow and focusedWindow:isVisible() then
        local currentFocus = window.focusedWindow()
        if currentFocus and currentFocus:id() ~= focusedWindow:id() then
            focusedWindow:focus()
        end
        drawActiveWindowOutline(focusedWindow)
    elseif window.focusedWindow() then
        drawActiveWindowOutline(window.focusedWindow())
    end

    fullscreen.updateButtonOverlaysWithRetry()
end
M.handleWindowEvent = handleWindowEvent

local function handleWindowMoved(win)
    if not win then return end
    local winId = win:id()

    if core.fullscreenState and core.fullscreenState.active then return end
    if core.snapshotsState and core.snapshotsState.isCreating then return end

    -- Newly created windows are handled by handleWindowEvent; skip here to avoid double-tiling.
    if winId and not core.lastKnownWindowIds[winId] then return end

    local focusedWin = window.focusedWindow()
    if focusedWin and focusedWin:id() == winId then
        drawActiveWindowOutline(focusedWin)
    end

    local winScreen = win:screen()
    if not winScreen then return end
    local screenId = winScreen:id()
    -- windowLastScreen is owned by tileWindowsInternal (the only place that
    -- knows a window was *placed* on a screen). Reading here gives us the
    -- last *tiled* screen, which stays stable across every windowMoved event
    -- in the same drag — so `screenChanged` stays true until the user drops.
    local previousScreenId = core.windowLastScreen[winId]

    local screenChanged = previousScreenId and previousScreenId ~= screenId
    local windowNeedsRetile = not previousScreenId and core.lastKnownWindowIds[winId]

    if screenChanged then
        if core.pendingReposition then core.pendingReposition:stop(); core.pendingReposition = nil end
        if core.tilingDelayTimer then core.tilingDelayTimer:stop(); core.tilingDelayTimer = nil end
        core.tilingCount = 0

        -- Defer until the user drops: each windowMoved during the cross-screen
        -- drag resets this timer, so the final firing observes the actual drop
        -- frame and inserts the window at the computed position on screen B.
        core.pendingReposition = timer.doAfter(0.3, function()
            core.pendingReposition = nil

            local curScreen = win:screen()
            if not curScreen then
                tiler.tileWindows()
                return
            end
            local destScrId = curScreen:id()
            local curScrFrame = curScreen:frame()
            local destSpace = core.spaces.activeSpaceOnScreen(curScreen) or core.getCurrentSpace()
            local dropFrame = win:frame()

            core.updateWindowOrder()

            local order = core.windowOrderBySpace[destSpace] or {}
            local othersOnDest = {}
            local movedInOrder = false
            for _, w in ipairs(order) do
                if w:id() == winId then
                    movedInOrder = true
                else
                    local s = w:screen()
                    if s and s:id() == destScrId then
                        local sz = w:size()
                        if sz and sz.h > cfg.collapsedWindowHeight then
                            table.insert(othersOnDest, w)
                        end
                    end
                end
            end

            if movedInOrder and #othersOnDest > 0 and dropFrame then
                local insertIndex = operations.calculateDropPosition(dropFrame, othersOnDest, curScrFrame)
                insertIndex = math.max(1, math.min(insertIndex, #othersOnDest + 1))

                -- Rebuild order: keep non-dest-screen / collapsed entries in place,
                -- splice moved window into the dest-screen non-collapsed sequence.
                local newOrder = {}
                local destSeen = 0
                local placed = false
                for _, w in ipairs(order) do
                    if w:id() == winId then
                        -- skip; reinserted at insertIndex below
                    else
                        local s = w:screen()
                        local onDest = s and s:id() == destScrId
                        local sz = w:size()
                        local isNonCollapsed = sz and sz.h > cfg.collapsedWindowHeight
                        if onDest and isNonCollapsed and not placed then
                            destSeen = destSeen + 1
                            if destSeen == insertIndex then
                                table.insert(newOrder, win)
                                placed = true
                            end
                        end
                        table.insert(newOrder, w)
                    end
                end
                if not placed then table.insert(newOrder, win) end
                core.windowOrderBySpace[destSpace] = newOrder
            end

            tiler.tileWindows()
        end)
        return
    end

    if windowNeedsRetile then
        if core.pendingReposition then core.pendingReposition:stop(); core.pendingReposition = nil end
        if core.tilingDelayTimer then core.tilingDelayTimer:stop(); core.tilingDelayTimer = nil end
        core.tilingCount = 0
        timer.doAfter(0.02, function()
            core.updateWindowOrder()
            tiler.tileWindows()
        end)
        timer.doAfter(0.15, function()
            core.updateWindowOrder()
            tiler.tileWindows()
        end)
        return
    end

    if core.tilingCount > 0 then return end
    if winId and animation.isAnimating(winId) then return end

    local app = core.safeGetApplication(win)
    if not core.isAppIncluded(app, win) then return end
    if win:isFullScreen() then return end

    local sz = win:size()
    local isCollapsed = sz and sz.h <= cfg.collapsedWindowHeight

    if isCollapsed then
        tiler.tileWindows()
        return
    end

    local capturedFrame = win:frame()
    if not capturedFrame then return end

    local winSpaces = core.spaces.windowSpaces(win)
    local winSpace = winSpaces and winSpaces[1] or core.getCurrentSpace()
    local screenFrame = snapshots.getAdjustedScreenFrame(winScreen)
    local horizontal = (screenFrame.w > screenFrame.h)

    local currentOrder = core.windowOrderBySpace[winSpace] or {}
    local screenWindows = getScreenWindows(currentOrder, screenId, false)

    if #screenWindows == 0 then
        tiler.tileWindows()
        return
    end

    local winInOrder = false
    for _, w in ipairs(screenWindows) do
        if w:id() == winId then winInOrder = true; break end
    end

    if not winInOrder then
        core.updateWindowOrder()
        tiler.tileWindows()
        return
    end

    local allScreenWindows = getScreenWindows(currentOrder, screenId, true)
    local collapsedWins = tiler.getCollapsedWindows(allScreenWindows)
    local numCollapsed = #collapsedWins

    local totalWeight = 0
    for _, w in ipairs(screenWindows) do
        totalWeight = totalWeight + tiler.getWindowWeight(w)
    end

    if totalWeight <= 0 then
        tiler.tileWindows()
        return
    end

    local totalGaps = math.max(#screenWindows - 1, 0) * cfg.tileGap

    -- Match tileWeighted formula: (h + g) * n - g  (no trailing gap).
    local collapsedAreaSize = 0
    if numCollapsed > 0 then
        if horizontal then
            collapsedAreaSize = 0
        else
            collapsedAreaSize = (cfg.collapsedWindowHeight + cfg.tileGap) * numCollapsed - cfg.tileGap
        end
    end

    local availableSpace = horizontal
        and (screenFrame.w - totalGaps)
        or (screenFrame.h - totalGaps - collapsedAreaSize)

    if availableSpace <= 0 then
        tiler.tileWindows()
        return
    end

    local expectedSize = availableSpace * tiler.getWindowWeight(win) / totalWeight
    local actualSize = horizontal and capturedFrame.w or capturedFrame.h

    local sizeDiff = math.abs(actualSize - expectedSize)
    local wasResized = sizeDiff > 20

    if wasResized then
        if #screenWindows < 2 then
            tiler.tileWindows()
            return
        end

        local winIndex = nil
        for i, w in ipairs(screenWindows) do
            if w:id() == win:id() then winIndex = i; break end
        end
        if not winIndex then
            tiler.tileWindows()
            return
        end

        local expectedPos = horizontal and screenFrame.x or screenFrame.y
        for i = 1, winIndex - 1 do
            local w = screenWindows[i]
            local wWeight = tiler.getWindowWeight(w)
            local wSize = math.floor(availableSpace * wWeight / totalWeight)
            expectedPos = expectedPos + wSize + cfg.tileGap
        end

        local actualPos = horizontal and capturedFrame.x or capturedFrame.y
        local positionMoved = math.abs(actualPos - expectedPos) > 10

        local adjacentWin = nil
        if positionMoved then
            if winIndex > 1 then adjacentWin = screenWindows[winIndex - 1] end
        else
            if winIndex < #screenWindows then adjacentWin = screenWindows[winIndex + 1] end
        end

        if adjacentWin then
            local oldWeight = tiler.getWindowWeight(win)
            local adjOldWeight = tiler.getWindowWeight(adjacentWin)
            local combinedWeight = oldWeight + adjOldWeight

            local newWeight = (actualSize / availableSpace) * totalWeight
            newWeight = math.max(0.2, math.min(newWeight, combinedWeight - 0.2))

            local adjNewWeight = combinedWeight - newWeight
            adjNewWeight = math.max(0.2, adjNewWeight)

            tiler.setWindowWeight(win, newWeight)
            tiler.setWindowWeight(adjacentWin, adjNewWeight)
        end

        if core.pendingReposition then
            core.pendingReposition:stop()
            core.pendingReposition = nil
        end

        tiler.tileWindows()
        return
    end

    -- Move-not-resize: debounce and reorder by drop position.
    if core.pendingReposition then core.pendingReposition:stop() end

    core.pendingReposition = timer.doAfter(0.3, function()
        core.pendingReposition = nil

        local wSpaces = core.spaces.windowSpaces(win)
        local space = wSpaces and wSpaces[1] or core.getCurrentSpace()
        local order = core.windowOrderBySpace[space] or {}
        local scrn = win:screen()
        if not scrn then
            tiler.tileWindows()
            return
        end

        local scrFrame = scrn:frame()
        local scrId = scrn:id()

        local scrnWindows = getScreenWindows(order, scrId, false)

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
            tiler.tileWindows()
            return
        end

        local currentIndex = 0
        for i, w in ipairs(scrnWindows) do
            if w:id() == win:id() then currentIndex = i; break end
        end

        local newIndex = operations.calculateDropPosition(win:frame(), otherWindows, scrFrame)
        newIndex = math.max(1, math.min(newIndex, #otherWindows + 1))

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

            core.windowOrderBySpace[space] = newOrder
        end

        tiler.tileWindows()
    end)
end
M.handleWindowMoved = handleWindowMoved

local function handleWindowDestroyed(_win)
    tiler.pruneStaleWeights()
    core.updateWindowOrder()
    tiler.tileWindows()
    -- Don't fan out to handleWindowFocused; the windowFocused subscription
    -- will fire naturally and double-handling causes focus flicker.
    if not window.focusedWindow() then
        outline.hide()
    end
end

local function debouncedHandleWindowEvent(_win, _appName, _eventName)
    if eventDebounce then eventDebounce:stop() end
    eventDebounce = timer.doAfter(cfg.eventDebounceSeconds, function()
        handleWindowEvent()
        eventDebounce = nil
    end)
end

local function setupWindowFilterSubscriptions()
    local ok, err = pcall(function()
        window.filter.default:subscribe({
            window.filter.windowCreated,
            window.filter.windowHidden,
            window.filter.windowUnhidden,
            window.filter.windowMinimized,
            window.filter.windowUnminimized,
        }, debouncedHandleWindowEvent)

        window.filter.default:subscribe(window.filter.windowMoved, handleWindowMoved)
        window.filter.default:subscribe(window.filter.windowDestroyed, handleWindowDestroyed)
        window.filter.default:subscribe(window.filter.windowFocused, handleWindowFocused)

        -- Catch true minimizations: snapshots use off-screen storage, not native minimize.
        window.filter.default:subscribe(window.filter.windowMinimized, function(win)
            if not win then return end
            local winId = win:id()
            if not winId then return end

            if not snapshots.isMinimized(winId) then
                core.warn("Recovering accidentally minimized window: " .. (win:title() or "untitled"))
                timer.doAfter(0.1, function()
                    if win and win:isMinimized() then
                        win:unminimize()
                        win:focus()
                        timer.doAfter(0.2, function()
                            core.updateWindowOrder()
                            tiler.tileWindows()
                            fullscreen.updateButtonOverlaysWithRetry()
                        end)
                    end
                end)
            end
        end)
    end)

    if not ok then
        print("[WindowScape] Window filter subscription failed, retrying in 1s: " .. tostring(err))
        timer.doAfter(1, setupWindowFilterSubscriptions)
        return false
    end
    return true
end

local function preventGC()
    core.pruneStaleSpaces()
    tiler.pruneStaleWeights()

    local now = timer.secondsSinceEpoch()
    local stuckThreshold = 5

    if core.tilingCount > 0 and (now - core.tilingStartTime) > stuckThreshold then
        core.warn("Watchdog: tilingCount stuck at " .. core.tilingCount ..
                  " for " .. math.floor(now - core.tilingStartTime) .. "s, resetting")
        core.tilingCount = 0
    end

    local snapshotsState = core.snapshotsState
    if snapshotsState and snapshotsState.isCreating and
       (now - snapshotsState.isCreatingStart) > stuckThreshold then
        core.warn("Watchdog: isCreating stuck for " ..
                  math.floor(now - snapshotsState.isCreatingStart) .. "s, resetting")
        snapshotsState.isCreating = false
    end

    if focusPollTimer and not focusPollTimer:running() then
        core.warn("Focus poll timer stopped, restarting...")
        startFocusPollTimer()
    end
end

function M.start()
    setupWindowFilterSubscriptions()

    spacesWatcher = core.spaces.watcher.new(function(_)
        outline.hide()
        outline.stopRefresh()
        handleWindowEvent()
    end)
    spacesWatcher:start()

    -- macOS posts the screen-config notification before NSScreen metrics are
    -- fully settled, so reading scr:frame() inside the watcher callback can
    -- return stale (pre-change) values. Debounce, then re-read.
    screenWatcher = screen.watcher.new(function()
        if screenChangeDebounce then screenChangeDebounce:stop() end
        screenChangeDebounce = timer.doAfter(0.25, function()
            screenChangeDebounce = nil
            core.warn("Screen configuration changed, repositioning")

            if core.tilingDelayTimer then core.tilingDelayTimer:stop(); core.tilingDelayTimer = nil end
            if core.pendingReposition then core.pendingReposition:stop(); core.pendingReposition = nil end
            core.tilingCount = 0

            fullscreen.reframeToCurrentScreen()
            snapshots.updateLayout()
            if not (core.fullscreenState and core.fullscreenState.active) then
                tiler.tileWindows()
            end
            fullscreen.updateButtonOverlaysWithRetry()
        end)
    end)
    screenWatcher:start()

    rightClickTap = eventtap.new({ eventtap.event.types.rightMouseDown }, function(_)
        local pos = mouse.absolutePosition()
        for winId, data in pairs(core.snapshotsState.windows) do
            if data.canvas then
                local frame = data.canvas:frame()
                if pos.x >= frame.x and pos.x <= frame.x + frame.w and
                   pos.y >= frame.y and pos.y <= frame.y + frame.h then
                    snapshots.showContextMenu(winId, data)
                    return true
                end
            end
        end
        return false
    end)
    rightClickTap:start()

    watchdogTimer = timer.doEvery(10, preventGC)

    -- Periodic overlay refresh — keeps zoom/min/pin/close buttons aligned with the
    -- active window when sidebar autohide or other slow layout changes occur.
    core.fullscreenState.overlayRefreshTimer = timer.doEvery(2, function()
        if not core.fullscreenState.active and
           (not core.snapshotsState or not core.snapshotsState.isCreating) then
            fullscreen.updateButtonOverlaysIfFocusChanged()
        end
    end)

    -- Seed lastKnownWindowIds with whatever's visible right now, so the first
    -- handleWindowEvent doesn't treat every existing window as new.
    local initialFocused = window.focusedWindow()
    if initialFocused then
        drawActiveWindowOutline(initialFocused)
        lastKnownFocusedId = initialFocused:id()
    end

    startFocusPollTimer()

    for _, scr in ipairs(screen.allScreens()) do
        local screenSpace = core.spaces.activeSpaceOnScreen(scr) or core.getCurrentSpace()
        for _, win in ipairs(window.visibleWindows()) do
            local okSpaces = core.spaces.windowSpaces(win)
            local app = core.safeGetApplication(win)
            local winId = win:id()
            if winId and okSpaces and fnutils.contains(okSpaces, screenSpace) and
               not win:isFullScreen() and core.isAppIncluded(app, win) then
                core.lastKnownWindowIds[winId] = true
            end
        end
    end
end

-- Stop everything we own; used by the WindowScape.cleanup() API.
function M.stop()
    if eventDebounce then eventDebounce:stop(); eventDebounce = nil end
    if focusDebounceTimer then focusDebounceTimer:stop(); focusDebounceTimer = nil end
    if pendingWindowEvent then pendingWindowEvent:stop(); pendingWindowEvent = nil end
    if focusPollTimer then focusPollTimer:stop(); focusPollTimer = nil end
    if watchdogTimer then watchdogTimer:stop(); watchdogTimer = nil end
    if rightClickTap then rightClickTap:stop(); rightClickTap = nil end
    if screenChangeDebounce then screenChangeDebounce:stop(); screenChangeDebounce = nil end
    -- spaces.watcher and screen.watcher don't expose stop() in all Hammerspoon versions;
    -- dropping the reference is sufficient since the Lua state is rebuilt on reload.
    spacesWatcher = nil
    screenWatcher = nil
end

return M
