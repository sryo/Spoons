-- DigUp: remember everything you've seen on screen.
-- https://github.com/sryo/Spoons/blob/main/DigUp/ocr.lua - async OCR queue via Swift helper
local task = require("hs.task")
local json = require("hs.json")

local cfg = require("DigUp.config")
local db  = require("DigUp.db")

local ocr = {}
local queue = {}
local processing = false
local MAX_QUEUE = 100

-- Expanded menu items that are UI chrome noise
local menuItems = {
    File=1, Edit=1, View=1, Help=1, Window=1, Insert=1, Format=1, Tools=1,
    Go=1, Run=1, Selection=1, Terminal=1, Debug=1, Navigate=1, Product=1,
    Editor=1, Source=1, Refactor=1, Build=1, Analyze=1, Find=1, Table=1,
}

-- Day abbreviations
local dayAbbrevs = { Mon=1, Tue=1, Wed=1, Thu=1, Fri=1, Sat=1, Sun=1 }

-- Noise filter: reject single chars, whitespace, menu items, pure numbers,
-- timestamps, percentages, pure punctuation, day abbreviations, AM/PM
local function isNoise(text)
    if #text <= 1 then return true end
    if text:match("^%s*$") then return true end
    if menuItems[text] then return true end
    if text:match("^%d+$") then return true end           -- pure numbers
    if text:match("^%d+:%d+") then return true end         -- timestamps (12:34, 1:23:45)
    if text:match("^%d+%%$") then return true end          -- percentages (85%)
    if text:match("^%p+$") then return true end            -- pure punctuation
    if dayAbbrevs[text] then return true end
    if text == "AM" or text == "PM" then return true end

    -- User-defined noise patterns
    for _, pat in ipairs(cfg.noisePatterns or {}) do
        if text:match(pat) then return true end
    end

    return false
end

local function processNext()
    if #queue == 0 then
        processing = false
        return
    end
    processing = true
    local item = table.remove(queue, 1)
    local frameId, imagePath, clipboardText = item[1], item[2], item[3]

    local t = task.new(cfg.ocrHelperPath, function(exitCode, stdOut, stdErr)
        if exitCode == 0 and stdOut and #stdOut > 2 then
            local ok, results = pcall(json.decode, stdOut)
            if ok and results then
                -- Collect accepted texts for full_text concatenation
                local seen = {}
                local unique = {}

                for _, entry in ipairs(results) do
                    local text = entry.text or ""
                    local confidence = entry.confidence or 0
                    if confidence >= cfg.ocrConfidence and not isNoise(text) then
                        local ok2, err2 = pcall(db.insertFrameText,
                            frameId, text,
                            entry.x or 0, entry.y or 0,
                            entry.width or 0, entry.height or 0,
                            confidence
                        )
                        if not ok2 then
                            print("[DigUp] ocr: insertFrameText failed: " .. tostring(err2))
                        end

                        -- Dedup for full_text concat
                        if not seen[text] then
                            seen[text] = true
                            unique[#unique + 1] = text
                        end
                    end
                end

                -- Concatenate all unique OCR regions into full_text
                local fullText = table.concat(unique, "\n")
                if clipboardText and clipboardText ~= "" then
                    fullText = fullText .. "\n" .. clipboardText
                end
                if #fullText > 0 then
                    local ok3, err3 = pcall(db.updateFrameFullText, frameId, fullText)
                    if not ok3 then
                        print("[DigUp] ocr: updateFrameFullText failed for frame " .. tostring(frameId) .. ": " .. tostring(err3))
                    end
                end
            end
        else
            if exitCode ~= 0 then
                print("[DigUp] ocr: helper exited with code " .. tostring(exitCode) .. " for frame " .. tostring(frameId))
            end
        end
        processNext()
    end, {imagePath})

    if not t or not t:start() then
        print("[DigUp] ocr: failed to launch helper for frame " .. tostring(frameId))
        processNext()
    end
end

function ocr.enqueue(frameId, imagePath, clipboardText)
    queue[#queue + 1] = { frameId, imagePath, clipboardText }
    -- Drop oldest if queue too large
    while #queue > MAX_QUEUE do
        table.remove(queue, 1)
    end
    if not processing then
        processNext()
    end
end

function ocr.queueSize()
    return #queue
end

return ocr
