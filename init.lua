require("hs.ipc")
--require "TrackpadKeys"
--require "HyperlinkHijacker"
require "Sssssssscroll"
require "WindowScape"
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
