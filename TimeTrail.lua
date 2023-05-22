-- TimeTrail
-- This Hammerspoon script displays the current time near the mouse pointer as you move it across the screen.
-- The text turns red if the battery is low, fades out if the mouse is idle and disappears during typing.

function displayTimeNearMouse()
  local mousePosition = hs.mouse.absolutePosition()
  local screen = hs.mouse.getCurrentScreen()
  local rect = screen:fullFrame()

  local function getTextColor()
    local batteryPercentage = hs.battery.percentage()
    local isCharging = hs.battery.isCharging()

    if batteryPercentage <= 30 and not isCharging then
      return {red = 1, alpha = 1}
    else
      return {white = 1, alpha = 1}
    end
  end

  local hoursString = hs.styledtext.new(os.date("%H"), {
    font = {size = 16},
    color = getTextColor(),
    shadow = {
      offset = {h = -1, w = 0},
      blurRadius = 2,
      color = {alpha = 1}
    }
  })

  local textPositionRadius = 30

  local function getMinutesAngle()
    local currentTime = os.date("*t")
    return (currentTime.min * 6) + (currentTime.sec * 0.1)
  end

  local function getHoursTextPosition(mousePosition, angle)
    local x = mousePosition.x + textPositionRadius * math.sin(math.rad(angle)) - 10
    local y = mousePosition.y - textPositionRadius * math.cos(math.rad(angle)) - 9
  
    return hs.geometry.point(x, y)
  end

  local hoursTextPosition = getHoursTextPosition(mousePosition, getMinutesAngle())

  local hoursText = hs.canvas.new(hs.geometry.rect(hoursTextPosition.x, hoursTextPosition.y, 20, 18))

  hoursText[1] = {
    type = "text",
    text = hoursString,
  }

  local function updateHoursString(newString)
    hoursString = hs.styledtext.new(newString, {
      font = {name = "Helvetica Neue", size = 16},
      color = getTextColor(),
      shadow = {
        offset = {h = -1, w = 0},
        blurRadius = 2,
        color = {alpha = 1}
      }
    })

    hoursText[1].text = hoursString
  end

  local function updateHoursText()
    updateHoursString(os.date("%H"))
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

  local hideTextTimer = hs.timer.delayed.new(2, function()
    fadeOutText()
  end)

  -- Update the hours text only when the mouse is moved
  local mouseTap = hs.eventtap.new({hs.eventtap.event.types.mouseMoved, hs.eventtap.event.types.leftMouseDragged}, function(event)
    if event:getType() == hs.eventtap.event.types.mouseMoved or event:getType() == hs.eventtap.event.types.leftMouseDragged then
      mousePosition = hs.mouse.absolutePosition()
      updateHoursText()

      -- Show the hours
      hoursText:alpha(1)
      hideTextTimer:stop()
      hideTextTimer:start()
    end
    return false
  end)

  mouseTap:start()

  -- Check the battery percentage and charging status
  local batteryCheckTimer = hs.timer.new(60, function()
    updateHoursString(os.date("%H"))
  end)

  batteryCheckTimer:start()

  -- Hide the hours text when typing starts
  local keyTap = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(event)
    hoursText:hide()
    return false
  end)

  keyTap:start()

  return {mouseTap, keyTap}
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
