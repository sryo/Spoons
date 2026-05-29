-- Simulator for WanderFocus._focusWindowUnderCursor. Stubs hs.mouse, hs.window,
-- and hs.axuielement so we can drive the focus decision directly without
-- synthesising real mouse events. Driven by tests/wanderfocus/focus.sh.

local L = dofile(hs.configdir .. "/tests/_test_lib.lua")

local LOG_PATH = "/tmp/wanderfocus-focus-sim.log"
local logF = io.open(LOG_PATH, "w")
local function logln(s) if logF then logF:write(s .. "\n") end end

-- Save originals so we can restore them after the sim.
local real = {
    abs        = hs.mouse.absolutePosition,
    curScreen  = hs.mouse.getCurrentScreen,
    focused    = hs.window.focusedWindow,
    visible    = hs.window.visibleWindows,
    sysWide    = hs.axuielement.systemWideElement,
    winElement = hs.axuielement.windowElement,
}
local savedLive = package.loaded["WanderFocus"]

-- Mock state, reset per-scenario.
local state = {}
local function resetState()
    state.mouse           = { x = 0, y = 0 }
    state.screen          = {
        frame = function() return { x = 0, y = 0, w = 1920, h = 1080 } end,
    }
    state.windows         = {}
    state.focused         = nil
    state.obstruction     = false
    state.typing          = false
    state.focusCalls      = {}
    state.axMainCalls     = {}
    state.visibleCallCount = 0
end

local function makeWindow(opts)
    local w = {}
    w._id        = opts.id or 1
    w._app       = opts.app or "TestApp"
    w._frame     = opts.frame or { x = 0, y = 0, w = 400, h = 300 }
    w._screen    = opts.screen or state.screen
    w._visible   = opts.visible ~= false
    w._minimized = opts.minimized or false
    w._standard  = opts.standard ~= false
    w._role      = opts.role or "AXWindow"
    w._subrole   = opts.subrole or "AXStandardWindow"
    function w:frame()       return self._frame end
    function w:screen()      return self._screen end
    function w:application() return { name = function() return w._app end } end
    function w:isVisible()   return self._visible end
    function w:isMinimized() return self._minimized end
    function w:isStandard()  return self._standard end
    function w:role()        return self._role end
    function w:subrole()     return self._subrole end
    function w:id()          return self._id end
    function w:focus()
        table.insert(state.focusCalls, self._id)
        state.focused = self
        return true
    end
    return w
end

-- Install mocks once; reset state between scenarios.
hs.mouse.absolutePosition = function() return state.mouse end
hs.mouse.getCurrentScreen = function() return state.screen end
hs.window.focusedWindow   = function() return state.focused end
hs.window.visibleWindows = function()
    state.visibleCallCount = state.visibleCallCount + 1
    return state.windows
end

hs.axuielement.systemWideElement = function()
    return {
        elementAtPosition = function(_, _)
            if state.obstruction then
                return {
                    pid = function() return nil end,
                    attributeValue = function(_, attr)
                        if attr == "AXRole" then return "AXMenuBar" end
                    end,
                }
            end
            return nil
        end,
        attributeValue = function(_, attr)
            if attr == "AXFocusedUIElement" then
                if state.typing then
                    return { attributeValue = function() return "AXTextField" end }
                end
                return nil
            end
        end,
    }
end

hs.axuielement.windowElement = function(win)
    return {
        setAttributeValue = function(_, attr, _)
            if attr == "AXMain" then
                table.insert(state.axMainCalls, win:id())
            end
        end,
    }
end

local function loadModule()
    package.loaded["WanderFocus"] = nil
    return require("WanderFocus")
end

local results = {}
local function scenario(name, fn)
    resetState()
    local M = loadModule()
    local ok, err = pcall(fn, M)
    table.insert(results, { name = name, pass = ok, err = err })
    if ok then
        logln(string.format("PASS  %s", name))
    else
        logln(string.format("FAIL  %s", name))
        logln("     error: " .. tostring(err))
    end
end

scenario("A: cursor in window focuses it (autoraise)", function(M)
    local winA = makeWindow{ id = 1, frame = { x = 0, y = 0, w = 400, h = 300 } }
    state.windows = { winA }
    state.mouse   = { x = 200, y = 150 }
    M._focusWindowUnderCursor()
    L.assertEq(state.focusCalls[1], 1, "focused winA")
    L.assertEq(#state.axMainCalls, 0, "no AXMain in autoraise mode")
end)

scenario("B: cursor staying in same window short-circuits rescan", function(M)
    local winA = makeWindow{ id = 1, frame = { x = 0, y = 0, w = 400, h = 300 } }
    state.windows = { winA }
    state.mouse   = { x = 200, y = 150 }
    M._focusWindowUnderCursor()
    local callsBefore = state.visibleCallCount
    state.mouse = { x = 210, y = 160 }
    M._focusWindowUnderCursor()
    L.assertEq(state.visibleCallCount, callsBefore, "visibleWindows not called again")
end)

scenario("C: UI obstruction blocks focus", function(M)
    local winA = makeWindow{ id = 1 }
    state.windows     = { winA }
    state.mouse       = { x = 200, y = 150 }
    state.obstruction = true
    M._focusWindowUnderCursor()
    L.assertEq(#state.focusCalls, 0, "no focus while obstruction")
end)

scenario("D: modal currently focused blocks rescan", function(M)
    local winA     = makeWindow{ id = 1, role = "AXWindow", subrole = "AXStandardWindow" }
    local winModal = makeWindow{ id = 2, role = "AXSheet",  subrole = "AXDialog" }
    state.windows = { winA, winModal }
    state.focused = winModal
    state.mouse   = { x = 200, y = 150 }
    M._focusWindowUnderCursor()
    L.assertEq(#state.focusCalls, 0, "no focus while modal owns focus")
end)

scenario("E: cmdPressed gates focus", function(M)
    local winA = makeWindow{ id = 1 }
    state.windows = { winA }
    state.mouse   = { x = 200, y = 150 }
    M._ignoreConditions.cmdPressed = true
    M._focusWindowUnderCursor()
    L.assertEq(#state.focusCalls, 0, "no focus during cmd")
end)

scenario("F: dragging gates focus", function(M)
    local winA = makeWindow{ id = 1 }
    state.windows = { winA }
    state.mouse   = { x = 200, y = 150 }
    M._ignoreConditions.dragging = true
    M._focusWindowUnderCursor()
    L.assertEq(#state.focusCalls, 0, "no focus during drag")
end)

scenario("G: cmd-release grace gate prevents focus", function(M)
    local winA = makeWindow{ id = 1 }
    state.windows = { winA }
    state.mouse   = { x = 200, y = 150 }
    M._ignoreConditions.cmdReleaseGate = true
    M._focusWindowUnderCursor()
    L.assertEq(#state.focusCalls, 0, "no focus in grace period")
end)

scenario("H: ignored-app window is skipped", function(M)
    local winA = makeWindow{ id = 1, app = "Alfred" }
    state.windows = { winA }
    state.mouse   = { x = 200, y = 150 }
    M._focusWindowUnderCursor()
    L.assertEq(#state.focusCalls, 0, "ignored app not focused")
end)

scenario("I: typing prevents cross-window focus switch", function(M)
    local winA = makeWindow{ id = 1, frame = { x = 0,   y = 0, w = 400, h = 300 } }
    local winB = makeWindow{ id = 2, frame = { x = 500, y = 0, w = 400, h = 300 } }
    state.windows = { winA, winB }
    state.focused = winA
    state.mouse   = { x = 700, y = 150 } -- inside winB's adjusted frame
    state.typing  = true
    M._focusWindowUnderCursor()
    L.assertEq(#state.focusCalls, 0, "typing blocks cross-window focus")
end)

scenario("J: mode=autofocus sets AXMain without raising", function(M)
    M.cfg.mode = "autofocus"
    local winA = makeWindow{ id = 1 }
    state.windows = { winA }
    state.mouse   = { x = 200, y = 150 }
    M._focusWindowUnderCursor()
    L.assertEq(#state.focusCalls, 0, "no win:focus() in autofocus")
    L.assertEq(state.axMainCalls[1], 1, "AXMain set on winA")
end)

scenario("K: mode=off short-circuits before any work", function(M)
    M.cfg.mode = "off"
    local winA = makeWindow{ id = 1 }
    state.windows = { winA }
    state.mouse   = { x = 200, y = 150 }
    M._focusWindowUnderCursor()
    L.assertEq(#state.focusCalls, 0, "no focus when off")
    L.assertEq(#state.axMainCalls, 0, "no AXMain when off")
    L.assertEq(state.visibleCallCount, 0, "visibleWindows never called when off")
end)

scenario("L: cursor inside buffer band does not focus", function(M)
    -- Frame (0,0,400,300), buffer 16 -> adjusted (16,16,368,268).
    local winA = makeWindow{ id = 1, frame = { x = 0, y = 0, w = 400, h = 300 } }
    state.windows = { winA }
    state.mouse   = { x = 5, y = 5 } -- inside frame, outside adjusted
    M._focusWindowUnderCursor()
    L.assertEq(#state.focusCalls, 0, "buffer zone skipped")
end)

scenario("M: start/stop manages watchers", function(M)
    M.start()
    local mw = M._mouseWatcher
    local sw = M._scrollWatcher
    local dw = M._dragWatcher
    local cw = M._cmdWatcher
    M.stop() -- always stop before asserting, so failed asserts don't leak taps.
    L.assertEq(mw ~= nil, true, "mouseWatcher created on start")
    L.assertEq(sw ~= nil, true, "scrollWatcher created on start")
    L.assertEq(dw ~= nil, true, "dragWatcher created on start")
    L.assertEq(cw ~= nil, true, "cmdWatcher created on start")
    L.assertEq(M._mouseWatcher,  nil, "mouseWatcher cleared on stop")
    L.assertEq(M._scrollWatcher, nil, "scrollWatcher cleared on stop")
    L.assertEq(M._dragWatcher,   nil, "dragWatcher cleared on stop")
    L.assertEq(M._cmdWatcher,    nil, "cmdWatcher cleared on stop")
end)

hs.mouse.absolutePosition        = real.abs
hs.mouse.getCurrentScreen        = real.curScreen
hs.window.focusedWindow          = real.focused
hs.window.visibleWindows         = real.visible
hs.axuielement.systemWideElement = real.sysWide
hs.axuielement.windowElement     = real.winElement
package.loaded["WanderFocus"]    = savedLive

local failed = 0
for _, r in ipairs(results) do if not r.pass then failed = failed + 1 end end
local passed = #results - failed
logln(string.format("\n%d/%d scenarios passed", passed, #results))
if logF then logF:close() end
return string.format("%d/%d", passed, #results)
