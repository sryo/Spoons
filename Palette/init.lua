-- Palette: a Quicksilver-style command palette for Hammerspoon.
-- v1 is single-stage (noun only): pick a menu item from the frontmost app
-- and Enter activates it. Verb stage + more sources land in later phases.
--
-- Trigger: Ctrl+Cmd+Space (Spotlight is Cmd+Space; this avoids the clash).

local Palette = {}
package.loaded["Palette"] = Palette

local state    = require("Palette.state")
local canvas   = require("Palette.canvas")
local keys     = require("Palette.keys")
local matcher  = require("Palette.matcher")
local recents  = require("Palette.recents")

local menuitems = require("Palette.sources.menuitems")
local activate  = require("Palette.verbs.activate")

Palette.config = {
    hotkey = { { "ctrl", "cmd" }, "space" },
}

local sources = { menuitems }
local verbs   = { activate = activate }

local rawItems = {} -- collected from sources at open-time

local function refresh()
    state.items = matcher.rank(rawItems, state.query)
    state.focusedIndex = math.min(math.max(1, state.focusedIndex), math.max(1, #state.items))
    canvas.draw(state)
end

local function close()
    keys.stop()
    canvas.hide()
    state.reset()
end

local function activateFocused()
    local item = state.items[state.focusedIndex]
    if not item then return end
    local verb = verbs[item.defaultVerb or "activate"]
    if not verb then return end
    -- Close the overlay first so focus returns to the target app, then run.
    close()
    hs.timer.doAfter(0.02, function()
        local ok, err = verb.run(item)
        if ok then
            recents.record(item.source, item.id)
        elseif err then
            hs.alert.show("Palette: " .. tostring(err))
        end
    end)
end

local function open()
    if state.open then return end
    state.reset()
    state.open     = true
    state.openedAt = hs.timer.secondsSinceEpoch()

    rawItems = {}
    for _, src in ipairs(sources) do
        local ok, items, name = pcall(src.list)
        if ok and items then
            if name then state.appName = name end
            for _, it in ipairs(items) do
                rawItems[#rawItems + 1] = it
            end
        end
    end

    canvas.show()
    refresh()

    keys.start({
        char = function(c)
            state.query = state.query .. c
            state.focusedIndex = 1
            refresh()
        end,
        backspace = function()
            if #state.query > 0 then
                state.query = state.query:sub(1, -2)
                state.focusedIndex = 1
                refresh()
            end
        end,
        up = function()
            if state.focusedIndex > 1 then
                state.focusedIndex = state.focusedIndex - 1
                canvas.draw(state)
            end
        end,
        down = function()
            if state.focusedIndex < #state.items then
                state.focusedIndex = state.focusedIndex + 1
                canvas.draw(state)
            end
        end,
        ["return"] = function() activateFocused() end,
        escape     = function() close() end,
    })
end

recents.init()

local hotkeyBinding = hs.hotkey.bind(
    Palette.config.hotkey[1],
    Palette.config.hotkey[2],
    open
)

Palette.open    = open
Palette.close   = close
Palette.refresh = refresh
Palette._state  = state
Palette._hotkey = hotkeyBinding

return Palette
