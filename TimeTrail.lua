-- TimeTrail
-- This Hammerspoon script displays the current time near the mouse pointer as you move it across the screen.

function mouseHighlight()
  -- Get the current co-ordinates of the mouse pointer
  local mousepoint = hs.mouse.absolutePosition()
  local screen = hs.mouse.getCurrentScreen()
  local rect = screen:fullFrame()

  -- Calculate offsets to keep the time visible when close to the right or bottom screen edges
  local offsetX = (mousepoint.x + 180 > rect.x + rect.w) and -40 or 16
  local offsetY = (mousepoint.y + 180 > rect.y + rect.h) and -40 or 16

  -- Function to get the text color based on the battery percentage and charging status
  local function getTextColor()
    local batteryPercentage = hs.battery.percentage()
    local isCharging = hs.battery.isCharging()

    if batteryPercentage <= 30 and not isCharging then
      return {red = 1, alpha = 1}
    else
      return {white = 1, alpha = 1}
    end
  end

  -- Create the styled text object for hours
  local hoursString = hs.styledtext.new(os.date("%H"), {
    font = {name = "Helvetica Neue", size = 16},
    color = getTextColor(),
    shadow = {
      offset = {h = -1, w = 0},
      blurRadius = 2,
      color = {alpha = 1}
    }
  })

  local radius = 30

  -- Function to calculate the angle of the minute handle
  local function getMinuteHandleAngle()
    local currentTime = os.date("*t")
    return (currentTime.min * 6) + (currentTime.sec * 0.1)
  end

  -- Function to calculate the position of the hours text
  local function getHoursTextPosition(mousepoint, angle)
    local x = mousepoint.x + radius * math.sin(math.rad(angle)) - 8 -- Subtract half the width of the bounding box (40 / 2)
    local y = mousepoint.y - radius * math.cos(math.rad(angle)) - 9 -- Subtract half the height of the bounding box (40 / 2)
    return hs.geometry.point(x, y)
  end

  local hoursTextPosition = getHoursTextPosition(mousepoint, getMinuteHandleAngle())
  local hoursText = hs.drawing.text(hs.geometry.rect(hoursTextPosition.x, hoursTextPosition.y, 20, 18), hoursString)

  -- Set the appearance of the hours text
  hoursText:setTextSize(24)

  -- Show the hours text
  hoursText:bringToFront()
  hoursText:show()

  -- Function to update the hours text
  local function updateHoursText()
    -- Update the hours string
    hoursString = hs.styledtext.new(os.date("%H"), {
      font = {name = "Helvetica Neue", size = 16},
      color = getTextColor(),
      shadow = {
        offset = {h = -1, w = 0},
        blurRadius = 2,
        color = {alpha = 1}
      }
    })

    -- Update the hours text object
    hoursText:setStyledText(hoursString)

    -- Update the position of the hours text
    local minuteHandleAngle = getMinuteHandleAngle()
    local hoursTextPosition = getHoursTextPosition(mousepoint, minuteHandleAngle)
    hoursText:setTopLeft(hoursTextPosition)
    hoursText:bringToFront()
    hoursText:show()
  end

  -- Create an eventtap to listen for mouse events
  local mouseTap = hs.eventtap.new({hs.eventtap.event.types.mouseMoved, hs.eventtap.event.types.leftMouseDragged}, function(event)
    -- Update the hours text only when the mouse is moved
    if event:getType() == hs.eventtap.event.types.mouseMoved or event:getType() == hs.eventtap.event.types.leftMouseDragged then
      mousepoint = hs.mouse.absolutePosition()
      updateHoursText()
    end
    return false
  end)

  local fadeOutDuration = 0.25 -- Duration of the fade-out effect in seconds
  local fadeOutStep = 0.0125 -- Time between each fade-out step in seconds
  local fadeOutAlphaStep = fadeOutStep / fadeOutDuration -- Decrease in alpha value at each step

  local function fadeOutText()
    local currentAlpha = hoursText:alpha()

    if currentAlpha > 0 then
      hoursText:setAlpha(currentAlpha - fadeOutAlphaStep)
      hs.timer.doAfter(fadeOutStep, fadeOutText)
    else
      hoursText:hide()
    end
  end

  local hideTextTimer = hs.timer.delayed.new(2.5, function()
    fadeOutText()
  end)

  -- Create an eventtap to listen for mouse events
  local mouseTap = hs.eventtap.new({hs.eventtap.event.types.mouseMoved, hs.eventtap.event.types.leftMouseDragged}, function(event)
    -- Update the hours text only when the mouse is moved
    if event:getType() == hs.eventtap.event.types.mouseMoved or event:getType() == hs.eventtap.event.types.leftMouseDragged then
      mousepoint = hs.mouse.absolutePosition()
      updateHoursText()

      -- Show the hours text, set the alpha value to 1, and reset the hide timer
      hoursText:show()
      hoursText:setAlpha(1)
      hideTextTimer:stop()
      hideTextTimer:start()
    end
    return false
  end)

  mouseTap:start()

  -- Create a timer to periodically check the battery percentage and charging status
  local batteryCheckTimer = hs.timer.new(60, function()
    updateHoursText()
  end)
  batteryCheckTimer:start()

  -- Create an eventtap to listen for key events
  local keyTap = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(event)
    -- Hide the hours text when typing starts
    hoursText:hide()
    return false
  end)

  keyTap:start()
  return {mouseTap, keyTap}
end


-- Hide the Hammerspoon Dock icon
hs.dockicon.hide()
local mouseEventTap = mouseHighlight()

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