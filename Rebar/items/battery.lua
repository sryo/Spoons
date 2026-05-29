return {
    id       = "battery",
    side     = "right",
    order    = 50,
    update   = function()
        local pct = hs.battery.percentage()
        if not pct then return "" end
        local prefix = hs.battery.powerSource() == "AC Power" and "▲ " or ""
        return string.format("%s%d%%", prefix, math.floor(pct + 0.5))
    end,
    interval = 60,
}
