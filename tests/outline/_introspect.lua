-- Test-only peek at WindowScape.outline upvalues.
-- Usage from a test:
--   local i = dofile('/Users/.../tests/outline/_introspect.lua')
--   i.showing(), i.frame(), i.strokeColor(), i.radius(), i.refreshInterval(), ...

local function up(name)
    -- Walk every exported function. Upvalues are by-reference cells: any
    -- function that closes over `name` returns its current value. Different
    -- exports close over different subsets — `draw` has trackedWinId/
    -- trackedColor, `stopRefresh` has refreshTimer/refreshInterval,
    -- `cleanup` has appliedCornerRadius, etc. — so we try them all.
    local outline = require("WindowScape.outline")
    for _, fn in pairs(outline) do
        if type(fn) == "function" then
            local i = 1
            while true do
                local n, v = debug.getupvalue(fn, i)
                if not n then break end
                if n == name then return v end
                i = i + 1
            end
        end
    end
    return nil
end

local M = {}

function M.canvas() return up("activeOutline") end
function M.refreshInterval() return up("refreshInterval") end
function M.refreshTimerRunning()
    local t = up("refreshTimer")
    return t and t:running() or false
end
function M.trackedColor() return up("trackedColor") end
function M.appliedCornerRadius() return up("appliedCornerRadius") end

function M.showing()
    local c = M.canvas()
    return c and c:isShowing() or false
end

function M.frame()
    local c = M.canvas()
    return c and c:frame() or nil
end

function M.strokeColor()
    local c = M.canvas()
    if not c or not c[1] then return nil end
    return c[1].strokeColor
end

function M.radius()
    local c = M.canvas()
    if not c or not c[1] then return nil end
    local r = c[1].roundedRectRadii
    return r and r.xRadius or nil
end

return M
