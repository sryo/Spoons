-- Diagnostic runner for the Muse HUD text/cursor behaviour.
--
-- Reaches Muse's module-locals via the debug.getupvalue chain rooted at
-- Muse.start. Drives the test by directly mutating `state.buffer` and calling
-- `rebuildInput()` (plus startCursorBlink + updateReadyState to mirror what
-- onInputKey would do). No synthesised keystrokes, no dependence on the HUD
-- staying focused — see feedback_hud_test_direct_state.md for why.
--
-- For each character in MUSE_TEST.testString we:
--   • append the char to state.buffer
--   • call rebuildInput(), startCursorBlink(), updateReadyState() — same
--     side-effects as the printable-input branch of onInputKey
--   • wait stepDelay seconds for the canvas to redraw
--   • snapshot canvas frame, c[2].frame (input), c[7].frame (cursor),
--     full buffer + last char, and save a PNG of the HUD region
--
-- Writes /tmp/muse-text-cursor-test.{json,txt,log} and touches a .done flag.

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

local Muse = package.loaded["Muse"]
assert(Muse, "Muse module not loaded — uncomment require('Muse') in init.lua and reload")

local startU = upvals(Muse.start)
assert(type(startU.onFlags) == "function", "could not reach onFlags upvalue")
local flagsU = upvals(startU.onFlags)
local state   = flagsU.state
local openFn  = flagsU.open
local closeFn = flagsU.close
assert(type(state) == "table",      "could not find state upvalue")
assert(type(openFn) == "function",  "could not find open upvalue")
assert(type(closeFn) == "function", "could not find close upvalue")

local openU = upvals(openFn)
local rebuildInput     = openU.rebuildInput
local startCursorBlink = openU.startCursorBlink
local onInputKey       = openU.onInputKey
assert(type(rebuildInput)     == "function", "could not reach rebuildInput")
assert(type(startCursorBlink) == "function", "could not reach startCursorBlink")
assert(type(onInputKey)       == "function", "could not reach onInputKey")
local updateReadyState = upvals(onInputKey).updateReadyState
assert(type(updateReadyState) == "function", "could not reach updateReadyState")

local cfg = _G.MUSE_TEST or {}
local TEST_STRING = cfg.testString or "the quick brown fox jumps over the lazy dog 123!"
local STEP_DELAY  = cfg.stepDelay  or 0.05
local OPEN_SETTLE = cfg.openSettle or 0.25

local OUT_JSON    = "/tmp/muse-text-cursor-test.json"
local OUT_SUMMARY = "/tmp/muse-text-cursor-test.txt"
local OUT_LOG     = "/tmp/muse-text-cursor-test.log"
local DONE_FLAG   = "/tmp/muse-text-cursor-test.done"
local SHOT_DIR    = "/tmp"

local logF = io.open(OUT_LOG, "w")
local function log(msg)
    if logF then logF:write(os.date("%H:%M:%S ") .. msg .. "\n"); logF:flush() end
end

os.remove(OUT_JSON)
os.remove(OUT_SUMMARY)
os.remove(DONE_FLAG)
for f in hs.fs.dir(SHOT_DIR) do
    if f:match("^muse%-test%-%d+%.png$") then os.remove(SHOT_DIR .. "/" .. f) end
end

if state.open then closeFn() end
openFn()

-- Stop the dismissTap for the duration of the test so an environmental click
-- can't kill the HUD mid-run. It's restarted at finish (or on the abort path).
local dismissTapRestored = false
local function restoreDismissTap()
    if dismissTapRestored then return end
    dismissTapRestored = true
    if state.dismissTap then pcall(function() state.dismissTap:start() end) end
end
if state.dismissTap then pcall(function() state.dismissTap:stop() end) end

local records = {}

local function frameCopy(f)
    if not f then return nil end
    return { x = f.x, y = f.y, w = f.w, h = f.h }
end

local function capture(idx, char)
    local c = state.canv
    if not c then
        log(string.format("[muse-test] canvas missing at idx %d", idx))
        return false
    end
    local cf       = c:frame()
    local inputF   = frameCopy(c[2].frame)
    local cursorF  = frameCopy(c[7].frame)
    local shotPath = string.format("%s/muse-test-%03d.png", SHOT_DIR, idx)

    local scr = hs.screen.mainScreen()
    for _, s in ipairs(hs.screen.allScreens()) do
        local sf = s:fullFrame()
        if cf.x >= sf.x and cf.x < sf.x + sf.w and cf.y >= sf.y and cf.y < sf.y + sf.h then
            scr = s; break
        end
    end
    local ok, snap = pcall(function() return scr:snapshot({ x = cf.x, y = cf.y, w = cf.w, h = cf.h }) end)
    if ok and snap then pcall(function() snap:saveToFile(shotPath) end) end

    local buf = state.buffer or ""
    local lastChar = ""
    if #buf > 0 then
        local lastOff = utf8.offset(buf, -1) or 1
        lastChar = buf:sub(lastOff)
    end
    local rec = {
        index        = idx,
        char         = char,
        bufferLastCh = lastChar,
        buffer       = buf,
        bufferLen    = utf8.len(buf) or #buf,
        canvasFrame  = frameCopy(cf),
        inputFrame   = inputF,
        cursorFrame  = cursorF,
        cursorOn     = state.cursorOn and true or false,
        statusKind   = state.statusKind,
        screenshot   = shotPath,
    }
    records[#records + 1] = rec
    log(string.format(
        "[%03d] typed='%s' last='%s' buf=%3d  in(x=%.1f,y=%.1f,w=%.1f,h=%.1f)  cur(x=%.1f,y=%.1f,w=%.1f,h=%.1f)",
        idx, char, lastChar, rec.bufferLen,
        inputF.x, inputF.y, inputF.w, inputF.h,
        cursorF.x, cursorF.y, cursorF.w, cursorF.h))
    return true
end

local function finish(reason)
    restoreDismissTap()
    closeFn()

    local jf = io.open(OUT_JSON, "w")
    jf:write(hs.json.encode(records, true))
    jf:close()

    local sf = io.open(OUT_SUMMARY, "w")
    sf:write(string.format("Muse text/cursor capture — %d records, test string %q (%s)\n\n",
                            #records, TEST_STRING, reason or "completed"))
    sf:write("idx  typed last  buf-len  input(x,y,w,h)                       cursor(x,y,w,h)                      buffer\n")
    sf:write("---  ----- ----  -------  ------------------------------       ------------------------------       ------\n")
    for _, r in ipairs(records) do
        sf:write(string.format(
            "%3d  '%s'   '%s'   %3d      (%6.1f,%6.1f,%6.1f,%6.1f)       (%6.1f,%6.1f,%6.1f,%6.1f)       %q\n",
            r.index, r.char, r.bufferLastCh, r.bufferLen,
            r.inputFrame.x, r.inputFrame.y, r.inputFrame.w, r.inputFrame.h,
            r.cursorFrame.x, r.cursorFrame.y, r.cursorFrame.w, r.cursorFrame.h,
            r.buffer))
    end
    sf:close()

    local f = io.open(DONE_FLAG, "w"); f:write(reason or "done"); f:close()
    log(string.format("[muse-test] wrote %d records to %s (%s)", #records, OUT_JSON, reason or "done"))
end

hs.timer.doAfter(OPEN_SETTLE, function()
    if not state.open or not state.canv then
        log("[muse-test] Muse did not open — aborting")
        return finish("error: open failed")
    end

    capture(0, "")

    local chars = {}
    for _, cp in utf8.codes(TEST_STRING) do
        chars[#chars + 1] = utf8.char(cp)
    end

    local function stepN(n)
        if n > #chars then return finish() end
        if not state.open or not state.canv then
            return finish(string.format("error: HUD closed at step %d", n))
        end
        local ch = chars[n]
        state.buffer = state.buffer .. ch
        local ok, err = pcall(function()
            rebuildInput()
            startCursorBlink()
            updateReadyState()
        end)
        if not ok then
            log(string.format("stepN %d rebuild ERROR: %s", n, tostring(err)))
            return finish("error: rebuild failed at step " .. n)
        end
        hs.timer.doAfter(STEP_DELAY, function()
            local cok, cerr = pcall(capture, n, ch)
            if not cok then log(string.format("stepN %d capture ERROR: %s", n, tostring(cerr))) end
            stepN(n + 1)
        end)
    end
    stepN(1)
end)

return "started"
