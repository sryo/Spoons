-- Sssssssscroll: Use mouth noises to scroll and control applications.
-- "Ssssssss" sound for continuous scrolling,
-- Single water drop sound (lip pop) for one action,
-- Double water drop sound (two quick lip pops) for another action (might take some time to master).

local noises = require "hs.noises"
local application = require "hs.application"
local eventtap = require "hs.eventtap"
local alert = require "hs.alert"
local timer = require "hs.timer"

-- Configuration
local config = {
    scrollSpeed = 20,             -- Pixels to scroll per tick during continuoussssssss scroll
    scrollInterval = 0.02,        -- Seconds between scroll ticks
    waterDropScrollAmount = 600,  -- Pixels to scroll on single water drop sound (lip pop)
    doubleWaterDropInterval = 0.6 -- Maximum interval (in seconds) between drops for a double water drop event
}

-- Custom actions for different applications
local appActions = {
    ["Sublime Text"] = {
        continuoussssssss = function() eventtap.keyStroke({}, "down") end,
        waterDrop = function() eventtap.keyStroke({}, "up") end,
        doubleWaterDrop = function() eventtap.keyStroke({ "cmd" }, "p") end -- Open command palette
    },
    ["Finder"] = {
        continuoussssssss = function() eventtap.keyStroke({}, "down") end,
        waterDrop = function() eventtap.keyStroke({}, "up") end,
        doublewaterDrop = function() eventtap.keyStroke({}, "space") end -- Open selected item
    },
    ["Terminal"] = {
        continuoussssssss = function() eventtap.keyStroke({ "cmd" }, "n") end, -- Scroll to next mark
        waterDrop = function() eventtap.keyStroke({ "cmd" }, "p") end,         -- Scroll to previous mark
        doubleWaterDrop = function() eventtap.keyStroke({ "cmd" }, "k") end    -- Clear terminal
    }
}

local scrollTimer = nil
local lastWaterDropTime = 0
local waterDropTimer = nil

local SssssssscrollManager = {}
SssssssscrollManager.listener = nil
SssssssscrollManager.isListening = false

function SssssssscrollManager:handleNoise(eventNum)
    local currentApp = application.frontmostApplication():name()
    local appSpecificActions = appActions[currentApp] or {}

    if eventNum == 1 then -- Start of "sssssssssss"
        if appSpecificActions.continuoussssssss then
            scrollTimer = timer.doEvery(config.scrollInterval, appSpecificActions.continuoussssssss)
        else
            scrollTimer = timer.doEvery(config.scrollInterval, function()
                eventtap.scrollWheel({ 0, -config.scrollSpeed }, {}, "pixel")
            end)
        end
    elseif eventNum == 2 then -- End of "sssssssssss"
        if scrollTimer then
            scrollTimer:stop()
            scrollTimer = nil
        end
    elseif eventNum == 3 then -- Water drop sound (lip pop)
        local currentTime = timer.secondsSinceEpoch()
        if currentTime - lastWaterDropTime < config.doubleWaterDropInterval then
            -- Double water drop detected
            if waterDropTimer then waterDropTimer:stop() end
            if appSpecificActions.doubleWaterDrop then
                appSpecificActions.doubleWaterDrop()
            else
                -- Default double water drop action
                eventtap.keyStroke({ "shift" }, "space")
            end
        else
            -- Start timer for potential double water drop
            lastWaterDropTime = currentTime
            if waterDropTimer then waterDropTimer:stop() end
            waterDropTimer = timer.doAfter(config.doubleWaterDropInterval, function()
                if appSpecificActions.waterDrop then
                    appSpecificActions.waterDrop()
                else
                    eventtap.scrollWheel({ 0, config.waterDropScrollAmount }, {}, "pixel")
                end
            end)
        end
    end
end

function SssssssscrollManager:toggleListener()
    if not self.isListening then
        self.listener:start()
        alert.show("Sssssssscroll: Listening")
    else
        self.listener:stop()
        if scrollTimer then
            scrollTimer:stop()
            scrollTimer = nil
        end
        if waterDropTimer then
            waterDropTimer:stop()
            waterDropTimer = nil
        end
        alert.show("Sssssssscroll: Stopped listening")
    end
    self.isListening = not self.isListening
end

function SssssssscrollManager:init()
    self.isListening = false
    self.listener = noises.new(function(eventNum) self:handleNoise(eventNum) end)
end

function SssssssscrollManager:addAppAction(appName, actionType, action)
    if not appActions[appName] then
        appActions[appName] = {}
    end
    appActions[appName][actionType] = action
    alert.show("Added " .. actionType .. " action for " .. appName)
end

SssssssscrollManager:init()

hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "S", function() SssssssscrollManager:toggleListener() end)

return SssssssscrollManager
