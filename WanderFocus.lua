-- WanderFocus: A focus-follows-mouse implementation for Hammerspoon.

local wanderTimer = nil
local dragTimer = nil
local gracePeriodTimer = nil
local wanderDelay = 0.2
local buffer = 16

local scrollCooldown = 0
local scrollCheckInterval = 0.2

local ignoredApps = {
    ["Parallels Desktop"] = true,
    ["VMware Fusion"] = true,
    ["Alfred"] = true,
    ["Raycast"] = true,
    ["Spotlight"] = true,
    ["LoginWindow"] = true
}

local ignoreConditions = {
    cmdPressed = false,
    dragging = false,
    switching = false
}


local function isUIObstruction(point)
    local success, result = pcall(function()
        local elem = hs.axuielement.systemWideElement():elementAtPosition(point)
        if not elem then return false end

        local pid = elem:pid()
        if pid then
            local app = hs.application.applicationForPID(pid)
            if app and app:bundleID() == "com.apple.dock" then return true end -- Check App (Dock)
        end

        local role = elem:attributeValue("AXRole") -- Check Roles (Menus)
        if role == "AXMenuBar" or role == "AXMenuBarItem" or role == "AXMenu" or role == "AXMenuItem" then
            return true
        end
        return false
    end)

    return success and result or false -- If API fails (crash/timeout), assume NO obstruction to keep things moving
end

-- Check for Typing (Protects Finder Rename / Desktop Rename)
local function isTyping()
    local success, result = pcall(function()
        -- We use systemWideElement because renaming on Desktop has NO focused window
        local system = hs.axuielement.systemWideElement()
        local currentElement = system:attributeValue("AXFocusedUIElement")

        if not currentElement then return false end

        local role = currentElement:attributeValue("AXRole")

        -- Block switch if editing text (Rename, Forms, Spotlight, etc)
        if role == "AXTextField" or role == "AXTextArea" or role == "AXComboBox" then
            return true
        end
        return false
    end)

    -- If API fails, assume NOT typing (fail open) or True (fail closed)?
    if not success then
        return false
    end
    return result
end

local function isModal(win)
    if not win then return false end
    local modalTypes = { AXDialog = true, AXSystemDialog = true, AXSheet = true, AXSavePanel = true, AXPopover = true }
    return modalTypes[win:role()] or modalTypes[win:subrole()]
end

local function getAdjustedFrame(win)
    local frame = win:frame()
    local screenFrame = win:screen():frame()
    local newW, newH = frame.w - 2 * buffer, frame.h - 2 * buffer
    if newW <= 0 or newH <= 0 then return frame end

    return {
        x = math.max(frame.x + buffer, screenFrame.x),
        y = math.max(frame.y + buffer, screenFrame.y),
        w = math.min(newW, screenFrame.w - (frame.x - screenFrame.x)),
        h = math.min(newH, screenFrame.h - (frame.y - screenFrame.y))
    }
end

local function focusWindowUnderCursor()
    if ignoreConditions.cmdPressed or ignoreConditions.dragging or ignoreConditions.switching then return end

    local mousePoint = hs.mouse.absolutePosition()
    local mouseScreen = hs.mouse.getCurrentScreen()
    if not mouseScreen then return end

    if isUIObstruction(mousePoint) then return end

    local windows = hs.fnutils.filter(hs.window.orderedWindows(), function(win)
        if win:screen() ~= mouseScreen then return false end
        local app = win:application()
        if not app then return false end
        return win:isVisible()
            and not win:isMinimized()
            and win:isStandard()
            and not ignoredApps[app:name()]
    end)

    local currentFocus = hs.window.focusedWindow()
    if isModal(currentFocus) then return end

    for _, win in ipairs(windows) do
        local adjFrame = getAdjustedFrame(win)

        if mousePoint.x >= adjFrame.x and mousePoint.x <= (adjFrame.x + adjFrame.w) and
            mousePoint.y >= adjFrame.y and mousePoint.y <= (adjFrame.y + adjFrame.h) then
            if win ~= currentFocus then
                if isTyping() then return end
                win:focus()
            end
            break
        end
    end
end

local mouseWatcher = hs.eventtap.new({ hs.eventtap.event.types.mouseMoved }, function()
    if wanderTimer then wanderTimer:stop() end
    wanderTimer = hs.timer.doAfter(wanderDelay, focusWindowUnderCursor)
    return false
end):start()

local scrollWatcher = hs.eventtap.new({ hs.eventtap.event.types.scrollWheel }, function()
    local now = hs.timer.secondsSinceEpoch()
    if (now - scrollCooldown) > scrollCheckInterval then
        if wanderTimer then wanderTimer:stop() end
        focusWindowUnderCursor()
        scrollCooldown = now
    end
    return false
end):start()

local draggingWatcher = hs.eventtap.new({ hs.eventtap.event.types.leftMouseDragged }, function()
    ignoreConditions.dragging = true
    if dragTimer then dragTimer:stop() end
    dragTimer = hs.timer.doAfter(0.5, function() ignoreConditions.dragging = false end)
    return false
end):start()

local cmdWatcher = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged }, function(event)
    local flags = event:getFlags()
    if flags.cmd then
        ignoreConditions.cmdPressed = true
        if gracePeriodTimer then gracePeriodTimer:stop() end
    else
        ignoreConditions.cmdPressed = false
        ignoreConditions.switching = true
        gracePeriodTimer = hs.timer.doAfter(0.5, function()
            ignoreConditions.switching = false
        end)
    end
    return false
end):start()

hs.shutdownCallback = function()
    if wanderTimer then wanderTimer:stop() end
    if dragTimer then dragTimer:stop() end
    if gracePeriodTimer then gracePeriodTimer:stop() end
    mouseWatcher:stop()
    scrollWatcher:stop()
    draggingWatcher:stop()
    cmdWatcher:stop()
end
