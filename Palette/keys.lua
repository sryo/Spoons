-- Global keyDown eventtap used while the palette is open. Consumes every key
-- so the focused app cannot react. Calls into the supplied handlers for
-- characters and the small set of special keys we care about.

local eventtap = hs.eventtap
local etypes   = eventtap.event.types

local M = {}

-- Some input methods (ABC Extended, U.S. International, several ISO layouts)
-- absorb keys like shift+` as the start of a dead-key composition for typing
-- accented characters (ã, ñ, õ, ...). At the eventtap layer getCharacters()
-- comes back empty for those keys, so we'd never see ~, _, |, etc.
-- Mapping below is US QWERTY shift pairs. Non-US layouts whose unshifted
-- character matches a US key get the same shifted result; layouts that
-- diverge would need their own entries.
local SHIFT_FALLBACK = {
    ["`"] = "~", ["1"] = "!",  ["2"] = "@", ["3"] = "#",
    ["4"] = "$", ["5"] = "%",  ["6"] = "^", ["7"] = "&",
    ["8"] = "*", ["9"] = "(",  ["0"] = ")",
    ["-"] = "_", ["="] = "+",  ["["] = "{", ["]"] = "}",
    ["\\"] = "|", [";"] = ":", ["'"] = "\"",
    [","] = "<", ["."] = ">",  ["/"] = "?",
}

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

        if handlers.onAnyKey then handlers.onAnyKey() end

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
        if (not char or #char == 0) and not flags.cmd and not flags.ctrl then
            -- Dead key (e.g. shift+` on layouts where it's a tilde combiner).
            -- Recover the literal character via the system keymap + shift table.
            local base = hs.keycodes.map[keyCode]
            if base and #base == 1 then
                if flags.shift then
                    char = SHIFT_FALLBACK[base] or base:upper()
                else
                    char = base
                end
            end
        end
        if char and #char > 0 then
            local b = char:byte(1)
            -- Printable ASCII (skip control chars and DEL) or any UTF-8
            -- multibyte start byte. This lets non-US keyboards produce ~, ñ,
            -- á, ¿, etc., which earlier rejected as "non-printable".
            local printable = (b >= 32 and b ~= 127) or b >= 128
            if printable then
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
