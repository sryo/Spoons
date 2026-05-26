-- Muse backend: Claude Code CLI in print mode (`claude -p`) with stream-json output.
-- Requires: `claude` on PATH (reuses existing CLI auth, no API key needed).
-- Config:   Muse.config.backends.claudecli = {} -- (no options yet)

local M = require("Muse")
local h = M.helpers

M.config.backends.claudecli = M.config.backends.claudecli or {}

return {
  name = "claudecli",
  guidance = "Install Claude Code CLI (claude on PATH)",

  available = function()
    local out = hs.execute("command -v claude 2>/dev/null")
    if not out or out == "" then return false, "claude CLI not on PATH" end
    return true
  end,

  stream = function(_, prompt, history, _, onChunk, onDone, onError)
    local sh = os.getenv("SHELL") or "/bin/zsh"
    -- --strict-mcp-config + empty mcpServers disables MCP entirely. Without this
    -- claude hangs on MCP startup when launched from Hammerspoon (the user's
    -- MCP servers are reachable from an interactive shell but not from hs.task).
    local cmd = "claude -p --output-format=stream-json --verbose --include-partial-messages"
              .. " --strict-mcp-config --mcp-config '{\"mcpServers\":{}}'"
    -- Multi-turn continuity: Muse stashes the session id on the history table
    -- after the first turn. We pass --resume to make claude pick up that
    -- conversation; on the first turn there's nothing to resume, so we skip it.
    if history and history.sessionId then
      cmd = cmd .. " --resume " .. history.sessionId
    end
    return h.newTask(sh,
      { "-l", "-c", cmd },
      prompt,
      function(chunk)
        for line in chunk:gmatch("[^\r\n]+") do
          local ok, obj = pcall(h.json.decode, line)
          if not ok or type(obj) ~= "table" then goto continue end
          if obj.type == "stream_event"
             and obj.event and obj.event.type == "content_block_delta"
             and obj.event.delta and obj.event.delta.type == "text_delta"
             and obj.event.delta.text then
            onChunk(obj.event.delta.text)
          elseif obj.type == "system" and obj.subtype == "init" and obj.session_id and history then
            history.sessionId = obj.session_id
          end
          ::continue::
        end
      end,
      onDone, onError)
  end,
}
