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
local core, snapshots, tiler, animation, fullscreen
local callbacks

function M.init(config, const, deps, cbs)
    cfg        = config
    CONST      = const
    core       = deps.core
    snapshots  = deps.snapshots
    tiler      = deps.tiler
    animation  = deps.animation
    fullscreen = deps.fullscreen
    callbacks  = cbs or {}
end

-- restoreData (optional): used by session restore on hs.reload to rehydrate a
-- previously-minimized window's snapshot without re-running the hide+animate
-- flow. Shape: { originalFrame = {x,y,w,h}, snapSize = {w,h}, screenId = N }.
-- When set: window is assumed already at the off-screen sliver, the animation
-- is skipped, and the retile / focus-previous-window side effects are skipped
-- (the caller drives the post-restore retile pass).
function M.createSnapshot(win, restoreData)
    if not win then return end
    local windowSnapshots = core.snapshotsState
    if not windowSnapshots then return end
    if windowSnapshots.isCreating then return end

    local winId = win:id()
    if not winId then return end
    if windowSnapshots.windows[winId] then return end

    windowSnapshots.isCreating = true
    windowSnapshots.isCreatingStart = timer.secondsSinceEpoch()

    local scr = win:screen() or screen.mainScreen()
    local scrFrame = scr:frame()
    local scrId = restoreData and restoreData.screenId or scr:id()

    local snapshot = win:snapshot()
    if not snapshot and not restoreData then
        windowSnapshots.isCreating = false
        print("[WindowScape] Could not take snapshot of window, aborting minimize")
        return
    end

    local originalFrame = restoreData and restoreData.originalFrame or win:frame()
    local snapSize = restoreData and restoreData.snapSize or snapshots.getSnapshotSizeForWindow(originalFrame)

    windowSnapshots.windows[winId] = {
        win = win,
        canvas = nil,
        originalFrame = originalFrame,
        snapSize = snapSize,
        screenId = scrId,
    }
    table.insert(windowSnapshots.order, winId)

    if not restoreData then
        -- Hide window off-screen immediately so retile reclaims its space before animation.
        -- Anchor with a 1px overlap on the source display so macOS doesn't relocate the
        -- window to a neighboring display (it forcibly relocates fully off-screen frames).
        win:setFrame(
            geometry.rect({
                x = scrFrame.x + scrFrame.w - 1,
                y = scrFrame.y + scrFrame.h - 1,
                w = originalFrame.w,
                h = originalFrame.h,
            }),
            0)

        -- isCreating would normally block tileWindows(), so call the internal pass directly.
        core.updateWindowOrder()
        tiler.tileWindowsInternal()
        callbacks.focusPreviousWindow(winId)

        local newFocused = window.focusedWindow()
        if newFocused and newFocused:id() ~= winId then
            callbacks.drawOutline(newFocused)
        end
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

    local function finishSnapshot()
        local app = core.safeGetApplication(win)
        local bid = app and app:bundleID()
        local appIcon = bid and image.imageFromAppBundle(bid) or nil

        -- Fall back to the app icon when win:snapshot() can't grab the window
        -- (e.g. parked off-screen during a restore). refreshSnapshots replaces
        -- this on its next tick once a real snapshot becomes available.
        local imageForElement = snapshot or appIcon

        local snapshotCanvas = canvas.new({ x = targetX, y = targetY, w = snapSize.w, h = snapSize.h })

        snapshotCanvas:appendElements({
            type = "rectangle",
            action = "fill",
            fillColor = { white = 0.2, alpha = 0.9 },
            roundedRectRadii = { xRadius = 6, yRadius = 6 },
        })

        snapshotCanvas:appendElements({
            type = "image",
            image = imageForElement,
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

        if appIcon then
            local iconSize = 32
            snapshotCanvas:appendElements({
                type = "image",
                image = appIcon,
                frame = { x = (snapSize.w - iconSize) / 2, y = snapSize.h - iconSize - 4, w = iconSize, h = iconSize },
                imageScaling = "scaleToFit",
            })
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

            zoomAnimTimer = timer.doEvery(interval, function()
                local elapsed = timer.secondsSinceEpoch() - startTime
                local t2 = math.min(elapsed / duration, 1)
                local ease2 = animation.easeOutCubic(t2)
                local currentScale = animation.lerp(fromScale, toScale, ease2)

                -- Re-read data.baseX/Y each tick so the strip can scroll
                -- under a zoomed snapshot without the zoom dragging it back.
                local baseX = data.baseX or canv:frame().x
                local baseY = data.baseY or canv:frame().y

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
                    snapshots.showTooltip(winId, snapFrame)
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
                    snapshots.hideTooltip()
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

                snapshots.hideTooltip()

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
                        snapshots.restoreFromSnapshot(winId)
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
                snapshots.hideTooltip()
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
        callbacks.updateButtonOverlaysWithRetry()

        local focused = window.focusedWindow()
        if focused then
            callbacks.drawOutline(focused)
        end

        if not restoreData and core.onLayoutChange then core.onLayoutChange() end
    end

    if restoreData then
        finishSnapshot()
        return
    end

    local winFrame = win:frame()
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
            finishSnapshot()
        end
    end)
end

return M
