-- MenuMaestro: https://github.com/sryo/Spoons/blob/main/MenuMaestro.lua
-- Use MenuMaestro to effortlessly browse and select menu items through an adaptive, intent-aware interface.
-- It learns your patterns, prioritizes your frequent actions, and evolves with your workflow.
-- Inspired by MenuChooser by Jacob Williams (https://github.com/brokensandals/motley-hammerspoons)
-- Enhanced with machine learning concepts to create a truly responsive "intenterface" experience.

local chooser = require("hs.chooser")
local styledtext = require("hs.styledtext")
local canvas = require("hs.canvas")
local settings = require("hs.settings")

local sortAlphabetically    = true  -- Set to false for hierarchical sorting
local maxRecentItems        = 9     -- Set to 0 to disable recently run items
local numberOfFingersToOpen = 5
local daysToRemember        = 30

local menuMaestro
local recentItems = {}
local usageData = {}
local settingsKey = "menuMaestroUsageData"
gestureTap = nil

local function loadUsageData()
    usageData = settings.get(settingsKey) or {}
end

local function saveUsageData()
    settings.set(settingsKey, usageData)
end

local function updateUsageData(appName, menuPath)
    local currentTime = os.time()
    if not usageData[appName] then
        usageData[appName] = {}
    end
    if not usageData[appName][menuPath] then
        usageData[appName][menuPath] = {count = 0, lastUsed = 0}
    end
    usageData[appName][menuPath].count = usageData[appName][menuPath].count + 1
    usageData[appName][menuPath].lastUsed = currentTime
    saveUsageData()
end

local function cleanUpUsageData()
    local currentTime = os.time()
    local cutoffTime = currentTime - (daysToRemember * 24 * 60 * 60)
    for appName, appData in pairs(usageData) do
        for menuPath, itemData in pairs(appData) do
            if itemData.lastUsed < cutoffTime then
                appData[menuPath] = nil
            end
        end
        if next(appData) == nil then
            usageData[appName] = nil
        end
    end
    saveUsageData()
end

local function calculatePriorityScore(appName, menuPath)
    if not usageData[appName] or not usageData[appName][menuPath] then
        return 0
    end
    local itemData = usageData[appName][menuPath]
    local recency = os.time() - itemData.lastUsed
    local frequency = itemData.count
    return frequency * 1000000 / (recency + 1)
end

function shortcutToString(modifiers, shortcut)
    local str = ""
    local keyMap = {
        cmd = "⌘", ctrl = "⌃", alt = "⌥", shift = "⇧", ["\xEF\x9C\x84"] = "F1", ["\xEF\x9C\x85"] = "F2", ["\xEF\x9C\x86"] = "F3", ["\xEF\x9C\x87"] = "F4", ["\xEF\x9C\x88"] = "F5", ["\xEF\x9C\x89"] = "F6", ["\xEF\x9C\x8A"] = "F7", ["\xEF\x9C\x8B"] = "F8", ["\xEF\x9C\x8C"] = "F9", ["\xEF\x9C\x8D"] = "F10", ["\xEF\x9C\x8E"] = "F11", ["\xEF\x9C\x8F"] = "F12", ["\xEF\x9C\x80"] = "▶", ["\xEF\x9C\x81"] = "◀", ["\xEF\x9C\x82"] = "▲", ["\xEF\x9C\x83"] = "▼", ["\x1B"] = "⎋", ["\x0D"] = "↩", ["\x08"] = "⌫", ["\x7F"] = "⌦", ["\x09"] = "⇥", ["\xE2\x84\xAA"] = "⇪", ["\xE2\x87\x9E"] = "⇞", ["\xE2\x87\x9F"] = "⇟", ["\xE2\x86\x96"] = "↖", ["\xE2\x86\x98"] = "↘"
    }

    if shortcut and shortcut ~= "" then
        for _, modifier in pairs(modifiers) do
            str = str .. (keyMap[modifier] or "")
        end

        str = str .. (keyMap[shortcut] or shortcut)
    end

    return str
end

function shortcutToImage(modifiers, shortcut)
    local text = shortcutToString(modifiers, shortcut or "")
    local textCanvas = canvas.new { x = 0, y = 0, w = 32, h = 32 }

    local textColor
    if hs.host.interfaceStyle() == "Dark" then
        textColor = { red = 1, green = 1, blue = 1, alpha = 0.8 }
    else
        textColor = { red = 0, blue = 0, green = 0, alpha = 0.8 }
    end

    textCanvas[1] = {
        type = "text",
        text = text,
        frame = { x = "0%", y = "12%", h = "100%", w = "100%" },
        textAlignment = "right",
        textColor = textColor,
        textSize = 10
    }
    local image = textCanvas:imageFromCanvas()
    return image
end

function collectMenuItems(menuPath, path, list, choices)
    for _, item in pairs(list) do
        local title = item.AXTitle or ''
        local currentMenuPath
        if menuPath then
            currentMenuPath = menuPath .. ' > ' .. title
        else
            currentMenuPath = title
        end
        local pathList = {}
        for i, title in ipairs(path) do
            pathList[i] = title
        end
        pathList[#pathList + 1] = title
        if item.AXChildren then
            collectMenuItems(currentMenuPath, pathList, item.AXChildren[1], choices)
        elseif item.AXEnabled and title and (not (title == '')) then
            local modifiers = {}
            if item.AXMenuItemCmdModifiers then
                for _, mod in pairs(item.AXMenuItemCmdModifiers) do
                    table.insert(modifiers, mod)
                end
            end
            local shortcut = item.AXMenuItemCmdChar or ""
            local shortcutImage = shortcutToImage(modifiers, shortcut or "")
            choices[#choices + 1] = {
                text = styledtext.new(title),
                plainText = title,
                subText = currentMenuPath,
                path = pathList,
                image = shortcutImage
            }
        end
    end
end

function openMenuMaestro()
    local app = hs.application.frontmostApplication()
    local appName = app:name()

    if not recentItems[appName] then
        recentItems[appName] = {}
    end

    app:getMenuItems(function(menu)
        local choices = {}
        collectMenuItems(nil, {}, menu, choices)

        local choiceLookup = {}
        for _, choice in ipairs(choices) do
            local menuPath = table.concat(choice.path, " > ")
            choiceLookup[menuPath] = choice
        end

        local priorityChoices = {}
        local seenPaths = {}

        for _, recentItem in ipairs(recentItems[appName]) do
            local menuPath = table.concat(recentItem.path, " > ")
            if choiceLookup[menuPath] and not seenPaths[menuPath] then
                local mergedChoice = hs.fnutils.copy(choiceLookup[menuPath])
                mergedChoice.text = styledtext.new("⭯ " .. mergedChoice.plainText)
                mergedChoice.plainText = "⭯ " .. mergedChoice.plainText
                table.insert(priorityChoices, mergedChoice)
                seenPaths[menuPath] = true
            end
        end

        if usageData[appName] then
            for menuPath, itemData in pairs(usageData[appName]) do
                if choiceLookup[menuPath] and not seenPaths[menuPath] then
                    local mergedChoice = hs.fnutils.copy(choiceLookup[menuPath])
                    local score = calculatePriorityScore(appName, menuPath)
                    mergedChoice.score = score
                    table.insert(priorityChoices, mergedChoice)
                    seenPaths[menuPath] = true
                end
            end
        end

        table.sort(priorityChoices, function(a, b)
            return (a.score or math.huge) > (b.score or math.huge)
        end)

        if #priorityChoices > maxRecentItems then
            for i = maxRecentItems + 1, #priorityChoices do
                priorityChoices[i] = nil
            end
        end

        local remainingChoices = {}
        for _, choice in ipairs(choices) do
            local menuPath = table.concat(choice.path, " > ")
            if not seenPaths[menuPath] then
                table.insert(remainingChoices, choice)
            end
        end

        if sortAlphabetically then
            table.sort(remainingChoices, function(a, b)
                return a.plainText < b.plainText
            end)
        end

        local finalChoices = {}
        for _, choice in ipairs(priorityChoices) do
            table.insert(finalChoices, choice)
        end
        for _, choice in ipairs(remainingChoices) do
            table.insert(finalChoices, choice)
        end

        local completionFn = function(result)
            if result then
                local menuPath = table.concat(result.path, " > ")
                local success = app:selectMenuItem(result.path)
                if success then
                    updateUsageData(appName, menuPath)
                    -- Update recent items
                    for i, item in ipairs(recentItems[appName]) do
                        if table.concat(item.path, " > ") == menuPath then
                            table.remove(recentItems[appName], i)
                            break
                        end
                    end
                    table.insert(recentItems[appName], 1, result)
                    if #recentItems[appName] > maxRecentItems then
                        table.remove(recentItems[appName])
                    end
                else
                    if usageData[appName] then
                        usageData[appName][menuPath] = nil
                    end
                    for i, item in ipairs(recentItems[appName]) do
                        if table.concat(item.path, " > ") == menuPath then
                            table.remove(recentItems[appName], i)
                            break
                        end
                    end
                    saveUsageData()
                    hs.alert.show("Menu item not found: " .. menuPath)
                end
            end
        end

        menuMaestro = chooser.new(completionFn)
        menuMaestro:choices(finalChoices)
        menuMaestro:searchSubText(true)
        menuMaestro:placeholderText("Find a menu item in " .. appName .. "...")
        menuMaestro:show()
    end)
end

function isMenuMaestroOpen()
    return menuMaestro and menuMaestro:isVisible()
end

function touchToOpenMenuMaestro(event)
    local touches = event:getTouches()
    if touches and #touches == numberOfFingersToOpen and not wasOpened and not isMenuMaestroOpen() then
        for _, touch in ipairs(touches) do
            if touch.phase == "ended" then
                wasOpened = true
                openMenuMaestro()
                return
            end
        end
    elseif touches and #touches > numberOfFingersToOpen then
        wasOpened = true
        return true
    elseif touches and #touches < numberOfFingersToOpen then
        wasOpened = false
    end
end

loadUsageData()

hs.timer.doEvery(24 * 60 * 60, cleanUpUsageData)

if gestureTap then
    gestureTap:stop()
end
gestureTap = hs.eventtap.new({ hs.eventtap.event.types.gesture }, touchToOpenMenuMaestro)
gestureTap:start()

hs.hotkey.bind({ "ctrl", "alt" }, "space", openMenuMaestro)
