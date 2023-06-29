-- TimeTrail: https://github.com/sryo/Spoons/blob/main/TimeTrail.lua
-- This Hammerspoon script displays the current time near the mouse pointer as you move it across the screen.
-- The text turns red if the battery is low, fades out if the mouse is idle and disappears during typing.

local is24HourFormat      = true
local fontName            = nil
local fontSize            = 16
local textPositionRadius  = 30
local normalColor         = {white = 1, alpha = 1}  
local lowBatteryColor     = {red = 1, alpha = 1}  
local batteryThreshold    = 30
local hideTextDelay       = 2
local canvasWidth         = fontSize + 4
local canvasHeight        = fontSize + 2

function displayTimeNearMouse()
  local mousePosition = hs.mouse.absolutePosition()
  local screen = hs.mouse.getCurrentScreen()
  screenBounds = screen:fullFrame()

  local function checkBatteryStatus()
    local batteryPercentage = hs.battery.percentage()
    local isCharging = hs.battery.isCharging()

    if batteryPercentage <= batteryThreshold and not isCharging then
      return lowBatteryColor
    else
      return normalColor
    end
  end

  local hoursString

  local function updateHoursString(newString)
    hoursString = hs.styledtext.new(newString, {
      font = {name = fontName, size = fontSize},
      color = checkBatteryStatus(),
      shadow = {
        offset = {h = -1, w = 0},
        blurRadius = 2,
        color = {alpha = 1}
      }
    })
  end

  local formatString = is24HourFormat and "%H" or "%I"
  updateHoursString(os.date(formatString))

  local textPositionRadius = textPositionRadius

  local function getMinutesAngle()
    local currentTime = os.date("*t")
    return (currentTime.min * 6) + (currentTime.sec * 0.1)
  end

  local function getHoursTextPosition(mousePosition, angle)
    local x = mousePosition.x + textPositionRadius * math.sin(math.rad(angle)) - 8
    local y = mousePosition.y - textPositionRadius * math.cos(math.rad(angle)) - 7

    -- boundary check
    screenBounds = hs.mouse.getCurrentScreen():fullFrame()
    local edgeMargin = 8

    if x < edgeMargin then
      x = edgeMargin
    elseif x + canvasWidth > screenBounds.w - edgeMargin then
      x = screenBounds.w - edgeMargin - canvasWidth
    end

    if y < edgeMargin then
      y = edgeMargin
    elseif y + canvasHeight > screenBounds.h - edgeMargin then
      y = screenBounds.h - edgeMargin - canvasHeight
    end

    return hs.geometry.point(x, y)
end

  local hoursTextPosition = getHoursTextPosition(mousePosition, getMinutesAngle())

  local hoursText = hs.canvas.new(hs.geometry.rect(hoursTextPosition.x, hoursTextPosition.y, canvasWidth, canvasHeight))
  hoursText[1] = {
    type = "text",
    text = hoursString,
  }

  local function updateHoursText()
    updateHoursString(os.date(formatString))
    hoursText[1].text = hoursString
    local minuteHandleAngle = getMinutesAngle()
    local hoursTextPosition = getHoursTextPosition(mousePosition, minuteHandleAngle)
    hoursText:topLeft(hoursTextPosition)
    hoursText:show()
  end

  local fadeOutDuration = 0.25
  local fadeOutStep = 0.0125
  local fadeOutAlphaStep = fadeOutStep / fadeOutDuration

  local function fadeOutText()
    local currentAlpha = hoursText:alpha()

    if currentAlpha > 0 then
      hoursText:alpha(currentAlpha - fadeOutAlphaStep)
      hs.timer.doAfter(fadeOutStep, fadeOutText)
    else
      hoursText:hide()
    end
  end

  local hideTextTimer = hs.timer.delayed.new(hideTextDelay, fadeOutText)

  local updateOnMouseMove = hs.eventtap.new({hs.eventtap.event.types.mouseMoved}, function(event)
    if event:getType() == hs.eventtap.event.types.mouseMoved then
      mousePosition = hs.mouse.absolutePosition()
      updateHoursText()
      hoursText:alpha(1)
      hideTextTimer:stop()
      hideTextTimer:start()
    end
    return false
  end)

  updateOnMouseMove:start()

  local batteryCheckTimer = hs.timer.new(60, function()
    updateHoursString(os.date(formatString))
  end)

  batteryCheckTimer:start()

  local hideOnKeyDown = hs.eventtap.new({hs.eventtap.event.types.keyDown, hs.eventtap.event.types.leftMouseDragged}, function(event)
    hoursText:hide()
    return false
  end)

  hideOnKeyDown:start()

  return {updateOnMouseMove, hideOnKeyDown}
end

local mouseEventTap = displayTimeNearMouse()

function screenWatcherCallback(eventType)
  if eventType == hs.caffeinate.watcher.screensDidUnlock then
    if not mouseEventTap:isEnabled() then
      mouseEventTap:start()
    end
  elseif eventType == hs.caffeinate.watcher.screensDidLock then
    if mouseEventTap:isEnabled() then
      mouseEventTap:stop()
    end
  end
end

local screenWatcher = hs.caffeinate.watcher.new(screenWatcherCallback)
screenWatcher:start()
