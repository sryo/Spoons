-- Simulator for the TTTaps +1 recognizer. Feeds synthetic gesture events and
-- checks which onPlusOne handlers fire, exercising the recognizer without
-- physical input. Driven by tests/tttaps/plusone.sh; returns "N/M"
-- (passed/total) to the caller and writes a detailed per-scenario log to
-- /tmp/tttaps-plusone-sim.log.
--
-- We never touch the live TTTaps instance. For each scenario we temporarily
-- swap package.loaded, require a fresh copy of the module, register recording
-- onPlusOne handlers, then drive its exposed _onGesture handler directly.
-- After the scenario the cached module is restored and the fresh instance is
-- discarded.

local LOG_PATH = "/tmp/tttaps-plusone-sim.log"
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
    g.onPlusOne(2, function(side)
        table.insert(calls, "focus(" .. (side == "left" and "backward" or "forward") .. ")")
    end)
    g.onPlusOne(3, function(side)
        table.insert(calls, "move(" .. (side == "left" and "backward" or "forward") .. ")")
    end)
    g.onPlusOne(4, function(side)
        table.insert(calls, "screen(" .. (side == "left" and "previous" or "next") .. ")")
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
local function scenario(name, expectedCalls, body)
    fakeTime = 0
    calls = {}
    currentHandle = freshHandler()
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

scenario("A: 2+1 outside cluster, fast", { "focus(backward)" }, function()
    feed({ touch("a", 0.40), touch("b", 0.60) })
    tick(30)
    feed({ touch("a", 0.40), touch("b", 0.60), touch("c", 0.10) })
    tick(40)
    feed({ touch("a", 0.40), touch("b", 0.60) })
    feed({})
end)

scenario("B: 2+1 inside cluster (between resting fingers)", { "focus(backward)" }, function()
    feed({ touch("a", 0.30), touch("b", 0.70) })
    tick(20)
    feed({ touch("a", 0.30), touch("b", 0.70), touch("c", 0.45) })
    tick(40)
    feed({ touch("a", 0.30), touch("b", 0.70) })
    feed({})
end)

scenario("C: 2+1 post-settling (slow tap)", { "focus(forward)" }, function()
    feed({ touch("a", 0.40), touch("b", 0.60) })
    tick(200)
    feed({ touch("a", 0.40), touch("b", 0.60), touch("c", 0.90) })
    tick(40)
    feed({ touch("a", 0.40), touch("b", 0.60) })
    feed({})
end)

scenario("D: 3+1 move (rest 3 then tap 4th)", { "move(forward)" }, function()
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70) })
    tick(200)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70), touch("d", 0.95) })
    tick(40)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70) })
    feed({})
end)

scenario("E: rapid 2+1 taps within one hold each fire once",
    { "focus(backward)", "focus(forward)", "focus(backward)" }, function()
    feed({ touch("a", 0.40), touch("b", 0.60) })
    tick(200)
    feed({ touch("a", 0.40), touch("b", 0.60), touch("c", 0.10) })
    tick(30)
    feed({ touch("a", 0.40), touch("b", 0.60) })
    tick(30)
    feed({ touch("a", 0.40), touch("b", 0.60), touch("d", 0.90) })
    tick(30)
    feed({ touch("a", 0.40), touch("b", 0.60) })
    tick(30)
    feed({ touch("a", 0.40), touch("b", 0.60), touch("e", 0.05) })
    tick(30)
    feed({ touch("a", 0.40), touch("b", 0.60) })
    feed({})
end)

scenario("F: all 3 fingers in one event (no intermediate touchCount=2)",
    { "focus(backward)" }, function()
    feed({ touch("a", 0.40), touch("b", 0.60), touch("c", 0.05) })
    tick(40)
    feed({ touch("a", 0.40), touch("b", 0.60) })
    feed({})
end)

scenario("G: 2+1 inside, +1 stays past settling (held tap)",
    { "focus(backward)" }, function()
    feed({ touch("a", 0.30), touch("b", 0.70) })
    tick(20)
    feed({ touch("a", 0.30), touch("b", 0.70), touch("c", 0.45) })
    tick(100)
    feed({ touch("a", 0.30), touch("b", 0.70), touch("c", 0.45) })
    tick(80)
    feed({ touch("a", 0.30), touch("b", 0.70) })
    feed({})
end)

scenario("H: 3-finger rest held long (no tap intent)", {}, function()
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70) })
    tick(500)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70) })
    tick(200)
    feed({})
end)

scenario("I: 2+1 inside, held very long (no fire)",
    {}, function()
    feed({ touch("a", 0.30), touch("b", 0.70) })
    tick(20)
    feed({ touch("a", 0.30), touch("b", 0.70), touch("c", 0.45) })
    tick(400)
    feed({ touch("a", 0.30), touch("b", 0.70), touch("c", 0.45) })
    tick(80)
    feed({ touch("a", 0.30), touch("b", 0.70) })
    feed({})
end)

scenario("J: 2+1 outside, fingers landed in 3 separate frames",
    { "focus(forward)" }, function()
    feed({ touch("a", 0.40) })
    tick(8)
    feed({ touch("a", 0.40), touch("b", 0.60) })
    tick(8)
    feed({ touch("a", 0.40), touch("b", 0.60), touch("c", 0.95) })
    tick(40)
    feed({ touch("a", 0.40), touch("b", 0.60) })
    feed({})
end)

scenario("K: 3+1 move, all 4 fingers in one event (fast)",
    { "move(forward)" }, function()
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70), touch("d", 0.95) })
    tick(40)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70) })
    feed({})
end)

scenario("L: 3+1 move, 3 fingers asymmetric then 4th",
    { "move(forward)" }, function()
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.80) })
    tick(200)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.80), touch("d", 0.97) })
    tick(40)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.80) })
    feed({})
end)

scenario("M: 3-finger rest with positional asymmetry, no tap intent",
    {}, function()
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.92) })
    tick(500)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.92) })
    tick(100)
    feed({})
end)

scenario("N: 3+1 with +1 X inside cluster, Y below it (portrait-style tap)",
    { "move(backward)" }, function()
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70) })
    tick(200)
    feed({ touch("a", 0.30, 0.5), touch("b", 0.50, 0.5), touch("c", 0.70, 0.5),
           touch("d", 0.45, 0.9) })
    tick(40)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70) })
    feed({})
end)

scenario("O: 3+1 held 400ms still fires (touchdown semantics)",
    { "move(forward)" }, function()
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70) })
    tick(200)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70), touch("d", 0.95) })
    tick(400)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70), touch("d", 0.95) })
    tick(40)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70) })
    feed({})
end)

scenario("P: two 3+1 taps within the same 3-finger hold both fire",
    { "move(backward)", "move(forward)" }, function()
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70) })
    tick(200)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70), touch("d", 0.05) })
    tick(40)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70) })
    tick(30)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70), touch("e", 0.95) })
    tick(40)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70) })
    feed({})
end)

scenario("Q: 2-finger drag taints the gesture; subsequent +1 is suppressed",
    {}, function()
    feed({ touch("a", 0.40, 0.5), touch("b", 0.60, 0.5) })
    tick(30)
    feed({ touch("a", 0.65, 0.5), touch("b", 0.85, 0.5) })
    tick(30)
    feed({ touch("a", 0.65, 0.5), touch("b", 0.85, 0.5), touch("c", 0.10, 0.5) })
    tick(40)
    feed({ touch("a", 0.65, 0.5), touch("b", 0.85, 0.5) })
    feed({})
end)

scenario("R: 3 fingers landing slowly (over 100 ms) is a 3-cluster, not 2+1",
    { "move(forward)" }, function()
    feed({ touch("a", 0.30) })
    tick(20)
    feed({ touch("a", 0.30), touch("b", 0.50) })
    tick(100)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70) })
    tick(300)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70), touch("d", 0.95) })
    tick(40)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70) })
    feed({})
end)

scenario("S: 2+1 with +1 held does NOT re-fire on subsequent events",
    { "focus(forward)" }, function()
    feed({ touch("a", 0.40), touch("b", 0.60) })
    tick(200)
    feed({ touch("a", 0.40), touch("b", 0.60), touch("c", 0.90) })
    tick(50)
    feed({ touch("a", 0.40), touch("b", 0.60), touch("c", 0.90) })
    tick(50)
    feed({ touch("a", 0.40), touch("b", 0.60), touch("c", 0.90) })
    tick(50)
    feed({ touch("a", 0.40), touch("b", 0.60), touch("c", 0.90) })
    feed({})
end)

scenario("T: 2+1, full release, 2+1 again -> two fires (separate cycles)",
    { "focus(backward)", "focus(forward)" }, function()
    feed({ touch("a", 0.40), touch("b", 0.60) })
    tick(200)
    feed({ touch("a", 0.40), touch("b", 0.60), touch("c", 0.10) })
    tick(40)
    feed({})
    tick(350)
    feed({ touch("d", 0.40), touch("e", 0.60) })
    tick(200)
    feed({ touch("d", 0.40), touch("e", 0.60), touch("f", 0.95) })
    feed({})
end)

scenario("U: 3+1, +1 held across multiple events, no re-fire",
    { "move(forward)" }, function()
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70) })
    tick(200)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70), touch("d", 0.95) })
    tick(40)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70), touch("d", 0.95, nil, "moved") })
    tick(40)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70), touch("d", 0.95, nil, "stationary") })
    tick(40)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70), touch("d", 0.95) })
    feed({})
end)

scenario("V: 3+1 with explicit phase=ended, then second 3+1 fires",
    { "move(backward)", "move(forward)" }, function()
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70) })
    tick(200)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70), touch("d", 0.05) })
    tick(40)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70), touch("d", 0.05, nil, "ended") })
    tick(10)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70) })
    tick(30)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70), touch("e", 0.95) })
    tick(40)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70) })
    feed({})
end)

scenario("W: 3+1, +1 vanishes without an ended event, rapid second tap fires",
    { "move(backward)", "move(forward)" }, function()
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70) })
    tick(200)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70), touch("d", 0.05) })
    tick(40)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70) })
    tick(40)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70), touch("e", 0.95) })
    tick(40)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70) })
    feed({})
end)

-- ---------- Cleanup ----------

package.loaded["TTTaps"] = savedLive
hs_timer.secondsSinceEpoch = realClock

local failed = 0
for _, r in ipairs(results) do if not r.pass then failed = failed + 1 end end
local passed = #results - failed
logln(string.format("\n%d/%d scenarios passed", passed, #results))
if logF then logF:close() end
return string.format("%d/%d", passed, #results)
