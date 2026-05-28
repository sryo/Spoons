-- Deterministic matcher tests. Feeds fixed item lists and queries to
-- Palette.matcher.rank and checks the resulting ordering. recents.score is
-- stubbed to return 0 so ranking depends only on the match score.
--
-- Returns "N/M" to the shell driver and writes /tmp/palette-matcher.log.

local LOG_PATH = "/tmp/palette-matcher.log"
local logF = io.open(LOG_PATH, "w")
local function logln(s) if logF then logF:write(s .. "\n") end end

local realRecents = package.loaded["Palette.recents"]
package.loaded["Palette.recents"] = { score = function() return 0 end }

package.loaded["Palette.matcher"] = nil
local matcher = require("Palette.matcher")

local function item(id, title, subtitle)
    return { id = id, title = title, subtitle = subtitle or "", source = "test" }
end

local function hiddenItem(id, title)
    return { id = id, title = title, subtitle = "", source = "test", hideOnEmptyQuery = true }
end

local results = {}

local function ids(list)
    local out = {}
    for i, it in ipairs(list) do out[i] = it.id end
    return table.concat(out, ",")
end

local function scenario(name, items, query, expectedIds)
    local ranked = matcher.rank(items, query)
    local got = ids(ranked)
    local pass = (got == expectedIds)
    table.insert(results, { name = name, want = expectedIds, got = got, pass = pass })
    logln(string.format("%s  %s", pass and "PASS" or "FAIL", name))
    if not pass then
        logln("     want: [" .. expectedIds .. "]")
        logln("     got:  [" .. got .. "]")
    end
end

-- ---------- Scenarios ----------

scenario("empty query returns all in input order",
    { item("a", "Apple"), item("b", "Banana"), item("c", "Cherry") },
    "",
    "a,b,c"
)

scenario("exact title match wins",
    { item("a", "Save All"), item("b", "Save") },
    "save",
    "b,a"
)

scenario("prefix beats midstring",
    { item("a", "Page Down"), item("b", "Page Up"), item("c", "Open Page") },
    "page",
    "a,b,c"
)

scenario("case-insensitive match",
    { item("a", "REPLACE"), item("b", "replace") },
    "Re",
    "a,b"
)

scenario("subtitle match still surfaces",
    { item("a", "Help", "About"), item("b", "Reload", "View > Reload") },
    "reload",
    "b"
)

scenario("subtitle match has lower weight than title match",
    { item("a", "Save", "File > Save"), item("b", "Save All", "File > Save All") },
    "save",
    "a,b"
)

scenario("non-matching items are excluded",
    { item("a", "Foo"), item("b", "Bar"), item("c", "Baz") },
    "qq",
    ""
)

scenario("earlier substring position scores higher",
    { item("a", "xxxxxFoo"), item("b", "Foobar"), item("c", "xxFoo") },
    "foo",
    "b,c,a"
)

scenario("hideOnEmptyQuery items are skipped when query is empty",
    { item("a", "Visible"), hiddenItem("b", "Hidden"), item("c", "Visible 2") },
    "",
    "a,c"
)

scenario("hideOnEmptyQuery items appear once the user types",
    { item("a", "Apple"), hiddenItem("b", "Banana") },
    "ban",
    "b"
)

-- ---------- Cleanup ----------

package.loaded["Palette.recents"] = realRecents

local failed = 0
for _, r in ipairs(results) do if not r.pass then failed = failed + 1 end end
local passed = #results - failed
logln(string.format("\n%d/%d scenarios passed", passed, #results))
if logF then logF:close() end
return string.format("%d/%d", passed, #results)
