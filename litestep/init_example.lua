--[[
  LiteStep Example - How to use the LiteStep module in Hammerspoon

  Add this to your init.lua:
    require("litestep.init_example")

  Or copy the relevant parts to your existing configuration.
]]

local LiteStep = require("LiteStep")

-- Load the theme configuration
LiteStep.loadTheme("litestep/theme.rc")

-- Create a taskbar
local taskbar = LiteStep.createTaskbar("Taskbar")
if taskbar then
    taskbar:create()
end

-- Create clock label with dynamic time
local clockLabel = LiteStep.createLabel("ClockLabel")
if clockLabel then
    clockLabel:create()

    -- Update clock every second
    local clockTimer = hs.timer.doEvery(1, function()
        local timeStr = os.date("%I:%M %p")
        clockLabel.window:setText(timeStr)
    end)
end

-- Create date label
local dateLabel = LiteStep.createLabel("DateLabel")
if dateLabel then
    dateLabel:create()

    -- Update date every minute
    local dateTimer = hs.timer.doEvery(60, function()
        local dateStr = os.date("%b %d")
        dateLabel.window:setText(dateStr)
    end)

    -- Set initial date
    dateLabel.window:setText(os.date("%b %d"))
end

-- Create status label
local statusLabel = LiteStep.createLabel("StatusLabel")
if statusLabel then
    statusLabel:create()

    -- Example: Update status when switching spaces
    local spaceWatcher = hs.spaces.watcher.new(function(space)
        statusLabel.window:setText("Space " .. tostring(space))
    end)
    spaceWatcher:start()
end

-- Cleanup function for config reload
function LiteStep_cleanup()
    LiteStep.destroyAll()
end

-- Register cleanup with Hammerspoon reload
hs.shutdownCallback = LiteStep_cleanup

print("LiteStep loaded successfully!")
