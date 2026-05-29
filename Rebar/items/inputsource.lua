-- Current keyboard layout. "U.S." -> "US", "Spanish - ISO" -> "ES", etc.
-- Event-driven via hs.keycodes.inputSourceChanged.

local M = {
    id       = "inputsource",
    side     = "right",
    order    = 75,
    interval = 0,
}

local KNOWN = {
    ["U.S."]            = "US",
    ["U.S. International"] = "US",
    ["British"]         = "UK",
    ["Spanish"]         = "ES",
    ["Spanish - ISO"]   = "ES",
    ["Latin American"]  = "LA",
    ["French"]          = "FR",
    ["French - Numerical"] = "FR",
    ["German"]          = "DE",
    ["Italian"]         = "IT",
    ["Portuguese"]      = "PT",
    ["Dutch"]           = "NL",
}

function M.update()
    local layout = hs.keycodes.currentLayout()
    if not layout or layout == "" then return "" end
    if KNOWN[layout] then return KNOWN[layout] end
    -- Fallback: first two letters uppercased, stripped of punctuation.
    local s = layout:gsub("%W", ""):sub(1, 2):upper()
    return s
end

local _refresh

function M.setup(refresh)
    _refresh = refresh
    hs.keycodes.inputSourceChanged(function()
        if _refresh then _refresh() end
    end)
end

function M.teardown()
    _refresh = nil
end

return M
