-- "Activate" is the default verb for every item. It dispatches by source:
-- for menu items, it calls app:selectMenuItem on the path payload.
-- Returns ok, err.

local M = {}
M.id        = "activate"
M.label     = "Activate"
M.needsPrep = false

local handlers = {}

handlers.menuitems = function(item)
    local p = item.payload or {}
    local app = p.appName and hs.application.find(p.appName) or hs.application.frontmostApplication()
    if not app then return false, "app not found" end
    local ok = app:selectMenuItem(p.path)
    return ok, ok and nil or "menu item not selectable"
end

handlers.apps = function(item)
    local p = item.payload or {}
    local app = p.bundleID and hs.application.find(p.bundleID) or nil
    if not app then return false, "app not found" end
    return app:activate(), nil
end

function M.run(item, _prep)
    if not item then return false, "no item" end
    local h = handlers[item.source]
    if not h then return false, "no handler for source " .. tostring(item.source) end
    return h(item)
end

return M
