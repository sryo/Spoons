-- Use MenuMaestro to easily browse and select menu items through a friendly interface.
-- Inspired by MenuChooser by Jacob Williams (https://github.com/brokensandals/motley-hammerspoons)

local chooser = require("hs.chooser")
local styledtext = require("hs.styledtext")
local canvas = require("hs.canvas")

local function getFontSize()
    local screen = hs.screen.mainScreen()
    local frame = screen:fullFrame()
    local width = frame.w
    local minFontSize = 13
    local maxFontSize = 23
    local minScreenWidth = 1080
    local maxScreenWidth = 1920

    if width < minScreenWidth then return minFontSize end
    if width > maxScreenWidth then return maxFontSize end

    return minFontSize + (maxFontSize - minFontSize) * ((width - minScreenWidth) / (maxScreenWidth - minScreenWidth))
end

local function shortcutToString(modifiers, shortcut)
    local str = ""
    local keyMap = {
        cmd = "⌘", ctrl = "⌃", alt = "⌥",  shift = "⇧", ["\xEF\x9C\x84"] = "F1", ["\xEF\x9C\x85"] = "F2", ["\xEF\x9C\x86"] = "F3", ["\xEF\x9C\x87"] = "F4", ["\xEF\x9C\x88"] = "F5", ["\xEF\x9C\x89"] = "F6", ["\xEF\x9C\x8A"] = "F7", ["\xEF\x9C\x8B"] = "F8", ["\xEF\x9C\x8C"] = "F9", ["\xEF\x9C\x8D"] = "F10", ["\xEF\x9C\x8E"] = "F11", ["\xEF\x9C\x8F"] = "F12", ["\xEF\x9C\x80"] = "▶", ["\xEF\x9C\x81"] = "◀", ["\xEF\x9C\x82"] = "▲", ["\xEF\x9C\x83"] = "▼", ["\x1B"] = "⎋", ["\x0D"] = "↩", ["\x08"] = "⌫", ["\x7F"] = "⌦", ["\x09"] = "⇥", ["\xE2\x84\xAA"] = "⇪", ["\xE2\x87\x9E"] = "⇞", ["\xE2\x87\x9F"] = "⇟", ["\xE2\x86\x96"] = "↖", ["\xE2\x86\x98"] = "↘"
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
    local textCanvas = canvas.new{ x = 0, y = 0, w = 32, h = 32 }
    textCanvas[1] = {
        type = "text",
        text = text,
        frame = { x = "0%", y = "12%", h = "100%", w = "100%" },
        textAlignment = "right",
        textColor = { red = 0, blue = 0, green = 0, alpha = 0.8 },
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
        pathList[#pathList+1] = title
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
            choices[#choices+1] = {
                text = styledtext.new(title, { font = { size = getFontSize() } }),
                subText = currentMenuPath,
                path = pathList,
                image = shortcutImage
            }
        end
    end
end

local function chooseMenuItem()
    local app = hs.application.frontmostApplication()
    local appName = app:name()

    app:getMenuItems(function(menu)
        local choices = {}
        collectMenuItems(nil, {}, menu, choices)
        local completionFn = function(result)
            if result then
                app:selectMenuItem(result.path)
            end
        end
        local menuItemChooser = chooser.new(completionFn)
        menuItemChooser:choices(choices)
        menuItemChooser:searchSubText(true)

        menuItemChooser:placeholderText("Find a menu item in " .. appName .. "...")

        menuItemChooser:show()
    end)
end


hs.hotkey.bind({"ctrl", "alt"}, "space", chooseMenuItem)
