local keys = {
    {"q", "w", "e", "r", "t", "y", "u", "i", "o", "p"},
    {"a", "s", "d", "f", "g", "h", "j", "k", "l", "ñ"},
    {"z", "x", "c", "v", "b", "n", "m", ",", ".", "shift"},
    {"shift", "fn", "ctrl", "alt", "cmd", "space", "space", "space", "enter", "backspace"},
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
                    -- capitalize the character if the last modifier was shift
                    key = key:upper()
                    lastModifier = nil
                else
                    -- if it's not shift or if the key is not a character (e.g., it's a special key),
                    -- we'll pass the modifier and the key to keyStroke
                    hs.eventtap.keyStroke({lastModifier}, key)
                    lastModifier = nil
                    return
                end
            end
            hs.eventtap.keyStrokes(key)
        end
    end
end

eventtap = hs.eventtap.new({hs.eventtap.event.types.gesture}, function(e)
    local newTouches = e:getTouches()

    for i, touch in ipairs(newTouches) do
        if touch.normalizedPosition and touch.touching then
            local x, y = getGridCell(touch.normalizedPosition)
            local id = touch.identity

            if touches[id] then
                if touch.force >= 300 and not touches[id].emitted then
                    emitKey(x, y)
                    touches[id].emitted = true
                elseif touches[id].lastKey ~= keys[y][x] then
                    local key = keys[y] and keys[y][x] or nil
                    hs.alert.show("Touched key: " .. (key or "nil"), 0.25)
                    print("Touched key: " .. (key or "nil"))
                    touches[id].lastKey = keys[y][x]
                end
            else
                local key = keys[y] and keys[y][x] or nil
                hs.alert.show("Touched key: " .. (key or "nil"), 0.25)
                print("Touch began on key: " .. (key or "nil"))
                touches[id] = {emitted = false, lastKey = keys[y][x]}
            end

        elseif touch.phase == "ended" or touch.phase == "cancelled" then
            -- deactivate any modifier keys if they're no longer being pressed
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
