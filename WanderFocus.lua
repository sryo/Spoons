-- WanderFocus: A focus-follows-mouse implementation for Hammerspoon.

local wanderTimer = nil
local wanderDelay = 0.2
local buffer = 16
local ignoreConditions = { cmdPressed = false, dragging = false, missionControlActive = false }

local function isMissionControlActive()
    return hs.spaces.missionControlSpace() ~= nil
end

local function getVisibleWindows()
    return hs.window.orderedWindows()
end

local function getAdjustedFrame(win)
    local frame = win:frame()
    frame.x = frame.x - buffer
    frame.y = frame.y - buffer
    frame.w = frame.w + (2 * buffer)
    frame.h = frame.h + (2 * buffer)
    return frame
end

-- Ensure window frame does not go below buffer distance from screen edges
local function isPointInFrame(point, frame)
    local screenFrame = hs.screen.mainScreen():frame()

    local adjFrameX = math.max(frame.x, screenFrame.x + buffer)
    local adjFrameY = math.max(frame.y, screenFrame.y + buffer)
    local adjFrameW = math.min(frame.x + frame.w, screenFrame.x + screenFrame.w - buffer) - adjFrameX
    local adjFrameH = math.min(frame.y + frame.h, screenFrame.y + screenFrame.h - buffer) - adjFrameY

    return point.x >= adjFrameX and point.x <= (adjFrameX + adjFrameW)
        and point.y >= adjFrameY and point.y <= (adjFrameY + adjFrameH)
end

local function isModal(win)
    if not win then return false end
    local role = win:role()
    local subrole = win:subrole()
    -- Common roles/subroles for modals
    local modalRoles = {
        AXSystemDialog = true,
        AXDialog = true,
        AXSheet = true,
        AXPopover = true
    }
    return modalRoles[role] or modalRoles[subrole]
end

local function focusWindowUnderCursor()
    if ignoreConditions.cmdPressed or ignoreConditions.dragging or ignoreConditions.missionControlActive then
        return -- Abort if any ignore condition is met
    end

    -- Check if current focused window is a modal
    local currentFocus = hs.window.focusedWindow()
    if isModal(currentFocus) then
        return -- Don't change focus
    end

    local mousePoint = hs.mouse.absolutePosition()
    local windows = getVisibleWindows()

    for _, win in ipairs(windows) do
        local adjustedFrame = getAdjustedFrame(win)
        if isPointInFrame(mousePoint, adjustedFrame) then
            local app = win:application()
            if app then
                local winId = win:id()
                app:activate()
                hs.timer.doAfter(0.001, function()
                    local freshWin = hs.window.get(winId)
                    if freshWin then
                        freshWin:focus()
                    end
                end)
            end
            break
        end
    end
end

local mouseWatcher = hs.eventtap.new({ hs.eventtap.event.types.mouseMoved }, function()
    if wanderTimer then
        wanderTimer:stop()
        wanderTimer = nil
    end
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
    hs.timer.doAfter(0.5, function()
        ignoreConditions.dragging = false
    end)
    return false
end):start()

hs.shutdownCallback = function()
    if wanderTimer then
        wanderTimer:stop()
        wanderTimer = nil
    end
    if mouseWatcher then mouseWatcher:stop() end
    if cmdWatcher then cmdWatcher:stop() end
    if missionControlWatcher then missionControlWatcher:stop() end
    if draggingWatcher then draggingWatcher:stop() end
end
