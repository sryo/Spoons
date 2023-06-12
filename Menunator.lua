-- This script stops the menu bar from appearing at the top of the screen when you move your mouse there and prevents the Dock from appearing when the mouse is at the bottom edge of the screen.

-- Hide menu bar when the mouse is close to the top of the screen, but only if the currently focused window is fullscreened
ev_top = hs.eventtap.new({hs.eventtap.event.types.mouseMoved}, function(e)
    local win = hs.window.focusedWindow()
    if win and win:isFullScreen() then
        return e:location().y < 4
    else
        return false
    end
end):start()

-- Prevent Dock from appearing when the mouse is close to the bottom of the screen, but only if the currently focused window is fullscreened
ev_bottom = hs.eventtap.new({hs.eventtap.event.types.mouseMoved}, function(e)
    local win = hs.window.focusedWindow()
    local screen_frame = hs.screen.primaryScreen():fullFrame()
    if win and win:isFullScreen() and e:location().y > screen_frame.h - 4 then
        hs.mouse.absolutePosition(hs.geometry.point(screen_frame.h - 4)) -- Yup, produces an error, but works.
    end
end):start()
