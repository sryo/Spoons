-- AskMuse verb. Hands the focused item's identifying info to Muse as
-- pre-attached text context, then opens Muse so the user can ask anything
-- with that context already loaded. Requires Muse.openWithContext, which
-- Muse exposes as a programmatic entry point.

local M = {}
M.id        = "askmuse"
M.label     = "Ask Muse"
M.needsPrep = false

local function describe(item)
    local lines = {}
    if item.title and item.title ~= "" then lines[#lines + 1] = item.title end
    if item.subtitle and item.subtitle ~= "" and item.subtitle ~= item.title then
        lines[#lines + 1] = item.subtitle
    end
    local p = item.payload or {}
    if p.appName then lines[#lines + 1] = "App: " .. p.appName end
    if p.bundleID then lines[#lines + 1] = "Bundle: " .. p.bundleID end
    return table.concat(lines, "\n")
end

function M.run(item, _prep)
    if not item then return false, "no item" end
    local Muse = package.loaded["Muse"]
    if not Muse or not Muse.openWithContext then
        return false, "Muse.openWithContext not available"
    end
    Muse.openWithContext(describe(item))
    return true
end

return M
