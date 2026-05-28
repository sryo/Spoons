-- Simulator for MenuMaestro's data layer: usage tracking, priority scoring,
-- shortcut glyph rendering, and final-choices ordering.
--
-- The module installs an eventtap and a hotkey at load. We stub both (capturing
-- callbacks) so module-load is benign, then walk upvalues from the captured
-- touchToOpenMenuMaestro callback to reach `openMenuMaestro` and through it
-- the locals we care about. `hs.settings` is stubbed with an in-memory store
-- so usage data manipulation is isolated.

local LOG_PATH = "/tmp/menumaestro-sim.log"
local logF = io.open(LOG_PATH, "w")
local function logln(s) if logF then logF:write(s .. "\n") end end

local L = dofile(hs.configdir .. "/tests/_test_lib.lua")
local deepUpvals, assertEq, assertNear = L.deepUpvals, L.assertEq, L.assertNear

-- ---------- Live values ----------

local saved = {
    eventtapNew      = hs.eventtap.new,
    hotkeyBind       = hs.hotkey.bind,
    settingsGet      = hs.settings.get,
    settingsSet      = hs.settings.set,
    chooserNew       = hs.chooser.new,
    canvasNew        = hs.canvas.new,
    hostStyle        = hs.host.interfaceStyle,
    timerDoEvery     = hs.timer.doEvery,
    frontmostApp     = hs.application.frontmostApplication,
    isMenuMaestroOpen = _G.isMenuMaestroOpen,
}

-- ---------- Per-scenario state ----------

local capturedTouchCb -- the eventtap callback (touchToOpenMenuMaestro)
local capturedHotkey  -- the hotkey callback (openMenuMaestro)
local capturedDaily   -- the daily-cleanup callback (cleanUpUsageData)
local store           -- hs.settings backing
local now             -- override os.time for scoring tests
local realOsTime      = os.time

local function fakeCanvas()
    local elements = {}
    return setmetatable({}, {
        __index = function(_, k)
            if type(k) == "number" then
                elements[k] = elements[k] or {}; return elements[k]
            end
            return function() return setmetatable({}, { __index = function() return function() end end }) end
        end,
        __newindex = function(_, k, v)
            if type(k) == "number" then elements[k] = v end
        end,
    })
end

local function installStubs()
    capturedTouchCb = nil
    capturedHotkey  = nil
    capturedDaily   = nil
    store = {}
    now = 1700000000

    hs.eventtap.new = function(_, callback)
        capturedTouchCb = callback
        return { start = function() end, stop = function() end }
    end
    hs.hotkey.bind = function(_, _, callback)
        capturedHotkey = callback
        return { delete = function() end }
    end
    hs.settings.get = function(k) return store[k] end
    hs.settings.set = function(k, v) store[k] = v end
    hs.chooser.new = function()
        return {
            choices = function() end, searchSubText = function() end,
            placeholderText = function() end, rows = function() end,
            show = function() end, delete = function() end, isVisible = function() return false end,
        }
    end
    hs.canvas.new = function(_) return fakeCanvas() end
    hs.host.interfaceStyle = function() return "Light" end
    hs.timer.doEvery = function(_, callback) capturedDaily = callback; return { stop = function() end } end
    hs.application.frontmostApplication = function() return nil end
    os.time = function() return now end
end

local function restoreLive()
    hs.eventtap.new                     = saved.eventtapNew
    hs.hotkey.bind                      = saved.hotkeyBind
    hs.settings.get                     = saved.settingsGet
    hs.settings.set                     = saved.settingsSet
    hs.chooser.new                      = saved.chooserNew
    hs.canvas.new                       = saved.canvasNew
    hs.host.interfaceStyle              = saved.hostStyle
    hs.timer.doEvery                    = saved.timerDoEvery
    hs.application.frontmostApplication = saved.frontmostApp
    _G.isMenuMaestroOpen                = saved.isMenuMaestroOpen
    os.time                             = realOsTime
end

local function freshModule()
    package.loaded["MenuMaestro"] = nil
    require("MenuMaestro")
    -- Walk deeply from both captured callbacks to find module-locals.
    local U = {}
    for k, v in pairs(deepUpvals(capturedTouchCb or function() end)) do U[k] = v end
    for k, v in pairs(deepUpvals(capturedHotkey or function() end)) do
        if U[k] == nil then U[k] = v end
    end
    -- cleanUpUsageData is only registered as a timer callback; capture it directly.
    U.cleanUpUsageData = capturedDaily
    return U
end

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

scenario("updateUsageData increments count and updates lastUsed", function()
    local U = freshModule()
    assert(type(U.updateUsageData) == "function", "couldn't reach updateUsageData via upvalues")
    assert(type(U.usageData) == "table", "couldn't reach usageData table")

    U.updateUsageData("TestApp", "File > Open")
    assertEq(U.usageData["TestApp"]["File > Open"].count, 1, "first call sets count to 1")
    assertEq(U.usageData["TestApp"]["File > Open"].lastUsed, now, "lastUsed is current time")

    now = now + 10
    U.updateUsageData("TestApp", "File > Open")
    assertEq(U.usageData["TestApp"]["File > Open"].count, 2, "second call increments count")
    assertEq(U.usageData["TestApp"]["File > Open"].lastUsed, now, "lastUsed updates to new time")
end)

scenario("cleanUpUsageData removes entries past retention window", function()
    local U = freshModule()
    local secondsPerDay = 24 * 60 * 60
    local oldTime = now - (40 * secondsPerDay) -- older than default 30 days
    local freshTime = now - (5 * secondsPerDay)
    U.usageData["AppA"] = {
        ["old > entry"]   = { count = 5, lastUsed = oldTime },
        ["fresh > entry"] = { count = 3, lastUsed = freshTime },
    }
    U.usageData["AppB"] = {
        ["only > old"] = { count = 1, lastUsed = oldTime },
    }
    U.cleanUpUsageData()
    assertEq(U.usageData["AppA"]["old > entry"], nil, "stale entry removed")
    assert(U.usageData["AppA"]["fresh > entry"] ~= nil, "fresh entry preserved")
    assertEq(U.usageData["AppB"], nil, "app with only-stale entries pruned entirely")
end)

scenario("calculatePriorityScore matches the count * 1e6 / (recency+1) formula", function()
    local U = freshModule()
    U.usageData["AppX"] = {
        ["heavy"] = { count = 100, lastUsed = now - 60 }, -- 60s recency
        ["light"] = { count = 1,   lastUsed = now - 10 }, -- 10s recency
    }
    local heavy = U.calculatePriorityScore("AppX", "heavy")
    local light = U.calculatePriorityScore("AppX", "light")
    assertNear(heavy, 100 * 1e6 / (60 + 1), 1, "heavy formula")
    assertNear(light, 1   * 1e6 / (10 + 1), 1, "light formula")
    assert(heavy > light, "100/60s should outscore 1/10s")
    assertEq(U.calculatePriorityScore("AppX", "unknown"), 0, "unknown path scores 0")
    assertEq(U.calculatePriorityScore("UnknownApp", "any"), 0, "unknown app scores 0")
end)

scenario("shortcutToString maps modifiers + key to glyphs", function()
    local U = freshModule()
    assertEq(U.shortcutToString({ "cmd" }, "s"), "⌘s", "cmd+s")
    assertEq(U.shortcutToString({ "cmd", "shift" }, "s"), "⌘⇧s", "cmd+shift+s")
    assertEq(U.shortcutToString({ "ctrl", "alt" }, "f"), "⌃⌥f", "ctrl+alt+f")
    assertEq(U.shortcutToString({}, ""), "", "empty stays empty")
    assertEq(U.shortcutToString({ "cmd" }, "\x0D"), "⌘↩", "cmd+return glyph")
end)

-- ---------- Cleanup ----------

restoreLive()
package.loaded["MenuMaestro"] = nil

local failed = 0
for _, r in ipairs(results) do if not r.pass then failed = failed + 1 end end
local passed = #results - failed
logln(string.format("\n%d/%d scenarios passed", passed, #results))
if logF then logF:close() end
return string.format("%d/%d", passed, #results)
