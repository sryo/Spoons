-- Launch verb. For installed-but-not-running apps. Uses bundle id so renamed
-- or moved bundles still launch.

local M = {}
M.id        = "launch"
M.label     = "Launch"
M.needsPrep = false

function M.run(item, _prep)
    if not item then return false, "no item" end
    if item.source ~= "installedapps" then
        return false, "launch applies to installed apps only"
    end
    local bundleID = (item.payload or {}).bundleID
    if not bundleID then return false, "missing bundle id" end
    local ok = hs.application.launchOrFocusByBundleID(bundleID)
    return ok, ok and nil or "could not launch"
end

return M
