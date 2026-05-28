-- Window controls: nearby-click forwarding for close / minimize / zoom / pin.
-- Refreshes target rects on focus events. One shared overlay + two global
-- event taps handle hover visual (cone+box, action-tinted) and click redirect.
-- Geometry (distSq / buildPolygon) ported from BubbleCursor.

local ax       = require("hs.axuielement")
local canvas   = require("hs.canvas")
local eventtap = require("hs.eventtap")
local fnutils  = require("hs.fnutils")
local mouse    = require("hs.mouse")
local timer    = require("hs.timer")
local window   = require("hs.window")

local M = {}

local cfg, callbacks

local function FM() return require("FrameMaster") end

-- ─── Tunables ────────────────────────────────────────────────

local MAX_HOVER_DISTANCE     = 28
local MAX_CLICK_DISTANCE     = MAX_HOVER_DISTANCE
local CONE_PADDING_MIN       = 0
local CONE_PADDING_MAX       = 8
local STROKE_WIDTH           = 1.5
local CORNER_RADIUS          = 10
local CANVAS_SLACK           = 4
-- Debounced full refresh during cursor activity. Catches AX rect drift that
-- doesn't fire focus events (e.g. Arc's autohiding sidebar).
local RECT_REFRESH_INTERVAL  = 0.5

local AX_ATTR_FOR_KIND = {
    close    = "AXCloseButton",
    zoom     = "AXZoomButton",
    minimize = "AXMinimizeButton",
}

local PIN_COLOR = { red = 0.3, green = 0.3, blue = 0.3, alpha = 0.6 }

local kindColors = {
    close    = { fill = { red = 0.85, green = 0.20, blue = 0.20, alpha = 0.18 },
                 stroke = { red = 0.95, green = 0.25, blue = 0.25, alpha = 0.85 } },
    zoom     = { fill = { red = 0.20, green = 0.70, blue = 0.30, alpha = 0.18 },
                 stroke = { red = 0.25, green = 0.80, blue = 0.35, alpha = 0.85 } },
    minimize = { fill = { red = 0.95, green = 0.65, blue = 0.15, alpha = 0.18 },
                 stroke = { red = 1.00, green = 0.72, blue = 0.20, alpha = 0.85 } },
    pin      = { fill = { red = 0.95, green = 0.65, blue = 0.15, alpha = 0.18 },
                 stroke = { red = 1.00, green = 0.72, blue = 0.20, alpha = 0.85 } },
}

-- ─── State ───────────────────────────────────────────────────

local currentTargets = {}
local sharedOverlay = nil
local overlayVisible = false
local pinVisualOverlay = nil
local mouseTap = nil
local clickTap = nil
local lastNearestTarget = nil
local lastRefreshFocusedWinId = nil
local lastRectRefresh = 0

local sqrt, max, huge = math.sqrt, math.max, math.huge

-- ─── Geometry ────────────────────────────────────────────────

local function distSq(cx, cy, r)
    local dx = max(r.x - cx, 0, cx - (r.x + r.w))
    local dy = max(r.y - cy, 0, cy - (r.y + r.h))
    return dx * dx + dy * dy
end

local function findNearest(cx, cy)
    local nearSq, nearest = huge, nil
    for _, t in ipairs(currentTargets) do
        local d = distSq(cx, cy, t.frame)
        if d < nearSq then nearest, nearSq = t, d end
    end
    return nearest, nearSq
end

local function buildPolygon(cx, cy, rect, padding)
    local p = padding
    local R = { x = rect.x - p, y = rect.y - p, w = rect.w + p * 2, h = rect.h + p * 2 }
    local C = {
        { x = R.x,       y = R.y },
        { x = R.x + R.w, y = R.y },
        { x = R.x + R.w, y = R.y + R.h },
        { x = R.x,       y = R.y + R.h },
    }
    if cx >= R.x and cx <= R.x + R.w and cy >= R.y and cy <= R.y + R.h then
        return C, nil
    end
    local isL = cx < R.x
    local isR = cx > R.x + R.w
    local isA = cy < R.y
    local isB = cy > R.y + R.h
    local P = { { x = cx, y = cy } }
    if     isA and isL then P[2]=C[2]; P[3]=C[3]; P[4]=C[4]
    elseif isA and isR then P[2]=C[1]; P[3]=C[4]; P[4]=C[3]
    elseif isB and isR then P[2]=C[2]; P[3]=C[1]; P[4]=C[4]
    elseif isB and isL then P[2]=C[1]; P[3]=C[2]; P[4]=C[3]
    elseif isA         then P[2]=C[1]; P[3]=C[4]; P[4]=C[3]; P[5]=C[2]
    elseif isB         then P[2]=C[4]; P[3]=C[1]; P[4]=C[2]; P[5]=C[3]
    elseif isL         then P[2]=C[1]; P[3]=C[2]; P[4]=C[3]; P[5]=C[4]
    else                    P[2]=C[2]; P[3]=C[1]; P[4]=C[4]; P[5]=C[3]
    end
    return P, 1
end

-- Rounds convex polygon corners with circular arcs approximated by cubic
-- beziers (CSS `polygon(round Rpx, ...)` semantics). The apex vertex stays
-- sharp. Per-corner radius is clamped to half the shorter adjacent edge,
-- except on the side touching the apex where the full edge is available.
-- Output coords are already offset by (ox, oy) for the canvas frame.
local function roundPolygonCorners(poly, radius, sharpIdx, ox, oy)
    local N = #poly
    local coords = {}
    local eps = 1e-6
    local sqrtf, acos, tan, pi, min = math.sqrt, math.acos, math.tan, math.pi, math.min

    for i = 1, N do
        local prevIdx = (i - 2) % N + 1
        local nextIdx = i % N + 1
        local V = poly[i]

        if i == sharpIdx or radius < 0.5 then
            coords[#coords + 1] = { x = V.x - ox, y = V.y - oy }
        else
            local prev, nxt = poly[prevIdx], poly[nextIdx]
            local vAx, vAy = prev.x - V.x, prev.y - V.y
            local vBx, vBy = nxt.x  - V.x, nxt.y  - V.y
            local lenA = sqrtf(vAx*vAx + vAy*vAy)
            local lenB = sqrtf(vBx*vBx + vBy*vBy)

            if lenA < eps or lenB < eps then
                coords[#coords + 1] = { x = V.x - ox, y = V.y - oy }
            else
                local uAx, uAy = vAx / lenA, vAy / lenA
                local uBx, uBy = vBx / lenB, vBy / lenB
                local dot = uAx * uBx + uAy * uBy
                if dot < -1 then dot = -1 elseif dot > 1 then dot = 1 end
                local theta = acos(dot)

                if theta < eps or theta > pi - eps then
                    coords[#coords + 1] = { x = V.x - ox, y = V.y - oy }
                else
                    local maxA = (prevIdx == sharpIdx) and lenA or lenA / 2
                    local maxB = (nextIdx == sharpIdx) and lenB or lenB / 2
                    local halfTheta = theta / 2
                    local t = min(radius / tan(halfTheta), maxA, maxB)
                    local rEff = t * tan(halfTheta)

                    local P1x, P1y = V.x + uAx * t, V.y + uAy * t
                    local P2x, P2y = V.x + uBx * t, V.y + uBy * t
                    local k = rEff * (4 / 3) * tan((pi - theta) / 4)
                    local CP1x, CP1y = P1x - uAx * k, P1y - uAy * k
                    local CP2x, CP2y = P2x - uBx * k, P2y - uBy * k

                    coords[#coords + 1] = { x = P1x - ox, y = P1y - oy }
                    coords[#coords + 1] = {
                        x = P2x - ox, y = P2y - oy,
                        c1x = CP1x - ox, c1y = CP1y - oy,
                        c2x = CP2x - ox, c2y = CP2y - oy,
                    }
                end
            end
        end
    end

    return coords
end

-- ─── AX rect resolution ──────────────────────────────────────

local function rectForButton(axWin, win, axAttr)
    if not axWin then return nil end
    local ok, result = pcall(function()
        local button = axWin:attributeValue(axAttr)
        if not button then return nil end
        local pos = button:attributeValue("AXPosition")
        local size = button:attributeValue("AXSize")
        if not (pos and size) then return nil end
        local winFrame = win and win:frame()
        if winFrame then
            local cx = pos.x + size.w / 2
            local cy = pos.y + size.h / 2
            if cx < winFrame.x or cx > winFrame.x + winFrame.w
                or cy < winFrame.y or cy > winFrame.y + winFrame.h then
                return nil
            end
        end
        return { x = pos.x, y = pos.y, w = size.w, h = size.h }
    end)
    return ok and result or nil
end

local function pinFrameForWin(win)
    if not win then return nil end
    local winFrame = win:frame()
    if not winFrame then return nil end

    local titlebarHeight = 28
    pcall(function()
        local axWin = ax.windowElement(win)
        if axWin then
            local closeButton = axWin:attributeValue("AXCloseButton")
            if closeButton then
                local pos = closeButton:attributeValue("AXPosition")
                if pos then titlebarHeight = (pos.y - winFrame.y + 7) * 2 end
            end
        end
    end)

    local buttonSize = 14
    local buttonMargin = 12
    return {
        x = winFrame.x + winFrame.w - buttonSize - buttonMargin,
        y = winFrame.y + (titlebarHeight - buttonSize) / 2,
        w = buttonSize,
        h = buttonSize,
    }
end

-- ─── Pin visual (we paint it — not a real button) ────────────

local function ensurePinVisual(frame)
    if not frame then
        if pinVisualOverlay then pinVisualOverlay:delete(); pinVisualOverlay = nil end
        return
    end
    if not pinVisualOverlay then
        pinVisualOverlay = canvas.new(frame)
        pinVisualOverlay:appendElements({
            type = "circle",
            action = "fill",
            center = { x = frame.w / 2, y = frame.h / 2 },
            radius = frame.w / 2 - 1,
            fillColor = PIN_COLOR,
        })
        pinVisualOverlay:level(canvas.windowLevels.floating)
        pinVisualOverlay:clickActivating(false)
        pinVisualOverlay:show()
    else
        pinVisualOverlay:frame(frame)
        pinVisualOverlay:elementAttribute(1, "center", { x = frame.w / 2, y = frame.h / 2 })
        pinVisualOverlay:elementAttribute(1, "radius", frame.w / 2 - 1)
    end
end

local function clearPinVisual()
    if pinVisualOverlay then pinVisualOverlay:delete(); pinVisualOverlay = nil end
end

-- ─── Shared cone+box overlay ─────────────────────────────────

local function ensureSharedOverlay()
    if sharedOverlay then return end
    sharedOverlay = canvas.new({ x = 0, y = 0, w = 1, h = 1 })
    sharedOverlay:appendElements({
        id = "cone",
        type = "segments",
        action = "strokeAndFill",
        closed = true,
        fillColor   = { alpha = 0 },
        strokeColor = { alpha = 0 },
        strokeWidth = STROKE_WIDTH,
        coordinates = { { x = 0, y = 0 } },
    })
    sharedOverlay:level(canvas.windowLevels.overlay)
    sharedOverlay:clickActivating(false)
end

local function hideOverlay()
    if overlayVisible then sharedOverlay:hide(); overlayVisible = false end
    if lastNearestTarget then FM().hideTooltip() end
    lastNearestTarget = nil
end

-- Pin has no dedicated tooltip — color signals state. Others share FM's
-- corner-keyed messages (matches their visual position on the titlebar).
local function showTooltipFor(target)
    local corner =
        target.kind == "close"    and "topLeft"
        or target.kind == "zoom"    and "topRight"
        or target.kind == "minimize" and "bottomRight"
        or nil
    if not corner then return end
    local fm = FM()
    if fm.messages and fm.messages[corner] then
        fm.showMessage(corner, fm.messages[corner](target.win))
    end
end

local function updateOverlay(cx, cy)
    if #currentTargets == 0 then hideOverlay(); return end
    local target, nearSq = findNearest(cx, cy)
    if not target or sqrt(nearSq) > MAX_HOVER_DISTANCE then
        hideOverlay()
        return
    end

    ensureSharedOverlay()
    local f = target.frame
    local margin = MAX_HOVER_DISTANCE + CANVAS_SLACK
    local cFrame = {
        x = f.x - margin, y = f.y - margin,
        w = f.w + margin * 2, h = f.h + margin * 2,
    }
    sharedOverlay:frame(cFrame)
    local ox, oy = cFrame.x, cFrame.y

    local colors = kindColors[target.kind] or kindColors.zoom
    local t = 1 - math.min(1, sqrt(nearSq) / MAX_HOVER_DISTANCE)
    local conePad = CONE_PADDING_MIN + (CONE_PADDING_MAX - CONE_PADDING_MIN) * t
    sharedOverlay["cone"].fillColor   = colors.fill
    sharedOverlay["cone"].strokeColor = colors.stroke
    local poly, apexIdx = buildPolygon(cx, cy, f, conePad)
    sharedOverlay["cone"].coordinates = roundPolygonCorners(poly, CORNER_RADIUS, apexIdx, ox, oy)

    if not overlayVisible then sharedOverlay:show(); overlayVisible = true end
    if target ~= lastNearestTarget then
        FM().hideTooltip()
        showTooltipFor(target)
        lastNearestTarget = target
    end
end

local function onMouseMoved()
    local now = timer.secondsSinceEpoch()
    if now - lastRectRefresh > RECT_REFRESH_INTERVAL then
        lastRectRefresh = now
        M.updateButtonOverlays()
    end
    local pos = mouse.absolutePosition()
    updateOverlay(pos.x, pos.y)
    return false
end

local function onLeftMouseDown()
    if #currentTargets == 0 then return false end
    local pos = mouse.absolutePosition()
    local target, nearSq = findNearest(pos.x, pos.y)
    if not target or sqrt(nearSq) > MAX_CLICK_DISTANCE then return false end

    -- Defend against stale rects (Arc sidebar autohide etc.). The pin's frame
    -- is window-derived and moves only when the window moves, so skip it here.
    local axAttr = AX_ATTR_FOR_KIND[target.kind]
    if axAttr then
        local axWin = ax.windowElement(target.win)
        local liveRect = rectForButton(axWin, target.win, axAttr)
        if not liveRect then
            -- Button is gone (sidebar collapsed). Refresh and let click pass.
            M.updateButtonOverlays()
            return false
        end
        target.frame = liveRect
        if sqrt(distSq(pos.x, pos.y, liveRect)) > MAX_CLICK_DISTANCE then return false end
    end

    -- Swallow within radius — including direct hits — so the WindowScape
    -- action runs instead of macOS's native traffic-light behavior.
    hideOverlay()
    local winId = target.winId
    if target.kind == "close" then
        local cw = window.get(winId)
        if cw then cw:close() end
    elseif target.kind == "zoom" then
        local cw = window.get(winId)
        if cw and callbacks.toggleFullscreen then callbacks.toggleFullscreen(cw, winId) end
    elseif target.kind == "minimize" then
        if callbacks.createSnapshot then callbacks.createSnapshot(target.win) end
    elseif target.kind == "pin" then
        if callbacks.toggleAppExclusion then callbacks.toggleAppExclusion(winId) end
        timer.doAfter(0.1, M.updateButtonOverlays)
    end
    return true
end

local function ensureTaps()
    if not mouseTap then
        mouseTap = eventtap.new({ eventtap.event.types.mouseMoved }, onMouseMoved)
        mouseTap:start()
    end
    if not clickTap then
        clickTap = eventtap.new({ eventtap.event.types.leftMouseDown }, onLeftMouseDown)
        clickTap:start()
    end
end

local function stopTaps()
    if mouseTap then mouseTap:stop(); mouseTap = nil end
    if clickTap then clickTap:stop(); clickTap = nil end
end

-- ─── Public refresh API ──────────────────────────────────────

function M.clearAllOverlays()
    currentTargets = {}
    clearPinVisual()
    hideOverlay()
end

function M.updateButtonOverlays()
    if callbacks.isFullscreenActive and callbacks.isFullscreenActive() then return end
    if callbacks.isSnapshotsCreating and callbacks.isSnapshotsCreating() then return end

    local currentSpace = callbacks.getCurrentSpace and callbacks.getCurrentSpace()
    if not currentSpace then return end

    local newTargets = {}
    local pinFrame = nil
    local focusedWin = window.focusedWindow()
    local focusedWinId = focusedWin and focusedWin:id()
    lastRefreshFocusedWinId = focusedWinId

    for _, win in ipairs(window.visibleWindows()) do
        local okSpaces = callbacks.windowSpaces and callbacks.windowSpaces(win)
        local app = callbacks.safeGetApplication and callbacks.safeGetApplication(win)
        local winId = win:id()
        if not winId then goto continue end
        if not okSpaces or not fnutils.contains(okSpaces, currentSpace) then goto continue end
        if win:isFullScreen() then goto continue end

        local isStandard = win:isStandard() and app
        local sz = win:size()
        local isCollapsed = sz and sz.h <= cfg.collapsedWindowHeight
        local included = app and callbacks.isAppIncluded and callbacks.isAppIncluded(app, win)
        if not included then goto continue end
        if isCollapsed then goto continue end
        if callbacks.isAXSlow and callbacks.isAXSlow(app) then goto continue end

        if cfg.showPinButton and isStandard and winId == focusedWinId then
            local pf = pinFrameForWin(win)
            if pf then
                pinFrame = pf
                newTargets[#newTargets + 1] = { kind = "pin", frame = pf, win = win, winId = winId }
            end
        end

        local closeRect, zoomRect, minimizeRect = callbacks.measureAX(app, function()
            local axWin = ax.windowElement(win)
            return rectForButton(axWin, win, "AXCloseButton"),
                   rectForButton(axWin, win, "AXZoomButton"),
                   rectForButton(axWin, win, "AXMinimizeButton")
        end)

        if closeRect    then newTargets[#newTargets + 1] = { kind = "close",    frame = closeRect,    win = win, winId = winId } end
        if zoomRect     then newTargets[#newTargets + 1] = { kind = "zoom",     frame = zoomRect,     win = win, winId = winId } end
        if minimizeRect then newTargets[#newTargets + 1] = { kind = "minimize", frame = minimizeRect, win = win, winId = winId } end

        ::continue::
    end

    currentTargets = newTargets
    ensurePinVisual(pinFrame)
    ensureTaps()

    if overlayVisible then
        local pos = mouse.absolutePosition()
        lastNearestTarget = nil
        updateOverlay(pos.x, pos.y)
    end
end

-- Simulated fullscreen: only zoom + minimize on the one visible window.
function M.setFullscreenButtons(win)
    if not win then return end
    local winId = win:id()
    if not winId then return end

    local newTargets = {}
    local axWin = ax.windowElement(win)
    if axWin then
        local zoomRect = rectForButton(axWin, win, "AXZoomButton")
        local minRect  = rectForButton(axWin, win, "AXMinimizeButton")
        if zoomRect then newTargets[#newTargets + 1] = { kind = "zoom",     frame = zoomRect, win = win, winId = winId } end
        if minRect  then newTargets[#newTargets + 1] = { kind = "minimize", frame = minRect,  win = win, winId = winId } end
    end
    currentTargets = newTargets
    clearPinVisual()
    ensureTaps()
end

function M.updateButtonOverlaysIfFocusChanged()
    local fw = window.focusedWindow()
    local fid = fw and fw:id()
    if fid == lastRefreshFocusedWinId then return end
    M.updateButtonOverlays()
end

-- AX rects aren't reliably available immediately after window events.
function M.updateButtonOverlaysWithRetry()
    timer.doAfter(0.1, M.updateButtonOverlays)
    timer.doAfter(0.5, M.updateButtonOverlays)
end

function M.cleanup()
    M.clearAllOverlays()
    stopTaps()
    if sharedOverlay then sharedOverlay:delete(); sharedOverlay = nil end
end

function M.init(config, cbs)
    cfg = config
    callbacks = cbs or {}
end

return M
