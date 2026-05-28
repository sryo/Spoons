-- Menu items source. Walks the frontmost app's menu tree and emits one
-- Palette item per leaf. The shortcut is exposed as a plain text accessory
-- (right-aligned in the canvas) rather than a pre-rendered image.

local M = {}
M.id = "menuitems"

local keyMap = {
    cmd = "⌘", ctrl = "⌃", alt = "⌥", shift = "⇧",
    -- Arrows (U+F700..U+F703)
    ["\xEF\x9C\x80"] = "Up",
    ["\xEF\x9C\x81"] = "Down",
    ["\xEF\x9C\x82"] = "Left",
    ["\xEF\x9C\x83"] = "Right",
    -- F1..F12 (U+F704..U+F70F)
    ["\xEF\x9C\x84"] = "F1",  ["\xEF\x9C\x85"] = "F2",  ["\xEF\x9C\x86"] = "F3",
    ["\xEF\x9C\x87"] = "F4",  ["\xEF\x9C\x88"] = "F5",  ["\xEF\x9C\x89"] = "F6",
    ["\xEF\x9C\x8A"] = "F7",  ["\xEF\x9C\x8B"] = "F8",  ["\xEF\x9C\x8C"] = "F9",
    ["\xEF\x9C\x8D"] = "F10", ["\xEF\x9C\x8E"] = "F11", ["\xEF\x9C\x8F"] = "F12",
    -- Navigation cluster (U+F728..U+F72D)
    ["\xEF\x9C\xA8"] = "⌦",
    ["\xEF\x9C\xA9"] = "Home",
    ["\xEF\x9C\xAB"] = "End",
    ["\xEF\x9C\xAC"] = "PgUp",
    ["\xEF\x9C\xAD"] = "PgDn",
    -- Clear / Help
    ["\xE2\x8C\xA7"] = "Clear",
    ["\xEF\x9C\xB9"] = "Clear",
    ["\xEF\x9D\x86"] = "?",
    -- ASCII control
    ["\x1B"] = "⎋", ["\x0D"] = "↩", ["\x08"] = "⌫", ["\x7F"] = "⌦", ["\x09"] = "⇥",
    -- Caps Lock (U+21EA)
    ["\xE2\x87\xAA"] = "Caps",
}

local function shortcutToString(modifiers, shortcut)
    if not shortcut or shortcut == "" then return "" end
    local modStr = ""
    for _, m in pairs(modifiers) do
        modStr = modStr .. (keyMap[m] or "")
    end
    local keyStr = keyMap[shortcut] or shortcut
    return modStr .. keyStr
end

local function collect(menuPath, path, list, items, depth)
    depth = depth or 0
    if depth > 10 or not list then return end
    for _, item in pairs(list) do
        if item.AXTitle and item.AXTitle ~= "" then
            local title       = item.AXTitle
            local currentPath = menuPath and (menuPath .. " > " .. title) or title
            local pathList    = {}
            for i, p in ipairs(path) do pathList[i] = p end
            pathList[#pathList + 1] = title
            if item.AXChildren then
                collect(currentPath, pathList, item.AXChildren[1], items, depth + 1)
            else
                local modifiers = {}
                if item.AXMenuItemCmdModifiers then
                    for _, m in pairs(item.AXMenuItemCmdModifiers) do
                        modifiers[#modifiers + 1] = m
                    end
                end
                local shortcut  = item.AXMenuItemCmdChar or ""
                local accessory = shortcutToString(modifiers, shortcut)
                local mark      = item.AXMenuItemMarkChar
                if mark == "" then mark = nil end
                items[#items + 1] = {
                    id          = currentPath,
                    title       = title,
                    subtitle    = currentPath,
                    icon        = nil,
                    accessory   = accessory ~= "" and accessory or nil,
                    enabled     = item.AXEnabled and true or false,
                    markChar    = mark,
                    source      = M.id,
                    payload     = { path = pathList, appName = nil }, -- appName filled in list()
                    defaultVerb = "activate",
                    verbs       = { "activate", "askmuse" },
                }
            end
        end
    end
end

function M.list()
    local app = hs.application.frontmostApplication()
    if not app then return {}, nil end
    local menu = app:getMenuItems()
    if not menu then return {}, app:name() end
    local items = {}
    collect(nil, {}, menu, items)
    local appName = app:name()
    for _, it in ipairs(items) do
        it.payload.appName = appName
        -- Per-app learning: the same "File > Save" in Safari and in Terminal
        -- have separate usage counts so each app ranks its own frequents.
        it.id = appName .. " :: " .. it.id
    end
    return items, appName
end

return M
