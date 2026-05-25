-- Muse backend: Apple Intelligence via the FoundationModels framework (macOS 26+).
-- Stub: delegates to a tiny Swift helper binary that this repo doesn't ship.
--
-- To enable, build a CLI that reads a prompt from stdin and streams tokens to
-- stdout. Minimal recipe (Swift 6, Xcode 26+):
--
--   import Foundation
--   import FoundationModels
--   let session = LanguageModelSession()
--   let prompt = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
--   let stream = session.streamResponse(to: prompt)
--   for try await partial in stream {
--     FileHandle.standardOutput.write(partial.data(using: .utf8)!)
--   }
--
--   swiftc -o muse-foundation muse-foundation.swift
--   mkdir -p ~/.hammerspoon/Muse-helpers && mv muse-foundation ~/.hammerspoon/Muse-helpers/
--
-- Until that binary exists, this backend reports unavailable and is skipped.

local M = require("Muse")
local h = M.helpers

M.config.backends.apple = M.config.backends.apple or {
  helperPath = os.getenv("HOME") .. "/.hammerspoon/Muse-helpers/muse-foundation",
}

return {
  name = "apple",

  available = function()
    local p = M.config.backends.apple.helperPath
    local f = io.open(p, "r")
    if not f then return false, "FoundationModels helper not built (" .. p .. ")" end
    f:close()
    return true
  end,

  stream = function(_, prompt, _, onChunk, onDone, onError)
    return h.newTask(M.config.backends.apple.helperPath, {}, prompt, onChunk, onDone, onError)
  end,
}
