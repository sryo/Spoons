require("hs.ipc")
--require "TrackpadKeys"
--require "HyperlinkHijacker"
require "Sssssssscroll"
local WindowScape = require "WindowScape"
require "FrameMaster"
--require "EdgeHopper"
--require "WanderFocus"
require "SideSwipe"
require "AutoDMG"
--require "AppTimeout"
require "NoTunes"
--require "BubbleCursor"
--require "DigUp"
--require "UndoClose"
local CloudPad = require("CloudPad"); CloudPad.start()
--require "TimeTrail"


--local ZXNav = require("ZXNav")
--ZXNav:start()

local Muse = require("Muse")

local Palette = require("Palette")

local TTTaps = require("TTTaps")
TTTaps.onTap(5, function()
    if not Palette.isOpen() then Palette.open() end
end)
TTTaps.onPlusOne(4, function(side)
    WindowScape.moveToAdjacentScreen(side == "left" and "previous" or "next")
end)
TTTaps.onDrag(3, function(direction)
    if direction == "left" then
        WindowScape.focusAdjacent("backward")
    elseif direction == "right" then
        WindowScape.focusAdjacent("forward")
    end
end)
TTTaps.onDrag(4, function(direction)
    if direction == "left" then
        WindowScape.moveInOrder("backward")
    elseif direction == "right" then
        WindowScape.moveInOrder("forward")
    elseif direction == "up" then
        WindowScape.toggleFullscreen()
    elseif direction == "down" then
        WindowScape.minimize()
    end
end)
TTTaps.start()

--local ChoiceBox = require("ChoiceBox")

--local anycomplete = require("ZXSuggest")
--anycomplete.start()

--[[
-- adjust require to where you install this relative to ~/.hammerspoon
local axbrowse = require("temp")
local lastApp
hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "b", function()
    local currentApp = hs.axuielement.applicationElement(hs.application.frontmostApplication())
    if currentApp == lastApp then
        axbrowse.browse() -- try to continue from where we left off
    else
        lastApp = currentApp
        axbrowse.browse(currentApp) -- new app, so start over
    end
end)
]]
