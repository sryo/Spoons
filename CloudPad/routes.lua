local fs = require("hs.fs")
local protocol = require("CloudPad.protocol")
local input = require("CloudPad.input")
local screenshot = require("CloudPad.screenshot")
local log = require("CloudPad.log")

local M = {}

local CORS = {
    ["Access-Control-Allow-Origin"] = "*",
    ["Access-Control-Allow-Headers"] = "Content-Type",
    ["Access-Control-Allow-Methods"] = "POST, GET, OPTIONS",
}

local function mergeHeaders(h)
    local out = {}
    for k, v in pairs(CORS) do out[k] = v end
    if h then for k, v in pairs(h) do out[k] = v end end
    return out
end

local mime = {
    html = "text/html; charset=utf-8",
    css  = "text/css; charset=utf-8",
    js   = "application/javascript; charset=utf-8",
    json = "application/json; charset=utf-8",
    png  = "image/png",
    jpg  = "image/jpeg",
    svg  = "image/svg+xml",
}

local function extOf(path)
    local e = path:match("%.([%w]+)$")
    return e and e:lower() or nil
end

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

local function loadAssets(dir)
    local cache = {}
    local function walk(prefix, base)
        local iter, dirObj = fs.dir(base)
        if not iter then return end
        for name in function() return iter(dirObj) end do
            if name ~= "." and name ~= ".." then
                local full = base .. "/" .. name
                local attr = fs.attributes(full)
                if attr and attr.mode == "directory" then
                    walk(prefix .. "/" .. name, full)
                else
                    local data = readFile(full)
                    if data then
                        local ext = extOf(name) or "bin"
                        cache[prefix .. "/" .. name] = {
                            body = data,
                            contentType = mime[ext] or "application/octet-stream",
                        }
                    end
                end
            end
        end
    end
    walk("", dir)
    return cache
end

function M.build(opts)
    local cache = loadAssets(opts.assetsDir)
    local version = opts.version or "1"

    local function asset(path)
        local hit = cache[path]
        if not hit then return nil end
        return hit.body, 200, mergeHeaders({ ["Content-Type"] = hit.contentType })
    end

    local handlers = {}

    handlers["GET /"] = function() return asset("/index.html") end

    handlers["GET /health"] = function()
        local body = protocol.encode({ ok = true, version = version })
        return body, 200, mergeHeaders({ ["Content-Type"] = mime.json })
    end

    handlers["GET /screenshot"] = function()
        local data, px, py = screenshot.capture()
        if not data then
            return "screen error", 500, mergeHeaders({ ["Content-Type"] = "text/plain" })
        end
        return data, 200, mergeHeaders({
            ["Content-Type"] = mime.jpg,
            ["Cache-Control"] = "no-store",
            ["X-Cursor-Pct-X"] = tostring(px or 0),
            ["X-Cursor-Pct-Y"] = tostring(py or 0),
        })
    end

    handlers["POST /events"] = function(body)
        local data, err = protocol.decodeBatch(body)
        if not data then
            log.debug("bad batch:", err)
            return protocol.encode({ ok = false, error = err }), 400,
                mergeHeaders({ ["Content-Type"] = mime.json })
        end
        local n = input.drain(data.events)
        return protocol.encode({ ok = true, drained = n }), 200,
            mergeHeaders({ ["Content-Type"] = mime.json })
    end

    return function(method, path, headers, body)
        if method == "OPTIONS" then
            return "", 200, mergeHeaders({})
        end
        local key = method .. " " .. path
        local h = handlers[key]
        if h then return h(body) end
        if method == "GET" then
            local body2, status, hdrs = asset(path)
            if body2 then return body2, status, hdrs end
        end
        return "not found", 404, mergeHeaders({ ["Content-Type"] = "text/plain" })
    end, function() cache = loadAssets(opts.assetsDir) end
end

return M
