-- Local weather via wttr.in. Format: "+17°C ☁" (temperature + condition glyph).
-- 10min poll; click opens the Weather app.

return {
    id             = "weather",
    side           = "center-right",
    order          = 60,
    defaultEnabled = false,
    command        = [[curl -s --max-time 5 "wttr.in/?format=%t+%c" 2>/dev/null | tr -d '\n']],
    interval       = 600,
    onClick        = "open -a Weather",
}
