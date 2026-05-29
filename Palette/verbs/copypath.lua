-- Copy a path to the system clipboard. Returns ok, err.

local M = {}
M.id        = "copypath"
M.label     = "Copy Path"
M.needsPrep = false

function M.run(item)
    if not item or not item.payload or not item.payload.path then
        return false, "no path"
    end
    hs.pasteboard.setContents(item.payload.path)
    return true, nil
end

return M
