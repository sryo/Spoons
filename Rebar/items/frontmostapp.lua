local M = {
    id       = "frontmostapp",
    side     = "left",
    order    = 10,
    interval = 0,
}

local watcher

function M.update()
    local app = hs.application.frontmostApplication()
    return app and app:name() or ""
end

function M.setup(refresh)
    watcher = hs.application.watcher.new(function(_name, event)
        if event == hs.application.watcher.activated then refresh() end
    end)
    watcher:start()
end

function M.teardown()
    if watcher then watcher:stop(); watcher = nil end
end

return M
