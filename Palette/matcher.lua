-- Pure ranking. Combines case-insensitive substring match against title and
-- subtitle with a per-item recency / usage boost. v1 keeps it simple; can be
-- swapped for fuzzy subsequence scoring later without touching callers.

local recents = require("Palette.recents")

local M = {}

-- score returns a number >= 0 for a hit, -1 for miss.
local function matchScore(query, target)
    if not query or query == "" then return 0 end
    if not target or target == "" then return -1 end
    local lq = query:lower()
    local lt = target:lower()
    if lt == lq then return 1000 end
    if lt:sub(1, #lq) == lq then return 500 end
    local pos = lt:find(lq, 1, true)
    if pos then return math.max(0, 200 - pos) end
    return -1
end

function M.rank(items, query)
    local matches = {}
    local emptyQuery = query == ""
    for _, item in ipairs(items) do
        if emptyQuery and item.hideOnEmptyQuery then goto continue end
        do
            local tScore = matchScore(query, item.title)
            local sScore = matchScore(query, item.subtitle or "")
            local matchVal = math.max(tScore, sScore * 0.6)
            local hit = emptyQuery or (matchVal > 0) or (tScore == 0 and sScore == 0)
            if hit then
                local boost = recents.score(item.source, item.id)
                item.fromHistory = boost > 0
                -- For empty query, recency dominates. For non-empty, recency is a
                -- strong tiebreaker (boost / 10 keeps recent items near the top).
                local total
                if emptyQuery then
                    total = boost
                else
                    total = matchVal + boost / 10
                end
                matches[#matches + 1] = { item = item, score = total }
            end
        end
        ::continue::
    end
    table.sort(matches, function(a, b) return a.score > b.score end)
    local out = {}
    for i, m in ipairs(matches) do out[i] = m.item end
    return out
end

-- Exposed for testing.
M._matchScore = matchScore

return M
