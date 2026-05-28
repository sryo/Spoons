-- Menu items source. Walks the frontmost app's menu tree and emits one
-- Palette item per leaf. The shortcut-glyph renderer is lifted from
-- MenuMaestro (debugged against the macOS keycap quirks).

local canvas = hs.canvas

local M = {}
M.id = "menuitems"

local cfg = {
    showShortcutImages = true,
    iconSize           = 32,
}

local imageCache = {}
local blankImage = nil

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

local function estW(s)
    local w = 0
    for i = 1, #s do
        local b = s:byte(i)
        if b < 0x80 then w = w + 6
        elseif b >= 0xC0 then w = w + 9 end
    end
    return w
end

local function shortcutToString(modifiers, shortcut)
    if not shortcut or shortcut == "" then return "" end
    local modStr = ""
    for _, m in pairs(modifiers) do
        modStr = modStr .. (keyMap[m] or "")
    end
    local keyStr = keyMap[shortcut] or shortcut
    if modStr ~= "" and keyStr ~= "" and estW(modStr .. keyStr) > 30 then
        return modStr .. "\n" .. keyStr
    end
    return modStr .. keyStr
end

local function getBlankImage()
    if blankImage then return blankImage end
    local c = canvas.new { x = 0, y = 0, w = cfg.iconSize, h = cfg.iconSize }
    blankImage = c:imageFromCanvas()
    c:delete()
    return blankImage
end

local function shortcutToImage(modifiers, shortcut)
    if not cfg.showShortcutImages then return nil end
    local text = shortcutToString(modifiers, shortcut)
    if not text or text == "" then return getBlankImage() end
    if imageCache[text] then return imageCache[text] end

    local textColor = { white = 0, alpha = 0.8 }
    if hs.host.interfaceStyle() == "Dark" then
        textColor = { white = 1, alpha = 0.8 }
    end

    local c = canvas.new { x = 0, y = 0, w = cfg.iconSize, h = cfg.iconSize }
    c[1] = {
        type          = "text",
        text          = text,
        frame         = { x = "0%", y = "12%", h = "100%", w = "100%" },
        textAlignment = "right",
        textColor     = textColor,
        textSize      = 11,
    }
    local img = c:imageFromCanvas()
    imageCache[text] = img
    c:delete()
    return img
end

local function collect(menuPath, path, list, items, depth)
    depth = depth or 0
    if depth > 10 or not list then return end
    for _, item in pairs(list) do
        if item.AXEnabled and item.AXTitle and item.AXTitle ~= "" then
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
                local shortcut = item.AXMenuItemCmdChar or ""
                items[#items + 1] = {
                    id          = currentPath,
                    title       = title,
                    subtitle    = currentPath,
                    icon        = shortcutToImage(modifiers, shortcut),
                    source      = M.id,
                    payload     = { path = pathList, appName = nil }, -- appName filled in list()
                    defaultVerb = "activate",
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
    end
    return items, appName
end

return M
