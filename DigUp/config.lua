-- DigUp: remember everything you've seen on screen.
-- https://github.com/sryo/Spoons/blob/main/DigUp/config.lua - settings (intervals, hotkeys, limits, blacklists)
local cfg = {
    captureInterval   = 2,
    storageDir        = hs.configdir .. "/DigUp/data",
    ocrConfidence     = 0.35,
    minPixelDiff      = 0.05, -- fraction of bytes that must differ to count as a new frame
    minBatteryPct     = 20,   -- skip capture below this %; 0 to disable
    blacklist         = {},
    retentionDays     = 30,
    maxStorageGB      = 5,
    searchHotkey      = { mods = {"ctrl", "alt", "cmd"}, key = "r" },
    toggleHotkey      = { mods = {"ctrl", "alt", "cmd"}, key = "d" },

    -- Skip windows whose title contains any of these (lowercase match)
    sensitivePatterns = {
        "private browsing",   -- Safari
        "incognito",          -- Chrome
        "private window",     -- Firefox
        "password",
        "keychain",
        "credential",
        "ssh ", "sudo ",
    },

    -- Clipboard capture (searchable clipboard history alongside screenshots)
    captureClipboard  = true,

    -- Event merge gap: consecutive same-window matches within this many seconds
    -- collapse into a single result showing duration
    eventMergeGap     = 10,

    -- Max width for saved screenshots (downscaled before JPEG save; OCR uses full-res)
    screenshotMaxWidth = 1280,

    -- Extra noise patterns to filter from OCR (Lua patterns, matched against full text)
    noisePatterns     = {},

    -- Never record these apps (bundle IDs)
    defaultBlacklist  = {
        "com.1password.1password",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "org.keepassxc.keepassxc",
        "com.bitwarden.desktop",
    },
}

cfg.dbPath          = cfg.storageDir .. "/digup.db"
cfg.screenshotDir   = cfg.storageDir .. "/screenshots"
cfg.ocrHelperPath   = cfg.storageDir .. "/ocr_helper"
cfg.blacklistPath   = cfg.storageDir .. "/blacklist.json"

-- Merge default blacklist into runtime blacklist
for _, bundle in ipairs(cfg.defaultBlacklist) do
    cfg.blacklist[bundle] = true
end

return cfg
