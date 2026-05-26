-- Fullscreen UI: button overlays (zoom, minimize, pin, close), their tooltip,
-- and the periodic / debounced / retry-on-AX update loops.

local canvas      = require("hs.canvas")
local timer       = require("hs.timer")
local window      = require("hs.window")
local axuielement = require("hs.axuielement")
local fnutils     = require("hs.fnutils")
local styledtext  = require("hs.styledtext")
local drawing     = require("hs.drawing")
local mouse       = require("hs.mouse")
local screen      = require("hs.screen")

local M = {}

local cfg, callbacks

local OVERLAY_PADDING = 4

-- Lazy require — FrameMaster is loaded after WindowScape in init.lua, so an
-- eager require would race. Mouse callbacks fire long after both are loaded.
local function FM() return require("FrameMaster") end

-- Overlay state — keyed by winId.
M.zoomOverlays     = {}
M.minimizeOverlays = {}
M.pinOverlays      = {}
M.closeOverlays    = {}

local buttonTooltipCanvas = nil
local buttonTooltipTimer  = nil
local overlayUpdateTimer  = nil
local lastRefreshFocusedWinId = nil

local function padRect(rect)
    return {
        x = rect.x - OVERLAY_PADDING,
        y = rect.y - OVERLAY_PADDING,
        w = rect.w + OVERLAY_PADDING * 2,
        h = rect.h + OVERLAY_PADDING * 2,
    }
end

local function clearOverlaySet(set)
    for k, overlay in pairs(set) do
        if overlay then overlay:delete() end
        set[k] = nil
    end
end

-- If `rect` is non-nil, ensure overlayTable[winId] exists and matches rect.
-- If `rect` is nil and we have an old overlay for this winId, delete it.
local function syncOverlay(overlayTable, winId, rect, createFn, win)
    if rect then
        if overlayTable[winId] then
            overlayTable[winId]:frame(padRect(rect))
        else
            local newOverlay = createFn(win)
            if newOverlay then overlayTable[winId] = newOverlay end
        end
    elseif overlayTable[winId] then
        overlayTable[winId]:delete()
        overlayTable[winId] = nil
    end
end

-- Resolve the AX rect for the named button on an already-resolved AX window.
-- Skips buttons that resolve outside the window frame (e.g. Arc's autohiding sidebar).
local function getButtonRectFor(axWin, win, axAttributeName)
    if not axWin then return nil end
    local ok, result = pcall(function()
        local button = axWin:attributeValue(axAttributeName)
        if not button then return nil end
        local pos = button:attributeValue("AXPosition")
        local size = button:attributeValue("AXSize")
        if not (pos and size) then return nil end
        local winFrame = win and win:frame()
        if winFrame then
            local cx = pos.x + size.w / 2
            local cy = pos.y + size.h / 2
            if cx < winFrame.x or cx > winFrame.x + winFrame.w or
               cy < winFrame.y or cy > winFrame.y + winFrame.h then
                return nil
            end
        end
        return { x = pos.x, y = pos.y, w = size.w, h = size.h }
    end)
    return ok and result or nil
end

local function getButtonRect(win, axAttributeName)
    if not win then return nil end
    return getButtonRectFor(axuielement.windowElement(win), win, axAttributeName)
end

function M.getZoomButtonRect(win)     return getButtonRect(win, "AXZoomButton")     end
function M.getMinimizeButtonRect(win) return getButtonRect(win, "AXMinimizeButton") end
function M.getCloseButtonRect(win)    return getButtonRect(win, "AXCloseButton")    end

function M.clearZoomOverlays()     clearOverlaySet(M.zoomOverlays)     end
function M.clearMinimizeOverlays() clearOverlaySet(M.minimizeOverlays) end
function M.clearPinOverlays()      clearOverlaySet(M.pinOverlays)      end
function M.clearCloseOverlays()    clearOverlaySet(M.closeOverlays)    end
function M.clearAllOverlays()
    M.clearZoomOverlays()
    M.clearMinimizeOverlays()
    M.clearPinOverlays()
    M.clearCloseOverlays()
end

function M.showButtonTooltip(text, x, y)
    if buttonTooltipTimer then buttonTooltipTimer:stop(); buttonTooltipTimer = nil end

    if not buttonTooltipCanvas then
        buttonTooltipCanvas = canvas.new({ x = 0, y = 0, w = 1, h = 1 })
        buttonTooltipCanvas:level(canvas.windowLevels._MaximumWindowLevelKey)
        buttonTooltipCanvas:behavior("canJoinAllSpaces")
        buttonTooltipCanvas:appendElements({
            type = "rectangle",
            action = "fill",
            roundedRectRadii = { xRadius = 4, yRadius = 4 },
            fillColor = { white = 0, alpha = 0.75 },
        })
        buttonTooltipCanvas:appendElements({
            type = "text",
            text = "",
            frame = { x = 0, y = 0, w = "100%", h = "100%" },
        })
    end

    local styledMessage = styledtext.new(text, {
        font = { size = 20 },
        color = { white = 1, alpha = 1 },
        shadow = { offset = { h = -1, w = 0 }, blurRadius = 2, color = { alpha = 1 } },
    })

    local textSize = drawing.getTextDrawingSize(styledMessage)
    local tooltipW = textSize.w
    local tooltipH = 24

    local tooltipX = x - tooltipW / 2
    local tooltipY = y + 20

    local scrFrame = (mouse.getCurrentScreen() or screen.mainScreen()):fullFrame()
    local edgeMargin = 8

    if tooltipX < scrFrame.x + edgeMargin then
        tooltipX = scrFrame.x + edgeMargin
    elseif tooltipX + tooltipW > scrFrame.x + scrFrame.w - edgeMargin then
        tooltipX = scrFrame.x + scrFrame.w - edgeMargin - tooltipW
    end

    if tooltipY < scrFrame.y + edgeMargin then
        tooltipY = scrFrame.y + edgeMargin
    elseif tooltipY + tooltipH > scrFrame.y + scrFrame.h - edgeMargin then
        tooltipY = scrFrame.y + scrFrame.h - edgeMargin - tooltipH
    end

    buttonTooltipCanvas:elementAttribute(2, "text", styledMessage)
    buttonTooltipCanvas:frame({ x = tooltipX, y = tooltipY, w = tooltipW, h = tooltipH })
    buttonTooltipCanvas:alpha(1)
    buttonTooltipCanvas:show()
end

function M.hideButtonTooltip()
    if not buttonTooltipCanvas then return end
    if buttonTooltipTimer then buttonTooltipTimer:stop(); buttonTooltipTimer = nil end

    local fadeOutDuration = 0.125
    local fadeOutStep = 0.025
    local fadeOutAlphaStep = fadeOutStep / fadeOutDuration
    local currentAlpha = buttonTooltipCanvas:alpha()

    local function fade()
        currentAlpha = currentAlpha - fadeOutAlphaStep
        if currentAlpha > 0 then
            buttonTooltipCanvas:alpha(currentAlpha)
            buttonTooltipTimer = timer.doAfter(fadeOutStep, fade)
        else
            buttonTooltipCanvas:hide()
            buttonTooltipTimer = nil
        end
    end
    fade()
end

function M.createZoomOverlay(win)
    if not win then return nil end
    local winId = win:id()
    if not winId then return nil end

    local rect = M.getZoomButtonRect(win)
    if not rect then return nil end

    local overlay = canvas.new(padRect(rect))
    overlay:appendElements({
        type = "rectangle",
        action = "fill",
        fillColor = { alpha = 0.01 },
        roundedRectRadii = { xRadius = 5, yRadius = 5 },
    })
    overlay:level(canvas.windowLevels.floating)
    overlay:clickActivating(false)
    overlay:canvasMouseEvents(true, true, true, true)

    overlay:mouseCallback(function(c, msg)
        if msg == "mouseEnter" then
            c:elementAttribute(1, "fillColor", { green = 0.6, alpha = 0.3 })
            local fm = FM()
            fm.showMessage("topRight", fm.messages.topRight(win))
        elseif msg == "mouseExit" then
            c:elementAttribute(1, "fillColor", { alpha = 0.01 })
            FM().hideTooltip()
        elseif msg == "mouseDown" then
            c:elementAttribute(1, "fillColor", { green = 0.8, alpha = 0.5 })
        elseif msg == "mouseUp" then
            FM().hideTooltip()
            local currentWin = window.get(winId)
            if not currentWin then return end

            callbacks.toggleFullscreen(currentWin, winId)
        end
    end)

    overlay:show()
    return overlay
end

function M.createMinimizeOverlay(win)
    if not win then return nil end
    local winId = win:id()
    if not winId then return nil end

    local rect = M.getMinimizeButtonRect(win)
    if not rect then return nil end

    local overlay = canvas.new(padRect(rect))
    overlay:appendElements({
        type = "rectangle",
        action = "fill",
        fillColor = { alpha = 0.01 },
        roundedRectRadii = { xRadius = 5, yRadius = 5 },
    })
    overlay:level(canvas.windowLevels.floating)
    overlay:clickActivating(false)
    overlay:canvasMouseEvents(true, true, true, true)

    overlay:mouseCallback(function(c, msg)
        if msg == "mouseEnter" then
            c:elementAttribute(1, "fillColor", { red = 0.9, green = 0.6, alpha = 0.3 })
            local fm = FM()
            fm.showMessage("bottomRight", fm.messages.bottomRight(win))
        elseif msg == "mouseExit" then
            c:elementAttribute(1, "fillColor", { alpha = 0.01 })
            FM().hideTooltip()
        elseif msg == "mouseDown" then
            c:elementAttribute(1, "fillColor", { red = 0.9, green = 0.6, alpha = 0.5 })
        elseif msg == "mouseUp" then
            FM().hideTooltip()
            callbacks.createSnapshot(win)
        end
    end)

    overlay:show()
    return overlay
end

function M.updatePinOverlayAppearance(overlay, isPinned)
    if not overlay then return end
    local newColor = isPinned
        and { red = 0.9, green = 0.6, blue = 0.1, alpha = 0.9 }
        or { red = 0.3, green = 0.3, blue = 0.3, alpha = 0.6 }
    overlay:elementAttribute(2, "fillColor", newColor)
end

function M.getPinButtonFrame(win)
    if not win then return nil end
    local winFrame = win:frame()
    if not winFrame then return nil end

    local titlebarHeight = 28
    pcall(function()
        local axWin = axuielement.windowElement(win)
        if axWin then
            local closeButton = axWin:attributeValue("AXCloseButton")
            if closeButton then
                local pos = closeButton:attributeValue("AXPosition")
                if pos then
                    titlebarHeight = (pos.y - winFrame.y + 7) * 2
                end
            end
        end
    end)

    local buttonSize = 14
    local buttonMargin = 12

    return {
        x = winFrame.x + winFrame.w - buttonSize - buttonMargin,
        y = winFrame.y + (titlebarHeight - buttonSize) / 2,
        w = buttonSize,
        h = buttonSize,
    }
end

-- Pin button: click toggles the window's app in/out of the tiling exclusion list.
-- Color: orange when the app is currently excluded, gray when included.
function M.createPinOverlay(win)
    if not win then return nil end
    local winId = win:id()
    if not winId then return nil end

    local frame = M.getPinButtonFrame(win)
    if not frame then return nil end

    local app = callbacks.safeGetApplication and callbacks.safeGetApplication(win)
    local isExcluded = app and callbacks.isAppIncluded and not callbacks.isAppIncluded(app, win)

    local overlay = canvas.new(padRect(frame))
    overlay:appendElements({
        type = "rectangle",
        action = "fill",
        fillColor = { alpha = 0.01 },
        roundedRectRadii = { xRadius = 5, yRadius = 5 },
    })
    overlay:appendElements({
        type = "circle",
        action = "fill",
        center = { x = frame.w / 2 + OVERLAY_PADDING, y = frame.h / 2 + OVERLAY_PADDING },
        radius = frame.w / 2 - 1,
        fillColor = isExcluded
            and { red = 0.9, green = 0.6, blue = 0.1, alpha = 0.9 }
            or { red = 0.3, green = 0.3, blue = 0.3, alpha = 0.6 },
    })
    overlay:level(canvas.windowLevels.floating)
    overlay:clickActivating(false)
    overlay:canvasMouseEvents(true, true, true, true)

    overlay:mouseCallback(function(c, msg)
        local cFrame = c:frame()
        local centerX = cFrame.x + cFrame.w / 2
        local centerY = cFrame.y + cFrame.h / 2

        if msg == "mouseEnter" then
            c:elementAttribute(1, "fillColor", { red = 0.9, green = 0.6, blue = 0.1, alpha = 0.2 })
            local currentApp = callbacks.safeGetApplication and callbacks.safeGetApplication(win)
            local currentlyExcluded = currentApp and callbacks.isAppIncluded and not callbacks.isAppIncluded(currentApp, win)
            M.showButtonTooltip(currentlyExcluded and "Include" or "Exclude", centerX, centerY)
        elseif msg == "mouseExit" then
            c:elementAttribute(1, "fillColor", { alpha = 0.01 })
            M.hideButtonTooltip()
        elseif msg == "mouseDown" then
            c:elementAttribute(1, "fillColor", { red = 0.9, green = 0.6, blue = 0.1, alpha = 0.4 })
        elseif msg == "mouseUp" then
            M.hideButtonTooltip()
            callbacks.toggleAppExclusion(winId)
            -- toggleAppExclusion already retiles and updates outlines; refresh overlays after.
            timer.doAfter(0.1, callbacks.updateButtonOverlays)
        end
    end)

    overlay:show()
    return overlay
end

function M.createCloseOverlay(win)
    if not win then return nil end
    local winId = win:id()
    if not winId then return nil end

    local rect = M.getCloseButtonRect(win)
    if not rect then return nil end

    local overlay = canvas.new(padRect(rect))
    overlay:appendElements({
        type = "rectangle",
        action = "fill",
        fillColor = { alpha = 0.01 },
        roundedRectRadii = { xRadius = 5, yRadius = 5 },
    })
    overlay:level(canvas.windowLevels.floating)
    overlay:clickActivating(false)
    overlay:canvasMouseEvents(true, true, true, true)

    overlay:mouseCallback(function(c, msg)
        if msg == "mouseEnter" then
            c:elementAttribute(1, "fillColor", { red = 0.8, alpha = 0.3 })
            local fm = FM()
            fm.showMessage("topLeft", fm.messages.topLeft(win))
        elseif msg == "mouseExit" then
            c:elementAttribute(1, "fillColor", { alpha = 0.01 })
            FM().hideTooltip()
        elseif msg == "mouseDown" then
            c:elementAttribute(1, "fillColor", { red = 0.8, alpha = 0.5 })
        elseif msg == "mouseUp" then
            FM().hideTooltip()
            local currentWin = window.get(winId)
            if currentWin then currentWin:close() end
        end
    end)

    overlay:show()
    return overlay
end

function M.updateButtonOverlays()
    if callbacks.isFullscreenActive() then return end
    if callbacks.isSnapshotsCreating() then return end

    local currentSpace = callbacks.getCurrentSpace and callbacks.getCurrentSpace()
    if not currentSpace then return end

    local activeWinIds = {}
    local allStandardWinIds = {}
    local focusedWin = window.focusedWindow()
    local focusedWinId = focusedWin and focusedWin:id()
    lastRefreshFocusedWinId = focusedWinId

    for _, win in ipairs(window.visibleWindows()) do
        local okSpaces = callbacks.windowSpaces and callbacks.windowSpaces(win)
        local app = callbacks.safeGetApplication and callbacks.safeGetApplication(win)
        local winId = win:id()

        if not winId then goto continue end
        if not okSpaces or not fnutils.contains(okSpaces, currentSpace) then goto continue end
        if win:isFullScreen() then goto continue end

        local isStandard = win:isStandard() and app
        local sz = win:size()
        local isCollapsed = sz and sz.h <= cfg.collapsedWindowHeight
        local axWin -- resolved lazily; one AX rebuild per window, max.

        -- Skip excluded apps (tile but no overlay) and apps whose AX has
        -- measured slow this session (e.g. WhatsApp / other Catalyst).
        local included = app and callbacks.isAppIncluded and callbacks.isAppIncluded(app, win)
        if not included then goto continue end
        if callbacks.isAXSlow and callbacks.isAXSlow(app) then goto continue end

        if isStandard and not isCollapsed and winId == focusedWinId then
            allStandardWinIds[winId] = true

            local pinRect = M.getPinButtonFrame(win)
            if pinRect then
                local pinFrame = padRect(pinRect)
                if M.pinOverlays[winId] then
                    M.pinOverlays[winId]:frame(pinFrame)
                    M.updatePinOverlayAppearance(M.pinOverlays[winId], false)
                else
                    local newOverlay = M.createPinOverlay(win)
                    if newOverlay then
                        M.pinOverlays[winId] = newOverlay
                        M.updatePinOverlayAppearance(newOverlay, false)
                    end
                end
            end
        end

        activeWinIds[winId] = true
        -- Time the WHOLE AX block (windowElement + 3 attribute queries). The
        -- windowElement call alone is cheap; the attribute queries are where
        -- Catalyst apps stall the Lua thread.
        local closeRect, zoomRect, minimizeRect = callbacks.measureAX(app, function()
            axWin = axWin or axuielement.windowElement(win)
            return getButtonRectFor(axWin, win, "AXCloseButton"),
                   getButtonRectFor(axWin, win, "AXZoomButton"),
                   getButtonRectFor(axWin, win, "AXMinimizeButton")
        end)

        syncOverlay(M.closeOverlays,    winId, closeRect,    M.createCloseOverlay,    win)
        syncOverlay(M.zoomOverlays,     winId, zoomRect,     M.createZoomOverlay,     win)
        syncOverlay(M.minimizeOverlays, winId, minimizeRect, M.createMinimizeOverlay, win)

        ::continue::
    end

    -- Drop overlays for windows that are no longer eligible.
    for winId, overlay in pairs(M.closeOverlays) do
        if not activeWinIds[winId] then overlay:delete(); M.closeOverlays[winId] = nil end
    end
    for winId, overlay in pairs(M.zoomOverlays) do
        if not activeWinIds[winId] then overlay:delete(); M.zoomOverlays[winId] = nil end
    end
    for winId, overlay in pairs(M.minimizeOverlays) do
        if not activeWinIds[winId] then overlay:delete(); M.minimizeOverlays[winId] = nil end
    end
    for winId, overlay in pairs(M.pinOverlays) do
        if not allStandardWinIds[winId] then overlay:delete(); M.pinOverlays[winId] = nil end
    end
end

-- Periodic safety-net path: skip the (expensive) full sweep when the focused
-- window hasn't changed since the last refresh. Real window events still call
-- updateButtonOverlays() directly and bypass this short-circuit.
function M.updateButtonOverlaysIfFocusChanged()
    local fw = window.focusedWindow()
    local fid = fw and fw:id()
    if fid == lastRefreshFocusedWinId then return end
    M.updateButtonOverlays()
end

function M.updateButtonOverlaysDebounced()
    if overlayUpdateTimer then overlayUpdateTimer:stop() end
    overlayUpdateTimer = timer.doAfter(0.05, function()
        overlayUpdateTimer = nil
        M.updateButtonOverlays()
    end)
end

-- AX elements need time after a window event to become available; retry a few times.
function M.updateButtonOverlaysWithRetry()
    timer.doAfter(0.1, M.updateButtonOverlays)
    timer.doAfter(0.5, M.updateButtonOverlays)
end

function M.cleanup()
    M.clearAllOverlays()
    if buttonTooltipCanvas then buttonTooltipCanvas:delete(); buttonTooltipCanvas = nil end
    if overlayUpdateTimer then overlayUpdateTimer:stop(); overlayUpdateTimer = nil end
end

function M.init(config, cbs)
    cfg = config
    callbacks = cbs or {}
end

return M
