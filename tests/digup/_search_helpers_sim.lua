-- Simulator for DigUp's pure search helpers (extractSnippet, formatTime,
-- buildChoices). These are the bits that don't need a live SQLite DB or
-- a real OCR helper — just string and table manipulation around results.
-- Deeper integration (DB roundtrip, capture pixel-diff, OCR queue) is left
-- for separate tests when needed.
--
-- We require DigUp.search fresh per test. Side-effect-free at load time;
-- the SQLite connection is opened only via db.init() which we never call.

local LOG_PATH = "/tmp/digup-sim.log"
local logF = io.open(LOG_PATH, "w")
local function logln(s) if logF then logF:write(s .. "\n") end end

local L = dofile(hs.configdir .. "/tests/_test_lib.lua")
local deepUpvals, assertEq = L.deepUpvals, L.assertEq

local function freshSearch()
    package.loaded["DigUp.search"] = nil
    local search = require("DigUp.search")
    -- search.show is an exposed module function; its upvalues reach the local
    -- helpers (extractSnippet, formatTime, buildChoices, ...).
    return search, deepUpvals(search.show)
end

local results = {}
local function scenario(name, body)
    local ok, err = pcall(body)
    if not ok then
        table.insert(results, { name = name, pass = false })
        logln(string.format("FAIL  %s", name))
        logln("     error: " .. tostring(err))
        return
    end
    table.insert(results, { name = name, pass = true })
    logln(string.format("PASS  %s", name))
end


-- ---------- Scenarios ----------

scenario("extractSnippet returns short text untouched (after whitespace collapse)", function()
    local _, U = freshSearch()
    assert(type(U.extractSnippet) == "function", "extractSnippet reachable")
    -- 60-char text under maxLen=120 → returned as-is, but multi-space collapsed.
    local out = U.extractSnippet("hello    world  foo  bar", "world", 120)
    assertEq(out, "hello world foo bar", "whitespace collapsed, no truncation")
end)

scenario("extractSnippet centers around the first query word match", function()
    local _, U = freshSearch()
    local text = "lorem ipsum dolor sit amet consectetur adipiscing elit "
              .. "sed do eiusmod TARGET tempor incididunt ut labore et dolore "
              .. "magna aliqua ut enim ad minim veniam"
    local out = U.extractSnippet(text, "TARGET", 40)
    assert(out:find("TARGET", 1, true), "match must appear in snippet, got: " .. out)
    -- With prefix trimmed there should be a leading "...".
    assert(out:sub(1, 3) == "...", "leading ellipsis when truncated from front")
end)

scenario("extractSnippet truncates with trailing ... when no query match", function()
    local _, U = freshSearch()
    local text = ("a"):rep(200)
    local out = U.extractSnippet(text, "zzz", 30)
    assertEq(#out, 30, "snippet length matches maxLen")
    assert(out:sub(-3) == "...", "trailing ellipsis when no match found")
end)

scenario("extractSnippet ignores 1-char query tokens (require >=2 chars)", function()
    local _, U = freshSearch()
    local text = "this is a long text where the letter Z is mentioned only here at " ..
                 "position 38 in the original raw string"
    -- "z" is only 1 char → skipped; should behave as no-match.
    local out = U.extractSnippet(text, "z", 30)
    assertEq(#out, 30, "snippet length matches maxLen")
    assert(out:sub(-3) == "...", "trailing ellipsis (treated as no-match)")
end)

scenario("extractSnippet handles empty/nil query gracefully", function()
    local _, U = freshSearch()
    local text = "this is a fairly long text that should be truncated cleanly"
    local out1 = U.extractSnippet(text, "", 20)
    assert(out1:sub(-3) == "...", "empty query → no match path, trailing ellipsis")
    local out2 = U.extractSnippet(text, nil, 20)
    assert(out2:sub(-3) == "...", "nil query → no match path, trailing ellipsis")
end)

-- ---------- Cleanup ----------

package.loaded["DigUp.search"]  = nil
package.loaded["DigUp.capture"] = nil
package.loaded["DigUp.db"]      = nil
package.loaded["DigUp.config"]  = nil

local failed = 0
for _, r in ipairs(results) do if not r.pass then failed = failed + 1 end end
local passed = #results - failed
logln(string.format("\n%d/%d scenarios passed", passed, #results))
if logF then logF:close() end
return string.format("%d/%d", passed, #results)
