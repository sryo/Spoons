local config = {
    forceThreshold         = 20,
    scrollUnit             = "pixel",
    scrollAmount           = {0, 3},
    scrollRepetitionSpeed  = 0.001,
    directionResetTimeout  = .5,
}

local activeTouches = {}
local lastScrollTime = nil
local scrollDirection = -1
local gestureEnded = false

local function keyRepeatAction(touchID, modifiers, key)
    activeTouches[touchID] = hs.timer.doWhile(
        function()
            return activeTouches[touchID] ~= nil
        end,
        function()
            hs.eventtap.keyStroke(modifiers, key)
        end,
        hs.eventtap.keyRepeatInterval()
    )
end

local zones = {
    {
        friendlyName = "Scroll",
        x = 0, y = 0, width = 1, height = 0.02,
        actions = {
            ["none"] = function(touchID)
                activeTouches[touchID] = hs.timer.doWhile(function() return activeTouches[touchID] ~= nil end, function() 
                    local scrollAmount = {0, config.scrollAmount[2] * scrollDirection}
                    hs.eventtap.event.newScrollEvent(scrollAmount, {}, config.scrollUnit):post() 
                end, config.scrollRepetitionSpeed)
            end
        }
    },
    {
        friendlyName = "Esc",
        x = 0, y = 0.96, width = 0.04, height = 0.04,
        actions = {
            ["none"] = function(touchID)
                keyRepeatAction(touchID, {}, "escape")
            end
        }
    },
    {
        friendlyName = "Undo/Redo",
        x = 0.96, y = 0.96, width = 0.04, height = 0.04,
        actions = {
            ["none"] = function(touchID)
                keyRepeatAction(touchID, {"cmd"}, "z")
            end,
            ["shift"] = function(touchID)
                keyRepeatAction(touchID, {"cmd", "shift"}, "z")
            end,
        }
    },
}

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
end

eventtap = hs.eventtap.new({hs.eventtap.event.types.gesture}, function(e)
    local touches = e:getTouches()
    for i, touch in ipairs(touches) do
        if touch.normalizedPosition and touch.touching and touch.force >= config.forceThreshold then
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
                    action(touch.identity)
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
    end

    -- Added condition for touches outside active zones
    for i, touch in ipairs(touches) do
        if touch.normalizedPosition and not getActiveZone(touch.normalizedPosition) and activeTouches[touch.identity] then
            activeTouches[touch.identity]:stop()
            activeTouches[touch.identity] = nil
            gestureEnded = true
        end
    end

    if gestureEnded and lastScrollTime and (os.time() - lastScrollTime >= config.directionResetTimeout) then
        resetScrollDirection()
        lastScrollTime = nil
    end

    return false
end)

eventtap:start()

hs.window.filter.new():subscribe({ hs.window.filter.windowFocused }, function()
    resetScrollDirection()
end)
