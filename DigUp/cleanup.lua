-- DigUp: remember everything you've seen on screen.
-- https://github.com/sryo/Spoons/blob/main/DigUp/cleanup.lua - prune old screenshots by age and disk usage
local fs    = require("hs.fs")
local timer = require("hs.timer")
local cfg   = require("DigUp.config")
local db    = require("DigUp.db")

local cleanup = {}
local cleanupTimer

-- Calculate total size of a directory in bytes (recursive)
local function getDirSize(dir)
    local total = 0
    local iter, dirObj = fs.dir(dir)
    if not iter then return 0 end
    for file in iter, dirObj do
        if file ~= "." and file ~= ".." then
            local path = dir .. "/" .. file
            local attr = fs.attributes(path)
            if attr then
                if attr.mode == "directory" then
                    total = total + getDirSize(path)
                else
                    total = total + (attr.size or 0)
                end
            end
        end
    end
    return total
end

function cleanup.run()
    -- 1. Time-based retention
    if cfg.retentionDays and type(cfg.retentionDays) == "number" and cfg.retentionDays > 0 then
        local cutoff = os.time() - (cfg.retentionDays * 86400)
        local paths = db.deleteOldFrames(cutoff)
        
        local deletedCount = 0
        for _, path in ipairs(paths) do
            if fs.attributes(path) then
                os.remove(path)
                -- Also remove thumbnail if it exists
                local thumbPath = path:gsub("%.jpg$", "_thumb.jpg")
                if fs.attributes(thumbPath) then os.remove(thumbPath) end
                deletedCount = deletedCount + 1
            end
        end
        
        if #paths > 0 then
            print(string.format("[DigUp] cleanup: removed %d screenshots (%d DB rows) older than %d days", deletedCount, #paths, cfg.retentionDays))
        end
    end
    
    -- 2. Size-based pruning
    if cfg.maxStorageGB and type(cfg.maxStorageGB) == "number" and cfg.maxStorageGB > 0 then
        local maxBytes = cfg.maxStorageGB * 1024 * 1024 * 1024
        local currentSize = getDirSize(cfg.screenshotDir)
        
        if currentSize > maxBytes then
            print(string.format("[DigUp] cleanup: %.1f GB used, limit is %.1f GB, pruning oldest",
                currentSize / (1024*1024*1024), cfg.maxStorageGB))
            
            local totalDeleted = 0
            local maxIterations = 200
            local iteration = 0
            -- Delete in batches of 50 until under the limit
            while currentSize > maxBytes and iteration < maxIterations do
                iteration = iteration + 1
                local oldest = db.getOldestFrames(50)
                if #oldest == 0 then break end
                
                for _, frame in ipairs(oldest) do
                    local path = frame.screenshotPath
                    if path and fs.attributes(path) then
                        local attr = fs.attributes(path)
                        currentSize = currentSize - (attr.size or 0)
                        os.remove(path)
                        -- Also remove thumbnail
                        local thumbPath = path:gsub("%.jpg$", "_thumb.jpg")
                        if fs.attributes(thumbPath) then
                            local tAttr = fs.attributes(thumbPath)
                            currentSize = currentSize - (tAttr.size or 0)
                            os.remove(thumbPath)
                        end
                    end
                    totalDeleted = totalDeleted + 1
                end
                
                -- Delete from DB
                if #oldest > 0 then
                    local lastTimestamp = oldest[#oldest].timestamp
                    db.deleteOldFrames(lastTimestamp + 1)
                end
            end
            
            if totalDeleted > 0 then
                print(string.format("[DigUp] cleanup: pruned %d frames, now %.1f GB (limit %.1f GB)",
                    totalDeleted, currentSize / (1024*1024*1024), cfg.maxStorageGB))
            end
        end
    end
end

function cleanup.start()
    -- Run once shortly after startup
    timer.doAfter(15, cleanup.run)
    
    -- Repeat every 12 hours
    cleanupTimer = timer.doEvery(43200, cleanup.run)
end

function cleanup.stop()
    if cleanupTimer then
        cleanupTimer:stop()
        cleanupTimer = nil
    end
end

return cleanup
