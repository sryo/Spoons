-- AppTimeout: automatically close apps that have no windows left

local checkInterval = 10
local timeoutDuration = 300

-- Set to 'true' to keep it alive
local ignoredApps = {
    ["Finder"] = true,
    ["Dock"] = true,
    ["SystemUIServer"] = true,
    ["ControlCenter"] = true,
    ["Transmission"] = true,
    ["Calendar"] = true,
    ["Stickies"] = true,
    ["Spotify"] = true,
    ["‎WhatsApp"] = true,
    ["Activity Monitor"] = true,
    ["Hammerspoon"] = true,
    ["loginwindow"] = true,
    ["Spotlight"] = true,
}

local windowlessApps = {}

local function checkApps()
    local runningApps = hs.application.runningApplications()

    for _, app in ipairs(runningApps) do
        local name = app:name()
        local bundleID = app:bundleID()

        if name and app:kind() == 1 then
            if not ignoredApps[name] then
                local windows = app:allWindows()

                if #windows == 0 and not app:isFrontmost() then
                    if not windowlessApps[name] then
                        windowlessApps[name] = os.time()
                        print(string.format("AppTimeout: Monitoring %s (No windows)", name))
                    elseif os.time() - windowlessApps[name] >= timeoutDuration then
                        print(string.format("AppTimeout: Closing %s (Timeout reached)", name))
                        app:kill()
                        windowlessApps[name] = nil
                    end
                else
                    if windowlessApps[name] then
                        windowlessApps[name] = nil
                        print(string.format("AppTimeout: Stopped monitoring %s", name))
                    end
                end
            end
        end
    end

    for name, _ in pairs(windowlessApps) do
        if not hs.application.get(name) then
            windowlessApps[name] = nil
        end
    end
end

checkAppsTimer = hs.timer.new(checkInterval, checkApps):start()
print("AppTimeout is running")
