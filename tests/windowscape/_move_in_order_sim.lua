-- Simulator for operations.moveWindowInOrder. Stubs hs.window.focusedWindow,
-- hs.mouse.absolutePosition, and hs.geometry.isPointInRect so the function
-- runs in isolation against fake window and screen objects. Verifies the
-- orientation-aware swap: landscape compares X centers, portrait compares Y.
--
-- Returns "N/M" to the shell driver and writes /tmp/wsg-mvio-sim.log.

local LOG_PATH = "/tmp/wsg-mvio-sim.log"
local logF = io.open(LOG_PATH, "w")
local function logln(s) if logF then logF:write(s .. "\n") end end

local hs_window   = require("hs.window")
local hs_mouse    = require("hs.mouse")
local hs_geometry = require("hs.geometry")

local realFocusedWindow = hs_window.focusedWindow
local realAbsPos        = hs_mouse.absolutePosition
local realPointInRect   = hs_geometry.isPointInRect

local fakeFocused = nil
hs_window.focusedWindow = function() return fakeFocused end
hs_mouse.absolutePosition = function(_) return { x = 0, y = 0 } end
hs_geometry.isPointInRect = function() return false end

local function makeScreen(id, frame)
    return {
        _id    = id,
        _frame = frame,
        id     = function(self) return self._id end,
        frame  = function(self) return self._frame end,
    }
end

local function makeWin(id, frame, scr)
    return {
        _id     = id,
        _frame  = frame,
        _screen = scr,
        id      = function(self) return self._id end,
        frame   = function(self) return self._frame end,
        size    = function(self) return { w = self._frame.w, h = self._frame.h } end,
        screen  = function(self) return self._screen end,
        focus   = function(self) return true end,
    }
end

local savedLive = package.loaded["WindowScape.operations"]
package.loaded["WindowScape.operations"] = nil
local operations = require("WindowScape.operations")

local function idsOf(list)
    local s = ""
    for i, w in ipairs(list) do
        s = s .. (i > 1 and "," or "") .. tostring(w:id())
    end
    return s
end

local results = {}

local function scenario(name, setup)
    local s = setup()
    local cfg = { collapsedWindowHeight = 12 }
    local order = s.order
    local capturedOrder = nil
    local callbacks = {
        getCurrentSpace   = function() return 1 end,
        getWindowOrder    = function() return order end,
        setWindowOrder    = function(_, newOrder) capturedOrder = newOrder; order = newOrder end,
        tileWindows       = function() end,
        drawOutline       = function() end,
        updateWindowOrder = function() end,
    }
    operations.init(cfg, callbacks)
    fakeFocused = s.focus

    operations.moveWindowInOrder(s.direction)

    local got  = idsOf(capturedOrder or order)
    local pass = (got == s.want)
    table.insert(results, { name = name, want = s.want, got = got, pass = pass })
    logln(string.format("%s  %s", pass and "PASS" or "FAIL", name))
    if not pass then
        logln("     want: [" .. s.want .. "]")
        logln("     got:  [" .. got .. "]")
    end
end

-- Landscape screen: 1920x1080. Three windows side-by-side, full height.
-- A at x=0, B at x=640, C at x=1280. Visual order left-to-right: A, B, C.
scenario("landscape forward from middle: A B C -> A C B", function()
    local scr = makeScreen(1, { x = 0, y = 0, w = 1920, h = 1080 })
    local a = makeWin("A", { x = 0,    y = 0, w = 640, h = 1080 }, scr)
    local b = makeWin("B", { x = 640,  y = 0, w = 640, h = 1080 }, scr)
    local c = makeWin("C", { x = 1280, y = 0, w = 640, h = 1080 }, scr)
    return { order = { a, b, c }, focus = b, direction = "forward", want = "A,C,B" }
end)

scenario("landscape backward from middle: A B C -> B A C", function()
    local scr = makeScreen(1, { x = 0, y = 0, w = 1920, h = 1080 })
    local a = makeWin("A", { x = 0,    y = 0, w = 640, h = 1080 }, scr)
    local b = makeWin("B", { x = 640,  y = 0, w = 640, h = 1080 }, scr)
    local c = makeWin("C", { x = 1280, y = 0, w = 640, h = 1080 }, scr)
    return { order = { a, b, c }, focus = b, direction = "backward", want = "B,A,C" }
end)

scenario("landscape forward at right edge clamps (no change)", function()
    local scr = makeScreen(1, { x = 0, y = 0, w = 1920, h = 1080 })
    local a = makeWin("A", { x = 0,    y = 0, w = 640, h = 1080 }, scr)
    local b = makeWin("B", { x = 640,  y = 0, w = 640, h = 1080 }, scr)
    local c = makeWin("C", { x = 1280, y = 0, w = 640, h = 1080 }, scr)
    return { order = { a, b, c }, focus = c, direction = "forward", want = "A,B,C" }
end)

scenario("landscape backward at left edge clamps (no change)", function()
    local scr = makeScreen(1, { x = 0, y = 0, w = 1920, h = 1080 })
    local a = makeWin("A", { x = 0,    y = 0, w = 640, h = 1080 }, scr)
    local b = makeWin("B", { x = 640,  y = 0, w = 640, h = 1080 }, scr)
    local c = makeWin("C", { x = 1280, y = 0, w = 640, h = 1080 }, scr)
    return { order = { a, b, c }, focus = a, direction = "backward", want = "A,B,C" }
end)

-- Portrait screen: 1080x1920. Three windows stacked top-to-bottom.
-- A at y=0, B at y=640, C at y=1280. Visual order top-to-bottom: A, B, C.
scenario("portrait forward from middle: A B C -> A C B", function()
    local scr = makeScreen(1, { x = 0, y = 0, w = 1080, h = 1920 })
    local a = makeWin("A", { x = 0, y = 0,    w = 1080, h = 640 }, scr)
    local b = makeWin("B", { x = 0, y = 640,  w = 1080, h = 640 }, scr)
    local c = makeWin("C", { x = 0, y = 1280, w = 1080, h = 640 }, scr)
    return { order = { a, b, c }, focus = b, direction = "forward", want = "A,C,B" }
end)

scenario("portrait backward from middle: A B C -> B A C", function()
    local scr = makeScreen(1, { x = 0, y = 0, w = 1080, h = 1920 })
    local a = makeWin("A", { x = 0, y = 0,    w = 1080, h = 640 }, scr)
    local b = makeWin("B", { x = 0, y = 640,  w = 1080, h = 640 }, scr)
    local c = makeWin("C", { x = 0, y = 1280, w = 1080, h = 640 }, scr)
    return { order = { a, b, c }, focus = b, direction = "backward", want = "B,A,C" }
end)

scenario("portrait forward at bottom edge clamps (no change)", function()
    local scr = makeScreen(1, { x = 0, y = 0, w = 1080, h = 1920 })
    local a = makeWin("A", { x = 0, y = 0,    w = 1080, h = 640 }, scr)
    local b = makeWin("B", { x = 0, y = 640,  w = 1080, h = 640 }, scr)
    local c = makeWin("C", { x = 0, y = 1280, w = 1080, h = 640 }, scr)
    return { order = { a, b, c }, focus = c, direction = "forward", want = "A,B,C" }
end)

scenario("portrait backward at top edge clamps (no change)", function()
    local scr = makeScreen(1, { x = 0, y = 0, w = 1080, h = 1920 })
    local a = makeWin("A", { x = 0, y = 0,    w = 1080, h = 640 }, scr)
    local b = makeWin("B", { x = 0, y = 640,  w = 1080, h = 640 }, scr)
    local c = makeWin("C", { x = 0, y = 1280, w = 1080, h = 640 }, scr)
    return { order = { a, b, c }, focus = a, direction = "backward", want = "A,B,C" }
end)

-- Cached list out of sync with visual order: cached is [C, B, A] but visually
-- A is at top, C in the middle, B at the bottom. forward from C (visually
-- middle) swaps it past B (visually bottom). The function normalizes the
-- cached list to match the new visual stack: [A, B, C].
scenario("portrait recovers when list drifts from visual order", function()
    local scr = makeScreen(1, { x = 0, y = 0, w = 1080, h = 1920 })
    local a = makeWin("A", { x = 0, y = 0,    w = 1080, h = 640 }, scr) -- visually top
    local c = makeWin("C", { x = 0, y = 640,  w = 1080, h = 640 }, scr) -- visually middle
    local b = makeWin("B", { x = 0, y = 1280, w = 1080, h = 640 }, scr) -- visually bottom
    return { order = { c, b, a }, focus = c, direction = "forward", want = "A,B,C" }
end)

-- Mixed screens: only the focused screen's windows participate. A window on
-- another screen keeps its slot in the order.
scenario("multi-screen swap only touches focused screen", function()
    local s1 = makeScreen(1, { x = 0,    y = 0, w = 1920, h = 1080 })
    local s2 = makeScreen(2, { x = 1920, y = 0, w = 1920, h = 1080 })
    local a = makeWin("A", { x = 0,    y = 0, w = 960, h = 1080 }, s1)
    local b = makeWin("B", { x = 960,  y = 0, w = 960, h = 1080 }, s1)
    local x = makeWin("X", { x = 1920, y = 0, w = 1920, h = 1080 }, s2)
    return { order = { a, x, b }, focus = a, direction = "forward", want = "B,X,A" }
end)

-- Collapsed window keeps its slot in the order.
scenario("collapsed window keeps its slot during swap", function()
    local scr = makeScreen(1, { x = 0, y = 0, w = 1920, h = 1080 })
    local a = makeWin("A", { x = 0,    y = 0,    w = 640, h = 1080 }, scr)
    local b = makeWin("B", { x = 640,  y = 0,    w = 640, h = 1080 }, scr)
    local k = makeWin("K", { x = 0,    y = 1068, w = 1920, h = 12   }, scr) -- collapsed
    local c = makeWin("C", { x = 1280, y = 0,    w = 640, h = 1080 }, scr)
    return { order = { a, b, k, c }, focus = b, direction = "forward", want = "A,C,K,B" }
end)

-- Cleanup. Restore real hs functions so any later code in this session
-- still works correctly.
hs_window.focusedWindow   = realFocusedWindow
hs_mouse.absolutePosition = realAbsPos
hs_geometry.isPointInRect = realPointInRect
package.loaded["WindowScape.operations"] = savedLive

local failed = 0
for _, r in ipairs(results) do if not r.pass then failed = failed + 1 end end
local passed = #results - failed
logln(string.format("\n%d/%d scenarios passed", passed, #results))
if logF then logF:close() end
return string.format("%d/%d", passed, #results)
