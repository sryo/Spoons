-- Per-source frequency + recency learning, persisted via hs.settings.
-- Schema: data[sourceId][itemId] = { count, lastUsed }

local M = {}

local settings = hs.settings
local KEY      = "paletteUsageData"
local data     = nil

local cfg = {
    daysToRemember = 30,
}

local function load()
    if data then return end
    data = settings.get(KEY) or {}
end

local function save()
    settings.set(KEY, data)
end

function M.record(sourceId, itemId)
    if not sourceId or not itemId then return end
    load()
    data[sourceId] = data[sourceId] or {}
    data[sourceId][itemId] = data[sourceId][itemId] or { count = 0, lastUsed = 0 }
    data[sourceId][itemId].count    = data[sourceId][itemId].count + 1
    data[sourceId][itemId].lastUsed = os.time()
    save()
end

function M.score(sourceId, itemId)
    load()
    local entry = data[sourceId] and data[sourceId][itemId]
    if not entry then return 0 end
    local recency = os.time() - entry.lastUsed
    return entry.count * 1000000 / (recency + 1)
end

function M.forget(sourceId, itemId)
    if not sourceId or not itemId then return end
    load()
    if data[sourceId] and data[sourceId][itemId] then
        data[sourceId][itemId] = nil
        if next(data[sourceId]) == nil then data[sourceId] = nil end
        save()
    end
end

-- Returns the live { itemId = entry } table for a given source. Mutating it
-- won't persist; treat as read-only.
function M.entries(sourceId)
    load()
    return data[sourceId] or {}
end

function M.cleanup()
    load()
    local cutoff = os.time() - (cfg.daysToRemember * 86400)
    local changed = false
    for src, items in pairs(data) do
        for id, entry in pairs(items) do
            if entry.lastUsed < cutoff then
                items[id] = nil
                changed = true
            end
        end
        if next(items) == nil then
            data[src] = nil
            changed = true
        end
    end
    if changed then save() end
end

function M.init()
    load()
    M.cleanup()
end

return M
