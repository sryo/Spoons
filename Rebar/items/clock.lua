-- Bind LC_TIME to the user's locale so weekday/month abbreviations match
-- the rest of the system (otherwise Lua defaults to the C locale -> English).
pcall(os.setlocale, "", "time")

return {
    id       = "clock",
    side     = "right",
    order    = 90,
    update   = function() return os.date("%a %b %d  %H:%M") end,
    interval = 30,
    onClick  = "open /System/Applications/Calendar.app",
}
