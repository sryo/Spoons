-- MenuMaestro: https://github.com/sryo/Spoons/blob/main/MenuMaestro.lua
-- Use MenuMaestro to easily browse and select menu items through a friendly interface.
-- Inspired by MenuChooser by Jacob Williams (https://github.com/brokensandals/motley-hammerspoons)

local chooser = require("hs.chooser")
local styledtext = require("hs.styledtext")
local canvas = require("hs.canvas")

local sortAlphabetically = true -- Set to false for hierarchical sorting.
local maxRecentItems = 5        -- You can change this to store a different number of recent items

local recentItems = {}

local function shortcutToString(modifiers, shortcut)
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

local function shortcutToImage(modifiers, shortcut)
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

local function collectMenuItems(menuPath, path, list, choices)
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
        local regularChoices = {}
        collectMenuItems(nil, {}, menu, regularChoices)

        local recentPaths = {}
        for _, recentItem in ipairs(recentItems[appName]) do
            recentPaths[recentItem.plainText] = true
        end

        regularChoices = hs.fnutils.filter(regularChoices, function(choice)
            return not recentPaths[choice.plainText]
        end)

        if sortAlphabetically then
            table.sort(regularChoices, function(a, b) return a.plainText < b.plainText end)
        end

        local recentChoices = {}
        for i, recentItem in ipairs(recentItems[appName]) do
            local choice = {
                text = styledtext.new("⭯ " .. recentItem.plainText),
                plainText = "⭯ " .. recentItem.plainText,
                subText = recentItem.subText,
                path = recentItem.path,
                image = recentItem.image
            }
            table.insert(recentChoices, choice)
        end

        local choices = recentChoices
        for _, choice in ipairs(regularChoices) do
            table.insert(choices, choice)
        end

        local completionFn = function(result)
            if result then
                table.insert(recentItems[appName], 1, result)
                if #recentItems[appName] > maxRecentItems then
                    table.remove(recentItems[appName])
                end
                app:selectMenuItem(result.path)
            end
        end

        menuMaestro = chooser.new(completionFn)
        menuMaestro:choices(choices)
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
    if touches and #touches == 4 and not wasHandled and not isMenuMaestroOpen() then
        wasHandled = true
        openMenuMaestro()
    elseif touches and #touches < 4 then
        wasHandled = false
    end
end

gestureTap = hs.eventtap.new({ hs.eventtap.event.types.gesture }, touchToOpenMenuMaestro)
gestureTap:start()

hs.hotkey.bind({ "ctrl", "alt" }, "space", openMenuMaestro)
