-- Window snapshot (minimize) system

local canvas   = require("hs.canvas")
local geometry = require("hs.geometry")
local timer    = require("hs.timer")
local screen   = require("hs.screen")
local mouse    = require("hs.mouse")
local window   = require("hs.window")
local menubar  = require("hs.menubar")
local eventtap = require("hs.eventtap")
local styledtext = require("hs.styledtext")
local drawing  = require("hs.drawing")

local cfg, CONST
local callbacks = {}

-- Snapshot state
local snapshots = {
    windows = {},
    order = {},
    isCreating = false,
    isCreatingStart = 0,
    refreshTimer = nil,
}

-- Layout constants
local PADDING = 8
local GAP = 4
local COLUMN_WIDTH = 140

-- Tooltip state
local tooltipCanvas = nil
local tooltipFadeTimer = nil
local tooltipHideTimer = nil
local tooltipCurrentWinId = nil

-- Refresh state
local refreshCount = 0
local SLOW_REFRESH_INTERVAL = 10

local function log(msg)
    if callbacks.log then callbacks.log(msg) end
end

local function truncateMiddle(input, maxLength)
    if #input <= maxLength then return input end
    local partLen = math.floor(maxLength / 2)
    return input:sub(1, partLen - 2) .. "..." .. input:sub(-partLen)
end

local function getSnapshotSizeForWindow(winFrame)
    local w = COLUMN_WIDTH - PADDING * 2
    if not winFrame or winFrame.w <= 0 or winFrame.h <= 0 then
        return { w = w, h = math.floor(w * 0.66) }
    end
    local aspectRatio = winFrame.w / winFrame.h
    local h = math.floor(w / aspectRatio)
    h = math.max(h, 30)
    h = math.min(h, 200)
    return { w = w, h = h }
end

local function getSnapshotSize()
    return { w = COLUMN_WIDTH - PADDING * 2, h = 80 }
end

local function getReservedArea(scr)
    if #snapshots.order == 0 then return nil end
    local scrId = scr:id()
    local maxHeight = 0
    local hasSnapshots = false

    for _, winId in ipairs(snapshots.order) do
        local data = snapshots.windows[winId]
        if data and data.screenId == scrId then
            hasSnapshots = true
            local snapSize = data.snapSize or getSnapshotSize()
            if snapSize.h > maxHeight then
                maxHeight = snapSize.h
            end
        end
    end

    if not hasSnapshots then return nil end

    local frame = scr:frame()
    local isLandscape = frame.w > frame.h

    if isLandscape then
        return {
            x = frame.x + frame.w - COLUMN_WIDTH,
            y = frame.y,
            w = COLUMN_WIDTH,
            h = frame.h
        }
    else
        local rowHeight = maxHeight + PADDING * 2
        return {
            x = frame.x,
            y = frame.y + frame.h - rowHeight,
            w = frame.w,
            h = rowHeight
        }
    end
end

local function getAdjustedScreenFrame(scr)
    local frame = scr:frame()
    local reserved = getReservedArea(scr)
    if not reserved then return frame end

    local isLandscape = frame.w > frame.h
    if isLandscape then
        return {
            x = frame.x,
            y = frame.y,
            w = frame.w - COLUMN_WIDTH,
            h = frame.h
        }
    else
        return {
            x = frame.x,
            y = frame.y,
            w = frame.w,
            h = frame.h - reserved.h
        }
    end
end

local function removeFromOrder(winId)
    for i, id in ipairs(snapshots.order) do
        if id == winId then
            table.remove(snapshots.order, i)
            return
        end
    end
end

local function cleanupResources(winId)
    local data = snapshots.windows[winId]
    if not data then return end
    if data.dragTap then data.dragTap:stop() end
    if data.canvas then data.canvas:delete() end
    snapshots.windows[winId] = nil
    removeFromOrder(winId)
end

local function updateLayout()
    if #snapshots.order == 0 then return end

    local snapshotsByScreen = {}
    for _, winId in ipairs(snapshots.order) do
        local data = snapshots.windows[winId]
        if data and data.canvas and data.screenId then
            if not snapshotsByScreen[data.screenId] then
                snapshotsByScreen[data.screenId] = {}
            end
            table.insert(snapshotsByScreen[data.screenId], { winId = winId, data = data })
        end
    end

    for _, scr in ipairs(screen.allScreens()) do
        local scrId = scr:id()
        local screenSnapshots = snapshotsByScreen[scrId]
        if screenSnapshots and #screenSnapshots > 0 then
            local frame = scr:frame()
            local isLandscape = frame.w > frame.h

            local currentY = frame.y + PADDING
            local currentX = frame.x + PADDING

            for _, item in ipairs(screenSnapshots) do
                local data = item.data
                local snapSize = data.snapSize or getSnapshotSize()
                local x, y
                if isLandscape then
                    x = frame.x + frame.w - COLUMN_WIDTH + PADDING
                    y = currentY
                    currentY = currentY + snapSize.h + GAP
                else
                    x = currentX
                    y = frame.y + frame.h - snapSize.h - PADDING
                    currentX = currentX + snapSize.w + GAP
                end
                data.canvas:topLeft({ x = x, y = y })
            end
        end
    end
end

local function initTooltip()
    if tooltipCanvas then return end
    tooltipCanvas = canvas.new({ x = 0, y = 0, w = 1, h = 1 })
    tooltipCanvas:level(canvas.windowLevels._MaximumWindowLevelKey)
    tooltipCanvas:appendElements({
        type = "rectangle",
        action = "fill",
        roundedRectRadii = { xRadius = 4, yRadius = 4 },
        fillColor = { white = 0, alpha = 0.75 }
    })
    tooltipCanvas:appendElements({
        type = "text",
        text = "",
        textLineBreak = "wordWrap",
        frame = { x = 0, y = 0, w = "100%", h = "100%" }
    })
    tooltipCanvas:behavior("canJoinAllSpaces")
end

local function showTooltip(winId, snapFrame)
    local data = snapshots.windows[winId]
    if not data or not data.win then return end

    local title = data.win:title() or "Untitled"
    local app = callbacks.safeGetApplication and callbacks.safeGetApplication(data.win)
    local appName = app and app:name() or ""

    local message
    if appName ~= "" and title ~= "" and appName ~= title then
        message = appName .. "\n" .. title
    elseif appName ~= "" then
        message = appName
    else
        message = title
    end

    initTooltip()

    if tooltipFadeTimer then tooltipFadeTimer:stop(); tooltipFadeTimer = nil end
    if tooltipHideTimer then tooltipHideTimer:stop(); tooltipHideTimer = nil end

    local fontSize = 12
    local padding = 8
    local maxWidth = 180

    local lines = {}
    for line in message:gmatch("[^\n]+") do
        table.insert(lines, truncateMiddle(line, 30))
    end
    local truncatedMessage = table.concat(lines, "\n")

    local styledMessage = styledtext.new(truncatedMessage, {
        font = { size = fontSize },
        color = { white = 1, alpha = 1 },
        paragraphStyle = { alignment = "center" },
        shadow = { offset = { h = -1, w = 0 }, blurRadius = 2, color = { alpha = 1 } }
    })

    local textSize = drawing.getTextDrawingSize(styledMessage)
    local tooltipW = math.min(textSize.w, maxWidth) + padding * 2
    local tooltipH = textSize.h + padding

    local tooltipX = snapFrame.x - tooltipW - 8
    local tooltipY = snapFrame.y + (snapFrame.h - tooltipH) / 2

    local scr = screen.mainScreen()
    local scrFrame = scr:frame()

    if tooltipX < scrFrame.x then
        tooltipX = snapFrame.x + snapFrame.w + 8
    end
    if tooltipY < scrFrame.y then tooltipY = scrFrame.y + 4 end
    if tooltipY + tooltipH > scrFrame.y + scrFrame.h then
        tooltipY = scrFrame.y + scrFrame.h - tooltipH - 4
    end

    tooltipCanvas:frame({ x = tooltipX, y = tooltipY, w = tooltipW, h = tooltipH })
    tooltipCanvas:elementAttribute(1, "fillColor", { white = 0, alpha = 0.75 })
    tooltipCanvas:elementAttribute(2, "text", styledMessage)
    tooltipCanvas:alpha(1)
    tooltipCanvas:show()

    tooltipCurrentWinId = winId
end

local function hideTooltip()
    if not tooltipCanvas then return end

    if tooltipFadeTimer then tooltipFadeTimer:stop(); tooltipFadeTimer = nil end

    local fadeOutDuration = 0.125
    local fadeOutStep = 0.025
    local fadeOutAlphaStep = fadeOutStep / fadeOutDuration
    local currentAlpha = tooltipCanvas:alpha()

    local function fade()
        currentAlpha = currentAlpha - fadeOutAlphaStep
        if currentAlpha > 0 then
            tooltipCanvas:alpha(currentAlpha)
            tooltipFadeTimer = timer.doAfter(fadeOutStep, fade)
        else
            tooltipCanvas:hide()
            tooltipFadeTimer = nil
            tooltipCurrentWinId = nil
        end
    end
    fade()
end

local function refreshSnapshots()
    local ok, err = pcall(function()
        if snapshots.isCreating then return end

        local count = 0
        for _ in pairs(snapshots.windows) do count = count + 1 end
        if count == 0 then refreshCount = 0; return end

        refreshCount = refreshCount + 1
        if refreshCount > SLOW_REFRESH_INTERVAL then
            if refreshCount % 10 ~= 0 then return end
        end

        for winId, data in pairs(snapshots.windows) do
            if data and data.canvas then
                local newSnapshot = window.snapshotForID(winId, true)
                if newSnapshot then
                    data.canvas[2].image = newSnapshot
                end
            end
        end
    end)
    if not ok then print("[WindowScape] refreshSnapshots error: " .. tostring(err)) end
end

local restoreFromSnapshot, createSnapshot, showContextMenu

restoreFromSnapshot = function(winId)
    if tooltipCurrentWinId == winId then hideTooltip() end
    local data = snapshots.windows[winId]
    if not data then return end

    local win = data.win
    if not win or not (callbacks.safeGetApplication and callbacks.safeGetApplication(win)) then
        cleanupResources(winId)
        updateLayout()
        return
    end

    local startFrame = data.canvas:frame()
    local targetFrame = data.originalFrame

    local snapshot = win:snapshot()
    if not snapshot then
        win:setFrame(geometry.rect(targetFrame), 0)
        win:focus()
        cleanupResources(winId)
        updateLayout()
        timer.doAfter(0.2, function()
            callbacks.updateWindowOrder()
            callbacks.tileWindows()
            callbacks.updateButtonOverlays()
        end)
        return
    end

    data.canvas:hide()

    local animCanvas = canvas.new(startFrame)
    animCanvas:appendElements({
        type = "image",
        image = snapshot,
        frame = { x = 0, y = 0, w = "100%", h = "100%" },
        imageScaling = "scaleToFit",
    })
    animCanvas:level(canvas.windowLevels.floating)
    animCanvas:show()

    local steps = CONST.ANIMATION_STEPS
    local currentStep = 0
    local animTimer
    animTimer = timer.doEvery(CONST.ANIMATION_INTERVAL, function()
        currentStep = currentStep + 1
        local t = currentStep / steps
        local ease = 1 - math.pow(1 - t, 3)

        local newX = startFrame.x + (targetFrame.x - startFrame.x) * ease
        local newY = startFrame.y + (targetFrame.y - startFrame.y) * ease
        local newW = startFrame.w + (targetFrame.w - startFrame.w) * ease
        local newH = startFrame.h + (targetFrame.h - startFrame.h) * ease

        animCanvas:frame({ x = newX, y = newY, w = newW, h = newH })

        if currentStep >= steps then
            animTimer:stop()
            animCanvas:delete()

            win:setFrame(geometry.rect(targetFrame), 0)
            win:focus()

            cleanupResources(winId)
            updateLayout()

            timer.doAfter(0.2, function()
                callbacks.updateWindowOrder()
                callbacks.tileWindows()
                callbacks.updateButtonOverlays()
            end)
        end
    end)
end

local function clearAll()
    for winId, data in pairs(snapshots.windows) do
        if data.dragTap then data.dragTap:stop() end
        if data.canvas then data.canvas:delete() end
    end
    snapshots.windows = {}
    snapshots.order = {}
end

local function restoreAll()
    local winIds = {}
    for winId, _ in pairs(snapshots.windows) do
        table.insert(winIds, winId)
    end
    for _, winId in ipairs(winIds) do
        restoreFromSnapshot(winId)
    end
end

local function closeAll()
    for winId, data in pairs(snapshots.windows) do
        if data.win and callbacks.safeGetApplication and callbacks.safeGetApplication(data.win) then
            data.win:close()
        end
        if data.dragTap then data.dragTap:stop() end
        if data.canvas then data.canvas:delete() end
    end
    snapshots.windows = {}
    snapshots.order = {}
    updateLayout()
    callbacks.updateWindowOrder()
    callbacks.tileWindows()
    callbacks.updateButtonOverlays()
end

showContextMenu = function(winId, data)
    local menuItems = {
        { title = "Restore", fn = function() restoreFromSnapshot(winId) end },
        { title = "Close", fn = function()
            if data.win and callbacks.safeGetApplication and callbacks.safeGetApplication(data.win) then
                data.win:close()
            end
            cleanupResources(winId)
            updateLayout()
            callbacks.updateWindowOrder()
            callbacks.tileWindows()
        end },
        { title = "-" },
        { title = "Restore All", fn = function() restoreAll() end },
        { title = "Close All", fn = function() closeAll() end },
    }

    local menu = menubar.new(false)
    menu:setMenu(menuItems)
    menu:popupMenu(mouse.absolutePosition(), true)
    timer.doAfter(0.1, function() menu:delete() end)
end

local function isMinimized(winId)
    return snapshots.windows[winId] ~= nil
end

local function getState()
    return snapshots
end

local function startRefreshTimer()
    if snapshots.refreshTimer then return end
    snapshots.refreshTimer = timer.doEvery(0.5, refreshSnapshots)
end

local function init(config, constants, cbs)
    cfg = config
    CONST = constants
    callbacks = cbs or {}
    startRefreshTimer()
end

local function cleanup()
    if snapshots.refreshTimer then
        snapshots.refreshTimer:stop()
        snapshots.refreshTimer = nil
    end
    if tooltipFadeTimer then tooltipFadeTimer:stop() end
    if tooltipHideTimer then tooltipHideTimer:stop() end
    if tooltipCanvas then tooltipCanvas:delete(); tooltipCanvas = nil end
    clearAll()
end

return {
    init = init,
    cleanup = cleanup,
    getState = getState,
    getSnapshotSizeForWindow = getSnapshotSizeForWindow,
    getSnapshotSize = getSnapshotSize,
    getAdjustedScreenFrame = getAdjustedScreenFrame,
    cleanupResources = cleanupResources,
    updateLayout = updateLayout,
    isMinimized = isMinimized,
    showTooltip = showTooltip,
    hideTooltip = hideTooltip,
    restoreFromSnapshot = restoreFromSnapshot,
    clearAll = clearAll,
    showContextMenu = showContextMenu,
    PADDING = PADDING,
    GAP = GAP,
    COLUMN_WIDTH = COLUMN_WIDTH,
}
