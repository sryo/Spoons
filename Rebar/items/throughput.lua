-- Format: "↑ 12k ↓ 340k" (bytes/sec, rounded).

local M = {
    id             = "throughput",
    side           = "right",
    order          = 60,
    interval       = 0,
    defaultEnabled = false,
}

local last = { rx = 0, tx = 0, ts = 0 }
local pendingTask, pollTimer, _refresh

local function human(n)
    if n < 1024 then return string.format("%d", n) end
    if n < 1024 * 1024 then return string.format("%dk", n / 1024) end
    return string.format("%.1fM", n / (1024 * 1024))
end

local function scrape()
    if pendingTask then return end
    pendingTask = hs.task.new("/usr/sbin/netstat", function(_code, out)
        pendingTask = nil
        if not out then return end
        local rx, tx = 0, 0
        for line in out:gmatch("[^\n]+") do
            local parts = {}
            for p in line:gmatch("%S+") do table.insert(parts, p) end
            -- netstat -ib: <Link…> token in column 3 marks the byte-count row.
            if parts[1] and not parts[1]:match("^lo") and parts[3] and parts[3]:match("^<Link") then
                local ibytes = tonumber(parts[7])
                local obytes = tonumber(parts[10])
                if ibytes then rx = rx + ibytes end
                if obytes then tx = tx + obytes end
            end
        end
        local now = hs.timer.secondsSinceEpoch()
        local dt = now - last.ts
        if last.ts > 0 and dt > 0 then
            local dRx = math.max(0, rx - last.rx) / dt
            local dTx = math.max(0, tx - last.tx) / dt
            local val = string.format("↑ %s ↓ %s", human(dTx), human(dRx))
            if M._cached ~= val then
                M._cached = val
                if _refresh then _refresh() end
            end
        end
        last.rx, last.tx, last.ts = rx, tx, now
    end, { "-ib" })
    pendingTask:start()
end

function M.update() return M._cached or "" end

function M.setup(refresh)
    _refresh = refresh
    scrape()
    pollTimer = hs.timer.doEvery(1, scrape)
end

function M.teardown()
    _refresh = nil
    if pollTimer then pollTimer:stop(); pollTimer = nil end
    if pendingTask then pendingTask:terminate(); pendingTask = nil end
    last.rx, last.tx, last.ts = 0, 0, 0
    M._cached = nil
end

return M
