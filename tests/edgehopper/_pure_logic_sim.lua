-- Simulator for EdgeHopper's pure-logic helpers (edge detection, corner
-- exclusion, multi-monitor adjacency, wrap-position math, pressure decay).
-- Real mouse movement is covered by the integration scripts in this directory;
-- this file unit-tests the math without touching the live eventtap.
--
-- EdgeHopper installs its eventtap at module-load (`hs.eventtap.new(..., fn):start()`).
-- We stub `hs.eventtap.new` to capture the anonymous handler, then walk upvalues
-- to reach helpers like getEdgeAt, inCorner, hasAdjacentScreenAt, getWrapPosition,
-- trimOldEvents.

local LOG_PATH = "/tmp/edgehopper-sim.log"
local logF = io.open(LOG_PATH, "w")
local function logln(s) if logF then logF:write(s .. "\n") end end

local L = dofile(hs.configdir .. "/tests/_test_lib.lua")
local deepUpvals, assertEq = L.deepUpvals, L.assertEq

local saved = {
    eventtapNew         = hs.eventtap.new,
    screenWatcherNew    = hs.screen.watcher.new,
    canvasNew           = hs.canvas.new,
    screenAllScreens    = hs.screen.allScreens,
    shutdownCallback    = hs.shutdownCallback,
    -- The module overwrites _G.mouseTunnelHandler and _G.mouseTunnelScreenWatcher
    -- with globals (no `local`). Save them for restore.
    mouseTunnelHandler        = _G.mouseTunnelHandler,
    mouseTunnelScreenWatcher  = _G.mouseTunnelScreenWatcher,
}

local capturedHandler

local function fakeCanvas()
    local elements = {}
    return setmetatable({}, {
        __index = function(_, k)
            if type(k) == "number" then elements[k] = elements[k] or {}; return elements[k] end
            return function() end
        end,
        __newindex = function(_, k, v)
            if type(k) == "number" then elements[k] = v end
        end,
    })
end

local screensList -- mutable per scenario

local function installStubs()
    capturedHandler = nil
    screensList = {}

    hs.eventtap.new = function(_, callback)
        capturedHandler = callback
        return { start = function() return capturedHandler end, stop = function() end }
    end
    hs.screen.watcher.new = function(_) return { start = function() end, stop = function() end } end
    hs.canvas.new = function(_) return fakeCanvas() end
    hs.screen.allScreens = function() return screensList end
end

local function restoreLive()
    hs.eventtap.new                 = saved.eventtapNew
    hs.screen.watcher.new           = saved.screenWatcherNew
    hs.canvas.new                   = saved.canvasNew
    hs.screen.allScreens            = saved.screenAllScreens
    hs.shutdownCallback             = saved.shutdownCallback
    _G.mouseTunnelHandler           = saved.mouseTunnelHandler
    _G.mouseTunnelScreenWatcher     = saved.mouseTunnelScreenWatcher
end

local function freshModule()
    package.loaded["EdgeHopper"] = nil
    require("EdgeHopper")
    assert(type(capturedHandler) == "function", "eventtap callback not captured")
    return deepUpvals(capturedHandler)
end

local function mockScreen(x, y, w, h, name)
    return {
        fullFrame = function() return { x = x, y = y, w = w, h = h } end,
        frame     = function() return { x = x, y = y, w = w, h = h } end,
        getUUID   = function() return name or string.format("scr-%d-%d", x, y) end,
        name      = function() return name or "Screen" end,
    }
end

local results = {}
local function scenario(name, body)
    installStubs()
    local ok, err = pcall(body)
    if not ok then
        table.insert(results, { name = name, pass = false })
        logln(string.format("FAIL  %s", name))
        logln("     error: " .. tostring(err))
        return
    end
    table.insert(results, { name = name, pass = true })
    logln(string.format("PASS  %s", name))
end


-- ---------- Scenarios ----------

scenario("getEdgeAt detects each edge within threshold and returns nil away from edges", function()
    local U = freshModule()
    local frame = { x = 0, y = 0, w = 1920, h = 1080 }
    assertEq(U.getEdgeAt(2,    540, frame), "left",   "x=2 → left")
    assertEq(U.getEdgeAt(1918, 540, frame), "right",  "x=1918 → right")
    assertEq(U.getEdgeAt(960,  2,   frame), "top",    "y=2 → top")
    assertEq(U.getEdgeAt(960,  1078, frame), "bottom", "y=1078 → bottom")
    assertEq(U.getEdgeAt(960,  540, frame), nil,      "center → nil")
end)

scenario("inCorner flags corner zones, not edges or center", function()
    local U = freshModule()
    local frame = { x = 0, y = 0, w = 1920, h = 1080 }
    assert(U.inCorner(2,    2,    frame), "top-left within exclusion")
    assert(U.inCorner(1918, 1078, frame), "bottom-right within exclusion")
    assert(not U.inCorner(2,    540,  frame), "mid-left edge is not a corner")
    assert(not U.inCorner(960,  540,  frame), "center is not a corner")
end)

scenario("hasAdjacentScreenAt finds left-adjacent screen and rejects misaligned y", function()
    local U = freshModule()
    local primary   = mockScreen(0,    0, 1920, 1080, "primary")
    local leftRight = mockScreen(-1280, 0, 1280,  800, "left") -- mounted to the left of primary
    screensList = { primary, leftRight }
    local primaryFrame = primary.fullFrame()
    -- y=400 is inside leftRight's vertical span (0..800); should match.
    assertEq(U.hasAdjacentScreenAt("left", 0, 400, primaryFrame), true, "y=400 within left screen")
    -- y=900 is below leftRight's range (which ends at 800); should not match.
    assertEq(U.hasAdjacentScreenAt("left", 0, 900, primaryFrame), false, "y=900 outside left screen")
end)

scenario("getWrapPosition (current mode) wraps within the current screen", function()
    local U = freshModule()
    local primary = mockScreen(0, 0, 1920, 1080, "primary")
    local x, y
    x, y = U.getWrapPosition("left",  0,    500, primary)
    assertEq(x, 1920 - 25, "left wrap x = screen.w - WRAP_OFFSET")
    assertEq(y, 500,       "left wrap preserves y")
    x, y = U.getWrapPosition("right", 1919, 500, primary)
    assertEq(x, 25,        "right wrap x = WRAP_OFFSET")
    x, y = U.getWrapPosition("top",   600,  0,   primary)
    assertEq(y, 1080 - 25, "top wrap y = screen.h - WRAP_OFFSET")
    x, y = U.getWrapPosition("bottom", 600, 1079, primary)
    assertEq(y, 25,        "bottom wrap y = WRAP_OFFSET")
end)

scenario("trimOldEvents drops events older than PRESSURE_TIMEOUT and decrements currentPressure", function()
    local U = freshModule()
    assert(type(U.trimOldEvents) == "function", "trimOldEvents reachable")
    -- Upvalue accessors. trimOldEvents reassigns `pressureEvents` to a fresh
    -- table after dropping old entries, so we have to re-read after each call.
    local function getUv(fn, name)
        local i = 1
        while true do
            local n, v = debug.getupvalue(fn, i)
            if not n then return nil end
            if n == name then return v, i end
            i = i + 1
        end
    end
    local function setUv(fn, name, val)
        local _, idx = getUv(fn, name)
        if idx then debug.setupvalue(fn, idx, val); return true end
        return false
    end
    -- Seed: two old events (well past 1000ms PRESSURE_TIMEOUT), one fresh.
    local oldT, freshT = 100, 5000
    setUv(U.trimOldEvents, "pressureEvents", {
        { time = oldT,     distance = 10 },
        { time = oldT + 1, distance = 20 },
        { time = freshT,   distance = 15 },
    })
    setUv(U.trimOldEvents, "currentPressure", 45)
    -- Trim at now=5500ms → threshold 4500ms. 100 and 101 drop; 5000 kept.
    U.trimOldEvents(5500)
    local after = getUv(U.trimOldEvents, "pressureEvents")
    assertEq(#after, 1, "only the fresh event remains")
    assertEq(after[1].time, freshT, "fresh event is the one kept")
    assertEq(getUv(U.trimOldEvents, "currentPressure"), 15, "currentPressure decremented by 30 (10+20)")
end)

-- ---------- Cleanup ----------

restoreLive()
package.loaded["EdgeHopper"] = nil

local failed = 0
for _, r in ipairs(results) do if not r.pass then failed = failed + 1 end end
local passed = #results - failed
logln(string.format("\n%d/%d scenarios passed", passed, #results))
if logF then logF:close() end
return string.format("%d/%d", passed, #results)
