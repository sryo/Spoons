local eventtap = require("hs.eventtap")
local mouse = require("hs.mouse")
local keymap = require("CloudPad.keymap")
local log = require("CloudPad.log")

local M = {}

local etypes = eventtap.event.types
local eprops = eventtap.event.properties

local function accelerate(d)
    local a = math.abs(d)
    local sign = d < 0 and -1 or 1
    local scaled
    if a < 1.0 then
        scaled = a * 0.5
    elseif a <= 6.0 then
        scaled = 0.5 + (a - 1.0) * 0.6
    else
        scaled = 3.5 + math.sqrt(a - 6.0) * 1.6
    end
    return sign * scaled
end

local function moveBy(dx, dy)
    local p = mouse.absolutePosition()
    mouse.absolutePosition({ x = p.x + accelerate(dx), y = p.y + accelerate(dy) })
end

local function clickAt(button, count)
    local pos = mouse.absolutePosition()
    if button == "right" then
        eventtap.rightClick(pos)
        return
    end
    if button == "middle" then
        local down = eventtap.event.newMouseEvent(etypes.otherMouseDown, pos, "other")
        local up   = eventtap.event.newMouseEvent(etypes.otherMouseUp,   pos, "other")
        down:setProperty(eprops.mouseEventButtonNumber, 2)
        up:setProperty(eprops.mouseEventButtonNumber, 2)
        down:post(); up:post()
        return
    end
    count = count or 1
    if count >= 2 then
        local d1 = eventtap.event.newMouseEvent(etypes.leftMouseDown, pos)
        local u1 = eventtap.event.newMouseEvent(etypes.leftMouseUp,   pos)
        d1:setProperty(eprops.mouseEventClickState, 1):post()
        u1:setProperty(eprops.mouseEventClickState, 1):post()
        local d2 = eventtap.event.newMouseEvent(etypes.leftMouseDown, pos)
        local u2 = eventtap.event.newMouseEvent(etypes.leftMouseUp,   pos)
        d2:setProperty(eprops.mouseEventClickState, 2):post()
        u2:setProperty(eprops.mouseEventClickState, 2):post()
    else
        eventtap.leftClick(pos)
    end
end

local function scrollBy(dx, dy)
    eventtap.scrollWheel({ math.floor(dx + 0.5), math.floor(dy + 0.5) }, {}, "pixel")
end

local function pressKey(name, mods)
    local k = keymap.normalize(name)
    if not k then
        log.warn("unknown key:", name)
        return
    end
    eventtap.keyStroke(keymap.normalizeMods(mods), k, 0)
end

local function typeText(s)
    if type(s) == "string" and #s > 0 then
        eventtap.keyStrokes(s)
    end
end

function M.dispatch(evt)
    local t = evt and evt.t
    if t == "move" then
        moveBy(tonumber(evt.dx) or 0, tonumber(evt.dy) or 0)
    elseif t == "click" then
        clickAt(evt.button or "left", tonumber(evt.count) or 1)
    elseif t == "scroll" then
        scrollBy(tonumber(evt.dx) or 0, tonumber(evt.dy) or 0)
    elseif t == "key" then
        pressKey(evt.key, evt.mods)
    elseif t == "text" then
        typeText(evt.s)
    elseif t == "mode" then
        log.debug("mode:", evt.mode)
    else
        log.debug("unknown event type:", t)
    end
end

function M.drain(events)
    if type(events) ~= "table" then return 0 end
    local n = 0
    for _, e in ipairs(events) do
        M.dispatch(e)
        n = n + 1
    end
    return n
end

return M
