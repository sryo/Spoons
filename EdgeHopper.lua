-- EdgeHopper.lua: Wrap the mouse cursor when it moves off the edge of the screen

local edgeBuffer = 2          -- pixels from edge to trigger wrap
local ghostDistance = 40      -- pixels from edge to show ghost
local cornerExclusion = 10    -- skip corners (let FrameMaster handle them)
local dwellThreshold = 0.25   -- seconds of stillness to prevent wrap
local dwellMoveTolerance = 3  -- pixels of movement allowed while dwelling

local ghostCanvas = nil
local dwellTimer = nil
local isDwelling = false
local lastEdgePosition = nil

local function createGhost()
    local canvas = hs.canvas.new({ x = 0, y = 0, w = 24, h = 24 })
    canvas:level(hs.canvas.windowLevels.cursor)
    canvas[1] = {
        type = "circle",
        center = { x = 12, y = 12 },
        radius = 6,
        fillColor = { white = 1, alpha = 0.25 },
        strokeColor = { white = 1, alpha = 0.4 },
        strokeWidth = 1.5
    }
    canvas[2] = {
        type = "circle",
        center = { x = 12, y = 12 },
        radius = 10,
        action = "stroke",
        strokeColor = { white = 1, alpha = 0.15 },
        strokeWidth = 1
    }
    return canvas
end

local function inCorner(x, y, frame)
    local nearLeft = x <= frame.x + cornerExclusion
    local nearRight = x >= frame.x + frame.w - cornerExclusion
    local nearTop = y <= frame.y + cornerExclusion
    local nearBottom = y >= frame.y + frame.h - cornerExclusion
    return (nearLeft or nearRight) and (nearTop or nearBottom)
end

local function getEdgeInfo(x, y, frame, distance)
    -- Returns edge name and opposite position
    local offset = 5
    if x <= frame.x + distance then
        return "left", frame.x + frame.w - offset, y
    elseif x >= frame.x + frame.w - distance then
        return "right", frame.x + offset, y
    elseif y <= frame.y + distance then
        return "top", x, frame.y + frame.h - offset
    elseif y >= frame.y + frame.h - distance then
        return "bottom", x, frame.y + offset
    end
    return nil, x, y
end

local function hapticFeedback()
    local pop = hs.sound.getByName("Tink")
    if pop then
        pop:volume(0.15):play()
    end
end

local function hideGhost()
    if ghostCanvas then
        ghostCanvas:hide()
    end
end

local function showGhost(x, y, alpha)
    if not ghostCanvas then
        ghostCanvas = createGhost()
    end
    ghostCanvas:topLeft({ x = x - 12, y = y - 12 })
    ghostCanvas[1].fillColor.alpha = 0.25 * alpha
    ghostCanvas[1].strokeColor.alpha = 0.4 * alpha
    ghostCanvas[2].strokeColor.alpha = 0.15 * alpha
    ghostCanvas:show()
end

local function resetDwell()
    if dwellTimer then
        dwellTimer:stop()
        dwellTimer = nil
    end
    isDwelling = false
    lastEdgePosition = nil
end

local function isDragging()
    return hs.eventtap.checkMouseButtons().left
end

mouseTunnelHandler = hs.eventtap.new({ hs.eventtap.event.types.mouseMoved }, function(e)
    local pos = e:location()
    local screen = hs.mouse.getCurrentScreen()
    if not screen then return false end
    local frame = screen:fullFrame()

    -- Skip corners entirely (FrameMaster territory)
    if inCorner(pos.x, pos.y, frame) then
        hideGhost()
        resetDwell()
        return false
    end

    -- Skip while dragging
    if isDragging() then
        hideGhost()
        resetDwell()
        return false
    end

    local atEdge, wrapX, wrapY = getEdgeInfo(pos.x, pos.y, frame, edgeBuffer)
    local nearEdge, ghostX, ghostY = getEdgeInfo(pos.x, pos.y, frame, ghostDistance)

    if atEdge then
        -- Check for dwell (cursor staying still at edge)
        if lastEdgePosition then
            local dx = math.abs(pos.x - lastEdgePosition.x)
            local dy = math.abs(pos.y - lastEdgePosition.y)
            if dx <= dwellMoveTolerance and dy <= dwellMoveTolerance then
                -- Still dwelling, don't wrap
                if isDwelling then
                    hideGhost()
                    return false
                end
                -- Waiting for dwell timer
                return false
            else
                -- Moved enough, reset dwell and allow wrap
                resetDwell()
            end
        end

        -- Start dwell detection
        if not dwellTimer then
            lastEdgePosition = { x = pos.x, y = pos.y }
            dwellTimer = hs.timer.doAfter(dwellThreshold, function()
                isDwelling = true
                hideGhost()
            end)
        end

        -- Wrap if not dwelling
        if not isDwelling then
            resetDwell()
            hs.mouse.setAbsolutePosition({ x = wrapX, y = wrapY })
            hapticFeedback()
            hideGhost()
        end
        return false

    elseif nearEdge then
        -- Show ghost preview
        resetDwell()
        local proximity = 1 - (math.min(
            math.abs(pos.x - frame.x),
            math.abs(pos.x - (frame.x + frame.w)),
            math.abs(pos.y - frame.y),
            math.abs(pos.y - (frame.y + frame.h))
        ) - edgeBuffer) / (ghostDistance - edgeBuffer)
        proximity = math.max(0, math.min(1, proximity))
        showGhost(ghostX, ghostY, proximity)
        return false

    else
        -- Away from edges
        hideGhost()
        resetDwell()
        return false
    end
end):start()

mouseTunnelScreenWatcher = hs.screen.watcher.new(function()
    mouseTunnelHandler:stop()
    mouseTunnelHandler:start()
    hideGhost()
    resetDwell()
end):start()

-- Cleanup on reload
hs.shutdownCallback = (function()
    local existingCallback = hs.shutdownCallback
    return function()
        if existingCallback then existingCallback() end
        if mouseTunnelHandler then mouseTunnelHandler:stop() end
        if mouseTunnelScreenWatcher then mouseTunnelScreenWatcher:stop() end
        if ghostCanvas then ghostCanvas:delete() end
        if dwellTimer then dwellTimer:stop() end
    end
end)()
