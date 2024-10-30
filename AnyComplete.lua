-- nathancahill's anycomplete, ported to choicebox.lua (experimental)
local ChoiceBox = require("ChoiceBox")

-- Anycomplete Configuration
local anycompleteEngine = "google"
local endpoints = {
    google = "https://suggestqueries.google.com/complete/search?client=firefox&q=%s",
    duckduckgo = "https://duckduckgo.com/ac/?q=%s",
}

-- Anycomplete Function
local function anycomplete()
    local current = hs.application.frontmostApplication()
    local originalClipboard = hs.pasteboard.getContents()

    local function choiceBoxCallback(chosen)
        ChoiceBox.close()
        current:activate()
        if not chosen then return end
        
        -- Save the original clipboard content
        local originalClipboard = hs.pasteboard.getContents()
        
        -- Copy the chosen text to clipboard
        hs.pasteboard.setContents(chosen.text)
        
        -- Paste the chosen text
        hs.eventtap.keyStroke({"cmd"}, "v")
        
        -- Restore the original clipboard content
        hs.timer.doAfter(0.1, function()
            hs.pasteboard.setContents(originalClipboard)
        end)
    end

    local function updateChoiceBox()
        local string = ChoiceBox.searchText
        if string:len() == 0 then 
            ChoiceBox.clearChoices()
            return
        end

        local query = hs.http.encodeForQuery(string)

        hs.http.asyncGet(string.format(endpoints[anycompleteEngine], query), nil, function(status, data)
            if not data then return end
            local ok, results = pcall(function() return hs.json.decode(data) end)
            if not ok then return end

            local choices = {}
            if anycompleteEngine == "google" then
                choices = hs.fnutils.imap(results[2], function(result)
                    return {
                        text = result,
                        callback = function() choiceBoxCallback({text = result}) end
                    }
                end)
            elseif anycompleteEngine == "duckduckgo" then
                choices = hs.fnutils.imap(results, function(result)
                    return {
                        text = result["phrase"],
                        callback = function() choiceBoxCallback({text = result["phrase"]}) end
                    }
                end)
            end

            ChoiceBox.clearChoices()
            for i, choice in ipairs(choices) do
                local shortcut = i <= 9 and ("⌘" .. tostring(i)) or nil
                ChoiceBox.addChoice(choice.text, choice.callback, nil, shortcut)
            end
            ChoiceBox.filterChoices()
        end)
    end

    -- Override only necessary ChoiceBox behaviors
    local originalOnClose = ChoiceBox.onClose
    ChoiceBox.onClose = function()
        hs.pasteboard.setContents(originalClipboard)  -- Restore original clipboard
        if originalOnClose then originalOnClose() end
    end

    local originalKeyHandler = ChoiceBox.keyHandler
    ChoiceBox.keyHandler = function(event)
        local keyCode = event:getKeyCode()
        local flags = event:getFlags()
        local char = event:getCharacters()

        -- Handle specific key combinations for anycomplete
        if flags:containExactly({'cmd'}) and tonumber(char) and tonumber(char) >= 1 and tonumber(char) <= 9 then
            local index = tonumber(char)
            if index <= #ChoiceBox.filteredChoices then
                local selectedChoice = ChoiceBox.filteredChoices[index]
                if selectedChoice and selectedChoice.callback then
                    selectedChoice.callback()
                end
                return true
            end
        elseif keyCode == 48 then  -- Tab key
            if #ChoiceBox.filteredChoices > 0 then
                ChoiceBox.searchText = ChoiceBox.filteredChoices[1].text
                updateChoiceBox()
            end
            return true
        end

        -- Use the original key handler for other keys
        local result = originalKeyHandler(event)
        
        -- Update choices after each keystroke
        if result then
            updateChoiceBox()
        end
        
        return result
    end

    ChoiceBox.show("topLeft")
    updateChoiceBox()
end

-- Bind Anycomplete to a hotkey
hs.hotkey.bind({"cmd", "alt"}, "G", anycomplete)