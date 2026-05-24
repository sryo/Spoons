-- WindowScape entry point: requires all modules, wires the callback graph,
-- starts watchers, binds hotkeys, and returns the public API.

local window = require("hs.window")

local config         = require("WindowScape.config")
local cfg            = config.cfg
local CONST          = config.CONST

local core           = require("WindowScape.core")
local animation      = require("WindowScape.animation")
local outline        = require("WindowScape.outline")
local snapshots      = require("WindowScape.snapshots")
local snapshotUI     = require("WindowScape.snapshots.ui")
local fullscreen     = require("WindowScape.fullscreen")
local layouts        = require("WindowScape.layouts")
local operations     = require("WindowScape.operations")
local gestures       = require("WindowScape.gestures")
local tiler          = require("WindowScape.tiler")
local snapshotCreate = require("WindowScape.snapshot_create")
local events         = require("WindowScape.events")
local keybinds       = require("WindowScape.keybinds")

-- ---------------------------------------------------------------------------
-- Phase 1: leaf modules (no cross-dependencies)
-- ---------------------------------------------------------------------------

core.init(cfg)
animation.init(cfg)
core.loadList()

-- ---------------------------------------------------------------------------
-- Phase 2: snapshots + fullscreen (own their own state; populate core's pointers)
-- ---------------------------------------------------------------------------

local snapshotCallbacks = {
    safeGetApplication = core.safeGetApplication,
    log = core.log,
    -- tileWindows / updateWindowOrder / updateButtonOverlays wired below
}
snapshots.init(cfg, CONST, snapshotCallbacks)
core.snapshotsState = snapshots.getState()

local fullscreenCallbacks = {
    safeGetApplication = core.safeGetApplication,
    log = core.log,
}
fullscreen.init(cfg, fullscreenCallbacks)
core.fullscreenState = fullscreen.getState()

-- ---------------------------------------------------------------------------
-- Phase 3: outline (needs getOutlineColorForWindow which depends on snapshot state)
-- ---------------------------------------------------------------------------

local function getOutlineColorForWindow(win)
    if not win then return cfg.outlineColor end
    local winId = win:id()
    if not winId then return cfg.outlineColor end

    local app = core.safeGetApplication(win)
    local isExcluded = app and not core.isAppIncluded(app, win)

    if isExcluded then
        return cfg.outlineColorPinned
    elseif core.pseudoWindows[winId] then
        return cfg.outlineColorPseudo
    end
    return cfg.outlineColor
end

outline.init(cfg, CONST, animation, getOutlineColorForWindow, core.log, function(winId)
    return core.snapshotsState.windows[winId] ~= nil
end)

-- ---------------------------------------------------------------------------
-- Phase 4: tiler (depends on layouts, animation, snapshots, fullscreen)
-- ---------------------------------------------------------------------------

tiler.init(cfg, {
    core       = core,
    layouts    = layouts,
    animation  = animation,
    snapshots  = snapshots,
    fullscreen = fullscreen,
})

-- ---------------------------------------------------------------------------
-- Phase 5: snapshot UI tooltip + snapshot creator
-- ---------------------------------------------------------------------------

snapshotUI.init(cfg, {
    safeGetApplication = core.safeGetApplication,
    getSnapshotsState  = function() return core.snapshotsState end,
})

-- Wrap snapshots.restoreFromSnapshot to hide the tooltip when restoring the
-- window the tooltip is currently pointing at.
local function restoreFromSnapshot(winId)
    if snapshotUI.currentWinId == winId then
        snapshotUI.hide()
    end
    snapshots.restoreFromSnapshot(winId)
end

snapshotCreate.init(cfg, CONST, {
    core       = core,
    snapshots  = snapshots,
    snapshotUI = snapshotUI,
    tiler      = tiler,
    animation  = animation,
    fullscreen = fullscreen,
}, {
    focusPreviousWindow         = function(excludeId) return events.focusPreviousWindow(excludeId) end,
    drawOutline                 = outline.draw,
    updateButtonOverlaysWithRetry = fullscreen.updateButtonOverlaysWithRetry,
    restoreFromSnapshot         = restoreFromSnapshot,
})

-- ---------------------------------------------------------------------------
-- Phase 6: operations + gestures (need callbacks into core/tiler/outline)
-- ---------------------------------------------------------------------------

operations.init(cfg, {
    log              = core.log,
    getCurrentSpace  = core.getCurrentSpace,
    getWindowOrder   = function(space) return core.windowOrderBySpace[space] or {} end,
    setWindowOrder   = function(space, order) core.windowOrderBySpace[space] = order end,
    updateWindowOrder = core.updateWindowOrder,
    tileWindows      = tiler.tileWindows,
    drawOutline      = outline.draw,
    hideOutline      = function() outline.stopRefresh(); outline.hide() end,
})

gestures.init(cfg, {
    focusAdjacentWindow        = operations.focusAdjacentWindow,
    moveWindowInOrder          = operations.moveWindowInOrder,
    moveWindowToAdjacentScreen = operations.moveWindowToAdjacentScreen,
})

-- ---------------------------------------------------------------------------
-- Phase 7: Backfill snapshot + fullscreen callback tables now that tiler exists
-- ---------------------------------------------------------------------------

snapshotCallbacks.tileWindows         = tiler.tileWindows
snapshotCallbacks.updateWindowOrder   = core.updateWindowOrder
snapshotCallbacks.updateButtonOverlays = fullscreen.updateButtonOverlaysWithRetry

fullscreenCallbacks.restoreWeights = function(saved)
    for winId, weight in pairs(saved) do
        core.windowWeights[winId] = weight
    end
end
fullscreenCallbacks.getWeights = function()
    local copy = {}
    for k, v in pairs(core.windowWeights) do copy[k] = v end
    return copy
end
fullscreenCallbacks.updateWindowOrder    = core.updateWindowOrder
fullscreenCallbacks.tileWindows          = tiler.tileWindows
fullscreenCallbacks.drawOutline          = outline.draw
fullscreenCallbacks.hideOutline          = function() outline.stopRefresh(); outline.hide() end
fullscreenCallbacks.getCurrentSpace      = core.getCurrentSpace
fullscreenCallbacks.windowSpaces         = function(win) return core.spaces.windowSpaces(win) end
fullscreenCallbacks.isAppIncluded        = core.isAppIncluded
fullscreenCallbacks.isSnapshotsCreating  = function() return core.snapshotsState.isCreating end
fullscreenCallbacks.createSnapshot       = snapshotCreate.createSnapshot
fullscreenCallbacks.isPseudoWindow       = function(winId) return core.pseudoWindows[winId] ~= nil end
fullscreenCallbacks.togglePseudoWindow   = function(winId)
    if core.pseudoWindows[winId] then
        core.pseudoWindows[winId] = nil
    else
        local win = window.get(winId)
        if win then
            local sz = win:size()
            core.pseudoWindows[winId] = { preferredW = sz.w, preferredH = sz.h }
        end
    end
end

-- ---------------------------------------------------------------------------
-- Phase 8: events + keybinds + initial render
-- ---------------------------------------------------------------------------

events.init(cfg, {
    core       = core,
    tiler      = tiler,
    snapshots  = snapshots,
    fullscreen = fullscreen,
    outline    = outline,
    animation  = animation,
    operations = operations,
})

keybinds.init(cfg, {
    core       = core,
    tiler      = tiler,
    fullscreen = fullscreen,
    outline    = outline,
    operations = operations,
    animation  = animation,
    gestures   = gestures,
})

events.start()
keybinds.bind()
tiler.tileWindows()
fullscreen.updateButtonOverlays()

core.log("WindowScape initialized" ..
    " [layout:" .. cfg.layoutMode .. "]" ..
    (cfg.enableAnimations and " [animations]" or "") ..
    (cfg.enableTTTaps and " [TTTaps]" or ""))

-- ---------------------------------------------------------------------------
-- Global helpers (consumed by FrameMaster and the menubar)
-- ---------------------------------------------------------------------------

function restartWindowScapeTTTaps()
    if cfg.enableTTTaps then
        gestures.stop()
        gestures.start()
    end
end

function cycleWindowScapeLayout()
    return keybinds.cycleLayout()
end

function windowScapeToggleFullscreen()
    local win = window.focusedWindow()
    if not win then return "No window" end
    local fsState = core.fullscreenState
    if fsState.active and fsState.window and fsState.window:id() == win:id() then
        fullscreen.exit()
        return "Exited Fullscreen for " .. (win:title() or "Window")
    else
        fullscreen.enter(win)
        return "Entered Fullscreen for " .. (win:title() or "Window")
    end
end

function windowScapeIsFullscreen(win)
    if not win then return false end
    local fsState = core.fullscreenState
    return fsState.active and fsState.window and fsState.window:id() == win:id()
end

function windowScapeMinimize()
    local win = window.focusedWindow()
    if not win then return "No window" end
    local title = win:title() or "Window"
    snapshotCreate.createSnapshot(win)
    return "Minimized " .. title
end

function windowScapeIsMinimized(win)
    if not win then return false end
    local winId = win:id()
    return winId and core.snapshotsState.windows[winId] ~= nil
end

local function cleanup()
    if core.tilingDelayTimer then core.tilingDelayTimer:stop(); core.tilingDelayTimer = nil end
    if core.pendingReposition then core.pendingReposition:stop(); core.pendingReposition = nil end
    if core.snapshotsState and core.snapshotsState.refreshTimer then
        core.snapshotsState.refreshTimer:stop()
    end
    events.stop()
    snapshotUI.cleanup()
    animation.cancelAllAnimations()
    outline.cleanup()
    if cfg.enableTTTaps then gestures.stop() end
    fullscreen.clearZoomOverlays()
    fullscreen.clearMinimizeOverlays()
    fullscreen.clearPinOverlays()
    fullscreen.clearCloseOverlays()
    core.log("WindowScape cleanup complete")
end

return {
    cleanup          = cleanup,
    tileWindows      = tiler.tileWindows,
    toggleFullscreen = windowScapeToggleFullscreen,
    minimize         = windowScapeMinimize,
    isFullscreen     = windowScapeIsFullscreen,
    isMinimized      = windowScapeIsMinimized,
    cycleLayout      = cycleWindowScapeLayout,
    getLayoutMode    = function() return cfg.layoutMode end,
    setLayoutMode    = function(mode)
        if mode == "weighted" or mode == "dwindle" or mode == "master" then
            cfg.layoutMode = mode
            tiler.tileWindows()
            return true
        end
        return false
    end,
    getConfig        = function() return cfg end,
    restartTTTaps    = restartWindowScapeTTTaps,
}
