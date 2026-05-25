local httpserver = require("hs.httpserver")
local network = require("hs.network")
local host = require("hs.host")
local routes = require("CloudPad.routes")
local screenshot = require("CloudPad.screenshot")
local log = require("CloudPad.log")

local M = {}

local function ipv4Address()
    local ok, iface = pcall(network.primaryInterfaces)
    if not ok or type(iface) ~= "string" then return nil end
    local okd, details = pcall(network.interfaceDetails, iface)
    if not okd or not details or not details.IPv4 or not details.IPv4.Addresses then
        return nil
    end
    local addr = details.IPv4.Addresses[1]
    if addr and #addr > 0 then return addr end
    return nil
end

local function bonjourHost()
    local names = host.names()
    if not names then return nil end
    for _, n in ipairs(names) do
        if type(n) == "string" and n:match("%.local$") then return n end
    end
    -- No name ended in .local; synthesize one from the first plain name.
    if names[1] and #names[1] > 0 then
        return names[1]:gsub("%.local$", "") .. ".local"
    end
    return nil
end

local function lanAddress()
    return bonjourHost() or ipv4Address() or "localhost"
end

function M.start(opts)
    local instance = { port = opts.port, assetsDir = opts.assetsDir }
    local handler, rebuildCache = routes.build({
        assetsDir = opts.assetsDir,
        version = opts.version,
    })
    instance.rebuildCache = rebuildCache

    local server = httpserver.new(false, false)
    server:setPort(opts.port)
    server:setCallback(function(method, path, headers, body)
        local ok, body2, status, hdrs = pcall(handler, method, path, headers, body)
        if not ok then
            log.error("handler error:", body2)
            return "server error", 500, { ["Content-Type"] = "text/plain" }
        end
        return body2, status, hdrs
    end)
    server:start()
    instance.server = server

    local addr = lanAddress()
    instance.url = string.format("http://%s:%d", addr, opts.port)
    log.info("running at " .. instance.url)
    return instance
end

function M.stop(instance)
    if not instance then return end
    if instance.server then
        instance.server:stop()
        instance.server = nil
    end
    screenshot.cleanup()
    instance.url = nil
end

return M
