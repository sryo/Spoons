local fs    = require("hs.fs")
local task  = require("hs.task")
local alert = require("hs.alert")
local timer = require("hs.timer")
local app   = require("hs.application")
local key   = require("hs.eventtap").keyStroke
local scroll = require("hs.eventtap").scrollWheel

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

local config = {
    pythonVenvPath = os.getenv("HOME") .. "/.hammerspoon/.venv/bin/python",
    pythonScriptPath = os.getenv("HOME") .. "/.hammerspoon/hs_noises.py",
    scrollSpeed = 20,
    scrollInterval = 0.02,
    waterDropScrollAmount = 600,
    doubleWaterDropInterval = 0.6
}

local appActions = {
    ["Sublime Text"] = {
        continuoussssssss = function() key({}, "down") end,
        waterDrop = function() key({}, "up") end,
        doubleWaterDrop = function() key({ "cmd" }, "p") end
    },
    ["Finder"] = {
        continuoussssssss = function() key({}, "down") end,
        waterDrop = function() key({}, "up") end,
        doubleWaterDrop = function() key({}, "space") end
    },
    ["Terminal"] = {
        continuoussssssss = function() key({ "cmd" }, "n") end,
        waterDrop = function() key({ "cmd" }, "p") end,
        doubleWaterDrop = function() key({ "cmd" }, "k") end
    }
}

--------------------------------------------------------------------------------
-- SCROLL MANAGER
--------------------------------------------------------------------------------

local SssssssscrollManager = {}
local scrollTimer = nil
local waterDropTimer = nil
local lastWaterDropTime = 0

function SssssssscrollManager:handleNoise(eventNum)
    local currentApp = app.frontmostApplication():name()
    local actions = appActions[currentApp] or {}

    if eventNum == 1 then -- Hiss start
        scrollTimer = timer.doEvery(config.scrollInterval,
            actions.continuoussssssss or function()
                scroll({ 0, -config.scrollSpeed }, {}, "pixel")
            end)
    elseif eventNum == 2 then -- Hiss end
        if scrollTimer then scrollTimer:stop(); scrollTimer = nil end
    elseif eventNum == 3 then -- Single pop
        local now = timer.secondsSinceEpoch()
        if now - lastWaterDropTime < config.doubleWaterDropInterval then
            if waterDropTimer then waterDropTimer:stop() end
            (actions.doubleWaterDrop or function() key({ "shift" }, "space") end)()
        else
            lastWaterDropTime = now
            if waterDropTimer then waterDropTimer:stop() end
            waterDropTimer = timer.doAfter(config.doubleWaterDropInterval,
                actions.waterDrop or function()
                    scroll({ 0, config.waterDropScrollAmount }, {}, "pixel")
                end)
        end
    end
end

--------------------------------------------------------------------------------
-- PYTHON TASK LAUNCHER
--------------------------------------------------------------------------------

local audioTask = nil

local function startAudioHelper()
    if not fs.attributes(config.pythonVenvPath) then
        alert.show("Python venv not found at:\n" .. config.pythonVenvPath)
        return
    end

    if not fs.attributes(config.pythonScriptPath) then
        alert.show("Missing Python script:\n" .. config.pythonScriptPath)
        return
    end

    audioTask = task.new(config.pythonVenvPath,
        function(_, stdout, stderr)
            for line in stdout:gmatch("[^\r\n]+") do
                local n = tonumber(line)
                if n then SssssssscrollManager:handleNoise(n) end
            end
            if stderr and #stderr > 0 then
                alert.show("Error: " .. stderr)
            end
            return false
        end,
        { config.pythonScriptPath }
    )
    audioTask:start()
    alert.show("🎤 Audio monitor started")
end

--------------------------------------------------------------------------------
-- HOTKEY TOGGLE
--------------------------------------------------------------------------------

hs.hotkey.bind({ "ctrl", "alt", "cmd" }, "N", function()
    if audioTask and audioTask:isRunning() then
        audioTask:terminate()
        alert.show("🛑 Audio monitor stopped")
    else
        startAudioHelper()
    end
end)

--------------------------------------------------------------------------------
-- START ON LAUNCH
--------------------------------------------------------------------------------

startAudioHelper()
