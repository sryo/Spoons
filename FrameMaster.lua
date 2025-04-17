-- FrameMaster: https://github.com/sryo/Spoons/blob/main/FrameMaster.lua
-- Take control of your Mac's 'hot corners', menu bar, and dock.

local killMenu         = true  -- prevent the menu bar from appearing
local killDock         = true  -- prevent the dock from appearing
local onlyFullscreen   = false -- but only on fullscreen spaces
local buffer           = 4     -- increase if you still manage to activate them
local showTooltips     = true  -- set this to false to improve performance if necessary
local tooltipMaxLength = 50    -- maximum length for tooltip messages
local reopenAfterKill  = true  -- show an autoclosing modal to reopen the last killed app
local tooltipMargin    = 0     -- increase this value to add extra spacing if needed

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

local lastKilledApp = nil
local lastKilledAppName = nil

function showReopenDialog()
    if reopenAfterKill then
        local message = "You just killed " .. lastKilledAppName .. ". Would you like to reopen it?"
        local script = [[
            tell application "System Events"
                activate
                display dialog "]] .. message .. [[" buttons {"Ignore", "Reopen"} default button 2 giving up after 5
                if result is not missing value and button returned of result is "Reopen" then
                    return "Reopen"
                else
                    return "Ignore"
                end if
            end tell
        ]]
        local appleScriptTask = hs.task.new("/usr/bin/osascript", function(exitCode, stdOut, stdErr)
            print("exitCode: " .. exitCode .. " stdOut: " .. stdOut .. " stdErr: " .. stdErr)
            if exitCode == 0 and stdOut:find("Reopen") then
                hs.application.launchOrFocusByBundleID(lastKilledApp)
            end
        end, { "-e", script })

        appleScriptTask:start()
    end
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

hotCorners = {
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
                lastKilledAppName = getAppName()
                lastKilledApp = app:bundleID()
                showReopenDialog()
                print(lastKilledApp)
            else
                hs.eventtap.keyStroke({ "cmd" }, "w")
                hs.timer.usleep(100000) -- Wait a little for the close action to complete
                local allWindows = app:allWindows()
                local visibleWindows = {}
                for i, win in ipairs(allWindows) do
                    if win:isVisible() then
                        table.insert(visibleWindows, win)
                    end
                end
                if #visibleWindows == 0 or not window then
                    app:kill()
                    if nextWindow then
                        hs.timer.doAfter(0.5, function() nextWindow:focus() end)
                    end
                    executedActionMessage = "Quitted " .. getAppName()
                else
                    executedActionMessage = "Closed " .. getWindowTitle()
                end
            end

            hs.timer.doAfter(0.5, function()
                local currentMousePosition = hs.mouse.absolutePosition()
                hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.mouseMoved, currentMousePosition):post()
            end)

            return executedActionMessage
        end,
        message = function()
            local app = hs.application.frontmostApplication()
            if hs.eventtap.checkKeyboardModifiers().shift then
                return "Kill " .. getAppName()
            elseif not app or not app:focusedWindow() then
                return "Quit " .. getAppName()
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
                hs.eventtap.keyStroke({ "ctrl", "cmd" }, "F")
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

local function getCurrentScreenFrame()
    local screen = hs.mouse.getCurrentScreen()
    if screen then
        return screen:frame()
    end
    return nil
end

function checkForHotCorner(x, y)
    local frame = getCurrentScreenFrame()
    if not frame then return nil end

    local left   = frame.x
    local right  = frame.x + frame.w
    local top    = frame.y
    local bottom = frame.y + frame.h

    if x <= left + buffer and y <= top + buffer then
        return "topLeft"
    elseif x >= right - buffer and y <= top + buffer then
        return "topRight"
    elseif x >= right - buffer and y >= bottom - buffer then
        return "bottomRight"
    elseif x <= left + buffer and y >= bottom - buffer then
        return "bottomLeft"
    end
    return nil
end

function truncateString(input, maxLength)
    maxLength = maxLength or 50
    if #input > maxLength then
        local partLen = math.floor(maxLength / 2)
        input = input:sub(1, partLen - 2) .. '...' .. input:sub(-partLen)
    end
    return input
end

tooltipAlert = hs.canvas.new({ x = 0, y = 0, w = 1, h = 1 })
tooltipAlert:level(hs.canvas.windowLevels._MaximumWindowLevelKey)
tooltipAlert[1] = {
    type = "rectangle",
    action = "fill",
    roundedRectRadii = { xRadius = 4, yRadius = 4 },
    fillColor = { white = 0, alpha = 0.75 }
}
tooltipAlert[2] = {
    type = "text",
    text = "",
    textLineBreak = "clip",
    textColor = { white = 1, alpha = 1 }
}

function showMessage(corner, message)
    if fadeTimer then
        fadeTimer:stop()
        fadeTimer = nil
    end
    local fontSize = 20
    local styledMessage = hs.styledtext.new(truncateString(message, tooltipMaxLength), {
        font = { size = fontSize },
        color = { white = 1, alpha = 1 },
        shadow = {
            offset = { h = -1, w = 0 },
            blurRadius = 2,
            color = { alpha = 1 }
        }
    })

    local textSize = hs.drawing.getTextDrawingSize(styledMessage)
    local tooltipHeight = 24

    local frame = getCurrentScreenFrame()
    if not frame then return end

    local tooltipX, tooltipY
    if corner == "topLeft" or corner == "bottomLeft" then
        tooltipX = frame.x + tooltipMargin
    else
        tooltipX = frame.x + frame.w - textSize.w - tooltipMargin
    end

    if corner == "topLeft" or corner == "topRight" then
        tooltipY = frame.y + tooltipMargin
    else
        tooltipY = frame.y + frame.h - tooltipHeight - tooltipMargin
    end

    local textFrame = hs.geometry.rect(tooltipX, tooltipY, textSize.w, tooltipHeight)
    tooltipAlert:frame(textFrame)
    tooltipAlert[1].fillColor.alpha = 0.75
    tooltipAlert[2].text = styledMessage
    tooltipAlert[2].textColor.alpha = 1
    tooltipAlert:alpha(1)
    tooltipAlert:behavior("canJoinAllSpaces")
    tooltipAlert:show()

    if hideTooltipTimer then
        hideTooltipTimer:stop()
    end
    hideTooltipTimer = hs.timer.doAfter(0.75, hideTooltip)
end

local fadeTimer = nil

function hideTooltip()
    if fadeTimer then
        fadeTimer:stop()
        fadeTimer = nil
    end

    local fadeOutDuration = 0.125
    local fadeOutStep = 0.025
    local fadeOutAlphaStep = fadeOutStep / fadeOutDuration
    local currentAlpha = tooltipAlert:alpha()
    local cornerToFade = lastCorner

    local function fade()
        local point = hs.mouse.absolutePosition()
        if cornerToFade == checkForHotCorner(point.x, point.y) then
            return
        end
        currentAlpha = currentAlpha - fadeOutAlphaStep
        tooltipAlert:alpha(currentAlpha)
        if currentAlpha > 0 then
            fadeTimer = hs.timer.doAfter(fadeOutStep, fade)
        else
            tooltipAlert:hide()
            fadeTimer = nil
        end
    end

    fadeTimer = hs.timer.doAfter(0, fade)
end

if showTooltips then
    cornerHover = hs.eventtap.new({ hs.eventtap.event.types.mouseMoved, hs.eventtap.event.types.flagsChanged },
        function(event)
            local point = hs.mouse.absolutePosition()
            local currentCorner = checkForHotCorner(point.x, point.y)

            if currentCorner and not isDesktop() then
                lastCorner = currentCorner
                showMessage(lastCorner, hotCorners[lastCorner].message())
            elseif lastCorner and not currentCorner then
                hideTooltip()
                lastCorner = nil
            end

            if lastCorner and event:getType() == hs.eventtap.event.types.flagsChanged then
                showMessage(lastCorner, hotCorners[lastCorner].message())
            end

            local win = hs.window.focusedWindow()
            local screen = win and win:screen() or hs.mouse.getCurrentScreen()
            local screenFrame = screen and screen:fullFrame()
            if screenFrame then
                if (not onlyFullscreen) or (onlyFullscreen and win and win:isFullScreen()) then
                    if killMenu and not hs.eventtap.checkKeyboardModifiers().shift and
                        event:location().y < screenFrame.y + buffer and
                        (event:location().x > screenFrame.x + buffer and event:location().x < screenFrame.x + screenFrame.w - buffer) then
                        return true
                    elseif killDock and not hs.eventtap.checkKeyboardModifiers().shift then
                        if dockPos == "bottom" and (screenFrame.y + screenFrame.h - event:location().y) < buffer and
                            (event:location().x > screenFrame.x + buffer and event:location().x < screenFrame.x + screenFrame.w - buffer) then
                            return true
                        elseif dockPos == "left" and (event:location().x - screenFrame.x) < buffer and
                            (event:location().y > screenFrame.y + buffer and event:location().y < screenFrame.y + screenFrame.h - buffer) then
                            return true
                        elseif dockPos == "right" and (screenFrame.x + screenFrame.w - event:location().x) < buffer and
                            (event:location().y > screenFrame.y + buffer and event:location().y < screenFrame.y + screenFrame.h - buffer) then
                            return true
                        end
                    end
                end
            end
            return false
        end):start()
end

cornerClick = hs.eventtap.new({ hs.eventtap.event.types.leftMouseDown }, function(event)
    local point = hs.mouse.absolutePosition()
    lastCorner = checkForHotCorner(point.x, point.y)
    if lastCorner and not isDesktop() then
        local message = truncateString(hotCorners[lastCorner].action())
        showMessage(lastCorner, message)
        return true
    end
    return false
end):start()
