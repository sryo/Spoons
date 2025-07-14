-- NoTunes: Block iTunes/Music and launch Spotify instead.

local blockedBundleIDs = { ["com.apple.Music"] = true, ["com.apple.iTunes"] = true }
local spotifyBundleID = "com.spotify.client"

local function blockAndReplace()
    local killedAny = false

    local appsToKill = {}
    for _, app in ipairs(hs.application.runningApplications()) do
        if blockedBundleIDs[app:bundleID()] then
            table.insert(appsToKill, app)
        end
    end

    for _, app in ipairs(appsToKill) do
        pcall(function()
            app:kill()
            killedAny = true
        end)
    end

    if killedAny then
        hs.timer.doAfter(0.5, function()
            hs.application.launchOrFocusByBundleID(spotifyBundleID)
        end)
    end
end

local watcher = hs.application.watcher.new(function(event, app)
    pcall(blockAndReplace)
end)

watcher:start()
return { watcher = watcher }
