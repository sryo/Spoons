-- Muse backend: Claude Code CLI in print mode (`claude -p`) with stream-json output.
-- Requires: `claude` on PATH (reuses existing CLI auth, no API key needed).
-- Config:   Muse.config.backends.claudecli = {} -- (no options yet)

local M = require("Muse")
local h = M.helpers

M.config.backends.claudecli = M.config.backends.claudecli or {}

return {
  name = "claudecli",

  available = function()
    local out = hs.execute("command -v claude 2>/dev/null")
    if not out or out == "" then return false, "claude CLI not on PATH" end
    return true
  end,

  stream = function(_, prompt, _, onChunk, onDone, onError)
    local sh = os.getenv("SHELL") or "/bin/zsh"
    return h.newTask(sh,
      { "-l", "-c", "claude -p --output-format=stream-json --verbose" },
      prompt,
      function(chunk)
        for line in chunk:gmatch("[^\r\n]+") do
          local ok, obj = pcall(h.json.decode, line)
          if ok and type(obj) == "table"
             and obj.type == "assistant"
             and obj.message and obj.message.content then
            for _, c in ipairs(obj.message.content) do
              if c.type == "text" and c.text then onChunk(c.text) end
            end
          end
        end
      end,
      onDone, onError)
  end,
}
