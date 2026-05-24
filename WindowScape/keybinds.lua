-- WindowScape hotkey bindings (extracted from WindowScape.lua:1843-1985).
-- All bindings use cfg.mods (Ctrl+Cmd by default); screen-traversal uses cfg.screenMods.

local hotkey = require("hs.hotkey")
local window = require("hs.window")

local M = {}

local cfg
local core, tiler, fullscreen, outline, operations, animation, gestures

local drawActiveWindowOutline

function M.init(config, deps)
    cfg        = config
    core       = deps.core
    tiler      = deps.tiler
    fullscreen = deps.fullscreen
    outline    = deps.outline
    operations = deps.operations
    animation  = deps.animation
    gestures   = deps.gestures

    drawActiveWindowOutline = outline.draw
end

local function toggleFocusedWindowInList()
    local focused = window.focusedWindow()
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

function M.cycleLayout()
    local modes = { "weighted", "dwindle", "master" }
    local currentIndex = 1
    for i, mode in ipairs(modes) do
        if mode == cfg.layoutMode then currentIndex = i; break end
    end
    local nextIndex = (currentIndex % #modes) + 1
    cfg.layoutMode = modes[nextIndex]
    tiler.tileWindows()
    return cfg.layoutMode
end

function M.bind()
    hotkey.bind(cfg.mods, ",", toggleFocusedWindowInList)

    hotkey.bind(cfg.mods, "Left",  function() operations.moveWindowInOrder("backward") end)
    hotkey.bind(cfg.mods, "Right", function() operations.moveWindowInOrder("forward")  end)
    hotkey.bind(cfg.screenMods, "Left",  function() operations.moveWindowToAdjacentScreen("previous") end)
    hotkey.bind(cfg.screenMods, "Right", function() operations.moveWindowToAdjacentScreen("next")     end)

    -- Reset all window weights to equal
    hotkey.bind(cfg.mods, "0", function()
        core.windowWeights = {}
        tiler.tileWindows()
        fullscreen.updateButtonOverlaysWithRetry()
    end)

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

    -- Force retile (reset stuck flags and retile)
    hotkey.bind(cfg.mods, "R", function()
        core.log("Force retile triggered")
        core.tilingCount = 0
        if core.snapshotsState then core.snapshotsState.isCreating = false end
        core.updateWindowOrder()
        tiler.tileWindows()
        fullscreen.updateButtonOverlaysWithRetry()
    end)

    hotkey.bind(cfg.mods, "=", function()
        local win = window.focusedWindow()
        if not win then return end
        tiler.setWindowWeight(win, tiler.getWindowWeight(win) + 0.1)
        tiler.tileWindows()
        fullscreen.updateButtonOverlaysWithRetry()
        core.log("Increased weight to " .. string.format("%.1f", tiler.getWindowWeight(win)))
    end)

    hotkey.bind(cfg.mods, "-", function()
        local win = window.focusedWindow()
        if not win then return end
        tiler.setWindowWeight(win, tiler.getWindowWeight(win) - 0.1)
        tiler.tileWindows()
        fullscreen.updateButtonOverlaysWithRetry()
        core.log("Decreased weight to " .. string.format("%.1f", tiler.getWindowWeight(win)))
    end)

    hotkey.bind(cfg.mods, "]", function()
        cfg.masterRatio = math.min(cfg.masterRatio + 0.05, 0.9)
        tiler.tileWindows()
        fullscreen.updateButtonOverlaysWithRetry()
        core.log("Master ratio: " .. string.format("%.0f%%", cfg.masterRatio * 100))
    end)

    hotkey.bind(cfg.mods, "[", function()
        cfg.masterRatio = math.max(cfg.masterRatio - 0.05, 0.1)
        tiler.tileWindows()
        fullscreen.updateButtonOverlaysWithRetry()
        core.log("Master ratio: " .. string.format("%.0f%%", cfg.masterRatio * 100))
    end)

    hotkey.bind(cfg.mods, "L", function()
        M.cycleLayout()
        fullscreen.updateButtonOverlaysWithRetry()
        core.log("Layout mode: " .. cfg.layoutMode)
    end)

    -- Toggle pseudotiling for focused window
    hotkey.bind(cfg.mods, "P", function()
        local win = window.focusedWindow()
        if not win then return end
        local winId = win:id()
        if not winId then return end

        if core.pseudoWindows[winId] then
            core.pseudoWindows[winId] = nil
            core.log("Disabled pseudotiling for " .. (win:title() or "untitled"))
        else
            local frame = win:frame()
            core.pseudoWindows[winId] = { preferredW = frame.w, preferredH = frame.h }
            core.log("Enabled pseudotiling for " .. (win:title() or "untitled"))
        end
        tiler.tileWindows()
        fullscreen.updateButtonOverlaysWithRetry()
        drawActiveWindowOutline(win)
    end)

    hotkey.bind(cfg.mods, "A", function()
        cfg.enableAnimations = not cfg.enableAnimations
        if not cfg.enableAnimations then
            animation.cancelAllAnimations()
        end
        core.log("Animations: " .. (cfg.enableAnimations and "enabled" or "disabled"))
    end)

    hotkey.bind(cfg.mods, "D", function()
        cfg.debugLogging = not cfg.debugLogging
        print("[WindowScape] Debug logging: " .. (cfg.debugLogging and "ON" or "OFF"))
    end)

    if cfg.enableTTTaps then
        gestures.start()
    end
end

return M
