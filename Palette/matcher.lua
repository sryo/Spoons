-- Subsequence-based fuzzy matcher. Each character of the lowercased query must
-- appear in the lowercased title in order; the matcher returns a score plus
-- the matched character indices (1-based, into the original title) so the
-- renderer can bold the hit glyphs. Subtitle is matched too but with a lower
-- weight and without producing positions.
--
-- Items with bypassMatcher = true skip scoring entirely and ride at a fixed
-- mid-high score (used by synthetic sources like calc and shellrunner).

local recents = require("Palette.recents")

local M = {}

local BYPASS_SCORE = 600

local function isWordBoundary(prevChar, ch)
    if not prevChar then return true end
    if prevChar == " " or prevChar == "/" or prevChar == "."
        or prevChar == "_" or prevChar == "-" then return true end
    -- camelCase: lower -> upper transition in the original (un-lowered) title.
    if prevChar >= "a" and prevChar <= "z" and ch >= "A" and ch <= "Z" then
        return true
    end
    return false
end

-- fuzzyMatch returns score, positions or nil if no subsequence hit.
local function fuzzyMatch(query, title)
    if query == "" then return 0, {} end
    if not title or title == "" then return nil end

    local q = query:lower()
    local t = title:lower()
    local titleChars, lowerChars = {}, {}
    for i = 1, #title do
        titleChars[i] = title:sub(i, i)
        lowerChars[i] = t:sub(i, i)
    end
    local positions = {}
    local score = 0
    local ti = 1
    local consecutive = 0
    local firstMatchIdx = nil
    local lastMatchIdx = nil

    for qi = 1, #q do
        local qc = q:sub(qi, qi)
        local found = false
        while ti <= #lowerChars do
            if lowerChars[ti] == qc then
                positions[#positions + 1] = ti
                local prev = (ti > 1) and titleChars[ti - 1] or nil
                local bonus = 0
                if ti == 1 then bonus = bonus + 25 end
                if isWordBoundary(prev, titleChars[ti]) then bonus = bonus + 15 end
                if lastMatchIdx and (ti - lastMatchIdx) == 1 then
                    consecutive = consecutive + 1
                    bonus = bonus + 8 + consecutive * 2
                else
                    consecutive = 0
                end
                score = score + 10 + bonus
                firstMatchIdx = firstMatchIdx or ti
                lastMatchIdx = ti
                ti = ti + 1
                found = true
                break
            end
            ti = ti + 1
        end
        if not found then return nil end
    end

    -- Penalise long total spans (matched range relative to title length).
    local span = lastMatchIdx - firstMatchIdx + 1
    local spanPenalty = math.floor((span - #q) * 1.5)
    score = score - spanPenalty

    -- Penalise matches that begin deep in the title.
    if firstMatchIdx > 1 then
        score = score - math.min(firstMatchIdx - 1, 20)
    end

    -- Exact case-insensitive equality wins decisively.
    if t == q then score = score + 1000 end
    -- Prefix matches beat scattered subsequence hits.
    if t:sub(1, #q) == q then score = score + 200 end

    if score < 1 then score = 1 end
    return score, positions
end

-- subtitleScore is a cheaper, position-less score used only to break ties when
-- the title alone wouldn't match well. No positions returned.
local function subtitleScore(query, subtitle)
    if query == "" then return 0 end
    if not subtitle or subtitle == "" then return nil end
    local s = subtitle:lower()
    local q = query:lower()
    if s == q then return 600 end
    if s:sub(1, #q) == q then return 200 end
    local pos = s:find(q, 1, true)
    if pos then return math.max(0, 100 - pos) end
    return nil
end

function M.rank(items, query)
    local matches = {}
    local emptyQuery = query == ""
    for _, item in ipairs(items) do
        if emptyQuery and item.hideOnEmptyQuery then goto continue end
        do
            if item.bypassMatcher then
                local boost = recents.score(item.source, item.id)
                item.fromHistory = boost > 0
                if item.matchPositions == nil then item.matchPositions = {} end
                matches[#matches + 1] = {
                    item = item,
                    score = BYPASS_SCORE + boost / 100,
                }
                goto continue
            end

            local tScore, tPositions
            if emptyQuery then
                tScore, tPositions = 0, {}
            else
                tScore, tPositions = fuzzyMatch(query, item.title or "")
            end
            local sScore
            if not tScore and not emptyQuery then
                sScore = subtitleScore(query, item.subtitle or "")
            end

            local matchVal = tScore or (sScore and sScore * 0.6) or nil
            local hit = emptyQuery or matchVal ~= nil
            if hit then
                local boost = recents.score(item.source, item.id)
                item.fromHistory = boost > 0
                item.matchPositions = tPositions or {}
                local total
                if emptyQuery then
                    total = boost
                else
                    total = matchVal + boost / 10
                end
                matches[#matches + 1] = { item = item, score = total }
            else
                item.matchPositions = {}
            end
        end
        ::continue::
    end
    table.sort(matches, function(a, b) return a.score > b.score end)
    local out = {}
    for i, m in ipairs(matches) do out[i] = m.item end
    return out
end

-- Exposed for tests.
M._fuzzyMatch = fuzzyMatch
M._subtitleScore = subtitleScore
M._BYPASS_SCORE = BYPASS_SCORE

return M
