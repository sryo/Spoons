-- Time-until-next-rain glance via wttr.in's j1 JSON forecast. Scans the 3-day
-- hourly forecast for the first slot with chanceofrain >= threshold and
-- displays the lead time. Hides itself when no rain is in the window.

local M = {
    id             = "rain",
    side           = "left",
    order          = 45,
    interval       = 0,
    defaultEnabled = false,
    onClick        = "open -a Weather",
}

local RAIN_THRESHOLD_PCT = 50
local POLL_INTERVAL_S    = 1800

local pollTimer
local lastValue = ""

local function formatLead(hoursAhead)
    if hoursAhead < 1 then return "☔ now" end
    if hoursAhead < 24 then return "☔ " .. math.floor(hoursAhead + 0.5) .. "h" end
    local days = math.floor(hoursAhead / 24 + 0.5)
    return "☔ " .. days .. "d"
end

local function nextRain(j)
    if not j or not j.weather then return nil end
    local now = os.time()
    for _, day in ipairs(j.weather) do
        local Y, Mo, D = (day.date or ""):match("(%d+)-(%d+)-(%d+)")
        if Y then
            for _, h in ipairs(day.hourly or {}) do
                local n = tonumber(h.time) or 0
                local slotTime = os.time({
                    year = tonumber(Y), month = tonumber(Mo), day = tonumber(D),
                    hour = math.floor(n / 100), min = n % 100, sec = 0,
                })
                local chance = tonumber(h.chanceofrain) or 0
                if slotTime >= now and chance >= RAIN_THRESHOLD_PCT then
                    return (slotTime - now) / 3600
                end
            end
        end
    end
    return nil
end

local function poll(refresh)
    -- wttr.in serves JSON to curl-ish user-agents and HTML to browsers.
    hs.http.asyncGet("https://wttr.in/?format=j1",
        { ["User-Agent"] = "curl/8.0" },
        function(status, body)
            if status ~= 200 or not body then return end
            local ok, j = pcall(hs.json.decode, body)
            if not ok then return end
            local hoursAhead = nextRain(j)
            local newVal = hoursAhead and formatLead(hoursAhead) or ""
            if newVal ~= lastValue then
                lastValue = newVal
                refresh()
            end
        end)
end

function M.update() return lastValue end

function M.setup(refresh)
    poll(refresh)
    pollTimer = hs.timer.doEvery(POLL_INTERVAL_S, function() poll(refresh) end)
end

function M.teardown()
    if pollTimer then pollTimer:stop(); pollTimer = nil end
    lastValue = ""
end

return M
