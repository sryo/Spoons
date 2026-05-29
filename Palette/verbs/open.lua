-- Open a filesystem path via /usr/bin/open. Bumps the parent directory's
-- visited-dir frecency so future searches surface it. Returns ok, err.

local recents = require("Palette.recents")

local M = {}
M.id        = "open"
M.label     = "Open"
M.needsPrep = false

function M.run(item)
    if not item or not item.payload or not item.payload.path then
        return false, "no path"
    end
    local path = item.payload.path
    local task = hs.task.new("/usr/bin/open", nil, { path })
    if not task then return false, "task creation failed" end
    if not task:start() then return false, "task start failed" end
    local parent = path:match("(.*)/[^/]+$")
    if parent and parent ~= "" and hs.fs.attributes(parent) then
        recents.record("files", parent)
    end
    return true, nil
end

return M
