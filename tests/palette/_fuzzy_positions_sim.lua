-- Asserts that the new fuzzy matcher returns the matched character indices
-- expected by the canvas bolding code.

local LOG_PATH = "/tmp/palette-fuzzy-positions.log"
local logF = io.open(LOG_PATH, "w")
local function logln(s) if logF then logF:write(s .. "\n") end end

local realRecents = package.loaded["Palette.recents"]
package.loaded["Palette.recents"] = { score = function() return 0 end }
package.loaded["Palette.matcher"] = nil
local matcher = require("Palette.matcher")

local results = {}

local function checkMatch(name, query, title, wantPositions, wantHit)
    local score, positions = matcher._fuzzyMatch(query, title)
    local hit = score ~= nil
    local pass = hit == wantHit
    if hit and wantHit then
        local got = table.concat(positions, ",")
        local want = table.concat(wantPositions, ",")
        if got ~= want then pass = false end
    end
    results[#results + 1] = { name = name, pass = pass }
    if not pass then
        logln(("FAIL  %s  score=%s positions=[%s] hit=%s")
            :format(name, tostring(score),
                table.concat(positions or {}, ","), tostring(hit)))
    else
        logln("PASS  " .. name)
    end
end

local function checkBypassPreservesPositions(name)
    local items = {
        {
            id = "x", title = "= 544", subtitle = "17 * 32",
            source = "calc", bypassMatcher = true,
            matchPositions = { 3, 4, 5 },
        },
    }
    local ranked = matcher.rank(items, "17 * 32")
    local pass = ranked[1] and ranked[1].matchPositions
        and table.concat(ranked[1].matchPositions, ",") == "3,4,5"
    results[#results + 1] = { name = name, pass = pass }
    logln((pass and "PASS  " or "FAIL  ") .. name)
end

local function checkRankPopulatesPositions(name)
    local items = {
        { id = "a", title = "Safari", source = "t" },
        { id = "b", title = "Google Chrome", source = "t" },
    }
    local ranked = matcher.rank(items, "saf")
    local first = ranked[1]
    local pass = first
        and first.id == "a"
        and first.matchPositions
        and table.concat(first.matchPositions, ",") == "1,2,3"
    results[#results + 1] = { name = name, pass = pass }
    logln((pass and "PASS  " or "FAIL  ") .. name)
end

checkMatch("prefix subsequence", "saf", "Safari", { 1, 2, 3 }, true)
checkMatch("midstring subsequence", "chr", "Google Chrome", { 8, 9, 10 }, true)
checkMatch("scattered subsequence", "abc", "axbycz", { 1, 3, 5 }, true)
checkMatch("no match returns nil", "xz", "Safari", nil, false)
checkMatch("empty query matches anything", "", "Safari", {}, true)
checkBypassPreservesPositions("bypassMatcher items keep their positions")
checkRankPopulatesPositions("rank populates matchPositions on items")

package.loaded["Palette.recents"] = realRecents

local failed = 0
for _, r in ipairs(results) do if not r.pass then failed = failed + 1 end end
local passed = #results - failed
logln(string.format("\n%d/%d scenarios passed", passed, #results))
if logF then logF:close() end
return string.format("%d/%d", passed, #results)
