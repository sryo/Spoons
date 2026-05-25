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
    mods             = { "ctrl", "cmd" },
    key              = "B",
    searchDepth      = 16,
    maxClickDistance = 150,   -- redirect clicks within this radius of target
    -- Visual gating: overlay fully opaque inside fadeStartDistance, fades to 0 by maxVisualDistance.
    -- Keep maxVisualDistance ≤ maxClickDistance so you see a target before you can click-redirect it.
    maxVisualDistance = 120,
    fadeStartDistance = 70,
    -- Cone (the polygon from cursor toward target)
    conePadding      = 4,
    coneStrokeWidth  = 1.5,
    -- Focus rectangle (rounded outline around the target itself)
    boxPadding       = 6,
    boxCornerRadius  = 6,
    boxStrokeWidth   = 1.5,
    -- Hide overlay after the cursor sits still this long (ms). Click
    -- redirect stays armed; next motion re-shows the overlay.
    steadyTimeoutMs  = 1500,
    -- Debug hotkey: prints AX role chain under the cursor to the console.
    debugMods        = { "ctrl", "cmd" },
    debugKey         = "D",
}

local colors = {
    coneFill   = { red = 0.40, green = 0.55, blue = 0.95, alpha = 0.10 },
    coneStroke = { red = 0.45, green = 0.60, blue = 0.98, alpha = 0.35 },
    boxFill    = { red = 0.40, green = 0.55, blue = 0.95, alpha = 0.06 },
    boxStroke  = { red = 0.45, green = 0.60, blue = 0.98, alpha = 0.85 },
}

local function applyAlpha(c, f)
    return { red = c.red, green = c.green, blue = c.blue, alpha = c.alpha * f }
end

local function applyFadeToOverlay(overlay, fade)
    overlay["focusBox"].strokeColor = applyAlpha(colors.boxStroke,  fade)
    overlay["focusBox"].fillColor   = applyAlpha(colors.boxFill,    fade)
    overlay["cone"].strokeColor     = applyAlpha(colors.coneStroke, fade)
    overlay["cone"].fillColor       = applyAlpha(colors.coneFill,   fade)
end

local INTERACTIVE_ROLES = {
    "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton",
    "AXComboBox", "AXSlider", "AXTextField",
    "AXLink", "AXMenuItem", "AXMenuButton", "AXDisclosureTriangle",
    "AXIncrementor", "AXCell",
    "AXTab", "AXSegmentedControl", "AXToolbarItem", "AXMenuBarItem",
    "AXSwitch", "AXImage", "AXRow", "AXOutlineRow",
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
local scrollTap = nil
local appWatcher = nil
local steadyTimer = nil
local axObserver = nil
local enumerateDebounceTimer = nil
-- Forward declarations: defined after enumerateTargets but called from inside it.
local setupObserver, teardownObserver, debouncedEnumerate
-- currentTarget: nearest element each frame, used by onMouseClick for redirect.
-- lastTarget: last target painted to canvas, used only to dedupe canvas writes.
local currentTarget = nil
local trackedWinId = nil
local lastFocusCheck = 0
local cachedFocusedWin = nil
local cachedFocusedFrame = nil
local cachedMenuRoot = nil
-- Cancellable handle for the in-flight elementSearch; without cancel+restart
-- on each enumerate, concurrent searches accumulate on big AX trees.
local currentSearch = nil
-- Per-event dedupe state. Trackpad sub-pixel drift fires mouseMoved at
-- 60-120 Hz with a stationary hand; without this we'd cross the Cocoa
-- bridge 6 times per frame for no visible change.
local lastMoveX, lastMoveY = -1, -1
local lastTarget = nil
local lastFadeBin = -1
local lastUpdateX, lastUpdateY = -1, -1

-- Tag set on synthetic clicks we post so our own clickTap can recognize
-- and pass them through instead of recursing.
local CLICK_TAG = 0xBC1
local PROP_USERDATA = eventtap.event.properties.eventSourceUserData

local sqrt, abs, max, min, huge = math.sqrt, math.abs, math.max, math.min, math.huge

-- ─── Geometry ────────────────────────────────────────────────

-- Squared distance from point to nearest edge of rect (0 if inside)
local function distSq(cx, cy, r)
    local dx = max(r.x - cx, 0, cx - (r.x + r.w))
    local dy = max(r.y - cy, 0, cy - (r.y + r.h))
    return dx * dx + dy * dy
end

local function findNearest(cx, cy)
    local nearSq = huge
    local nearest = nil
    for _, t in ipairs(cachedTargets) do
        local d = distSq(cx, cy, t.frame)
        if d < nearSq then
            nearest, nearSq = t, d
        end
    end
    if not nearest then return nil end
    return nearest, nearSq
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
    local p = cfg.conePadding
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
-- Async search for interactive AX elements in the focused window — or, if
-- a menu is open, in that menu's AX subtree (menus aren't children of any
-- window on macOS; they're separate top-level entities owned by the app).

-- Returns the deepest currently-open AXMenu in `app`, or nil. Covers:
--   - menubar dropdowns (axApp:AXMenuBar's AXSelectedChildren chain)
--   - contextual / popup menus (top-level AXChildren of the app)
local function findOpenMenu(app)
    if not app then return nil end
    local axApp = ax.applicationElement(app)
    if not axApp then return nil end

    -- Walk a menu chain down to its deepest open submenu.
    local function deepest(menu)
        if not menu then return nil end
        local children = menu:attributeValue("AXChildren") or {}
        for _, item in ipairs(children) do
            local subs = item:attributeValue("AXChildren") or {}
            for _, s in ipairs(subs) do
                if s:attributeValue("AXRole") == "AXMenu" then
                    return deepest(s) or s
                end
            end
        end
        return menu
    end

    local menubar = axApp:attributeValue("AXMenuBar")
    if menubar then
        local selected = menubar:attributeValue("AXSelectedChildren") or {}
        for _, item in ipairs(selected) do
            local children = item:attributeValue("AXChildren") or {}
            for _, c in ipairs(children) do
                if c:attributeValue("AXRole") == "AXMenu" then
                    return deepest(c) or c
                end
            end
        end
    end

    local topLevel = axApp:attributeValue("AXChildren") or {}
    for _, c in ipairs(topLevel) do
        if c:attributeValue("AXRole") == "AXMenu" then
            return deepest(c) or c
        end
    end

    return nil
end

local function enumerateTargets()
    if currentSearch then
        pcall(function() currentSearch:cancel() end)
        currentSearch = nil
    end

    local win = cachedFocusedWin or hs.window.focusedWindow()
    if not win then cachedTargets = {}; return end

    local app = win:application()
    if not app then cachedTargets = {}; return end

    local axApp = ax.applicationElement(app)
    if not axApp then cachedTargets = {}; return end

    -- Root the search at the open menu's subtree when one's open, otherwise
    -- at the focused window. Cuts node count vs. searching the whole app.
    local axRoot = cachedMenuRoot or axApp:attributeValue("AXFocusedWindow")
    if not axRoot then cachedTargets = {}; return end

    local rootFrame = axRoot:attributeValue("AXFrame") or win:frame()
    local wf = rootFrame

    currentSearch = axRoot:elementSearch(function(_, results)
        currentSearch = nil
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
        setupObserver(app, axRoot)
    end, function(element)
        local ok, role = pcall(function() return element.AXRole end)
        return ok and role and roleSet[role] or false
    end, { depth = cfg.searchDepth })
end

-- ─── AX Observer ─────────────────────────────────────────────
-- Subscribe to AX notifications on the focused window (or open menu) so
-- the cache refreshes when content actually moves (Finder scroll, folder
-- navigation, selection change, window resize). Event-driven, no polling.

debouncedEnumerate = function()
    if enumerateDebounceTimer then enumerateDebounceTimer:stop() end
    enumerateDebounceTimer = timer.doAfter(0.1, function()
        enumerateDebounceTimer = nil
        if active then enumerateTargets() end
    end)
end

teardownObserver = function()
    if axObserver then
        pcall(function() axObserver:stop() end)
        axObserver = nil
    end
end

setupObserver = function(app, axRoot)
    teardownObserver()
    if not app or not axRoot then return end
    local pid = app:pid()
    if not pid then return end
    local ok, obs = pcall(function() return ax.observer.new(pid) end)
    if not ok or not obs then return end
    pcall(function() obs:callback(function() debouncedEnumerate() end) end)

    -- App-level events: focused element / focused window changes (catches
    -- keyboard navigation in Finder etc).
    local axApp = ax.applicationElement(app)
    if axApp then
        for _, notif in ipairs({
            "AXFocusedUIElementChanged",
            "AXFocusedWindowChanged",
            "AXMainWindowChanged",
        }) do
            pcall(function() obs:addWatcher(axApp, notif) end)
        end
    end

    -- Root (focused window / open menu) layout / selection / resize events.
    for _, notif in ipairs({
        "AXLayoutChanged",
        "AXSelectedChildrenChanged",
        "AXSelectedRowsChanged",
        "AXResized",
        "AXMoved",
        "AXValueChanged",
    }) do
        pcall(function() obs:addWatcher(axRoot, notif) end)
    end
    local ok2 = pcall(function() obs:start() end)
    if ok2 then axObserver = obs end
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
        id = "focusBox",
        type = "rectangle",
        action = "strokeAndFill",
        roundedRectRadii = { xRadius = cfg.boxCornerRadius, yRadius = cfg.boxCornerRadius },
        fillColor   = colors.boxFill,
        strokeColor = colors.boxStroke,
        strokeWidth = cfg.boxStrokeWidth,
        frame = { x = 0, y = 0, w = 0, h = 0 },
    })
    overlay:appendElements({
        id = "cone",
        type = "segments",
        action = "strokeAndFill",
        closed = true,
        fillColor   = colors.coneFill,
        strokeColor = colors.coneStroke,
        strokeWidth = cfg.coneStrokeWidth,
        coordinates = { { x = 0, y = 0 } },
    })
    overlay:level(canvas.windowLevels.overlay)
    overlay:clickActivating(false)
end

local function computeFade(nearSq)
    local d = sqrt(nearSq)
    if d <= cfg.fadeStartDistance then return 1 end
    if d >= cfg.maxVisualDistance then return 0 end
    local t = (cfg.maxVisualDistance - d) / (cfg.maxVisualDistance - cfg.fadeStartDistance)
    return t * t
end

local function updateOverlay(cx, cy)
    if not overlay then return end

    local target, nearSq = findNearest(cx, cy)
    if not target then
        if overlayVisible then overlay:hide(); overlayVisible = false end
        currentTarget = nil
        lastTarget = nil
        return
    end

    -- Track nearest target regardless of visual fade; onMouseClick's
    -- maxClickDistance is the authoritative gate for click redirect.
    currentTarget = target

    local fade = computeFade(nearSq)
    if fade <= 0 then
        if overlayVisible then overlay:hide(); overlayVisible = false end
        lastTarget = nil
        return
    end

    -- Dedupe canvas updates: bail when nothing visible would change.
    local fadeBin  = math.floor(fade * 20)
    local sameTgt  = (target == lastTarget)
    local sameFade = (fadeBin == lastFadeBin)
    local samePos  = abs(cx - lastUpdateX) < 2 and abs(cy - lastUpdateY) < 2
    if sameTgt and sameFade and samePos and overlayVisible then return end

    local ox, oy = overlayOrigin.x, overlayOrigin.y
    local f = target.frame
    local bp = cfg.boxPadding

    -- Focus box frame only depends on the target rect.
    if not sameTgt then
        overlay["focusBox"].frame = {
            x = f.x - bp - ox,
            y = f.y - bp - oy,
            w = f.w + bp * 2,
            h = f.h + bp * 2,
        }
    end
    if not sameTgt or not sameFade then
        applyFadeToOverlay(overlay, fade)
    end

    -- Cone coords always update (we only reach here when cursor moved enough).
    local poly = buildPolygon(cx, cy, f)
    local coords = {}
    for i, pt in ipairs(poly) do
        coords[i] = { x = pt.x - ox, y = pt.y - oy }
    end
    overlay["cone"].coordinates = coords

    if not overlayVisible then overlay:show(); overlayVisible = true end
    lastTarget, lastFadeBin = target, fadeBin
    lastUpdateX, lastUpdateY = cx, cy
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
        cachedFocusedWin   = win
        cachedFocusedFrame = win and win:frame() or nil
        local app = win and win:application()
        local newMenu = findOpenMenu(app)
        local menuChanged = newMenu ~= cachedMenuRoot
        cachedMenuRoot = newMenu
        local winId = win and win:id()
        if winId ~= trackedWinId or menuChanged then
            trackedWinId = winId
            lastTarget = nil
            enumerateTargets()
        end
    end

    local pos = mouse.absolutePosition()
    if abs(pos.x - lastMoveX) < 1 and abs(pos.y - lastMoveY) < 1 then
        return false
    end
    lastMoveX, lastMoveY = pos.x, pos.y

    if steadyTimer then steadyTimer:stop() end
    steadyTimer = timer.doAfter(cfg.steadyTimeoutMs / 1000, function()
        if overlayVisible then overlay:hide(); overlayVisible = false end
        lastTarget = nil
    end)

    local wf = cachedFocusedFrame
    if wf and (pos.x < wf.x or pos.x > wf.x + wf.w
            or pos.y < wf.y or pos.y > wf.y + wf.h) then
        if overlayVisible then overlay:hide(); overlayVisible = false end
        currentTarget = nil
        lastTarget = nil
        return false
    end
    updateOverlay(pos.x, pos.y)
    return false
end

local function postSyntheticClick(center)
    local et = eventtap.event.types
    local d  = eventtap.event.newMouseEvent(et.leftMouseDown, center)
    local u  = eventtap.event.newMouseEvent(et.leftMouseUp,   center)
    d:setProperty(PROP_USERDATA, CLICK_TAG)
    u:setProperty(PROP_USERDATA, CLICK_TAG)
    d:post(); u:post()
end

-- Redirect a click to `target`. Returns true if we acted (and the original
-- click should be swallowed), false if we couldn't (let it pass through).
local function tryPress(target)
    if not target or not target.element then return false end
    -- Liveness probe: a stale AX handle returns nil or errors here.
    local ok, actions = pcall(function() return target.element:actionNames() end)
    if not ok or not actions then return false end
    for _, a in ipairs(actions) do
        if a == "AXPress" then
            pcall(function() target.element:performAction("AXPress") end)
            return true
        end
    end
    -- No AXPress action — fall back to a synthetic click at the target's
    -- center. Tagged so our own clickTap won't recurse on it.
    local f = target.frame
    postSyntheticClick({ x = f.x + f.w / 2, y = f.y + f.h / 2 })
    return true
end

local function onMouseClick(event)
    -- Ignore synthetic events we posted ourselves.
    if event:getProperty(PROP_USERDATA) == CLICK_TAG then return false end

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

    return tryPress(currentTarget)
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
    -- Scroll re-enumerates because AXLayoutChanged often fires on inner
    -- scroll-area descendants we don't have subscriptions on.
    scrollTap = eventtap.new({ eventtap.event.types.scrollWheel }, function()
        debouncedEnumerate()
        return false
    end):start()
    appWatcher = hs.application.watcher.new(function(_, event)
        if event == hs.application.watcher.activated then
            cachedFocusedWin, cachedFocusedFrame = nil, nil
            cachedMenuRoot = nil
            lastFocusCheck = 0
            trackedWinId = nil
            enumerateTargets()
        end
    end):start()
end

local function stop()
    active = false
    if mouseTap then mouseTap:stop(); mouseTap = nil end
    if clickTap then clickTap:stop(); clickTap = nil end
    if scrollTap then scrollTap:stop(); scrollTap = nil end
    if appWatcher then appWatcher:stop(); appWatcher = nil end
    if steadyTimer then steadyTimer:stop(); steadyTimer = nil end
    if currentSearch then pcall(function() currentSearch:cancel() end); currentSearch = nil end
    if enumerateDebounceTimer then enumerateDebounceTimer:stop(); enumerateDebounceTimer = nil end
    teardownObserver()
    deleteOverlay()
    cachedTargets = {}
    currentTarget = nil
    trackedWinId = nil
    cachedFocusedWin, cachedFocusedFrame = nil, nil
    cachedMenuRoot = nil
    lastMoveX, lastMoveY = -1, -1
    lastTarget = nil
    lastFadeBin = -1
    lastUpdateX, lastUpdateY = -1, -1
end

-- ─── Debug ───────────────────────────────────────────────────
-- Press the debug hotkey (or call BubbleCursor.inspect()) to print the AX
-- role chain under the cursor + whether the immediate element matches our
-- INTERACTIVE_ROLES list. Use it to find what role a clickable thing has
-- when it isn't being recognized.

local function inspectUnderCursor()
    local pos = mouse.absolutePosition()
    local el  = ax.systemWideElement():elementAtPosition(pos)
    if not el then hs.alert.show("BubbleCursor: nothing under cursor"); return end

    print(string.format("\n── BubbleCursor inspect @ %d,%d ──", pos.x, pos.y))
    local node = el
    local depth = 0
    while node and depth < 6 do
        local role    = node:attributeValue("AXRole") or "?"
        local subrole = node:attributeValue("AXSubrole") or ""
        local frame   = node:attributeValue("AXFrame")
        local ok, actions = pcall(function() return node:actionNames() end)
        local actStr = (ok and actions) and table.concat(actions, ",") or "-"
        local fStr   = frame and string.format("%dx%d@%d,%d", frame.w, frame.h, frame.x, frame.y) or "no-frame"
        print(string.format("  [%d] %s%s  %s  actions={%s}",
            depth, role,
            subrole ~= "" and (" (" .. subrole .. ")") or "",
            fStr, actStr))
        node = node:attributeValue("AXParent")
        depth = depth + 1
    end

    local elRole = el:attributeValue("AXRole") or "?"
    local marker = roleSet[elRole] and "✓ in INTERACTIVE_ROLES" or "✗ NOT in INTERACTIVE_ROLES"
    hs.alert.show("Inspect: " .. elRole .. "  " .. marker)
end

-- ─── Hotkeys ─────────────────────────────────────────────────

hs.hotkey.bind(cfg.mods, cfg.key, function()
    if active then
        stop()
        hs.alert.show("Bubble Cursor OFF")
    else
        start()
        hs.alert.show("Bubble Cursor ON")
    end
end)

hs.hotkey.bind(cfg.debugMods, cfg.debugKey, inspectUnderCursor)

start()

return { start = start, stop = stop, inspect = inspectUnderCursor }
