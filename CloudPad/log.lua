local M = {}

local PREFIX = "[CloudPad] "
M.level = "info"

local levels = { debug = 1, info = 2, warn = 3, error = 4 }

local function emit(lvl, ...)
    if levels[lvl] < levels[M.level] then return end
    local parts = { ... }
    for i, v in ipairs(parts) do parts[i] = tostring(v) end
    print(PREFIX .. table.concat(parts, " "))
end

function M.debug(...) emit("debug", ...) end
function M.info(...)  emit("info",  ...) end
function M.warn(...)  emit("warn",  ...) end
function M.error(...) emit("error", ...) end

return M
