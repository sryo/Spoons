-- TrackpadKeys: https://github.com/sryo/Spoons/blob/main/TrackpadKeys.lua
-- This adds a row of keys to the top of the trackpad.

local TrackpadKeys = {}

TrackpadKeys.config = {
    showKeyPreview = true,
    keyPreviewDuration = 1,
    cornerActivationArea = 0.15,
    messageDuration = 0.5,
    circleFillDuration = 0.1,
    debug = false
}

local keyboard = {
    "escape", "q", "a", "z", "w", "s", "x", "e", "d", "c", "r", "f", "v", "t", "g", "b", "y", "h", "n", "u", "j", "m", "i", "k", ",", "o", "l", ".", "p", "ñ", "-", "space", "delete", "return"
}

local symbols = {
    space = "___",
    ["return"] = "↵",
    delete = "⌫",
    escape = "⎋"
}

local keyboardZone = {
    y = 0.97,
    height = 0.03
}

local cornerZone = {
    y = 0,
    height = 0.15,
    leftWidth = 0.15,
    rightWidth = 0.15
}

local currentKey = nil
local isKeyEmitted = false
local keyboardTouch = nil
local cornerTouch = nil
local circleFillTimer = nil
local lastTouchPosition = nil
local lastTouchCount = 0

local function debugPrint(message)
    if TrackpadKeys.config.debug then
        print(os.date("%H:%M:%S").." [TW] "..message)
    end
end

local function getKeyPreviewPosition()
    local screenSize = hs.screen.mainScreen():frame()
    return (screenSize.w - 30) / 2, screenSize.h - 100
end

local keyPreviewX, keyPreviewY = getKeyPreviewPosition()

local keyPreview = hs.canvas.new({x = keyPreviewX, y = keyPreviewY, w = 250, h = 50})
keyPreview[1] = {
    type = "rectangle",
    action = "fill",
    roundedRectRadii = { xRadius = 4, yRadius = 4 },
    fillColor = { white = 0, alpha = 0.75 }
}

for i = 1, 5 do
    keyPreview[i + 1] = {
        type = "text",
        text = "",
        textColor = { white = 1, alpha = 1 },
        textAlignment = "center",
        textSize = 20,
        frame = { x = (i-1)*50, y = 10, w = 50, h = 30 }
    }
end

keyPreview[7] = {
    type = "circle",
    action = "stroke",
    strokeColor = { red = 1, green = 1, blue = 0, alpha = 1 },
    strokeWidth = 2,
    center = { x = 125, y = 25 },
    radius = 0
}

local messageCanvas = hs.canvas.new({x = keyPreviewX, y = keyPreviewY, w = 250, h = 50})
messageCanvas[1] = {
    type = "rectangle",
    action = "fill",
    roundedRectRadii = { xRadius = 4, yRadius = 4 },
    fillColor = { white = 0, alpha = 0.75 }
}
messageCanvas[2] = {
    type = "text",
    text = "",
    textColor = { white = 1, alpha = 1 },
    textAlignment = "center",
    textSize = 16,
    frame = { x = 0, y = 15, w = 250, h = 20 }
}

local function showMessage(message)
    messageCanvas[2].text = message
    messageCanvas:show()

    if messageTimer then
        messageTimer:stop()
    end

    messageTimer = hs.timer.doAfter(TrackpadKeys.config.messageDuration, function()
        messageCanvas:hide()
    end)
end

local function updatePressureCircle(pressure, fill)
    local maxRadius = 1
    local radius = pressure * maxRadius
    keyPreview[7].radius = radius
    if fill then
        keyPreview[7].action = "fill"
        keyPreview[7].fillColor = { red = 1, green = 1, blue = 0, alpha = 1 }
    else
        keyPreview[7].action = "stroke"
        keyPreview[7].strokeColor = { red = 1, green = 1, blue = 0, alpha = 1 }
    end
    keyPreview:show()
end

local function getSelectedKey(pos)
    local index = math.floor(pos.x * #keyboard) + 1
    return math.min(index, #keyboard)
end

local function showKeyPreview(index, isModified)
    if keyPreviewTimer then
        keyPreviewTimer:stop()
    end

    keyPreviewTimer = hs.timer.doAfter(TrackpadKeys.config.keyPreviewDuration, function()
        keyPreview:hide()
    end)

    for i = 1, 5 do
        local keyIndex = index - 3 + i
        if keyIndex >= 1 and keyIndex <= #keyboard then
            local key = keyboard[keyIndex]
            local displayKey = symbols[key] or key
            if isModified and #key == 1 then
                displayKey = displayKey:upper()
            end
            keyPreview[i + 1].text = displayKey
            keyPreview[i + 1].textColor = (i == 3) and 
                (isKeyEmitted and { white = 1, alpha = 1 } or { red = 1, green = 1, blue = 0, alpha = 1 }) or
                { white = 1, alpha = 1 }
        else
            keyPreview[i + 1].text = ""
        end
    end

    keyPreview:show()
end

local function emitKey(key, isModified, touchPosition)
    local modifiers = isModified and {"shift"} or {}
    local emittedKey = isModified and key:upper() or key
    
    hs.eventtap.keyStroke(modifiers, emittedKey)
    debugPrint("Emitting key: " .. emittedKey)

    isKeyEmitted = true
    updatePressureCircle(1, true)
    showKeyPreview(getSelectedKey(touchPosition), isModified)

    if circleFillTimer then
        circleFillTimer:stop()
    end
    circleFillTimer = hs.timer.doAfter(TrackpadKeys.config.circleFillDuration, function()
        isKeyEmitted = false
        updatePressureCircle(0, false)
        showKeyPreview(getSelectedKey(touchPosition), isModified)
    end)

    showMessage("Emitted: " .. emittedKey)
    return emittedKey
end

local function isInCorner(pos)
    return (pos.y <= cornerZone.y + cornerZone.height) and
           (pos.x <= cornerZone.leftWidth or pos.x >= 1 - cornerZone.rightWidth)
end

local function resetState()
    currentKey = nil
    isKeyEmitted = false
    keyboardTouch = nil
    cornerTouch = nil
    lastTouchPosition = nil
    if circleFillTimer then
        circleFillTimer:stop()
    end
    keyPreview:hide()
    messageCanvas:hide()
    debugPrint("TrackpadKeys state reset")
end

local function handleTouches(touches)
    local newKeyboardTouch = nil
    local newCornerTouch = nil
    local gestureEnded = (#touches == 0)

    for _, touch in ipairs(touches) do
        if touch.type == "indirect" and touch.normalizedPosition then
            if touch.normalizedPosition.y >= keyboardZone.y and 
               touch.normalizedPosition.y <= keyboardZone.y + keyboardZone.height then
                newKeyboardTouch = touch
            elseif isInCorner(touch.normalizedPosition) then
                newCornerTouch = touch
            end
        end
    end

    if newKeyboardTouch then
        local index = getSelectedKey(newKeyboardTouch.normalizedPosition)
        local newKey = keyboard[index]
        local isModified = cornerTouch ~= nil or newCornerTouch ~= nil

        if newKey ~= currentKey or lastTouchPosition == nil then
            currentKey = newKey
            showKeyPreview(index, isModified)
            debugPrint("Key selected: " .. currentKey .. ", Modified: " .. tostring(isModified))
        end

        updatePressureCircle(newKeyboardTouch.force, isKeyEmitted)

        debugPrint("Touch position: y=" .. newKeyboardTouch.normalizedPosition.y .. ", Pressure: " .. newKeyboardTouch.force)
        lastTouchPosition = newKeyboardTouch.normalizedPosition
    end

    local touchCount = #touches
    debugPrint("Touch count: " .. touchCount .. ", Last touch count: " .. lastTouchCount)

    if keyboardTouch and not newKeyboardTouch and touchCount < lastTouchCount then
        debugPrint("Touch ended. Last position: " .. (lastTouchPosition and ("y=" .. lastTouchPosition.y) or "unknown"))
        if currentKey and lastTouchPosition and 
           lastTouchPosition.y >= keyboardZone.y and 
           lastTouchPosition.y <= keyboardZone.y + keyboardZone.height then
            local isModified = cornerTouch ~= nil or newCornerTouch ~= nil
            debugPrint("Finger lifted in key zone. Emitting key: " .. currentKey)
            local emittedKey = emitKey(currentKey, isModified, lastTouchPosition)
        else
            debugPrint("Touch ended outside key zone or no key selected. No key emitted.")
            keyPreview:hide()
            showMessage("No key emitted")
        end
        currentKey = nil
    elseif keyboardTouch and not newKeyboardTouch then
        debugPrint("Touch moved out of keyboard zone. Cancelling key emission.")
        keyPreview:hide()
        showMessage("Key cancelled")
        currentKey = nil
    elseif keyboardTouch and newKeyboardTouch then
        if lastTouchPosition and 
           (lastTouchPosition.y < keyboardZone.y or lastTouchPosition.y > keyboardZone.y + keyboardZone.height) and
           (newKeyboardTouch.normalizedPosition.y >= keyboardZone.y and newKeyboardTouch.normalizedPosition.y <= keyboardZone.y + keyboardZone.height) then
            debugPrint("Finger moved into keyboard zone.")
        end
    end

    keyboardTouch = newKeyboardTouch
    cornerTouch = newCornerTouch
    lastTouchPosition = newKeyboardTouch and newKeyboardTouch.normalizedPosition or lastTouchPosition
    lastTouchCount = touchCount

    if gestureEnded then
        resetState()
    end
end

local function start()
    local gestureEventtap = hs.eventtap.new({hs.eventtap.event.types.gesture}, function(e)
        local touches = e:getTouches()
        if touches then
            handleTouches(touches)
        end
    end)

    local escapeEventtap = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(e)
        local keyCode = e:getKeyCode()
        if keyCode == hs.keycodes.map.escape then
            resetState()
            return true
        end
        return false
    end)

    gestureEventtap:start()
    escapeEventtap:start()
    debugPrint("TrackpadKeys started")
    return gestureEventtap, escapeEventtap
end

local gestureEventtap, escapeEventtap = start()

function TrackpadKeys.stop()
    if gestureEventtap then
        gestureEventtap:stop()
    end
    if escapeEventtap then
        escapeEventtap:stop()
    end
    debugPrint("TrackpadKeys stopped")
end

return TrackpadKeys
