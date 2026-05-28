-- Palette: a Quicksilver-style command palette for Hammerspoon.
-- v2 is two-stage (noun then verb): pick an item, then Tab to pick a verb
-- (or Enter to run the item's default verb).
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
local apps      = require("Palette.sources.apps")

local verbs = {
    activate = require("Palette.verbs.activate"),
    hide     = require("Palette.verbs.hide"),
    quit     = require("Palette.verbs.quit"),
    askmuse  = require("Palette.verbs.askmuse"),
}

Palette.config = {
    hotkey  = { { "ctrl", "cmd" }, "space" },
    sources = { menuitems, apps },
}

local function refresh()
    state.items = matcher.rank(state.raw, state.query)
    state.focused = math.min(math.max(1, state.focused), math.max(1, #state.items))
    canvas.draw(state)
end

local function close()
    keys.stop()
    canvas.hide()
    state.reset()
end

-- Push current stage frame onto history; replace with the new stage.
local function pushStage(newStage, newRaw, opts)
    opts = opts or {}
    state.history[#state.history + 1] = {
        stage          = state.stage,
        query          = state.query,
        raw            = state.raw,
        items          = state.items,
        focused        = state.focused,
        selectedItem   = state.selectedItem,
        selectedVerb   = state.selectedVerb,
    }
    state.stage        = newStage
    state.query        = ""
    state.raw          = newRaw
    state.focused      = 1
    if opts.selectedItem ~= nil then state.selectedItem = opts.selectedItem end
    if opts.selectedVerb ~= nil then state.selectedVerb = opts.selectedVerb end
    refresh()
end

local function popStage()
    local prev = table.remove(state.history)
    if not prev then return false end
    state.stage        = prev.stage
    state.query        = prev.query
    state.raw          = prev.raw
    state.items        = prev.items
    state.focused      = prev.focused
    state.selectedItem = prev.selectedItem
    state.selectedVerb = prev.selectedVerb
    canvas.draw(state)
    return true
end

-- Build the verb-stage item list for a chosen noun.
local function verbItemsFor(item)
    local out = {}
    local declared = item.verbs or { item.defaultVerb or "activate" }
    for _, vid in ipairs(declared) do
        local v = verbs[vid]
        if v then
            out[#out + 1] = {
                id          = "verb:" .. v.id,
                title       = v.label or v.id,
                subtitle    = "",
                icon        = nil,
                source      = "verbs",
                payload     = { verb = v },
                defaultVerb = nil,
            }
        end
    end
    return out
end

local function advanceFromNoun()
    if state.stage ~= "noun" then return end
    local item = state.items[state.focused]
    if not item then return end
    local list = verbItemsFor(item)
    if #list == 0 then return end
    pushStage("verb", list, { selectedItem = item })
end

-- Run a verb on the selected noun.
local function runVerb(verb, item)
    if not (verb and item) then return end
    close()
    hs.timer.doAfter(0.02, function()
        local ok, err = verb.run(item, nil)
        if ok then
            recents.record(item.source, item.id)
            recents.record("verb:" .. item.source, verb.id)
        elseif err then
            hs.alert.show("Palette: " .. tostring(err))
        end
    end)
end

local function activateFocused()
    if state.stage == "noun" then
        local item = state.items[state.focused]
        if not item then return end
        local verb = verbs[item.defaultVerb or "activate"]
        if not verb then
            hs.alert.show("Palette: no default verb for " .. tostring(item.title))
            return
        end
        runVerb(verb, item)
    elseif state.stage == "verb" then
        local row = state.items[state.focused]
        if not row then return end
        local verb = row.payload and row.payload.verb
        if not verb then return end
        runVerb(verb, state.selectedItem)
    end
end

local function open()
    if state.open then return end
    state.reset()
    state.open     = true
    state.openedAt = hs.timer.secondsSinceEpoch()

    local raw = {}
    for _, src in ipairs(Palette.config.sources) do
        local ok, items, name = pcall(src.list)
        if ok and items then
            if name and state.appName == "" then state.appName = name end
            for _, it in ipairs(items) do raw[#raw + 1] = it end
        end
    end
    state.stage = "noun"
    state.raw   = raw

    canvas.show()
    refresh()

    keys.start({
        char = function(c)
            state.query = state.query .. c
            state.focused = 1
            refresh()
        end,
        backspace = function()
            if #state.query > 0 then
                state.query = state.query:sub(1, -2)
                state.focused = 1
                refresh()
            end
        end,
        up = function()
            if state.focused > 1 then
                state.focused = state.focused - 1
                canvas.draw(state)
            end
        end,
        down = function()
            if state.focused < #state.items then
                state.focused = state.focused + 1
                canvas.draw(state)
            end
        end,
        ["return"] = function() activateFocused() end,
        tab = function(event)
            local flags = event and event:getFlags() or {}
            if flags.shift then
                if not popStage() then close() end
            else
                if state.stage == "noun" then advanceFromNoun() end
            end
        end,
        escape = function()
            if not popStage() then close() end
        end,
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
Palette.verbs   = verbs
Palette._state  = state
Palette._hotkey = hotkeyBinding

return Palette
