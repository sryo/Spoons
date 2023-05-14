function handleUrlEvent(_, event, params)
    hs.printf("URL event received: %s", event)
    hs.printf("URL event params: %s", hs.inspect(params))

    local browsers = {
        { name = "Arc", bundleID = "company.thebrowser.Browser", args = "" },
        { name = "Google Chrome", bundleID = "com.google.Chrome", args = "" },
        { name = "Google Chrome Incognito", bundleID = "com.google.Chrome", args = "--incognito" },
        { name = "Google Chrome Profile 1", bundleID = "com.google.Chrome", args = "--profile-directory=\"Profile 1\"" },
        { name = "Google Chrome Profile 2", bundleID = "com.google.Chrome", args = "--profile-directory=\"Profile 2\"" },
        { name = "Firefox", bundleID = "org.mozilla.firefox", args = "" },
        { name = "Safari", bundleID = "com.apple.Safari", args = "" },
    }

    local function generateChoices(timeLeft)
        local choices = {}
        for i, browser in ipairs(browsers) do
            local icon = hs.image.imageFromAppBundle(browser.bundleID)
            local subText = "Open link in " .. browser.name
            if i == 1 then
                subText = subText .. " (" .. tostring(timeLeft) .. "s remaining)"
            end
            table.insert(choices, {
                ["text"] = browser.name,
                ["subText"] = subText,
                ["image"] = icon,
                ["bundleID"] = browser.bundleID,
                ["args"] = browser.args
            })
        end
        return choices
    end

    local function handleBrowserSelection(choice)
        if timer then
            timer:stop()
        end
        if choice then
            hs.printf("Selected browser: %s", choice.text)
            local command = "/usr/bin/open -b " .. choice.bundleID .. " \"" .. event .. "\" --args " .. choice.args
            hs.printf("Executing command: %s", command)
            hs.execute(command)
        end
    end

    local countdown = 5
    local browserChooser = hs.chooser.new(handleBrowserSelection)
    local timer

    local function updateCountdown()
        if countdown == 0 then
            timer:stop()
            browserChooser:hide()
            handleBrowserSelection(browserChooser:choices()[1])
        else
            browserChooser:choices(generateChoices(countdown))
            browserChooser:refreshChoicesCallback()
            countdown = countdown - 1
        end
    end

    browserChooser:choices(generateChoices(countdown))
    browserChooser:queryChangedCallback(function() end) -- Disable filtering
    browserChooser:show()

    timer = hs.timer.new(1, updateCountdown, true):start()
end

hs.urlevent.setDefaultHandler('http')
hs.urlevent.setDefaultHandler('https')
hs.urlevent.httpCallback = handleUrlEvent
