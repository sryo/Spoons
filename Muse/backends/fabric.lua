-- Muse backend: Fabric CLI (https://github.com/danielmiessler/fabric).
-- Requires: `fabric` on PATH and configured with a model.
-- Config:   Muse.config.backends.fabric = { pattern = "improve_writing" | nil }
--           When pattern is set, runs `fabric --stream --pattern <name>`.

local M = require("Muse")
local h = M.helpers

M.config.backends.fabric = M.config.backends.fabric or {
  pattern = nil,
}

return {
  name = "fabric",
  guidance = "Install fabric CLI (https://github.com/danielmiessler/fabric)",

  available = function()
    local out = hs.execute("command -v fabric 2>/dev/null")
    if not out or out == "" then return false, "fabric not on PATH" end
    return true
  end,

  stream = function(_, prompt, _, onChunk, onDone, onError)
    local sh = os.getenv("SHELL") or "/bin/zsh"
    local c  = M.config.backends.fabric
    local cmd = "fabric --stream"
    if c.pattern and c.pattern ~= "" then
      cmd = cmd .. " --pattern " .. c.pattern
    end
    return h.newTask(sh, { "-l", "-c", cmd }, prompt, onChunk, onDone, onError)
  end,
}
