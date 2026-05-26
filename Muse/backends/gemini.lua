-- Muse backend: Google Gemini generateContent (SSE via curl).
-- Requires: GEMINI_API_KEY (or GOOGLE_API_KEY) in env.
-- Config:   Muse.config.backends.gemini = { model = "..." }

local M = require("Muse")
local h = M.helpers

M.config.backends.gemini = M.config.backends.gemini or {
  model = "gemini-2.5-flash",
}

local function apiKey()
  return os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")
end

return {
  name = "gemini",
  guidance = "Set GEMINI_API_KEY (or GOOGLE_API_KEY) in your shell env",

  available = function()
    if not apiKey() then
      return false, "GEMINI_API_KEY not set"
    end
    return true
  end,

  stream = function(_, prompt, history, onChunk, onDone, onError)
    local c = M.config.backends.gemini
    local contents = {}
    for _, m in ipairs(history or {}) do
      local role = m.role == "assistant" and "model" or "user"
      table.insert(contents, { role = role, parts = { { text = m.content } } })
    end
    table.insert(contents, { role = "user", parts = { { text = prompt } } })
    local body = h.json.encode({ contents = contents })
    local url  = "https://generativelanguage.googleapis.com/v1beta/models/"
              .. c.model .. ":streamGenerateContent?alt=sse"
    local args = {
      "-N", "-s", "--no-buffer", url,
      "-H", "x-goog-api-key: " .. apiKey(),
      "-H", "content-type: application/json",
      "-d", body,
    }
    return h.newTask("/usr/bin/curl", args, nil, function(chunk)
      h.parseSSE(chunk, function(line)
        if not line:match("^data: ") then return end
        local payload = line:sub(7)
        local ok, obj = pcall(h.json.decode, payload)
        if not ok or type(obj) ~= "table" or not obj.candidates then return end
        local parts = obj.candidates[1]
                  and obj.candidates[1].content
                  and obj.candidates[1].content.parts
        if not parts then return end
        for _, p in ipairs(parts) do
          if p.text then onChunk(p.text) end
        end
      end)
    end, onDone, onError)
  end,
}
