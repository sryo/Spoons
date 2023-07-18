-- ForceKeys: https://github.com/sryo/Spoons/blob/main/ForceKeys.lua
-- This script maps your keyboard onto the Magic Trackpad, making text input a touch away.

local config = {
    tooltipDuration = 1,    -- in seconds
    forceThreshold = 300    -- threshold for force tap
}

local keys = {
    {"q", "w", "e", "r", "t", "y", "u", "i", "o", "p"},
    {"a", "s", "d", "f", "g", "h", "j", "k", "l", "ñ"},
    {"z", "x", "c", "v", "b", "n", "m", ",", ".", "shift"},
    {"shift", "fn", "ctrl", "alt", "cmd", "space", "space", "space", "enter", "backspace"},
}

local keySymbols = {
    shift = "⇧",
    ctrl = "⌃",
    alt = "⌥",
    cmd = "⌘",
    space = "⎵",
    enter = "↩",
    backspace = "⌫",
    fn = "fn"
}

local touches = {}
local activeModifiers = {}

local function getGridCell(pos)
    local x = math.min(math.floor(pos.x * 10) + 1, 10)
    local y = math.min(math.floor((1 - pos.y) * 4) + 1, 4)
    return x, y
end

local lastModifier = nil

local function emitKey(x, y)
    local key = keys[y][x]
    if key then
        print("Emitting key: " .. key)
        if key == "space" then
            hs.eventtap.keyStrokes(" ")
            lastModifier = nil
        elseif key == "enter" then
            hs.eventtap.keyStroke({}, "return")
            lastModifier = nil
        elseif key == "backspace" then
            hs.eventtap.keyStroke({}, "delete")
            lastModifier = nil
        elseif key == "ctrl" or key == "alt" or key == "shift" or key == "cmd" or key == "fn" then
            lastModifier = key
        else
            if lastModifier then
                if lastModifier == "shift" and #key == 1 then
                    key = key:upper()
                    lastModifier = nil
                else
                    hs.eventtap.keyStroke({lastModifier}, key)
                    lastModifier = nil
                    return
                end
            end
            hs.eventtap.keyStrokes(key)
        end
    end
end

local tooltipAlert = hs.canvas.new({x = 0, y = 0, w = 0, h = 0}):show()
tooltipAlert[1] = {
    type = "rectangle",
    action = "fill",
    roundedRectRadii = { xRadius = 4, yRadius = 4 },
    fillColor = { white = 0, alpha = 0.75 }
}
tooltipAlert[2] = {
    type = "text",
    text = "",
    textColor = { white = 1, alpha = 1 },
    textAlignment = "center"    -- Center align the text
}

local tooltipTimer = nil

local function showTooltip(key)
    if keySymbols[key] then
        key = keySymbols[key]
    end

    local screenSize = hs.screen.mainScreen():frame()
    tooltipAlert:frame({
        x = (screenSize.w - 30) / 2,   -- center the tooltip horizontally
        y = screenSize.h - 30,
        w = 30,                        -- set width to a fixed value of 30
        h = 30
    })
    tooltipAlert[2].text = key
    tooltipAlert:show()

    if tooltipTimer then
        tooltipTimer:stop()
    end
    tooltipTimer = hs.timer.doAfter(config.tooltipDuration, function() tooltipAlert:hide() end)
end

eventtap = hs.eventtap.new({hs.eventtap.event.types.gesture}, function(e)
    local newTouches = e:getTouches()

    for i, touch in ipairs(newTouches) do
        if touch.normalizedPosition and touch.touching then
            local x, y = getGridCell(touch.normalizedPosition)
            local id = touch.identity

            if touches[id] then
                if touch.force >= config.forceThreshold and not touches[id].emitted then
                    emitKey(x, y)
                    touches[id].emitted = true
                elseif touches[id].lastKey ~= keys[y][x] then
                    local key = keys[y] and keys[y][x] or nil
                    showTooltip(key)
                    touches[id].lastKey = keys[y][x]
                end
            else
                local key = keys[y] and keys[y][x] or nil
                showTooltip(key)
                touches[id] = {emitted = false, lastKey = keys[y][x]}
            end
        elseif touch.phase == "ended" or touch.phase == "cancelled" then
            local x, y = getGridCell(touch.normalizedPosition)
            local key = keys[y][x]
            if key == "ctrl" or key == "alt" or key == "shift" or key == "cmd" or key == "fn" then
                for i=#activeModifiers, 1, -1 do
                    if activeModifiers[i] == key then
                        table.remove(activeModifiers, i)
                    end
                end
            end
            touches[touch.identity] = nil
        end
    end
    return false
end)

eventtap:start()
