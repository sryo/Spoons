-- Network status. Shows the WiFi SSID when associated, "Ethernet" when only
-- a wired interface has reachability, "offline" otherwise. Event-driven via
-- hs.wifi.watcher and hs.network.reachability.internet.

local M = {
    id       = "network",
    side     = "right",
    order    = 60,
    interval = 0,
}

local wifiWatcher, reach, pollTimer

local function isReachable()
    local r = hs.network.reachability.internet()
    if not r then return false end
    local status = r:status()
    local flag = hs.network.reachability.flags.reachable or 0x2
    return status and (status & flag) ~= 0
end

function M.update()
    if not isReachable() then return "offline" end
    local iface = hs.network.primaryInterfaces()
    if not iface then return "offline" end
    -- Identify Wi-Fi: only the AirPort interface has an "AirPort" key in its
    -- interfaceDetails. hs.network.primaryInterfaces sometimes returns the
    -- BSD name twice (no friendly service name), so the service string is
    -- unreliable for this.
    local detail = hs.network.interfaceDetails(iface) or {}
    if detail.AirPort then
        local ssid = hs.wifi.currentNetwork()
        -- macOS 14+ hides the SSID unless Hammerspoon has Location permission;
        -- in that case currentNetwork() returns nil even though Wi-Fi is up.
        return (ssid and ssid ~= "") and ssid or "Wi-Fi"
    end
    return "Ethernet"
end

function M.setup(refresh)
    wifiWatcher = hs.wifi.watcher.new(function(_, event)
        if event == "SSIDChange" or event == "powerChange" or event == "linkChange" then
            refresh()
        end
    end)
    wifiWatcher:start()
    reach = hs.network.reachability.internet()
    if reach then
        reach:setCallback(function() refresh() end)
        reach:start()
    end
    -- Triggers the Location permission prompt the first time. macOS 14+ only
    -- returns the SSID via CoreWLAN when the calling process has Location
    -- granted; without it we'd be stuck showing "Wi-Fi" forever. After
    -- permission is decided, we keep a slow poll for ~30 seconds to pick up
    -- the SSID once it becomes available, then stop.
    pcall(function() hs.location.start() end)
    local ticks = 0
    pollTimer = hs.timer.doEvery(3, function()
        ticks = ticks + 1
        refresh()
        if ticks >= 10 or hs.wifi.currentNetwork() then
            pollTimer:stop(); pollTimer = nil
        end
    end)
end

function M.teardown()
    if wifiWatcher then wifiWatcher:stop(); wifiWatcher = nil end
    if reach then reach:stop(); reach = nil end
    if pollTimer then pollTimer:stop(); pollTimer = nil end
    pcall(function() hs.location.stop() end)
end

return M
