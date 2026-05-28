-- Running apps source. Lists apps with at least one visible window and
-- exposes them as items with the standard verbs.

local M = {}
M.id = "apps"

local SELF = "Hammerspoon"

function M.list()
    local items = {}
    for _, app in ipairs(hs.application.runningApplications()) do
        local name = app:name()
        local bundleID = app:bundleID()
        if name and bundleID and name ~= SELF then
            local wins = app:visibleWindows() or {}
            if #wins > 0 then
                local icon
                pcall(function() icon = hs.image.imageFromAppBundle(bundleID) end)
                items[#items + 1] = {
                    id          = "app:" .. bundleID,
                    title       = name,
                    subtitle    = string.format("%d window%s", #wins, #wins == 1 and "" or "s"),
                    icon        = icon,
                    source      = M.id,
                    payload     = { bundleID = bundleID, pid = app:pid(), appName = name },
                    defaultVerb = "activate",
                    verbs       = { "activate", "hide", "quit", "askmuse" },
                }
            end
        end
    end
    return items, nil
end

return M
