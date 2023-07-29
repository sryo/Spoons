-- TrackpadWizard: https://github.com/sryo/Spoons/blob/main/TrackpadWizard.lua
-- This enables customizable trackpad gestures, allowing users to define zones on their trackpad that can trigger specific actions, and includes a gesture crafting mode for defining new zones.

local config = {
    forceThreshold         = 60,
    scrollUnit             = "pixel",
    scrollAmount           = {0, 3},
    scrollRepetitionSpeed  = 0.002,
    directionResetTimeout  = .35,
    showKeyPreview         = true,
    keyPreviewDuration     = 1,
    debug                  = false
}

local activeTouches = {}
local lastScrollTime = nil
local scrollDirection = -1
local gestureEnded = false
local gestureCraft = false
local craftTouchStart, craftTouchEnd = nil, nil

local zones = {
    {
        friendlyName = "Scroll",
        x = 0, y = 0, width = .75, height = 0.02,
        actions = {
            ["none"] = function(touchID, touch)
                activeTouches[touchID] = hs.timer.doWhile(function() return activeTouches[touchID] ~= nil end, function() 
                    local scrollAmount = {0, config.scrollAmount[2] * scrollDirection}
                    hs.eventtap.event.newScrollEvent(scrollAmount, {}, config.scrollUnit):post()
                end, config.scrollRepetitionSpeed)
            end
        }
    },
    {
        friendlyName = "Undo/Redo",
        x = 0.75, y = 0, width = 0.25, height = 0.02,
        actions = {
            ["none"] = function(touchID, touch)
                keyRepeatAction(touchID, "z", {"cmd"})
            end,
            ["shift"] = function(touchID, touch)
                keyRepeatAction(touchID, "z", {"cmd", "shift"})
            end,
        }
    },
    {
        friendlyName = "Keyboard",
        x = 0, y = 0.8, width = 1, height = 0.2,
        actions = {
            ["none"] = function(touchID, touch)
                local x, y = getGridCell(touch.normalizedPosition, 11, 3)
                emitKey(x, y, touchID, touch)
            end,
            ["ended"] = function(touchID, touch)
                activeTouches[touchID] = nil
            end
        }
    },
-- To add a new zone, define the friendlyName, x and y coordinates, width, and height, as well as the actions for the zone.
-- The x and y coordinates, as well as width and height are normalized to (0 - 1), relative to the trackpad's surface. This means 1 corresponds to the full width/height of the trackpad.
-- 'friendlyName' is a human-readable name for the zone that can be printed when the zone is touched for easier debugging.
-- 'actions' is a table that maps the touch events to functions that are called when the zone is touched with that event. Current events are 'none' for a touch with no modifiers and 'ended' for when a touch ends.
-- Each function in 'actions' receives the ID of the touch and the touch event itself as arguments.
}

local keyboard = {
    {"q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "escape"},
    {"a", "s", "d", "f", "g", "h", "j", "k", "l", "ñ", "delete"},
    {"z", "x", "c", "v", "b", "n", "m", ",", ".", "-", "space", "enterKey"}
}

local symbols = {
    escape = "⎋",
    delete = "⌫",
    space = "⎵",
    enterKey = "⏎"
}

function getNearbyKeys(x, y)
    local nearbyKeys = {{"", "", ""}, {"", "", ""}, {"", "", ""}}
    for j = math.max(1, y-1), math.min(#keyboard, y+1) do
        for i = math.max(1, x-1), math.min(#keyboard[j], x+1) do
            local key = keyboard[j][i]
            nearbyKeys[j - y + 2][i - x + 2] = symbols[key] or key
        end
    end
    return nearbyKeys
end

local function getKeyPreviewPosition()
    local screenSize = hs.screen.mainScreen():frame()
    return (screenSize.w - 30) / 2, screenSize.h - 100
end

local keyPreviewX, keyPreviewY = getKeyPreviewPosition()

local keyPreview = hs.canvas.new({x = keyPreviewX, y = keyPreviewY, w = 100, h = 100})
keyPreview[1] = {
    type = "rectangle",
    action = "fill",
    roundedRectRadii = { xRadius = 4, yRadius = 4 },
    fillColor = { white = 0, alpha = 0.75 }
}

local gridPadding = 10
local cellWidth = (100 - 4 * gridPadding) / 3
local cellHeight = cellWidth

for i = 1, 9 do
    local row = math.floor((i - 1) / 3)
    local column = (i - 1) % 3
    keyPreview[i + 1] = {
        type = "text",
        text = "",
        textColor = { white = 1, alpha = 1 },
        textAlignment = "center",
        textSize = 16,
        frame = {
            x = column * (cellWidth + gridPadding) + gridPadding,
            y = row * (cellHeight + gridPadding) + gridPadding,
            w = cellWidth,
            h = cellHeight
        }
    }
end

function showKeyPreview(key, nearbyKeys, isTouching)
    if keyPreviewTimer then
        keyPreviewTimer:stop()
    end

    keyPreviewTimer = hs.timer.doAfter(config.keyPreviewDuration, function()
        keyPreview:hide()
    end)

    if key == "" or not isTouching then
        keyPreview:hide()
        return
    end

    if not config.showKeyPreview or not key or key == "" then
        return
    end

    local positions = {
        {1, 2, 3},
        {4, 5, 6},
        {7, 8, 9}
    }

    for i = 1, 3 do
        for j = 1, #positions[i] do
            keyPreview[positions[i][j] + 1].text = nearbyKeys[i][j] or ""
            if i == 2 and j == 2 then
                keyPreview[positions[i][j] + 1].textColor = { red = 1, green = 1, blue = 0, alpha = 1 }
            else
                keyPreview[positions[i][j] + 1].textColor = { white = 1, alpha = 1 }
            end
        end
    end

    keyPreview:show()
end

local keystrokeSent = {}

function keyRepeatAction(touchID, key, modifiers)
    if not keystrokeSent[touchID] then
        activeTouches[touchID] = true
        hs.eventtap.keyStroke(modifiers, key)
        keystrokeSent[touchID] = true
    end
end

function getGridCell(pos, numColumns, numRows)
    local adjustedX = pos.x
    local adjustedY = (pos.y - 0.8) / 0.2
    local x = math.min(math.floor(adjustedX * numColumns) + 1, numColumns)
    local y = numRows - math.min(math.floor(adjustedY * numRows) + 1, numRows) + 1
    debugPrint(string.format("Normalized position: %.2f, %.2f Grid cell: %d, %d", adjustedX, adjustedY, x, y))
    return x, y
end

function emitKey(x, y, touchID, touch)
    debugPrint("emitKey called with x: " .. tostring(x) .. ", y: " .. tostring(y))
    local keyToPreview = nil
    if keyboard[y] and keyboard[y][x] and keyboard[y][x] ~= "" then
        local key = keyboard[y][x]
        debugPrint("Key at cell " .. tostring(x) .. ", " .. tostring(y) .. " is: " .. key)
        if touch.force < config.forceThreshold then
            debugPrint("Touch force is less than forceThreshold. Calling showKeyPreview...")
            keyToPreview = key
            local nearbyKeys = getNearbyKeys(x, y)
            showKeyPreview(keyToPreview, nearbyKeys, touch.touching)
        else
            debugPrint("Touch force is equal or greater than forceThreshold. Sending key event...")
            keyRepeatAction(touchID, key, {})
        end
    else
        debugPrint("No key found at cell " .. tostring(x) .. ", " .. tostring(y))
    end
end


local zoneCounter = 0

local function enterGestureCraft()
    gestureCraft = true
    debugPrint("Gesture Craft mode entered. Please make a diagonal gesture across your desired zone.")
    zoneCounter = zoneCounter + 1
end

local function exitGestureCraft()
    if craftTouchStart and craftTouchEnd then
        local zoneCoordinates = {
            x = math.min(craftTouchStart.x, craftTouchEnd.x),
            y = math.min(craftTouchStart.y, craftTouchEnd.y),
            width = math.abs(craftTouchEnd.x - craftTouchStart.x),
            height = math.abs(craftTouchEnd.y - craftTouchStart.y)
        }
        debugPrint(string.format("New Zone coordinates: x = %.2f, y = %.2f, width = %.2f, height = %.2f",
            zoneCoordinates.x, zoneCoordinates.y, zoneCoordinates.width, zoneCoordinates.height))
        local newZoneName = "Zone" .. zoneCounter
        table.insert(zones, {
            friendlyName = newZoneName,
            x = zoneCoordinates.x,
            y = zoneCoordinates.y,
            width = zoneCoordinates.width,
            height = zoneCoordinates.height,
            actions = {
                ["none"] = function(touchID)
                    debugPrint(string.format("Touching %s with coordinates: x = %.2f, y = %.2f, width = %.2f, height = %.2f",
                                        newZoneName, zoneCoordinates.x, zoneCoordinates.y, zoneCoordinates.width, zoneCoordinates.height))
                end
            }
        })
        craftTouchStart, craftTouchEnd = nil, nil
    else
        debugPrint("No valid diagonal gesture detected.")
    end
    gestureCraft = false
end

local function resetScrollDirection()
    scrollDirection = -1
end

local function getActiveZone(pos)
    for i, zone in ipairs(zones) do
        if pos.x >= zone.x and pos.x <= zone.x + zone.width and
           pos.y >= zone.y and pos.y <= zone.y + zone.height then
            return zone
        end
    end
    return nil
end

eventtap = hs.eventtap.new({hs.eventtap.event.types.gesture}, function(e)
    local touches = e:getTouches()
    for i, touch in ipairs(touches) do
        if gestureCraft then
            if touch.touching then
                if not craftTouchStart then
                    craftTouchStart = touch.normalizedPosition
                end
                craftTouchEnd = touch.normalizedPosition
            elseif not touch.touching and craftTouchStart and craftTouchEnd then
                exitGestureCraft()
            end
        else
            if touch.normalizedPosition and touch.touching then
                local activeZone = getActiveZone(touch.normalizedPosition)
                if activeZone then
                    local modifiers = hs.eventtap.checkKeyboardModifiers()
                    local modifierState = "none"

                    local modifierKeysOrder = {"cmd", "alt", "shift", "ctrl", "fn"}

                    for _, key in ipairs(modifierKeysOrder) do
                        if modifiers[key] then
                            modifierState = (modifierState == "none") and key or (modifierState .. "+" .. key)
                        end
                    end

                    local action = activeZone.actions[modifierState]
                    if action and not activeTouches[touch.identity] then
                        action(touch.identity, touch)
                    end
                    gestureEnded = false
                end
            elseif not touch.touching and activeTouches[touch.identity] then
                activeTouches[touch.identity]:stop()
                activeTouches[touch.identity] = nil
                if getActiveZone(touch.normalizedPosition) and getActiveZone(touch.normalizedPosition).friendlyName == "Scroll" then
                    scrollDirection = -scrollDirection
                end
                lastScrollTime = os.time() 
                gestureEnded = true
            end

            if touch.normalizedPosition and not getActiveZone(touch.normalizedPosition) and activeTouches[touch.identity] then
                activeTouches[touch.identity]:stop()
                activeTouches[touch.identity] = nil
                gestureEnded = true
            end
        end
    end

    if gestureEnded and lastScrollTime and (os.time() - lastScrollTime >= config.directionResetTimeout) then
        resetScrollDirection()
        lastScrollTime = nil
    end
end)

eventtap:start()

hs.window.filter.new():subscribe({ hs.window.filter.windowFocused }, function()
    resetScrollDirection()
end)

local hammerspoonFilter = hs.window.filter.new(false):setAppFilter('Hammerspoon')

local hotkey = hs.hotkey.new({"ctrl", "shift"}, "G", enterGestureCraft)

local function enableHotkey()
    hotkey:enable()
end

local function disableHotkey()
    hotkey:disable()
end

hammerspoonFilter:subscribe(hs.window.filter.windowFocused, enableHotkey)
hammerspoonFilter:subscribe(hs.window.filter.windowUnfocused, disableHotkey)

function debugPrint(message)
    if config.debug then
        print(message)
    end
end
