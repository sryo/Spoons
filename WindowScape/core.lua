-- WindowScape core: state ownership, persistence, and shared utilities.
-- All other modules read mutable state through this module (e.g. core.windowOrderBySpace)
-- so that reassigning a whole table (e.g. core.windowWeights = {}) reaches every reader.

local spacesOk, spaces = pcall(require, "hs.spaces")
if not spacesOk then
    spaces = {
        focusedSpace = function() return 1 end,
        windowSpaces = function(_) return { 1 } end,
        allSpaces = function() return { ["Main"] = { 1 } } end,
        activeSpaceOnScreen = function(_) return 1 end,
        watcher = { new = function(_) return { start = function() end } end },
        activeSpaces = function() return { 1 } end,
        spaceType = function(_) return "user" end,
        spacesForScreen = function(_) return { 1 } end,
        moveWindowToSpace = function(_, _) end,
        gotoSpace = function(_) end,
    }
    package.loaded["hs.spaces"] = spaces
    print("[WindowScape] hs.spaces unavailable (Dock disabled?), using single-space mode")
end

local window = require("hs.window")
local screen = require("hs.screen")
local json   = require("hs.json")
local timer  = require("hs.timer")

local M = {}

M.spaces = spaces

-- Configuration is assigned by init()
M.cfg = nil

-- Persistence
M.listPath = hs.configdir .. "/WindowScape_apps.json"
M.listedApps = {}

-- Window state
M.windowOrderBySpace    = {}
M.windowWeights         = {} -- winId -> weight (default 1.0)
M.windowLastScreen      = {} -- winId -> screenId
M.focusHistory          = {} -- array of winIds, most recent first
M.focusHistoryMax       = 10
M.lastKnownWindowIds    = {}
M.lastKnownWindowFrames = {}

-- Tile-loop tracking (read by events.lua, written by tiler.lua)
M.tilingCount      = 0
M.tilingStartTime  = 0
M.pendingReposition = nil -- timer
M.tilingDelayTimer  = nil -- timer

-- Cross-module state pointers (populated after dependent modules init)
M.snapshotsState  = nil
M.fullscreenState = nil

-- Per-bundleID cache of apps whose AX queries have measured slow once. Catalyst
-- apps (e.g. WhatsApp) live here. Modules that hammer AX should consult this
-- and skip non-essential queries for slow apps. Resets on Hammerspoon reload.
M.slowAXApps         = {}
M.slowSetFrameApps   = {}
M.measuredApps       = {} -- bundleID -> true, so we only log the AX timing once per app

local SLOW_AX_THRESHOLD_MS       = 50
local SLOW_SETFRAME_THRESHOLD_MS = 50

function M.isAXSlow(app)
    if not app then return false end
    local bundleID = app:bundleID()
    return bundleID and M.slowAXApps[bundleID] or false
end

-- Wraps `fn`, times it. First time we ever measure a given bundleID we log the
-- timing (slow OR fast) so the user can see what's being detected. If the call
-- exceeds the threshold the app is cached as slow and subsequent measureAX
-- calls short-circuit, returning fn() directly without timing or logging.
function M.measureAX(app, fn)
    local bundleID = app and app:bundleID()
    if bundleID and M.slowAXApps[bundleID] then return fn() end

    local t0 = timer.secondsSinceEpoch()
    local results = { fn() } -- table-pack to preserve any number of returns
    local elapsedMs = (timer.secondsSinceEpoch() - t0) * 1000

    if bundleID and not M.measuredApps[bundleID] then
        M.measuredApps[bundleID] = true
        if elapsedMs > SLOW_AX_THRESHOLD_MS then
            M.slowAXApps[bundleID] = true
            M.warn(string.format("AX SLOW: %s took %.0fms, skipping overlays for this app", bundleID, elapsedMs))
        else
            M.log(string.format("AX ok:   %s took %.0fms", bundleID, elapsedMs))
        end
    elseif bundleID and elapsedMs > SLOW_AX_THRESHOLD_MS then
        -- Already-measured app suddenly spiked, mark it.
        M.slowAXApps[bundleID] = true
        M.warn(string.format("AX SLOW: %s spiked to %.0fms, skipping overlays for this app", bundleID, elapsedMs))
    end
    return table.unpack(results)
end

function M.isSetFrameSlow(app)
    if not app then return false end
    local bundleID = app:bundleID()
    return bundleID and M.slowSetFrameApps[bundleID] or false
end

function M.markSetFrameSlow(app, elapsedMs)
    local bundleID = app and app:bundleID()
    if not bundleID or M.slowSetFrameApps[bundleID] then return end
    if elapsedMs > SLOW_SETFRAME_THRESHOLD_MS then
        M.slowSetFrameApps[bundleID] = true
        M.warn(string.format("setFrame SLOW: %s took %.0fms, skipping animation for this app", bundleID, elapsedMs))
    end
end

-- Two-tier logging:
--   M.log : verbose per-event diagnostic, gated by cfg.debugLogging (default off)
--   M.warn: errors, perf warnings, rare-but-meaningful events (always prints)
function M.log(message)
    if M.cfg and M.cfg.debugLogging then
        print(os.date("%Y-%m-%d %H:%M:%S") .. " [WindowScape] " .. message)
    end
end

function M.warn(message)
    print(os.date("%Y-%m-%d %H:%M:%S") .. " [WindowScape] " .. message)
end

-- Safe wrapper for win:application() — avoids "Unable to fetch NSRunningApplication"
-- when the window's process has terminated but the window userdata still exists.
function M.safeGetApplication(win)
    if not win then return nil end
    local ok, app = pcall(function() return win:application() end)
    if ok and app then return app end
    return nil
end

function M.getCurrentSpace()
    return spaces.focusedSpace()
end

function M.pruneStaleSpaces()
    local allSpaces = spaces.allSpaces()
    if not allSpaces then return end

    local valid = {}
    for _, screenSpaces in pairs(allSpaces) do
        for _, spaceId in ipairs(screenSpaces) do
            valid[spaceId] = true
        end
    end

    for spaceId in pairs(M.windowOrderBySpace) do
        if not valid[spaceId] then
            M.windowOrderBySpace[spaceId] = nil
            M.warn("Pruned stale space: " .. tostring(spaceId))
        end
    end
end

-- Atomic write: write to .tmp then rename, so a failed write doesn't lose the list.
function M.saveList()
    local tmpPath = M.listPath .. ".tmp"
    local ok, err = json.write(M.listedApps, tmpPath, true, true)
    if not ok then
        M.warn("Failed to write temp app list: " .. tostring(err))
        return
    end
    local renamed, renameErr = os.rename(tmpPath, M.listPath)
    if not renamed then
        M.warn("Failed to rename temp app list: " .. tostring(renameErr))
        os.remove(tmpPath)
    end
end

function M.loadList()
    M.listedApps = json.read(M.listPath) or {}
    if next(M.listedApps) == nil then
        M.listedApps["org.hammerspoon.Hammerspoon"] = true
        M.saveList()
    end
end

function M.isAppIncluded(app, win)
    if not (app and win) then return false end
    if not win:isStandard() then return false end

    local winId = win:id()
    if winId and M.snapshotsState and M.snapshotsState.windows[winId] then
        return false
    end

    local bundleID = app:bundleID()
    local appName  = app:name()
    local listed   = (bundleID and M.listedApps[bundleID]) or (appName and M.listedApps[appName])

    if M.cfg.exclusionMode then
        return not listed
    else
        return listed == true
    end
end

function M.isSystem(win)
    return win and (win:role() == "AXScrollArea" or win:subrole() == "AXSystemDialog")
end

-- Rebuild windowOrderBySpace for each screen's active space, preserving prior ordering.
function M.updateWindowOrder()
    local allScreens = screen.allScreens()
    local allWindows = window.visibleWindows()

    for _, scr in ipairs(allScreens) do
        local screenId = scr:id()
        local screenSpace = spaces.activeSpaceOnScreen(scr) or M.getCurrentSpace()

        local screenWindows = {}
        local screenWindowSet = {}

        for _, win in ipairs(allWindows) do
            local okSpaces = spaces.windowSpaces(win)
            local app = M.safeGetApplication(win)
            local winScreen = win:screen()
            local winId = win:id()
            if winId and okSpaces and winScreen and winScreen:id() == screenId and
               not win:isFullScreen() and M.isAppIncluded(app, win) then
                if hs.fnutils.contains(okSpaces, screenSpace) then
                    table.insert(screenWindows, win)
                    screenWindowSet[winId] = win
                end
            end
        end

        local prevOrder = M.windowOrderBySpace[screenSpace] or {}
        local newOrder = {}
        local newOrderSet = {}

        for _, win in ipairs(prevOrder) do
            local winId = win:id()
            if winId and screenWindowSet[winId] then
                table.insert(newOrder, win)
                newOrderSet[winId] = true
            end
        end

        for _, win in ipairs(screenWindows) do
            local winId = win:id()
            if winId and not newOrderSet[winId] then
                table.insert(newOrder, win)
                newOrderSet[winId] = true
            end
        end

        M.windowOrderBySpace[screenSpace] = newOrder
    end
end

function M.init(cfg)
    M.cfg = cfg
end

return M
