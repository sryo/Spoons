-- DigUp: remember everything you've seen on screen.
-- https://github.com/sryo/Spoons/blob/main/DigUp/search.lua - chooser, screenshot viewer, timeline scrubber
local chooser     = require("hs.chooser")
local canvas      = require("hs.canvas")
local screen      = require("hs.screen")
local image       = require("hs.image")
local eventtap    = require("hs.eventtap")
local styledtext  = require("hs.styledtext")
local timer       = require("hs.timer")

local cfg = require("DigUp.config")
local db  = require("DigUp.db")
local capture = require("DigUp.capture")

local search = {}
local searchChooser
local viewer       -- canvas overlay
local viewerTap    -- eventtap for keyboard nav
local currentFrame -- currently displayed frame data
local activeQuery  -- search terms to highlight across all frames

-- Scrubber configuration
local THUMB_W = 160
local THUMB_H = 90
local THUMB_GAP = 12
local THUMBS_TO_SHOW = 7 -- Odd numbers work best so the active frame is centered

-- Format epoch timestamp to readable string
local function formatTime(ts)
    if not ts then return "" end
    return os.date("%Y-%m-%d %H:%M:%S", ts)
end

-- Extract a ~maxLen char snippet from text centered on the first occurrence of any query word.
local function extractSnippet(text, query, maxLen)
    -- Collapse whitespace for display
    text = text:gsub("%s+", " ")
    if #text <= maxLen then return text end

    local textLower = text:lower()
    local bestPos
    for w in (query or ""):lower():gmatch("%S+") do
        if #w >= 2 then
            local pos = textLower:find(w, 1, true)
            if pos and (not bestPos or pos < bestPos) then bestPos = pos end
        end
    end

    if not bestPos then
        return text:sub(1, maxLen - 3) .. "..."
    end

    local half = math.floor(maxLen / 2)
    local startPos = math.max(1, bestPos - half)
    local endPos = startPos + maxLen - 1
    if endPos > #text then
        endPos = #text
        startPos = math.max(1, endPos - maxLen + 1)
    end
    local snippet = text:sub(startPos, endPos)
    if startPos > 1 then snippet = "..." .. snippet end
    if endPos < #text then snippet = snippet .. "..." end
    return snippet
end

-- Build chooser choices from search results (now with duration/frameCount from event merging)
local function buildChoices(results, query)
    local choices = {}
    for _, r in ipairs(results) do
        local subText = r.appName or ""
        if r.windowTitle and r.windowTitle ~= "" then
            subText = subText .. " - " .. r.windowTitle
        end
        subText = subText .. "  |  " .. formatTime(r.timestamp)

        -- Show duration if event spans multiple frames
        if r.frameCount and r.frameCount > 1 then
            local dur = r.duration or 0
            subText = subText .. "  |  visible " .. math.floor(dur) .. "s (" .. r.frameCount .. " frames)"
        end

        -- Show a snippet of the matched text centered on the query words
        local displayText = r.matchedText
        if not displayText or displayText == "" then
            displayText = "(no text)"
        else
            displayText = extractSnippet(displayText, query, 120)
        end

        local thumbImg
        if r.screenshotPath then
            thumbImg = image.imageFromPath(r.screenshotPath)
        end

        choices[#choices + 1] = {
            text    = displayText,
            subText = subText,
            image   = thumbImg,
            frameId = r.frameId,
            path    = r.screenshotPath,
        }
    end
    return choices
end

-- Fullscreen viewer with thumbnail scrubber at the bottom
local function showViewer(frameData)
    if not frameData or not frameData.screenshotPath then return end
    -- Look up where the search text appears in this frame
    if activeQuery and not frameData.matchRegions then
        frameData.matchRegions = db.findMatchInFrame(frameData.id, activeQuery)
    end
    currentFrame = frameData

    local scr = screen.mainScreen()
    local f = scr:fullFrame()
    local img = image.imageFromPath(frameData.screenshotPath)
    if not img then return end

    if viewer then viewer:delete() end

    viewer = canvas.new(f)
    
    -- 1. Dark overlay background
    viewer[1] = {
        type  = "rectangle",
        frame = { x = 0, y = 0, w = f.w, h = f.h },
        fillColor = { red = 0, green = 0, blue = 0, alpha = 0.85 },
        action = "fill",
    }

    -- Screenshot, centered above scrubber area
    local imgSize = img:size()
    -- Leave bottom 150px for the timeline scrubber track
    local viewerH = f.h - 150
    local scale = math.min((f.w * 0.9) / imgSize.w, (viewerH * 0.9) / imgSize.h)
    local dw = imgSize.w * scale
    local dh = imgSize.h * scale
    local dx = (f.w - dw) / 2
    local dy = (viewerH - dh) / 2

    viewer[2] = {
        type  = "image",
        frame = { x = dx, y = dy, w = dw, h = dh },
        image = img,
        imageScaling = "scaleProportionally",
    }
    
    -- Highlight all OCR match regions
    if frameData.matchRegions and #frameData.matchRegions > 0 then
        local scaleX = dw / imgSize.w
        local scaleY = dh / imgSize.h

        for _, region in ipairs(frameData.matchRegions) do
            local hx = dx + (region.x * scaleX)
            local hy = dy + (region.y * scaleY)
            local hw = region.w * scaleX
            local hh = region.h * scaleY

            -- Pad the highlight box
            local padding = 6
            hx = hx - padding
            hy = hy - padding
            hw = hw + (padding * 2)
            hh = hh + (padding * 2)

            -- Clamp to image bounds
            if hx < dx then
                hw = hw - (dx - hx)
                hx = dx
            end
            if hy < dy then
                hh = hh - (dy - hy)
                hy = dy
            end
            if (hx + hw) > (dx + dw) then hw = (dx + dw) - hx end
            if (hy + hh) > (dy + dh) then hh = (dy + dh) - hy end

            viewer[#viewer + 1] = {
                type = "rectangle",
                action = "strokeAndFill",
                strokeColor = {red = 1.0, green = 0.9, blue = 0.2, alpha = 0.9},
                strokeWidth = 3,
                fillColor = {red = 1.0, green = 0.9, blue = 0.2, alpha = 0.25},
                frame = { x = hx, y = hy, w = hw, h = hh },
                roundedRectRadii = { xRadius = 6, yRadius = 6 }
            }
        end
    end

    -- Info bar
    local info = (frameData.appName or "") .. "  |  " .. (frameData.windowTitle or "") .. "  |  " .. formatTime(frameData.timestamp)
    viewer[#viewer + 1] = {
        type = "text",
        frame = { x = 0, y = dy + dh + 10, w = f.w, h = 30 },
        text = styledtext.new(info, {
            font  = { name = ".AppleSystemUIFont", size = 16 },
            color = { white = 0.9 },
            paragraphStyle = { alignment = "center" },
        }),
    }
    
    -- Grab frames around the current one for the scrubber strip
    local function getSurroundingFrames(centerId, halfCount)
        local frames = {}
        
        -- Older (left)
        local currId = centerId
        for i=1, halfCount do
            local prev = db.getAdjacentFrame(currId, -1)
            if prev then
                table.insert(frames, 1, prev)
                currId = prev.id
            else
                break
            end
        end
        
        table.insert(frames, frameData) -- Middle frame
        
        -- Newer (right)
        currId = centerId
        for i=1, halfCount do
            local nxt = db.getAdjacentFrame(currId, 1)
            if nxt then
                table.insert(frames, nxt)
                currId = nxt.id
            else
                break
            end
        end
        return frames
    end

    local halfTarget = math.floor(THUMBS_TO_SHOW / 2)
    local timelineFrames = getSurroundingFrames(frameData.id, halfTarget)
    
    local totalScrubWidth = (#timelineFrames * THUMB_W) + ((#timelineFrames - 1) * THUMB_GAP)
    local startX = (f.w - totalScrubWidth) / 2
    local scrubberY = f.h - THUMB_H - 24
    
    -- Draw each thumbnail
    for i, frame in ipairs(timelineFrames) do
        local isCenter = (frame.id == frameData.id)
        local xPos = startX + ((i - 1) * (THUMB_W + THUMB_GAP))
        
        -- Background / Border for thumbnail
        local borderColor = isCenter and {red=0.2, green=0.5, blue=0.9, alpha=1.0} or {white=0.3, alpha=1.0}
        
        viewer[#viewer + 1] = {
            id = "thumbBg_" .. frame.id,
            trackMouseUp = true,
            type = "rectangle",
            action = "strokeAndFill",
            strokeColor = borderColor,
            strokeWidth = isCenter and 3 or 1,
            fillColor = {white = 0.1, alpha = 0.8},
            frame = { x = xPos - 2, y = scrubberY - 2, w = THUMB_W + 4, h = THUMB_H + 4 },
            roundedRectRadii = { xRadius = 4, yRadius = 4 }
        }
        
        -- Prefer _thumb.jpg, fall back to full image
        local tImg
        if frame.screenshotPath then
            local thumbPath = frame.screenshotPath:gsub("%.jpg$", "_thumb.jpg")
            tImg = image.imageFromPath(thumbPath) or image.imageFromPath(frame.screenshotPath)
        end
        
        if tImg then
            viewer[#viewer + 1] = {
                id = "thumbImg_" .. frame.id,
                trackMouseUp = true,
                type = "image",
                frame = { x = xPos, y = scrubberY, w = THUMB_W, h = THUMB_H },
                image = tImg,
                imageScaling = "scaleProportionally",
                imageAlpha = isCenter and 1.0 or 0.5
            }
        end
        
        -- Timestamp label
        viewer[#viewer + 1] = {
            id = "thumbText_" .. frame.id,
            trackMouseUp = true,
            type = "text",
            frame = { x = xPos, y = scrubberY + THUMB_H + 4, w = THUMB_W, h = 20 },
            text = styledtext.new(os.date("%H:%M:%S", frame.timestamp), {
                font  = { name = ".AppleSystemUIFont", size = 10 },
                color = { white = isCenter and 0.9 or 0.5 },
                paragraphStyle = { alignment = "center" },
            }),
        }
    end

    viewer:mouseCallback(function(canvas, event, id, x, y)
        if event == "mouseUp" and type(id) == "string" then
            local frameIdStr = id:match("thumb%a+_(%d+)")
            if frameIdStr then
                local frameId = tonumber(frameIdStr)
                if frameId and frameId ~= currentFrame.id then
                    local newFrame = db.getFrameById(frameId)
                    if newFrame then
                        showViewer(newFrame)
                    end
                end
            end
        end
    end)

    viewer:level(canvas.windowLevels.overlay)
    viewer:behavior(canvas.windowBehaviors.canJoinAllSpaces)
    viewer:clickActivating(false)
    viewer:show()

    -- Keyboard navigation
    if viewerTap then viewerTap:stop() end
    viewerTap = eventtap.new({ eventtap.event.types.keyDown }, function(e)
        local key = e:getKeyCode()
        -- Escape = 53, Left = 123, Right = 124
        if key == 53 then
            search.hideViewer()
            return true
        elseif key == 123 then
            local prev = db.getAdjacentFrame(currentFrame.id, -1)
            if prev then showViewer(prev) end
            return true
        elseif key == 124 then
            local nxt = db.getAdjacentFrame(currentFrame.id, 1)
            if nxt then showViewer(nxt) end
            return true
        end
        return false
    end)
    viewerTap:start()
end

function search.hideViewer()
    if viewer then
        viewer:delete()
        viewer = nil
    end
    if viewerTap then
        viewerTap:stop()
        viewerTap = nil
    end
    currentFrame = nil
    activeQuery = nil
    capture.resume()
end

function search.show()
    capture.pause()
    if searchChooser then searchChooser:delete() end

    searchChooser = chooser.new(function(choice)
        if not choice then 
            capture.resume()
            return 
        end
        local frameData = db.getFrameById(choice.frameId)
        if frameData then
            activeQuery = searchChooser and searchChooser:query() or nil
            showViewer(frameData)
        else
            capture.resume()
        end
    end)

    searchChooser:searchSubText(true)
    searchChooser:placeholderText("Type what you remember...")
    searchChooser:rows(10)
    searchChooser:queryChangedCallback(function(query)
        if not query or query == "" then
            searchChooser:choices({})
            return
        end
        -- Debounce with a small delay
        timer.doAfter(0.15, function()
            if not searchChooser then return end
            local ok, currentQuery = pcall(function() return searchChooser:query() end)
            if ok and currentQuery == query then
                local results = db.search(query, 50)
                if searchChooser then
                    searchChooser:choices(buildChoices(results, query))
                end
            end
        end)
    end)

    searchChooser:show()
end

return search
