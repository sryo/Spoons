-- Snapshot creation: animates a window into the thumbnail sidebar and wires
-- the resulting canvas's mouse callbacks (hover tooltip, drag-to-reposition,
-- click-to-restore, right-click context menu, top-left X to close).

local canvas   = require("hs.canvas")
local geometry = require("hs.geometry")
local screen   = require("hs.screen")
local mouse    = require("hs.mouse")
local eventtap = require("hs.eventtap")
local timer    = require("hs.timer")
local window   = require("hs.window")
local image    = require("hs.image")

local M = {}

local cfg, CONST
local core, snapshots, snapshotUI, tiler, animation, fullscreen
local callbacks

function M.init(config, const, deps, cbs)
    cfg        = config
    CONST      = const
    core       = deps.core
    snapshots  = deps.snapshots
    snapshotUI = deps.snapshotUI
    tiler      = deps.tiler
    animation  = deps.animation
    fullscreen = deps.fullscreen
    callbacks  = cbs or {}
end

function M.createSnapshot(win)
    if not win then return end
    local windowSnapshots = core.snapshotsState
    if not windowSnapshots then return end
    if windowSnapshots.isCreating then return end

    local winId = win:id()
    if not winId then return end
    if windowSnapshots.windows[winId] then return end

    windowSnapshots.isCreating = true
    windowSnapshots.isCreatingStart = timer.secondsSinceEpoch()

    local winFrame = win:frame()
    local scr = win:screen() or screen.mainScreen()
    local scrFrame = scr:frame()
    local scrId = scr:id()

    local snapshot = win:snapshot()
    if not snapshot then
        windowSnapshots.isCreating = false
        print("[WindowScape] Could not take snapshot of window, aborting minimize")
        return
    end

    local snapSize = snapshots.getSnapshotSizeForWindow(winFrame)

    windowSnapshots.windows[winId] = {
        win = win,
        canvas = nil,
        originalFrame = winFrame,
        snapSize = snapSize,
        screenId = scrId,
    }
    table.insert(windowSnapshots.order, winId)

    -- Hide window off-screen immediately so retile reclaims its space before animation.
    win:setFrame(
        geometry.rect({
            x = scrFrame.x + scrFrame.w + 100,
            y = scrFrame.y + scrFrame.h + 100,
            w = winFrame.w,
            h = winFrame.h,
        }),
        0)

    -- isCreating would normally block tileWindows(), so call the internal pass directly.
    core.updateWindowOrder()
    tiler.tileWindowsInternal()
    if callbacks.focusPreviousWindow then
        callbacks.focusPreviousWindow(winId)
    end

    local newFocused = window.focusedWindow()
    if newFocused and newFocused:id() ~= winId and callbacks.drawOutline then
        callbacks.drawOutline(newFocused)
    end

    local isLandscape = scrFrame.w > scrFrame.h
    local snapshotColumnWidth = snapshots.COLUMN_WIDTH
    local snapshotPadding     = snapshots.PADDING
    local snapshotGap         = snapshots.GAP

    local targetX, targetY
    if isLandscape then
        targetX = scrFrame.x + scrFrame.w - snapshotColumnWidth + snapshotPadding
        targetY = scrFrame.y + snapshotPadding
        for _, existingWinId in ipairs(windowSnapshots.order) do
            if existingWinId ~= winId then
                local data = windowSnapshots.windows[existingWinId]
                if data and data.snapSize and data.screenId == scrId then
                    targetY = targetY + data.snapSize.h + snapshotGap
                end
            end
        end
    else
        targetY = scrFrame.y + scrFrame.h - snapSize.h - snapshotPadding
        targetX = scrFrame.x + snapshotPadding
        for _, existingWinId in ipairs(windowSnapshots.order) do
            if existingWinId ~= winId then
                local data = windowSnapshots.windows[existingWinId]
                if data and data.snapSize and data.screenId == scrId then
                    targetX = targetX + data.snapSize.w + snapshotGap
                end
            end
        end
    end

    local animCanvas = canvas.new(winFrame)
    animCanvas:appendElements({
        type = "image",
        image = snapshot,
        frame = { x = 0, y = 0, w = "100%", h = "100%" },
        imageScaling = "scaleProportionally",
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

        local newX = winFrame.x + (targetX - winFrame.x) * ease
        local newY = winFrame.y + (targetY - winFrame.y) * ease
        local newW = winFrame.w + (snapSize.w - winFrame.w) * ease
        local newH = winFrame.h + (snapSize.h - winFrame.h) * ease

        animCanvas:frame({ x = newX, y = newY, w = newW, h = newH })

        if currentStep >= steps then
            animTimer:stop()
            animCanvas:delete()

            local snapshotCanvas = canvas.new({ x = targetX, y = targetY, w = snapSize.w, h = snapSize.h })

            snapshotCanvas:appendElements({
                type = "rectangle",
                action = "fill",
                fillColor = { white = 0.2, alpha = 0.9 },
                roundedRectRadii = { xRadius = 6, yRadius = 6 },
            })

            snapshotCanvas:appendElements({
                type = "image",
                image = snapshot,
                frame = { x = 2, y = 2, w = snapSize.w - 4, h = snapSize.h - 4 },
                imageScaling = "scaleProportionally",
            })

            snapshotCanvas:appendElements({
                type = "circle",
                action = "fill",
                center = { x = 10, y = 10 },
                radius = 6,
                fillColor = { red = 0.8, green = 0.2, blue = 0.2, alpha = 0.8 },
            })

            local app = core.safeGetApplication(win)
            if app then
                local appIcon = app:bundleID() and image.imageFromAppBundle(app:bundleID())
                if appIcon then
                    local iconSize = 32
                    snapshotCanvas:appendElements({
                        type = "image",
                        image = appIcon,
                        frame = { x = (snapSize.w - iconSize) / 2, y = snapSize.h - iconSize - 4, w = iconSize, h = iconSize },
                        imageScaling = "scaleToFit",
                    })
                end
            end

            snapshotCanvas:level(canvas.windowLevels.floating)
            snapshotCanvas:clickActivating(false)
            snapshotCanvas:canvasMouseEvents(true, true, true, true)

            local zoomScale = CONST.SNAPSHOT_ZOOM_SCALE
            local isZoomed = false
            local zoomAnimTimer = nil

            local function animateZoom(canv, fromScale, toScale, duration)
                if zoomAnimTimer then zoomAnimTimer:stop() end

                local startTime = timer.secondsSinceEpoch()
                local fps = 60
                local interval = 1 / fps
                local data = windowSnapshots.windows[winId]
                if not data then return end

                local baseX = data.baseX or canv:frame().x
                local baseY = data.baseY or canv:frame().y

                zoomAnimTimer = timer.doEvery(interval, function()
                    local elapsed = timer.secondsSinceEpoch() - startTime
                    local t2 = math.min(elapsed / duration, 1)
                    local ease2 = animation.easeOutCubic(t2)
                    local currentScale = animation.lerp(fromScale, toScale, ease2)

                    local newW2 = data.snapSize.w * currentScale
                    local newH2 = data.snapSize.h * currentScale
                    local offsetX = (data.snapSize.w - newW2) / 2
                    local offsetY = (data.snapSize.h - newH2) / 2

                    canv:frame({
                        x = baseX + offsetX,
                        y = baseY + offsetY,
                        w = newW2,
                        h = newH2,
                    })

                    canv:transformation(hs.canvas.matrix.scale(currentScale))

                    if t2 >= 1 then
                        zoomAnimTimer:stop()
                        zoomAnimTimer = nil
                    end
                end)
            end

            local isDragging = false
            local dragStartMousePos = nil
            local dragStartCanvasFrame = nil
            local dragThreshold = CONST.SNAPSHOT_DRAG_THRESHOLD

            snapshotCanvas:mouseCallback(function(c, msg, _id, x, y)
                if msg == "mouseEnter" then
                    if not isDragging then
                        local snapFrame = c:frame()
                        snapshotUI.show(winId, snapFrame)
                        if not isZoomed then
                            isZoomed = true
                            local data = windowSnapshots.windows[winId]
                            if data then
                                local currentFrame = c:frame()
                                data.baseX = currentFrame.x
                                data.baseY = currentFrame.y
                                animateZoom(c, 1.0, zoomScale, 0.1)
                            end
                        end
                    end
                elseif msg == "mouseExit" then
                    if not isDragging then
                        snapshotUI.hide()
                        if isZoomed then
                            isZoomed = false
                            animateZoom(c, zoomScale, 1.0, 0.1)
                        end
                    end
                elseif msg == "mouseDown" then
                    local buttons = mouse.getButtons()
                    if buttons.right then
                        snapshots.showContextMenu(winId, windowSnapshots.windows[winId])
                        return
                    end
                    dragStartMousePos = mouse.absolutePosition()
                    dragStartCanvasFrame = c:frame()
                    isDragging = false
                elseif msg == "mouseUp" then
                    local wasDragging = isDragging
                    isDragging = false
                    dragStartMousePos = nil
                    dragStartCanvasFrame = nil

                    snapshotUI.hide()

                    if wasDragging then
                        local canvasFrame = c:frame()
                        local centerX = canvasFrame.x + canvasFrame.w / 2
                        local centerY = canvasFrame.y + canvasFrame.h / 2

                        local targetScreen = nil
                        for _, scr2 in ipairs(screen.allScreens()) do
                            local sf = scr2:frame()
                            if centerX >= sf.x and centerX < sf.x + sf.w and
                               centerY >= sf.y and centerY < sf.y + sf.h then
                                targetScreen = scr2
                                break
                            end
                        end

                        local data = windowSnapshots.windows[winId]
                        if data and targetScreen then
                            local newScreenId = targetScreen:id()
                            if data.screenId ~= newScreenId then
                                data.screenId = newScreenId
                                local newScreenFrame = targetScreen:frame()
                                data.originalFrame = {
                                    x = newScreenFrame.x + (newScreenFrame.w - data.originalFrame.w) / 2,
                                    y = newScreenFrame.y + (newScreenFrame.h - data.originalFrame.h) / 2,
                                    w = data.originalFrame.w,
                                    h = data.originalFrame.h,
                                }
                            end
                        end

                        snapshots.updateLayout()
                        tiler.tileWindows()
                    else
                        local buttons = mouse.getButtons()
                        if buttons.right then return end

                        if x < CONST.SNAPSHOT_CLOSE_SIZE and y < CONST.SNAPSHOT_CLOSE_SIZE then
                            if win and core.safeGetApplication(win) then
                                win:close()
                            end
                            snapshots.cleanupResources(winId)
                            snapshots.updateLayout()
                            core.updateWindowOrder()
                            tiler.tileWindows()
                        else
                            if callbacks.restoreFromSnapshot then
                                callbacks.restoreFromSnapshot(winId)
                            else
                                snapshots.restoreFromSnapshot(winId)
                            end
                        end
                    end
                end
            end)

            -- Canvas doesn't get mouseDragged reliably, so we mirror drags via an eventtap.
            local dragTap = eventtap.new({ eventtap.event.types.leftMouseDragged }, function(_)
                if not dragStartMousePos or not dragStartCanvasFrame then return false end

                local currentPos = mouse.absolutePosition()
                local dx = currentPos.x - dragStartMousePos.x
                local dy = currentPos.y - dragStartMousePos.y

                if not isDragging and (math.abs(dx) > dragThreshold or math.abs(dy) > dragThreshold) then
                    isDragging = true
                    if isZoomed then
                        isZoomed = false
                        if zoomAnimTimer then
                            zoomAnimTimer:stop()
                            zoomAnimTimer = nil
                        end
                        local data = windowSnapshots.windows[winId]
                        if data then
                            snapshotCanvas:frame({
                                x = dragStartCanvasFrame.x,
                                y = dragStartCanvasFrame.y,
                                w = data.snapSize.w,
                                h = data.snapSize.h,
                            })
                            snapshotCanvas:transformation(hs.canvas.matrix.identity())
                        end
                    end
                    snapshotUI.hide()
                end

                if isDragging then
                    local data = windowSnapshots.windows[winId]
                    if data then
                        snapshotCanvas:topLeft({
                            x = dragStartCanvasFrame.x + dx,
                            y = dragStartCanvasFrame.y + dy,
                        })
                    end
                end

                return false
            end)

            dragTap:start()

            snapshotCanvas:show()

            if windowSnapshots.windows[winId] then
                windowSnapshots.windows[winId].canvas = snapshotCanvas
                windowSnapshots.windows[winId].dragTap = dragTap
            end

            windowSnapshots.isCreating = false

            snapshots.updateLayout()
            if callbacks.updateButtonOverlaysWithRetry then
                callbacks.updateButtonOverlaysWithRetry()
            end

            local focused = window.focusedWindow()
            if focused and callbacks.drawOutline then
                callbacks.drawOutline(focused)
            end
        end
    end)
end

return M
