-- Descend into a directory by rewriting the palette query. keepOpen = true
-- tells init.lua's runVerb to skip the standard close-then-record path and
-- instead apply the returned directive { rewriteQuery = string } to live
-- state, then refresh. Bumps the directory's visited-dir frecency.

local recents = require("Palette.recents")
local files   = require("Palette.sources.files")

local M = {}
M.id        = "enter"
M.label     = "Enter"
M.needsPrep = false
M.keepOpen  = true

function M.run(item)
    if not item or not item.payload or not item.payload.path then
        return false, "no path"
    end
    local path = item.payload.path
    recents.record("files", path)
    return true, nil, { rewriteQuery = files.abbreviatePath(path) .. "/" }
end

return M
