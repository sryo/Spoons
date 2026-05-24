-- Snapshot tooltip UI (extracted from WindowScape.lua:569-720).
-- Owns the tooltip canvas + fade timers. The currentWinId is exposed so callers
-- (e.g. snapshot_create.lua) can check whether the tooltip targets a given window.

local canvas = require("hs.canvas")
local screen = require("hs.screen")
local timer  = require("hs.timer")
local drawing = require("hs.drawing")
local styledtext = require("hs.styledtext")

local M = {}

local cfg, callbacks
local tooltipCanvas    = nil
local tooltipFadeTimer = nil
local tooltipHideTimer = nil

M.currentWinId = nil

function M.init(config, cbs)
    cfg = config
    callbacks = cbs or {}
end

function M.truncateMiddle(input, maxLength)
    maxLength = maxLength or 40
    if #input > maxLength then
        local partLen = math.floor(maxLength / 2)
        input = input:sub(1, partLen - 2) .. "..." .. input:sub(-partLen)
    end
    return input
end

local function initCanvas()
    if tooltipCanvas then return end
    tooltipCanvas = canvas.new({ x = 0, y = 0, w = 1, h = 1 })
    tooltipCanvas:level(canvas.windowLevels._MaximumWindowLevelKey)
    tooltipCanvas:appendElements({
        type = "rectangle",
        action = "fill",
        roundedRectRadii = { xRadius = 4, yRadius = 4 },
        fillColor = { white = 0, alpha = 0.75 },
    })
    tooltipCanvas:appendElements({
        type = "text",
        text = "",
        textLineBreak = "wordWrap",
        frame = { x = 0, y = 0, w = "100%", h = "100%" },
    })
    tooltipCanvas:behavior("canJoinAllSpaces")
end

function M.show(winId, snapFrame)
    local snapshotsState = callbacks.getSnapshotsState and callbacks.getSnapshotsState()
    if not snapshotsState then return end

    local data = snapshotsState.windows[winId]
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

    initCanvas()

    if tooltipFadeTimer then tooltipFadeTimer:stop(); tooltipFadeTimer = nil end
    if tooltipHideTimer then tooltipHideTimer:stop(); tooltipHideTimer = nil end

    local fontSize = 12
    local padding = 8
    local maxWidth = 180

    local lines = {}
    for line in message:gmatch("[^\n]+") do
        if #line > 30 then line = line:sub(1, 27) .. "..." end
        table.insert(lines, line)
    end
    local truncated = table.concat(lines, "\n")

    local styled = styledtext.new(truncated, {
        font = { size = fontSize },
        color = { white = 1, alpha = 1 },
        paragraphStyle = { alignment = "center" },
        shadow = {
            offset = { h = -1, w = 0 },
            blurRadius = 2,
            color = { alpha = 1 },
        },
    })

    local textSize = drawing.getTextDrawingSize(styled)
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
    tooltipCanvas:elementAttribute(2, "text", styled)
    tooltipCanvas:alpha(1)
    tooltipCanvas:show()

    M.currentWinId = winId
end

function M.hide()
    if not tooltipCanvas then return end

    if tooltipFadeTimer then tooltipFadeTimer:stop(); tooltipFadeTimer = nil end

    local fadeDuration = 0.125
    local fadeStep = 0.025
    local alphaStep = fadeStep / fadeDuration
    local currentAlpha = tooltipCanvas:alpha()

    local function fade()
        currentAlpha = currentAlpha - alphaStep
        if currentAlpha > 0 then
            tooltipCanvas:alpha(currentAlpha)
            tooltipFadeTimer = timer.doAfter(fadeStep, fade)
        else
            tooltipCanvas:hide()
            tooltipFadeTimer = nil
            M.currentWinId = nil
        end
    end

    fade()
end

function M.cleanup()
    if tooltipFadeTimer then tooltipFadeTimer:stop(); tooltipFadeTimer = nil end
    if tooltipHideTimer then tooltipHideTimer:stop(); tooltipHideTimer = nil end
    if tooltipCanvas then tooltipCanvas:delete(); tooltipCanvas = nil end
    M.currentWinId = nil
end

return M
