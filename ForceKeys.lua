-- ForceKeys: https://github.com/sryo/Spoons/blob/main/ForceKeys.lua
-- This script maps your keyboard onto the Magic Trackpad, making text input a touch away.

local config = {
    tooltipDuration = .5,   -- in seconds
    forceThreshold = 300    -- threshold for force tap
}

local keys = {
    {"cmd+a", "cmd+c", "cmd+x", "cmd+v", "cmd+f", "cmd+s", "cmd+r", "cmd+t", "cmd+z", "cmd+shift+z"},
    -- {"!", "@", "#", "$", "%", "&", "/", "(", ")", "+"},
    -- {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0"},
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
    fn = "fn",
    ["cmd+a"] = "🗹",
    ["cmd+c"] = "📑",
    ["cmd+x"] = "✂",
    ["cmd+v"] = "📋",
    ["cmd+f"] = "🔍",
    ["cmd+s"] = "💾",
    ["cmd+r"] = "🔄",
    ["cmd+t"] = "🆕",
    ["cmd+z"] = "⏪",
    ["cmd+shift+z"] = "⏩"
}

local touches = {}
local activeModifiers = {}

local function getGridCell(pos)
    local numColumns = #keys[1]
    local numRows = #keys

    local x = math.min(math.floor(pos.x * numColumns) + 1, numColumns)
    local y = math.min(math.floor((1 - pos.y) * numRows) + 1, numRows)

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
        elseif key:find("+") then
            local keys = {}
            for k in key:gmatch("%w+") do
                table.insert(keys, k)
            end
            hs.eventtap.keyStroke(keys, keys[#keys], 0)
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
    textAlignment = "center"
}

local tooltipTimer = nil

local function showTooltip(key, isTouching)
    if keySymbols[key] then
        key = keySymbols[key]
    end

    local screenSize = hs.screen.mainScreen():frame()
    tooltipAlert:frame({
        x = (screenSize.w - 30) / 2,
        y = screenSize.h - 30,
        w = 30,
        h = 30
    })
    tooltipAlert[2].text = key
    tooltipAlert:show()

    if tooltipTimer then
        tooltipTimer:stop()
    end
    if not isTouching then
        tooltipTimer = hs.timer.doAfter(config.tooltipDuration, function() tooltipAlert:hide() end)
    end
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
                    showTooltip(key, touch.touching)
                    touches[id].lastKey = keys[y][x]
                end
            else
                local key = keys[y] and keys[y][x] or nil
                showTooltip(key, touch.touching)
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
            showTooltip(key, false)
            touches[touch.identity] = nil
        end
    end
    return false
end)

eventtap:start()
