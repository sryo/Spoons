-- Window movement and focus operations

local geometry = require("hs.geometry")
local mouse    = require("hs.mouse")
local screen   = require("hs.screen")
local window   = require("hs.window")
local timer    = require("hs.timer")

local cfg, callbacks

local function log(msg)
    if callbacks.log then callbacks.log(msg) end
end

local function warn(msg)
    if callbacks.warn then callbacks.warn(msg) else log(msg) end
end

-- Move mouse to maintain relative position when window moves
local function moveMouseWithWindow(oldFrame, newFrame)
    if not (oldFrame and newFrame) then return end
    local mousePos = mouse.absolutePosition()
    if geometry.isPointInRect(mousePos, oldFrame) then
        local relX = (mousePos.x - oldFrame.x) / oldFrame.w
        local relY = (mousePos.y - oldFrame.y) / oldFrame.h
        local newX = newFrame.x + (relX * newFrame.w)
        local newY = newFrame.y + (relY * newFrame.h)
        mouse.absolutePosition({ x = newX, y = newY })
    end
end

-- Move focused window forward/backward in tiling order.
-- Orientation-aware: on landscape, "forward" swaps with the window to the right
-- and "backward" with the one to the left. On portrait, "forward" swaps with the
-- window below and "backward" with the one above. Wraps at edges. Only swaps
-- within the focused window's screen.
local function moveWindowInOrder(direction)
    local currentSpace = callbacks.getCurrentSpace()
    local focusedWindow = window.focusedWindow()
    if not focusedWindow then
        callbacks.updateWindowOrder()
        return
    end

    local focusedScreen = focusedWindow:screen()
    if not focusedScreen then
        callbacks.updateWindowOrder()
        return
    end

    local screenFrame = focusedScreen:frame()
    local screenId = focusedScreen:id()
    local horizontal = (screenFrame.w > screenFrame.h)

    local windowOrder = callbacks.getWindowOrder(currentSpace)

    local sorted = {}
    for _, win in ipairs(windowOrder) do
        local sz = win:size()
        local s = win:screen()
        if sz and sz.h > cfg.collapsedWindowHeight and s and s:id() == screenId then
            table.insert(sorted, win)
        end
    end

    table.sort(sorted, function(a, b)
        local fa, fb = a:frame(), b:frame()
        if horizontal then
            return (fa.x + fa.w / 2) < (fb.x + fb.w / 2)
        else
            return (fa.y + fa.h / 2) < (fb.y + fb.h / 2)
        end
    end)

    local focusedIndex
    for i, win in ipairs(sorted) do
        if win:id() == focusedWindow:id() then
            focusedIndex = i
            break
        end
    end

    if not focusedIndex or #sorted < 2 then
        callbacks.updateWindowOrder()
        return
    end

    local targetIndex
    if direction == "forward" then
        if focusedIndex >= #sorted then return end
        targetIndex = focusedIndex + 1
    else
        if focusedIndex <= 1 then return end
        targetIndex = focusedIndex - 1
    end

    sorted[focusedIndex], sorted[targetIndex] = sorted[targetIndex], sorted[focusedIndex]

    local newOrder = {}
    local sIdx = 1
    for _, win in ipairs(windowOrder) do
        local sz = win:size()
        local s = win:screen()
        local onScreen = s and s:id() == screenId
        local nonCollapsed = sz and sz.h > cfg.collapsedWindowHeight
        if onScreen and nonCollapsed then
            table.insert(newOrder, sorted[sIdx])
            sIdx = sIdx + 1
        else
            table.insert(newOrder, win)
        end
    end

    local oldFrame = focusedWindow:frame()
    callbacks.setWindowOrder(currentSpace, newOrder)
    callbacks.tileWindows()
    focusedWindow:focus()
    local newFrame = focusedWindow:frame()
    moveMouseWithWindow(oldFrame, newFrame)
    callbacks.drawOutline(focusedWindow)
end

-- Focus next/previous window in tiling order
local function focusAdjacentWindow(direction)
    local currentSpace = callbacks.getCurrentSpace()
    local focusedWindow = window.focusedWindow()
    local windowOrder = callbacks.getWindowOrder(currentSpace)

    local focusedScreen = focusedWindow and focusedWindow:screen()
    local screenWindows = {}

    for _, win in ipairs(windowOrder) do
        local sz = win:size()
        local winScreen = win:screen()
        if sz and sz.h > cfg.collapsedWindowHeight then
            if not focusedScreen or (winScreen and winScreen:id() == focusedScreen:id()) then
                table.insert(screenWindows, win)
            end
        end
    end

    if #screenWindows == 0 then return end

    local focusedIndex = 0
    if focusedWindow then
        for i, win in ipairs(screenWindows) do
            if win:id() == focusedWindow:id() then
                focusedIndex = i
                break
            end
        end
    end

    local targetIndex
    if direction == "forward" or direction == "next" then
        if focusedIndex >= #screenWindows then return end
        targetIndex = focusedIndex + 1
    else
        if focusedIndex <= 1 then return end
        targetIndex = focusedIndex - 1
    end

    local targetWin = screenWindows[targetIndex]
    if targetWin then
        local newFrame = targetWin:frame()
        targetWin:focus()
        callbacks.drawOutline(targetWin)

        if newFrame then
            local centerX = newFrame.x + newFrame.w / 2
            local centerY = newFrame.y + newFrame.h / 2
            mouse.absolutePosition({ x = centerX, y = centerY })
        end
    end
end

-- Move window to adjacent screen
local function moveWindowToAdjacentScreen(direction)
    local focusedWindow = window.focusedWindow()
    if not focusedWindow then
        warn("No focused window; cannot move to adjacent screen")
        return
    end

    local oldFrame = focusedWindow:frame()
    local currentScreen = focusedWindow:screen()
    if not currentScreen then
        warn("No screen for focused window; cannot move to adjacent screen")
        return
    end

    local allScreens = screen.allScreens()
    if #allScreens < 2 then
        warn("Only one screen available; cannot move window")
        return
    end

    local currentScreenIndex
    for i, scr in ipairs(allScreens) do
        if scr:id() == currentScreen:id() then
            currentScreenIndex = i
            break
        end
    end

    if not currentScreenIndex then
        warn("Current screen not found in screen list")
        return
    end

    local targetScreenIndex
    if direction == "next" then
        targetScreenIndex = (currentScreenIndex % #allScreens) + 1
    else
        targetScreenIndex = ((currentScreenIndex - 2 + #allScreens) % #allScreens) + 1
    end

    local targetScreen = allScreens[targetScreenIndex]
    if not targetScreen then
        warn("Target screen not resolved; aborting move")
        return
    end

    local targetFrame = targetScreen:frame()
    local oldScreenFrame = currentScreen:frame()

    local relX = (oldFrame.x - oldScreenFrame.x) / oldScreenFrame.w
    local relY = (oldFrame.y - oldScreenFrame.y) / oldScreenFrame.h
    local relW = oldFrame.w / oldScreenFrame.w
    local relH = oldFrame.h / oldScreenFrame.h

    local newFrame = {
        x = targetFrame.x + (relX * targetFrame.w),
        y = targetFrame.y + (relY * targetFrame.h),
        w = relW * targetFrame.w,
        h = relH * targetFrame.h
    }

    callbacks.hideOutline()
    focusedWindow:setFrame(geometry.rect(newFrame), 0)

    timer.doAfter(0.15, function()
        focusedWindow:focus()
        callbacks.updateWindowOrder()
        callbacks.tileWindows()
        local finalFrame = focusedWindow:frame()
        moveMouseWithWindow(oldFrame, finalFrame)
        callbacks.drawOutline(focusedWindow)
    end)
end

-- Calculate where a dropped window should be inserted in tiling order.
-- `dropFrame` is the window's frame captured at drop time — pass the captured
-- value, not `win:frame()` from later, since a retile may have moved the window.
local function calculateDropPosition(dropFrame, screenWindows, screenFrame)
    if not dropFrame then return 1 end
    local dropCenterX = dropFrame.x + dropFrame.w / 2
    local dropCenterY = dropFrame.y + dropFrame.h / 2
    local horizontal = (screenFrame.w > screenFrame.h)

    local insertIndex = 1
    for i, win in ipairs(screenWindows) do
        local winFrame = win:frame()
        local winCenterX = winFrame.x + winFrame.w / 2
        local winCenterY = winFrame.y + winFrame.h / 2

        if horizontal then
            if dropCenterX > winCenterX then
                insertIndex = i + 1
            end
        else
            if dropCenterY > winCenterY then
                insertIndex = i + 1
            end
        end
    end

    return insertIndex
end

-- Adjust focused window weight by `delta` (positive = grow, negative = shrink).
-- Clamps against cfg.widthMin / cfg.widthMax; tiler also floors at 0.1.
local function adjustFocusedWidth(delta)
    local win = window.focusedWindow()
    if not win then return end
    if not (callbacks.getWindowWeight and callbacks.setWindowWeight) then return end
    local current = callbacks.getWindowWeight(win)
    local target  = math.max(cfg.widthMin, math.min(cfg.widthMax, current + delta))
    callbacks.setWindowWeight(win, target)
    if callbacks.tileWindows then callbacks.tileWindows() end
    if callbacks.updateFullscreenOverlays then callbacks.updateFullscreenOverlays() end
    log(string.format("Width %s to %.2f", delta >= 0 and "grew" or "shrank", target))
end

local function grow()
    adjustFocusedWidth(cfg.widthStep)
end

local function shrink()
    adjustFocusedWidth(-cfg.widthStep)
end

-- Reset the focused window's weight to cfg.widthDefault. Other windows untouched
-- (the Ctrl+Cmd+0 hotkey clears the whole weights table; this is per-window).
local function cycleWidth()
    local win = window.focusedWindow()
    if not win then return end
    if not callbacks.setWindowWeight then return end
    callbacks.setWindowWeight(win, cfg.widthDefault)
    if callbacks.tileWindows then callbacks.tileWindows() end
    if callbacks.updateFullscreenOverlays then callbacks.updateFullscreenOverlays() end
    log(string.format("Width reset to %.2f", cfg.widthDefault))
end

local function resetAllWeights()
    if callbacks.clearAllWeights then callbacks.clearAllWeights() end
    if callbacks.tileWindows then callbacks.tileWindows() end
    if callbacks.updateFullscreenOverlays then callbacks.updateFullscreenOverlays() end
end

local function forceRetile()
    if callbacks.resetTilingCount then callbacks.resetTilingCount() end
    if callbacks.clearSnapshotCreating then callbacks.clearSnapshotCreating() end
    if callbacks.updateWindowOrder then callbacks.updateWindowOrder() end
    if callbacks.tileWindows then callbacks.tileWindows() end
    if callbacks.updateFullscreenOverlays then callbacks.updateFullscreenOverlays() end
end

local function init(config, cbs)
    cfg = config
    callbacks = cbs or {}
end

return {
    init = init,
    moveMouseWithWindow = moveMouseWithWindow,
    moveWindowInOrder = moveWindowInOrder,
    focusAdjacentWindow = focusAdjacentWindow,
    moveWindowToAdjacentScreen = moveWindowToAdjacentScreen,
    calculateDropPosition = calculateDropPosition,
    grow = grow,
    shrink = shrink,
    cycleWidth = cycleWidth,
    resetAllWeights = resetAllWeights,
    forceRetile = forceRetile,
}
