-- Shared helpers for unit-sim tests under tests/<module>/_<feature>_sim.lua.
-- Sims load this via:
--     local L = dofile(hs.configdir .. "/tests/_test_lib.lua")
-- and use L.deepUpvals / L.assertEq / L.assertNear.

local M = {}

-- Walk a function's upvalues recursively. Closures of inner functions reachable
-- via function-valued upvalues are also harvested, so module-locals used only
-- through nested helpers are still found. `seen` prevents cycles.
function M.deepUpvals(fn)
    local t, seen = {}, {}
    local function walk(f)
        if type(f) ~= "function" or seen[f] then return end
        seen[f] = true
        local i = 1
        while true do
            local n, v = debug.getupvalue(f, i)
            if not n then break end
            if t[n] == nil then t[n] = v end
            if type(v) == "function" then walk(v) end
            i = i + 1
        end
    end
    walk(fn)
    return t
end

function M.assertEq(got, want, msg)
    if got ~= want then
        error(string.format("%s: got %s, want %s", msg or "assertEq", tostring(got), tostring(want)), 2)
    end
end

function M.assertNear(got, want, tol, msg)
    if math.abs(got - want) > tol then
        error(string.format("%s: got %s, want ~%s (±%s)",
            msg or "assertNear", tostring(got), tostring(want), tostring(tol)), 2)
    end
end

return M
