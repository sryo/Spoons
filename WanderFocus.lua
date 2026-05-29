-- WanderFocus: focus-follows-mouse for Hammerspoon.

local module = {}

module.cfg = {
    wanderDelay = 0.2,
    buffer = 16,
    scrollCheckInterval = 0.2,
    cmdReleaseGate = 0.5,
    dragGate = 0.5,
    mode = "autoraise", -- "autoraise" | "autofocus" | "off"
    ignoredApps = {
        ["Parallels Desktop"] = true,
        ["VMware Fusion"] = true,
        ["Alfred"] = true,
        ["Raycast"] = true,
        ["Spotlight"] = true,
        ["LoginWindow"] = true,
    },
}

local ignoreConditions = {
    cmdPressed = false,
    dragging = false,
    cmdReleaseGate = false,
}

local focusCache = nil -- { win = hs.window, frame = rect } when valid
local scrollCooldown = 0

local function isUIObstruction(point)
    local ok, result = pcall(function()
        local elem = hs.axuielement.systemWideElement():elementAtPosition(point)
        if not elem then return false end

        local pid = elem:pid()
        if pid then
            local app = hs.application.applicationForPID(pid)
            if app and app:bundleID() == "com.apple.dock" then return true end
        end

        local role = elem:attributeValue("AXRole")
        if role == "AXMenuBar" or role == "AXMenuBarItem" or role == "AXMenu" or role == "AXMenuItem" then
            return true
        end
        return false
    end)

    return ok and result or false
end

local function isTyping()
    -- Protect Finder / Desktop rename and short form fields. AXTextArea is
    -- intentionally excluded: it's the permanent focus of editor windows
    -- (Terminal, TextEdit, Notes, IDEs) and would block focus-follow there.
    -- systemWideElement because Desktop rename has no focused window.
    local ok, result = pcall(function()
        local sys = hs.axuielement.systemWideElement()
        local elem = sys:attributeValue("AXFocusedUIElement")
        if not elem then return false end
        local role = elem:attributeValue("AXRole")
        return role == "AXTextField" or role == "AXComboBox"
    end)
    return ok and result or false
end

local modalTypes = {
    AXDialog = true, AXSystemDialog = true, AXSheet = true,
    AXSavePanel = true, AXPopover = true,
}

local function isModal(win)
    if not win then return false end
    local ok, result = pcall(function()
        return modalTypes[win:role()] or modalTypes[win:subrole()] or false
    end)
    return ok and result or false
end

local function getAdjustedFrame(win)
    local frame = win:frame()
    local screenFrame = win:screen():frame()
    local buffer = module.cfg.buffer
    local newW, newH = frame.w - 2 * buffer, frame.h - 2 * buffer
    if newW <= 0 or newH <= 0 then return frame end

    return {
        x = math.max(frame.x + buffer, screenFrame.x),
        y = math.max(frame.y + buffer, screenFrame.y),
        w = math.min(newW, screenFrame.w - (frame.x - screenFrame.x)),
        h = math.min(newH, screenFrame.h - (frame.y - screenFrame.y)),
    }
end

local function pointInFrame(p, f)
    return p.x >= f.x and p.x <= (f.x + f.w)
       and p.y >= f.y and p.y <= (f.y + f.h)
end

local function focusOnto(win)
    if module.cfg.mode == "autofocus" then
        local axwin = hs.axuielement.windowElement(win)
        if axwin then axwin:setAttributeValue("AXMain", true) end
    else
        win:focus()
    end
end

function module._focusWindowUnderCursor()
    if module.cfg.mode == "off" then return end
    if ignoreConditions.cmdPressed or ignoreConditions.dragging or ignoreConditions.cmdReleaseGate then
        return
    end

    local mousePoint = hs.mouse.absolutePosition()
    local mouseScreen = hs.mouse.getCurrentScreen()
    if not mouseScreen then return end

    -- Short-circuit on cursor still inside the cached window's interior.
    -- pointInFrame first, focusedWindow() second so we skip the AX call
    -- whenever the cursor has left the cache box.
    if focusCache and pointInFrame(mousePoint, focusCache.frame)
       and hs.window.focusedWindow() == focusCache.win then
        return
    end

    if isUIObstruction(mousePoint) then return end

    local currentFocus = hs.window.focusedWindow()
    if isModal(currentFocus) then return end

    local ignored = module.cfg.ignoredApps
    -- visibleWindows() spans all screens; orderedWindows() is scoped to the
    -- currently focused space, which drops windows on a secondary display.
    local windows = hs.fnutils.filter(hs.window.visibleWindows(), function(win)
        if win:screen() ~= mouseScreen then return false end
        local app = win:application()
        if not app then return false end
        return win:isVisible()
            and not win:isMinimized()
            and win:isStandard()
            and not ignored[app:name()]
    end)

    for _, win in ipairs(windows) do
        local adj = getAdjustedFrame(win)
        if pointInFrame(mousePoint, adj) then
            if win ~= currentFocus then
                if isTyping() then return end
                focusOnto(win)
            end
            focusCache = { win = win, frame = adj }
            return
        end
    end
end

local function invalidateCache()
    focusCache = nil
end

function module.start()
    if module._mouseWatcher then return end

    local et = hs.eventtap.event.types

    module._mouseWatcher = hs.eventtap.new({ et.mouseMoved }, function()
        if module._wanderTimer then module._wanderTimer:stop() end
        module._wanderTimer = hs.timer.doAfter(module.cfg.wanderDelay, module._focusWindowUnderCursor)
        return false
    end):start()

    module._scrollWatcher = hs.eventtap.new({ et.scrollWheel }, function()
        local now = hs.timer.secondsSinceEpoch()
        if (now - scrollCooldown) > module.cfg.scrollCheckInterval then
            if module._wanderTimer then module._wanderTimer:stop() end
            module._focusWindowUnderCursor()
            scrollCooldown = now
        end
        return false
    end):start()

    module._dragWatcher = hs.eventtap.new({ et.leftMouseDragged }, function()
        ignoreConditions.dragging = true
        if module._dragTimer then module._dragTimer:stop() end
        module._dragTimer = hs.timer.doAfter(module.cfg.dragGate, function()
            ignoreConditions.dragging = false
        end)
        return false
    end):start()

    -- Only the cmd-down → cmd-up transition arms the grace gate. Tapping
    -- shift/alt/ctrl alone must not blind the module.
    module._cmdWatcher = hs.eventtap.new({ et.flagsChanged }, function(event)
        local cmdNow = event:getFlags().cmd or false
        if cmdNow then
            ignoreConditions.cmdPressed = true
            if module._gracePeriodTimer then module._gracePeriodTimer:stop() end
        elseif ignoreConditions.cmdPressed then
            ignoreConditions.cmdPressed = false
            ignoreConditions.cmdReleaseGate = true
            module._gracePeriodTimer = hs.timer.doAfter(module.cfg.cmdReleaseGate, function()
                ignoreConditions.cmdReleaseGate = false
            end)
        end
        return false
    end):start()
end

function module.stop()
    for _, key in ipairs({ "_mouseWatcher", "_scrollWatcher", "_dragWatcher", "_cmdWatcher" }) do
        local w = module[key]
        if w then w:stop(); module[key] = nil end
    end
    for _, key in ipairs({ "_wanderTimer", "_dragTimer", "_gracePeriodTimer" }) do
        local t = module[key]
        if t then t:stop(); module[key] = nil end
    end
    invalidateCache()
    ignoreConditions.cmdPressed = false
    ignoreConditions.dragging = false
    ignoreConditions.cmdReleaseGate = false
end

-- Exposed for tests.
module._ignoreConditions = ignoreConditions
module._invalidateCache = invalidateCache

return module
