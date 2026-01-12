-- SideSwipe: Trackpad edge sliders for volume and brightness.

local SideSwipe = {}

SideSwipe.config = {
    edgeWidth = 0.002,
    edgePadding = 0.08,
    showHud = true,
    hudDuration = 1,
    debug = false,
    edges = {
        left = "brightness",
        right = "volume",
        top = nil,
        bottom = nil
    }
}

local actions = {
    volume = {
        fn = function(value)
            local device = hs.audiodevice.defaultOutputDevice()
            if device then device:setVolume(value) end
        end,
        symbol = "♪"
    },
    brightness = {
        fn = function(value)
            for _, screen in ipairs(hs.screen.allScreens()) do
                local name = screen:name() or ""
                if name:find("Built%-in") or name:find("Color LCD") or name:find("Internal") then
                    screen:setBrightness(value / 100)
                    return
                end
            end
            hs.brightness.set(math.floor(value))
        end,
        symbol = "☀"
    }
}

local function debugPrint(message)
    if SideSwipe.config.debug then
        print(os.date("%H:%M:%S") .. " [SS] " .. message)
    end
end

local canvasSize = 80
local ringSize = 66

local function getHudFrame()
    local screenSize = hs.screen.mainScreen():frame()
    return {
        x = (screenSize.w - canvasSize) / 2,
        y = screenSize.h - canvasSize - 40,
        w = canvasSize,
        h = canvasSize
    }
end

local hud = hs.canvas.new(getHudFrame())

hud[1] = {
    type = "circle",
    action = "fill",
    center = { x = canvasSize / 2, y = canvasSize / 2 },
    radius = canvasSize / 2,
    fillColor = { white = 0.1, alpha = 0.6 }
}

hud[2] = {
    type = "arc",
    action = "fill",
    center = { x = canvasSize / 2, y = canvasSize / 2 },
    radius = ringSize / 2,
    startAngle = 0,
    endAngle = 0,
    fillColor = { white = 1, alpha = 0.9 }
}

hud[3] = {
    type = "circle",
    action = "fill",
    center = { x = canvasSize / 2, y = canvasSize / 2 },
    radius = 20,
    fillColor = { white = 0.1, alpha = 0.95 }
}

hud[4] = {
    type = "text",
    text = "",
    textColor = { white = 1, alpha = 1 },
    textAlignment = "center",
    textSize = 22,
    frame = { x = 0, y = 26, w = canvasSize, h = 28 }
}

local hudTimer = nil

local function showHud(symbol, value)
    if not SideSwipe.config.showHud then return end
    hud[2].endAngle = (value / 100) * 360
    hud[4].text = symbol
    hud:show()

    if hudTimer then hudTimer:stop() end
    hudTimer = hs.timer.doAfter(SideSwipe.config.hudDuration, function()
        hud:hide()
    end)
end

local function getEdge(x, y)
    local w = SideSwipe.config.edgeWidth
    if x <= w then return "left" end
    if x >= 1 - w then return "right" end
    if y <= w then return "top" end
    if y >= 1 - w then return "bottom" end
    return nil
end

local validTouches = {}

local function handleTouches(touches)
    local currentIds = {}

    for _, touch in ipairs(touches) do
        if touch.type == "indirect" and touch.normalizedPosition then
            local id = touch.identity
            currentIds[id] = true

            if touch.touching then
                local x, y = touch.normalizedPosition.x, touch.normalizedPosition.y
                local edge = getEdge(x, y)

                -- Ignore touches that didn't start in edge zone
                if validTouches[id] == nil then
                    validTouches[id] = edge or false
                end

                local activeEdge = validTouches[id]
                if activeEdge then
                    local actionName = SideSwipe.config.edges[activeEdge]
                    local action = actionName and actions[actionName]
                    if action then
                        local pad = SideSwipe.config.edgePadding
                        local pos = (activeEdge == "left" or activeEdge == "right") and y or x
                        local value = math.max(0, math.min(100, (pos - pad) / (1 - 2 * pad) * 100))
                        action.fn(value)
                        debugPrint(actionName .. ": " .. value)
                        showHud(action.symbol, value)
                        return
                    end
                end
            end
        end
    end

    for id in pairs(validTouches) do
        if not currentIds[id] then
            validTouches[id] = nil
        end
    end
end

local gestureEventtap = nil
local screenWatcher = nil

local function repositionHud()
    hud:frame(getHudFrame())
    debugPrint("HUD repositioned")
end

function SideSwipe.start()
    gestureEventtap = hs.eventtap.new({ hs.eventtap.event.types.gesture }, function(e)
        local touches = e:getTouches()
        if touches then handleTouches(touches) end
        return false
    end)
    gestureEventtap:start()
    screenWatcher = hs.screen.watcher.new(repositionHud)
    screenWatcher:start()
    debugPrint("SideSwipe started")
end

function SideSwipe.stop()
    if gestureEventtap then
        gestureEventtap:stop()
        gestureEventtap = nil
    end
    if screenWatcher then
        screenWatcher:stop()
        screenWatcher = nil
    end
    hud:hide()
    debugPrint("SideSwipe stopped")
end

SideSwipe.start()

return SideSwipe
