-- Fullscreen UI: button overlays (zoom, minimize, pin, close), their tooltip,
-- and the periodic / debounced / retry-on-AX update loops.
-- Extracted from WindowScape/fullscreen.lua.

local canvas      = require("hs.canvas")
local timer       = require("hs.timer")
local window      = require("hs.window")
local axuielement = require("hs.axuielement")
local fnutils     = require("hs.fnutils")

local M = {}

local cfg, callbacks

-- Overlay state — keyed by winId.
M.zoomOverlays     = {}
M.minimizeOverlays = {}
M.pinOverlays      = {}
M.closeOverlays    = {}

local buttonTooltipCanvas = nil
local buttonTooltipTimer  = nil
local overlayUpdateTimer  = nil

local function log(msg)
    if callbacks.log then callbacks.log(msg) end
end

-- AX-driven button rect. Skips buttons that resolve outside the window frame
-- (e.g. inside Arc's autohiding sidebar).
local function getButtonRect(win, axAttributeName)
    if not win then return nil end
    local ok, result = pcall(function()
        local axWin = axuielement.windowElement(win)
        if not axWin then return nil end
        local button = axWin:attributeValue(axAttributeName)
        if not button then return nil end
        local pos = button:attributeValue("AXPosition")
        local size = button:attributeValue("AXSize")
        if not (pos and size) then return nil end
        local winFrame = win:frame()
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

function M.getZoomButtonRect(win)     return getButtonRect(win, "AXZoomButton")     end
function M.getMinimizeButtonRect(win) return getButtonRect(win, "AXMinimizeButton") end
function M.getCloseButtonRect(win)    return getButtonRect(win, "AXCloseButton")    end

function M.clearZoomOverlays()
    for _, overlay in pairs(M.zoomOverlays) do if overlay then overlay:delete() end end
    M.zoomOverlays = {}
end
function M.clearMinimizeOverlays()
    for _, overlay in pairs(M.minimizeOverlays) do if overlay then overlay:delete() end end
    M.minimizeOverlays = {}
end
function M.clearPinOverlays()
    for _, overlay in pairs(M.pinOverlays) do if overlay then overlay:delete() end end
    M.pinOverlays = {}
end
function M.clearCloseOverlays()
    for _, overlay in pairs(M.closeOverlays) do if overlay then overlay:delete() end end
    M.closeOverlays = {}
end
function M.clearAllOverlays()
    M.clearZoomOverlays()
    M.clearMinimizeOverlays()
    M.clearPinOverlays()
    M.clearCloseOverlays()
end

function M.showButtonTooltip(text, x, y)
    if buttonTooltipTimer then buttonTooltipTimer:stop(); buttonTooltipTimer = nil end

    if not buttonTooltipCanvas then
        buttonTooltipCanvas = canvas.new({ x = 0, y = 0, w = 100, h = 24 })
        buttonTooltipCanvas:level(canvas.windowLevels._MaximumWindowLevelKey)
        buttonTooltipCanvas:appendElements({
            type = "rectangle",
            action = "fill",
            roundedRectRadii = { xRadius = 4, yRadius = 4 },
            fillColor = { white = 0, alpha = 0.8 },
        })
        buttonTooltipCanvas:appendElements({
            type = "text",
            text = "",
            textAlignment = "center",
            textColor = { white = 1 },
            textSize = 12,
            frame = { x = 0, y = 4, w = "100%", h = "100%" },
        })
    end

    local padding = 8
    local tooltipW = math.max(#text * 7 + padding * 2, 60)
    local tooltipH = 24

    buttonTooltipCanvas:elementAttribute(2, "text", text)
    buttonTooltipCanvas:frame({ x = x - tooltipW / 2, y = y + 20, w = tooltipW, h = tooltipH })
    buttonTooltipCanvas:alpha(1)
    buttonTooltipCanvas:show()
end

function M.hideButtonTooltip()
    if buttonTooltipCanvas then buttonTooltipCanvas:hide() end
    if buttonTooltipTimer then buttonTooltipTimer:stop(); buttonTooltipTimer = nil end
end

function M.createZoomOverlay(win)
    if not win then return nil end
    local winId = win:id()
    if not winId then return nil end

    local rect = M.getZoomButtonRect(win)
    if not rect then return nil end

    local padding = 4
    local overlay = canvas.new({
        x = rect.x - padding, y = rect.y - padding,
        w = rect.w + padding * 2, h = rect.h + padding * 2,
    })
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
        local frame = c:frame()
        local centerX = frame.x + frame.w / 2
        local centerY = frame.y + frame.h / 2

        if msg == "mouseEnter" then
            c:elementAttribute(1, "fillColor", { green = 0.6, alpha = 0.3 })
            M.showButtonTooltip("Fullscreen", centerX, centerY)
        elseif msg == "mouseExit" then
            c:elementAttribute(1, "fillColor", { alpha = 0.01 })
            M.hideButtonTooltip()
        elseif msg == "mouseDown" then
            c:elementAttribute(1, "fillColor", { green = 0.8, alpha = 0.5 })
        elseif msg == "mouseUp" then
            M.hideButtonTooltip()
            local currentWin = window.get(winId)
            if not currentWin then return end

            if callbacks.toggleFullscreen then
                callbacks.toggleFullscreen(currentWin, winId)
            end
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

    local padding = 4
    local overlay = canvas.new({
        x = rect.x - padding, y = rect.y - padding,
        w = rect.w + padding * 2, h = rect.h + padding * 2,
    })
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
        local frame = c:frame()
        local centerX = frame.x + frame.w / 2
        local centerY = frame.y + frame.h / 2

        if msg == "mouseEnter" then
            c:elementAttribute(1, "fillColor", { red = 0.9, green = 0.6, alpha = 0.3 })
            M.showButtonTooltip("Minimize", centerX, centerY)
        elseif msg == "mouseExit" then
            c:elementAttribute(1, "fillColor", { alpha = 0.01 })
            M.hideButtonTooltip()
        elseif msg == "mouseDown" then
            c:elementAttribute(1, "fillColor", { red = 0.9, green = 0.6, alpha = 0.5 })
        elseif msg == "mouseUp" then
            M.hideButtonTooltip()
            if callbacks.createSnapshot then callbacks.createSnapshot(win) end
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

function M.createPinOverlay(win)
    if not win then return nil end
    local winId = win:id()
    if not winId then return nil end

    local frame = M.getPinButtonFrame(win)
    if not frame then return nil end

    local padding = 4
    local isPinned = callbacks.isPseudoWindow and callbacks.isPseudoWindow(winId) or false

    local overlay = canvas.new({
        x = frame.x - padding, y = frame.y - padding,
        w = frame.w + padding * 2, h = frame.h + padding * 2,
    })
    overlay:appendElements({
        type = "rectangle",
        action = "fill",
        fillColor = { alpha = 0.01 },
        roundedRectRadii = { xRadius = 5, yRadius = 5 },
    })
    overlay:appendElements({
        type = "circle",
        action = "fill",
        center = { x = frame.w / 2 + padding, y = frame.h / 2 + padding },
        radius = frame.w / 2 - 1,
        fillColor = isPinned
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
            local currentPinned = callbacks.isPseudoWindow and callbacks.isPseudoWindow(winId) or false
            M.showButtonTooltip(currentPinned and "Unpin" or "Pin", centerX, centerY)
        elseif msg == "mouseExit" then
            c:elementAttribute(1, "fillColor", { alpha = 0.01 })
            M.hideButtonTooltip()
        elseif msg == "mouseDown" then
            c:elementAttribute(1, "fillColor", { red = 0.9, green = 0.6, blue = 0.1, alpha = 0.4 })
        elseif msg == "mouseUp" then
            M.hideButtonTooltip()
            if callbacks.togglePseudoWindow then callbacks.togglePseudoWindow(winId) end
            local newPinned = callbacks.isPseudoWindow and callbacks.isPseudoWindow(winId) or false
            M.updatePinOverlayAppearance(c, newPinned)
            if callbacks.tileWindows then callbacks.tileWindows() end
            if callbacks.updateButtonOverlays then
                timer.doAfter(0.1, callbacks.updateButtonOverlays)
            end
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

    local padding = 4
    local overlay = canvas.new({
        x = rect.x - padding, y = rect.y - padding,
        w = rect.w + padding * 2, h = rect.h + padding * 2,
    })
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
        local frame = c:frame()
        local centerX = frame.x + frame.w / 2
        local centerY = frame.y + frame.h / 2

        if msg == "mouseEnter" then
            c:elementAttribute(1, "fillColor", { red = 0.8, alpha = 0.3 })
            M.showButtonTooltip("Close", centerX, centerY)
        elseif msg == "mouseExit" then
            c:elementAttribute(1, "fillColor", { alpha = 0.01 })
            M.hideButtonTooltip()
        elseif msg == "mouseDown" then
            c:elementAttribute(1, "fillColor", { red = 0.8, alpha = 0.5 })
        elseif msg == "mouseUp" then
            M.hideButtonTooltip()
            local currentWin = window.get(winId)
            if currentWin then currentWin:close() end
        end
    end)

    overlay:show()
    return overlay
end

function M.updateButtonOverlays()
    if callbacks.isFullscreenActive and callbacks.isFullscreenActive() then return end
    if callbacks.isSnapshotsCreating and callbacks.isSnapshotsCreating() then return end

    local currentSpace = callbacks.getCurrentSpace and callbacks.getCurrentSpace()
    if not currentSpace then return end

    local activeWinIds = {}
    local allStandardWinIds = {}
    local focusedWin = window.focusedWindow()
    local focusedWinId = focusedWin and focusedWin:id()

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

        if isStandard and not isCollapsed and winId == focusedWinId then
            allStandardWinIds[winId] = true

            local pinRect = M.getPinButtonFrame(win)
            if pinRect then
                local isExcluded = app and callbacks.isAppIncluded and not callbacks.isAppIncluded(app, win)
                local padding = 4
                local pinFrame = {
                    x = pinRect.x - padding, y = pinRect.y - padding,
                    w = pinRect.w + padding * 2, h = pinRect.h + padding * 2,
                }
                if M.pinOverlays[winId] then
                    M.pinOverlays[winId]:frame(pinFrame)
                    M.updatePinOverlayAppearance(M.pinOverlays[winId], isExcluded)
                else
                    local newOverlay = M.createPinOverlay(win)
                    if newOverlay then
                        M.pinOverlays[winId] = newOverlay
                        M.updatePinOverlayAppearance(newOverlay, isExcluded)
                    end
                end
            end
        end

        if app and callbacks.isAppIncluded and callbacks.isAppIncluded(app, win) then
            activeWinIds[winId] = true

            local closeRect    = M.getCloseButtonRect(win)
            local zoomRect     = M.getZoomButtonRect(win)
            local minimizeRect = M.getMinimizeButtonRect(win)

            if closeRect then
                local padding = 4
                local newFrame = {
                    x = closeRect.x - padding, y = closeRect.y - padding,
                    w = closeRect.w + padding * 2, h = closeRect.h + padding * 2,
                }
                if M.closeOverlays[winId] then
                    M.closeOverlays[winId]:frame(newFrame)
                else
                    local newOverlay = M.createCloseOverlay(win)
                    if newOverlay then M.closeOverlays[winId] = newOverlay end
                end
            elseif M.closeOverlays[winId] then
                M.closeOverlays[winId]:delete()
                M.closeOverlays[winId] = nil
            end

            if zoomRect then
                local padding = 4
                local newFrame = {
                    x = zoomRect.x - padding, y = zoomRect.y - padding,
                    w = zoomRect.w + padding * 2, h = zoomRect.h + padding * 2,
                }
                if M.zoomOverlays[winId] then
                    M.zoomOverlays[winId]:frame(newFrame)
                else
                    local newOverlay = M.createZoomOverlay(win)
                    if newOverlay then M.zoomOverlays[winId] = newOverlay end
                end
            elseif M.zoomOverlays[winId] then
                M.zoomOverlays[winId]:delete()
                M.zoomOverlays[winId] = nil
            end

            if minimizeRect then
                local padding = 4
                local newFrame = {
                    x = minimizeRect.x - padding, y = minimizeRect.y - padding,
                    w = minimizeRect.w + padding * 2, h = minimizeRect.h + padding * 2,
                }
                if M.minimizeOverlays[winId] then
                    M.minimizeOverlays[winId]:frame(newFrame)
                else
                    local newOverlay = M.createMinimizeOverlay(win)
                    if newOverlay then M.minimizeOverlays[winId] = newOverlay end
                end
            elseif M.minimizeOverlays[winId] then
                M.minimizeOverlays[winId]:delete()
                M.minimizeOverlays[winId] = nil
            end
        end

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
    timer.doAfter(0.3, M.updateButtonOverlays)
    timer.doAfter(0.6, M.updateButtonOverlays)
    timer.doAfter(1.0, M.updateButtonOverlays)
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
