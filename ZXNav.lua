-- ZXNav: https://github.com/sryo/Spoons/blob/main/ZXNav.lua
-- Use spacebar + ZXCVBNM, for faster text edits.
-- Based on "TouchCursor" by Kevin Li <kevinli020508@gmail.com> https://github.com/AlienKevin/touchcursor-macos
-- MIT License - https://opensource.org/licenses/MIT

local module = {}

local config = {
    keyMappings = {
        {"Z", "Home"},
        {"X", "End"},
        {"C", "Up"},
        {"V", "Down"},
        {"B", "Left"},
        {"N", "Right"},
        {"M", "Delete"},
        {",", "Return"}
    },

    modifierKey = "space",
    barHeight = 40,
    cornerRadius = 10,
    fontSize = 20,
    showDelay = 0.16
}

local function getSystemColors()
    local isDark = hs.host.interfaceStyle() == "Dark"
    return {
        barBackgroundColor = isDark and hs.drawing.color.asRGB({alpha=0.8, hex="#1E1E1E"}) or hs.drawing.color.asRGB({alpha=0.8, hex="#F0F0F0"}),
        textColor = isDark and hs.drawing.color.asRGB({hex="#FFFFFF"}) or hs.drawing.color.asRGB({hex="#000000"}),
        highlightColor = hs.drawing.color.asRGB({hex="#007AFF"})
    }
end

local STOP, GO = true, false
local DOWN, UP = true, false
local modifierDown = false
local normalKey = ""
local produceModifier = true
local keyBar
local showBarTimer

local function setupKeyBar()
    local screenFrame = hs.screen.primaryScreen():frame()
    if keyBar then
        keyBar:delete()
    end
    keyBar = hs.canvas.new({x = screenFrame.x, y = screenFrame.h - config.barHeight, w = screenFrame.w, h = config.barHeight})

    local colors = getSystemColors()

    keyBar:appendElements({
        type = "rectangle",
        action = "fill",
        fillColor = colors.barBackgroundColor,
        roundedRectRadii = {xRadius = config.cornerRadius, yRadius = config.cornerRadius},
    })

    local keyCount = #config.keyMappings
    local keyWidth = screenFrame.w / keyCount

    for i, mapping in ipairs(config.keyMappings) do
        local key, action = mapping[1], mapping[2]
        keyBar:appendElements({
            type = "text",
            text = key .. " " .. action,
            textColor = colors.textColor,
            textSize = config.fontSize,
            frame = {x = (i-1) * keyWidth, y = 5, w = keyWidth, h = config.barHeight - 10},
            textAlignment = "center"
        })
    end
end

local function highlightKey(key)
    local colors = getSystemColors()
    for i, element in ipairs(keyBar) do
        if element.type == "text" then
            element.textColor = (element.text:sub(1,1) == key)
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

local function cancelTouchCursor()
    modifierDown = false
    normalKey = ""
    produceModifier = false
    hideKeyBar()
end

local function handleKeyDown(event)
    local currKey = hs.keycodes.map[event:getKeyCode()]
    local flags = event:getFlags()
    modifiersDown = flags

    local otherModifiersPressed = flags.cmd or flags.alt or flags.shift or flags.ctrl

    if currKey == config.modifierKey and otherModifiersPressed then
        return GO
    end

    if currKey == normalKey then
        hs.eventtap.event.newKeyEvent({}, currKey, UP):post()
        return GO
    end

    if currKey == config.modifierKey and not otherModifiersPressed then
        modifierDown = true
        produceModifier = true
        if showBarTimer then
            showBarTimer:stop()
        end
        showBarTimer = hs.timer.doAfter(config.showDelay, function()
            keyBar:show()
        end)
        return STOP
    end

    if modifierDown then
        if currKey == "escape" then
            cancelTouchCursor()
            return STOP
        end

        for _, mapping in ipairs(config.keyMappings) do
            if currKey:upper() == mapping[1] then
                local newKey = mapping[2]
                produceModifier = false
                normalKey = newKey
                highlightKey(mapping[1])
                hs.eventtap.event.newKeyEvent(modifiersDown, newKey:lower(), DOWN):post()
                return STOP
            end
        end
    end

    return GO
end

local function handleKeyUp(event)
    local currKey = hs.keycodes.map[event:getKeyCode()]
    local flags = event:getFlags()
    modifiersDown = flags

    if currKey == normalKey:lower() then
        normalKey = ""
        return GO
    end

    if currKey == config.modifierKey then
        modifierDown = false
        normalKey = ""
        hideKeyBar()
        if produceModifier and not (flags.cmd or flags.alt or flags.shift or flags.ctrl) then
            normalKey = config.modifierKey
            hs.eventtap.event.newKeyEvent(modifiersDown, config.modifierKey, DOWN):post()
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

    -- Watcher for appearance changes
    module._appearanceWatcher = hs.distributednotifications.new(function(name, object, userInfo)
        if name == "AppleInterfaceThemeChangedNotification" then
            setupKeyBar()
        end
    end):start()
end

return module
