-- WanderFocus: A focus-follows-mouse implementation for Hammerspoon.
local wanderTimer = nil
local wanderDelay = 0.2
local ignoreConditions = { cmdPressed = false, dragging = false, missionControlActive = false }

local function isMissionControlActive()
    return hs.spaces.missionControlSpace() ~= nil
end

local function getVisibleWindows()
    return hs.window.orderedWindows()
end

-- Remove padding around windows.
local function getAdjustedFrame(win)
    local frame = win:frame()
    frame.x = frame.x + 3
    frame.y = frame.y + 3
    frame.w = frame.w - 6
    frame.h = frame.h - 6
    return frame
end

local function isPointInFrame(point, frame)
    return point.x >= frame.x and point.x <= (frame.x + frame.w)
        and point.y >= frame.y and point.y <= (frame.y + frame.h)
end

local function focusWindowUnderCursor()
    if ignoreConditions.cmdPressed or ignoreConditions.dragging or ignoreConditions.missionControlActive then
        return -- Abort if any ignore condition is met
    end

    local mousePoint = hs.mouse.absolutePosition()
    local windows = getVisibleWindows()

    for _, win in ipairs(windows) do
        local adjustedFrame = getAdjustedFrame(win)
        if isPointInFrame(mousePoint, adjustedFrame) then
            win:focus()
            break
        end
    end
end

local mouseWatcher = hs.eventtap.new({ hs.eventtap.event.types.mouseMoved }, function()
    if wanderTimer then wanderTimer:stop() end
    wanderTimer = hs.timer.doAfter(wanderDelay, focusWindowUnderCursor)
    return false
end):start()

local cmdWatcher = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged }, function(event)
    ignoreConditions.cmdPressed = event:getFlags().cmd
    return false
end):start()

local missionControlWatcher = hs.spaces.watcher.new(function()
    ignoreConditions.missionControlActive = isMissionControlActive()
end):start()

local draggingWatcher = hs.eventtap.new({ hs.eventtap.event.types.leftMouseDragged }, function()
    ignoreConditions.dragging = true
    hs.timer.doAfter(0.5, function() ignoreConditions.dragging = false end) -- Reset dragging after a short delay
    return false
end):start()

hs.shutdownCallback = function()
    if mouseWatcher then mouseWatcher:stop() end
    if cmdWatcher then cmdWatcher:stop() end
    if missionControlWatcher then missionControlWatcher:stop() end
    if draggingWatcher then draggingWatcher:stop() end
end
