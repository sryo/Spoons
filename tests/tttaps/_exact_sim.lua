-- Simulator for TTTaps.onTap (exact-N tap-and-release). Feeds synthetic gesture
-- events and checks whether the registered onTap handler fires.
-- Driven by tests/tttaps/exact.sh; returns "N/M" to the caller and writes a
-- detailed per-scenario log to /tmp/tttaps-exact-sim.log.

local LOG_PATH = "/tmp/tttaps-exact-sim.log"
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
local function freshHandler(taps)
    package.loaded["TTTaps"] = nil
    local g = require("TTTaps")
    for n, _ in pairs(taps) do
        g.onTap(n, function() table.insert(calls, "tap(" .. n .. ")") end)
    end
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
local function scenario(name, registered, expectedCalls, body)
    fakeTime = 0
    calls = {}
    currentHandle = freshHandler(registered)
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

scenario("A: clean 5-finger tap fires onTap(5)",
    { [5] = true }, { "tap(5)" }, function()
    -- All 5 fingers land in one event (no intermediate cluster forms).
    feed({ touch("a", 0.1, 0.5, "began"), touch("b", 0.3, 0.5, "began"),
           touch("c", 0.5, 0.5, "began"), touch("d", 0.7, 0.5, "began"),
           touch("e", 0.9, 0.5, "began") })
    tick(80)
    -- One finger ends, count still 5 in this event.
    feed({ touch("a", 0.1, 0.5, "ended"), touch("b", 0.3), touch("c", 0.5),
           touch("d", 0.7), touch("e", 0.9) })
    tick(20)
    feed({})
end)

scenario("B: 4-finger tap does NOT fire onTap(5)",
    { [5] = true }, {}, function()
    feed({ touch("a", 0.2, 0.5, "began"), touch("b", 0.4, 0.5, "began"),
           touch("c", 0.6, 0.5, "began"), touch("d", 0.8, 0.5, "began") })
    tick(80)
    feed({ touch("a", 0.2, 0.5, "ended"), touch("b", 0.4), touch("c", 0.6), touch("d", 0.8) })
    tick(20)
    feed({})
end)

scenario("C: two clean 5-finger taps fire twice (separate cycles)",
    { [5] = true }, { "tap(5)", "tap(5)" }, function()
    feed({ touch("a", 0.1, 0.5, "began"), touch("b", 0.3, 0.5, "began"),
           touch("c", 0.5, 0.5, "began"), touch("d", 0.7, 0.5, "began"),
           touch("e", 0.9, 0.5, "began") })
    tick(60)
    feed({ touch("a", 0.1, 0.5, "ended"), touch("b", 0.3), touch("c", 0.5),
           touch("d", 0.7), touch("e", 0.9) })
    tick(20)
    feed({})
    tick(350)
    feed({ touch("p", 0.1, 0.5, "began"), touch("q", 0.3, 0.5, "began"),
           touch("r", 0.5, 0.5, "began"), touch("s", 0.7, 0.5, "began"),
           touch("t", 0.9, 0.5, "began") })
    tick(60)
    feed({ touch("p", 0.1, 0.5, "ended"), touch("q", 0.3), touch("r", 0.5),
           touch("s", 0.7), touch("t", 0.9) })
    feed({})
end)

scenario("D: 4+1 (cluster 4 + 1 past settling) does NOT fire onTap(5)",
    { [5] = true }, {}, function()
    -- 4 fingers settle as cluster.
    feed({ touch("a", 0.20, 0.5, "began"), touch("b", 0.40, 0.5, "began"),
           touch("c", 0.60, 0.5, "began"), touch("d", 0.80, 0.5, "began") })
    tick(200)
    -- 5th lands past settling; +1 path latches onTap(5).
    feed({ touch("a", 0.20), touch("b", 0.40), touch("c", 0.60), touch("d", 0.80),
           touch("e", 0.95, 0.5, "began") })
    tick(40)
    -- 5th lifts (ended in count=5 event).
    feed({ touch("a", 0.20), touch("b", 0.40), touch("c", 0.60), touch("d", 0.80),
           touch("e", 0.95, 0.5, "ended") })
    tick(20)
    feed({ touch("a", 0.20), touch("b", 0.40), touch("c", 0.60), touch("d", 0.80) })
    feed({})
end)

scenario("E: 6 fingers down then lift does NOT fire onTap(5)",
    { [5] = true }, {}, function()
    feed({ touch("a", 0.1, 0.5, "began"), touch("b", 0.25, 0.5, "began"),
           touch("c", 0.4, 0.5, "began"), touch("d", 0.55, 0.5, "began"),
           touch("e", 0.7, 0.5, "began"), touch("f", 0.85, 0.5, "began") })
    tick(80)
    feed({ touch("a", 0.1, 0.5, "ended"), touch("b", 0.25), touch("c", 0.4),
           touch("d", 0.55), touch("e", 0.7), touch("f", 0.85) })
    tick(20)
    feed({})
end)

scenario("F: slow 5-finger land within settling fires onTap(5) on release",
    { [5] = true }, { "tap(5)" }, function()
    -- Fingers land in stages, all within the 150ms settling window.
    -- With clusterCap raised to 5 (by onTap(5) registration), all 5 are
    -- absorbed into the cluster; the +1 path never trips. Release fires onTap.
    feed({ touch("a", 0.10) })
    tick(20)
    feed({ touch("a", 0.10), touch("b", 0.30) })
    tick(20)
    feed({ touch("a", 0.10), touch("b", 0.30), touch("c", 0.50) })
    tick(20)
    feed({ touch("a", 0.10), touch("b", 0.30), touch("c", 0.50), touch("d", 0.70) })
    tick(20)
    feed({ touch("a", 0.10), touch("b", 0.30), touch("c", 0.50),
           touch("d", 0.70), touch("e", 0.90) })
    tick(40)
    feed({})
end)

scenario("G: real-Mac 5-finger sequence (all stationary, count drops in chunks)",
    { [5] = true }, { "tap(5)" }, function()
    -- Captured from a live trackpad: macOS never emits phase="ended"; fingers
    -- arrive in chunks (1 -> 4 -> 5) and disappear in chunks at release.
    feed({ touch("a", 0.40) })
    tick(8)
    feed({ touch("a", 0.40), touch("b", 0.60), touch("c", 0.45), touch("d", 0.80) })
    tick(15)
    feed({ touch("a", 0.40), touch("b", 0.60), touch("c", 0.45),
           touch("d", 0.80), touch("e", 0.55) })
    tick(200)
    feed({ touch("a", 0.40), touch("b", 0.60), touch("c", 0.45),
           touch("d", 0.80), touch("e", 0.55) })
    tick(50)
    feed({ touch("a", 0.40), touch("b", 0.60) })
    feed({ touch("a", 0.40) })
    feed({})
end)

scenario("H: cluster-4 settles, late +1 past settling suppresses onTap(5)",
    { [5] = true }, {}, function()
    -- 4 fingers settle as cluster=4. After settling, 5th lands and the +1 path
    -- dispatches (plusOneFired=true), suppressing onTap(5) even though peak=5.
    feed({ touch("a", 0.20), touch("b", 0.40), touch("c", 0.60), touch("d", 0.80) })
    tick(200)
    feed({ touch("a", 0.20), touch("b", 0.40), touch("c", 0.60),
           touch("d", 0.80), touch("e", 0.95) })
    tick(40)
    feed({ touch("a", 0.20), touch("b", 0.40), touch("c", 0.60), touch("d", 0.80) })
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
