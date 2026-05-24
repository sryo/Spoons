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

-- Apply pseudotiling via callback
local function applyPseudoTiling(win, tileFrame)
    if callbacks.applyPseudoTiling then
        return callbacks.applyPseudoTiling(win, tileFrame)
    end
    return tileFrame
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

-- Dwindle layout: binary split each new window into smallest tile
local function tileDwindle(screenFrame, windows, horizontal)
    if #windows == 0 then return end

    local frames = {}
    frames[1] = { x = screenFrame.x, y = screenFrame.y, w = screenFrame.w, h = screenFrame.h }

    for i = 2, #windows do
        local lastFrame = frames[i - 1]
        local splitHorizontal = (i % 2 == 0) == horizontal

        if splitHorizontal then
            local halfW = math.floor((lastFrame.w - cfg.tileGap) / 2)
            frames[i - 1] = { x = lastFrame.x, y = lastFrame.y, w = halfW, h = lastFrame.h }
            frames[i] = {
                x = lastFrame.x + halfW + cfg.tileGap,
                y = lastFrame.y,
                w = lastFrame.w - halfW - cfg.tileGap,
                h = lastFrame.h
            }
        else
            local halfH = math.floor((lastFrame.h - cfg.tileGap) / 2)
            frames[i - 1] = { x = lastFrame.x, y = lastFrame.y, w = lastFrame.w, h = halfH }
            frames[i] = {
                x = lastFrame.x,
                y = lastFrame.y + halfH + cfg.tileGap,
                w = lastFrame.w,
                h = lastFrame.h - halfH - cfg.tileGap
            }
        end
    end

    for i, win in ipairs(windows) do
        local finalFrame = applyPseudoTiling(win, frames[i])
        animatedSetFrame(win, finalFrame)
    end
end

-- Master-stack layout: one master window + stack of secondary windows
local function tileMaster(screenFrame, windows, horizontal)
    if #windows == 0 then return end

    local masterWin = windows[1]
    local stackWins = {}
    for i = 2, #windows do
        table.insert(stackWins, windows[i])
    end

    local masterFrame, stackFrame
    local masterLeft = (cfg.masterPosition == "left") or (cfg.masterPosition == "top")

    if horizontal then
        local masterW = math.floor(screenFrame.w * cfg.masterRatio)
        local stackW = screenFrame.w - masterW - cfg.tileGap

        if masterLeft then
            masterFrame = { x = screenFrame.x, y = screenFrame.y, w = masterW, h = screenFrame.h }
            stackFrame = { x = screenFrame.x + masterW + cfg.tileGap, y = screenFrame.y, w = stackW, h = screenFrame.h }
        else
            stackFrame = { x = screenFrame.x, y = screenFrame.y, w = stackW, h = screenFrame.h }
            masterFrame = { x = screenFrame.x + stackW + cfg.tileGap, y = screenFrame.y, w = masterW, h = screenFrame.h }
        end
    else
        local masterH = math.floor(screenFrame.h * cfg.masterRatio)
        local stackH = screenFrame.h - masterH - cfg.tileGap

        if masterLeft then
            masterFrame = { x = screenFrame.x, y = screenFrame.y, w = screenFrame.w, h = masterH }
            stackFrame = { x = screenFrame.x, y = screenFrame.y + masterH + cfg.tileGap, w = screenFrame.w, h = stackH }
        else
            stackFrame = { x = screenFrame.x, y = screenFrame.y, w = screenFrame.w, h = stackH }
            masterFrame = { x = screenFrame.x, y = screenFrame.y + stackH + cfg.tileGap, w = screenFrame.w, h = masterH }
        end
    end

    local finalMasterFrame = applyPseudoTiling(masterWin, masterFrame)
    animatedSetFrame(masterWin, finalMasterFrame)

    if #stackWins > 0 then
        if horizontal then
            local stackItemH = math.floor((stackFrame.h - (#stackWins - 1) * cfg.tileGap) / #stackWins)
            local y = stackFrame.y
            for i, win in ipairs(stackWins) do
                local h = (i == #stackWins) and (stackFrame.y + stackFrame.h - y) or stackItemH
                local frame = { x = stackFrame.x, y = y, w = stackFrame.w, h = h }
                local finalFrame = applyPseudoTiling(win, frame)
                animatedSetFrame(win, finalFrame)
                y = y + h + cfg.tileGap
            end
        else
            local stackItemW = math.floor((stackFrame.w - (#stackWins - 1) * cfg.tileGap) / #stackWins)
            local x = stackFrame.x
            for i, win in ipairs(stackWins) do
                local w = (i == #stackWins) and (stackFrame.x + stackFrame.w - x) or stackItemW
                local frame = { x = x, y = stackFrame.y, w = w, h = stackFrame.h }
                local finalFrame = applyPseudoTiling(win, frame)
                animatedSetFrame(win, finalFrame)
                x = x + w + cfg.tileGap
            end
        end
    end
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
                local finalFrame = applyPseudoTiling(win, tileFrame)
                animatedSetFrame(win, finalFrame)
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
                local finalFrame = applyPseudoTiling(win, tileFrame)
                animatedSetFrame(win, finalFrame)
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
    tileDwindle = tileDwindle,
    tileMaster = tileMaster,
    tileWeighted = tileWeighted,
}
