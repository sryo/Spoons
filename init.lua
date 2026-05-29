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

local Rebar = require("Rebar"); Rebar.start()
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
TTTaps.onDragStep(3, function(direction)
    if direction == "left" then
        WindowScape.focusAdjacent("backward")
    elseif direction == "right" then
        WindowScape.focusAdjacent("forward")
    end
end)
-- 4-drag undo arming. After firing minimize or fullscreen, an inverse drag
-- restores the captured window instead of running its normal verb. Disarms on
-- any mouseDown, or after a same-direction repeat (which runs the normal verb
-- on the new focused window without re-arming).
local fourDragArmed     = nil
local fourDragClickTap  = nil
local function disarmFourDrag()
    fourDragArmed = nil
    if fourDragClickTap then fourDragClickTap:stop(); fourDragClickTap = nil end
end
local function armFourDrag(kind, winId)
    fourDragArmed = { kind = kind, winId = winId }
    if fourDragClickTap then return end
    local et = hs.eventtap.event.types
    fourDragClickTap = hs.eventtap.new(
        { et.leftMouseDown, et.rightMouseDown, et.otherMouseDown },
        function() disarmFourDrag(); return false end
    )
    fourDragClickTap:start()
end
local function runFourDragVerb(kind)
    if kind == "fullscreen" then WindowScape.toggleFullscreen() else WindowScape.minimize() end
end
TTTaps.onDrag(4, function(direction)
    local kind = (direction == "up") and "fullscreen"
              or (direction == "down") and "minimize"
              or nil
    if not kind then return end
    if fourDragArmed and kind ~= fourDragArmed.kind then
        if fourDragArmed.kind == "minimize" then
            WindowScape.restoreSnapshot(fourDragArmed.winId)
        else
            WindowScape.exitFullscreenFor(fourDragArmed.winId)
        end
        disarmFourDrag()
        return
    end
    if fourDragArmed and kind == fourDragArmed.kind then
        runFourDragVerb(kind)
        disarmFourDrag()
        return
    end
    local win = hs.window.focusedWindow()
    local wasFs = win and WindowScape.isFullscreen(win) or false
    runFourDragVerb(kind)
    -- Only arm if the verb moved us into a state with something to undo:
    -- minimize is always one-way, fullscreen only when we just entered it.
    if not win then return end
    if kind == "fullscreen" and wasFs then return end
    armFourDrag(kind, win:id())
end)
TTTaps.onDragStep(4, function(direction)
    if direction == "left" then
        WindowScape.moveInOrder("backward")
    elseif direction == "right" then
        WindowScape.moveInOrder("forward")
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
