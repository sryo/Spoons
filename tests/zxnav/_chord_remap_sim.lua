-- Simulator for ZXNav's chord-remap state machine: mapping lookup,
-- space+key → action key event posting, modifier rejection, multi-key tracking,
-- and clean space-pass-through when no nav key was pressed.
--
-- ZXNav returns a module table (`module.start()`). We stub the side-effect
-- APIs (eventtap.new, hotkey.bind, canvas.new, screen.watcher.new, etc.),
-- call module.start() against the stubs, capture the keyDown/keyUp callbacks,
-- and reach handleKeyDown/handleKeyUp via debug.getupvalue.

local LOG_PATH = "/tmp/zxnav-sim.log"
local logF = io.open(LOG_PATH, "w")
local function logln(s) if logF then logF:write(s .. "\n") end end

local L = dofile(hs.configdir .. "/tests/_test_lib.lua")
local deepUpvals, assertEq = L.deepUpvals, L.assertEq

-- ---------- Live values ----------

local saved = {
    eventtapNew         = hs.eventtap.new,
    newKeyEvent         = hs.eventtap.event.newKeyEvent,
    canvasNew           = hs.canvas.new,
    screenPrimary       = hs.screen.primaryScreen,
    screenWatcherNew    = hs.screen.watcher.new,
    distNotifNew        = hs.distributednotifications.new,
    hotkeyBind          = hs.hotkey.bind,
    hostStyle           = hs.host.interfaceStyle,
    timerDoAfter        = hs.timer.doAfter,
    alertShow           = hs.alert.show,
}

local capturedKeyDownCb
local capturedKeyUpCb
local postedEvents -- list of {mods, key, isDown}

local function fakeCanvas()
    local elements = {}
    return setmetatable({}, {
        __index = function(t, k)
            if type(k) == "number" then elements[k] = elements[k] or {}; return elements[k] end
            if k == "delete" or k == "show" or k == "hide" or k == "level" or k == "behavior" then
                return function() end
            end
            if k == "appendElements" then return function() end end
            return function() end
        end,
        __newindex = function(_, k, v)
            if type(k) == "number" then elements[k] = v end
        end,
        __len = function() return #elements end,
    })
end

local function installStubs()
    capturedKeyDownCb = nil
    capturedKeyUpCb   = nil
    postedEvents      = {}

    hs.eventtap.new = function(types, callback)
        -- ZXNav installs separate taps for keyDown and keyUp.
        local kind = nil
        for _, t in ipairs(types or {}) do
            if t == hs.eventtap.event.types.keyDown then kind = "down" end
            if t == hs.eventtap.event.types.keyUp   then kind = "up"   end
        end
        if kind == "down" then capturedKeyDownCb = callback
        elseif kind == "up" then capturedKeyUpCb = callback end
        -- Real eventtap :start() returns self (chainable); mirror that so
        -- callers writing `module._tap = hs.eventtap.new(...):start()` end up
        -- with the tap object, not a boolean.
        local tap = {}
        tap.start = function() return tap end
        tap.stop  = function() end
        tap.isEnabled = function() return true end
        return tap
    end

    hs.eventtap.event.newKeyEvent = function(mods, key, isDown)
        return { post = function() table.insert(postedEvents, { mods = mods, key = key, isDown = isDown }) end }
    end

    hs.canvas.new = function(_) return fakeCanvas() end
    hs.screen.primaryScreen = function()
        return { frame = function() return { x = 0, y = 0, w = 1440, h = 900 } end }
    end
    hs.screen.watcher.new = function(_) return { start = function() end, stop = function() end } end
    hs.distributednotifications.new = function(_) return { start = function() end, stop = function() end } end
    hs.hotkey.bind = function(_, _, _) return { delete = function() end } end
    hs.host.interfaceStyle = function() return "Light" end
    hs.timer.doAfter = function(_, _) return { stop = function() end } end
    hs.alert.show = function() end
end

local function restoreLive()
    hs.eventtap.new                  = saved.eventtapNew
    hs.eventtap.event.newKeyEvent    = saved.newKeyEvent
    hs.canvas.new                    = saved.canvasNew
    hs.screen.primaryScreen          = saved.screenPrimary
    hs.screen.watcher.new            = saved.screenWatcherNew
    hs.distributednotifications.new  = saved.distNotifNew
    hs.hotkey.bind                   = saved.hotkeyBind
    hs.host.interfaceStyle           = saved.hostStyle
    hs.timer.doAfter                 = saved.timerDoAfter
    hs.alert.show                    = saved.alertShow
end

local function freshModule()
    package.loaded["ZXNav"] = nil
    local mod = require("ZXNav")
    mod.start()
    assert(type(capturedKeyDownCb) == "function", "keyDown eventtap callback not captured")
    assert(type(capturedKeyUpCb)   == "function", "keyUp eventtap callback not captured")
    local U = deepUpvals(capturedKeyDownCb)
    for k, v in pairs(deepUpvals(capturedKeyUpCb)) do
        if U[k] == nil then U[k] = v end
    end
    return capturedKeyDownCb, capturedKeyUpCb, U
end

-- ---------- Mock key events ----------

local function keyEvent(keyName, flags)
    local kc = hs.keycodes.map[keyName] or 0
    return {
        getKeyCode = function() return kc end,
        getFlags   = function() return flags or {} end,
    }
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


local function findPost(key, isDown)
    for _, p in ipairs(postedEvents) do
        if p.key == key and p.isDown == isDown then return p end
    end
    return nil
end

-- ---------- Scenarios ----------

scenario("findMapping returns the inner-ring entry for Z and nil for unmapped keys", function()
    local _, _, U = freshModule()
    assert(type(U.findMapping) == "function", "findMapping reachable")
    local m = U.findMapping("z")
    assert(m, "Z should be mapped")
    assertEq(m[1], "Z", "key name in mapping")
    assertEq(m[2], "Home", "Z maps to Home")
    assertEq(U.findMapping("q"), nil, "Q is unmapped")
end)

scenario("space + Z posts a Home keyDown (no modifiers)", function()
    local down, _, _ = freshModule()
    down(keyEvent("space"))  -- press space to enter modifier mode
    down(keyEvent("z"))      -- press Z while space held
    local home = findPost("home", true)
    assert(home, "expected a 'home' keyDown post")
    -- No modifiers.
    assertEq(next(home.mods), nil, "home post should have empty modifier set")
end)

scenario("space pressed while cmd already held does NOT enter modifier mode", function()
    local down, _, U = freshModule()
    -- User holds Cmd then taps Space: real OS delivers a 'space' keyDown with
    -- flags.cmd=true. ZXNav's handler must early-return GO so the system gets
    -- a normal cmd+space (e.g. Spotlight) without ZXNav consuming the event.
    local before = #postedEvents
    local result = down(keyEvent("space", { cmd = true }))
    assertEq(result, false, "handler returns GO when space arrives with cmd held")
    assertEq(#postedEvents, before, "no synthetic key event posted")
    -- After the call, modifierDown should still be false (no modifier mode).
    -- Reach it via debug.getupvalue on handleKeyDown.
    local function getUv(fn, name)
        local i = 1
        while true do
            local n, v = debug.getupvalue(fn, i)
            if not n then return nil end
            if n == name then return v end
            i = i + 1
        end
    end
    assertEq(getUv(down, "modifierDown"), false, "modifier mode not entered")
end)

scenario("multiple chord keys tracked independently; releasing one does not affect the other", function()
    local down, up, U = freshModule()
    down(keyEvent("space"))
    down(keyEvent("z"))           -- posts home DOWN
    down(keyEvent("x"))           -- posts end DOWN
    -- Both should be tracked in heldMappedKeys.
    assert(U.heldMappedKeys["z"], "z held")
    assert(U.heldMappedKeys["x"], "x held")
    -- Release Z only.
    up(keyEvent("z"))
    -- home UP should have been posted; x's mapping (end) should still be marked held.
    assert(findPost("home", false), "expected 'home' keyUp after releasing Z")
    -- Re-walk because state may have been replaced.
    assertEq(U.heldMappedKeys["z"], nil, "z no longer held")
    assert(U.heldMappedKeys["x"], "x still held after releasing Z")
end)

scenario("space released alone (no nav key pressed) yields a clean space keystroke deferred", function()
    -- Module's handleKeyUp defers the synthesized space via hs.timer.doAfter(0, ...).
    -- Capture the deferred fn through our timer stub so we can invoke it manually
    -- and verify what it posts.
    local deferred
    hs.timer.doAfter = function(_, fn) deferred = fn; return { stop = function() end } end
    -- Also stub hs.eventtap.keyStroke (used inside the deferred function).
    local strokeCalls = {}
    local origKeyStroke = hs.eventtap.keyStroke
    hs.eventtap.keyStroke = function(mods, key, delay) table.insert(strokeCalls, { mods = mods, key = key }) end

    local down, up, _ = freshModule()
    down(keyEvent("space"))      -- enter modifier mode
    up(keyEvent("space"))        -- release without pressing any nav key
    assert(type(deferred) == "function", "expected a deferred space keystroke to be scheduled")
    deferred()
    assertEq(#strokeCalls, 1, "exactly one keyStroke synthesised")
    assertEq(strokeCalls[1].key, "space", "space key synthesised")

    hs.eventtap.keyStroke = origKeyStroke
end)

-- ---------- Cleanup ----------

restoreLive()
package.loaded["ZXNav"] = nil

local failed = 0
for _, r in ipairs(results) do if not r.pass then failed = failed + 1 end end
local passed = #results - failed
logln(string.format("\n%d/%d scenarios passed", passed, #results))
if logF then logF:close() end
return string.format("%d/%d", passed, #results)
