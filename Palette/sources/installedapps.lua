-- Installed apps source. Enumerates .app bundles via the Spotlight index so
-- the user can launch an app that isn't currently running. Items are hidden
-- on empty query so the palette doesn't flood with hundreds of rows.

local M = {}
M.id = "installedapps"

local SELF = "Hammerspoon"

local cache = {}

local function isLaunchable(path)
    if path:find(".app/", 1, true) then return false end
    if path:find("/Library/Application Support/", 1, true) then return false end
    return path:sub(-4) == ".app"
end

local function rebuildMetadata()
    local handle = io.popen([[mdfind "kMDItemContentType == 'com.apple.application-bundle'" 2>/dev/null]])
    if not handle then cache = {}; return end
    local seen, out = {}, {}
    for path in handle:lines() do
        if isLaunchable(path) then
            local info = hs.application.infoForBundlePath(path)
            local bundleID = info and info.CFBundleIdentifier
            if bundleID and not seen[bundleID] then
                seen[bundleID] = true
                local name = info.CFBundleDisplayName or info.CFBundleName
                          or path:match("([^/]+)%.app$") or "App"
                if name ~= SELF then
                    out[#out + 1] = { path = path, bundleID = bundleID, name = name }
                end
            end
        end
    end
    handle:close()
    cache = out
end

local function hydrateIcons()
    for _, entry in ipairs(cache) do
        if not entry.icon then
            pcall(function() entry.icon = hs.image.iconForFile(entry.path) end)
        end
    end
end

-- Rebuild is fully deferred: mdfind + 350 infoForBundlePath calls + 350 icon
-- loads is ~500ms of blocking work, none of which needs to be done before the
-- user actually opens the palette. Module require returns immediately; the
-- cache populates on the next event loop tick.
local function rebuild()
    hs.timer.doAfter(0, function()
        rebuildMetadata()
        hydrateIcons()
    end)
end

rebuild()

-- Watch the standard app directories so a freshly installed app shows up
-- without a Hammerspoon reload. Watchers must stay reachable from Lua or
-- they GC silently.
M._watchers = {}
do
    local dirs = {
        "/Applications",
        "/System/Applications",
        os.getenv("HOME") .. "/Applications",
    }
    local pending
    local function schedule()
        if pending then pending:stop() end
        pending = hs.timer.doAfter(2.0, rebuild)
    end
    for _, dir in ipairs(dirs) do
        local w = hs.pathwatcher.new(dir, schedule)
        if w then w:start(); M._watchers[#M._watchers + 1] = w end
    end
end

local function runningWithWindows()
    local set = {}
    for _, app in ipairs(hs.application.runningApplications()) do
        local bid = app:bundleID()
        if bid then
            local wins = app:visibleWindows() or {}
            if #wins > 0 then set[bid] = true end
        end
    end
    return set
end

function M.list()
    local skip = runningWithWindows()
    local items = {}
    for _, entry in ipairs(cache) do
        if not skip[entry.bundleID] then
            items[#items + 1] = {
                id               = "installedapp:" .. entry.bundleID,
                title            = entry.name,
                subtitle         = "",
                icon             = entry.icon,
                source           = M.id,
                payload          = { bundleID = entry.bundleID, path = entry.path, appName = entry.name },
                defaultVerb      = "launch",
                verbs            = { "launch", "askmuse" },
                hideOnEmptyQuery = true,
            }
        end
    end
    return items, nil
end

M.refresh = rebuild

return M
