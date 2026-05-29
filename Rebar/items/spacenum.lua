-- perScreen because each display has its own Spaces in macOS.

local M = {
    id        = "spacenum",
    side      = "left",
    order     = 50,
    perScreen = true,
    interval  = 0,
}

local watcher

function M.update(scr)
    local ok, allSpaces = pcall(hs.spaces.allSpaces)
    if not ok or not allSpaces then return "" end
    local screenSpaces = allSpaces[scr:getUUID()]
    if not screenSpaces then return "" end
    local active = pcall(hs.spaces.activeSpaces) and hs.spaces.activeSpaces() or {}
    local activeID = active[scr:getUUID()]
    if not activeID then return "" end
    for i, id in ipairs(screenSpaces) do
        if id == activeID then
            local dots = {}
            for j = 1, #screenSpaces do
                dots[j] = (j == i) and "●" or "○"
            end
            return table.concat(dots, " ")
        end
    end
    return ""
end

function M.setup(refresh)
    watcher = hs.spaces.watcher.new(function() refresh() end)
    watcher:start()
end

function M.teardown()
    if watcher then watcher:stop(); watcher = nil end
end

return M
