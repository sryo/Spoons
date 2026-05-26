-- Simulated fullscreen: hides other windows on the space, maximizes one window,
-- and overlays a small set of button affordances (delegated to fullscreen_ui).
-- The UI module owns all overlay canvases; this file owns only the
-- enter/exit lifecycle and the savedWeights/hiddenWindows state.

local geometry = require("hs.geometry")
local timer    = require("hs.timer")
local window   = require("hs.window")
local fnutils  = require("hs.fnutils")

local ui = require("WindowScape.fullscreen_ui")

local M = {}

local cfg, callbacks

local state = {
    active = false,
    window = nil,
    hiddenWindows = {},
    savedWeights = {},
    overlayRefreshTimer = nil,
}

local function log(msg)
    if callbacks.log then callbacks.log(msg) end
end

function M.exit()
    if not state.active then return end
    log("Exiting simulated fullscreen")

    state.active = false

    callbacks.restoreWeights(state.savedWeights)
    state.savedWeights = {}

    for _, data in ipairs(state.hiddenWindows) do
        if data.win and callbacks.safeGetApplication(data.win) and data.frame then
            data.win:setFrame(geometry.rect(data.frame), 0)
        end
    end
    state.hiddenWindows = {}
    state.window = nil

    ui.clearAllOverlays()

    callbacks.updateWindowOrder()
    callbacks.tileWindows()
    local focused = window.focusedWindow()
    if focused then callbacks.drawOutline(focused) end
    ui.updateButtonOverlays()
end

function M.enter(win)
    if not win then return end
    if state.active then
        M.exit()
        return
    end

    log("Entering simulated fullscreen for: " .. (win:title() or "untitled"))

    local winScreen = win:screen()
    if not winScreen then return end
    local screenFrame = winScreen:frame()

    state.savedWeights = callbacks.getWeights()

    state.active = true
    state.window = win
    state.hiddenWindows = {}

    callbacks.hideOutline()

    ui.clearAllOverlays()

    local currentSpace = callbacks.getCurrentSpace and callbacks.getCurrentSpace() or 1
    for _, otherWin in ipairs(window.visibleWindows()) do
        if otherWin:id() ~= win:id() then
            local okSpaces = callbacks.windowSpaces and callbacks.windowSpaces(otherWin)
            if okSpaces and fnutils.contains(okSpaces, currentSpace) then
                local app = callbacks.safeGetApplication(otherWin)
                if app and callbacks.isAppIncluded(app, otherWin) then
                    local originalFrame = otherWin:frame()
                    table.insert(state.hiddenWindows, { win = otherWin, frame = originalFrame })
                    otherWin:setFrame(
                        geometry.rect({
                            x = screenFrame.x + screenFrame.w + 100,
                            y = screenFrame.y + screenFrame.h + 100,
                            w = 1, h = 1,
                        }),
                        0)
                end
            end
        end
    end

    win:setFrame(geometry.rect(screenFrame), 0)
    win:focus()

    -- Some apps maintain aspect ratio; re-center after macOS adjusts the size.
    timer.doAfter(0.05, function()
        if not state.active then return end
        local actualFrame = win:frame()
        if not actualFrame then return end

        if actualFrame.w < screenFrame.w or actualFrame.h < screenFrame.h then
            local centeredX = screenFrame.x + (screenFrame.w - actualFrame.w) / 2
            local centeredY = screenFrame.y + (screenFrame.h - actualFrame.h) / 2
            win:setFrame(geometry.rect({
                x = centeredX, y = centeredY,
                w = actualFrame.w, h = actualFrame.h,
            }), 0)
        end
    end)

    -- AX button rects aren't reliably available immediately; wait briefly.
    timer.doAfter(0.15, function()
        if not state.active then return end
        ui.setFullscreenButtons(win)
    end)
end

-- Re-apply the fullscreen window's frame after a screen-config change.
-- `enter()` captures the frame once and `tileWindows` is a no-op while
-- fullscreen is active, so without this the window keeps the pre-change
-- frame on resolution or rotation events. Idempotent: re-queries the
-- screen each call so it's safe to call multiple times.
function M.reframeToCurrentScreen()
    if not state.active or not state.window then return end
    local win = state.window
    if not callbacks.safeGetApplication or not callbacks.safeGetApplication(win) then return end
    local scr = win:screen()
    if not scr then return end
    local screenFrame = scr:frame()

    win:setFrame(geometry.rect(screenFrame), 0)

    -- Re-park hidden windows. The previous off-screen anchor may now sit
    -- inside the new arrangement after a display change.
    for _, data in ipairs(state.hiddenWindows) do
        if data.win and callbacks.safeGetApplication(data.win) then
            data.win:setFrame(
                geometry.rect({
                    x = screenFrame.x + screenFrame.w + 100,
                    y = screenFrame.y + screenFrame.h + 100,
                    w = 1, h = 1,
                }),
                0)
        end
    end
end

function M.getState()
    return state
end

function M.init(config, cbs)
    cfg = config
    callbacks = cbs or {}

    -- ui.lua reads callbacks at use-time (not init-time), so passing the same
    -- table reference lets init.lua's later backfills reach it.
    callbacks.isFullscreenActive = function() return state.active end
    callbacks.toggleFullscreen   = function(currentWin, winId)
        if state.active and state.window and state.window:id() == winId then
            M.exit()
        else
            M.enter(currentWin)
        end
    end

    ui.init(cfg, callbacks)
end

function M.cleanup()
    ui.cleanup()
    if state.overlayRefreshTimer then
        state.overlayRefreshTimer:stop()
        state.overlayRefreshTimer = nil
    end
end

-- Any access on M that isn't defined locally falls through to ui — covers
-- clear/create/show/hide button helpers, getButtonRect helpers, and the
-- updateButtonOverlays / updateButtonOverlaysWithRetry / Debounced functions.
setmetatable(M, { __index = ui })

return M
