--[[
  DigUp: remember everything you've seen on screen.
  Captures your screen periodically, reads the text in each frame, and lets you
  search it all back. Pick a result and scrub through nearby moments.

  Hotkeys (change in DigUp/config.lua):
    ctrl+alt+cmd+R  search
    ctrl+alt+cmd+D  toggle recording

  Files:
    DigUp.lua                      loads everything (this file)
    DigUp/config.lua               settings
    DigUp/capture.lua              screenshot loop, thumbnails
    DigUp/ocr.lua                  async OCR via Swift CLI
    DigUp/db.lua                   SQLite + FTS
    DigUp/search.lua               chooser, viewer, scrubber
    DigUp/menubar.lua              menubar icon, blacklist
    DigUp/cleanup.lua              old frame pruning
    DigUp/digup_ocr_helper.swift   Vision OCR CLI source
    DigUp/data/                    DB, screenshots, compiled binary

  First run:
    1. Grant Hammerspoon screen recording + accessibility permissions.
    2. require("DigUp") in init.lua, reload.
    (OCR binary auto-compiles on first run if swiftc is available.)
]]

local hotkey     = require("hs.hotkey")
local caffeinate = require("hs.caffeinate")

local cfg     = require("DigUp.config")
local db      = require("DigUp.db")
local capture = require("DigUp.capture")
local ocr     = require("DigUp.ocr")
local search  = require("DigUp.search")
local mb      = require("DigUp.menubar")
local cleanup = require("DigUp.cleanup")

-- Make sure data dirs exist (no shell, uses hs.fs.mkdir)
local function ensureDir(path)
    if hs.fs.attributes(path, "mode") == "directory" then return true end
    local parts = {}
    for segment in path:gmatch("[^/]+") do
        parts[#parts + 1] = segment
        local partial = "/" .. table.concat(parts, "/")
        if hs.fs.attributes(partial, "mode") ~= "directory" then
            local ok, err = hs.fs.mkdir(partial)
            if not ok then
                print("[DigUp] ensureDir failed: " .. (err or partial))
                return false
            end
        end
    end
    return true
end

local function ensureDirs()
    ensureDir(cfg.storageDir)
    ensureDir(cfg.screenshotDir)
end

-- Auto-compile OCR binary if missing or incompatible
local function ensureOCRHelper()
    -- Test if existing binary actually runs (catches wrong architecture)
    local f = io.open(cfg.ocrHelperPath, "r")
    if f then
        f:close()
        local _, status = hs.execute('"' .. cfg.ocrHelperPath .. '" /dev/null 2>/dev/null')
        if status then return end -- binary exists and executes
        print("[DigUp] ocr binary exists but failed to run, recompiling...")
    end

    -- Check for swiftc
    local _, hasSwiftc = hs.execute("command -v swiftc >/dev/null 2>&1")
    if not hasSwiftc then
        print("[DigUp] ERROR: swiftc not found. Install with: xcode-select --install")
        hs.alert.show("DigUp: Xcode CLI tools required.\nRun: xcode-select --install")
        return
    end

    local swiftSrc = hs.configdir .. "/DigUp/digup_ocr_helper.swift"
    print("[DigUp] compiling ocr helper...")
    local output, status = hs.execute('swiftc -O -o "' .. cfg.ocrHelperPath .. '" "' .. swiftSrc .. '" 2>&1')
    if status then
        print("[DigUp] compiled ok")
    else
        print("[DigUp] compile failed: " .. (output or ""))
        hs.alert.show("DigUp: OCR helper compile failed. See console.")
    end
end

-- Init (wrapped so DigUp failure doesn't kill other modules)
local ok, err = pcall(function()
    ensureDirs()
    ensureOCRHelper()

    if db.init() == false then
        error("database init failed")
    end

    mb.init()
    cleanup.start()

    -- Bind hotkeys
    hotkey.bind(cfg.searchHotkey.mods, cfg.searchHotkey.key, function()
        search.show()
    end)

    hotkey.bind(cfg.toggleHotkey.mods, cfg.toggleHotkey.key, function()
        if capture.isRecording() then
            capture.pause()
        else
            capture.resume()
        end
        mb.updateIcon()
    end)

    -- Pause on screen lock, resume on unlock
    local caffWatcher = caffeinate.watcher.new(function(event)
        if event == caffeinate.watcher.screensDidLock
           or event == caffeinate.watcher.screensDidSleep
           or event == caffeinate.watcher.systemWillSleep then
            capture.pause()
            mb.updateIcon()
        elseif event == caffeinate.watcher.screensDidUnlock
               or event == caffeinate.watcher.screensDidWake
               or event == caffeinate.watcher.systemDidWake then
            capture.resume()
            mb.updateIcon()
        end
    end)
    caffWatcher:start()

    -- Start recording
    capture.start(ocr.enqueue)
    mb.updateIcon()

    print("[DigUp] started, capturing every " .. cfg.captureInterval .. "s")
end)

if not ok then
    print("[DigUp] FAILED to start: " .. tostring(err))
end

