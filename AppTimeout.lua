-- AppTimeout: automatically close apps that have no windows

local windowlessApps = {}

local function checkApps()
    for _, app in ipairs(hs.application.runningApplications()) do
        local name = app:name()
        if app:kind() == 1 and
            name ~= "Finder" and
            name ~= "Dock" and
            name ~= "SystemUIServer" and
            name ~= "ControlCenter" and
            name ~= "Transmission" and
            name ~= "Calendar" and
            name ~= "Stickies" and
            name ~= "‎WhatsApp" and
            name ~= "Activity Monitor" and
            name ~= "Hammerspoon" then
            local allWindows = hs.window.filter.new(function(win)
                return win:application():name() == name
            end)

            if #allWindows:getWindows() == 0 then
                if not windowlessApps[name] then
                    windowlessApps[name] = os.time()
                    print(string.format("Monitoring %s", name))
                elseif os.time() - windowlessApps[name] >= 300 then
                    print(string.format("Closing %s", name))
                    app:kill()
                    windowlessApps[name] = nil
                end
            elseif windowlessApps[name] then
                windowlessApps[name] = nil
                print(string.format("Stopped monitoring %s", name))
            end
        end
    end
end

checkAppsTimer = hs.timer.new(20, checkApps):start()
print("AppTimeout is running")
