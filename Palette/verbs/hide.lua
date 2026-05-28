-- Hide verb. Currently only meaningful for apps items.

local M = {}
M.id        = "hide"
M.label     = "Hide"
M.needsPrep = false

function M.run(item, _prep)
    if not item then return false, "no item" end
    if item.source ~= "apps" then return false, "hide applies to apps only" end
    local app = hs.application.find((item.payload or {}).bundleID)
    if not app then return false, "app not found" end
    app:hide()
    return true
end

return M
