local ChoiceBox = {}

ChoiceBox.choices = {}
ChoiceBox.filteredChoices = {}
ChoiceBox.selectedIndex = 1
ChoiceBox.window = nil
ChoiceBox.searchText = ""
ChoiceBox.keyEventTap = nil
ChoiceBox.mouseEventTap = nil

-- Debug logging function
local function log(message)
    print(os.date("%Y-%m-%d %H:%M:%S") .. ": " .. message)
end

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

function ChoiceBox.createWindow()
    if ChoiceBox.window then
        log("ChoiceBox window already exists, reusing")
        return ChoiceBox.window
    end
    
    log("Creating new ChoiceBox window")
    local screen = hs.screen.mainScreen()
    local screenFrame = screen:frame()
    local windowWidth = 600
    local windowHeight = 400
    local windowFrame = {
        x = (screenFrame.w - windowWidth) / 2,
        y = (screenFrame.h - windowHeight) / 2,
        w = windowWidth,
        h = windowHeight
    }
    
    local newWindow = hs.drawing.rectangle(windowFrame)
    newWindow:setFillColor({white = 0.95, alpha = 0.95})
    newWindow:setStrokeColor({white = 0.8})
    newWindow:setStrokeWidth(2)
    newWindow:setRoundedRectRadii(10, 10)
    newWindow:setBehavior(hs.drawing.windowBehaviors.canJoinAllSpaces)
    newWindow:setLevel(hs.drawing.windowLevels.modalPanel)
    
    return newWindow
end

function ChoiceBox.updateContent()
    if not ChoiceBox.window then
        log("ChoiceBox window is nil, creating")
        ChoiceBox.window = ChoiceBox.createWindow()
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

    -- Search box
    local searchBox = hs.drawing.rectangle({
        x = windowFrame.x + 10,
        y = windowFrame.y + 10,
        w = windowFrame.w - 20,
        h = 30
    })
    searchBox:setFillColor({white = 1})
    searchBox:setStrokeColor({white = 0.8})
    searchBox:setStrokeWidth(1)
    searchBox:show()
    table.insert(ChoiceBox.window.contentDrawings, searchBox)

    local searchTextDrawing = hs.drawing.text({
        x = windowFrame.x + 15,
        y = windowFrame.y + 15,
        w = windowFrame.w - 30,
        h = 20
    }, ChoiceBox.searchText)
    searchTextDrawing:setTextColor({black = 1})
    searchTextDrawing:show()
    table.insert(ChoiceBox.window.contentDrawings, searchTextDrawing)

    -- Choices
    for i, choice in ipairs(ChoiceBox.filteredChoices) do
        local y = windowFrame.y + 50 + (i - 1) * 30
        local choiceRect = {
            x = windowFrame.x + 10,
            y = y,
            w = windowFrame.w - 20,
            h = 25
        }
        
        if i == ChoiceBox.selectedIndex then
            local selectedBg = hs.drawing.rectangle(choiceRect)
            selectedBg:setFillColor({red = 0.9, green = 0.9, blue = 1})
            selectedBg:show()
            table.insert(ChoiceBox.window.contentDrawings, selectedBg)
        end
        
        local choiceText = hs.drawing.text(choiceRect, choice.text)
        choiceText:setTextColor(i == ChoiceBox.selectedIndex and {blue = 0.5} or {black = 1})
        choiceText:show()
        table.insert(ChoiceBox.window.contentDrawings, choiceText)

        -- Store the rectangle for this choice
        table.insert(ChoiceBox.window.choiceRects, choiceRect)
    end

    ChoiceBox.window:show()
end

function ChoiceBox.filterChoices()
    log("Filtering choices")
    ChoiceBox.filteredChoices = {}
    for _, choice in ipairs(ChoiceBox.choices) do
        if fuzzyMatch(choice.text, ChoiceBox.searchText) then
            table.insert(ChoiceBox.filteredChoices, choice)
        end
    end
    ChoiceBox.selectedIndex = 1
    ChoiceBox.updateContent()
end

function ChoiceBox.keyHandler(event)
    log("Key event received")
    local keyCode = event:getKeyCode()
    local flags = event:getFlags()
    local char = event:getCharacters()

    if keyCode == 53 then  -- ESC key
        ChoiceBox.close()
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
                        log("Choice clicked: " .. i)
                        local selectedChoice = ChoiceBox.filteredChoices[i]
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
end

function ChoiceBox.show()
    log("Showing ChoiceBox")
    if not ChoiceBox.window then
        ChoiceBox.window = ChoiceBox.createWindow()
    end
    
    ChoiceBox.searchText = ""
    ChoiceBox.filterChoices()
    
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
end

-- Function to add a new choice
function ChoiceBox.addChoice(text, callback, subText)
    local id = tostring(math.random()):sub(3)  -- Simple unique ID generation
    table.insert(ChoiceBox.choices, {
        id = id,
        text = text,
        callback = callback,
        subText = subText
    })
    return id
end

-- Function to remove a choice
function ChoiceBox.removeChoice(id)
    for i, choice in ipairs(ChoiceBox.choices) do
        if choice.id == id then
            table.remove(ChoiceBox.choices, i)
            break
        end
    end
    ChoiceBox.filterChoices()
end

-- Function to prompt for a new choice
function ChoiceBox.promptNewChoice()
    ChoiceBox.close()
    hs.focus()
    local text = hs.dialog.textPrompt("Add New Choice", "Enter the text for the new choice:", "", "OK", "Cancel")
    if text and text ~= "" then
        local subText = hs.dialog.textPrompt("Add New Choice", "Enter the subtext (optional):", "", "OK", "Cancel")
        ChoiceBox.addChoice(text, function() print("Selected: " .. text) end, subText)
    end
    ChoiceBox.show()
end

-- Initialize choices
function ChoiceBox.initializeChoices()
    ChoiceBox.addChoice("Safari", function() hs.application.launchOrFocus("Safari") end, "Web Browser")
    ChoiceBox.addChoice("Chrome", function() hs.application.launchOrFocus("Google Chrome") end, "Web Browser")
    ChoiceBox.addChoice("Terminal", function() hs.application.launchOrFocus("Terminal") end, "Development")
    ChoiceBox.addChoice("VS Code", function() hs.application.launchOrFocus("Visual Studio Code") end, "Development")
end

-- Initialize choices when the script loads
ChoiceBox.initializeChoices()

-- Bind to a hotkey
hs.hotkey.bind({"cmd", "alt"}, "C", function()
    log("Hotkey triggered")
    ChoiceBox.show()
end)

log("ChoiceBox script loaded")

return ChoiceBox