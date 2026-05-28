-- Trackpad gesture recognition (TTTaps - N+1 finger gestures)

local eventtap = require("hs.eventtap")
local timer    = require("hs.timer")

local cfg, callbacks
local ttTaps = nil

-- Gesture state
local initialFingerCount         = 0
local gestureStartTime           = 0
local gestureStartThreshold      = 0.08 -- Time to let all initial fingers settle before detecting +1
local clusterGap                 = 0.00 -- Normalized x distance for "outside cluster" (fires +1 mid-settle)
local initialTouchIdentities     = {}   -- Store touch identities instead of positions

local actionPerformedThisGesture = false -- Track if +1 action was performed
local pendingSide                = nil   -- Queued tap side ("left"/"right"); dispatched on +1 lift
local speculativeBumpFrom        = nil   -- Pre-bump initialFingerCount; non-nil while speculative absorb is in effect
local ambiguousInitTime          = nil   -- Time of initial 3+/4-finger landing; lift within 200ms = +1 tap
local fingersAddedDuringSettling = false -- Track if more fingers were added during settling (indicates failed +1)
local initialTouchPositions      = {}    -- Track initial positions to detect drag vs tap
local dragThreshold              = 0.15  -- Normalized distance threshold for drag detection (15% of trackpad)
local gestureDragged             = false -- Track if fingers moved significantly (drag, not tap)
local lastLiftTime               = 0     -- Time of last processed lift (to ignore rapid phantom lifts)

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

    if touchCount == 0 then
        -- Ignore rapid phantom lifts from system gestures (require 0.3s between lifts)
        if currentTime - lastLiftTime < 0.3 then
            return false
        end
        lastLiftTime = currentTime

        if initialFingerCount > 0 then
            initialFingerCount     = 0
            gestureStartTime       = 0
            initialTouchIdentities = {}
        end
        actionPerformedThisGesture = false
        fingersAddedDuringSettling = false
        gestureDragged             = false
        pendingSide                = nil
        speculativeBumpFrom        = nil
        ambiguousInitTime          = nil
        initialTouchPositions      = {}
        return false
    end

    local function snapshotInitial()
        initialTouchIdentities = {}
        initialTouchPositions = {}
        for i = 1, touchCount do
            initialTouchIdentities[touches[i].identity] = true
            initialTouchPositions[touches[i].identity] = {
                x = touches[i].normalizedPosition.x,
                y = touches[i].normalizedPosition.y
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

    local function isOutsideCluster(pos)
        if not pos then return false end
        local minX, maxX = math.huge, -math.huge
        for _, p in pairs(initialTouchPositions) do
            if p.x < minX then minX = p.x end
            if p.x > maxX then maxX = p.x end
        end
        return pos.x < (minX - clusterGap) or pos.x > (maxX + clusterGap)
    end

    local function queueAction(side)
        pendingSide = side
    end

    local function dispatchPending()
        local side = pendingSide
        if not side then return end
        pendingSide = nil
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
        actionPerformedThisGesture = true
    end

    if initialFingerCount == 0 then
        if touchCount == 2 or touchCount == 3 or touchCount == 4 then
            initialFingerCount = touchCount
            gestureStartTime = currentTime
            snapshotInitial()
            -- If 3+ fingers landed in one frame, mark as ambiguous: a finger lifting
            -- within 200ms is likely a +1 tap whose down event was merged by the OS.
            if touchCount >= 3 then
                ambiguousInitTime = currentTime
            end
        end
    elseif touchCount > initialFingerCount and touchCount <= 4 and gestureStartTime and (currentTime - gestureStartTime < gestureStartThreshold) then
        -- More fingers arrived during the settling window.
        local extraPos = (touchCount == initialFingerCount + 1) and newFingerPos() or nil
        if extraPos then
            if isOutsideCluster(extraPos) then
                queueAction(extraPos.x <= 0.5 and "left" or "right")
            else
                queueAction(extraPos.x <= 0.5 and "left" or "right")
                if not speculativeBumpFrom then
                    speculativeBumpFrom = initialFingerCount
                end
                if initialFingerCount == 2 and touchCount == 3 then
                    fingersAddedDuringSettling = true
                end
                initialFingerCount = touchCount
                gestureStartTime = currentTime
                snapshotInitial()
            end
        else
            initialFingerCount = touchCount
            gestureStartTime = currentTime
            snapshotInitial()
            speculativeBumpFrom = nil
            pendingSide = nil
        end
    elseif touchCount < initialFingerCount and gestureStartTime then
        if speculativeBumpFrom then
            initialFingerCount = speculativeBumpFrom
            speculativeBumpFrom = nil
            snapshotInitial()
            dispatchPending()
        elseif ambiguousInitTime and currentTime - ambiguousInitTime < 0.20 then
            -- Initial set was ambiguous and a finger lifted in the tap window:
            -- the missing finger was the +1 tap. Use its position to pick side.
            local presentIds = {}
            for i = 1, touchCount do presentIds[touches[i].identity] = true end
            local liftedX = nil
            for id, pos in pairs(initialTouchPositions) do
                if not presentIds[id] then liftedX = pos.x; break end
            end
            if liftedX then
                initialFingerCount = touchCount
                snapshotInitial()
                queueAction(liftedX <= 0.5 and "left" or "right")
                dispatchPending()
            end
            ambiguousInitTime = nil
        end
        if touchCount < initialFingerCount then
            initialFingerCount = touchCount
            gestureStartTime = currentTime
            snapshotInitial()
            pendingSide = nil
        end
    elseif touchCount >= initialFingerCount and gestureStartTime then
        if touchCount == initialFingerCount then
            -- If a speculative bump has been sitting for long enough, confirm as rest
            -- (cancel the queued action and commit to the bumped initialFingerCount).
            if speculativeBumpFrom and currentTime - gestureStartTime > 0.20 then
                speculativeBumpFrom = nil
                pendingSide = nil
            end
            -- If the ambiguous-init window expired, commit to the multi-finger initial.
            if ambiguousInitTime and currentTime - ambiguousInitTime > 0.20 then
                ambiguousInitTime = nil
            end
            -- Only dispatch outside speculative mode; lift in partial-lift branch decides otherwise.
            if not speculativeBumpFrom then
                dispatchPending()
            end
        end
        -- Check if any finger has moved beyond drag threshold
        if not gestureDragged and touchCount == initialFingerCount then
            for i = 1, touchCount do
                local identity = touches[i].identity
                local initPos = initialTouchPositions[identity]
                if initPos then
                    local dx = touches[i].normalizedPosition.x - initPos.x
                    local dy = touches[i].normalizedPosition.y - initPos.y
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist > dragThreshold then
                        gestureDragged = true
                        break
                    end
                end
            end
        end

        if touchCount == initialFingerCount + 1 and currentTime - gestureStartTime > gestureStartThreshold then
            local extraPos = newFingerPos()
            if extraPos then
                queueAction(extraPos.x <= 0.5 and "left" or "right")
            end
        end
    end

    return false -- Don't consume event
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
