local keycodes = require("hs.keycodes")

local M = {}

local aliases = {
    enter = "return",
    esc = "escape",
    back = "backspace",
    del = "delete",
    arrowup = "up", arrowdown = "down", arrowleft = "left", arrowright = "right",
    pgup = "pageup", pgdn = "pagedown",
}

local extra = {
    [" "] = "space",
    ["\n"] = "return",
}

function M.normalize(name)
    if not name then return nil end
    local k = tostring(name):lower()
    k = extra[k] or aliases[k] or k
    if keycodes.map[k] then return k end
    return nil
end

local validMods = { shift = true, ctrl = true, cmd = true, alt = true, fn = true }

function M.normalizeMods(mods)
    if type(mods) ~= "table" then return {} end
    local out = {}
    for _, m in ipairs(mods) do
        local v = tostring(m):lower()
        if v == "option" then v = "alt" end
        if v == "control" then v = "ctrl" end
        if v == "command" or v == "meta" then v = "cmd" end
        if validMods[v] then out[#out + 1] = v end
    end
    return out
end

return M
