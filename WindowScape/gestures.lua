-- Trackpad gesture recognition (TTTaps - N+1 finger gestures)

local eventtap = require("hs.eventtap")
local timer    = require("hs.timer")

local cfg, callbacks
local ttTaps = nil

-- Gesture state
local initialFingerCount         = 0
local gestureStartTime           = 0
local gestureStartThreshold      = 0.15  -- Cluster is still settling for this long after a finger arrives
local initialTouchIdentities     = {}    -- Identities of fingers in the settled cluster
local initialTouchPositions      = {}    -- Snapshot positions of cluster fingers
local gestureDragged             = false -- True if any cluster finger moved past dragThreshold; blocks dispatch
local ambiguousInitTime          = nil   -- Time of a 3+ finger landing in one event; lift within 200ms = +1
local plusOneActive              = false -- True after a +1 dispatched; cleared when touchCount drops back to the cluster
local lastNonZeroTouchTime       = nil   -- Time of last event with touchCount > 0; used for phantom/stale checks
local phantomLiftWindow          = 0.20  -- A touchCount=0 event within this much of the last real touch is treated as phantom
local pendingPhantomLift         = false -- True after we debounced an n=0 event; if the gap grows we treat it as real
local staleStateWindow           = 0.30  -- A non-zero event after this much silence with a pending phantom resets state
local dragThreshold              = 0.15  -- Normalized distance: cluster finger moved this far ⇒ drag, not tap

-- Diagnostic logging. Set true to print every gesture event to the console.
local debugLog                   = false

local function resetState()
    initialFingerCount         = 0
    gestureStartTime           = 0
    initialTouchIdentities     = {}
    initialTouchPositions      = {}
    gestureDragged             = false
    ambiguousInitTime          = nil
    plusOneActive              = false
end

local function handleTTTaps(event)
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

    if debugLog then
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
            "[ws.gestures] t=%.3f n=%d init=%d pOA=%s amb=%s drag=%s :: %s",
            currentTime,
            touchCount,
            initialFingerCount,
            tostring(plusOneActive),
            tostring(ambiguousInitTime),
            tostring(gestureDragged),
            table.concat(parts, " ")
        ))
    end

    -- Full release: reset, but reject phantom n=0 events that arrive while a
    -- real touch is still on the trackpad. macOS occasionally sends a spurious
    -- empty event mid-gesture (observed in the diagnostic trace).
    if touchCount == 0 then
        if lastNonZeroTouchTime and currentTime - lastNonZeroTouchTime < phantomLiftWindow then
            pendingPhantomLift = true
            return false
        end
        resetState()
        lastNonZeroTouchTime = nil
        pendingPhantomLift   = false
        return false
    end

    -- If we debounced an n=0 and then nothing came back for a long time, the
    -- "phantom" was actually a real lift. Reset state on the first non-zero
    -- event after the staleStateWindow.
    if pendingPhantomLift and lastNonZeroTouchTime
       and currentTime - lastNonZeroTouchTime > staleStateWindow then
        resetState()
    end
    pendingPhantomLift   = false
    lastNonZeroTouchTime = currentTime

    -- Count-based +1 re-arm. macOS reassigns touch identities mid-tap on some
    -- hardware (observed in the diagnostic trace), so identity- and phase-based
    -- dedup are unreliable. A single physical tap keeps touchCount at
    -- initialFingerCount + 1 from start to finish, so we only re-arm when the
    -- count actually drops back to the cluster.
    if plusOneActive and touchCount <= initialFingerCount then
        plusOneActive = false
    end

    local function snapshotInitial()
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

    local function newFingerPos()
        for i = 1, touchCount do
            if not initialTouchIdentities[touches[i].identity] then
                return touches[i].normalizedPosition
            end
        end
        return nil
    end

    local function dispatch(extraX)
        local side = extraX <= 0.5 and "left" or "right"
        if debugLog then
            print(string.format("[ws.gestures]   >>> DISPATCH initial=%d side=%s",
                initialFingerCount, side))
        end
        if initialFingerCount == 2 then
            if callbacks.focusAdjacentWindow then
                callbacks.focusAdjacentWindow(side == "left" and "backward" or "forward")
            end
        elseif initialFingerCount == 3 then
            if callbacks.moveWindowInOrder then
                callbacks.moveWindowInOrder(side == "left" and "backward" or "forward")
            end
        elseif initialFingerCount == 4 then
            if callbacks.moveWindowToAdjacentScreen then
                callbacks.moveWindowToAdjacentScreen(side == "left" and "previous" or "next")
            end
        end
    end

    -- Settle: first 2/3/4-finger cluster.
    if initialFingerCount == 0 then
        if touchCount == 2 or touchCount == 3 or touchCount == 4 then
            initialFingerCount = touchCount
            gestureStartTime   = currentTime
            snapshotInitial()
            if touchCount >= 3 then
                ambiguousInitTime = currentTime
            end
        end
        return false
    end

    -- More fingers than the settled cluster.
    if touchCount > initialFingerCount then
        if gestureDragged or plusOneActive then return false end
        local age = currentTime - gestureStartTime
        if age < gestureStartThreshold then
            -- Still settling: treat additional fingers as part of the cluster.
            if touchCount <= 4 then
                initialFingerCount = touchCount
                gestureStartTime   = currentTime
                snapshotInitial()
                ambiguousInitTime  = currentTime
            end
            return false
        end
        -- Past settling: a +1 tap. Fire on touchdown; re-arm via the
        -- count-based check at the top of the next event.
        if touchCount == initialFingerCount + 1 then
            local pos = newFingerPos()
            if pos then
                plusOneActive = true
                dispatch(pos.x)
            end
        end
        return false
    end

    -- A finger lifted from the cluster.
    if touchCount < initialFingerCount then
        -- Ambiguous-init: 3+ landed together, one lifted within 200 ms.
        -- The lifted finger was the +1; use its snapshotted X to pick the side.
        if ambiguousInitTime and currentTime - ambiguousInitTime < 0.20
           and not gestureDragged and not plusOneActive then
            local presentIds = {}
            for i = 1, touchCount do presentIds[touches[i].identity] = true end
            local liftedX
            for id, pos in pairs(initialTouchPositions) do
                if not presentIds[id] then liftedX = pos.x; break end
            end
            if liftedX then
                plusOneActive      = true
                initialFingerCount = touchCount
                snapshotInitial()
                dispatch(liftedX)
                ambiguousInitTime = nil
                return false
            end
        end
        -- Held finger left: re-settle to the new cluster size.
        ambiguousInitTime  = nil
        initialFingerCount = touchCount
        gestureStartTime   = currentTime
        snapshotInitial()
        return false
    end

    -- Steady at the cluster size.
    if ambiguousInitTime and currentTime - ambiguousInitTime > 0.20 then
        ambiguousInitTime = nil
    end

    -- Drag detection: any cluster finger moved past threshold ⇒ taint, suppress future taps.
    if not gestureDragged then
        for i = 1, touchCount do
            local id = touches[i].identity
            local initPos = initialTouchPositions[id]
            if initPos then
                local dx = touches[i].normalizedPosition.x - initPos.x
                local dy = touches[i].normalizedPosition.y - initPos.y
                if (dx * dx + dy * dy) > (dragThreshold * dragThreshold) then
                    gestureDragged = true
                    break
                end
            end
        end
    end

    return false
end

local function start()
    if not cfg.enableTTTaps then return end

    if ttTaps then
        ttTaps:stop()
    end

    ttTaps = eventtap.new({ eventtap.event.types.gesture }, handleTTTaps)
    ttTaps:start()
end

local function stop()
    if ttTaps then
        ttTaps:stop()
        ttTaps = nil
    end
end

local function check()
    if not cfg.enableTTTaps then return end
    if not ttTaps or not ttTaps:isEnabled() then
        start()
    end
end

local function restart()
    stop()
    start()
end

local function init(config, cbs)
    cfg = config
    callbacks = cbs or {}
end

return {
    init = init,
    start = start,
    stop = stop,
    check = check,
    restart = restart,
}
