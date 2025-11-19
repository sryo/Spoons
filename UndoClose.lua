-- UndoClose.lua: Reopen recently closed applications with ⌘⌥Z

UndoClose = {}

UndoClose.config = {
    hotkey = { { "cmd", "option" }, "z" },
    timeout = 3,
}

local activationKey = nil
local timeoutTimer = nil
local lastAppBundleID = nil
local currentAlert = nil

local function log(message, show_alert)
    print("UndoClose: " .. message)
    if show_alert then hs.alert.show(message) end
end

local function cleanup()
    if activationKey then
        activationKey:delete()
        activationKey = nil
    end

    if timeoutTimer then
        timeoutTimer:stop()
        timeoutTimer = nil
    end

    if currentAlert then
        hs.alert.closeSpecific(currentAlert)
        currentAlert = nil
    end
end

UndoClose.watcher = hs.application.watcher.new(function(appName, event, app)
    if event == hs.application.watcher.terminated then
        if app and app:kind() == 1 then -- Filter: Standard apps only
            cleanup()                   -- Clear previous state if another app closes fast

            if app:bundleID() then
                lastAppBundleID = app:bundleID()

                local timeLeft = UndoClose.config.timeout

                local function showCountdown()
                    if currentAlert then hs.alert.closeSpecific(currentAlert) end

                    local msg = appName .. " was closed. ⌘⌥Z to reopen (" .. timeLeft .. ")"
                    currentAlert = hs.alert.show(msg, 1.1)
                end

                showCountdown()

                -- Create the hotkey
                activationKey = hs.hotkey.bind(
                    UndoClose.config.hotkey[1],
                    UndoClose.config.hotkey[2],
                    function()
                        log("Reopening: " .. appName, false) -- False = no extra alert, the app opening is enough feedback
                        hs.application.launchOrFocusByBundleID(lastAppBundleID)
                        cleanup()
                    end
                )

                timeoutTimer = hs.timer.doEvery(1, function()
                    timeLeft = timeLeft - 1
                    if timeLeft > 0 then
                        showCountdown()
                    else
                        cleanup()
                    end
                end)
            end
        end
    end
end)

UndoClose.watcher:start()
return UndoClose
