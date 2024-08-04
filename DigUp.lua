-- Import Hammerspoon modules
local window = require "hs.window"
local timer = require "hs.timer"
local fs = require "hs.fs"
local menubar = require "hs.menubar"
local alert = require "hs.alert"

-- Path to the whitelist file
local whitelistFilePath = os.getenv("HOME") .. "/.hammerspoon/whitelist.txt"

-- Function to load the whitelist from a file
local function loadWhitelist()
    local whitelist = {}
    local file = io.open(whitelistFilePath, "r")
    if file then
        for line in file:lines() do
            whitelist[line] = true
        end
        file:close()
    end
    return whitelist
end

-- Function to save the whitelist to a file
local function saveWhitelist(whitelist)
    local file = io.open(whitelistFilePath, "w")
    if file then
        for app in pairs(whitelist) do
            file:write(app .. "\n")
        end
        file:close()
    end
end

-- Initialize whitelist
local whitelist = loadWhitelist()

-- Create a menubar icon
local menubarIcon = menubar.new()

-- Function to update the menubar icon based on the currently active app's whitelist status
local function updateMenubarIcon()
    local win = window.frontmostWindow()
    if win then
        local app = win:application()
        local bundleID = app:bundleID()
        if whitelist[bundleID] then
            menubarIcon:setTitle("Recording") -- Display "Recording" if whitelisted
        else
            menubarIcon:setTitle("Ignored") -- Display "Ignored" if not whitelisted
        end
    end
end

updateMenubarIcon() -- Initial update of menubar icon

-- Add a click callback to the menubar icon to toggle whitelist
menubarIcon:setClickCallback(function()
    local win = window.frontmostWindow()
    if win then
        local app = win:application()
        local bundleID = app:bundleID()
        if whitelist[bundleID] then
            whitelist[bundleID] = nil
        else
            whitelist[bundleID] = true
        end
        saveWhitelist(whitelist)
        checkWindowFocus() -- Update timer after whitelist change
    end
end)

-- Define a variable to hold the timer
local captureTimer = nil

-- Function to start or stop the timer based on whether the currently focused app is in the whitelist
function checkWindowFocus()
    updateMenubarIcon()
    local win = window.frontmostWindow()
    if win then
        local app = win:application()
        if app and whitelist[app:bundleID()] then
            if not captureTimer then
                -- Start the timer if it's not already running
                captureTimer = timer.doEvery(3, function() checkAndCaptureWindow() end)
            end
        else
            -- Stop the timer if it's running
            if captureTimer then
                captureTimer:stop()
                captureTimer = nil
            end
        end
    end
end

-- Function to take a snapshot of the currently active window if it's in the whitelist
function checkAndCaptureWindow()
    local win = window.frontmostWindow()
    if win then
        local app = win:application()
        if app and whitelist[app:bundleID()] then
            -- Get the window ID
            local winID = win:id()
            -- Take a snapshot of the window
            local snapshot = window.snapshotForID(winID)
            if snapshot then
                -- Save the snapshot to a file
                local timestamp = os.date("%Y%m%d%H%M%S")
                local filename = os.getenv("HOME") .. "/Desktop/window_snapshot_" .. timestamp .. ".jpg"
                snapshot:saveToFile(filename, false, "jpg")
            end
        end
    end
end

-- Watch for window focus changes
window.filter.default:subscribe(window.filter.windowFocused, function(win)
    checkWindowFocus()
end)

-- Binding hotkey to take a snapshot manually
hs.hotkey.bind({ "ctrl", "alt" ,"shift"}, "space", checkAndCaptureWindow)
