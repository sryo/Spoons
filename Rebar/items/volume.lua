-- Volume item. Subscribes to the default output device's volume and mute
-- events so it reflects changes made by anything (SideSwipe, hardware keys,
-- Control Center, other apps) without polling. The singleton
-- hs.audiodevice.watcher catches the case where the default output device
-- itself changes (e.g. AirPods connect), and we rebind to the new one.

local M = {
    id       = "volume",
    side     = "right",
    order    = 70,
    interval = 0,
}

local currentDevice
local _refresh

-- Strip the user's possessive ("Mateo's AirPods Max" -> "AirPods Max").
-- The localized Mac speaker name ("MacBook Pro Speakers", "Altavoces de
-- MacBook Air") is suppressed entirely below by checking transportType.
local function trimPossessive(name)
    if not name then return "" end
    return (name:gsub("^[^']+'s ", ""))
end

local function format()
    local d = hs.audiodevice.defaultOutputDevice()
    if not d then return "" end
    local transport = d.transportType and d:transportType() or nil
    local isBuiltIn = (transport == "Built-in") or transport == nil
    local label = isBuiltIn and "" or trimPossessive(d:name())

    if d:muted() then
        return label ~= "" and ("♪ " .. label .. " muted") or "♪ muted"
    end
    local v = d:outputVolume()
    if not v then return "♪ " .. label end
    local pct = math.floor(v + 0.5)
    if label == "" then return string.format("♪ %d%%", pct) end
    return string.format("♪ %s %d%%", label, pct)
end

function M.update() return format() end

local function onDeviceEvent(_devUID, eventName)
    if eventName == "vmvc" or eventName == "mute" then
        if _refresh then _refresh() end
    end
end

local function rebindToDefault()
    if currentDevice then currentDevice:watcherStop() end
    currentDevice = hs.audiodevice.defaultOutputDevice()
    if currentDevice then
        currentDevice:watcherCallback(onDeviceEvent)
        currentDevice:watcherStart()
    end
    if _refresh then _refresh() end
end

function M.setup(refresh)
    _refresh = refresh
    rebindToDefault()
    hs.audiodevice.watcher.setCallback(function(event)
        if event == "dOut" then rebindToDefault() end
    end)
    hs.audiodevice.watcher.start()
end

function M.teardown()
    hs.audiodevice.watcher.stop()
    if currentDevice then currentDevice:watcherStop(); currentDevice = nil end
    _refresh = nil
end

return M
