-- Reveal a path in Finder via `open -R`. Returns ok, err.

local M = {}
M.id        = "reveal"
M.label     = "Reveal in Finder"
M.needsPrep = false

function M.run(item)
    if not item or not item.payload or not item.payload.path then
        return false, "no path"
    end
    local task = hs.task.new("/usr/bin/open", nil, { "-R", item.payload.path })
    if not task then return false, "task creation failed" end
    if not task:start() then return false, "task start failed" end
    return true, nil
end

return M
