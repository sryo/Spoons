-- WindowScape tiler: layout dispatch and per-window weight tracking.

local screen = require("hs.screen")
local window = require("hs.window")
local timer  = require("hs.timer")

local M = {}

local cfg
local core
local layouts
local animation
local snapshots
local fullscreen

-- Cached layout fn (assigned in init)
local tileWeighted

function M.init(config, deps)
    cfg        = config
    core       = deps.core
    layouts    = deps.layouts
    animation  = deps.animation
    snapshots  = deps.snapshots
    fullscreen = deps.fullscreen

    tileWeighted = layouts.tileWeighted

    -- Layouts module needs callbacks back into tiler for weights.
    layouts.init(cfg, {
        getWindowWeight  = M.getWindowWeight,
        animatedSetFrame = animation.animatedSetFrame,
    })
end

function M.getCollapsedWindows(wins)
    local collapsed = {}
    for _, win in ipairs(wins) do
        local s = win:size()
        if s and s.h <= cfg.collapsedWindowHeight then
            table.insert(collapsed, win)
        end
    end
    return collapsed
end

function M.getWindowWeight(win)
    if not win then return 1.0 end
    local winId = win:id()
    if not winId then return 1.0 end
    return core.windowWeights[winId] or 1.0
end

function M.setWindowWeight(win, weight)
    if not win then return end
    local winId = win:id()
    if not winId then return end
    core.windowWeights[winId] = math.max(0.1, weight)
end

-- Drop weight/history/screen entries for windows that no longer exist.
function M.pruneStaleWeights()
    local validIds = {}
    for _, win in ipairs(window.allWindows()) do
        local winId = win:id()
        if winId then validIds[winId] = true end
    end
    for winId in pairs(core.windowWeights) do
        if not validIds[winId] then core.windowWeights[winId] = nil end
    end
    for i = #core.focusHistory, 1, -1 do
        if not validIds[core.focusHistory[i]] then
            table.remove(core.focusHistory, i)
        end
    end
    for winId in pairs(core.windowLastScreen) do
        if not validIds[winId] then core.windowLastScreen[winId] = nil end
    end
end

local function tileWindowsInternal()
    core.updateWindowOrder()
    local allScreens = screen.allScreens()

    for _, scr in ipairs(allScreens) do
        local screenFrame = snapshots.getAdjustedScreenFrame(scr)
        local screenId = scr:id()
        local screenSpace = core.spaces.activeSpaceOnScreen(scr) or core.getCurrentSpace()

        local ordered = core.windowOrderBySpace[screenSpace] or {}
        local screenWindows = {}
        for _, win in ipairs(ordered) do
            if win and not win:isFullScreen() then
                local s = win:screen()
                if s and s:id() == screenId then
                    table.insert(screenWindows, win)
                    local winId = win:id()
                    if winId then
                        core.windowLastScreen[winId] = screenId
                    end
                end
            end
        end

        if #screenWindows == 0 then
            goto continue
        end

        local collapsedWins = M.getCollapsedWindows(screenWindows)
        local nonCollapsedWins = {}
        for _, w in ipairs(screenWindows) do
            local sz = w:size()
            if sz and sz.h > cfg.collapsedWindowHeight then
                table.insert(nonCollapsedWins, w)
            end
        end

        local horizontal = (screenFrame.w > screenFrame.h)
        tileWeighted(screenFrame, nonCollapsedWins, collapsedWins, horizontal)

        ::continue::
    end
end
M.tileWindowsInternal = tileWindowsInternal

function M.tileWindows()
    if core.fullscreenState and core.fullscreenState.active then return end
    if core.snapshotsState and core.snapshotsState.isCreating then return end

    animation.cancelAllAnimations()

    if core.tilingDelayTimer then
        core.tilingDelayTimer:stop()
        core.tilingDelayTimer = nil
    end

    core.tilingCount = 1
    core.tilingStartTime = timer.secondsSinceEpoch()
    local ok, err = pcall(tileWindowsInternal)
    if not ok then
        core.log("Error in tileWindowsInternal: " .. tostring(err))
    end
    local delay = cfg.enableAnimations and (cfg.animationDuration + 0.1) or 0.15
    core.tilingDelayTimer = timer.doAfter(delay, function()
        core.tilingCount = 0
        core.tilingDelayTimer = nil
    end)
end

return M
