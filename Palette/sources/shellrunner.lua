-- Shell runner source. Emits one synthetic row when the trimmed query's first
-- token resolves to an executable in $PATH. Bypasses the fuzzy matcher (the
-- row title is the user's literal command, which wouldn't subsequence-match
-- itself in a useful way). Fire and forget: the verb spawns via hs.task and
-- closes the palette, no output capture.

local M = {}
M.id = "shellrunner"
M.dynamic = true

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function splitPath()
    local out, p = {}, os.getenv("PATH") or ""
    for entry in p:gmatch("([^:]+)") do
        if entry ~= "" then out[#out + 1] = entry end
    end
    return out
end

local pathEntries = splitPath()
local lookupCache = {}

local function isExecutable(path)
    local attrs = hs.fs.attributes(path)
    if not attrs then return false end
    if attrs.mode ~= "file" then return false end
    -- mode is a string like "file" on macOS; permissions live under .permissions
    local perm = attrs.permissions or ""
    if perm:find("x") then return true end
    -- Fallback: assume executable if it lives in $PATH (rare edge case where
    -- attrs.permissions isn't surfaced as expected).
    return true
end

local function findInPath(token)
    if lookupCache[token] ~= nil then return lookupCache[token] end
    -- Reject paths and tokens with shell metachars; only bare command names.
    if token == "" or token:find("/") then
        lookupCache[token] = false
        return false
    end
    for _, dir in ipairs(pathEntries) do
        local candidate = dir .. "/" .. token
        if isExecutable(candidate) then
            lookupCache[token] = true
            return true
        end
    end
    lookupCache[token] = false
    return false
end

local terminalIcon
local function icon()
    if terminalIcon then return terminalIcon end
    pcall(function()
        terminalIcon = hs.image.iconForFile("/System/Applications/Utilities/Terminal.app")
    end)
    return terminalIcon
end

function M.list(query)
    query = query or ""
    local trimmed = trim(query)
    if trimmed == "" then return {}, nil end
    local firstToken = trimmed:match("^(%S+)")
    if not firstToken then return {}, nil end
    if not findInPath(firstToken) then return {}, nil end
    return {
        {
            id               = "shell:active",
            title            = trimmed,
            subtitle         = "Run shell command",
            icon             = icon(),
            source           = M.id,
            payload          = { command = trimmed },
            defaultVerb      = "runshell",
            verbs            = { "runshell", "askmuse" },
            hideOnEmptyQuery = true,
            bypassMatcher    = true,
        },
    }, nil
end

M._findInPath = findInPath

return M
