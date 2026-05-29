-- Shared session state. One stage at a time is active; advancing to verb /
-- prep pushes the current frame onto state.history so escape / shift-tab can
-- walk back.

local M = {}

M.open         = false
M.appName      = ""
M.openedAt     = 0

-- Current stage frame.
M.stage        = "noun"   -- "noun" | "verb" | "prep"
M.query        = ""        -- this stage's input buffer
M.caret        = 0         -- caret position inside query (0..utf8.len(query))
M.raw          = {}        -- unfiltered items for this stage
M.items        = {}        -- ranked items for state.query
M.focused      = 1         -- 1-based index into items
M.scrollOffset = 0         -- how many items at the top are scrolled off-screen
M.hovered      = nil       -- mouse-hover row index (independent of focused)

-- Set when stage > "noun". The chosen noun for the verb stage.
M.selectedItem = nil
-- Set when stage == "prep". The chosen verb.
M.selectedVerb = nil

-- Stack of {stage, query, raw, items, focused, selectedItem, selectedVerb}
-- pushed on advance, popped on back.
M.history      = {}

function M.reset()
    M.open         = false
    M.appName      = ""
    M.openedAt     = 0
    M.stage        = "noun"
    M.query        = ""
    M.caret        = 0
    M.raw          = {}
    M.items        = {}
    M.focused      = 1
    M.scrollOffset = 0
    M.hovered      = nil
    M.selectedItem = nil
    M.selectedVerb = nil
    M.history      = {}
end

return M
