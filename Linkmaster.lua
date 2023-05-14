function handleUrlEvent(scheme, host, params, fullURL)
    hs.printf("🔗 URL: %s", fullURL)

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

    local function generateChoices(browsers)
        local choices = {}
        for _, browser in ipairs(browsers) do
            local icon = browser.bundleID and hs.image.imageFromAppBundle(browser.bundleID) or nil
            table.insert(choices, {
                ["text"] = browser.name,
                ["subText"] = "Open link in " .. browser.name,
                ["image"] = icon,
                ["bundleID"] = browser.bundleID,
                ["action"] = browser.action,
                ["args"] = browser.args,
                ["appName"] = browser.appName,
            })
        end
        return choices
    end


    local function generateChoicesWithCountdown(countdown, browsers)
        local choices = generateChoices(browsers)
        choices[1].subText = choices[1].subText .. " (" .. countdown .. ")"
        return choices
    end

    local countdown = 5
    local countdownTimer
    local browserChooser

local function handleBrowserSelection(choice)
    if choice then
        hs.printf("🚀 Launching %s", choice.text)
        if choice.action == "clipboard" then
            hs.pasteboard.setContents(fullURL)
        else
            if choice.args and choice.args[1] ~= "" then
                local args = table.concat(choice.args, " ")
                local cmd = "/usr/bin/open -a \"" .. choice.appName .. "\" --args " .. args .. " \"" .. fullURL .. "\""
                hs.execute(cmd)
            else
                hs.urlevent.openURLWithBundle(fullURL, choice.bundleID)
            end
        end
        countdownTimer:stop()
        browserChooser:hide()
    end
end

    browserChooser = hs.chooser.new(handleBrowserSelection)
    browserChooser:choices(generateChoices(browsers))
    browserChooser:show()

    countdownTimer = hs.timer.new(1, function()
        if browserChooser:query() == "" then
            countdown = countdown - 1
            if countdown == 0 then
                countdownTimer:stop()
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

    hs.chooser.globalCallback = function(chooser, eventType)
        if eventType == "didClose" then
            countdownTimer:stop()
        end
        hs.chooser._defaultGlobalCallback(chooser, eventType)
    end
end
hs.urlevent.setDefaultHandler('http')
hs.urlevent.setDefaultHandler('https')
hs.urlevent.httpCallback = handleUrlEvent
