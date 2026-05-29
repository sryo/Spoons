-- Now playing from Spotify or Music. We gate every AppleEvent on
-- hs.application.runningApplications because "tell application X" will
-- launch X if it isn't running, which wedges the runloop.

local M = {
    id       = "nowplaying",
    side     = "center-left",
    order    = 50,
    interval = 2,
}

local pending

local SCRIPTS = {
    {
        bundle = "com.spotify.client",
        script = [[
            tell application id "com.spotify.client"
                if player state is playing then
                    return (name of current track) & " · " & (artist of current track)
                end if
            end tell
            return ""
        ]],
    },
    {
        bundle = "com.apple.Music",
        script = [[
            tell application id "com.apple.Music"
                if player state is playing then
                    return (name of current track) & " · " & (artist of current track)
                end if
            end tell
            return ""
        ]],
    },
}

local function isRunning(bundle)
    for _, app in ipairs(hs.application.runningApplications()) do
        if app:bundleID() == bundle then return true end
    end
    return false
end

function M.update()
    if pending then return M._cached or "" end
    local chosen
    for _, s in ipairs(SCRIPTS) do
        if isRunning(s.bundle) then chosen = s; break end
    end
    if not chosen then
        if M._cached ~= "" then
            M._cached = ""
            if M._refresh then M._refresh() end
        end
        return ""
    end
    pending = hs.task.new("/usr/bin/osascript", function(_code, stdout)
        pending = nil
        local val = (stdout or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if val == " · " then val = "" end
        if M._cached ~= val then
            M._cached = val
            if M._refresh then M._refresh() end
        end
    end, { "-e", chosen.script })
    pending:start()
    return M._cached or ""
end

function M.setup(refresh)
    M._refresh = refresh
end

function M.teardown()
    M._refresh = nil
    M._cached = nil
    if pending then pending:terminate(); pending = nil end
end

function M.onClick()
    for _, s in ipairs(SCRIPTS) do
        if isRunning(s.bundle) then
            local script = string.format([[tell application id "%s" to playpause]], s.bundle)
            hs.task.new("/usr/bin/osascript", nil, { "-e", script }):start()
            return
        end
    end
end

return M
