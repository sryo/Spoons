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
    innerRadius = 140,
    fontSize = 14,
    showDelay = 0.15
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

-- Tag synthetic events so our own watchers ignore them. Stop / start of the
-- eventtap around a synthetic post is racy: events are queued and delivered
-- after :post() returns, so the just-restarted watcher swallows the very
-- space it just sent.
local CLICK_TAG     = 0x5A584E -- "ZXN"
local PROP_USERDATA = hs.eventtap.event.properties.eventSourceUserData

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

-- Customization: click a slice to rebind, long-press to reset, esc / outside
-- click to cancel. Bindings persist via hs.settings.
local customBindings   = {}     -- { [SliceLetter] = { key = "...", label = "..." } }
local editMode         = nil    -- nil | { slice = "Z" }
local longPressTimer   = nil
local longPressSlice   = nil
local editDismissTap   = nil
local LONG_PRESS_SEC   = 0.5
local EDIT_FILL        = hs.drawing.color.asRGB({ alpha = 0.9, hex = "#FF9500" })

local PURE_MODIFIERS   = {
    cmd = true, alt = true, shift = true, ctrl = true,
    fn = true, capslock = true, rightcmd = true, rightalt = true,
    rightshift = true, rightctrl = true,
}

local KEY_LABELS = {
    pageup = "PgUp", pagedown = "PgDn",
    left = "←", right = "→", up = "↑", down = "↓",
    forwarddelete = "Del", delete = "Bksp",
    ["return"] = "↵", tab = "⇥", escape = "Esc",
    home = "Home", ["end"] = "End", space = "Spc",
}

local function renderLabel(key)
    return KEY_LABELS[key] or key:upper()
end

local function loadBindings()
    customBindings = hs.settings.get("ZXNav.customBindings") or {}
end

local function saveBindings()
    hs.settings.set("ZXNav.customBindings", customBindings)
end

local function defaultLabelFor(letter)
    for _, m in ipairs(config.innerMappings) do
        if m[1] == letter then return m[2] end
    end
    return ""
end

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
        local key = mapping[1]
        local action = (customBindings[key] and customBindings[key].label) or mapping[2]
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
            id = "slice_" .. key,
            trackMouseDown = true,
            trackMouseUp = true,
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
    local screenFrame = hs.screen.primaryScreen():fullFrame()
    if keyBar then
        keyBar:delete()
    end

    local centerX = screenFrame.w / 2
    local size = config.outerRadius * 2 + 40

    keyBar = hs.canvas.new({
        x = screenFrame.x + centerX - size / 2,
        y = screenFrame.y + screenFrame.h - config.outerRadius - 10,
        w = size,
        h = config.outerRadius + 20
    })
    keyBar:level(hs.canvas.windowLevels.overlay)
    keyBar:behavior("canJoinAllSpaces")
    keyBar:canvasMouseEvents(true, true)
    keyBar:mouseCallback(function(_, msg, id, _, _)
        if not id then return end
        local letter = id:match("^slice_(.+)$") or id:match("^key_(.+)$")
        if not letter then return end
        if msg == "mouseDown" then
            longPressSlice = letter
            if longPressTimer then longPressTimer:stop() end
            longPressTimer = hs.timer.doAfter(LONG_PRESS_SEC, function()
                longPressTimer = nil
                if longPressSlice == letter then
                    longPressSlice = nil
                    resetSliceToDefault(letter)
                end
            end)
        elseif msg == "mouseUp" then
            if longPressTimer then
                longPressTimer:stop()
                longPressTimer = nil
                longPressSlice = nil
                produceModifier = false
                enterEditMode(letter)
            end
        end
    end)

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

local function repaintSlice(letter)
    local label = (customBindings[letter] and customBindings[letter].label) or defaultLabelFor(letter)
    local colors = getSystemColors()
    for i = 1, #keyBar do
        local el = keyBar[i]
        if el.id == "key_" .. letter then
            keyBar[i].text = letter .. "\n" .. label
        elseif el.id == "slice_" .. letter then
            keyBar[i].fillColor = colors.barBackgroundColor
        end
    end
end

local function stopEditDismissTap()
    if editDismissTap then editDismissTap:stop(); editDismissTap = nil end
end

local function cancelEditMode()
    if not editMode then return end
    local letter = editMode.slice
    editMode = nil
    stopEditDismissTap()
    repaintSlice(letter)
    hideKeyBar()
end

local function startEditDismissTap()
    stopEditDismissTap()
    editDismissTap = hs.eventtap.new({ hs.eventtap.event.types.leftMouseDown }, function(e)
        if not editMode or not keyBar then return false end
        local f = keyBar:frame()
        local p = e:location()
        local inside = p.x >= f.x and p.x <= f.x + f.w
            and p.y >= f.y and p.y <= f.y + f.h
        if not inside then cancelEditMode() end
        return false
    end):start()
end

local function enterEditMode(letter)
    editMode = { slice = letter }
    for i = 1, #keyBar do
        local el = keyBar[i]
        if el.id == "slice_" .. letter then
            keyBar[i].fillColor = EDIT_FILL
        elseif el.id == "key_" .. letter then
            keyBar[i].text = letter .. "\n…?"
        end
    end
    startEditDismissTap()
end

local function exitEditMode()
    if not editMode then return end
    local letter = editMode.slice
    editMode = nil
    stopEditDismissTap()
    repaintSlice(letter)
    hideKeyBar()
end

local function resetSliceToDefault(letter)
    customBindings[letter] = nil
    saveBindings()
    repaintSlice(letter)
    hs.alert.show("ZXNav: reset " .. letter, 0.4)
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
    if event:getProperty(PROP_USERDATA) == CLICK_TAG then return GO end

    local currKey = hs.keycodes.map[event:getKeyCode()]
    local flags = event:getFlags()

    if editMode then
        if currKey == "escape" then
            cancelEditMode()
            return STOP
        end
        if PURE_MODIFIERS[currKey] or currKey == "space" then
            return STOP
        end
        customBindings[editMode.slice] = { key = currKey, label = renderLabel(currKey) }
        saveBindings()
        exitEditMode()
        return STOP
    end

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
            local sliceLetter = mapping[1]
            local custom = customBindings[sliceLetter]
            local action = custom
                and { key = custom.key, mods = {} }
                or actionMap[mapping[2]]
            if action then
                produceModifier = false
                normalKey = action.key
                originalKey = currKey
                highlightKey(sliceLetter)
                heldMappedKeys[currKey] = action
                hs.eventtap.event.newKeyEvent(action.mods, action.key, DOWN):post()
                return STOP
            end
        end
    end

    return GO
end

local function handleKeyUp(event)
    if event:getProperty(PROP_USERDATA) == CLICK_TAG then return GO end

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
        if not editMode then hideKeyBar() end
        normalKey = ""
        originalKey = ""
        -- If no nav key was pressed, produce a space
        if produceModifier and not (flags.cmd or flags.alt or flags.shift or flags.ctrl) then
            produceModifier = false -- Prevent re-entry
            -- Tagged synthetic events bypass our handlers via the CLICK_TAG
            -- check at the top of handleKeyDown / handleKeyUp.
            hs.timer.doAfter(0, function()
                local d = hs.eventtap.event.newKeyEvent({}, "space", DOWN)
                local u = hs.eventtap.event.newKeyEvent({}, "space", UP)
                d:setProperty(PROP_USERDATA, CLICK_TAG)
                u:setProperty(PROP_USERDATA, CLICK_TAG)
                d:post()
                u:post()
            end)
            return STOP
        end
    end

    return GO
end

function module.start()
    loadBindings()
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
