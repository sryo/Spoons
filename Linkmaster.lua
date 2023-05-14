function handleUrlEvent(scheme, host, params, fullURL)
    hs.printf("URL event received: %s", fullURL)

    local browsers = {
        { name = "Arc", bundleID = "company.thebrowser.Browser" },
        { name = "Google Chrome", bundleID = "com.google.Chrome" },
        { name = "Firefox", bundleID = "org.mozilla.firefox" },
        { name = "Safari", bundleID = "com.apple.Safari" },
        { name = "Copy to Clipboard", action = "clipboard" },
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
            hs.printf("Selected browser: %s", choice.text)
            if choice.action == "clipboard" then
                hs.pasteboard.setContents(fullURL)
            else
                hs.urlevent.openURLWithBundle(fullURL, choice.bundleID)
            end
            countdownTimer:stop()
            browserChooser:hide()
        end
    end

    browserChooser = hs.chooser.new(handleBrowserSelection)
    browserChooser:choices(generateChoices(browsers))
    browserChooser:show()

    countdownTimer = hs.timer.new(1, function()
        countdown = countdown - 1
        if countdown == 0 then
            countdownTimer:stop()
            browserChooser:select(1)
        else
            browserChooser:choices(generateChoicesWithCountdown(countdown, browsers))
            browserChooser:refreshChoicesCallback()
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
