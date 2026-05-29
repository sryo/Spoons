-- Test-only peek at WindowScape.outline upvalues.
-- Usage from a test:
--   local i = dofile('/Users/.../tests/outline/_introspect.lua')
--   i.showing(), i.frame(), i.strokeColor(), i.radius(), i.refreshInterval(), ...

local L = dofile(hs.configdir .. "/tests/_test_lib.lua")

local function up(name)
    return L.deepUpvals(require("WindowScape.outline").draw)[name]
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
