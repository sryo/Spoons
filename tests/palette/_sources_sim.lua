-- Source-level behavior: calc, shellrunner, and files. Hits the real source
-- modules with synthetic queries and asserts the emitted items.

local LOG_PATH = "/tmp/palette-sources.log"
local logF = io.open(LOG_PATH, "w")
local function logln(s) if logF then logF:write(s .. "\n") end end

local results = {}
local function check(name, pass, msg)
    results[#results + 1] = { name = name, pass = pass }
    if pass then
        logln("PASS  " .. name)
    else
        logln("FAIL  " .. name .. (msg and ("  " .. msg) or ""))
    end
end

-- ---------- calc ----------

local calc = require("Palette.sources.calc")

do
    local items = calc.list("17 * 32")
    check("calc emits for 17 * 32",
        #items == 1 and items[1].title == "= 544",
        "got " .. tostring(items[1] and items[1].title))
    check("calc bypasses matcher",
        items[1] and items[1].bypassMatcher == true)
    check("calc payload carries value",
        items[1] and items[1].payload.value == 544)
end

do
    local items = calc.list("(3 + 4) * 5 / 7")
    check("calc parses parens and precedence",
        #items == 1 and items[1].title == "= 5",
        "got " .. tostring(items[1] and items[1].title))
end

do
    local items = calc.list("pi * 2")
    check("calc recognises pi constant",
        #items == 1 and items[1].title:sub(1, 3) == "= 6")
end

do
    local items = calc.list("not math")
    check("calc emits nothing for non-math query", #items == 0)
end

do
    local items = calc.list("")
    check("calc emits nothing for empty query", #items == 0)
end

-- ---------- shellrunner ----------

local shellrunner = require("Palette.sources.shellrunner")

do
    local items = shellrunner.list("ls -la")
    check("shellrunner emits for ls -la",
        #items == 1 and items[1].title == "ls -la")
    check("shellrunner bypasses matcher",
        items[1] and items[1].bypassMatcher == true)
    check("shellrunner default verb is runshell",
        items[1] and items[1].defaultVerb == "runshell")
end

do
    local items = shellrunner.list("xyzzy_not_a_command")
    check("shellrunner emits nothing for unknown first token", #items == 0)
end

do
    local items = shellrunner.list("../etc/passwd")
    check("shellrunner refuses tokens with slashes", #items == 0)
end

-- ---------- files ----------

local files = require("Palette.sources.files")
local recents = require("Palette.recents")

do
    local items = files.list("~/")
    local hasDocs = false
    for _, it in ipairs(items) do
        if it.title == "Documents" then hasDocs = true; break end
    end
    check("files path mode lists home directory", hasDocs)
end

do
    local items = files.list("~/Doc")
    check("files path mode filters by tail",
        #items >= 1 and items[1].title == "Documents")
    check("files dir item default verb is enter",
        items[1] and items[1].defaultVerb == "enter")
    check("files dir item carries path payload",
        items[1] and items[1].payload.path
            == (os.getenv("HOME") .. "/Documents"))
end

do
    local items = files.list("/")
    check("files / lists root directory contents", #items > 0)
end

-- Visited-dir frecency: prime recents, then query a partial basename.
do
    local marker = "/tmp"
    recents.record(files.id, marker)
    local items = files.list("tmp")
    local hit = false
    for _, it in ipairs(items) do
        if it.payload.path == marker then hit = true; break end
    end
    check("files visited-dir frecency surfaces remembered dirs", hit)
end

-- ---------- summary ----------

local failed = 0
for _, r in ipairs(results) do if not r.pass then failed = failed + 1 end end
local passed = #results - failed
logln(string.format("\n%d/%d scenarios passed", passed, #results))
if logF then logF:close() end
return string.format("%d/%d", passed, #results)
