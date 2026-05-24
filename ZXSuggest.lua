local module = {}

local config = {
    keyMappings = {
        { "Z", 1 },
        { "X", 2 },
        { "C", 3 },
        { "V", 4 },
        { "B", 5 },
        { "N", 6 },
        { "M", 7 },
        { ",", 8 }
    },
    modifierKey = "space",
    barHeight = 40,
    cornerRadius = 10,
    fontSize = 20,
    showDelay = 0.16,
    engine = "google" -- or "duckduckgo"
}

local endpoints = {
    google = "https://suggestqueries.google.com/complete/search?client=firefox&q=%s",
    duckduckgo = "https://duckduckgo.com/ac/?q=%s",
}

-- Function to get system colors
local function getSystemColors()
    local isDark = hs.host.interfaceStyle() == "Dark"
    return {
        barBackgroundColor = isDark and hs.drawing.color.asRGB({ alpha = 0.8, hex = "#1E1E1E" }) or
        hs.drawing.color.asRGB({ alpha = 0.8, hex = "#F0F0F0" }),
        textColor = isDark and hs.drawing.color.asRGB({ hex = "#FFFFFF" }) or hs.drawing.color.asRGB({ hex = "#000000" }),
        highlightColor = hs.drawing.color.asRGB({ hex = "#007AFF" }) -- Blue highlight for both modes
    }
end

local STOP, GO = true, false
local DOWN, UP = true, false
local modifierDown = false
local normalKey = ""
local produceModifier = true
local keyBar
local showBarTimer
local currentSuggestions = {}

local function setupKeyBar()
    local screenFrame = hs.screen.primaryScreen():frame()
    if keyBar then
        keyBar:delete()
    end
    keyBar = hs.canvas.new({ x = screenFrame.x, y = screenFrame.h - config.barHeight, w = screenFrame.w, h = config
    .barHeight })

    local colors = getSystemColors()

    keyBar:appendElements({
        type = "rectangle",
        action = "fill",
        fillColor = colors.barBackgroundColor,
        roundedRectRadii = { xRadius = config.cornerRadius, yRadius = config.cornerRadius },
    })

    local keyCount = #config.keyMappings
    local keyWidth = screenFrame.w / keyCount

    for i, mapping in ipairs(config.keyMappings) do
        local key = mapping[1]
        keyBar:appendElements({
            type = "text",
            text = key,
            textColor = colors.textColor,
            textSize = config.fontSize,
            frame = { x = (i - 1) * keyWidth, y = 5, w = keyWidth, h = config.barHeight - 10 },
            textAlignment = "center"
        })
    end
end

local function updateSuggestions(suggestions)
    currentSuggestions = suggestions
    local keyCount = #config.keyMappings
    local screenFrame = hs.screen.primaryScreen():frame()
    local keyWidth = screenFrame.w / keyCount

    for i, mapping in ipairs(config.keyMappings) do
        local key = mapping[1]
        local suggestion = suggestions[i] or ""
        keyBar[i + 1].text = key .. " " .. suggestion
    end
end

local function highlightKey(key)
    local colors = getSystemColors()
    for i, element in ipairs(keyBar) do
        if element.type == "text" then
            element.textColor = (element.text:sub(1, 1) == key)
                and colors.highlightColor
                or colors.textColor
        end
    end
end

local function resetKeyHighlights()
    local colors = getSystemColors()
    for i, element in ipairs(keyBar) do
        if element.type == "text" then
            element.textColor = colors.textColor
        end
    end
end

local function hideKeyBar()
    resetKeyHighlights()
    keyBar:hide()
    if showBarTimer then
        showBarTimer:stop()
    end
end

local function cancelAnycomplete()
    modifierDown = false
    normalKey = ""
    produceModifier = false
    hideKeyBar()
end

local function getSuggestions(query, callback)
    local url = string.format(endpoints[config.engine], hs.http.encodeForQuery(query))
    hs.http.asyncGet(url, nil, function(status, body)
        if status ~= 200 or not body then return callback({}) end

        local ok, results = pcall(hs.json.decode, body)
        if not ok or type(results) ~= "table" then return callback({}) end

        if config.engine == "google" then
            callback(results[2] or {})
        elseif config.engine == "duckduckgo" then
            callback(hs.fnutils.imap(results, function(result) return result.phrase end) or {})
        else
            callback({})
        end
    end)
end

local function handleKeyDown(event)
    local currKey = hs.keycodes.map[event:getKeyCode()]
    local flags = event:getFlags()
    local otherModifiersPressed = flags.cmd or flags.alt or flags.shift or flags.ctrl

    if currKey == config.modifierKey and otherModifiersPressed then
        return GO
    end

    if currKey == config.modifierKey and not otherModifiersPressed then
        modifierDown = true
        produceModifier = true
        if showBarTimer then
            showBarTimer:stop()
        end
        showBarTimer = hs.timer.doAfter(config.showDelay, function()
            -- Get current selection or clipboard content
            local originalClipboard = hs.pasteboard.getContents()
            hs.eventtap.keyStroke({ "cmd" }, "c")
            hs.timer.usleep(20000) -- Wait for 20ms
            local query = hs.pasteboard.getContents() or ""
            hs.pasteboard.setContents(originalClipboard)

            getSuggestions(query, function(suggestions)
                updateSuggestions(suggestions)
                keyBar:show()
            end)
        end)
        return STOP
    end

    if modifierDown then
        if currKey == "escape" then
            cancelAnycomplete()
            return STOP
        end

        for _, mapping in ipairs(config.keyMappings) do
            if currKey:upper() == mapping[1] then
                local index = mapping[2]
                if currentSuggestions[index] then
                    produceModifier = false
                    normalKey = currentSuggestions[index]
                    highlightKey(mapping[1])
                    hs.eventtap.keyStrokes(currentSuggestions[index])
                    cancelAnycomplete()
                    return STOP
                end
            end
        end
    end

    return GO
end

local function handleKeyUp(event)
    local currKey = hs.keycodes.map[event:getKeyCode()]

    if currKey == config.modifierKey then
        modifierDown = false
        normalKey = ""
        hideKeyBar()
        if produceModifier then
            hs.eventtap.event.newKeyEvent({}, config.modifierKey, DOWN):post()
            return STOP
        end
    end

    return GO
end

function module.start()
    setupKeyBar()

    module._downWatcher = hs.eventtap.new(
        { hs.eventtap.event.types.keyDown },
        handleKeyDown
    ):start()

    module._upWatcher = hs.eventtap.new(
        { hs.eventtap.event.types.keyUp },
        handleKeyUp
    ):start()

    module._screenWatcher = hs.screen.watcher.new(function()
        setupKeyBar()
    end):start()

    module._appearanceWatcher = hs.distributednotifications.new(function(name, _, _)
        if name == "AppleInterfaceThemeChangedNotification" then
            setupKeyBar()
        end
    end):start()
end

return module
