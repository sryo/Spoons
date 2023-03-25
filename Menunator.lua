-- This script stops the menu bar from appearing at the top of the screen when you move your mouse there.

ev = hs.eventtap.new({hs.eventtap.event.types.mouseMoved}, function(e)
    return e:location().y < 1
end):start()
