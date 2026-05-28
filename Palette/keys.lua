-- Global keyDown eventtap used while the palette is open. Consumes every key
-- so the focused app cannot react. Calls into the supplied handlers for
-- characters and the small set of special keys we care about.

local eventtap = hs.eventtap
local etypes   = eventtap.event.types

local M = {}

-- Keycode → semantic name for special keys we route via dedicated handlers.
local SPECIAL = {
    [123] = "left",
    [124] = "right",
    [125] = "down",
    [126] = "up",
    [36]  = "return",  -- Return
    [76]  = "return",  -- numpad Enter
    [53]  = "escape",
    [51]  = "backspace",
    [48]  = "tab",
    [115] = "home",
    [119] = "end_",
    [117] = "fwddel", -- Fn+Delete / Forward Delete
}

local tap      = nil
local handlers = {}

function M.start(callbacks)
    handlers = callbacks or {}
    if tap then tap:stop() end
    tap = eventtap.new({ etypes.keyDown }, function(event)
        local keyCode = event:getKeyCode()
        local flags   = event:getFlags()
        local special = SPECIAL[keyCode]

        if special then
            local fn = handlers[special]
            if fn then fn(event) end
            return true
        end

        -- Cmd+Backspace is a destructive shortcut (Palette uses it to forget
        -- the focused item from history). Keycode 51 is handled above via the
        -- "backspace" handler — fall through; the handler can inspect flags.

        -- Cmd+digit is a quick-pick into the focused item's verb list.
        if flags.cmd and not flags.ctrl and not flags.alt then
            local c = event:getCharacters() or ""
            if #c == 1 and c:match("[1-9]") then
                if handlers.verbQuickPick then handlers.verbQuickPick(tonumber(c)) end
                return true
            end
        end

        -- Bare digit is a quick-pick into the visible item list (Nth visible row).
        if not flags.cmd and not flags.ctrl and not flags.alt then
            local c = event:getCharacters() or ""
            if #c == 1 and c:match("[1-9]") then
                if handlers.itemQuickPick then handlers.itemQuickPick(tonumber(c)) end
                return true
            end
        end

        -- Don't treat other cmd / ctrl combinations as character input (they're shortcuts).
        if flags.cmd or flags.ctrl then return true end

        local char = event:getCharacters() -- respects shift; capital letters come through correctly
        if char and #char > 0 then
            local b = char:byte(1)
            if b >= 32 and b < 127 then
                if handlers.char then handlers.char(char) end
            end
        end
        return true
    end)
    tap:start()
end

function M.stop()
    if tap then tap:stop(); tap = nil end
    handlers = {}
end

function M.isActive()
    return tap ~= nil
end

return M
