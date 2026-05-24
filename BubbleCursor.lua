-- BubbleCursor.lua
-- Dynamic area cursor (Grossman & Balakrishnan, CHI 2005)
-- Highlights the nearest interactive element with a cone polygon that
-- projects from the cursor to the target. While active, left-clicks
-- select the nearest target via AXPress. Toggle with ctrl+cmd+B.

local ax       = require("hs.axuielement")
local canvas   = require("hs.canvas")
local eventtap = require("hs.eventtap")
local timer    = require("hs.timer")
local mouse    = require("hs.mouse")

local cfg = {
    fillColor       = { red = 0.4, green = 0.5, blue = 0.9, alpha = 0.15 },
    strokeColor     = { red = 0.4, green = 0.5, blue = 0.9, alpha = 0.4 },
    strokeWidth     = 1.5,
    padding         = 4,
    mods            = { "ctrl", "cmd" },
    key             = "B",
    searchDepth     = 15,
    refreshInterval = 3,
    maxClickDistance = 150,
}

local INTERACTIVE_ROLES = {
    "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton",
    "AXComboBox", "AXSlider", "AXTextField",
    "AXLink", "AXMenuItem", "AXMenuButton", "AXDisclosureTriangle",
    "AXIncrementor", "AXCell",
}

local roleSet = {}
for _, role in ipairs(INTERACTIVE_ROLES) do roleSet[role] = true end

-- State
local active = false
local cachedTargets = {}
local overlay = nil
local overlayOrigin = nil
local overlayVisible = false
local mouseTap = nil
local clickTap = nil
local refreshTimer = nil
local appWatcher = nil
local currentTarget = nil
local trackedWinId = nil
local lastFocusCheck = 0

local sqrt, abs, max, min, huge = math.sqrt, math.abs, math.max, math.min, math.huge

-- ─── Geometry ────────────────────────────────────────────────

-- Squared distance from point to nearest edge of rect (0 if inside)
local function distSq(cx, cy, r)
    local dx = max(r.x - cx, 0, cx - (r.x + r.w))
    local dy = max(r.y - cy, 0, cy - (r.y + r.h))
    return dx * dx + dy * dy
end

-- Distance from point to farthest corner of rect (containment distance)
local function containDist(cx, cy, r)
    local dx = max(abs(cx - r.x), abs(cx - (r.x + r.w)))
    local dy = max(abs(cy - r.y), abs(cy - (r.y + r.h)))
    return sqrt(dx * dx + dy * dy)
end

-- Find nearest target; compute bubble radius per the paper:
-- radius = min(containmentDist(closest), intersectDist(secondClosest))
local function findNearest(cx, cy)
    local nearSq, secSq = huge, huge
    local nearest = nil

    for _, t in ipairs(cachedTargets) do
        local d = distSq(cx, cy, t.frame)
        if d < nearSq then
            secSq = nearSq
            nearest, nearSq = t, d
        elseif d < secSq then
            secSq = d
        end
    end

    if not nearest then return nil end
    local radius = min(containDist(cx, cy, nearest.frame), secSq < huge and sqrt(secSq) or huge)
    return nearest, radius
end

-- Build the cone polygon from cursor to target.
-- Cursor apex + all 4 corners. The corners walk from the nearest face
-- around the BACK of the rectangle (following the perimeter), creating
-- a filled cone that fully wraps the target.
--
-- Corners: C[1]=TL  C[2]=TR  C[3]=BR  C[4]=BL
-- Perimeter CW: C1→C2→C3→C4
--
--          C[1]────C[2]
--           │        │
--          C[4]────C[3]

local function buildPolygon(cx, cy, rect)
    local p = cfg.padding
    local R = { x = rect.x - p, y = rect.y - p, w = rect.w + p * 2, h = rect.h + p * 2 }

    local C = {
        { x = R.x,       y = R.y },
        { x = R.x + R.w, y = R.y },
        { x = R.x + R.w, y = R.y + R.h },
        { x = R.x,       y = R.y + R.h },
    }

    -- Inside padded rect: just the rectangle
    if cx >= R.x and cx <= R.x + R.w and cy >= R.y and cy <= R.y + R.h then
        return C
    end

    local isL = cx < R.x
    local isR = cx > R.x + R.w
    local isA = cy < R.y
    local isB = cy > R.y + R.h

    -- Start at one end of the nearest face, walk CW or CCW through the
    -- back of the rect to the other end. Each case verified by hand.
    local P = { { x = cx, y = cy } }
    if     isA and isL then P[2]=C[2]; P[3]=C[3]; P[4]=C[4]; P[5]=C[1]  -- back: right→bottom→left
    elseif isA and isR then P[2]=C[1]; P[3]=C[4]; P[4]=C[3]; P[5]=C[2]  -- back: left→bottom→right
    elseif isB and isR then P[2]=C[2]; P[3]=C[1]; P[4]=C[4]; P[5]=C[3]  -- back: top→left→bottom
    elseif isB and isL then P[2]=C[1]; P[3]=C[2]; P[4]=C[3]; P[5]=C[4]  -- back: top→right→bottom
    elseif isA         then P[2]=C[1]; P[3]=C[4]; P[4]=C[3]; P[5]=C[2]  -- back: left→bottom→right
    elseif isB         then P[2]=C[4]; P[3]=C[1]; P[4]=C[2]; P[5]=C[3]  -- back: left→top→right
    elseif isL         then P[2]=C[1]; P[3]=C[2]; P[4]=C[3]; P[5]=C[4]  -- back: top→right→bottom
    else                    P[2]=C[2]; P[3]=C[1]; P[4]=C[4]; P[5]=C[3]  -- back: top→left→bottom
    end

    return P
end

-- ─── Target Enumeration ─────────────────────────────────────
-- Async search for interactive AX elements in the focused app.
-- Cached between frames; refreshed on app switch and periodic timer.

local function enumerateTargets()
    local win = hs.window.focusedWindow()
    if not win then cachedTargets = {}; return end

    local app = win:application()
    if not app then cachedTargets = {}; return end

    local axApp = ax.applicationElement(app)
    if not axApp then cachedTargets = {}; return end

    local wf = win:frame()

    axApp:elementSearch(function(_, results)
        if not active then return end
        local targets = {}
        for i = 1, #results do
            local el = results[i]
            local frame = el.AXFrame
            if frame and el.AXEnabled ~= false
                and frame.w > 2 and frame.h > 2
                and frame.x + frame.w > wf.x and frame.y + frame.h > wf.y
                and frame.x < wf.x + wf.w and frame.y < wf.y + wf.h
            then
                targets[#targets + 1] = { frame = frame, element = el }
            end
        end
        cachedTargets = targets
    end, function(element)
        local ok, role = pcall(function() return element.AXRole end)
        return ok and role and roleSet[role] or false
    end, { depth = cfg.searchDepth })
end

-- ─── Overlay ─────────────────────────────────────────────────
-- Fullscreen canvas with a single filled polygon (segments element).
-- Coordinates are updated per-frame; the canvas frame stays fixed.

local function createOverlay()
    local mnX, mnY, mxX, mxY = huge, huge, -huge, -huge
    for _, s in ipairs(hs.screen.allScreens()) do
        local f = s:fullFrame()
        mnX = min(mnX, f.x); mnY = min(mnY, f.y)
        mxX = max(mxX, f.x + f.w); mxY = max(mxY, f.y + f.h)
    end
    overlayOrigin = { x = mnX, y = mnY }

    overlay = canvas.new({ x = mnX, y = mnY, w = mxX - mnX, h = mxY - mnY })
    overlay:appendElements({
        id = "poly",
        type = "segments",
        action = "strokeAndFill",
        closed = true,
        fillColor = cfg.fillColor,
        strokeColor = cfg.strokeColor,
        strokeWidth = cfg.strokeWidth,
        coordinates = { { x = 0, y = 0 } },
    })
    overlay:level(canvas.windowLevels.overlay)
    overlay:clickActivating(false)
end

local function updateOverlay(cx, cy)
    if not overlay then return end

    local target = findNearest(cx, cy)
    if not target then
        if overlayVisible then overlay:hide(); overlayVisible = false end
        currentTarget = nil
        return
    end

    currentTarget = target
    local poly = buildPolygon(cx, cy, target.frame)

    local ox, oy = overlayOrigin.x, overlayOrigin.y
    local coords = {}
    for i, pt in ipairs(poly) do
        coords[i] = { x = pt.x - ox, y = pt.y - oy }
    end

    overlay["poly"].coordinates = coords
    if not overlayVisible then overlay:show(); overlayVisible = true end
end

local function deleteOverlay()
    if overlay then overlay:delete(); overlay = nil end
    overlayOrigin = nil
    overlayVisible = false
    currentTarget = nil
end

-- ─── Event Handling ──────────────────────────────────────────

local function onMouseMoved()
    local now = timer.secondsSinceEpoch()
    if now - lastFocusCheck > 0.5 then
        lastFocusCheck = now
        local win = hs.window.focusedWindow()
        local winId = win and win:id()
        if winId ~= trackedWinId then
            trackedWinId = winId
            enumerateTargets()
        end
    end

    local pos = mouse.absolutePosition()
    local win = hs.window.focusedWindow()
    if win then
        local wf = win:frame()
        if pos.x < wf.x or pos.x > wf.x + wf.w
            or pos.y < wf.y or pos.y > wf.y + wf.h then
            if overlayVisible then overlay:hide(); overlayVisible = false end
            currentTarget = nil
            return false
        end
    end
    updateOverlay(pos.x, pos.y)
    return false
end

local function onMouseClick()
    if not currentTarget or not currentTarget.element then return false end

    local pos = mouse.absolutePosition()
    local f = currentTarget.frame

    -- If cursor is directly on the target, let the normal click through
    if pos.x >= f.x and pos.x <= f.x + f.w
        and pos.y >= f.y and pos.y <= f.y + f.h then
        return false
    end

    -- If cursor is too far from the target, let the normal click through
    local d = sqrt(distSq(pos.x, pos.y, f))
    if d > cfg.maxClickDistance then return false end

    -- Cursor is outside the target but nearby — redirect click via AXPress
    pcall(function() currentTarget.element:performAction("AXPress") end)
    return true
end

-- ─── Lifecycle ───────────────────────────────────────────────

local function start()
    if active then return end
    active = true
    trackedWinId = nil
    lastFocusCheck = 0

    createOverlay()
    enumerateTargets()

    mouseTap = eventtap.new({ eventtap.event.types.mouseMoved }, onMouseMoved):start()
    clickTap = eventtap.new({ eventtap.event.types.leftMouseDown }, onMouseClick):start()
    refreshTimer = timer.doEvery(cfg.refreshInterval, enumerateTargets)
    appWatcher = hs.application.watcher.new(function(_, event)
        if event == hs.application.watcher.activated then
            trackedWinId = nil
            enumerateTargets()
        end
    end):start()
end

local function stop()
    active = false
    if mouseTap then mouseTap:stop(); mouseTap = nil end
    if clickTap then clickTap:stop(); clickTap = nil end
    if refreshTimer then refreshTimer:stop(); refreshTimer = nil end
    if appWatcher then appWatcher:stop(); appWatcher = nil end
    deleteOverlay()
    cachedTargets = {}
    currentTarget = nil
    trackedWinId = nil
end

-- ─── Hotkey ──────────────────────────────────────────────────

hs.hotkey.bind(cfg.mods, cfg.key, function()
    if active then
        stop()
        hs.alert.show("Bubble Cursor OFF")
    else
        start()
        hs.alert.show("Bubble Cursor ON")
    end
end)

return { start = start, stop = stop }
