-- Quit verb. For apps items only. Uses :kill() which sends the standard
-- quit Apple Event; the app gets to show "save changes?" dialogs.

local M = {}
M.id        = "quit"
M.label     = "Quit"
M.needsPrep = false

function M.run(item, _prep)
    if not item then return false, "no item" end
    if item.source ~= "apps" then return false, "quit applies to apps only" end
    local app = hs.application.find((item.payload or {}).bundleID)
    if not app then return false, "app not found" end
    app:kill()
    return true
end

return M
