-- Window tiling layout algorithms

local cfg
local callbacks = {}

local function init(config, cbs)
    cfg = config
    callbacks = cbs or {}
end

-- Get window weight via callback
local function getWindowWeight(win)
    if callbacks.getWindowWeight then
        return callbacks.getWindowWeight(win)
    end
    return 1.0
end

-- Animate window frame via callback
local function animatedSetFrame(win, frame)
    if callbacks.animatedSetFrame then
        callbacks.animatedSetFrame(win, frame)
    end
end

-- Distribute space according to weights
local function distributeWeighted(total, gaps, windows)
    if #windows == 0 then return {} end

    local totalWeight = 0
    for _, win in ipairs(windows) do
        totalWeight = totalWeight + getWindowWeight(win)
    end

    local avail = total - math.max(#windows - 1, 0) * gaps
    local sizes = {}
    local allocated = 0

    for i, win in ipairs(windows) do
        local weight = getWindowWeight(win)
        if i == #windows then
            sizes[i] = avail - allocated
        else
            sizes[i] = math.floor(avail * weight / totalWeight)
            allocated = allocated + sizes[i]
        end
    end

    return sizes
end

-- Equal distribution for collapsed windows
local function distributeEven(total, gaps, count)
    if count <= 0 then return 0, 0 end
    local avail = total - math.max(count - 1, 0) * gaps
    local base  = math.floor(avail / count)
    local rem   = avail - base * count
    return base, rem
end

-- Weighted layout with collapsed window handling
local function tileWeighted(screenFrame, nonCollapsedWins, collapsedWins, horizontal)
    local numCollapsed = #collapsedWins
    local numNonCollapsed = #nonCollapsedWins

    if horizontal then
        local collapsedAreaHeight = (numCollapsed > 0) and (cfg.collapsedWindowHeight + cfg.tileGap) or 0
        local mainAreaHeight = screenFrame.h - collapsedAreaHeight

        if numNonCollapsed > 0 then
            local widths = distributeWeighted(screenFrame.w, cfg.tileGap, nonCollapsedWins)
            local x = screenFrame.x
            for i, win in ipairs(nonCollapsedWins) do
                local tileFrame = { x = x, y = screenFrame.y, w = widths[i], h = mainAreaHeight }
                animatedSetFrame(win, tileFrame)
                x = x + widths[i] + cfg.tileGap
            end
        end

        if numCollapsed > 0 then
            local baseW, remW = distributeEven(screenFrame.w, cfg.tileGap, numCollapsed)
            local collapsedX = screenFrame.x
            local collapsedY = screenFrame.y + mainAreaHeight
            for i, win in ipairs(collapsedWins) do
                local w = baseW + ((i == numCollapsed) and remW or 0)
                local newFrame = { x = collapsedX, y = collapsedY, w = w, h = cfg.collapsedWindowHeight }
                animatedSetFrame(win, newFrame)
                collapsedX = collapsedX + w + cfg.tileGap
            end
        end
    else
        local collapsedAreaHeight = 0
        if numCollapsed > 0 then
            collapsedAreaHeight = (cfg.collapsedWindowHeight + cfg.tileGap) * numCollapsed - cfg.tileGap
        end
        local mainAreaHeight = screenFrame.h - collapsedAreaHeight

        if numNonCollapsed > 0 then
            local heights = distributeWeighted(mainAreaHeight, cfg.tileGap, nonCollapsedWins)
            local y = screenFrame.y
            for i, win in ipairs(nonCollapsedWins) do
                local tileFrame = { x = screenFrame.x, y = y, w = screenFrame.w, h = heights[i] }
                animatedSetFrame(win, tileFrame)
                y = y + heights[i] + cfg.tileGap
            end
        end

        if numCollapsed > 0 then
            local collapsedX = screenFrame.x
            local collapsedY = screenFrame.y + mainAreaHeight
            for _, win in ipairs(collapsedWins) do
                local newFrame = { x = collapsedX, y = collapsedY, w = screenFrame.w, h = cfg.collapsedWindowHeight }
                animatedSetFrame(win, newFrame)
                collapsedY = collapsedY + cfg.collapsedWindowHeight + cfg.tileGap
            end
        end
    end
end

return {
    init = init,
    distributeWeighted = distributeWeighted,
    distributeEven = distributeEven,
    tileWeighted = tileWeighted,
}
