-- FrameMaster: https://github.com/sryo/Spoons/blob/main/FrameMaster.lua
-- Take control of your Mac's 'hot corners', menu bar, and dock.

local cfg = {
    killMenu         = true,
    killDock         = true,
    onlyFullscreen   = false,
    buffer           = 4,
    showTooltips     = true,
    tooltipMaxLength = 50,
    reopenAfterKill  = true,
    tooltipMargin    = 0,
    useWindowScape   = true,
}

local ok, windowScape = pcall(require, "WindowScape")
if not ok then
    cfg.useWindowScape = false
    windowScape = nil
end

local function windowName(w)
    w = w or hs.window.focusedWindow()
    return (w and w:title()) or "Window"
end

local function appNameOf(w)
    local a = w and w:application() or hs.application.frontmostApplication()
    return (a and a:name()) or "App"
end

local focusedWindowName = windowName
local frontmostAppName  = appNameOf

local function hasActionableWindow(win)
    win = win or hs.window.focusedWindow()
    if not win then return false end
    local subrole = win.subrole and win:subrole()
    if subrole and subrole ~= "AXStandardWindow" and subrole ~= "AXDialog" then
        return false
    end
    return true
end

local function getDockPosition()
    local handle = io.popen("defaults read com.apple.dock orientation")
    if not handle then return "bottom" end
    local result = handle:read("*a") or ""
    handle:close()
    return result:gsub("^%s*(.-)%s*$", "%1")
end

local dockPos = getDockPosition()
local lastKilledApp, lastKilledAppName = nil, nil
local fadeTimer, hideTooltipTimer = nil, nil
local lastCorner = nil

local function showReopenDialog()
    if not cfg.reopenAfterKill or not lastKilledAppName then return end
    local name, bundleID = lastKilledAppName, lastKilledApp
    hs.timer.doAfter(0.1, function()
        local choice = hs.dialog.blockAlert(
            "Reopen?",
            "You just killed " .. name .. ". Reopen it?",
            "Reopen", "Ignore", "informational"
        )
        if choice == "Reopen" then
            hs.application.launchOrFocusByBundleID(bundleID)
        end
    end)
end

local function windowScapeToggleFullscreen()
    return windowScape and windowScape.toggleFullscreen and windowScape.toggleFullscreen()
end

local function windowScapeIsFullscreen(win)
    return windowScape and windowScape.isFullscreen and windowScape.isFullscreen(win)
end

local function windowScapeMinimize()
    return windowScape and windowScape.minimize and windowScape.minimize()
end

local hotCorners = {
    topLeft = {
        action = function()
            if not hasActionableWindow() then return "" end
            local app = hs.application.frontmostApplication()
            local window = app and app:focusedWindow()
            if not window then return "" end

            local nextWindow = hs.window.orderedWindows()[2]

            if hs.eventtap.checkKeyboardModifiers().shift then
                local killedName = frontmostAppName()
                local bundleID = app:bundleID()
                app:kill9()
                if nextWindow then nextWindow:focus() end
                lastKilledAppName = killedName
                lastKilledApp = bundleID
                showReopenDialog()
                return "Killed " .. killedName
            end

            hs.eventtap.keyStroke({ "cmd" }, "w")
            hs.timer.usleep(100000)
            local visibleWindows = hs.fnutils.filter(app:allWindows(), function(w)
                return w:isVisible()
            end)

            local result
            if #visibleWindows == 0 then
                local quittedName = frontmostAppName()
                app:kill()
                if nextWindow then
                    hs.timer.doAfter(0.5, function() nextWindow:focus() end)
                end
                result = "Quitted " .. quittedName
            else
                result = "Closed " .. focusedWindowName()
            end

            hs.timer.doAfter(0.5, function()
                local pos = hs.mouse.absolutePosition()
                hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.mouseMoved, pos):post()
            end)

            return result
        end,
        message = function(win)
            win = win or hs.window.focusedWindow()
            if not hasActionableWindow(win) then return "" end
            if hs.eventtap.checkKeyboardModifiers().shift then
                return "Kill " .. appNameOf(win)
            end
            return "Close " .. windowName(win)
        end
    },
    topRight = {
        action = function()
            local window = hs.window.focusedWindow()
            if not hasActionableWindow(window) then return "" end
            if hs.eventtap.checkKeyboardModifiers().shift then
                window:toggleZoom()
                return "Zoomed " .. focusedWindowName()
            end
            if cfg.useWindowScape and windowScape then
                return windowScapeToggleFullscreen()
            end
            hs.eventtap.keyStroke({ "ctrl", "cmd" }, "F")
            return "Toggled Fullscreen for " .. focusedWindowName()
        end,
        message = function(win)
            win = win or hs.window.focusedWindow()
            if not hasActionableWindow(win) then return "" end
            if hs.eventtap.checkKeyboardModifiers().shift then
                return "Zoom " .. windowName(win)
            end
            if cfg.useWindowScape and windowScape and windowScapeIsFullscreen(win) then
                return "Exit Fullscreen for " .. windowName(win)
            end
            return "Toggle Fullscreen for " .. windowName(win)
        end
    },
    bottomRight = {
        action = function()
            local window = hs.window.focusedWindow()
            if not hasActionableWindow(window) or window:isFullScreen() then return "" end
            if hs.eventtap.checkKeyboardModifiers().shift then
                local app = window:application()
                if app then app:hide() end
                return "Hid " .. focusedWindowName()
            end
            if cfg.useWindowScape and windowScape then
                return windowScapeMinimize()
            end
            window:minimize()
            return "Minimized " .. focusedWindowName()
        end,
        message = function(win)
            win = win or hs.window.focusedWindow()
            if not hasActionableWindow(win) or win:isFullScreen() then return "" end
            if hs.eventtap.checkKeyboardModifiers().shift then
                return "Hide " .. windowName(win)
            end
            return "Minimize " .. windowName(win)
        end
    },
    bottomLeft = {
        action = function()
            if hs.eventtap.checkKeyboardModifiers().shift then
                local app = hs.application.get("System Preferences")
                if not app then
                    hs.application.launchOrFocus("System Preferences")
                    return "Launched System Preferences"
                end
                app:activate()
                return "Focused System Preferences"
            end
            hs.osascript.applescript('tell application "Finder" to make new Finder window')
            hs.application.launchOrFocus("Finder")
            return "Opened Finder window"
        end,
        message = function()
            if hs.eventtap.checkKeyboardModifiers().shift then
                return "Open System Preferences"
            end
            return "New Finder Window"
        end
    }
}

local function getCurrentScreenFrame()
    local screen = hs.mouse.getCurrentScreen()
    return screen and screen:frame() or nil
end

local function checkForHotCorner(x, y)
    local frame = getCurrentScreenFrame()
    if not frame then return nil end

    local left, right = frame.x, frame.x + frame.w
    local top, bottom = frame.y, frame.y + frame.h
    local b = cfg.buffer

    if x <= left + b and y <= top + b then
        return "topLeft"
    elseif x >= right - b and y <= top + b then
        return "topRight"
    elseif x >= right - b and y >= bottom - b then
        return "bottomRight"
    elseif x <= left + b and y >= bottom - b then
        return "bottomLeft"
    end
    return nil
end

local function truncateString(input, maxLength)
    maxLength = maxLength or 50
    if #input > maxLength then
        local partLen = math.floor(maxLength / 2)
        input = input:sub(1, partLen - 2) .. '...' .. input:sub(-partLen)
    end
    return input
end

local tooltipAlert = hs.canvas.new({ x = 0, y = 0, w = 1, h = 1 })
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

local cornerPositions = {
    topLeft     = function(f, w, h, m) return f.x + m,                f.y + m end,
    topRight    = function(f, w, h, m) return f.x + f.w - w - m,      f.y + m end,
    bottomLeft  = function(f, w, h, m) return f.x + m,                f.y + f.h - h - m end,
    bottomRight = function(f, w, h, m) return f.x + f.w - w - m,      f.y + f.h - h - m end,
}

local hideTooltip

local function showMessage(corner, message)
    if not message or message == "" then return end
    if fadeTimer then
        fadeTimer:stop()
        fadeTimer = nil
    end

    local styledMessage = hs.styledtext.new(truncateString(message, cfg.tooltipMaxLength), {
        font = { size = 20 },
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

    local positioner = cornerPositions[corner]
    if not positioner then return end
    local tooltipX, tooltipY = positioner(frame, textSize.w, tooltipHeight, cfg.tooltipMargin)

    tooltipAlert:frame(hs.geometry.rect(tooltipX, tooltipY, textSize.w, tooltipHeight))
    tooltipAlert[1].fillColor.alpha = 0.75
    tooltipAlert[2].text = styledMessage
    tooltipAlert:alpha(1)
    tooltipAlert:behavior("canJoinAllSpaces")
    tooltipAlert:show()

    if hideTooltipTimer then hideTooltipTimer:stop() end
    hideTooltipTimer = hs.timer.doAfter(0.75, function() hideTooltip() end)
end

hideTooltip = function()
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
        if cornerToFade then
            local point = hs.mouse.absolutePosition()
            if cornerToFade == checkForHotCorner(point.x, point.y) then
                return
            end
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

local function isDockEdgeHit(pos, x, y, frame, buffer)
    if pos == "bottom" then
        return (frame.y + frame.h - y) < buffer
            and x > frame.x + buffer
            and x < frame.x + frame.w - buffer
    elseif pos == "left" then
        return (x - frame.x) < buffer
            and y > frame.y + buffer
            and y < frame.y + frame.h - buffer
    elseif pos == "right" then
        return (frame.x + frame.w - x) < buffer
            and y > frame.y + buffer
            and y < frame.y + frame.h - buffer
    end
    return false
end

local cornerHover
if cfg.showTooltips then
    cornerHover = hs.eventtap.new({ hs.eventtap.event.types.mouseMoved, hs.eventtap.event.types.flagsChanged },
        function(event)
            local point = hs.mouse.absolutePosition()
            local currentCorner = checkForHotCorner(point.x, point.y)

            if currentCorner then
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
            if screenFrame and ((not cfg.onlyFullscreen) or (cfg.onlyFullscreen and win and win:isFullScreen())) then
                local shift = hs.eventtap.checkKeyboardModifiers().shift
                local loc = event:location()
                if cfg.killMenu and not shift
                    and loc.y < screenFrame.y + cfg.buffer
                    and loc.x > screenFrame.x + cfg.buffer
                    and loc.x < screenFrame.x + screenFrame.w - cfg.buffer then
                    return true
                end
                if cfg.killDock and not shift
                    and isDockEdgeHit(dockPos, loc.x, loc.y, screenFrame, cfg.buffer) then
                    return true
                end
            end
            return false
        end):start()
end

local cornerClick = hs.eventtap.new({ hs.eventtap.event.types.leftMouseDown }, function(event)
    local point = hs.mouse.absolutePosition()
    lastCorner = checkForHotCorner(point.x, point.y)
    if not lastCorner then return false end
    local result = hotCorners[lastCorner].action()
    if result and result ~= "" then
        showMessage(lastCorner, truncateString(result))
        return true
    end
    return false
end):start()

local dockWatcher = hs.pathwatcher.new(
    os.getenv("HOME") .. "/Library/Preferences/com.apple.dock.plist",
    function() dockPos = getDockPosition() end
):start()

return {
    cornerHover  = cornerHover,
    cornerClick  = cornerClick,
    tooltipAlert = tooltipAlert,
    dockWatcher  = dockWatcher,
    showMessage  = showMessage,
    hideTooltip  = hideTooltip,
    messages     = {
        topLeft     = function(win) return hotCorners.topLeft.message(win)     end,
        topRight    = function(win) return hotCorners.topRight.message(win)    end,
        bottomRight = function(win) return hotCorners.bottomRight.message(win) end,
    },
}
