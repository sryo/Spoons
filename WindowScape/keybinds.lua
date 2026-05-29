-- WindowScape hotkey bindings (extracted from WindowScape.lua:1843-1985).
-- All bindings use cfg.mods (Ctrl+Cmd by default); screen-traversal uses cfg.screenMods.

local hotkey = require("hs.hotkey")
local window = require("hs.window")

local M = {}

local cfg
local core, tiler, fullscreen, outline, operations

local drawActiveWindowOutline

function M.init(config, deps)
    cfg        = config
    core       = deps.core
    tiler      = deps.tiler
    fullscreen = deps.fullscreen
    outline    = deps.outline
    operations = deps.operations

    drawActiveWindowOutline = outline.draw
end

local function toggleFocusedWindowInList(win)
    local focused = win or window.focusedWindow()
    if not focused then return end
    if focused:isFullScreen() then return end

    local app = core.safeGetApplication(focused)
    if not app then return end

    local bundleID = app:bundleID()
    local appName  = app:name()

    if (bundleID and core.listedApps[bundleID]) or (appName and core.listedApps[appName]) then
        if bundleID then core.listedApps[bundleID] = nil end
        if appName then core.listedApps[appName] = nil end
    else
        if bundleID then
            core.listedApps[bundleID] = true
        elseif appName then
            core.listedApps[appName] = true
        end
    end

    core.saveList()
    core.updateWindowOrder()
    tiler.tileWindows()
    drawActiveWindowOutline(focused)
    fullscreen.updateButtonOverlaysWithRetry()
end
M.toggleFocusedWindowInList = toggleFocusedWindowInList

function M.bind()
    hotkey.bind(cfg.mods, ",", toggleFocusedWindowInList)

    hotkey.bind(cfg.mods, "Left",  function() operations.moveWindowInOrder("backward") end)
    hotkey.bind(cfg.mods, "Right", function() operations.moveWindowInOrder("forward")  end)
    hotkey.bind(cfg.screenMods, "Left",  function() operations.moveWindowToAdjacentScreen("previous") end)
    hotkey.bind(cfg.screenMods, "Right", function() operations.moveWindowToAdjacentScreen("next")     end)

    hotkey.bind(cfg.mods, "0", operations.resetAllWeights)

    -- Toggle simulated fullscreen
    hotkey.bind(cfg.mods, "F", function()
        local win = window.focusedWindow()
        local fsState = core.fullscreenState
        if fsState and fsState.active then
            fullscreen.exit()
        elseif win then
            fullscreen.enter(win)
        end
    end)

    hotkey.bind(cfg.mods, "R", function()
        core.log("Force retile triggered")
        operations.forceRetile()
    end)

    hotkey.bind(cfg.mods, "=", operations.grow)
    hotkey.bind(cfg.mods, "-", operations.shrink)
    hotkey.bind(cfg.mods, "W", operations.cycleWidth)

    -- Ctrl+Cmd+P: toggle focused window's app in/out of the exclusion list
    -- (synonym for Ctrl+Cmd+",").
    hotkey.bind(cfg.mods, "P", toggleFocusedWindowInList)

    hotkey.bind(cfg.mods, "D", function()
        cfg.debugLogging = not cfg.debugLogging
        print("[WindowScape] Debug logging: " .. (cfg.debugLogging and "ON" or "OFF"))
    end)
end

return M
