local hotkey = require("hs.hotkey")
local pasteboard = require("hs.pasteboard")
local alert = require("hs.alert")
local serverMod = require("CloudPad.server")
local log = require("CloudPad.log")

local CONFIG_DIR = hs.configdir or os.getenv("HOME") .. "/.hammerspoon"
local DEFAULT_PORT = 1984
local DEFAULT_HOTKEY = { { "cmd", "ctrl" }, "C" }
local DEFAULT_ASSETS = CONFIG_DIR .. "/CloudPad/assets"

local function defaults(opts)
    opts = opts or {}
    opts.port = opts.port or DEFAULT_PORT
    opts.hotkey = opts.hotkey or DEFAULT_HOTKEY
    opts.assetsDir = opts.assetsDir or DEFAULT_ASSETS
    opts.version = opts.version or "2"
    return opts
end

-- Reload-safe singleton: clean up the previous instance before building a new one.
if _G.__CloudPadInstance then
    local prev = _G.__CloudPadInstance
    if prev.hotkey then prev.hotkey:delete() end
    if prev.instance and prev.instance.server then
        prev.instance.server:stop()
    end
    _G.__CloudPadInstance = nil
end

local singleton = {}
_G.__CloudPadInstance = singleton

local function bindHotkey(url)
    if not url then return nil end
    local spec = singleton.opts.hotkey
    return hotkey.bind(spec[1], spec[2], function()
        pasteboard.setContents(url)
        alert.show("CloudPad URL copied\n" .. url, 2)
    end)
end

local M = {}

function M.start(opts)
    if singleton.instance then return singleton end
    singleton.opts = defaults(opts)
    local ok, instance = pcall(serverMod.start, singleton.opts)
    if not ok then
        log.error("start failed:", instance)
        return nil
    end
    singleton.instance = instance
    singleton.hotkey = bindHotkey(instance.url)
    M.url = instance.url
    return singleton
end

function M.stop()
    if singleton.hotkey then
        singleton.hotkey:delete()
        singleton.hotkey = nil
    end
    if singleton.instance then
        serverMod.stop(singleton.instance)
        singleton.instance = nil
    end
    M.url = nil
end

function M.isRunning()
    return singleton.instance ~= nil
end

function M.setPort(n)
    local opts = singleton.opts or {}
    opts.port = n
    M.stop()
    M.start(opts)
end

function M.reload()
    local opts = singleton.opts
    M.stop()
    M.start(opts)
end

return M
