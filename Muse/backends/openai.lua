-- Muse backend: OpenAI chat completions (SSE via curl).
-- Requires: OPENAI_API_KEY in env.
-- Config:   Muse.config.backends.openai = { model = "..." }

local M = require("Muse")
local h = M.helpers

M.config.backends.openai = M.config.backends.openai or {
  model = "gpt-4o-mini",
}

return {
  name = "openai",

  available = function()
    if not os.getenv("OPENAI_API_KEY") then
      return false, "OPENAI_API_KEY not set"
    end
    return true
  end,

  stream = function(_, prompt, history, onChunk, onDone, onError)
    local c = M.config.backends.openai
    local messages = {}
    for _, m in ipairs(history or {}) do table.insert(messages, m) end
    table.insert(messages, { role = "user", content = prompt })
    local body = h.json.encode({
      model    = c.model,
      stream   = true,
      messages = messages,
    })
    local args = {
      "-N", "-s", "--no-buffer", "https://api.openai.com/v1/chat/completions",
      "-H", "authorization: Bearer " .. os.getenv("OPENAI_API_KEY"),
      "-H", "content-type: application/json",
      "-d", body,
    }
    return h.newTask("/usr/bin/curl", args, nil, function(chunk)
      h.parseSSE(chunk, function(line)
        if not line:match("^data: ") then return end
        local payload = line:sub(7)
        if payload == "[DONE]" then return end
        local ok, obj = pcall(h.json.decode, payload)
        if not ok or type(obj) ~= "table" or not obj.choices then return end
        local d = obj.choices[1] and obj.choices[1].delta
        if d and d.content then onChunk(d.content) end
      end)
    end, onDone, onError)
  end,
}
