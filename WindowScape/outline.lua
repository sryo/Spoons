-- Active window outline with color animation
--
-- Corner radius detection (macOS Tahoe / macOS 26):
-- Tahoe uses per-window corner radii based on window style:
--   - 26 pt for titled windows with a toolbar (Finder, etc.)
--   - 16 pt for titled windows without a toolbar (Terminal, etc.)
--   -  0 pt for borderless windows
-- Inferred via AXUIElement toolbar detection (AXChildren → AXRole=="AXToolbar").

local drawing     = require("hs.drawing")
local geometry    = require("hs.geometry")
local timer       = require("hs.timer")
local window      = require("hs.window")
local axuielement = require("hs.axuielement")

local cfg, CONST, animation
local getColorForWindow -- callback to get outline color
local isSnapshotted -- callback to check if window is snapshotted
local isAXSlow -- callback to check if a window's app has slow AX (skip queries)
local log -- logging function

local FAST_INTERVAL = 0.033
local SLOW_INTERVAL = 0.2
local IDLE_TICKS = 6

local activeOutline = nil
local refreshTimer = nil
local refreshInterval = nil
local lastFrame = nil
local trackedWinId = nil
local hideCounter = 0
local stableTickCount = 0

local currentColor = nil
local targetColor = nil
local colorAnimTimer = nil
local trackedCornerRadius = nil
local appliedCornerRadius = nil
local trackedColor = nil

local function getCornerRadius(win)
    if not win then return 0 end
    if not win:isStandard() then return 0 end
    -- Skip AX for known-slow apps (Catalyst etc.); use the more-common 16.
    -- pcall guards against a window whose process has died (NSRunningApplication
    -- fetch raises a LuaSkin error otherwise).
    local ok, app = pcall(function() return win:application() end)
    if isAXSlow and ok and app and isAXSlow(app) then return 16 end
    local axWin = axuielement.windowElement(win)
    local children = axWin:attributeValue("AXChildren")
    if children then
        for _, child in ipairs(children) do
            if child:attributeValue("AXRole") == "AXToolbar" then
                return 26
            end
        end
    end
    return 16
end

local function framesEqual(f1, f2)
    if not f1 or not f2 then return false end
    return f1.x == f2.x and f1.y == f2.y and f1.w == f2.w and f1.h == f2.h
end

local function isSystem(win)
    return win and (win:role() == "AXScrollArea" or win:subrole() == "AXSystemDialog")
end

local function stopRefresh()
    if refreshTimer then
        refreshTimer:stop()
        refreshTimer = nil
    end
    refreshInterval = nil
end

local function animateColor(newTargetColor)
    if not activeOutline then return end
    if not newTargetColor then return end

    -- check if already animating to this color
    if targetColor then
        local diff = math.abs((targetColor.red or 0) - (newTargetColor.red or 0)) +
            math.abs((targetColor.green or 0) - (newTargetColor.green or 0)) +
            math.abs((targetColor.blue or 0) - (newTargetColor.blue or 0))
        if diff < 0.01 then return end
    end

    if colorAnimTimer then
        colorAnimTimer:stop()
        colorAnimTimer = nil
    end

    if not currentColor then
        currentColor = newTargetColor
        targetColor = newTargetColor
        activeOutline:setStrokeColor(currentColor)
        return
    end

    local colorDiff = math.abs((currentColor.red or 0) - (newTargetColor.red or 0)) +
        math.abs((currentColor.green or 0) - (newTargetColor.green or 0)) +
        math.abs((currentColor.blue or 0) - (newTargetColor.blue or 0))
    if colorDiff < 0.01 then
        currentColor = newTargetColor
        targetColor = newTargetColor
        activeOutline:setStrokeColor(currentColor)
        return
    end

    targetColor = newTargetColor
    local startColor = {
        red = currentColor.red,
        green = currentColor.green,
        blue = currentColor.blue,
        alpha = currentColor.alpha
    }
    local startTime = timer.secondsSinceEpoch()
    local duration = 0.15

    colorAnimTimer = timer.doEvery(CONST.ANIMATION_INTERVAL, function()
        local elapsed = timer.secondsSinceEpoch() - startTime
        local t = math.min(elapsed / duration, 1)
        local ease = animation.easeOutCubic(t)

        currentColor = animation.lerpColor(startColor, targetColor, ease)
        if activeOutline then
            activeOutline:setStrokeColor(currentColor)
        end

        if t >= 1 then
            colorAnimTimer:stop()
            colorAnimTimer = nil
        end
    end)
end

local function updateFrame(frame, win)
    if not frame then return end

    local adjustedFrame = { x = frame.x, y = frame.y, w = frame.w, h = frame.h }
    -- trackedColor and trackedCornerRadius are computed once per focus change
    -- in draw(); reuse them so the 30 fps refresh doesn't call back into
    -- getColorForWindow or AX on every tick.
    local color = trackedColor or getColorForWindow(win)
    local radius = trackedCornerRadius or 16

    if not activeOutline then
        if log then log("CREATE outline at " .. adjustedFrame.x .. "," .. adjustedFrame.y) end
        activeOutline = drawing.rectangle(geometry.rect(adjustedFrame))
        currentColor = color
        activeOutline:setStrokeColor(currentColor)
        activeOutline:setFill(false)
        activeOutline:setStrokeWidth(cfg.outlineThickness)
        activeOutline:setRoundedRectRadii(radius, radius)
        activeOutline:setLevel(drawing.windowLevels.floating)
        appliedCornerRadius = radius
    else
        local framesMatch = framesEqual(adjustedFrame, lastFrame)
        if not framesMatch then
            local currentFrame = activeOutline:frame()
            if log then
                log("MOVING outline from " .. math.floor(currentFrame.x) .. "," .. math.floor(currentFrame.y) ..
                    " to " .. math.floor(adjustedFrame.x) .. "," .. math.floor(adjustedFrame.y))
            end
            activeOutline:hide()
            activeOutline:setFrame(geometry.rect(adjustedFrame))
        end
        if radius ~= appliedCornerRadius then
            activeOutline:setRoundedRectRadii(radius, radius)
            appliedCornerRadius = radius
        end
        animateColor(color)
    end

    lastFrame = adjustedFrame
    activeOutline:show()
end

local function clearTracked()
    trackedWinId = nil
    lastFrame = nil
    trackedCornerRadius = nil
    appliedCornerRadius = nil
    trackedColor = nil
end

local function refresh()
    local win = window.focusedWindow()
    if not win then
        if activeOutline then activeOutline:hide() end
        stopRefresh()
        clearTracked()
        return
    end

    local winId = win:id()
    if winId ~= trackedWinId then
        if activeOutline then activeOutline:hide() end
        stopRefresh()
        clearTracked()
        return
    end

    if not win:isVisible() then
        hideCounter = hideCounter + 1
        if hideCounter > 3 then
            if activeOutline then activeOutline:hide() end
            stopRefresh()
        end
        return
    end
    hideCounter = 0

    local frame = win:frame()
    if not frame then return end

    if framesEqual(frame, lastFrame) then
        stableTickCount = stableTickCount + 1
    else
        stableTickCount = 0
    end

    updateFrame(frame, win)

    -- Idle backoff: after IDLE_TICKS of stillness, slow the polling rate.
    -- Any frame change while slow brings us straight back to fast.
    if refreshInterval == FAST_INTERVAL and stableTickCount >= IDLE_TICKS then
        refreshTimer:stop()
        refreshInterval = SLOW_INTERVAL
        refreshTimer = timer.doEvery(SLOW_INTERVAL, refresh)
    elseif refreshInterval == SLOW_INTERVAL and stableTickCount == 0 then
        refreshTimer:stop()
        refreshInterval = FAST_INTERVAL
        refreshTimer = timer.doEvery(FAST_INTERVAL, refresh)
    end
end

local function startRefresh(win)
    stopRefresh()
    hideCounter = 0
    stableTickCount = 0
    refreshInterval = FAST_INTERVAL
    refreshTimer = timer.doEvery(FAST_INTERVAL, refresh)
end

local function draw(win)
    if log then log("drawOutline: " .. (win and win:title() or "nil") .. " id:" .. tostring(win and win:id())) end
    -- Don't draw outline for snapshotted (minimized) windows
    local winId = win and win:id()
    if winId and isSnapshotted and isSnapshotted(winId) then
        if activeOutline then activeOutline:hide() end
        stopRefresh()
        return
    end
    if win and win:isVisible() and not win:isFullScreen() and not isSystem(win) then
        local frame = win:frame()
        if not frame then return end

        trackedWinId = win:id()
        trackedCornerRadius = getCornerRadius(win)
        trackedColor = getColorForWindow(win)
        if log then log("outline frame: " .. frame.x .. "," .. frame.y .. " " .. frame.w .. "x" .. frame.h) end
        updateFrame(frame, win)
        startRefresh(win)
    else
        clearTracked()
        stopRefresh()
        if activeOutline then
            activeOutline:hide()
        end
    end
end

local function hide()
    if activeOutline then
        activeOutline:hide()
    end
end

local function cleanup()
    stopRefresh()
    if colorAnimTimer then colorAnimTimer:stop(); colorAnimTimer = nil end
    if activeOutline then activeOutline:hide() end
    appliedCornerRadius = nil
end

local function init(config, constants, anim, colorCallback, logFn, isSnapshottedFn, isAXSlowFn)
    cfg = config
    CONST = constants
    animation = anim
    getColorForWindow = colorCallback
    log = logFn
    isSnapshotted = isSnapshottedFn
    isAXSlow = isAXSlowFn
end

return {
    init = init,
    draw = draw,
    hide = hide,
    stopRefresh = stopRefresh,
    cleanup = cleanup,
}
