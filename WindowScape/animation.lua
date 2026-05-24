-- Window frame animation with easing

local timer    = require("hs.timer")
local geometry = require("hs.geometry")

local activeAnimations = {}
local cfg = nil

local function easeOutCubic(t)
    return 1 - math.pow(1 - t, 3)
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function lerpColor(c1, c2, t)
    return {
        red = lerp(c1.red or 0, c2.red or 0, t),
        green = lerp(c1.green or 0, c2.green or 0, t),
        blue = lerp(c1.blue or 0, c2.blue or 0, t),
        alpha = lerp(c1.alpha or 1, c2.alpha or 1, t),
    }
end

local function cancelAnimation(winId)
    if activeAnimations[winId] then
        if activeAnimations[winId].timer then
            activeAnimations[winId].timer:stop()
        end
        activeAnimations[winId] = nil
    end
end

local function cancelAllAnimations()
    for winId, _ in pairs(activeAnimations) do
        cancelAnimation(winId)
    end
end

local function isAnimating(winId)
    return activeAnimations[winId] ~= nil
end

local function animatedSetFrame(win, targetFrame, onComplete)
    if not win then return end
    local winId = win:id()
    if not winId then
        win:setFrame(geometry.rect(targetFrame), 0)
        if onComplete then onComplete() end
        return
    end

    cancelAnimation(winId)

    if not cfg or not cfg.enableAnimations then
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

    -- skip if frames nearly identical
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

local function init(config)
    cfg = config
end

return {
    init = init,
    easeOutCubic = easeOutCubic,
    lerp = lerp,
    lerpColor = lerpColor,
    cancelAnimation = cancelAnimation,
    cancelAllAnimations = cancelAllAnimations,
    isAnimating = isAnimating,
    animatedSetFrame = animatedSetFrame,
}
