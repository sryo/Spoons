-- Define hot corners with their actions and messages
local hotCorners = {
    topLeft = {action = function() hs.application.frontmostApplication():kill() end, message = "Close App"},
    topRight = {action = function() hs.eventtap.keyStroke({"ctrl", "cmd"}, "F") end, message = "Toggle Fullscreen"},
    bottomRight = {action = function() hs.window.focusedWindow():minimize() end, message = "Minimize Window"}
}

-- Create hotspots at the corners of the screen
for corner, _ in pairs(hotCorners) do
    local hotspot = hs.drawing.rectangle(hs.geometry.rect(0, 0, 4, 4))
    hotspot:setFillColor({ red = 0, blue = 0, green = 0, alpha = 0.0 }):setFill(true)
    hotspot:setLevel(hs.drawing.windowLevels.desktopIcon - 1)
    hotspot:setBehavior(hs.drawing.windowBehaviors.canJoinAllSpaces)
    hotspot:show()
end

-- Function to check if the mouse is in a hot corner
local function checkForHotCorner(x, y)
    local screenSize = hs.screen.mainScreen():fullFrame()
    for corner, props in pairs(hotCorners) do
        if corner == "topLeft" and x <= 4 and y <= 4 then
            return props
        end
        if corner == "topRight" and x >= screenSize.w - 4 and y <= 4 then
            return props
        end
        if corner == "bottomRight" and x >= screenSize.w - 4 and y >= screenSize.h - 4 then
            return props
        end
    end
    return nil
end

-- Function to show an alert
local lastAlertTime = 0
local function showAlert(props)
    local currentTime = hs.timer.secondsSinceEpoch()
    if currentTime - lastAlertTime < 1 then
        return
    end
    hs.alert.show(props.message, 1)
    lastAlertTime = currentTime
end

-- Event tap for mouse move events
mouseEventTap = hs.eventtap.new({hs.eventtap.event.types.mouseMoved}, function(event)
    local point = hs.mouse.getAbsolutePosition()
    local cornerProps = checkForHotCorner(point.x, point.y)
    if cornerProps then
        showAlert(cornerProps)
    end
end):start()

-- Event tap for mouse click events
cornerEventTap = hs.eventtap.new({hs.eventtap.event.types.leftMouseDown}, function(event)
    local point = hs.mouse.getAbsolutePosition()
    local cornerProps = checkForHotCorner(point.x, point.y)
    if cornerProps then
        cornerProps.action()
        return true
    end
    return false
end):start()
