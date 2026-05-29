-- Spawn the typed command in zsh as a login shell, fire and forget. The
-- palette closes before we get here (init.lua does that in runVerb), so any
-- error is surfaced via hs.alert.

local M = {}
M.id        = "runshell"
M.label     = "Run"
M.needsPrep = false

function M.run(item, _prep)
    if not item or not item.payload or not item.payload.command then
        return false, "no command"
    end
    local task = hs.task.new("/bin/zsh", nil, { "-lc", item.payload.command })
    if not task then return false, "task creation failed" end
    local ok = task:start()
    if not ok then return false, "task start failed" end
    return true, nil
end

return M
