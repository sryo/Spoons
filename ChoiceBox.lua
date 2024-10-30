local ChoiceBox = {}

ChoiceBox.choices = {}
ChoiceBox.filteredChoices = {}
ChoiceBox.selectedIndex = 1
ChoiceBox.window = nil
ChoiceBox.searchText = ""
ChoiceBox.keyEventTap = nil
ChoiceBox.mouseEventTap = nil
ChoiceBox.position = "topLeft"
ChoiceBox.growDirection = "down"
ChoiceBox.rowHotkeys = nil

-- Layout and style constants (now configurable)
ChoiceBox.config = {
    PADDING = 8,
    SEARCH_HEIGHT = 60,
    CHOICE_HEIGHT = 60,
    MIN_WIDTH = 80,  -- Minimum width for the ChoiceBox
    MAX_WIDTH = 800,  -- Maximum width for the ChoiceBox
    SEARCH_FONT_SIZE = 42,
    CHOICE_FONT_SIZE = 28,
    BG_COLOR = {black = 0.8, alpha = 0.8},
    TEXT_COLOR = {white = 1},
    HIGHLIGHT_COLOR = {red = .1, green = .3, blue = .9, alpha = 1},
    UNDERLINE_COLOR = {white = 1},
    MAX_VISIBLE_CHOICES = 9,
    WIDTH_MULTIPLIER = 0.46,
    DEFAULT_FONT = ".AppleSystemUIFont", -- or another system font like "Helvetica"
    PLACEHOLDER_TEXT = "Type to search..."
}

-- Debug logging function
local function log(message)
    print(os.date("%Y-%m-%d %H:%M:%S") .. ": " .. message)
end

-- Function to calculate average character width
local function calculateAverageCharWidth(fontSize)
    return fontSize * ChoiceBox.config.WIDTH_MULTIPLIER
end

-- Calculate and store average character widths
ChoiceBox.avgCharWidth = {
    search = calculateAverageCharWidth(ChoiceBox.config.SEARCH_FONT_SIZE),
    choice = calculateAverageCharWidth(ChoiceBox.config.CHOICE_FONT_SIZE)
}

-- Improved fuzzy matching function
local function fuzzyMatch(str, pattern)
    pattern = string.gsub(pattern, ".", function(c) return ".*" .. c:lower() end)
    return string.match(str:lower(), pattern)
end

-- Custom containsPoint function
local function containsPoint(rect, point)
    return point.x >= rect.x and point.x <= rect.x + rect.w and
           point.y >= rect.y and point.y <= rect.y + rect.h
end

function ChoiceBox.calculateWindowPosition(position, width, height)
    local screen = hs.screen.mainScreen()
    local screenFrame = screen:frame()
    local x, y

    if position == "topLeft" then
        x, y = screenFrame.x, screenFrame.y
        ChoiceBox.growDirection = "down"
    elseif position == "topRight" then
        x, y = screenFrame.x + screenFrame.w - width, screenFrame.y
        ChoiceBox.growDirection = "down"
    elseif position == "bottomLeft" then
        x, y = screenFrame.x, screenFrame.y + screenFrame.h - height
        ChoiceBox.growDirection = "up"
    elseif position == "bottomRight" then
        x, y = screenFrame.x + screenFrame.w - width, screenFrame.y + screenFrame.h - height
        ChoiceBox.growDirection = "up"
    else  -- Center by default
        x = screenFrame.x + (screenFrame.w - width) / 2
        y = screenFrame.y + (screenFrame.h - height) / 2
        ChoiceBox.growDirection = "down"
    end

    return {x = x, y = y, w = width, h = height}
end

function ChoiceBox.createWindow(position)
    if ChoiceBox.window then
        log("ChoiceBox window already exists, reusing")
        return ChoiceBox.window
    end
    
    log("Creating new ChoiceBox window")
    ChoiceBox.position = position or "center"
    local initialHeight = ChoiceBox.config.SEARCH_HEIGHT
    local windowFrame = ChoiceBox.calculateWindowPosition(ChoiceBox.position, ChoiceBox.config.MIN_WIDTH, initialHeight)

    local newWindow = hs.drawing.rectangle(windowFrame)
    newWindow:setFillColor({alpha = 0})
    newWindow:setStrokeColor({alpha = 0})
    newWindow:setBehavior(hs.drawing.windowBehaviors.canJoinAllSpaces)
    newWindow:setLevel(hs.drawing.windowLevels.modalPanel)

    return newWindow
end

function ChoiceBox.updateContent()
    if not ChoiceBox.window then
        log("ChoiceBox window is nil, creating")
        ChoiceBox.window = ChoiceBox.createWindow(ChoiceBox.position)
    end

    -- Clear existing content
    if ChoiceBox.window.contentDrawings then
        for _, drawing in ipairs(ChoiceBox.window.contentDrawings) do
            drawing:delete()
        end
    end
    ChoiceBox.window.contentDrawings = {}
    ChoiceBox.window.choiceRects = {}

    local windowFrame = ChoiceBox.window:frame()
    local maxWidth = ChoiceBox.config.MIN_WIDTH

    -- Function to get text size
    local function getTextSize(text, fontSize)
        return hs.drawing.getTextDrawingSize(text, {
            font = ChoiceBox.config.DEFAULT_FONT,
            size = fontSize
        })
    end

    -- Search box
    local searchText = ChoiceBox.searchText
    local displayText = searchText ~= "" and searchText or ChoiceBox.config.PLACEHOLDER_TEXT
    local searchTextSize = getTextSize(displayText, ChoiceBox.config.SEARCH_FONT_SIZE)
    local searchWidth = math.max(searchTextSize.w + ChoiceBox.config.PADDING * 2, ChoiceBox.config.MIN_WIDTH)
    searchWidth = math.min(searchWidth, ChoiceBox.config.MAX_WIDTH)
    maxWidth = math.max(maxWidth, searchWidth)

    local searchBox = hs.drawing.rectangle({
        x = windowFrame.x,
        y = windowFrame.y,
        w = searchWidth,
        h = ChoiceBox.config.SEARCH_HEIGHT
    })
    searchBox:setFillColor(ChoiceBox.config.BG_COLOR)
    searchBox:setStrokeColor({alpha = 0})
    searchBox:show()
    table.insert(ChoiceBox.window.contentDrawings, searchBox)

    local searchTextDrawing = hs.drawing.text({
        x = windowFrame.x + ChoiceBox.config.PADDING,
        y = windowFrame.y,
        w = searchWidth - (2 * ChoiceBox.config.PADDING),
        h = ChoiceBox.config.SEARCH_HEIGHT
    }, displayText)
    searchTextDrawing:setTextColor(searchText ~= "" and ChoiceBox.config.TEXT_COLOR or ChoiceBox.config.PLACEHOLDER_COLOR)
    searchTextDrawing:setTextFont(ChoiceBox.config.DEFAULT_FONT)
    searchTextDrawing:setTextSize(ChoiceBox.config.SEARCH_FONT_SIZE)
    searchTextDrawing:show()
    table.insert(ChoiceBox.window.contentDrawings, searchTextDrawing)

    -- Choices
    local totalHeight = ChoiceBox.config.SEARCH_HEIGHT
    local yOffset = ChoiceBox.growDirection == "down" and totalHeight or 0
    local visibleChoices = math.min(#ChoiceBox.filteredChoices, ChoiceBox.config.MAX_VISIBLE_CHOICES)

    for i = 1, visibleChoices do
        local choice = ChoiceBox.filteredChoices[i]
        local shortcutText = choice.shortcut or string.format("⌘%d", i)
        local fullText = shortcutText .. " " .. choice.text
        local choiceTextSize = getTextSize(fullText, ChoiceBox.config.CHOICE_FONT_SIZE)
        local choiceWidth = math.max(choiceTextSize.w + ChoiceBox.config.PADDING * 2, ChoiceBox.config.MIN_WIDTH)
        choiceWidth = math.min(choiceWidth, ChoiceBox.config.MAX_WIDTH)
        maxWidth = math.max(maxWidth, choiceWidth)

        local choiceRect = {
            x = windowFrame.x,
            y = windowFrame.y + yOffset,
            w = choiceWidth + ChoiceBox.config.PADDING,
            h = ChoiceBox.config.CHOICE_HEIGHT
        }

        local choiceBg = hs.drawing.rectangle(choiceRect)
        choiceBg:setFillColor(i == ChoiceBox.selectedIndex and ChoiceBox.config.HIGHLIGHT_COLOR or ChoiceBox.config.BG_COLOR)
        choiceBg:setStrokeColor({alpha = 0})
        choiceBg:show()
        table.insert(ChoiceBox.window.contentDrawings, choiceBg)

        local choiceText = hs.drawing.text({
            x = choiceRect.x + ChoiceBox.config.PADDING,
            y = choiceRect.y + ChoiceBox.config.PADDING,
            w = choiceWidth - (2 * ChoiceBox.config.PADDING),
            h = choiceRect.h + ChoiceBox.config.PADDING * 2
        }, fullText)
        choiceText:setTextColor(ChoiceBox.config.TEXT_COLOR)
        choiceText:setTextFont(ChoiceBox.config.DEFAULT_FONT)
        choiceText:setTextSize(ChoiceBox.config.CHOICE_FONT_SIZE)
        choiceText:show()
        table.insert(ChoiceBox.window.contentDrawings, choiceText)

        -- Underline matching text
        if ChoiceBox.searchText ~= "" then
            local matchStart, matchEnd = choice.text:lower():find(ChoiceBox.searchText:lower(), 1, true)
            if matchStart then
                local preMatchText = shortcutText .. " " .. choice.text:sub(1, matchStart - 1)
                local matchText = choice.text:sub(matchStart, matchEnd)
                local preMatchSize = getTextSize(preMatchText, ChoiceBox.config.CHOICE_FONT_SIZE)
                local matchSize = getTextSize(matchText, ChoiceBox.config.CHOICE_FONT_SIZE)
                local underlineRect = {
                    x = choiceRect.x + ChoiceBox.config.PADDING + preMatchSize.w,
                    y = choiceRect.y + ChoiceBox.config.CHOICE_HEIGHT / 2 + ChoiceBox.config.PADDING,
                    w = matchSize.w,
                    h = 4
                }
                local underline = hs.drawing.rectangle(underlineRect)
                underline:setFillColor(ChoiceBox.config.UNDERLINE_COLOR)
                underline:show()
                table.insert(ChoiceBox.window.contentDrawings, underline)
            end
        end

        -- Store the rectangle for this choice
        table.insert(ChoiceBox.window.choiceRects, choiceRect)

        if ChoiceBox.growDirection == "down" then
            yOffset = yOffset + ChoiceBox.config.CHOICE_HEIGHT
            totalHeight = totalHeight + ChoiceBox.config.CHOICE_HEIGHT
        else
            yOffset = yOffset - ChoiceBox.config.CHOICE_HEIGHT
            totalHeight = totalHeight + ChoiceBox.config.CHOICE_HEIGHT
        end
    end

    -- Adjust window size
    local newFrame = ChoiceBox.calculateWindowPosition(ChoiceBox.position, maxWidth, totalHeight)
    ChoiceBox.window:setFrame(newFrame)

    if ChoiceBox.growDirection == "up" then
        -- Adjust y positions of all elements
        for _, drawing in ipairs(ChoiceBox.window.contentDrawings) do
            local f = drawing:frame()
            f.y = f.y + (newFrame.h - windowFrame.h)
            drawing:setFrame(f)
        end
        for _, rect in ipairs(ChoiceBox.window.choiceRects) do
            rect.y = rect.y + (newFrame.h - windowFrame.h)
        end
    end

    ChoiceBox.window:show()
end

function ChoiceBox.filterChoices()
    log("Filtering choices")
    ChoiceBox.filteredChoices = {}
    for _, choice in ipairs(ChoiceBox.choices) do
        if ChoiceBox.searchText == "" or fuzzyMatch(choice.text, ChoiceBox.searchText) then
            table.insert(ChoiceBox.filteredChoices, choice)
        end
    end
    ChoiceBox.selectedIndex = 1
    ChoiceBox.updateContent()
    ChoiceBox.bindRowHotkeys()  -- Rebind hotkeys after filtering
end

function ChoiceBox.keyHandler(event)
    log("Key event received")
    local keyCode = event:getKeyCode()
    local flags = event:getFlags()
    local char = event:getCharacters()

    if keyCode == 53 then  -- ESC key
        ChoiceBox.close()
    elseif keyCode == 48 then  -- Tab key
        if #ChoiceBox.filteredChoices > 0 then
            ChoiceBox.searchText = ChoiceBox.filteredChoices[1].text
            ChoiceBox.filterChoices()  -- This will update the filtered results and the display
        end
    elseif keyCode == 125 then  -- Down arrow
        ChoiceBox.selectedIndex = math.min(ChoiceBox.selectedIndex + 1, #ChoiceBox.filteredChoices)
        ChoiceBox.updateContent()
    elseif keyCode == 126 then  -- Up arrow
        ChoiceBox.selectedIndex = math.max(ChoiceBox.selectedIndex - 1, 1)
        ChoiceBox.updateContent()
    elseif keyCode == 36 then  -- Return key
        local selectedChoice = ChoiceBox.filteredChoices[ChoiceBox.selectedIndex]
        if selectedChoice and selectedChoice.callback then
            ChoiceBox.close()
            selectedChoice.callback()
        end
    elseif keyCode == 51 then  -- Backspace
        ChoiceBox.searchText = string.sub(ChoiceBox.searchText, 1, -2)
        ChoiceBox.filterChoices()
    elseif char and #char > 0 then
        -- Allow typing in the ChoiceBox
        ChoiceBox.searchText = ChoiceBox.searchText .. char
        ChoiceBox.filterChoices()
    end
    
    return true  -- Prevent the event from propagating
end

function ChoiceBox.mouseHandler(event)
    local type = event:getType()
    if type == hs.eventtap.event.types.leftMouseDown then
        local mousePoint = hs.mouse.absolutePosition()
        if not ChoiceBox.window or not ChoiceBox.window:frame() then
            log("ChoiceBox window or frame is nil")
            return false
        end
        if not containsPoint(ChoiceBox.window:frame(), mousePoint) then
            log("Mouse click outside ChoiceBox window")
            ChoiceBox.close()
            return true
        else
            -- Check if the click is on a choice
            if ChoiceBox.window.choiceRects then
                for i, rect in ipairs(ChoiceBox.window.choiceRects) do
                    if containsPoint(rect, mousePoint) then
                        log("Choice clicked: " .. i)local selectedChoice = ChoiceBox.filteredChoices[i]
                        if selectedChoice and selectedChoice.callback then
                            ChoiceBox.close()
                            selectedChoice.callback()
                        end
                        return true
                    end
                end
            end
        end
    end
    return false
end

function ChoiceBox.bindRowHotkeys()
    if ChoiceBox.rowHotkeys then
        ChoiceBox.unbindRowHotkeys()
    end
    ChoiceBox.rowHotkeys = {}
    
    for i = 1, math.min(9, #ChoiceBox.filteredChoices) do
        local hotkey = hs.hotkey.bind({"cmd"}, tostring(i), function()
            local selectedChoice = ChoiceBox.filteredChoices[i]
            if selectedChoice and selectedChoice.callback then
                ChoiceBox.close()
                selectedChoice.callback()
            end
        end)
        table.insert(ChoiceBox.rowHotkeys, hotkey)
    end
end

function ChoiceBox.unbindRowHotkeys()
    if ChoiceBox.rowHotkeys then
        for _, hotkey in ipairs(ChoiceBox.rowHotkeys) do
            hotkey:delete()
        end
        ChoiceBox.rowHotkeys = nil
    end
end

function ChoiceBox.close()
    log("Closing ChoiceBox")
    if ChoiceBox.window then
        if ChoiceBox.window.contentDrawings then
            for _, drawing in ipairs(ChoiceBox.window.contentDrawings) do
                drawing:delete()
            end
        end
        ChoiceBox.window:hide()
        ChoiceBox.window:delete()
        ChoiceBox.window = nil
    end
    if ChoiceBox.keyEventTap then
        ChoiceBox.keyEventTap:stop()
        ChoiceBox.keyEventTap = nil
    end
    if ChoiceBox.mouseEventTap then
        ChoiceBox.mouseEventTap:stop()
        ChoiceBox.mouseEventTap = nil
    end
    ChoiceBox.unbindRowHotkeys()
    if ChoiceBox.onClose then
        ChoiceBox.onClose()
    end
end

function ChoiceBox.show(position)
    log("Showing ChoiceBox")
    if position then
        ChoiceBox.setPosition(position)
    end
    if not ChoiceBox.window then
        ChoiceBox.window = ChoiceBox.createWindow(ChoiceBox.position)
    end
    
    -- Reset search text and filtered choices
    ChoiceBox.searchText = ""
    ChoiceBox.filteredChoices = {}
    for _, choice in ipairs(ChoiceBox.choices) do
        table.insert(ChoiceBox.filteredChoices, choice)
    end
    ChoiceBox.selectedIndex = 1
    
    ChoiceBox.updateContent()
    
    if ChoiceBox.keyEventTap then
        ChoiceBox.keyEventTap:stop()
    end
    ChoiceBox.keyEventTap = hs.eventtap.new({hs.eventtap.event.types.keyDown}, ChoiceBox.keyHandler)
    ChoiceBox.keyEventTap:start()

    if ChoiceBox.mouseEventTap then
        ChoiceBox.mouseEventTap:stop()
    end
    ChoiceBox.mouseEventTap = hs.eventtap.new({hs.eventtap.event.types.leftMouseDown}, ChoiceBox.mouseHandler)
    ChoiceBox.mouseEventTap:start()

    -- Bind hotkeys for rows
    ChoiceBox.bindRowHotkeys()
end

function ChoiceBox.addChoice(text, callback, subText, shortcut)
    local id = tostring(math.random()):sub(3)  -- Simple unique ID generation
    table.insert(ChoiceBox.choices, {
        id = id,
        text = text,
        callback = callback,
        subText = subText,
        shortcut = shortcut
    })
    return id
end

function ChoiceBox.removeChoice(id)
    for i, choice in ipairs(ChoiceBox.choices) do
        if choice.id == id then
            table.remove(ChoiceBox.choices, i)
            break
        end
    end
    ChoiceBox.filterChoices()
end

function ChoiceBox.clearChoices()
    ChoiceBox.choices = {}
    ChoiceBox.filteredChoices = {}
    ChoiceBox.selectedIndex = 1
    ChoiceBox.updateContent()
end

function ChoiceBox.getChoiceCount()
    return #ChoiceBox.choices
end

function ChoiceBox.getSelectedChoice()
    if ChoiceBox.selectedIndex > 0 and ChoiceBox.selectedIndex <= #ChoiceBox.filteredChoices then
        return ChoiceBox.filteredChoices[ChoiceBox.selectedIndex]
    end
    return nil
end

function ChoiceBox.setPosition(position)
    ChoiceBox.position = position
    if ChoiceBox.window then
        local frame = ChoiceBox.calculateWindowPosition(position, ChoiceBox.window:frame().w, ChoiceBox.window:frame().h)
        ChoiceBox.window:setFrame(frame)
        ChoiceBox.updateContent()
    end
end

function ChoiceBox.isVisible()
    return ChoiceBox.window ~= nil and ChoiceBox.window:isVisible()
end

function ChoiceBox.updateChoices(newChoices)
    -- Update existing choices or add new ones
    for _, newChoice in ipairs(newChoices) do
        local existingIndex = ChoiceBox.findChoiceIndex(newChoice.id)
        if existingIndex then
            ChoiceBox.choices[existingIndex] = newChoice
        else
            table.insert(ChoiceBox.choices, newChoice)
        end
    end
    
    -- Remove choices that are no longer present
    local choicesToRemove = {}
    for i, choice in ipairs(ChoiceBox.choices) do
        if not ChoiceBox.findChoiceInList(choice.id, newChoices) then
            table.insert(choicesToRemove, i)
        end
    end
    for i = #choicesToRemove, 1, -1 do
        table.remove(ChoiceBox.choices, choicesToRemove[i])
    end
    
    ChoiceBox.filterChoices()
end

function ChoiceBox.findChoiceIndex(id)
    for i, choice in ipairs(ChoiceBox.choices) do
        if choice.id == id then
            return i
        end
    end
    return nil
end

function ChoiceBox.findChoiceInList(id, choiceList)
    for _, choice in ipairs(choiceList) do
        if choice.id == id then
            return true
        end
    end
    return false
end

log("ChoiceBox module loaded")

return ChoiceBox
