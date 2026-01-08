-- SideSwipe: Trackpad edge sliders for volume and brightness.

local SideSwipe = {}

SideSwipe.config = {
    edgeWidth = 0.02,
    edgePadding = 0.08,
    showHud = true,
    hudDuration = 1,
    debug = false
}

local function debugPrint(message)
    if SideSwipe.config.debug then
        print(os.date("%H:%M:%S") .. " [SS] " .. message)
    end
end

local canvasSize = 80
local ringSize = 66
local screenSize = hs.screen.mainScreen():frame()

local hud = hs.canvas.new({
    x = (screenSize.w - canvasSize) / 2,
    y = screenSize.h - canvasSize - 40,
    w = canvasSize,
    h = canvasSize
})

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

local function setVolume(value)
    local device = hs.audiodevice.defaultOutputDevice()
    if not device then return end

    device:setVolume(value)
    debugPrint("Volume: " .. value)
    showHud("♪", value)
end

local function setBrightness(value)
    hs.brightness.set(math.floor(value))
    debugPrint("Brightness: " .. value)
    showHud("☀", value)
end

local function getEdge(x)
    if x <= SideSwipe.config.edgeWidth then
        return "left"
    elseif x >= 1 - SideSwipe.config.edgeWidth then
        return "right"
    end
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
                local edge = getEdge(touch.normalizedPosition.x)

                -- Ignore touches that didn't start in edge zone
                if validTouches[id] == nil then
                    validTouches[id] = edge or false
                end
                if validTouches[id] then
                    local pad = SideSwipe.config.edgePadding
                    local y = touch.normalizedPosition.y
                    local value = math.max(0, math.min(100, (y - pad) / (1 - 2 * pad) * 100))
                    if validTouches[id] == "left" then
                        setVolume(value)
                    else
                        setBrightness(value)
                    end
                    return
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

function SideSwipe.start()
    gestureEventtap = hs.eventtap.new({ hs.eventtap.event.types.gesture }, function(e)
        local touches = e:getTouches()
        if touches then handleTouches(touches) end
        return false
    end)
    gestureEventtap:start()
    debugPrint("SideSwipe started")
end

function SideSwipe.stop()
    if gestureEventtap then
        gestureEventtap:stop()
        gestureEventtap = nil
    end
    hud:hide()
    debugPrint("SideSwipe stopped")
end

SideSwipe.start()

return SideSwipe
