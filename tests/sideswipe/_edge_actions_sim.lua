-- Simulator for SideSwipe. The module auto-starts on require: it creates a
-- HUD canvas, installs a gesture eventtap, and installs a screen watcher.
-- We stub the relevant `hs.*` APIs before each re-require so module-load
-- is captured (no live tap, no real canvas, no real device calls). The
-- stubbed `hs.eventtap.new` captures the gesture callback so we can feed
-- mock touch events to it directly.

local LOG_PATH = "/tmp/sideswipe-sim.log"
local logF = io.open(LOG_PATH, "w")
local function logln(s) if logF then logF:write(s .. "\n") end end

local L = dofile(hs.configdir .. "/tests/_test_lib.lua")
local assertEq, assertNear = L.assertEq, L.assertNear

-- ---------- Live values saved at module load ----------

local saved = {
    eventtapNew         = hs.eventtap.new,
    canvasNew           = hs.canvas.new,
    screenMainScreen    = hs.screen.mainScreen,
    screenAllScreens    = hs.screen.allScreens,
    screenWatcherNew    = hs.screen.watcher.new,
    audioDefaultOutput  = hs.audiodevice.defaultOutputDevice,
    brightnessSet       = hs.brightness.set,
    timerDoAfter        = hs.timer.doAfter,
}

-- ---------- Per-scenario state ----------

local capturedCallback   -- the function passed to hs.eventtap.new(..., fn)
local volumeCalls        -- list of values that landed on the recording device
local brightnessCalls    -- list of {screenName, value} that landed on a screen
local brightnessFallback -- list of values handled by hs.brightness.set
local recordingDevice    -- the object hs.audiodevice.defaultOutputDevice returns
local internalScreenName -- the screen name our stub flags as the internal display

local function noopFn() return setmetatable({}, { __index = function() return function() end end }) end

local function fakeCanvas()
    -- Index-by-number lazily returns a stored sub-table so the module can do
    -- both `hud[1] = {...}` (assign) and `hud[2].endAngle = X` (mutate).
    local elements = {}
    return setmetatable({}, {
        __index = function(_, k)
            if type(k) == "number" then
                elements[k] = elements[k] or {}
                return elements[k]
            end
            return function() end -- methods: show/hide/frame/etc.
        end,
        __newindex = function(_, k, v)
            if type(k) == "number" then elements[k] = v end
        end,
    })
end

local function installStubs()
    capturedCallback   = nil
    volumeCalls        = {}
    brightnessCalls    = {}
    brightnessFallback = {}
    internalScreenName = "Built-in Retina Display"
    recordingDevice = {
        setVolume = function(_, value) table.insert(volumeCalls, value) end,
    }

    hs.eventtap.new = function(_, callback)
        capturedCallback = callback
        return { start = function() end, stop = function() end, isEnabled = function() return true end }
    end

    hs.canvas.new = function(_) return fakeCanvas() end

    hs.screen.mainScreen = function()
        return { frame = function() return { x = 0, y = 0, w = 1440, h = 900 } end }
    end

    hs.screen.allScreens = function()
        local internal = {
            name = function() return internalScreenName end,
            setBrightness = function(_, value)
                table.insert(brightnessCalls, { screen = internalScreenName, value = value })
            end,
        }
        local external = {
            name = function() return "LG UltraFine 5K" end,
            setBrightness = function(_, value)
                table.insert(brightnessCalls, { screen = "LG UltraFine 5K", value = value })
            end,
        }
        return { external, internal } -- internal not first; module must select by name
    end

    hs.screen.watcher.new = function(_) return { start = function() end, stop = function() end } end

    hs.audiodevice.defaultOutputDevice = function() return recordingDevice end

    hs.brightness.set = function(value) table.insert(brightnessFallback, value) end

    -- The HUD uses timer.doAfter to auto-hide; just ignore.
    hs.timer.doAfter = function(_, _) return { stop = function() end } end
end

local function restoreLive()
    hs.eventtap.new                  = saved.eventtapNew
    hs.canvas.new                    = saved.canvasNew
    hs.screen.mainScreen             = saved.screenMainScreen
    hs.screen.allScreens             = saved.screenAllScreens
    hs.screen.watcher.new            = saved.screenWatcherNew
    hs.audiodevice.defaultOutputDevice = saved.audioDefaultOutput
    hs.brightness.set                = saved.brightnessSet
    hs.timer.doAfter                 = saved.timerDoAfter
end

local function freshModule()
    package.loaded["SideSwipe"] = nil
    require("SideSwipe")
    assert(type(capturedCallback) == "function", "gesture callback not captured during module load")
    return capturedCallback
end

-- ---------- Touch & event mocks ----------

local function mockEvent(touches)
    return {
        getTouches = function(_) return touches end,
    }
end

local function touch(id, x, y)
    return {
        identity           = id,
        type               = "indirect",
        touching           = true,
        normalizedPosition = { x = x, y = y or 0.5 },
    }
end

-- Feed one event through the captured callback.
local function feed(handler, touches) handler(mockEvent(touches)) end

-- ---------- Scenario harness ----------

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

scenario("touch at left edge fires brightness on the internal screen", function()
    local h = freshModule()
    feed(h, { touch("t1", 0.001, 0.5) })
    assert(#brightnessCalls > 0, "brightness action should fire")
    assertEq(brightnessCalls[1].screen, internalScreenName, "brightness routed to internal screen")
    assertEq(#volumeCalls, 0, "volume should not fire on a left-edge touch")
end)

scenario("touch at right edge fires volume on the DEFAULT output device", function()
    local h = freshModule()
    -- Mark our recording device with a sentinel field; assert that field exists
    -- on the call site by tracking via volumeCalls (only this device records).
    feed(h, { touch("t1", 0.999, 0.7) })
    assertEq(#volumeCalls, 1, "exactly one volume call")
    assertEq(#brightnessCalls, 0, "no brightness call")
    -- Value formula: y=0.7, edgePadding=0.08 → (0.7 - 0.08)/(1 - 2*0.08) * 100 ≈ 73.81
    assertNear(volumeCalls[1], (0.7 - 0.08) / (1 - 2 * 0.08) * 100, 0.1, "computed volume value")
end)

scenario("touch starting in middle never triggers action even if id persists", function()
    local h = freshModule()
    feed(h, { touch("t1", 0.5, 0.5) })       -- middle, validTouches[t1] sealed to false
    feed(h, { touch("t1", 0.001, 0.5) })     -- still 't1' — sealed; should NOT act
    assertEq(#brightnessCalls, 0, "brightness must stay silent (validTouches sealed)")
    assertEq(#volumeCalls, 0, "volume must stay silent")
end)

scenario("touch starting at edge stays active when drifting inward", function()
    local h = freshModule()
    feed(h, { touch("t1", 0.001, 0.5) })   -- started at left edge → sealed "left"
    feed(h, { touch("t1", 0.40, 0.5) })    -- drifted inward — still routes to brightness
    assert(#brightnessCalls >= 2, "brightness should fire on both samples, got " .. #brightnessCalls)
end)

scenario("value mapping respects edgePadding (0/0.5/1.0 at y=0.08/0.5/0.92)", function()
    -- Brightness action passes `value / 100` to screen:setBrightness; values
    -- recorded by our stub are in 0..1.
    local h = freshModule()
    feed(h, { touch("t1", 0.001, 0.08) })
    feed(h, { touch("t2", 0.001, 0.50) })
    feed(h, { touch("t3", 0.001, 0.92) })
    assertEq(#brightnessCalls, 3, "three brightness calls (one per fresh touch id)")
    assertNear(brightnessCalls[1].value, 0,   0.01, "y=0.08 → 0.0")
    assertNear(brightnessCalls[2].value, 0.5, 0.01, "y=0.5  → 0.5")
    assertNear(brightnessCalls[3].value, 1.0, 0.01, "y=0.92 → 1.0")
end)

scenario("non-default output device is not touched", function()
    -- Wrap defaultOutputDevice to record EVERY call and confirm the very device
    -- it returns is the one volume lands on. A bug routing volume to a different
    -- device would be caught here.
    local h = freshModule()
    local marker = "sentinel-default-" .. tostring(os.time())
    recordingDevice.__marker = marker
    -- Replace defaultOutputDevice mid-flight to return a different device; a
    -- correctly-written action calls defaultOutputDevice() each time and reads
    -- the CURRENT default at the moment of the touch.
    local secondCalls = {}
    local secondDevice = {
        __marker = "different",
        setVolume = function(_, v) table.insert(secondCalls, v) end,
    }
    hs.audiodevice.defaultOutputDevice = function() return secondDevice end
    feed(h, { touch("t1", 0.999, 0.5) })
    assertEq(#volumeCalls, 0, "old device must not be called after default changed")
    assertEq(#secondCalls, 1, "new default device receives the volume call")
end)

-- ---------- Cleanup ----------

restoreLive()
package.loaded["SideSwipe"] = nil

local failed = 0
for _, r in ipairs(results) do if not r.pass then failed = failed + 1 end end
local passed = #results - failed
logln(string.format("\n%d/%d scenarios passed", passed, #results))
if logF then logF:close() end
return string.format("%d/%d", passed, #results)
