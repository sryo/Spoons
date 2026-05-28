-- Muse backend: Fabric CLI (https://github.com/danielmiessler/fabric).
-- Requires: `fabric` on PATH and configured with a model.
-- Config:   Muse.config.backends.fabric = { pattern = "improve_writing" | nil }
--           When pattern is set, runs `fabric --stream --pattern <name>`.
--
-- Muse.config.systemPrompt is intentionally NOT applied here. Fabric patterns
-- are themselves the system prompt; stacking Muse's house style on top would
-- fight whatever the pattern is trying to do. Write a Muse-flavored fabric
-- pattern if you want both.

local M = require("Muse")
local h = M.helpers

M.config.backends.fabric = M.config.backends.fabric or {
  pattern = nil,
}

return {
  name = "fabric",
  guidance = "Install fabric CLI (https://github.com/danielmiessler/fabric)",

  available = function()
    return h.commandOnPath("fabric")
  end,

  stream = function(_, prompt, _, _, onChunk, onDone, onError)
    local sh = os.getenv("SHELL") or "/bin/zsh"
    local c  = M.config.backends.fabric
    local cmd = "fabric --stream"
    if c.pattern and c.pattern ~= "" then
      cmd = cmd .. " --pattern " .. c.pattern
    end
    return h.newTask(sh, { "-l", "-c", cmd }, prompt, onChunk, onDone, onError)
  end,
}
