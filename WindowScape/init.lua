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
local fullscreen     = require("WindowScape.fullscreen")
local layouts        = require("WindowScape.layouts")
local operations     = require("WindowScape.operations")
local gestures       = require("WindowScape.gestures")
local tiler          = require("WindowScape.tiler")
local snapshotCreate = require("WindowScape.snapshot_create")
local events         = require("WindowScape.events")
local keybinds       = require("WindowScape.keybinds")

core.init(cfg)
animation.init(cfg, {
    isSetFrameSlow   = core.isSetFrameSlow,
    markSetFrameSlow = core.markSetFrameSlow,
})
core.loadList()

local snapshotCallbacks = {
    safeGetApplication = core.safeGetApplication,
    log = core.log,
}
snapshots.init(cfg, CONST, snapshotCallbacks)
core.snapshotsState = snapshots.getState()

local fullscreenCallbacks = {
    safeGetApplication = core.safeGetApplication,
    log = core.log,
}
fullscreen.init(cfg, fullscreenCallbacks)
core.fullscreenState = fullscreen.getState()

local function getOutlineColorForWindow(win)
    if not win then return cfg.outlineColor end
    local app = core.safeGetApplication(win)
    local isExcluded = app and not core.isAppIncluded(app, win)
    return isExcluded and cfg.outlineColorPinned or cfg.outlineColor
end

outline.init(cfg, CONST, animation, getOutlineColorForWindow, core.log, snapshots.isMinimized, core.isAXSlow)

tiler.init(cfg, {
    core       = core,
    layouts    = layouts,
    animation  = animation,
    snapshots  = snapshots,
    fullscreen = fullscreen,
})

snapshotCreate.init(cfg, CONST, {
    core       = core,
    snapshots  = snapshots,
    tiler      = tiler,
    animation  = animation,
    fullscreen = fullscreen,
}, {
    focusPreviousWindow         = events.focusPreviousWindow,
    drawOutline                 = outline.draw,
    updateButtonOverlaysWithRetry = fullscreen.updateButtonOverlaysWithRetry,
})

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

-- The earlier inits captured these callback tables by reference, so backfilling
-- now reaches the consumer modules. Required because of the dependency cycle
-- between snapshots/fullscreen/tiler/snapshotCreate.
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
fullscreenCallbacks.toggleAppExclusion   = function(winId)
    local win = window.get(winId)
    if not win then return end
    keybinds.toggleFocusedWindowInList(win)
end
fullscreenCallbacks.isAXSlow  = core.isAXSlow
fullscreenCallbacks.measureAX = core.measureAX

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
    gestures   = gestures,
})

events.start()
keybinds.bind()
tiler.tileWindows()
fullscreen.updateButtonOverlays()

core.log("WindowScape initialized" ..
    (cfg.enableAnimations and " [animations]" or "") ..
    (cfg.enableTTTaps and " [TTTaps]" or ""))

-- Globals below are consumed by FrameMaster and the menubar.

function restartWindowScapeTTTaps()
    if cfg.enableTTTaps then
        gestures.stop()
        gestures.start()
    end
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
    return winId and snapshots.isMinimized(winId) or false
end

local function cleanup()
    if core.tilingDelayTimer then core.tilingDelayTimer:stop(); core.tilingDelayTimer = nil end
    if core.pendingReposition then core.pendingReposition:stop(); core.pendingReposition = nil end
    if core.snapshotsState and core.snapshotsState.refreshTimer then
        core.snapshotsState.refreshTimer:stop()
    end
    events.stop()
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
    getConfig        = function() return cfg end,
    restartTTTaps    = restartWindowScapeTTTaps,
}
