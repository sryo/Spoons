-- DigUp: remember everything you've seen on screen.
-- https://github.com/sryo/Spoons/blob/main/DigUp/menubar.lua - status icon, recording toggle, app blacklist
local menubar     = require("hs.menubar")
local json        = require("hs.json")
local application = require("hs.application")
local alert       = require("hs.alert")
local image       = require("hs.image")

local cfg     = require("DigUp.config")
local db      = require("DigUp.db")
local capture = require("DigUp.capture")
local search  = require("DigUp.search")

local mb = {}
local bar

-- Persist blacklist
local function saveBlacklist()
    local list = {}
    for bundle, _ in pairs(cfg.blacklist) do
        list[#list + 1] = bundle
    end
    local data = json.encode(list)
    local f = io.open(cfg.blacklistPath, "w")
    if f then f:write(data); f:close() end
end

local function loadBlacklist()
    local f = io.open(cfg.blacklistPath, "r")
    if not f then return end
    local data = f:read("*a")
    f:close()
    local ok, list = pcall(json.decode, data)
    if ok and list then
        -- Re-merge defaults so password managers are always blacklisted
        cfg.blacklist = {}
        for _, bundle in ipairs(cfg.defaultBlacklist) do
            cfg.blacklist[bundle] = true
        end
        for _, bundle in ipairs(list) do
            cfg.blacklist[bundle] = true
        end
    end
end

local function updateIcon()
    if not bar then return end
    if capture.isRecording() then
        bar:setTitle("⏺")
    elseif capture.isPaused() then
        bar:setTitle("⏸")
    else
        bar:setTitle("⏹")
    end
end

local function buildMenu()
    local items = {}

    -- Toggle recording
    local recLabel = capture.isRecording() and "Pause recording" or "Resume recording"
    items[#items + 1] = {
        title = recLabel,
        fn = function()
            if capture.isRecording() then
                capture.pause()
            else
                capture.resume()
            end
            updateIcon()
        end,
    }

    items[#items + 1] = { title = "-" }

    -- Block/unblock current app
    local app = application.frontmostApplication()
    if app then
        local bundle = app:bundleID()
        local name = app:name() or bundle
        if bundle then
            if cfg.blacklist[bundle] then
                items[#items + 1] = {
                    title = "Record " .. name,
                    fn = function()
                        cfg.blacklist[bundle] = nil
                        saveBlacklist()
                        alert.show("Recording " .. name)
                    end,
                }
            else
                items[#items + 1] = {
                    title = "Skip " .. name,
                    fn = function()
                        cfg.blacklist[bundle] = true
                        saveBlacklist()
                        alert.show("Skipping " .. name)
                    end,
                }
            end
        end
    end

    items[#items + 1] = { title = "-" }

    -- Search
    items[#items + 1] = {
        title = "Search…",
        fn = function() search.show() end,
    }

    items[#items + 1] = { title = "-" }

    -- Stats
    local stats = db.getStats()
    items[#items + 1] = {
        title = string.format("%d screenshots, %d searchable, %d apps",
            stats.totalFrames, stats.totalOCR, stats.distinctApps),
        disabled = true,
    }

    return items
end

function mb.init()
    loadBlacklist()
    bar = menubar.new()
    bar:setMenu(buildMenu)
    updateIcon()
end

function mb.updateIcon()
    updateIcon()
end

function mb.delete()
    if bar then bar:delete(); bar = nil end
end

return mb
