-- Simulator for the WindowScape gesture handler. Feeds synthetic gesture events
-- and checks which callbacks fire, exercising the recognizer without physical input.
-- Driven by tests/windowscape_gestures.sh; returns "N/M" (passed/total) to the
-- caller and writes a detailed per-scenario log to /tmp/wsg-gesture-sim.log.
--
-- We never touch the live WindowScape.gestures instance. For each scenario we
-- temporarily swap package.loaded, require a fresh copy of the module, init it
-- with our recording callbacks, then reach handleTTTaps via debug.getupvalue
-- on its `start` function. After the scenario the cached module is restored
-- and the fresh instance is discarded.

local LOG_PATH = "/tmp/wsg-gesture-sim.log"
local logF = io.open(LOG_PATH, "w")
local function logln(s) if logF then logF:write(s .. "\n") end end

local hs_timer = require("hs.timer")
local hs_eventtap = require("hs.eventtap")

-- Inject a fake clock so we can step time deterministically.
local fakeTime = 0
local realClock = hs_timer.secondsSinceEpoch
hs_timer.secondsSinceEpoch = function() return fakeTime end
local function tick(ms) fakeTime = fakeTime + ms / 1000 end

-- Stash the live gestures module so we can reload a clean copy per scenario.
local savedLive = package.loaded["WindowScape.gestures"]

local function upvals(fn)
    local t = {}
    if type(fn) ~= "function" then return t end
    local i = 1
    while true do
        local n, v = debug.getupvalue(fn, i)
        if not n then break end
        t[n] = v
        i = i + 1
    end
    return t
end

-- Each scenario gets a fresh handle to the gesture handler.
local calls = {}
local function freshHandler()
    package.loaded["WindowScape.gestures"] = nil
    local g = require("WindowScape.gestures")
    g.init({}, {
        focusAdjacentWindow        = function(dir) table.insert(calls, "focus(" .. tostring(dir) .. ")") end,
        moveWindowInOrder          = function(dir) table.insert(calls, "move("  .. tostring(dir) .. ")") end,
        moveWindowToAdjacentScreen = function(dir) table.insert(calls, "screen(".. tostring(dir) .. ")") end,
    })
    local handle = upvals(g.start).handleTTTaps
    assert(type(handle) == "function", "could not reach handleTTTaps via debug.getupvalue")
    return handle
end

-- Mock an hs.eventtap gesture event.
local function mockEvent(touches)
    return {
        getType         = function(_) return hs_eventtap.event.types.gesture end,
        getTouches      = function(_) return touches end,
        getTouchDetails = function(_) return {} end,
    }
end

-- A single touch entry. `id` should be stable across events for fingers
-- that stay down. Pass a NEW id for a finger that landed after a lift.
local function touch(id, x, y)
    return {
        identity           = id,
        touching           = true,
        type               = "indirect",
        normalizedPosition = { x = x, y = y or 0.5 },
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
    feed({ touch("a", 0.40), touch("b", 0.60) })                            -- t=0  rest
    tick(30)
    feed({ touch("a", 0.40), touch("b", 0.60), touch("c", 0.10) })           -- t=30 +1 LEFT outside
    tick(40)
    feed({ touch("a", 0.40), touch("b", 0.60) })                            -- t=70 +1 up
    feed({})                                                                -- full lift
end)

scenario("B: 2+1 inside cluster (between resting fingers)", { "focus(backward)" }, function()
    feed({ touch("a", 0.30), touch("b", 0.70) })                            -- t=0  rest wide
    tick(20)
    feed({ touch("a", 0.30), touch("b", 0.70), touch("c", 0.45) })           -- t=20 +1 between, left bias
    tick(40)
    feed({ touch("a", 0.30), touch("b", 0.70) })                            -- t=60 +1 up
    feed({})
end)

scenario("C: 2+1 post-settling (slow tap)", { "focus(forward)" }, function()
    feed({ touch("a", 0.40), touch("b", 0.60) })                            -- t=0  rest
    tick(200)                                                               -- past settling
    feed({ touch("a", 0.40), touch("b", 0.60), touch("c", 0.90) })           -- +1 RIGHT
    tick(40)
    feed({ touch("a", 0.40), touch("b", 0.60) })                            -- +1 up
    feed({})
end)

scenario("D: 3+1 move (rest 3 then tap 4th)", { "move(forward)" }, function()
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70) })           -- 3 fingers together
    tick(200)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70), touch("d", 0.95) })  -- +1 RIGHT
    tick(40)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70) })           -- 4th up
    feed({})
end)

scenario("E: rapid 2+1 taps x3 (left, right, left)",
    { "focus(backward)", "focus(forward)", "focus(backward)" }, function()
    feed({ touch("a", 0.40), touch("b", 0.60) })                            -- rest
    tick(200)
    -- tap 1
    feed({ touch("a", 0.40), touch("b", 0.60), touch("c", 0.10) })           -- LEFT
    tick(30)
    feed({ touch("a", 0.40), touch("b", 0.60) })
    tick(30)
    -- tap 2
    feed({ touch("a", 0.40), touch("b", 0.60), touch("d", 0.90) })           -- RIGHT
    tick(30)
    feed({ touch("a", 0.40), touch("b", 0.60) })
    tick(30)
    -- tap 3
    feed({ touch("a", 0.40), touch("b", 0.60), touch("e", 0.05) })           -- LEFT
    tick(30)
    feed({ touch("a", 0.40), touch("b", 0.60) })
    feed({})
end)

scenario("F: all 3 fingers in one event (no intermediate touchCount=2)",
    { "focus(backward)" }, function()
    -- The handler sees touchCount jump from 0 to 3 in one frame, then
    -- back to 2 when the +1 lifts. This is the case the user might trigger
    -- with a fast tap where the OS samples all 3 fingers together.
    feed({ touch("a", 0.40), touch("b", 0.60), touch("c", 0.05) })
    tick(40)
    feed({ touch("a", 0.40), touch("b", 0.60) })
    feed({})
end)

scenario("G: 2+1 inside, +1 stays past settling (held tap)",
    { "focus(backward)" }, function()
    feed({ touch("a", 0.30), touch("b", 0.70) })                            -- rest wide
    tick(20)
    feed({ touch("a", 0.30), touch("b", 0.70), touch("c", 0.45) })           -- +1 inside
    tick(100)                                                                -- past settling, +1 still down
    feed({ touch("a", 0.30), touch("b", 0.70), touch("c", 0.45) })           -- still 3, no change
    tick(80)
    feed({ touch("a", 0.30), touch("b", 0.70) })                            -- +1 up
    feed({})
end)

scenario("H: 3-finger rest held long (no tap intent)", {}, function()
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70) })           -- 3 fingers
    tick(500)                                                                -- long hold
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.70) })
    tick(200)
    feed({})                                                                 -- all lift
end)

scenario("I: 2+1 inside, held very long then lift (should be rest, no fire)",
    {}, function()
    feed({ touch("a", 0.30), touch("b", 0.70) })
    tick(20)
    feed({ touch("a", 0.30), touch("b", 0.70), touch("c", 0.45) })           -- +1 inside
    tick(400)                                                                -- held past rest threshold
    feed({ touch("a", 0.30), touch("b", 0.70), touch("c", 0.45) })
    tick(80)
    feed({ touch("a", 0.30), touch("b", 0.70) })                            -- now lift
    feed({})
end)

scenario("J: 2+1 outside, fingers landed in 3 separate frames",
    { "focus(forward)" }, function()
    feed({ touch("a", 0.40) })                                               -- finger 1
    tick(8)
    feed({ touch("a", 0.40), touch("b", 0.60) })                            -- finger 2
    tick(8)
    feed({ touch("a", 0.40), touch("b", 0.60), touch("c", 0.95) })           -- +1 RIGHT
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
    -- 3 fingers natural rest, one slightly off
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.80) })
    tick(200)                                                                -- past any ambiguous window
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.80), touch("d", 0.97) })
    tick(40)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.80) })
    feed({})
end)

scenario("M: 3-finger rest with positional asymmetry, no tap intent",
    {}, function()
    -- User puts 3 fingers down; rightmost is far from middle (looks like outlier but isn't)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.92) })
    tick(500)
    feed({ touch("a", 0.30), touch("b", 0.50), touch("c", 0.92) })
    tick(100)
    feed({})
end)

-- ---------- Cleanup ----------

-- Restore the live module so subsequent require() calls return the real instance.
package.loaded["WindowScape.gestures"] = savedLive
hs_timer.secondsSinceEpoch = realClock

local failed = 0
for _, r in ipairs(results) do if not r.pass then failed = failed + 1 end end
local passed = #results - failed
logln(string.format("\n%d/%d scenarios passed", passed, #results))
if logF then logF:close() end
return string.format("%d/%d", passed, #results)
