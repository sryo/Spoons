-- Muse backend: Anthropic Messages API (SSE via curl).
-- Requires: ANTHROPIC_API_KEY in env.
-- Config:   Muse.config.backends.claude = { model = "...", maxTokens = N }

local M = require("Muse")
local h = M.helpers

M.config.backends.claude = M.config.backends.claude or {
  model     = "claude-sonnet-4-6",
  maxTokens = 1024,
}

return {
  name = "claude",
  multimodal = true,
  guidance = "Get key at console.anthropic.com/settings/keys, then export ANTHROPIC_API_KEY=… in ~/.zshrc",

  available = function()
    if not os.getenv("ANTHROPIC_API_KEY") then
      return false, "ANTHROPIC_API_KEY not set"
    end
    return true
  end,

  stream = function(_, prompt, history, attachments, onChunk, onDone, onError)
    local c = M.config.backends.claude
    local messages = {}
    for _, m in ipairs(history or {}) do table.insert(messages, m) end
    local userContent = prompt
    if attachments and #attachments > 0 then
      userContent = {}
      for _, a in ipairs(attachments) do
        table.insert(userContent, {
          type = "image",
          source = { type = "base64", media_type = a.mime, data = a.base64 },
        })
      end
      table.insert(userContent, { type = "text", text = prompt })
    end
    table.insert(messages, { role = "user", content = userContent })
    local payload = {
      model      = c.model,
      max_tokens = c.maxTokens,
      stream     = true,
      messages   = messages,
    }
    local sp = h.systemPrompt("claude")
    if sp and sp ~= "" then payload.system = sp end
    local body = h.json.encode(payload)
    local args = {
      "-N", "-s", "--no-buffer", "https://api.anthropic.com/v1/messages",
      "-H", "x-api-key: " .. os.getenv("ANTHROPIC_API_KEY"),
      "-H", "anthropic-version: 2023-06-01",
      "-H", "content-type: application/json",
      "-d", body,
    }
    return h.newTask("/usr/bin/curl", args, nil, function(chunk)
      h.parseSSE(chunk, function(line)
        if not line:match("^data: ") then return end
        local payload = line:sub(7)
        if payload == "[DONE]" then return end
        local ok, obj = pcall(h.json.decode, payload)
        if not ok or type(obj) ~= "table" then return end
        if obj.type == "content_block_delta" and obj.delta and obj.delta.text then
          onChunk(obj.delta.text)
        end
      end)
    end, onDone, onError)
  end,
}
