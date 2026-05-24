-- NoTunes: Block iTunes/Music and launch Spotify instead.

local blockedBundleIDs = {
    ["com.apple.Music"]  = true,
    ["com.apple.iTunes"] = true
}
local spotifyBundleID = "com.spotify.client"

-- If Music launches, kill it.
local function killApp(app)
    if app then app:kill() end
end

local function ensureSpotify()
    if not hs.application.get(spotifyBundleID) then
        hs.application.launchOrFocusByBundleID(spotifyBundleID)
    end
end

local function enforcePolicy(app)
    if app and blockedBundleIDs[app:bundleID()] then
        killApp(app)
        hs.timer.doAfter(0.1, ensureSpotify)
    end
end

local appWatcher = hs.application.watcher.new(function(appName, eventType, app)
    if eventType == hs.application.watcher.launched then
        enforcePolicy(app)
    end
end)
appWatcher:start()

-- Intercept the Play key.
local mediaWatcher = hs.eventtap.new({ hs.eventtap.event.types.systemDefined }, function(event)
    local data = event:systemKey()

    if data.key == "PLAY" and data.down then
        local spotify = hs.application.get(spotifyBundleID)

        -- Run Spotify if it's NOT running...
        if not spotify then
            hs.application.launchOrFocusByBundleID(spotifyBundleID)

            return true -- consume the event.
        end
    end

    -- If Spotify IS running, let key events pass through.
    return false
end)

mediaWatcher:start()

return { appWatcher = appWatcher, mediaWatcher = mediaWatcher }
