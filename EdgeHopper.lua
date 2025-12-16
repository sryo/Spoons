-- EdgeHopper.lua: Wrap the mouse cursor when it moves off the edge of the screen

-- Configuration
local PRESSURE_THRESHOLD = 100 -- pixels of accumulated pressure to trigger
local PRESSURE_TIMEOUT = 1000  -- ms window for pressure accumulation
local MAX_PRESSURE_PER_EVENT = 15
local CORNER_EXCLUSION = 10
local WRAP_OFFSET = 25
local BUFFER_ZONE = 20    -- larger zone for dwell detection
local DWELL_TIMEOUT = 500 -- ms of inactivity to trigger dwell mode

-- Per-edge enable flags
local ENABLED_EDGES = {
    left = true,
    right = true,
    top = true,
    bottom = true
}

-- Multi-monitor behavior: "current" = wrap within current screen, "all" = wrap across all screens
local WRAP_MODE = "current"

-- State
local pressureEvents = {}
local currentPressure = 0
local lastTime = 0
local isTriggered = false
local currentEdge = nil
local membraneCanvas = nil
local ghostCanvas = nil
local isDwelling = false
local dwellTimer = nil

local function initMembrane()
    if membraneCanvas then return end
    membraneCanvas = hs.canvas.new({ x = 0, y = 0, w = 100, h = 100 })
    membraneCanvas:level(hs.canvas.windowLevels.cursor)
    membraneCanvas:behavior("canJoinAllSpaces")
    membraneCanvas[1] = {
        type = "segments",
        action = "stroke",
        strokeColor = { white = 1, alpha = 0 },
        strokeWidth = 2,
        coordinates = {}
    }
    membraneCanvas[2] = {
        type = "segments",
        action = "stroke",
        strokeColor = { white = 1, alpha = 0 },
        strokeWidth = 6,
        coordinates = {}
    }
end

local function initGhost()
    if ghostCanvas then return end
    ghostCanvas = hs.canvas.new({ x = 0, y = 0, w = 100, h = 100 })
    ghostCanvas:level(hs.canvas.windowLevels.cursor)
    ghostCanvas:behavior("canJoinAllSpaces")
    ghostCanvas[1] = {
        type = "segments",
        action = "fill",
        fillColor = { white = 0, alpha = 0 },
        coordinates = {}
    }
    ghostCanvas[2] = {
        type = "segments",
        action = "stroke",
        strokeColor = { white = 1, alpha = 0 },
        strokeWidth = 1,
        coordinates = {}
    }
end

local function showGhostBulge(edge, x, y, screen, progress)
    initGhost()

    local frame = screen:fullFrame()
    local coords = {}
    local segments = 16
    local length = 100
    local bulge = progress * 20 -- matches membrane bulge
    local canvasX, canvasY, canvasW, canvasH

    if edge == "left" or edge == "right" then
        -- Ghost appears on opposite edge
        local baseX = (edge == "left") and (frame.x + frame.w) or frame.x
        local startY = y - length / 2
        canvasX = baseX - 25
        canvasY = startY - 5
        canvasW = 50
        canvasH = length + 10

        for i = 0, segments do
            local t = i / segments
            local py = startY + t * length
            local bulgeAmount = bulge * (1 - (2 * t - 1) ^ 2)
            -- Bulge inward (opposite direction of membrane)
            local px = baseX + ((edge == "left") and -bulgeAmount or bulgeAmount)
            table.insert(coords, { x = px - canvasX, y = py - canvasY })
        end
    else
        local baseY = (edge == "top") and (frame.y + frame.h) or frame.y
        local startX = x - length / 2
        canvasX = startX - 5
        canvasY = baseY - 25
        canvasW = length + 10
        canvasH = 50

        for i = 0, segments do
            local t = i / segments
            local px = startX + t * length
            local bulgeAmount = bulge * (1 - (2 * t - 1) ^ 2)
            -- Bulge inward
            local py = baseY + ((edge == "top") and -bulgeAmount or bulgeAmount)
            table.insert(coords, { x = px - canvasX, y = py - canvasY })
        end
    end

    ghostCanvas:frame({ x = canvasX, y = canvasY, w = canvasW, h = canvasH })
    ghostCanvas[1].coordinates = coords
    ghostCanvas[1].fillColor.alpha = progress * 1
    ghostCanvas[2].coordinates = coords
    ghostCanvas[2].strokeColor.alpha = progress * 0.5
    ghostCanvas:show()
end

local function hideGhost()
    if ghostCanvas then ghostCanvas:hide() end
end

local function hideMembrane()
    if membraneCanvas then membraneCanvas:hide() end
end

local function updateMembrane(edge, x, y, frame, progress)
    initMembrane()

    local coords = {}
    local segments = 16
    local length = 100
    local bulge = progress * 20
    local canvasX, canvasY, canvasW, canvasH

    if edge == "left" or edge == "right" then
        local baseX = (edge == "left") and frame.x or (frame.x + frame.w)
        local startY = y - length / 2
        canvasX = baseX - 25
        canvasY = startY - 5
        canvasW = 50
        canvasH = length + 10

        for i = 0, segments do
            local t = i / segments
            local py = startY + t * length
            local bulgeAmount = bulge * (1 - (2 * t - 1) ^ 2)
            local px = baseX + ((edge == "left") and bulgeAmount or -bulgeAmount)
            table.insert(coords, { x = px - canvasX, y = py - canvasY })
        end
    else
        local baseY = (edge == "top") and frame.y or (frame.y + frame.h)
        local startX = x - length / 2
        canvasX = startX - 5
        canvasY = baseY - 25
        canvasW = length + 10
        canvasH = 50

        for i = 0, segments do
            local t = i / segments
            local px = startX + t * length
            local bulgeAmount = bulge * (1 - (2 * t - 1) ^ 2)
            local py = baseY + ((edge == "top") and bulgeAmount or -bulgeAmount)
            table.insert(coords, { x = px - canvasX, y = py - canvasY })
        end
    end

    membraneCanvas:frame({ x = canvasX, y = canvasY, w = canvasW, h = canvasH })
    membraneCanvas[1].coordinates = coords
    membraneCanvas[1].strokeColor.alpha = progress * 0.9
    membraneCanvas[2].coordinates = coords
    membraneCanvas[2].strokeColor.alpha = progress * 0.35
    membraneCanvas:show()
end

local function inCorner(x, y, frame)
    local nearLeft = x <= frame.x + CORNER_EXCLUSION
    local nearRight = x >= frame.x + frame.w - CORNER_EXCLUSION
    local nearTop = y <= frame.y + CORNER_EXCLUSION
    local nearBottom = y >= frame.y + frame.h - CORNER_EXCLUSION
    return (nearLeft or nearRight) and (nearTop or nearBottom)
end

local function getEdgeAt(x, y, frame)
    local threshold = 3
    if x <= frame.x + threshold then
        return "left"
    elseif x >= frame.x + frame.w - threshold then
        return "right"
    elseif y <= frame.y + threshold then
        return "top"
    elseif y >= frame.y + frame.h - threshold then
        return "bottom"
    end
    return nil
end

local function inBufferZone(x, y, frame)
    return x <= frame.x + BUFFER_ZONE
        or x >= frame.x + frame.w - BUFFER_ZONE
        or y <= frame.y + BUFFER_ZONE
        or y >= frame.y + frame.h - BUFFER_ZONE
end

local function startDwellTimer()
    if dwellTimer then dwellTimer:stop() end
    dwellTimer = hs.timer.doAfter(DWELL_TIMEOUT / 1000, function()
        isDwelling = true
        hideMembrane()
        hideGhost()
        pressureEvents = {}
        currentPressure = 0
        lastTime = 0
    end)
end

local function stopDwellTimer()
    if dwellTimer then
        dwellTimer:stop()
        dwellTimer = nil
    end
end

local function resetDwell()
    stopDwellTimer()
    isDwelling = false
end

local function animateRipple(canvas, delay, duration, startScale, startOpacity, finalScale)
    hs.timer.doAfter(delay / 1000, function()
        if not canvas then return end

        local steps = 30
        local stepTime = duration / 1000 / steps
        local currentStep = 0

        canvas:show()

        local timer
        timer = hs.timer.doEvery(stepTime, function()
            currentStep = currentStep + 1
            local progress = currentStep / steps

            if progress >= 1 or not canvas then
                if timer then timer:stop() end
                if canvas then
                    canvas:hide()
                    canvas:delete()
                end
                return
            end

            local scaleProgress = 1 - (1 - progress) ^ 2
            local scale = startScale + (finalScale - startScale) * scaleProgress

            local opacityProgress = progress ^ 2
            local opacity = startOpacity * (1 - opacityProgress)

            local size = 60 * scale
            local f = canvas:frame()
            local centerX = f.x + f.w / 2
            local centerY = f.y + f.h / 2

            canvas:frame({
                x = centerX - size / 2,
                y = centerY - size / 2,
                w = size,
                h = size
            })
            canvas[1].radius = size / 2 - 2
            canvas[1].center = { x = size / 2, y = size / 2 }
            canvas[1].strokeColor.alpha = opacity
            canvas[2].radius = size / 2 - 6
            canvas[2].center = { x = size / 2, y = size / 2 }
            canvas[2].fillColor.alpha = opacity * 0.3
        end)
    end)
end

local function createRipple(x, y)
    local size = 10
    local canvas = hs.canvas.new({ x = x - size / 2, y = y - size / 2, w = size, h = size })
    canvas:level(hs.canvas.windowLevels.overlay)
    canvas:behavior("canJoinAllSpaces")
    canvas[1] = {
        type = "circle",
        center = { x = size / 2, y = size / 2 },
        radius = size / 2 - 2,
        action = "stroke",
        strokeColor = { white = 1, alpha = 0.8 },
        strokeWidth = 2
    }
    canvas[2] = {
        type = "circle",
        center = { x = size / 2, y = size / 2 },
        radius = size / 2 - 6,
        action = "fill",
        fillColor = { white = 1, alpha = 0.3 }
    }
    return canvas
end

local function playRipples(x, y)
    local r1 = createRipple(x, y)
    local r2 = createRipple(x, y)
    local r3 = createRipple(x, y)

    animateRipple(r1, 0, 500, 0.5, 0.9, 4.0)
    animateRipple(r2, 50, 600, 0.25, 0.6, 3.0)
    animateRipple(r3, 150, 600, 0.0, 0.3, 2.0)
end

local function getDistanceAcross(edge, dx, dy)
    if edge == "left" then
        return math.max(0, -dx)
    elseif edge == "right" then
        return math.max(0, dx)
    elseif edge == "top" then
        return math.max(0, -dy)
    elseif edge == "bottom" then
        return math.max(0, dy)
    end
    return 0
end

local function getDistanceAlong(edge, dx, dy)
    if edge == "left" or edge == "right" then
        return math.abs(dy)
    else
        return math.abs(dx)
    end
end

-- Get wrap destination based on WRAP_MODE
local function getWrapPosition(edge, x, y, currentScreen)
    local currentFrame = currentScreen:fullFrame()

    if WRAP_MODE == "current" then
        -- Wrap within current screen
        if edge == "left" then
            return currentFrame.x + currentFrame.w - WRAP_OFFSET, y
        elseif edge == "right" then
            return currentFrame.x + WRAP_OFFSET, y
        elseif edge == "top" then
            return x, currentFrame.y + currentFrame.h - WRAP_OFFSET
        elseif edge == "bottom" then
            return x, currentFrame.y + WRAP_OFFSET
        end
    else
        -- Wrap across all screens - find the screen on the opposite side
        local screens = hs.screen.allScreens()
        local targetScreen = nil

        if edge == "left" then
            -- Find rightmost screen
            local maxX = -math.huge
            for _, s in ipairs(screens) do
                local f = s:fullFrame()
                if f.x + f.w > maxX then
                    maxX = f.x + f.w
                    targetScreen = s
                end
            end
            if targetScreen then
                local tf = targetScreen:fullFrame()
                return tf.x + tf.w - WRAP_OFFSET, y
            end
        elseif edge == "right" then
            -- Find leftmost screen
            local minX = math.huge
            for _, s in ipairs(screens) do
                local f = s:fullFrame()
                if f.x < minX then
                    minX = f.x
                    targetScreen = s
                end
            end
            if targetScreen then
                local tf = targetScreen:fullFrame()
                return tf.x + WRAP_OFFSET, y
            end
        elseif edge == "top" then
            -- Find bottommost screen
            local maxY = -math.huge
            for _, s in ipairs(screens) do
                local f = s:fullFrame()
                if f.y + f.h > maxY then
                    maxY = f.y + f.h
                    targetScreen = s
                end
            end
            if targetScreen then
                local tf = targetScreen:fullFrame()
                return x, tf.y + tf.h - WRAP_OFFSET
            end
        elseif edge == "bottom" then
            -- Find topmost screen
            local minY = math.huge
            for _, s in ipairs(screens) do
                local f = s:fullFrame()
                if f.y < minY then
                    minY = f.y
                    targetScreen = s
                end
            end
            if targetScreen then
                local tf = targetScreen:fullFrame()
                return x, tf.y + WRAP_OFFSET
            end
        end

        -- Fallback to current screen
        return getWrapPosition(edge, x, y, currentScreen)
    end

    return x, y
end

local function getOppositeEdgePoint(edge, x, y, currentScreen)
    local wrapX, wrapY = getWrapPosition(edge, x, y, currentScreen)
    local targetScreen = hs.screen.find({ x = wrapX, y = wrapY }) or currentScreen
    local tf = targetScreen:fullFrame()

    if edge == "left" then
        return tf.x + tf.w, y
    elseif edge == "right" then
        return tf.x, y
    elseif edge == "top" then
        return x, tf.y + tf.h
    elseif edge == "bottom" then
        return x, tf.y
    end
    return x, y
end

local function reset()
    pressureEvents = {}
    currentPressure = 0
    lastTime = 0
end

local function trimOldEvents(now)
    local threshold = now - PRESSURE_TIMEOUT
    local i = 1

    while i <= #pressureEvents do
        if pressureEvents[i].time >= threshold then
            break
        end
        currentPressure = currentPressure - pressureEvents[i].distance
        i = i + 1
    end

    if i > 1 then
        local newEvents = {}
        for j = i, #pressureEvents do
            table.insert(newEvents, pressureEvents[j])
        end
        pressureEvents = newEvents
    end

    currentPressure = math.max(0, currentPressure)
end

local function trigger(edge, x, y, screen)
    isTriggered = true
    local wrapX, wrapY = getWrapPosition(edge, x, y, screen)
    hideMembrane()
    hideGhost()

    hs.mouse.setAbsolutePosition({ x = wrapX, y = wrapY })

    -- Play ripples at entry edge
    local entryX, entryY = getOppositeEdgePoint(edge, x, y, screen)
    playRipples(entryX, entryY)

    -- Sound
    local pop = hs.sound.getByFile("/System/Library/Sounds/Pop.aiff")
    if pop then
        pop:volume(0.3)
        pop:play()
    end
    reset()
end

local function isDragging()
    return hs.eventtap.checkMouseButtons().left
end

local function isShiftHeld()
    return hs.eventtap.checkKeyboardModifiers().shift
end

mouseTunnelHandler = hs.eventtap.new({ hs.eventtap.event.types.mouseMoved }, function(e)
    -- Shift bypass - disable wrapping while shift is held
    if isShiftHeld() then
        hideMembrane()
        hideGhost()
        reset()
        resetDwell()
        return false
    end

    local pos = e:location()
    local screen = hs.mouse.getCurrentScreen()
    if not screen then return false end
    local frame = screen:fullFrame()

    if inCorner(pos.x, pos.y, frame) or isDragging() then
        currentEdge = nil
        reset()
        resetDwell()
        isTriggered = false
        hideMembrane()
        hideGhost()
        return false
    end

    -- Check if we left the buffer zone entirely - reset dwell
    if not inBufferZone(pos.x, pos.y, frame) then
        resetDwell()
        if currentEdge then
            currentEdge = nil
            isTriggered = false
            reset()
            hideMembrane()
            hideGhost()
        end
        return false
    end

    local edge = getEdgeAt(pos.x, pos.y, frame)

    -- In buffer zone but not at edge - might be dwelling
    if not edge then
        if currentEdge then
            currentEdge = nil
            isTriggered = false
            reset()
            hideMembrane()
            hideGhost()
        end
        -- Start dwell timer if not already dwelling
        if not isDwelling and not dwellTimer then
            startDwellTimer()
        end
        return false
    end

    -- Check if this edge is enabled
    if not ENABLED_EDGES[edge] then
        return false
    end

    -- At edge
    currentEdge = edge

    -- If dwelling, ignore pressure until user leaves buffer zone
    if isDwelling then
        return false
    end

    -- If already triggered, wait until pointer leaves
    if isTriggered then
        return false
    end

    local dx = e:getProperty(hs.eventtap.event.properties.mouseEventDeltaX)
    local dy = e:getProperty(hs.eventtap.event.properties.mouseEventDeltaY)

    local distanceAcross = getDistanceAcross(edge, dx, dy)
    local distanceAlong = getDistanceAlong(edge, dx, dy)

    -- Single strong push triggers immediately
    if distanceAcross >= PRESSURE_THRESHOLD then
        trigger(edge, pos.x, pos.y, screen)
        return true
    end

    -- Reject if sliding more than pushing
    if distanceAlong > distanceAcross then
        return false
    end

    -- Accumulate pressure
    local now = hs.timer.absoluteTime() / 1000000
    lastTime = now
    trimOldEvents(now)

    local distance = math.min(MAX_PRESSURE_PER_EVENT, distanceAcross)
    if distance > 0 then
        table.insert(pressureEvents, { time = now, distance = distance })
        currentPressure = currentPressure + distance
        stopDwellTimer()
    else
        if not dwellTimer and not isDwelling then
            startDwellTimer()
        end
    end

    -- Update visual
    local progress = math.min(1, currentPressure / PRESSURE_THRESHOLD)
    if progress > 0.05 then
        updateMembrane(edge, pos.x, pos.y, frame, progress)
        showGhostBulge(edge, pos.x, pos.y, screen, progress)
    else
        hideMembrane()
        hideGhost()
    end

    -- Check threshold
    if currentPressure >= PRESSURE_THRESHOLD then
        trigger(edge, pos.x, pos.y, screen)
        return true
    end

    return false
end):start()

mouseTunnelScreenWatcher = hs.screen.watcher.new(function()
    mouseTunnelHandler:stop()
    mouseTunnelHandler:start()
    hideMembrane()
    hideGhost()
    reset()
    resetDwell()
    isTriggered = false
end):start()

hs.shutdownCallback = (function()
    local existingCallback = hs.shutdownCallback
    return function()
        if existingCallback then existingCallback() end
        if mouseTunnelHandler then mouseTunnelHandler:stop() end
        if mouseTunnelScreenWatcher then mouseTunnelScreenWatcher:stop() end
        if membraneCanvas then
            membraneCanvas:delete()
            membraneCanvas = nil
        end
        if ghostCanvas then
            ghostCanvas:delete()
            ghostCanvas = nil
        end
        if dwellTimer then
            dwellTimer:stop()
            dwellTimer = nil
        end
    end
end)()
