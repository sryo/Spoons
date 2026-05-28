-- Shared mutable session state for the Palette. One global instance, mutated
-- on each open/close. Modules import this and read/write directly.

local M = {}

M.open         = false
M.query        = ""
M.items        = {}    -- ranked items for the current query (after matcher)
M.focusedIndex = 1     -- 1-based selection within state.items
M.appName      = ""    -- frontmost app name at open time, for placeholder
M.openedAt     = 0     -- timestamp of last open (for animation timing later)

function M.reset()
    M.open         = false
    M.query        = ""
    M.items        = {}
    M.focusedIndex = 1
    M.appName      = ""
    M.openedAt     = 0
end

return M
