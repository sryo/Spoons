-- ZXNav: https://github.com/sryo/Spoons/blob/main/ZXNav.lua
-- Use spacebar + ZXCVBNM, for faster text edits.
-- Based on "TouchCursor" by Kevin Li <kevinli020508@gmail.com> https://github.com/AlienKevin/touchcursor-macos
-- MIT License - https://opensource.org/licenses/MIT

local module = {}

local config = {
    -- Inner ring: bottom row (ZXCVBNM,./)
    innerMappings = {
        { "Z", "Home" },
        { "X", "End" },
        { "C", "Up" },
        { "V", "Down" },
        { "B", "Left" },
        { "N", "Right" },
        { "M", "Del" },
        { ",", "Return" },
        { ".", "Tab" },
        { "/", "Esc" }
    },

    -- Outer ring: home row (ASDFGHJKL;)
    outerMappings = {
        { "A", "SelAll" },
        { "S", "Save" },
        { "D", "DelWord" },
        { "F", "Find" },
        { "G", "Next" },
        { "H", "WordL" },
        { "J", "PgDn" },
        { "K", "PgUp" },
        { "L", "WordR" },
        { ";", "Undo" }
    },

    modifierKey = "space",
    outerRadius = 240,
    middleRadius = 170,
    innerRadius = 50,
    fontSize = 14,
    showDelay = 0
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
local originalKey = "" -- track the original key pressed
local produceModifier = true
local keyBar
local showBarTimer
local safetyTimer        -- auto-release if held too long
local SAFETY_TIMEOUT = 8 -- seconds

-- Track ALL held mapped keys
-- Key: action key name, Value: {mods = {}, key = "keyname"}
local heldMappedKeys = {}

-- Release ALL held mapped keys (called when spacebar is released)
local function releaseAllMappedKeys()
    for actionKey, action in pairs(heldMappedKeys) do
        hs.eventtap.event.newKeyEvent(action.mods, action.key, UP):post()
    end
    heldMappedKeys = {}
end

local function drawRing(keyBar, mappings, outerR, innerR, size, colors, isDark, textPosition)
    local keyCount = #mappings
    local arcSpan = math.pi
    local startAngle = math.pi

    for i, mapping in ipairs(mappings) do
        local key, action = mapping[1], mapping[2]
        local sliceAngle = arcSpan / keyCount
        local angle1 = startAngle - (i - 1) * sliceAngle
        local angle2 = startAngle - i * sliceAngle

        -- Slice background
        local path = {
            { x = size / 2 + innerR * math.cos(angle1), y = config.outerRadius + 10 - innerR * math.sin(angle1) }
        }
        -- Outer arc
        for j = 0, 8 do
            local a = angle1 + (angle2 - angle1) * j / 8
            table.insert(path,
                { x = size / 2 + outerR * math.cos(a), y = config.outerRadius + 10 - outerR * math.sin(a) })
        end
        -- Inner arc (reverse)
        for j = 8, 0, -1 do
            local a = angle1 + (angle2 - angle1) * j / 8
            table.insert(path,
                { x = size / 2 + innerR * math.cos(a), y = config.outerRadius + 10 - innerR * math.sin(a) })
        end

        keyBar:appendElements({
            type = "segments",
            action = "fill",
            coordinates = path,
            fillColor = colors.barBackgroundColor,
            closed = true,
            id = "slice_" .. key
        })

        keyBar:appendElements({
            type = "segments",
            action = "stroke",
            coordinates = path,
            strokeColor = { white = isDark and 1 or 0, alpha = 0.2 },
            strokeWidth = 1,
            closed = true
        })

        -- Text label
        local midAngle = (angle1 + angle2) / 2
        local textRadius = innerR + (outerR - innerR) * (textPosition or 0.5)
        local textX = size / 2 + textRadius * math.cos(midAngle)
        local textY = config.outerRadius + 10 - textRadius * math.sin(midAngle)

        keyBar:appendElements({
            type = "text",
            text = key .. "\n" .. action,
            textColor = colors.textColor,
            textSize = config.fontSize,
            frame = { x = textX - 30, y = textY - 16, w = 60, h = 36 },
            textAlignment = "center",
            id = "key_" .. key
        })
    end
end

local function setupKeyBar()
    local screenFrame = hs.screen.primaryScreen():frame()
    if keyBar then
        keyBar:delete()
    end

    local centerX = screenFrame.w / 2
    local size = config.outerRadius * 2 + 40

    keyBar = hs.canvas.new({
        x = screenFrame.x + centerX - size / 2,
        y = screenFrame.h - config.outerRadius - 20,
        w = size,
        h = config.outerRadius + 20
    })
    keyBar:level(hs.canvas.windowLevels.overlay)
    keyBar:behavior("canJoinAllSpaces")

    local colors = getSystemColors()
    local isDark = hs.host.interfaceStyle() == "Dark"

    -- Draw inner ring (bottom row: ZXCVBNM,./)
    drawRing(keyBar, config.innerMappings, config.outerRadius, config.innerRadius, size, colors, isDark, 0.5)

    -- Outer ring disabled for now
    -- drawRing(keyBar, config.outerMappings, config.outerRadius, config.middleRadius, size, colors, isDark, 0.5)
end

local function highlightKey(key)
    local colors = getSystemColors()
    for i = 1, #keyBar do
        local element = keyBar[i]
        if element.id == "slice_" .. key then
            keyBar[i].fillColor = colors.highlightColor
        elseif element.id and element.id:match("^slice_") then
            keyBar[i].fillColor = colors.barBackgroundColor
        end
        if element.id == "key_" .. key then
            keyBar[i].textColor = { white = 1, alpha = 1 }
        elseif element.id and element.id:match("^key_") then
            keyBar[i].textColor = colors.textColor
        end
    end
end

local function resetKeyHighlights()
    local colors = getSystemColors()
    for i = 1, #keyBar do
        local element = keyBar[i]
        if element.id and element.id:match("^slice_") then
            keyBar[i].fillColor = colors.barBackgroundColor
        end
        if element.id and element.id:match("^key_") then
            keyBar[i].textColor = colors.textColor
        end
    end
end

local function hideKeyBar()
    resetKeyHighlights()
    keyBar:hide()
    if showBarTimer then
        showBarTimer:stop()
    end
    if safetyTimer then
        safetyTimer:stop()
        safetyTimer = nil
    end
end

local function cancelTouchCursor()
    modifierDown = false
    normalKey = ""
    originalKey = ""
    produceModifier = false
    releaseAllMappedKeys()
    hideKeyBar()
end

-- Map action names to actual key events
local actionMap = {
    -- Inner ring (navigation)
    Home = { key = "home", mods = {} },
    End = { key = "end", mods = {} },
    Up = { key = "up", mods = {} },
    Down = { key = "down", mods = {} },
    Left = { key = "left", mods = {} },
    Right = { key = "right", mods = {} },
    Del = { key = "forwarddelete", mods = {} },
    Return = { key = "return", mods = {} },
    Tab = { key = "tab", mods = {} },
    Esc = { key = "escape", mods = {} },
    -- Outer ring (commands)
    SelAll = { key = "a", mods = { cmd = true } },
    Save = { key = "s", mods = { cmd = true } },
    DelWord = { key = "forwarddelete", mods = { alt = true } },
    Find = { key = "f", mods = { cmd = true } },
    Next = { key = "g", mods = { cmd = true } },
    WordL = { key = "left", mods = { alt = true } },
    PgDn = { key = "pagedown", mods = {} },
    PgUp = { key = "pageup", mods = {} },
    WordR = { key = "right", mods = { alt = true } },
    Undo = { key = "z", mods = { cmd = true } }
}

-- Kill sequence: release all potentially stuck keys (Cmd+Shift+Escape)
local function killSequence()
    -- Stop eventtaps first so they don't intercept our UP events
    if module._downWatcher then module._downWatcher:stop() end
    if module._upWatcher then module._upWatcher:stop() end

    -- Release tracked held keys first
    for _, action in pairs(heldMappedKeys) do
        hs.eventtap.event.newKeyEvent(action.mods, action.key, UP):post()
    end
    heldMappedKeys = {}

    -- Reset internal state
    modifierDown = false
    normalKey = ""
    originalKey = ""
    produceModifier = true
    hideKeyBar()

    -- Release spacebar
    hs.eventtap.event.newKeyEvent({}, "space", UP):post()

    -- Release all possible action keys (belt and suspenders)
    for _, action in pairs(actionMap) do
        hs.eventtap.event.newKeyEvent(action.mods, action.key, UP):post()
    end

    -- Release modifiers
    hs.eventtap.event.newKeyEvent({}, "cmd", UP):post()
    hs.eventtap.event.newKeyEvent({}, "alt", UP):post()
    hs.eventtap.event.newKeyEvent({}, "shift", UP):post()
    hs.eventtap.event.newKeyEvent({}, "ctrl", UP):post()

    -- Small delay then restart eventtaps
    hs.timer.doAfter(0.1, function()
        if module._downWatcher then module._downWatcher:start() end
        if module._upWatcher then module._upWatcher:start() end
    end)

    hs.alert.show("ZXNav: Reset", 0.5)
end

-- Nuclear option: completely stop ZXNav
local function stopZXNav()
    if module._downWatcher then module._downWatcher:stop() end
    if module._upWatcher then module._upWatcher:stop() end
    releaseAllMappedKeys()
    modifierDown = false
    normalKey = ""
    originalKey = ""
    produceModifier = true
    hideKeyBar()
    hs.alert.show("ZXNav: Stopped (run ZXNav.start() to restart)", 1)
end

-- Export for manual triggering
module.kill = killSequence
module.stop = stopZXNav

local function findMapping(key)
    for _, mapping in ipairs(config.innerMappings) do
        if key:upper() == mapping[1]:upper() then
            return mapping
        end
    end
    -- Outer ring disabled for now
    -- for _, mapping in ipairs(config.outerMappings) do
    --     if key:upper() == mapping[1]:upper() then
    --         return mapping
    --     end
    -- end
    return nil
end

local function handleKeyDown(event)
    local currKey = hs.keycodes.map[event:getKeyCode()]
    local flags = event:getFlags()

    if currKey == "escape" and not modifierDown then
        return GO
    end

    local otherModifiersPressed = flags.cmd or flags.alt or flags.shift or flags.ctrl

    if currKey == config.modifierKey and otherModifiersPressed then
        return GO
    end

    -- Handle key repeat (only when NOT in modifier mode, to avoid catching our own synthetic events)
    if currKey == normalKey and not modifierDown and not otherModifiersPressed then
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
        -- Safety timer: auto-release if held too long
        if safetyTimer then
            safetyTimer:stop()
        end
        safetyTimer = hs.timer.doAfter(SAFETY_TIMEOUT, function()
            if modifierDown then
                hs.alert.show("ZXNav: Safety release", 0.5)
                module.kill()
            end
        end)
        return STOP
    end

    if modifierDown then
        if currKey == "escape" then
            cancelTouchCursor()
            return STOP
        end

        local mapping = findMapping(currKey)
        if mapping then
            local action = actionMap[mapping[2]]
            if action then
                produceModifier = false
                normalKey = action.key
                originalKey = currKey
                highlightKey(mapping[1])
                -- Track this held key
                heldMappedKeys[currKey] = action
                hs.eventtap.event.newKeyEvent(action.mods, action.key, DOWN):post()
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

    -- Navigation key released - release that specific action key
    if heldMappedKeys[currKey] then
        local action = heldMappedKeys[currKey]
        hs.eventtap.event.newKeyEvent(action.mods, action.key, UP):post()
        heldMappedKeys[currKey] = nil
        -- Reset if this was the current key
        if currKey == originalKey then
            normalKey = ""
            originalKey = ""
        end
        return GO
    end

    -- Spacebar released
    if currKey == config.modifierKey then
        modifierDown = false
        -- Release ALL held mapped keys
        releaseAllMappedKeys()
        hideKeyBar()
        normalKey = ""
        originalKey = ""
        -- If no nav key was pressed, produce a space
        if produceModifier and not (flags.cmd or flags.alt or flags.shift or flags.ctrl) then
            produceModifier = false -- Prevent re-entry
            -- Defer keystroke to after this callback returns, with eventtaps stopped
            hs.timer.doAfter(0, function()
                if module._downWatcher then module._downWatcher:stop() end
                if module._upWatcher then module._upWatcher:stop() end
                hs.eventtap.keyStroke({}, "space", 0)
                if module._downWatcher then module._downWatcher:start() end
                if module._upWatcher then module._upWatcher:start() end
            end)
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

    -- Kill sequence hotkey: Cmd+Shift+Escape
    module._killHotkey = hs.hotkey.bind({ "cmd", "shift" }, "escape", killSequence)
end

return module
