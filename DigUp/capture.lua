-- DigUp: remember everything you've seen on screen.
-- https://github.com/sryo/Spoons/blob/main/DigUp/capture.lua - screenshot loop, change detection, thumbnails
local screen = require("hs.screen")
local image  = require("hs.image")
local fs     = require("hs.fs")
local timer  = require("hs.timer")
local window = require("hs.window")
local application = require("hs.application")
local battery = require("hs.battery")
local pasteboard = require("hs.pasteboard")

local cfg = require("DigUp.config")
local db  = require("DigUp.db")

local capture = {}
local captureTimer
local paused = false
local lastSnapshot
local nilSnapshotCount = 0
local lastAppBundle
local lastWinTitle
local lastClipboard

-- Byte-level diff ratio between two strings (0.0 = identical)
local function calculateStringDiff(str1, str2)
    if not str1 or not str2 or #str1 == 0 or #str2 == 0 then return 1.0 end

    local len1, len2 = #str1, #str2
    local minLen = math.min(len1, len2)
    local maxLen = math.max(len1, len2)

    local diffCount = 0
    for i = 1, minLen do
        if str1:byte(i) ~= str2:byte(i) then
            diffCount = diffCount + 1
        end
    end
    -- Count the length gap as extra differences
    diffCount = diffCount + (maxLen - minLen)

    return diffCount / maxLen
end

local function ensureDir(path)
    if fs.attributes(path, "mode") == "directory" then return true end
    -- Create parent directories iteratively (like mkdir -p)
    local parts = {}
    for segment in path:gmatch("[^/]+") do
        parts[#parts + 1] = segment
        local partial = "/" .. table.concat(parts, "/")
        if fs.attributes(partial, "mode") ~= "directory" then
            local ok, err = fs.mkdir(partial)
            if not ok then
                print("[DigUp] ensureDir failed: " .. (err or partial))
                return false
            end
        end
    end
    return true
end

function capture.tick()
    if paused then return end

    -- Frontmost app
    local app = application.frontmostApplication()
    if not app then return end
    local bundleId = app:bundleID() or ""
    local appName  = app:name() or ""

    -- Check blacklist
    if cfg.blacklist[bundleId] then return end

    -- Low battery? Skip.
    if cfg.minBatteryPct and cfg.minBatteryPct > 0 then
        if not battery.isCharging() and (battery.percentage() or 100) < cfg.minBatteryPct then
            return
        end
    end

    -- Get window title
    local win = window.frontmostWindow()
    local winTitle = win and win:title() or ""

    -- Skip sensitive windows
    local titleLower = winTitle:lower()
    for _, pattern in ipairs(cfg.sensitivePatterns) do
        if titleLower:find(pattern) then return end
    end

    -- App-change short-circuit: if app or window changed, skip expensive pixel diff
    local appChanged = (bundleId ~= lastAppBundle) or (winTitle ~= lastWinTitle)
    lastAppBundle = bundleId
    lastWinTitle = winTitle

    -- Capture focused window (smaller files, better OCR, more private)
    if not win then return end
    local snapshot = win:snapshot()
    if not snapshot then
        nilSnapshotCount = nilSnapshotCount + 1
        if nilSnapshotCount == 15 then
            print("[DigUp] WARNING: 15 consecutive nil snapshots. Grant Screen Recording permission to Hammerspoon.")
            hs.alert.show("DigUp: Screen Recording permission may be missing")
        end
        return
    end
    nilSnapshotCount = 0

    local diff = 1.0

    if appChanged then
        -- Context switch: guaranteed new content, skip pixel diff entirely
        lastSnapshot = nil
    else
        -- Same app/window: run pixel diff to detect meaningful changes
        local smallW, smallH = 64, 36
        local small = snapshot:copy()
        if not small then return end
        small = small:size({ w = smallW, h = smallH }, true)
        if not small then return end

        local smallData = small:encodeAsURLString(false, "PNG") or ""

        if lastSnapshot then
            diff = calculateStringDiff(smallData, lastSnapshot)
        end

        -- Skip if under change threshold
        if diff < (cfg.minPixelDiff or 0.05) then
            return
        end

        lastSnapshot = smallData
    end

    -- Build output path: screenshots/YYYY/MM/DD/HHMMSS.jpg
    local dateDir = os.date("%Y") .. "/" .. os.date("%m") .. "/" .. os.date("%d")
    local dir = cfg.screenshotDir .. "/" .. dateDir
    if not ensureDir(dir) then return end
    local basename = os.date("%H%M%S")
    local filepath = dir .. "/" .. basename .. ".jpg"
    local thumbpath = dir .. "/" .. basename .. "_thumb.jpg"

    -- Downscale before saving (OCR already ran on full-res snapshot in memory)
    local maxW = cfg.screenshotMaxWidth or 1280
    local sz = snapshot:size()
    if sz and sz.w > maxW then
        local scale = maxW / sz.w
        local saved = snapshot:copy()
        if saved then
            saved = saved:size({ w = math.floor(sz.w * scale), h = math.floor(sz.h * scale) }, true)
            if saved then snapshot = saved end
        end
    end

    -- Save screenshot as JPEG
    if not snapshot:saveToFile(filepath, false, "JPEG") then
        print("[DigUp] failed to save screenshot: " .. filepath)
        return
    end

    -- Save thumbnail
    local thumb = snapshot:copy()
    if thumb then
        thumb = thumb:size({ w = 160, h = 90 }, true)
        if thumb then thumb:saveToFile(thumbpath, false, "JPEG") end
    end

    -- Clipboard capture
    local clipboardText
    if cfg.captureClipboard then
        local clip = pasteboard.getContents()
        if clip and clip ~= lastClipboard then
            clipboardText = clip
            lastClipboard = clip
        end
    end

    -- Insert frame into database
    local now = os.time()
    local frameId = db.insertFrame(now, bundleId, appName, winTitle, filepath, "", diff, clipboardText)

    -- Return frameId, path, and clipboard so OCR can queue it
    return frameId, filepath, clipboardText
end

function capture.start(ocrQueueFn)
    captureTimer = timer.doEvery(cfg.captureInterval, function()
        local ok, frameId, filepath, clipText = pcall(capture.tick)
        if not ok then
            print("[DigUp] capture.tick error: " .. tostring(frameId))
            return
        end
        if frameId and ocrQueueFn then
            ocrQueueFn(frameId, filepath, clipText)
        end
    end)
end

function capture.stop()
    if captureTimer then
        captureTimer:stop()
        captureTimer = nil
    end
end

function capture.pause()
    paused = true
end

function capture.resume()
    paused = false
    lastSnapshot = nil
    lastAppBundle = nil
    lastWinTitle = nil
    lastClipboard = nil
end

function capture.isRecording()
    return captureTimer ~= nil and not paused
end

function capture.isPaused()
    return paused
end

return capture
