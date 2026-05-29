-- Rebar: a thin custom bar that paints over the system menubar.
-- Items live in Rebar/items/*.lua and are auto-loaded on start.
--
-- Trigger: Rebar.start() from init.lua. Stop with Rebar.stop().

local Rebar = {}
package.loaded["Rebar"] = Rebar

local canvas = hs.canvas
local screen = hs.screen
local timer  = hs.timer

local cfg = {
    bgColor    = { red = 0.05, green = 0.05, blue = 0.06, alpha = 1.0 },
    fgColor    = { white = 0.92, alpha = 1.0 },
    notchPadW  = 220,
    edgePad    = 12,
    itemGap    = 14,
    notchGap   = 10,
    fontSize   = 13,
    minHeight  = 26,
    notchedHeightThreshold = 30,
}

-- Module-level retention so canvas/timers don't get GC'd silently.
local state = {
    bars            = {},  -- screenUUID -> canvas
    items           = {},
    timers          = {},
    valueOf         = {},  -- id -> string (global) or { uuid -> string } (perScreen)
    screenWatcher   = nil,
    rightClickTap   = nil,
    contextMenu     = nil,
    enabledOverride = {},  -- id -> bool (persisted)
    spacesWatcher   = nil,
    peekTap         = nil,
    modeByScreen    = {},  -- uuid -> "normal" | "fullscreen-minimal" | "fullscreen-peek"
}
Rebar._state = state

local SETTINGS_KEY = "Rebar.enabledOverride"
local HIT_PREFIX   = "hit:"

local function logf(fmt, ...) hs.printf("Rebar: " .. fmt, ...) end

local function isEnabled(item)
    local override = state.enabledOverride[item.id]
    if override ~= nil then return override end
    return item.defaultEnabled ~= false
end

-- Items default to hiding when the screen is in a fullscreen space; set
-- hideInFullscreen = false on an item to keep it visible there too.
local function isVisibleInMode(item, mode)
    if mode == "fullscreen-minimal" and item.hideInFullscreen ~= false then
        return false
    end
    return true
end

-- ---------------------------------------------------------------- item loader

local function loadItems()
    local items = {}
    local dir = hs.configdir .. "/Rebar/items"
    for name in hs.fs.dir(dir) do
        local stem = name:match("^(.+)%.lua$")
        if stem then
            local ok, mod = pcall(require, "Rebar.items." .. stem)
            if ok and type(mod) == "table" and mod.id then
                mod._stem = stem
                table.insert(items, mod)
            else
                logf("skipped %s (%s)", name, ok and "missing .id" or tostring(mod))
            end
        end
    end
    table.sort(items, function(a, b)
        local oa, ob = a.order or 100, b.order or 100
        if oa ~= ob then return oa < ob end
        return a._stem < b._stem
    end)
    return items
end

-- ---------------------------------------------------------------- geometry

local function geometryFor(scr)
    local full   = scr:fullFrame()
    local usable = scr:frame()
    local menubarH = usable.y - full.y
    local notched  = menubarH > cfg.notchedHeightThreshold
    local barH     = notched and menubarH or cfg.minHeight
    return {
        x = full.x, y = full.y, w = full.w, h = barH,
        notched        = notched,
        notchLeftEdge  = full.x + full.w / 2 - cfg.notchPadW / 2,
        notchRightEdge = full.x + full.w / 2 + cfg.notchPadW / 2,
    }
end

-- ---------------------------------------------------------------- item shape

local function getValue(item, uuid)
    local v = state.valueOf[item.id]
    if item.perScreen then
        return (type(v) == "table" and v[uuid]) or ""
    end
    return v or ""
end

local function labelFor(item, uuid)
    local val = getValue(item, uuid)
    if item.icon and val ~= "" then return item.icon .. " " .. val end
    if val ~= "" then return val end
    return item.icon or ""
end

local function styledLabel(str, bold)
    local font = bold
        and { name = ".AppleSystemUIFontBold", size = cfg.fontSize }
        or  { size = cfg.fontSize }
    return hs.styledtext.new(str, {
        font  = font,
        color = cfg.fgColor,
    })
end

-- prepareItem measures and styles the label once. Returns nil if the item
-- has nothing to render; otherwise a record reused by buildElements at any x.
local function prepareItem(item, uuid)
    local label = labelFor(item, uuid)
    if label == "" then return nil end
    local styled = styledLabel(label, item.bold)
    local sz = hs.drawing.getTextDrawingSize(styled)
    local w = ((sz and sz.w) or (#label * cfg.fontSize * 0.6)) + 16
    return { item = item, styled = styled, w = w }
end

local function buildElements(prepared, x, h)
    return {
        {
            id          = HIT_PREFIX .. prepared.item.id,
            type        = "rectangle",
            frame       = { x = x, y = 0, w = prepared.w, h = h },
            fillColor   = { alpha = 0 },
            strokeColor = { alpha = 0 },
            trackMouseDown = true,
        },
        {
            type  = "text",
            frame = {
                x = x + 8,
                y = (h - cfg.fontSize) / 2 - 2,
                w = prepared.w - 16,
                h = cfg.fontSize + 6,
            },
            text  = prepared.styled,
        },
    }
end

-- ---------------------------------------------------------------- layout

local function bucketBySide(items, notched, mode)
    local sides = {
        left            = {},
        ["center-left"] = {},
        ["center-right"]= {},
        right           = {},
    }
    for _, it in ipairs(items) do
        if isEnabled(it) and isVisibleInMode(it, mode) then
            local side = it.side or "right"
            if not notched and side == "center-left" then
                side = "center-right"
            end
            if sides[side] then table.insert(sides[side], it) end
        end
    end
    return sides
end

-- placeRow takes a prepared list, a start x, and a direction (+1 grows right,
-- -1 grows left). Caller passes a sink for the produced elements.
local function placeRow(prepared, startX, dir, h, sink)
    local x = startX
    for _, p in ipairs(prepared) do
        if dir < 0 then x = x - p.w end
        for _, e in ipairs(buildElements(p, x, h)) do table.insert(sink, e) end
        if dir > 0 then x = x + p.w end
        x = x + dir * cfg.itemGap
    end
end

local function prepareSide(items, uuid)
    local out = {}
    for _, it in ipairs(items) do
        local p = prepareItem(it, uuid)
        if p then table.insert(out, p) end
    end
    return out
end

local function relayoutScreen(scr)
    local uuid = scr:getUUID()
    local bar = state.bars[uuid]
    if not bar then return end
    local geo   = geometryFor(scr)
    local mode  = state.modeByScreen[uuid] or "normal"
    local sides = bucketBySide(state.items, geo.notched, mode)

    local elems = {
        {
            type        = "rectangle",
            frame       = { x = 0, y = 0, w = geo.w, h = geo.h },
            fillColor   = cfg.bgColor,
            strokeColor = { alpha = 0 },
        },
    }

    placeRow(prepareSide(sides.left, uuid),  cfg.edgePad,             1, geo.h, elems)
    placeRow(prepareSide(sides.right, uuid), geo.w - cfg.edgePad,    -1, geo.h, elems)
    if geo.notched then
        placeRow(prepareSide(sides["center-left"], uuid),
                 geo.notchLeftEdge - cfg.notchGap, -1, geo.h, elems)
    end
    local centerRightStart = geo.notched and (geo.notchRightEdge + cfg.notchGap) or (geo.w / 2)
    placeRow(prepareSide(sides["center-right"], uuid),
             centerRightStart, 1, geo.h, elems)

    bar:replaceElements(elems)
    bar:size({ w = geo.w, h = geo.h })
    bar:topLeft({ x = geo.x, y = geo.y })

    -- In fullscreen-minimal mode, hide the canvas entirely when no items
    -- opted to stay visible. In any other mode (or when peeking), the bar
    -- shows so the user can reach items or right-click for the menu.
    local hasContent = #elems > 1
    if mode == "fullscreen-minimal" and not hasContent then
        bar:hide()
    else
        bar:show()
    end
end

local function relayoutAll()
    for _, scr in ipairs(screen.allScreens()) do relayoutScreen(scr) end
end

-- ---------------------------------------------------------------- mouse

local function findItem(itemId)
    for _, it in ipairs(state.items) do
        if it.id == itemId then return it end
    end
end

local function onMouse(_c, event, elemId)
    local itemId = type(elemId) == "string" and elemId:match("^" .. HIT_PREFIX .. "(.+)$")
    if not itemId then return end
    local item = findItem(itemId)
    if not item then return end
    if event == "mouseDown" then
        if type(item.onClick) == "function" then
            local ok, err = pcall(item.onClick)
            if not ok then logf("%s onClick error: %s", item.id, err) end
        elseif type(item.onClick) == "string" then
            hs.task.new("/bin/sh", nil, { "-c", item.onClick }):start()
        end
    end
end

-- ---------------------------------------------------------------- update

local function setValue(item, val, uuid)
    val = tostring(val or "")
    if item.perScreen then
        local tbl = state.valueOf[item.id]
        if type(tbl) ~= "table" then tbl = {}; state.valueOf[item.id] = tbl end
        if tbl[uuid] ~= val then
            tbl[uuid] = val
            relayoutAll()
        end
    elseif state.valueOf[item.id] ~= val then
        state.valueOf[item.id] = val
        relayoutAll()
    end
end

local function runShell(item)
    -- perScreen is only meaningful for update-fn items; shell items are global.
    local t = hs.task.new("/bin/sh", function(code, stdout)
        local val = ""
        if code == 0 and stdout then
            val = stdout:match("^[^\n]*") or ""
            val = val:gsub("^%s+", ""):gsub("%s+$", "")
        end
        setValue(item, val)
    end, { "-c", item.command })
    t:start()
end

local function runUpdateFn(item)
    if item.perScreen then
        for _, scr in ipairs(screen.allScreens()) do
            local ok, val = pcall(item.update, scr)
            if not ok then val = "" end
            setValue(item, val, scr:getUUID())
        end
    else
        local ok, val = pcall(item.update)
        if not ok then val = "" end
        setValue(item, val)
    end
end

local function tickItem(item)
    if not isEnabled(item) then return end
    if item.command then runShell(item)
    elseif item.update then runUpdateFn(item) end
end

-- ---------------------------------------------------------------- lifecycle

local function startItem(item)
    if type(item.setup) == "function" then
        local refresh = function() Rebar.refresh(item.id) end
        local ok, err = pcall(item.setup, refresh)
        if not ok then logf("%s setup error: %s", item.id, err) end
    end
    if item.command or item.update then
        tickItem(item)
        local interval = item.interval or 0
        if interval > 0 then
            state.timers[item.id] = timer.doEvery(interval, function() tickItem(item) end)
        end
    end
end

local function stopItem(item)
    local t = state.timers[item.id]
    if t then t:stop(); state.timers[item.id] = nil end
    if type(item.teardown) == "function" then pcall(item.teardown) end
    state.valueOf[item.id] = nil
end

-- ---------------------------------------------------------------- bars

local function destroyBars()
    for uuid, b in pairs(state.bars) do
        b:delete()
        state.bars[uuid] = nil
    end
end

local function rebuildBars()
    destroyBars()
    for _, scr in ipairs(screen.allScreens()) do
        local geo = geometryFor(scr)
        local bar = canvas.new({ x = geo.x, y = geo.y, w = geo.w, h = geo.h })
        bar:level(canvas.windowLevels.cursor)
        bar:behavior({ "canJoinAllSpaces", "stationary" })
        bar:mouseCallback(onMouse)
        state.bars[scr:getUUID()] = bar
        bar:show()
    end
    relayoutAll()
end

-- ---------------------------------------------------------------- fullscreen

local function isFullscreenScreen(scr)
    local ok, active = pcall(hs.spaces.activeSpaces)
    if not ok or not active then return false end
    local sid = active[scr:getUUID()]
    if not sid then return false end
    local ok2, t = pcall(hs.spaces.spaceType, sid)
    return ok2 and t == "fullscreen"
end

local onMouseMove   -- forward decl so updateFullscreenState can reference it

local function updateFullscreenState()
    local anyFs = false
    for _, scr in ipairs(screen.allScreens()) do
        local uuid = scr:getUUID()
        local fs = isFullscreenScreen(scr)
        if fs then
            anyFs = true
            -- Preserve peek across space-watcher events: only drop to minimal
            -- if we weren't already peeking on that screen.
            if state.modeByScreen[uuid] ~= "fullscreen-peek" then
                state.modeByScreen[uuid] = "fullscreen-minimal"
            end
        else
            state.modeByScreen[uuid] = "normal"
        end
    end
    if anyFs and not state.peekTap then
        state.peekTap = hs.eventtap.new(
            { hs.eventtap.event.types.mouseMoved },
            function() return onMouseMove() end
        )
        state.peekTap:start()
    elseif not anyFs and state.peekTap then
        state.peekTap:stop()
        state.peekTap = nil
    end
    relayoutAll()
end

onMouseMove = function()
    local pt = hs.mouse.absolutePosition()
    for _, scr in ipairs(screen.allScreens()) do
        local uuid = scr:getUUID()
        local mode = state.modeByScreen[uuid]
        if mode == "fullscreen-minimal" or mode == "fullscreen-peek" then
            local geo = geometryFor(scr)
            local onThisScreen = pt.x >= geo.x and pt.x < geo.x + geo.w
            if onThisScreen then
                local localY = pt.y - geo.y
                if mode == "fullscreen-minimal" and localY < 2 then
                    state.modeByScreen[uuid] = "fullscreen-peek"
                    relayoutScreen(scr)
                elseif mode == "fullscreen-peek" and localY > geo.h + 8 then
                    state.modeByScreen[uuid] = "fullscreen-minimal"
                    relayoutScreen(scr)
                end
            end
        end
    end
    return false
end

-- ---------------------------------------------------------------- right-click

local function showContextMenu()
    local menu = {}
    for _, it in ipairs(state.items) do
        table.insert(menu, {
            title   = it.id,
            checked = isEnabled(it),
            fn      = function() Rebar.toggle(it.id) end,
        })
    end
    if not state.contextMenu then
        state.contextMenu = hs.menubar.new(false)
    end
    state.contextMenu:setMenu(menu)
    state.contextMenu:popupMenu(hs.mouse.absolutePosition())
end

local function pointInAnyBar(pt)
    for _, bar in pairs(state.bars) do
        local f = bar:frame()
        if pt.x >= f.x and pt.x < f.x + f.w
            and pt.y >= f.y and pt.y < f.y + f.h then
            return true
        end
    end
    return false
end

-- ---------------------------------------------------------------- public

function Rebar.refresh(itemId)
    local it = findItem(itemId)
    if it then tickItem(it) end
end

-- Exposed for tests; forces a render pass on every screen with the current
-- mode + values. Not for general use; setValue already drives relayout.
function Rebar._relayout() relayoutAll() end

function Rebar.isEnabled(itemId)
    local it = findItem(itemId)
    return it and isEnabled(it) or false
end

function Rebar.setEnabled(itemId, on)
    local it = findItem(itemId)
    if not it then return end
    state.enabledOverride[itemId] = on and true or false
    hs.settings.set(SETTINGS_KEY, state.enabledOverride)
    if on then startItem(it) else stopItem(it) end
    relayoutAll()
end

function Rebar.toggle(itemId)
    local it = findItem(itemId)
    if not it then return end
    Rebar.setEnabled(itemId, not isEnabled(it))
end

function Rebar.start()
    if next(state.bars) then return end
    state.items = loadItems()
    state.enabledOverride = hs.settings.get(SETTINGS_KEY) or {}

    rebuildBars()

    for _, it in ipairs(state.items) do
        if isEnabled(it) then startItem(it) end
    end

    state.screenWatcher = screen.watcher.new(function()
        rebuildBars()
        updateFullscreenState()
    end):start()

    local okWatcher, sw = pcall(hs.spaces.watcher.new, function()
        updateFullscreenState()
    end)
    if okWatcher and sw then
        state.spacesWatcher = sw
        sw:start()
    end
    updateFullscreenState()

    state.rightClickTap = hs.eventtap.new(
        { hs.eventtap.event.types.rightMouseDown },
        function()
            local pt = hs.mouse.absolutePosition()
            if pointInAnyBar(pt) then
                showContextMenu()
                return true
            end
            return false
        end
    )
    state.rightClickTap:start()

    logf("started, %d items on %d screens", #state.items, #screen.allScreens())
end

function Rebar.stop()
    for _, it in ipairs(state.items) do stopItem(it) end
    if state.screenWatcher then state.screenWatcher:stop(); state.screenWatcher = nil end
    if state.spacesWatcher then state.spacesWatcher:stop(); state.spacesWatcher = nil end
    if state.peekTap       then state.peekTap:stop();       state.peekTap       = nil end
    if state.rightClickTap then state.rightClickTap:stop(); state.rightClickTap = nil end
    if state.contextMenu   then state.contextMenu:delete(); state.contextMenu   = nil end
    destroyBars()
end

return Rebar
