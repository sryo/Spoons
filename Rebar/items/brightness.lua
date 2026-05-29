-- hs.screen has no brightness change event, so this polls.

return {
    id        = "brightness",
    side      = "right",
    order     = 75,
    perScreen = true,
    interval  = 0.5,
    update    = function(scr)
        local b = scr:getBrightness()
        if not b then return "" end
        return string.format("☀ %d%%", math.floor(b * 100 + 0.5))
    end,
}
