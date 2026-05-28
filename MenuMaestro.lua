-- MenuMaestro: https://github.com/sryo/Spoons/blob/main/MenuMaestro.lua
-- Use MenuMaestro to effortlessly browse and select menu items through an adaptive, intent-aware interface.
-- It learns your patterns, prioritizes your frequent actions, and evolves with your workflow.
-- Inspired by MenuChooser by Jacob Williams (https://github.com/brokensandals/motley-hammerspoons)
-- Enhanced with machine learning concepts to create a truly responsive "intenterface" experience.

local chooser = require("hs.chooser")
local styledtext = require("hs.styledtext")
local canvas = require("hs.canvas")
local settings = require("hs.settings")
local application = require("hs.application")
local eventtap = require("hs.eventtap")
local timer = require("hs.timer")

local config = {
    sortAlphabetically = true, -- Set to false for hierarchical sorting
    maxRecentItems = 9,        -- Set to 0 to disable recently run items
    numberOfFingersToOpen = 5,
    daysToRemember = 30,
    showShortcutImages = true, -- Disable if still laggy on older machines
    logger = hs.logger.new('MenuMaestro', 'info')
}

local menuMaestro
local recentItems = {}
local usageData = {}
local settingsKey = "menuMaestroUsageData"
local imageCache = {}
local blankImage = nil

local function loadUsageData()
    usageData = settings.get(settingsKey) or {}
end

local function saveUsageData()
    settings.set(settingsKey, usageData)
end

local function updateUsageData(appName, menuPath)
    if not appName or not menuPath then return end

    local currentTime = os.time()
    if not usageData[appName] then usageData[appName] = {} end

    if not usageData[appName][menuPath] then
        usageData[appName][menuPath] = { count = 0, lastUsed = 0 }
    end

    usageData[appName][menuPath].count = usageData[appName][menuPath].count + 1
    usageData[appName][menuPath].lastUsed = currentTime
    saveUsageData()
end

local function cleanUpUsageData()
    local currentTime = os.time()
    local cutoffTime = currentTime - (config.daysToRemember * 24 * 60 * 60)
    local changed = false

    for appName, appData in pairs(usageData) do
        for menuPath, itemData in pairs(appData) do
            if itemData.lastUsed < cutoffTime then
                appData[menuPath] = nil
                changed = true
            end
        end
        if next(appData) == nil then
            usageData[appName] = nil
            changed = true
        end
    end

    if changed then saveUsageData() end
end

local function calculatePriorityScore(appName, menuPath)
    if not usageData[appName] or not usageData[appName][menuPath] then return 0 end

    local itemData = usageData[appName][menuPath]
    local recency = os.time() - itemData.lastUsed
    return itemData.count * 1000000 / (recency + 1)
end

local function shortcutToString(modifiers, shortcut)
    if not shortcut or shortcut == "" then return "" end

    -- Menu shortcut characters use NSEvent function-key codepoints in the
    -- Private Use Area (NSUpArrowFunctionKey = U+F700, etc).
    local keyMap = {
        cmd   = "⌘",
        ctrl  = "⌃",
        alt   = "⌥",
        shift = "⇧",
        -- Arrows (U+F700..U+F703)
        ["\xEF\x9C\x80"] = "Up",
        ["\xEF\x9C\x81"] = "Down",
        ["\xEF\x9C\x82"] = "Left",
        ["\xEF\x9C\x83"] = "Right",
        -- F1..F12 (U+F704..U+F70F)
        ["\xEF\x9C\x84"] = "F1",
        ["\xEF\x9C\x85"] = "F2",
        ["\xEF\x9C\x86"] = "F3",
        ["\xEF\x9C\x87"] = "F4",
        ["\xEF\x9C\x88"] = "F5",
        ["\xEF\x9C\x89"] = "F6",
        ["\xEF\x9C\x8A"] = "F7",
        ["\xEF\x9C\x8B"] = "F8",
        ["\xEF\x9C\x8C"] = "F9",
        ["\xEF\x9C\x8D"] = "F10",
        ["\xEF\x9C\x8E"] = "F11",
        ["\xEF\x9C\x8F"] = "F12",
        -- Navigation cluster (U+F728..U+F72D)
        ["\xEF\x9C\xA8"] = "⌦",     -- Forward Delete
        ["\xEF\x9C\xA9"] = "Home",  -- Home
        ["\xEF\x9C\xAB"] = "End",   -- End
        ["\xEF\x9C\xAC"] = "PgUp",  -- Page Up
        ["\xEF\x9C\xAD"] = "PgDn",  -- Page Down
        -- Clear / Num Lock and Help
        ["\xE2\x8C\xA7"] = "Clear",  -- Clear / Num Lock (literal glyph from macOS)
        ["\xEF\x9C\xB9"] = "Clear",  -- Clear / Num Lock (function-key form, defensive)
        ["\xEF\x9D\x86"] = "?",      -- Help
        -- ASCII control characters
        ["\x1B"] = "⎋",   -- Escape
        ["\x0D"] = "↩",   -- Return
        ["\x08"] = "⌫",   -- Backspace
        ["\x7F"] = "⌦",   -- DEL (defensive fallback)
        ["\x09"] = "⇥",   -- Tab
        -- Caps Lock (U+21EA)
        ["\xE2\x87\xAA"] = "Caps",
    }

    local modStr = ""
    for _, modifier in pairs(modifiers) do
        modStr = modStr .. (keyMap[modifier] or "")
    end
    local keyStr = keyMap[shortcut] or shortcut
    -- Wrap onto two lines only when the combined string would clip the 40px
    -- canvas. Single-glyph shortcuts (⌘O, ⌘↩, ⌘F1, ⌘Up) stay one-line.
    local function estW(s)
        local w = 0
        for i = 1, #s do
            local b = s:byte(i)
            if b < 0x80 then w = w + 6
            elseif b >= 0xC0 then w = w + 9 end
        end
        return w
    end
    if modStr ~= "" and keyStr ~= "" and estW(modStr .. keyStr) > 30 then
        return modStr .. "\n" .. keyStr
    end
    return modStr .. keyStr
end

local function getBlankImage()
    if blankImage then return blankImage end
    local c = canvas.new { x = 0, y = 0, w = 40, h = 32 }
    blankImage = c:imageFromCanvas()
    c:delete()
    return blankImage
end

local function shortcutToImage(modifiers, shortcut)
    if not config.showShortcutImages then return nil end

    local text = shortcutToString(modifiers, shortcut or "")

    -- If text is empty, return the cached blank image for alignment
    if not text or text == "" or text:match("^%s*$") then
        return getBlankImage()
    end

    if imageCache[text] then return imageCache[text] end

    local textColor = { red = 0, blue = 0, green = 0, alpha = 0.8 }
    if hs.host.interfaceStyle() == "Dark" then
        textColor = { red = 1, green = 1, blue = 1, alpha = 0.8 }
    end

    local textCanvas = canvas.new { x = 0, y = 0, w = 40, h = 32 }
    textCanvas[1] = {
        type = "text",
        text = text,
        frame = { x = "0%", y = "12%", h = "100%", w = "100%" },
        textAlignment = "right",
        textColor = textColor,
        textSize = 11
    }

    local image = textCanvas:imageFromCanvas()
    imageCache[text] = image
    textCanvas:delete()
    return image
end

local function collectMenuItems(menuPath, path, list, choices, depth)
    depth = depth or 0
    if depth > 10 then return end
    if not list then return end

    for _, item in pairs(list) do
        if item.AXEnabled and item.AXTitle and item.AXTitle ~= "" then
            local title = item.AXTitle
            local currentMenuPath = menuPath and (menuPath .. ' > ' .. title) or title
            local pathList = {}
            for i, p in ipairs(path) do pathList[i] = p end
            table.insert(pathList, title)

            if item.AXChildren then
                collectMenuItems(currentMenuPath, pathList, item.AXChildren[1], choices, depth + 1)
            else
                local modifiers = {}
                if item.AXMenuItemCmdModifiers then
                    for _, mod in pairs(item.AXMenuItemCmdModifiers) do
                        table.insert(modifiers, mod)
                    end
                end
                local shortcut = item.AXMenuItemCmdChar or ""

                -- Always call this now, as it handles returning the blank spacer
                local shortcutImage = shortcutToImage(modifiers, shortcut)

                table.insert(choices, {
                    text = styledtext.new(title),
                    plainText = title,
                    subText = currentMenuPath,
                    path = pathList,
                    image = shortcutImage,
                    id = currentMenuPath
                })
            end
        end
    end
end

local function openMenuMaestro()
    local app = application.frontmostApplication()
    if not app then
        hs.alert.show("No application focused"); return
    end

    local appName = app:name()
    if not recentItems[appName] then recentItems[appName] = {} end

    local menu = app:getMenuItems()
    if not menu then
        hs.timer.doAfter(0.1, function()
            menu = app:getMenuItems()
            if not menu then
                hs.alert.show("Could not retrieve menu items for " .. appName)
                return
            end
        end)
        return
    end

    local choices = {}
    collectMenuItems(nil, {}, menu, choices)

    local choiceLookup = {}
    for _, choice in ipairs(choices) do
        choiceLookup[choice.id] = choice
    end

    local priorityChoices = {}
    local seenIDs = {}

    for _, recentItem in ipairs(recentItems[appName]) do
        local menuPath = table.concat(recentItem.path, " > ")
        if choiceLookup[menuPath] and not seenIDs[menuPath] then
            local mergedChoice = hs.fnutils.copy(choiceLookup[menuPath])
            mergedChoice.subText = "↺ Recently Used • " .. mergedChoice.subText
            mergedChoice.score = math.huge
            table.insert(priorityChoices, mergedChoice)
            seenIDs[menuPath] = true
        end
    end

    if usageData[appName] then
        for menuPath, _ in pairs(usageData[appName]) do
            if choiceLookup[menuPath] and not seenIDs[menuPath] then
                local mergedChoice = hs.fnutils.copy(choiceLookup[menuPath])
                mergedChoice.score = calculatePriorityScore(appName, menuPath)
                table.insert(priorityChoices, mergedChoice)
                seenIDs[menuPath] = true
            end
        end
    end

    table.sort(priorityChoices, function(a, b)
        return (a.score or 0) > (b.score or 0)
    end)

    while #priorityChoices > config.maxRecentItems do
        table.remove(priorityChoices)
    end

    local finalChoices = {}
    for _, c in ipairs(priorityChoices) do
        table.insert(finalChoices, c)
    end

    local remaining = {}
    for _, choice in ipairs(choices) do
        if not seenIDs[choice.id] then
            table.insert(remaining, choice)
        end
    end

    if config.sortAlphabetically then
        table.sort(remaining, function(a, b) return a.plainText < b.plainText end)
    end

    for _, c in ipairs(remaining) do
        table.insert(finalChoices, c)
    end

    local completionFn = function(result)
        if result then
            local success = app:selectMenuItem(result.path)
            if success then
                local menuPath = table.concat(result.path, " > ")
                updateUsageData(appName, menuPath)

                for i, item in ipairs(recentItems[appName]) do
                    if table.concat(item.path, " > ") == menuPath then
                        table.remove(recentItems[appName], i)
                        break
                    end
                end
                table.insert(recentItems[appName], 1, result)
                if #recentItems[appName] > config.maxRecentItems then
                    table.remove(recentItems[appName])
                end
            else
                hs.alert.show("Failed to trigger menu item")
            end
        end
    end

    if menuMaestro then menuMaestro:delete() end
    menuMaestro = chooser.new(completionFn)
    menuMaestro:choices(finalChoices)
    menuMaestro:searchSubText(true)
    menuMaestro:placeholderText("MenuMaestro: " .. appName)
    menuMaestro:rows(10)
    menuMaestro:show()
end

function isMenuMaestroOpen()
    return menuMaestro and menuMaestro:isVisible()
end

local state = {
    wasOpened = false
}

local function touchToOpenMenuMaestro(event)
    local numberOfFingersToOpen = config.numberOfFingersToOpen
    local touches = event:getTouches()
    if not touches then return end

    if #touches == numberOfFingersToOpen and not state.wasOpened and not isMenuMaestroOpen() then
        for _, touch in ipairs(touches) do
            if touch.phase == "ended" then
                state.wasOpened = true
                openMenuMaestro()
                return
            end
        end
    elseif #touches > numberOfFingersToOpen then
        state.wasOpened = true
        return true
    elseif #touches < numberOfFingersToOpen then
        state.wasOpened = false
    end
end

loadUsageData()
timer.doEvery(24 * 60 * 60, cleanUpUsageData)

if _G.menuMaestroTap then
    _G.menuMaestroTap:stop()
    _G.menuMaestroTap = nil
end

_G.menuMaestroTap = eventtap.new({ eventtap.event.types.gesture }, touchToOpenMenuMaestro)
_G.menuMaestroTap:start()

hs.hotkey.bind({ "ctrl", "alt" }, "space", openMenuMaestro)
