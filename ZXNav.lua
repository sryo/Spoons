-- ZXNav: https://github.com/sryo/Spoons/blob/main/ZXNav.lua
-- Use spacebar + ZXCVBNM, for faster text edits.
-- Based on "TouchCursor" by Kevin Li <kevinli020508@gmail.com> https://github.com/AlienKevin/touchcursor-macos
-- MIT License - https://opensource.org/licenses/MIT

local module = {}

local config = {
    keyMappings = {
        {"Z", "Home"},
        {"X", "End"},
        {"C", "Left"},
        {"V", "Right"},
        {"B", "Up"},
        {"N", "Down"},
        {"M", "Delete"},
        {",", "Return"}
    },

    modifierKey = "space",
    barBackgroundColor = {alpha = 0.7, white = 0.1},
    textColor = {white = 1},
    highlightColor = {red = 1, green = 1, blue = 0},
    barHeight = 30,
    cornerRadius = 0,
    fontSize = 20
}

local STOP, GO = true, false
local DOWN, UP = true, false
local modifierDown = false
local normalKey = ""
local produceModifier = true
local keyBar

local function setupKeyBar()
    local screenFrame = hs.screen.primaryScreen():frame()
    if keyBar then
        keyBar:delete()
    end
    keyBar = hs.canvas.new({x = screenFrame.x, y = screenFrame.h - config.barHeight, w = screenFrame.w, h = config.barHeight})

    keyBar:appendElements({
        type = "rectangle",
        action = "fill",
        fillColor = config.barBackgroundColor,
        roundedRectRadii = {xRadius = config.cornerRadius, yRadius = config.cornerRadius},
    })

    local keyCount = #config.keyMappings
    local keyWidth = screenFrame.w / keyCount

    for i, mapping in ipairs(config.keyMappings) do
        local key, action = mapping[1], mapping[2]
        keyBar:appendElements({
            type = "text",
            text = key .. " " .. action,
            textColor = config.textColor,
            textSize = config.fontSize,
            frame = {x = (i-1) * keyWidth, y = 5, w = keyWidth, h = config.barHeight - 10},
            textAlignment = "center"
        })
    end
end

local function highlightKey(key)
    for i, element in ipairs(keyBar) do
        if element.type == "text" then
            element.textColor = (element.text:sub(1,1) == key)
                and config.highlightColor
                or config.textColor
        end
    end
    keyBar:show()
end

local function resetKeyHighlights()
    for i, element in ipairs(keyBar) do
        if element.type == "text" then
            element.textColor = config.textColor
        end
    end
end

local function hideKeyBar()
    resetKeyHighlights()
    keyBar:hide()
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

    -- Check if any modifier keys (except fn) are pressed
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
        keyBar:show()
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

    -- Add screen watcher to update bar on resolution changes
    module._screenWatcher = hs.screen.watcher.new(function()
        setupKeyBar()
    end):start()
end

function module.stop()
    if module._downWatcher then
        module._downWatcher:stop()
        module._downWatcher = nil
    end
    if module._upWatcher then
        module._upWatcher:stop()
        module._upWatcher = nil
    end
    if module._screenWatcher then
        module._screenWatcher:stop()
        module._screenWatcher = nil
    end
    if keyBar then
        keyBar:delete()
        keyBar = nil
    end
end

return module
