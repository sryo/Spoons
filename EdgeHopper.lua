-- Wrap the mouse cursor when it moves off the edge of the screen
mouseTunnelHandler = hs.eventtap.new({hs.eventtap.event.types.mouseMoved}, function(e)
    local currentLoc = e:location()
    local screen_frame = hs.screen.primaryScreen():fullFrame()

    -- Wrap horizontally
    if currentLoc.x <= 1 then
        hs.mouse.setAbsolutePosition(hs.geometry.point(screen_frame.w - 5, currentLoc.y))
    elseif currentLoc.x >= screen_frame.w - 1 then
        hs.mouse.setAbsolutePosition(hs.geometry.point(5, currentLoc.y))
    end

    -- Wrap vertically
    if currentLoc.y <= 1 then
        hs.mouse.setAbsolutePosition(hs.geometry.point(currentLoc.x, screen_frame.h - 5))
    elseif currentLoc.y >= screen_frame.h - 1 then
        hs.mouse.setAbsolutePosition(hs.geometry.point(currentLoc.x, 5))
    end

    -- By default, do not consume the event
    return false
end):start()

-- Refresh the mouseTunnelHandler whenever screen layout changes
mouseTunnelScreenWatcher = hs.screen.watcher.new(function()
    mouseTunnelHandler:stop()
    mouseTunnelHandler:start()
end):start()
