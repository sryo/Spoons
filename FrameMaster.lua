-- Take control of your Mac's 'hot corners', menu bar, and dock.

local killMenu          = true  -- prevent the menu bar from appearing
local killDock          = true  -- prevent the dock from appearing
local onlyFullscreen    = true  -- but only on fullscreen spaces
local buffer            = 4     -- increase if you still manage to activate them
local showTooltips      = true  -- set this to false to improve performance if necessary
local tooltipMaxLength  = 50    -- maximum length for tooltip messages

local function getWindowTitle(cornerAction)
    local window = hs.window.focusedWindow()
    local title = window and window:title() or "Window"
    return title, (cornerAction and cornerAction .. " " .. title or "No action")
end

local function getAppName(cornerAction)
    local app = hs.application.frontmostApplication()
    local appName = app and app:name() or "App"
    return appName, (cornerAction and cornerAction .. " " .. appName or "No action")
end

local function isDesktop()
    local window = hs.window.focusedWindow()
    return window and window:role() == "AXScrollArea"
end

local function getDockPosition()
    local handle = io.popen("defaults read com.apple.dock orientation")
    local result = handle:read("*a")
    handle:close()
    return result:gsub("^%s*(.-)%s*$", "%1")
end
local dockPos = getDockPosition()

local hotCorners = {
    topLeft = {
        action = function()
            local app = hs.application.frontmostApplication()
            if not app or isDesktop() then return "No action" end
    
            local window = app:focusedWindow()
            local nextWindow = hs.window.orderedWindows()[2]
    
            local executedActionMessage
            if hs.eventtap.checkKeyboardModifiers().shift then
                app:kill9()
                if nextWindow then nextWindow:focus() end
                executedActionMessage = "Force Killed " .. getAppName()
            else
                hs.eventtap.keyStroke({"cmd"}, "w")
                hs.timer.usleep(100000)  -- Wait a little for the close action to complete
                local allWindows = app:allWindows()
                local visibleWindows = {}
                for i, win in ipairs(allWindows) do
                    if win:isVisible() then
                        table.insert(visibleWindows, win)
                    end
                end
                if #visibleWindows == 0 or not window then
                    app:kill()
                    if nextWindow then nextWindow:focus() end
                    executedActionMessage = "Killed " .. getAppName()
                else
                    executedActionMessage = "Closed " .. getWindowTitle()
                end
            end
    
            hs.timer.doAfter(.5, function()
                local currentMousePosition = hs.mouse.getAbsolutePosition()
                hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.mouseMoved, currentMousePosition):post()
            end)

            return executedActionMessage
        end,
        message = function()
            local app = hs.application.frontmostApplication()
            if hs.eventtap.checkKeyboardModifiers().shift then
                return "Force Kill " .. getAppName()
                
            elseif not app or not app:focusedWindow() then
                return "Kill " .. getAppName()
            else
                return "Close " .. getWindowTitle()
            end
        end
    },
    topRight = {
        action = function()
            local window = hs.window.focusedWindow()
            if not window or isDesktop() then return "No action" end
            if hs.eventtap.checkKeyboardModifiers().shift then
                window:toggleZoom()
                return "Zoomed " .. getWindowTitle()
            else
                hs.eventtap.keyStroke({"ctrl", "cmd"}, "F")
                return "Toggled Fullscreen for " .. getWindowTitle()
            end
        end,
        message = function()
            if hs.eventtap.checkKeyboardModifiers().shift then
                return "Zoom " .. getWindowTitle()
            else
                return "Toggle Fullscreen for " .. getWindowTitle()
            end
        end
    },
    bottomRight = {
        action = function()
            local window = hs.window.focusedWindow()
            if not window or isDesktop() or window:isFullScreen() then return "No action" end
            if hs.eventtap.checkKeyboardModifiers().shift then
                window:application():hide()
                return "Hid " .. getWindowTitle()
            else
                window:minimize()
                return "Minimized " .. getWindowTitle()
            end
        end,
        message = function()
            local window = hs.window.focusedWindow()
            if not window or isDesktop() or (window and window:isFullScreen()) then return "" end
            if hs.eventtap.checkKeyboardModifiers().shift then
                return "Hide " .. getWindowTitle()
            else
                return "Minimize " .. getWindowTitle()
            end
        end
    },
    bottomLeft = {
        action = function()
            if hs.eventtap.checkKeyboardModifiers().shift then
                local app = hs.application.get("System Preferences")
                if not app then
                    hs.application.launchOrFocus("System Preferences")
                    return "Launched System Preferences"
                else
                    app:activate()
                    return "Focused System Preferences"
                end
            else
                local app = hs.application.get("Finder")
                hs.application.launchOrFocus("Finder")
                return "Launched Finder"
            end
        end,
        message = function()
            if hs.eventtap.checkKeyboardModifiers().shift then
                return "Open System Preferences"
            else
                return "Open Finder"
            end
        end
    }
}

local lastCorner = nil
local lastTooltipTime = 0
local lastTooltipCorner = nil
local screenSize = hs.screen.mainScreen():currentMode()

function updateScreenSize()
    screenSize = hs.screen.mainScreen():currentMode()
end

updateScreenSize()

local screenWatcher = hs.screen.watcher.newWithActiveScreen(updateScreenSize)
screenWatcher:start()

function checkForHotCorner(x, y)
    updateScreenSize()
    return ((x <= 1 and y <= buffer) and "topLeft") or 
           ((x >= screenSize.w - 1 and y <= buffer) and "topRight") or 
           ((x >= screenSize.w - 1 and y >= screenSize.h - buffer) and "bottomRight") or 
           ((x <= 1 and y >= screenSize.h - buffer) and "bottomLeft")
end

function showTooltip(corner)
    if corner ~= lastTooltipCorner or hs.timer.secondsSinceEpoch() - lastTooltipTime >= 1 then
        local message = hotCorners[corner].message()
        if message ~= "" then
            showMessage(lastCorner, message)
            lastTooltipTime = hs.timer.secondsSinceEpoch()
            lastTooltipCorner = corner
        end
    end
end

function truncateString(input, maxLength)
    maxLength = maxLength or 50
    if #input > maxLength then
        local partLen = math.floor(maxLength / 2)
        input = input:sub(1, partLen - 2) .. '...' .. input:sub(-partLen)
    end
    return input
end

tooltipAlert = hs.canvas.new({x = 0, y = 0, w = 1, h = 1})
tooltipAlert[1] = {
    type = "rectangle",
    action = "fill",
    roundedRectRadii = { xRadius = 4, yRadius = 4 },
    fillColor = { white = 0, alpha = 0.75 },
    frame = textFrame
}

tooltipAlert[2] = {
    type = "text",
    text = styledMessage,
    textLineBreak = "clip",
    textColor = { white = 1, alpha = 1 },
    frame = textFrame
}

function showMessage(corner, message)
    local fontSize = 20
    local styledMessage = hs.styledtext.new(truncateString(message, tooltipMaxLength), {
      font = {size = fontSize},
      color = {white = 1, alpha = 1},
        shadow = {
        offset = {h = -1, w = 0},
        blurRadius = 2,
        color = {alpha = 1}
      }
    })

    local textSize = hs.drawing.getTextDrawingSize(styledMessage)
    local tooltipHeight = 24
    local tooltipX = corner == "topLeft" or corner == "bottomLeft" or screenSize.w - textSize.w
    local tooltipY = corner == "topLeft" or corner == "topRight" or screenSize.h - tooltipHeight
    local textFrame = hs.geometry.rect(tooltipX, tooltipY, textSize.w, tooltipHeight)

    tooltipAlert:frame(textFrame)
    tooltipAlert[1].fillColor.alpha = 0.75
    tooltipAlert[2].text = styledMessage
    tooltipAlert[2].textColor.alpha = 1
    tooltipAlert:alpha(1)
    tooltipAlert:show()

    if hideTooltipTimer then
        hideTooltipTimer:stop()
    end
    hideTooltipTimer = hs.timer.doAfter(0.75, hideTooltip)
end

function hideTooltip()
    local fadeOutDuration = 0.25
    local fadeOutStep = 0.0125
    local fadeOutAlphaStep = fadeOutStep / fadeOutDuration
    local currentAlpha = 1.0
    local function fade()
        local point = hs.mouse.getAbsolutePosition()
        if lastCorner == checkForHotCorner(point.x, point.y) then
            -- cursor still in corner, return without fading tooltip.
            return
        end
        currentAlpha = currentAlpha - fadeOutAlphaStep
        tooltipAlert:alpha(currentAlpha)
        if currentAlpha > 0 then
            hs.timer.doAfter(fadeOutStep, fade)
        else
            tooltipAlert:hide()
        end
    end
    fade()
end

if showTooltips then
    cornerHover = hs.eventtap.new({hs.eventtap.event.types.mouseMoved, hs.eventtap.event.types.flagsChanged}, function(event)
        local point = hs.mouse.getAbsolutePosition()
        local currentCorner = checkForHotCorner(point.x, point.y)
    
        -- If the mouse is in a corner, update the tooltip message and the last corner
        if currentCorner and not isDesktop() then 
            lastCorner = currentCorner
            showMessage(lastCorner, hotCorners[lastCorner].message())
        -- If the mouse moved out from the last corner, hide the tooltip and clear the last corner
        elseif lastCorner and not currentCorner then
            hideTooltip()
            lastCorner = nil
        end
    
        -- If Shift key status changed while the mouse is in a corner, update the tooltip message
        if lastCorner and event:getType() == hs.eventtap.event.types.flagsChanged then
            hs.timer.doAfter(0.01, function()
                showMessage(lastCorner, hotCorners[lastCorner].message())
            end)
        end

        local win = hs.window.focusedWindow()
        local screenFrame = win and win:screen():fullFrame()
    
        if onlyFullscreen and win and win:isFullScreen() then
            if killMenu and not hs.eventtap.checkKeyboardModifiers().shift and event:location().y < buffer and (event:location().x > buffer and event:location().x < screenFrame.w - buffer) then
                return true
            elseif killDock and not hs.eventtap.checkKeyboardModifiers().shift then
                if dockPos == "bottom" and (screenFrame.h - event:location().y) < buffer and (event:location().x > buffer and event:location().x < screenFrame.w - buffer) then
                    return true
                elseif dockPos == "left" and event:location().x < buffer and (event:location().y > buffer and event:location().y < screenFrame.h - buffer) then
                    return true
                elseif dockPos == "right" and (screenFrame.w - event:location().x) < buffer and (event:location().y > buffer and event:location().y < screenFrame.h - buffer) then
                    return true
                end
            end
        end

        return false
    end):start()
end

cornerClick = hs.eventtap.new({hs.eventtap.event.types.leftMouseDown}, function(event)
    local point = hs.mouse.getAbsolutePosition()
    lastCorner = checkForHotCorner(point.x, point.y)
    if lastCorner and not isDesktop() then
        local message = truncateString(hotCorners[lastCorner].action())
        showMessage(lastCorner, message)
        return true
    end
    return false
end):start()
