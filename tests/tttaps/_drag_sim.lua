-- Simulator for the TTTaps drag recognizer. Feeds synthetic gesture events
-- and checks which onDrag handlers fire (and that onPlusOne still works
-- alongside drag). Driven by tests/tttaps/drag.sh; returns "N/M"
-- (passed/total) to the caller and writes a detailed per-scenario log to
-- /tmp/tttaps-drag-sim.log.
--
-- Coordinate convention: normalizedPosition is 0..1 on each axis with y=0
-- at the bottom of the trackpad (Cocoa). dy > 0 therefore means "up".

local LOG_PATH = "/tmp/tttaps-drag-sim.log"
local logF = io.open(LOG_PATH, "w")
local function logln(s) if logF then logF:write(s .. "\n") end end

local hs_timer = require("hs.timer")
local hs_eventtap = require("hs.eventtap")

local fakeTime = 0
local realClock = hs_timer.secondsSinceEpoch
hs_timer.secondsSinceEpoch = function() return fakeTime end
local function tick(ms) fakeTime = fakeTime + ms / 1000 end

local savedLive = package.loaded["TTTaps"]

local calls = {}
local function freshHandler()
    package.loaded["TTTaps"] = nil
    local g = require("TTTaps")
    g.onDrag(3, function(direction)
        table.insert(calls, "drag(3," .. direction .. ")")
    end)
    g.onDrag(4, function(direction)
        table.insert(calls, "drag(4," .. direction .. ")")
    end)
    g.onPlusOne(4, function(side)
        table.insert(calls, "plusone(4," .. side .. ")")
    end)
    assert(type(g._onGesture) == "function", "TTTaps._onGesture missing")
    return g._onGesture
end

local function freshStepHandler()
    package.loaded["TTTaps"] = nil
    local g = require("TTTaps")
    g.onDragStep(3, function(direction)
        table.insert(calls, "step(3," .. direction .. ")")
    end)
    g.onDragStep(4, function(direction)
        table.insert(calls, "step(4," .. direction .. ")")
    end)
    assert(type(g._onGesture) == "function", "TTTaps._onGesture missing")
    return g._onGesture
end

-- Mirrors the init.lua wiring: 4-finger horizontal scrubs (reorder), 4-finger
-- vertical is one-shot (maximize / minimize). Handler filters mirror init.lua.
local function freshMixedHandler()
    package.loaded["TTTaps"] = nil
    local g = require("TTTaps")
    g.onDragStep(3, function(direction)
        if direction == "left" or direction == "right" then
            table.insert(calls, "step(3," .. direction .. ")")
        end
    end)
    g.onDrag(4, function(direction)
        if direction == "up" or direction == "down" then
            table.insert(calls, "drag(4," .. direction .. ")")
        end
    end)
    g.onDragStep(4, function(direction)
        if direction == "left" or direction == "right" then
            table.insert(calls, "step(4," .. direction .. ")")
        end
    end)
    assert(type(g._onGesture) == "function", "TTTaps._onGesture missing")
    return g._onGesture
end

local function mockEvent(touches)
    return {
        getType         = function(_) return hs_eventtap.event.types.gesture end,
        getTouches      = function(_) return touches end,
        getTouchDetails = function(_) return {} end,
    }
end

local function touch(id, x, y, phase)
    return {
        identity           = id,
        touching           = phase ~= "ended" and phase ~= "cancelled",
        type               = "indirect",
        normalizedPosition = { x = x, y = y or 0.5 },
        phase              = phase,
    }
end

local currentHandle = nil
local function feed(touches) currentHandle(mockEvent(touches)) end

local results = {}
local function scenario(name, expectedCalls, body, makeHandler)
    fakeTime = 0
    calls = {}
    currentHandle = (makeHandler or freshHandler)()
    local ok, err = pcall(body)
    if not ok then
        table.insert(results, { name = name, want = "", got = "<error: " .. tostring(err) .. ">", pass = false })
        logln(string.format("FAIL  %s", name))
        logln("     error: " .. tostring(err))
        return
    end
    local got = table.concat(calls, ", ")
    local want = table.concat(expectedCalls, ", ")
    local pass = (got == want)
    table.insert(results, { name = name, want = want, got = got, pass = pass })
    logln(string.format("%s  %s", pass and "PASS" or "FAIL", name))
    if not pass then
        logln("     want: [" .. want .. "]")
        logln("     got:  [" .. got .. "]")
    end
end

-- ---------- Scenarios ----------

scenario("A: 3-finger drag right fires drag(3,right)",
    { "drag(3,right)" }, function()
    feed({ touch("a", 0.20, 0.5), touch("b", 0.30, 0.5), touch("c", 0.40, 0.5) })
    tick(30)
    feed({ touch("a", 0.23, 0.5), touch("b", 0.33, 0.5), touch("c", 0.43, 0.5) })
    tick(30)
    feed({ touch("a", 0.40, 0.5), touch("b", 0.50, 0.5), touch("c", 0.60, 0.5) })
    tick(20)
    feed({})
end)

scenario("B: 3-finger drag left fires drag(3,left)",
    { "drag(3,left)" }, function()
    feed({ touch("a", 0.60, 0.5), touch("b", 0.70, 0.5), touch("c", 0.80, 0.5) })
    tick(30)
    feed({ touch("a", 0.57, 0.5), touch("b", 0.67, 0.5), touch("c", 0.77, 0.5) })
    tick(30)
    feed({ touch("a", 0.40, 0.5), touch("b", 0.50, 0.5), touch("c", 0.60, 0.5) })
    tick(20)
    feed({})
end)

scenario("C: 3-finger drag up fires drag(3,up)",
    { "drag(3,up)" }, function()
    feed({ touch("a", 0.30, 0.30), touch("b", 0.40, 0.30), touch("c", 0.50, 0.30) })
    tick(30)
    feed({ touch("a", 0.30, 0.33), touch("b", 0.40, 0.33), touch("c", 0.50, 0.33) })
    tick(30)
    feed({ touch("a", 0.30, 0.50), touch("b", 0.40, 0.50), touch("c", 0.50, 0.50) })
    tick(20)
    feed({})
end)

scenario("D: 3-finger drag down fires drag(3,down)",
    { "drag(3,down)" }, function()
    feed({ touch("a", 0.30, 0.70), touch("b", 0.40, 0.70), touch("c", 0.50, 0.70) })
    tick(30)
    feed({ touch("a", 0.30, 0.67), touch("b", 0.40, 0.67), touch("c", 0.50, 0.67) })
    tick(30)
    feed({ touch("a", 0.30, 0.50), touch("b", 0.40, 0.50), touch("c", 0.50, 0.50) })
    tick(20)
    feed({})
end)

scenario("E: 4-finger drag right fires drag(4,right)",
    { "drag(4,right)" }, function()
    feed({ touch("a", 0.15, 0.5), touch("b", 0.25, 0.5),
           touch("c", 0.35, 0.5), touch("d", 0.45, 0.5) })
    tick(30)
    feed({ touch("a", 0.18, 0.5), touch("b", 0.28, 0.5),
           touch("c", 0.38, 0.5), touch("d", 0.48, 0.5) })
    tick(30)
    feed({ touch("a", 0.35, 0.5), touch("b", 0.45, 0.5),
           touch("c", 0.55, 0.5), touch("d", 0.65, 0.5) })
    tick(20)
    feed({})
end)

scenario("F: 4-finger drag left fires drag(4,left)",
    { "drag(4,left)" }, function()
    feed({ touch("a", 0.55, 0.5), touch("b", 0.65, 0.5),
           touch("c", 0.75, 0.5), touch("d", 0.85, 0.5) })
    tick(30)
    feed({ touch("a", 0.52, 0.5), touch("b", 0.62, 0.5),
           touch("c", 0.72, 0.5), touch("d", 0.82, 0.5) })
    tick(30)
    feed({ touch("a", 0.35, 0.5), touch("b", 0.45, 0.5),
           touch("c", 0.55, 0.5), touch("d", 0.65, 0.5) })
    tick(20)
    feed({})
end)

scenario("G: 4-finger drag up fires drag(4,up)",
    { "drag(4,up)" }, function()
    feed({ touch("a", 0.30, 0.30), touch("b", 0.40, 0.30),
           touch("c", 0.50, 0.30), touch("d", 0.60, 0.30) })
    tick(30)
    feed({ touch("a", 0.30, 0.33), touch("b", 0.40, 0.33),
           touch("c", 0.50, 0.33), touch("d", 0.60, 0.33) })
    tick(30)
    feed({ touch("a", 0.30, 0.50), touch("b", 0.40, 0.50),
           touch("c", 0.50, 0.50), touch("d", 0.60, 0.50) })
    tick(20)
    feed({})
end)

scenario("H: 4-finger drag down fires drag(4,down)",
    { "drag(4,down)" }, function()
    feed({ touch("a", 0.30, 0.70), touch("b", 0.40, 0.70),
           touch("c", 0.50, 0.70), touch("d", 0.60, 0.70) })
    tick(30)
    feed({ touch("a", 0.30, 0.67), touch("b", 0.40, 0.67),
           touch("c", 0.50, 0.67), touch("d", 0.60, 0.67) })
    tick(30)
    feed({ touch("a", 0.30, 0.50), touch("b", 0.40, 0.50),
           touch("c", 0.50, 0.50), touch("d", 0.60, 0.50) })
    tick(20)
    feed({})
end)

scenario("I: 4-finger drag below commit threshold does NOT fire",
    {}, function()
    -- Centroid travels only ~0.08, below the 0.15 commit threshold.
    feed({ touch("a", 0.20, 0.5), touch("b", 0.30, 0.5),
           touch("c", 0.40, 0.5), touch("d", 0.50, 0.5) })
    tick(30)
    feed({ touch("a", 0.24, 0.5), touch("b", 0.34, 0.5),
           touch("c", 0.44, 0.5), touch("d", 0.54, 0.5) })
    tick(30)
    feed({ touch("a", 0.28, 0.5), touch("b", 0.38, 0.5),
           touch("c", 0.48, 0.5), touch("d", 0.58, 0.5) })
    tick(20)
    feed({})
end)

scenario("J: sustained motion past commit fires only once",
    { "drag(4,right)" }, function()
    feed({ touch("a", 0.10, 0.5), touch("b", 0.20, 0.5),
           touch("c", 0.30, 0.5), touch("d", 0.40, 0.5) })
    tick(30)
    feed({ touch("a", 0.13, 0.5), touch("b", 0.23, 0.5),
           touch("c", 0.33, 0.5), touch("d", 0.43, 0.5) })
    tick(30)
    feed({ touch("a", 0.30, 0.5), touch("b", 0.40, 0.5),
           touch("c", 0.50, 0.5), touch("d", 0.60, 0.5) })
    tick(30)
    feed({ touch("a", 0.40, 0.5), touch("b", 0.50, 0.5),
           touch("c", 0.60, 0.5), touch("d", 0.70, 0.5) })
    tick(30)
    feed({ touch("a", 0.50, 0.5), touch("b", 0.60, 0.5),
           touch("c", 0.70, 0.5), touch("d", 0.80, 0.5) })
    tick(20)
    feed({})
end)

scenario("K: mixed-sign motion (pinch-like) does NOT fire",
    {}, function()
    -- Outer fingers move out, inner fingers stationary. Pos/neg X disagree.
    feed({ touch("a", 0.20, 0.5), touch("b", 0.40, 0.5),
           touch("c", 0.60, 0.5), touch("d", 0.80, 0.5) })
    tick(30)
    feed({ touch("a", 0.15, 0.5), touch("b", 0.38, 0.5),
           touch("c", 0.62, 0.5), touch("d", 0.85, 0.5) })
    tick(30)
    feed({ touch("a", 0.05, 0.5), touch("b", 0.35, 0.5),
           touch("c", 0.65, 0.5), touch("d", 0.95, 0.5) })
    tick(20)
    feed({})
end)

scenario("L: stationary 4-cluster + +1 tap still fires plusone(4)",
    { "plusone(4,left)" }, function()
    feed({ touch("a", 0.40, 0.5), touch("b", 0.50, 0.5),
           touch("c", 0.60, 0.5), touch("d", 0.70, 0.5) })
    tick(200)
    feed({ touch("a", 0.40, 0.5), touch("b", 0.50, 0.5),
           touch("c", 0.60, 0.5), touch("d", 0.70, 0.5),
           touch("e", 0.05, 0.5) })
    tick(40)
    feed({ touch("a", 0.40, 0.5), touch("b", 0.50, 0.5),
           touch("c", 0.60, 0.5), touch("d", 0.70, 0.5) })
    feed({})
end)

scenario("M: short horizontal then large vertical flips to vertical",
    { "drag(4,up)" }, function()
    feed({ touch("a", 0.30, 0.30), touch("b", 0.40, 0.30),
           touch("c", 0.50, 0.30), touch("d", 0.60, 0.30) })
    tick(30)
    -- Small rightward arm.
    feed({ touch("a", 0.33, 0.30), touch("b", 0.43, 0.30),
           touch("c", 0.53, 0.30), touch("d", 0.63, 0.30) })
    tick(30)
    -- Big upward; orthogonal-axis travel exceeds flip threshold (0.02 * 2.0).
    feed({ touch("a", 0.34, 0.40), touch("b", 0.44, 0.40),
           touch("c", 0.54, 0.40), touch("d", 0.64, 0.40) })
    tick(30)
    -- Vertical travel now past commit (0.15) and dominant.
    feed({ touch("a", 0.34, 0.50), touch("b", 0.44, 0.50),
           touch("c", 0.54, 0.50), touch("d", 0.64, 0.50) })
    tick(20)
    feed({})
end)

scenario("N: full release between two drags fires both",
    { "drag(3,right)", "drag(3,left)" }, function()
    feed({ touch("a", 0.20, 0.5), touch("b", 0.30, 0.5), touch("c", 0.40, 0.5) })
    tick(30)
    feed({ touch("a", 0.40, 0.5), touch("b", 0.50, 0.5), touch("c", 0.60, 0.5) })
    tick(20)
    feed({})
    tick(350)
    feed({ touch("p", 0.60, 0.5), touch("q", 0.70, 0.5), touch("r", 0.80, 0.5) })
    tick(30)
    feed({ touch("p", 0.40, 0.5), touch("q", 0.50, 0.5), touch("r", 0.60, 0.5) })
    tick(20)
    feed({})
end)

scenario("O: 4-finger landing all at once then drag right",
    { "drag(4,right)" }, function()
    feed({ touch("a", 0.10, 0.5), touch("b", 0.20, 0.5),
           touch("c", 0.30, 0.5), touch("d", 0.40, 0.5) })
    tick(30)
    feed({ touch("a", 0.30, 0.5), touch("b", 0.40, 0.5),
           touch("c", 0.50, 0.5), touch("d", 0.60, 0.5) })
    tick(20)
    feed({})
end)

scenario("P: stationary 3-cluster with no drag, no plusone bound for 3 -> nothing fires",
    {}, function()
    feed({ touch("a", 0.40, 0.5), touch("b", 0.50, 0.5), touch("c", 0.60, 0.5) })
    tick(500)
    feed({ touch("a", 0.40, 0.5), touch("b", 0.50, 0.5), touch("c", 0.60, 0.5) })
    tick(20)
    feed({})
end)

-- ---------- Step (onDragStep) scenarios ----------

scenario("Q: 4-finger step drag right with 3 commits' worth of travel fires 3 times",
    { "step(4,right)", "step(4,right)", "step(4,right)" }, function()
    feed({ touch("a", 0.05, 0.5), touch("b", 0.15, 0.5),
           touch("c", 0.25, 0.5), touch("d", 0.35, 0.5) })
    tick(20)
    feed({ touch("a", 0.08, 0.5), touch("b", 0.18, 0.5),
           touch("c", 0.28, 0.5), touch("d", 0.38, 0.5) })
    tick(20)
    feed({ touch("a", 0.20, 0.5), touch("b", 0.30, 0.5),
           touch("c", 0.40, 0.5), touch("d", 0.50, 0.5) })
    tick(20)
    feed({ touch("a", 0.35, 0.5), touch("b", 0.45, 0.5),
           touch("c", 0.55, 0.5), touch("d", 0.65, 0.5) })
    tick(20)
    feed({ touch("a", 0.50, 0.5), touch("b", 0.60, 0.5),
           touch("c", 0.70, 0.5), touch("d", 0.80, 0.5) })
    tick(20)
    feed({})
end, freshStepHandler)

scenario("R: step drag right then reverse to left within same gesture fires both",
    { "step(4,right)", "step(4,left)" }, function()
    feed({ touch("a", 0.40, 0.5), touch("b", 0.50, 0.5),
           touch("c", 0.60, 0.5), touch("d", 0.70, 0.5) })
    tick(20)
    feed({ touch("a", 0.43, 0.5), touch("b", 0.53, 0.5),
           touch("c", 0.63, 0.5), touch("d", 0.73, 0.5) })
    tick(20)
    feed({ touch("a", 0.55, 0.5), touch("b", 0.65, 0.5),
           touch("c", 0.75, 0.5), touch("d", 0.85, 0.5) })
    tick(20)
    feed({ touch("a", 0.52, 0.5), touch("b", 0.62, 0.5),
           touch("c", 0.72, 0.5), touch("d", 0.82, 0.5) })
    tick(20)
    feed({ touch("a", 0.40, 0.5), touch("b", 0.50, 0.5),
           touch("c", 0.60, 0.5), touch("d", 0.70, 0.5) })
    tick(20)
    feed({})
end, freshStepHandler)

scenario("S: step drag locks axis on first commit; later vertical drift does not fire",
    { "step(4,right)" }, function()
    feed({ touch("a", 0.30, 0.30), touch("b", 0.40, 0.30),
           touch("c", 0.50, 0.30), touch("d", 0.60, 0.30) })
    tick(20)
    feed({ touch("a", 0.33, 0.30), touch("b", 0.43, 0.30),
           touch("c", 0.53, 0.30), touch("d", 0.63, 0.30) })
    tick(20)
    -- Horizontal commit: fires step(4,right), locks horizontal.
    feed({ touch("a", 0.45, 0.30), touch("b", 0.55, 0.30),
           touch("c", 0.65, 0.30), touch("d", 0.75, 0.30) })
    tick(20)
    -- Pure vertical drift afterward must not arm.
    feed({ touch("a", 0.45, 0.50), touch("b", 0.55, 0.50),
           touch("c", 0.65, 0.50), touch("d", 0.75, 0.50) })
    tick(20)
    feed({ touch("a", 0.45, 0.70), touch("b", 0.55, 0.70),
           touch("c", 0.65, 0.70), touch("d", 0.75, 0.70) })
    tick(20)
    feed({})
end, freshStepHandler)

scenario("T: 3-finger step drag right fires per commit-distance step",
    { "step(3,right)", "step(3,right)" }, function()
    feed({ touch("a", 0.10, 0.5), touch("b", 0.20, 0.5), touch("c", 0.30, 0.5) })
    tick(20)
    feed({ touch("a", 0.13, 0.5), touch("b", 0.23, 0.5), touch("c", 0.33, 0.5) })
    tick(20)
    feed({ touch("a", 0.25, 0.5), touch("b", 0.35, 0.5), touch("c", 0.45, 0.5) })
    tick(20)
    feed({ touch("a", 0.40, 0.5), touch("b", 0.50, 0.5), touch("c", 0.60, 0.5) })
    tick(20)
    feed({})
end, freshStepHandler)

-- ---------- Mixed (init.lua style) scenarios ----------

scenario("U: mixed 4-finger vertical up fires drag(4,up) once even with continued travel",
    { "drag(4,up)" }, function()
    feed({ touch("a", 0.30, 0.10), touch("b", 0.40, 0.10),
           touch("c", 0.50, 0.10), touch("d", 0.60, 0.10) })
    tick(20)
    feed({ touch("a", 0.30, 0.13), touch("b", 0.40, 0.13),
           touch("c", 0.50, 0.13), touch("d", 0.60, 0.13) })
    tick(20)
    feed({ touch("a", 0.30, 0.25), touch("b", 0.40, 0.25),
           touch("c", 0.50, 0.25), touch("d", 0.60, 0.25) })
    tick(20)
    -- Continued upward motion past the commit-distance again: drag must NOT
    -- re-fire (it's one-shot), and the step handler filters up/down so no
    -- step record either.
    feed({ touch("a", 0.30, 0.40), touch("b", 0.40, 0.40),
           touch("c", 0.50, 0.40), touch("d", 0.60, 0.40) })
    tick(20)
    feed({ touch("a", 0.30, 0.55), touch("b", 0.40, 0.55),
           touch("c", 0.50, 0.55), touch("d", 0.60, 0.55) })
    tick(20)
    feed({})
end, freshMixedHandler)

scenario("V: mixed 4-finger horizontal scrub then vertical drift never fires drag(up)",
    { "step(4,right)", "step(4,right)" }, function()
    feed({ touch("a", 0.20, 0.30), touch("b", 0.30, 0.30),
           touch("c", 0.40, 0.30), touch("d", 0.50, 0.30) })
    tick(20)
    feed({ touch("a", 0.23, 0.30), touch("b", 0.33, 0.30),
           touch("c", 0.43, 0.30), touch("d", 0.53, 0.30) })
    tick(20)
    feed({ touch("a", 0.35, 0.30), touch("b", 0.45, 0.30),
           touch("c", 0.55, 0.30), touch("d", 0.65, 0.30) })
    tick(20)
    feed({ touch("a", 0.50, 0.30), touch("b", 0.60, 0.30),
           touch("c", 0.70, 0.30), touch("d", 0.80, 0.30) })
    tick(20)
    -- Now drift upward; axis is locked horizontal, so no drag(up) fire.
    feed({ touch("a", 0.50, 0.50), touch("b", 0.60, 0.50),
           touch("c", 0.70, 0.50), touch("d", 0.80, 0.50) })
    tick(20)
    feed({ touch("a", 0.50, 0.70), touch("b", 0.60, 0.70),
           touch("c", 0.70, 0.70), touch("d", 0.80, 0.70) })
    tick(20)
    feed({})
end, freshMixedHandler)

-- ---------- Cleanup ----------

package.loaded["TTTaps"] = savedLive
hs_timer.secondsSinceEpoch = realClock

local failed = 0
for _, r in ipairs(results) do if not r.pass then failed = failed + 1 end end
local passed = #results - failed
logln(string.format("\n%d/%d scenarios passed", passed, #results))
if logF then logF:close() end
return string.format("%d/%d", passed, #results)
