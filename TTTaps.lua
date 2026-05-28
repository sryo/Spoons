-- TTTaps: shared trackpad gesture recognizer.
--
-- Two recognizers feed off one hs.eventtap subscription:
--   TTTaps.onTap(n, fn)         fn() when exactly n fingers land and one lifts.
--   TTTaps.onPlusOne(cluster, fn)  fn(side) when a settled 2/3/4 cluster gets a
--                                  +1 tap. side is "left" or "right" based on
--                                  the extra finger's normalized x.
--
-- Lifecycle: TTTaps.start / stop / check / restart. Register handlers before
-- start; re-registration is idempotent (last fn wins per n / cluster).

local eventtap = require("hs.eventtap")
local timer    = require("hs.timer")

local M = {}

M.config = {
    gestureStartThreshold = 0.15, -- Cluster is still settling for this long after a finger arrives
    ambiguousInitWindow   = 0.20, -- 3+ landed together; a lift within this window is treated as the +1
    dragThreshold         = 0.15, -- Normalized distance: cluster finger moved this far means drag, taint dispatch
    phantomLiftWindow     = 0.20, -- A touchCount=0 within this much of the last real touch is treated as phantom
    staleStateWindow      = 0.30, -- A non-zero event after this much silence with a pending phantom resets state
    debugLog              = false,
}

local handlers = { tap = {}, plusOne = {} }
local clusterCap = 4

local tap = nil

local initialFingerCount     = 0
local gestureStartTime       = 0
local initialTouchIdentities = {}
local initialTouchPositions  = {}
local gestureDragged         = false
local ambiguousInitTime      = nil
local plusOneActive          = false
local lastNonZeroTouchTime   = nil
local pendingPhantomLift     = false
local peakCount              = 0
local plusOneFired           = false
local onTapFiredThisCycle    = false

local function resetState()
    initialFingerCount     = 0
    gestureStartTime       = 0
    initialTouchIdentities = {}
    initialTouchPositions  = {}
    gestureDragged         = false
    ambiguousInitTime      = nil
    plusOneActive          = false
    peakCount              = 0
    plusOneFired           = false
    onTapFiredThisCycle    = false
end

local function snapshotInitial(touches, touchCount)
    initialTouchIdentities = {}
    initialTouchPositions  = {}
    for i = 1, touchCount do
        initialTouchIdentities[touches[i].identity] = true
        initialTouchPositions[touches[i].identity] = {
            x = touches[i].normalizedPosition.x,
            y = touches[i].normalizedPosition.y,
        }
    end
end

local function newFingerPos(touches, touchCount)
    for i = 1, touchCount do
        if not initialTouchIdentities[touches[i].identity] then
            return touches[i].normalizedPosition
        end
    end
    return nil
end

local function dispatchPlusOne(extraX)
    -- Side is relative to the cluster's centroid, not the trackpad midpoint,
    -- so a cluster planted off-center still resolves left/right the way the
    -- user expects. Callers must ensure initialTouchPositions reflects the
    -- cluster fingers only (snapshot taken without the +1).
    local sum, count = 0, 0
    for _, pos in pairs(initialTouchPositions) do
        sum = sum + pos.x
        count = count + 1
    end
    local centroidX = count > 0 and sum / count or 0.5
    local side = extraX <= centroidX and "left" or "right"
    if M.config.debugLog then
        print(string.format("[tttaps]   >>> PLUSONE cluster=%d side=%s (extraX=%.2f centroid=%.2f)",
            initialFingerCount, side, extraX, centroidX))
    end
    plusOneFired = true
    local fn = handlers.plusOne[initialFingerCount]
    if fn then fn(side) end
end

local function onGesture(event)
    local eventType = event:getType(true)
    if eventType ~= eventtap.event.types.gesture then
        return false
    end

    local touches = event:getTouches()
    local touchCount = touches and #touches or 0
    local currentTime = timer.secondsSinceEpoch()

    local touchDetails = event:getTouchDetails()
    if not touchDetails then return false end
    if touchDetails.pressure then return false end

    if M.config.debugLog then
        local parts = {}
        for i = 1, touchCount do
            local t = touches[i]
            local p = t.normalizedPosition or {}
            parts[#parts + 1] = string.format(
                "[id=%s ph=%s touch=%s x=%.2f y=%.2f]",
                tostring(t.identity),
                tostring(t.phase),
                tostring(t.touching),
                p.x or -1, p.y or -1
            )
        end
        print(string.format(
            "[tttaps] t=%.3f n=%d init=%d pOA=%s amb=%s drag=%s :: %s",
            currentTime,
            touchCount,
            initialFingerCount,
            tostring(plusOneActive),
            tostring(ambiguousInitTime),
            tostring(gestureDragged),
            table.concat(parts, " ")
        ))
    end

    if touchCount == 0 then
        -- Fire onTap on the first n=0 of the cycle. The phantom-lift debounce
        -- below preserves cluster state for spurious mid-gesture n=0 events,
        -- but we don't wait for it because real releases produce no follow-up
        -- event to trigger stale recovery.
        if not onTapFiredThisCycle then
            local fn = handlers.tap[peakCount]
            if fn and not plusOneFired and not gestureDragged then
                fn()
            end
            onTapFiredThisCycle = true
        end
        if lastNonZeroTouchTime and currentTime - lastNonZeroTouchTime < M.config.phantomLiftWindow then
            pendingPhantomLift = true
            return false
        end
        resetState()
        lastNonZeroTouchTime = nil
        pendingPhantomLift   = false
        return false
    end

    if pendingPhantomLift and lastNonZeroTouchTime
       and currentTime - lastNonZeroTouchTime > M.config.staleStateWindow then
        resetState()
    end
    pendingPhantomLift   = false
    lastNonZeroTouchTime = currentTime

    if touchCount > peakCount then peakCount = touchCount end

    if plusOneActive and touchCount <= initialFingerCount then
        plusOneActive = false
    end

    if initialFingerCount == 0 then
        if touchCount >= 2 and touchCount <= clusterCap then
            initialFingerCount = touchCount
            gestureStartTime   = currentTime
            snapshotInitial(touches, touchCount)
            if touchCount >= 3 then
                ambiguousInitTime = currentTime
            end
        end
        return false
    end

    if touchCount > initialFingerCount then
        if gestureDragged or plusOneActive then return false end
        local age = currentTime - gestureStartTime
        if age < M.config.gestureStartThreshold then
            if touchCount <= clusterCap then
                initialFingerCount = touchCount
                gestureStartTime   = currentTime
                snapshotInitial(touches, touchCount)
                ambiguousInitTime  = currentTime
            end
            return false
        end
        if touchCount == initialFingerCount + 1 then
            local pos = newFingerPos(touches, touchCount)
            if pos then
                plusOneActive = true
                dispatchPlusOne(pos.x)
            end
        end
        return false
    end

    if touchCount < initialFingerCount then
        -- Ambiguous-init disambiguation: 3+ fingers landed together; a lift
        -- within the window means the lifted finger was a +1 on a smaller
        -- cluster. Skip this path when the current cluster size has a
        -- registered onTap, because the user's intent is more likely an
        -- N-finger tap (one finger lifting first) than an (N-1)+1.
        if ambiguousInitTime and currentTime - ambiguousInitTime < M.config.ambiguousInitWindow
           and not gestureDragged and not plusOneActive
           and not handlers.tap[initialFingerCount] then
            local presentIds = {}
            for i = 1, touchCount do presentIds[touches[i].identity] = true end
            local liftedX
            for id, pos in pairs(initialTouchPositions) do
                if not presentIds[id] then liftedX = pos.x; break end
            end
            if liftedX then
                plusOneActive      = true
                initialFingerCount = touchCount
                snapshotInitial(touches, touchCount)
                dispatchPlusOne(liftedX)
                ambiguousInitTime = nil
                return false
            end
        end
        ambiguousInitTime  = nil
        initialFingerCount = touchCount
        gestureStartTime   = currentTime
        snapshotInitial(touches, touchCount)
        return false
    end

    if ambiguousInitTime and currentTime - ambiguousInitTime > M.config.ambiguousInitWindow then
        ambiguousInitTime = nil
    end

    if not gestureDragged then
        for i = 1, touchCount do
            local id = touches[i].identity
            local initPos = initialTouchPositions[id]
            if initPos then
                local dx = touches[i].normalizedPosition.x - initPos.x
                local dy = touches[i].normalizedPosition.y - initPos.y
                if (dx * dx + dy * dy) > (M.config.dragThreshold * M.config.dragThreshold) then
                    gestureDragged = true
                    break
                end
            end
        end
    end

    return false
end

function M.onTap(n, fn)
    if type(n) ~= "number" or n <= 0 then return end
    handlers.tap[n] = fn
    if n > clusterCap then clusterCap = n end
end

function M.onPlusOne(cluster, fn)
    if type(cluster) ~= "number" or cluster < 2 or cluster > 4 then return end
    handlers.plusOne[cluster] = fn
end

function M.start()
    if tap then tap:stop() end
    tap = eventtap.new({ eventtap.event.types.gesture }, onGesture)
    tap:start()
end

function M.stop()
    if tap then tap:stop(); tap = nil end
    resetState()
end

function M.check()
    if not tap or not tap:isEnabled() then M.start() end
end

function M.restart()
    M.stop()
    M.start()
end

M._onGesture = onGesture

return M
