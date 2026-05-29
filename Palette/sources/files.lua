-- Files source. Two modes triggered by query shape:
--
--   1. Path mode: query starts with `/`, `~/`, or `./`. The source resolves
--      the directory prefix, lists children, and filters by the trailing
--      tail. Items bypass the global matcher (the query has the dir prefix
--      embedded; we already filtered by tail). matchPositions are filled in
--      so the canvas can still bold matched glyphs in the basename.
--
--   2. Visited-dir mode: query has no path trigger. The source iterates
--      directories the user has previously entered or opened files in
--      (recorded under recents source-id "files"). Items go through the
--      global matcher, which fuzzy-matches against the basename and lets
--      frecency boost the most-used picks.

local matcher = require("Palette.matcher")
local recents = require("Palette.recents")

local M = {}
M.id = "files"
M.dynamic = true

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local HOME = os.getenv("HOME") or ""

local function expandPath(p)
    if p == "~" then return HOME end
    if p:sub(1, 2) == "~/" then return HOME .. p:sub(2) end
    if p:sub(1, 2) == "./" then return HOME .. p:sub(2) end
    return p
end

local function abbreviatePath(absPath)
    if HOME ~= "" and absPath:sub(1, #HOME) == HOME then
        return "~" .. absPath:sub(#HOME + 1)
    end
    return absPath
end

local function isPathTrigger(q)
    return q:sub(1, 1) == "/" or q:sub(1, 2) == "~/" or q:sub(1, 2) == "./"
end

local function loadIcon(path)
    local icon
    pcall(function() icon = hs.image.iconForFile(path) end)
    return icon
end

local function makeItem(absPath, basename, isDir, matchPositions)
    return {
        id               = absPath,
        title            = basename,
        subtitle         = abbreviatePath(
            absPath:match("(.*)/[^/]+$") or "/"),
        icon             = loadIcon(absPath),
        source           = M.id,
        payload          = { path = absPath, isDir = isDir },
        defaultVerb      = isDir and "enter" or "open",
        verbs            = isDir
            and { "enter", "open", "reveal", "copypath", "askmuse" }
            or  { "open", "reveal", "copypath", "askmuse" },
        hideOnEmptyQuery = true,
        bypassMatcher    = matchPositions ~= nil,
        matchPositions   = matchPositions,
    }
end

local MAX_PATH_RESULTS = 30
local MAX_VISITED_RESULTS = 10

local function listPathDirectory(query)
    local slashAt = query:match("^.*()/")
    if not slashAt then return {} end
    local dir = query:sub(1, slashAt - 1)
    local tail = query:sub(slashAt + 1)

    local absDir
    if dir == "" then absDir = "/"
    elseif dir == "~" then absDir = HOME
    else absDir = expandPath(dir)
    end
    if absDir == "" then absDir = "/" end

    local showHidden = tail:sub(1, 1) == "."
    local children = {}
    local function consider(name)
        if name == "." or name == ".." then return end
        if not showHidden and name:sub(1, 1) == "." then return end
        local score, positions
        if tail == "" then
            score, positions = 0, {}
        else
            score, positions = matcher._fuzzyMatch(tail, name)
            if not score then return end
        end
        local fullPath = absDir == "/" and ("/" .. name) or (absDir .. "/" .. name)
        local cattrs = hs.fs.attributes(fullPath)
        local isDir = cattrs and cattrs.mode == "directory" or false
        children[#children + 1] = {
            name = name, path = fullPath, isDir = isDir,
            score = score, positions = positions,
        }
    end
    local ok = pcall(function()
        for name in hs.fs.dir(absDir) do consider(name) end
    end)
    if not ok then return {} end

    table.sort(children, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.isDir ~= b.isDir then return a.isDir end
        return a.name:lower() < b.name:lower()
    end)

    local out = {}
    for i = 1, math.min(#children, MAX_PATH_RESULTS) do
        local c = children[i]
        out[#out + 1] = makeItem(c.path, c.name, c.isDir, c.positions)
    end
    return out
end

-- Per-keystroke stat checks for every recents entry add up fast on big stores.
-- recents.cleanup prunes by age (30 days) on init; opening a missing path falls
-- through to /usr/bin/open which fails silently. Accept the occasional dead row.
local function listVisited(query)
    if query == "" then return {} end
    local lowerQ = query:lower()
    local out = {}
    for absPath in pairs(recents.entries(M.id)) do
        local name = absPath:match("([^/]+)$") or absPath
        if name:lower():find(lowerQ, 1, true) then
            out[#out + 1] = makeItem(absPath, name, true, nil)
            if #out >= MAX_VISITED_RESULTS then break end
        end
    end
    return out
end

function M.list(query)
    query = query or ""
    local trimmed = trim(query)
    if trimmed == "" then return {}, nil end
    if isPathTrigger(trimmed) then
        return listPathDirectory(trimmed), nil
    end
    return listVisited(trimmed), nil
end

M._listPathDirectory = listPathDirectory
M._listVisited = listVisited
M.abbreviatePath = abbreviatePath

return M
