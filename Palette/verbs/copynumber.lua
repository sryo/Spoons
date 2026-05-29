-- Copy the calculator result to the system clipboard. Returns ok, err.

local M = {}
M.id        = "copynumber"
M.label     = "Copy"
M.needsPrep = false

function M.run(item, _prep)
    if not item or not item.payload then return false, "no item" end
    local v = item.payload.formatted or tostring(item.payload.value)
    if not v then return false, "no value" end
    hs.pasteboard.setContents(v)
    return true, nil
end

return M
