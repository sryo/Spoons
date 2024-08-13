-- HyperlinkHijacker: https://github.com/sryo/Spoons/blob/main/HyperlinkHijacker.lua
-- Choose which browser opens your links. Shift-click to bypass chooser.

local passthroughs = {
    spotify = { url = "https://open.spotify.com/", appName = "Spotify", bundleID = "com.spotify.client" },
    -- Add more passthroughs here if needed
}

local browsers = {
    { name = "Arc", appName = "Arc", bundleID = "company.thebrowser.Browser", args = {""} },
    { name = "Google Chrome", appName = "Google Chrome", bundleID = "com.google.Chrome", args = {""} },
    { name = "Google Chrome (Incognito)", appName = "Google Chrome", bundleID = "com.google.Chrome", args = {"--incognito"} },
    { name = "Firefox", appName = "Firefox", bundleID = "org.mozilla.firefox", args = {""} },
    { name = "Firefox (Private)", appName = "Firefox", bundleID = "org.mozilla.firefox", args = {"-private"} },
    { name = "Safari", appName = "Safari", bundleID = "com.apple.Safari", args = {""} },
    { name = "Copy to Clipboard", action = "clipboard", args = {""} },
    -- Add more options here if needed
}

local countdownValue = 5

local function debugLog(message)
    print("DEBUG: " .. message)
end

local function getLastUsedBrowser()
    local saved = hs.settings.get("lastUsedBrowser")
    debugLog("Retrieved last used browser: " .. hs.inspect(saved))
    return saved or { bundleID = browsers[1].bundleID, args = browsers[1].args }
end

local lastUsedBrowser = getLastUsedBrowser()

local function saveLastUsedBrowser(browser)
    local toSave = { bundleID = browser.bundleID, args = browser.args }
    hs.settings.set("lastUsedBrowser", toSave)
    lastUsedBrowser = toSave
    debugLog("Saved last used browser: " .. hs.inspect(toSave))
end

local function generateChoices(browsers)
    local choices = {}
    local lastUsedChoice = nil

    for _, browser in ipairs(browsers) do
        local icon = browser.bundleID and hs.image.imageFromAppBundle(browser.bundleID) or nil
        local choice = {
            ["text"] = browser.name,
            ["subText"] = "Open link in " .. browser.name,
            ["image"] = icon,
            ["bundleID"] = browser.bundleID,
            ["action"] = browser.action,
            ["args"] = browser.args,
            ["appName"] = browser.appName,
        }

        if browser.bundleID == lastUsedBrowser.bundleID and
           ((browser.args[1] == lastUsedBrowser.args[1]) or 
            (browser.args[1] == "" and lastUsedBrowser.args[1] == nil)) then
            choice.subText = choice.subText .. " (Last used)"
            lastUsedChoice = choice
        else
            table.insert(choices, choice)
        end
    end

    if lastUsedChoice then
        table.insert(choices, 1, lastUsedChoice)
    end

    return choices
end

local function generateChoicesWithCountdown(countdown, browsers)
    local choices = generateChoices(browsers)
    choices[1].subText = choices[1].subText .. " (" .. countdown .. ")"
    return choices
end

function handleUrlEvent(scheme, host, params, fullURL)
    debugLog("Handling URL: " .. fullURL)
    hs.printf("🔗 URL: %s", fullURL)
    local modifiers = hs.eventtap.checkKeyboardModifiers()
    if modifiers["shift"] then
        hs.printf("🚀 Launching %s", browsers[1].appName)
        hs.urlevent.openURLWithBundle(fullURL, browsers[1].bundleID)
        return
    end
    for _, passthrough in pairs(passthroughs) do
        if string.sub(fullURL, 1, string.len(passthrough.url)) == passthrough.url then
            hs.printf("🚀 Launching %s", passthrough.appName)
            hs.urlevent.openURLWithBundle(fullURL, passthrough.bundleID)
            return
        end
    end

    local countdown = countdownValue
    local countdownTimer
    local browserChooser

    local function cleanup()
        if countdownTimer then
            countdownTimer:stop()
            countdownTimer = nil
        end
        if browserChooser then
            browserChooser:delete()
            browserChooser = nil
        end
    end

    local function handleBrowserSelection(choice)
        if choice then
            hs.printf("🚀 Launching %s", choice.text)
            if choice.action == "clipboard" then
                hs.pasteboard.setContents(fullURL)
            else
                saveLastUsedBrowser(choice)

                if choice.args and choice.args[1] ~= "" then
                    local args = table.concat(choice.args, " ")
                    local cmd = "/usr/bin/open -a \"" .. choice.appName .. "\" --args " .. args .. " \"" .. fullURL .. "\""
                    hs.execute(cmd)
                else
                    hs.urlevent.openURLWithBundle(fullURL, choice.bundleID)
                end
            end
        end
        cleanup()
    end

    browserChooser = hs.chooser.new(handleBrowserSelection)
    browserChooser:choices(generateChoices(browsers))

    browserChooser:show()

    countdownTimer = hs.timer.new(1, function()
        if browserChooser and browserChooser:query() == "" then
            countdown = countdown - 1
            if countdown == 0 then
                browserChooser:select(1)
            else
                browserChooser:choices(generateChoicesWithCountdown(countdown, browsers))
                browserChooser:refreshChoicesCallback()
            end
        else
            countdownTimer:stop()
        end
    end)

    countdownTimer:start()

    -- Set up a separate timer to check if the chooser has been closed
    local checkClosedTimer = hs.timer.new(0.1, function()
        if not browserChooser:isVisible() then
            cleanup()
            checkClosedTimer:stop()
        end
    end):start()

    return browserChooser, countdownTimer
end

hs.urlevent.setDefaultHandler('http')
hs.urlevent.setDefaultHandler('https')
hs.urlevent.httpCallback = handleUrlEvent
