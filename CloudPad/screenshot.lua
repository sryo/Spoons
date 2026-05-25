local mouse = require("hs.mouse")
local screen = require("hs.screen")
local log = require("CloudPad.log")

local M = {}

M.previewWidth = 480
local tmpPath = nil

local function tmpFile()
    if not tmpPath then
        tmpPath = os.tmpname() .. ".jpg"
    end
    return tmpPath
end

function M.cleanup()
    if tmpPath then
        os.remove(tmpPath)
        tmpPath = nil
    end
end

function M.capture()
    local pos = mouse.absolutePosition()
    local target = mouse.getCurrentScreen() or screen.mainScreen()
    if not target then return nil end

    local snap = target:snapshot()
    if not snap then return nil end

    local size = snap:size()
    local ratio = size.h / size.w
    snap:setSize({ w = M.previewWidth, h = math.floor(M.previewWidth * ratio) })

    local frame = target:fullFrame()
    local pctX = (pos.x - frame.x) / frame.w
    local pctY = (pos.y - frame.y) / frame.h

    local path = tmpFile()
    local ok = snap:saveToFile(path)
    if not ok then
        log.warn("snapshot save failed")
        return nil
    end
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()

    return data, pctX, pctY
end

return M
