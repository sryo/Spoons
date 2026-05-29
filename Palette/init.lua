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
local textbuf  = require("Palette.textbuffer")

local menuitems     = require("Palette.sources.menuitems")
local apps          = require("Palette.sources.apps")
local installedapps = require("Palette.sources.installedapps")
local calc          = require("Palette.sources.calc")
local shellrunner   = require("Palette.sources.shellrunner")
local files         = require("Palette.sources.files")

-- Auto-load every *.lua under Palette/verbs/ and key by the module's own id.
-- pcall'd so a broken verb file degrades to "this verb is missing" instead of
-- preventing the palette from loading at all.
local verbs = {}
do
    local dir = hs.configdir .. "/Palette/verbs"
    for name in hs.fs.dir(dir) do
        local stem = name:match("^(.+)%.lua$")
        if stem then
            local ok, mod = pcall(require, "Palette.verbs." .. stem)
            if ok and type(mod) == "table" and mod.id then
                verbs[mod.id] = mod
            else
                hs.printf("Palette: skipped verb %s (%s)", name,
                    ok and "missing .id" or tostring(mod))
            end
        end
    end
end

Palette.config = {
    hotkey  = { { "ctrl", "cmd" }, "space" },
    sources = { menuitems, apps, installedapps, calc, shellrunner, files },
}

local dismissTap = nil

-- Trackpad pixel-delta accumulator: trips +/-1 row step per scrollStepPx.
-- Reset on close / stage push/pop so sub-threshold deltas don't carry across.
local scrollAccum  = 0
local scrollStepPx = 24

-- Keep the focused item inside the visible window by sliding state.scrollOffset.
local function clampScroll()
    local rows = canvas.visibleRows()
    local maxScroll = math.max(0, #state.items - rows)
    if state.scrollOffset > maxScroll then state.scrollOffset = maxScroll end
    if state.scrollOffset < 0 then state.scrollOffset = 0 end
    if state.focused < state.scrollOffset + 1 then
        state.scrollOffset = state.focused - 1
    elseif state.focused > state.scrollOffset + rows then
        state.scrollOffset = state.focused - rows
    end
    if state.scrollOffset < 0 then state.scrollOffset = 0 end
end

-- ⏎ shows the default verb; ⌘1..⌘9 enumerate the remaining verbs in
-- declared order; ⌘⌫ appears only when the focused item has history.
local function hotkeyListForFocused()
    if state.stage ~= "noun" then return {} end
    local item = state.items[state.focused]
    if not item then return {} end
    local list = {}
    local default = item.defaultVerb or "activate"
    local declared = item.verbs or { default }
    local defaultVerb = verbs[default]
    if defaultVerb then
        list[#list + 1] = { hotkey = "⏎", label = defaultVerb.label or defaultVerb.id }
    end
    local n = 0
    for _, vid in ipairs(declared) do
        if vid ~= default then
            local v = verbs[vid]
            if v then
                n = n + 1
                if n > 9 then break end
                list[#list + 1] = { hotkey = "⌘" .. n, label = v.label or v.id }
            end
        end
    end
    if item.fromHistory then
        list[#list + 1] = { hotkey = "⌘⌫", label = "Forget" }
    end
    return list
end

local function draw()
    canvas.draw(state, hotkeyListForFocused())
end

-- Dynamic sources (.dynamic = true) emit synthetic items per query and are
-- re-evaluated on every refresh. Static sources are scanned once on open and
-- live in state.raw. Both pools merge before ranking so dynamic results
-- compete on the same scale as the rest.
local function buildPool()
    if state.stage ~= "noun" then return state.raw end
    local pool = {}
    for i = 1, #state.raw do pool[#pool + 1] = state.raw[i] end
    for _, src in ipairs(Palette.config.sources) do
        if src.dynamic then
            local ok, items = pcall(src.list, state.query)
            if ok and items then
                for _, it in ipairs(items) do pool[#pool + 1] = it end
            end
        end
    end
    return pool
end

local function refresh()
    state.items = matcher.rank(buildPool(), state.query)
    state.focused = math.min(math.max(1, state.focused), math.max(1, #state.items))
    clampScroll()
    draw()
end

local function close()
    if dismissTap then dismissTap:stop(); dismissTap = nil end
    keys.stop()
    canvas.hide()
    state.reset()
    scrollAccum = 0
end

-- Push current stage frame onto history; replace with the new stage.
local function pushStage(newStage, newRaw, opts)
    opts = opts or {}
    state.history[#state.history + 1] = {
        stage          = state.stage,
        query          = state.query,
        caret          = state.caret,
        raw            = state.raw,
        items          = state.items,
        focused        = state.focused,
        scrollOffset   = state.scrollOffset,
        selectedItem   = state.selectedItem,
        selectedVerb   = state.selectedVerb,
    }
    state.stage        = newStage
    state.query        = ""
    state.caret        = 0
    state.raw          = newRaw
    state.focused      = 1
    state.scrollOffset = 0
    if opts.selectedItem ~= nil then state.selectedItem = opts.selectedItem end
    if opts.selectedVerb ~= nil then state.selectedVerb = opts.selectedVerb end
    scrollAccum = 0
    refresh()
end

local function popStage()
    local prev = table.remove(state.history)
    if not prev then return false end
    state.stage        = prev.stage
    state.query        = prev.query
    state.caret        = prev.caret or 0
    state.raw          = prev.raw
    state.items        = prev.items
    state.focused      = prev.focused
    state.scrollOffset = prev.scrollOffset or 0
    state.selectedItem = prev.selectedItem
    state.selectedVerb = prev.selectedVerb
    scrollAccum        = 0
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
                accessory   = nil,
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

local function runVerb(verb, item)
    if not (verb and item) then return end
    -- Snapshot the Palette's frame BEFORE close() destroys the canvas, so verbs
    -- that summon another overlay (Ask Muse) can position it at the same spot.
    local context = { paletteFrame = canvas.frame() }
    -- keepOpen verbs run inline and may return a directive table that mutates
    -- the live palette state (e.g. enter directory rewrites the query).
    if verb.keepOpen then
        local ok, err, directive = verb.run(item, nil, context)
        if ok then
            recents.record(item.source, item.id)
            recents.record("verb:" .. item.source, verb.id)
        elseif err then
            hs.alert.show("Palette: " .. tostring(err))
        end
        if directive and directive.rewriteQuery then
            state.query        = directive.rewriteQuery
            state.caret        = textbuf.charLen(state.query)
            state.focused      = 1
            state.scrollOffset = 0
            refresh()
        end
        return
    end
    close()
    hs.timer.doAfter(0.02, function()
        local ok, err = verb.run(item, nil, context)
        if ok then
            recents.record(item.source, item.id)
            recents.record("verb:" .. item.source, verb.id)
        elseif err then
            hs.alert.show("Palette: " .. tostring(err))
        end
    end)
end

-- Fallback when the user pressed Enter but the result list is empty: ship the
-- typed query off to Muse as a free-form question. Reuses the askmuse verb so
-- the Muse-position-centered-on-Palette logic lives in one place.
local function askMuseWithQuery(query)
    runVerb(verbs.askmuse, { title = query, payload = {}, source = "ask" })
end

local function activateFocused()
    if state.stage == "noun" then
        if #state.items == 0 and state.query ~= "" then
            askMuseWithQuery(state.query)
            return
        end
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

-- Momentum scroll events are consumed but not stepped so a flick moves one
-- row, not thirty.
local function startDismissTap()
    if dismissTap then dismissTap:stop() end
    local etypes = hs.eventtap.event.types
    local props  = hs.eventtap.event.properties
    dismissTap = hs.eventtap.new(
        { etypes.leftMouseDown, etypes.rightMouseDown, etypes.scrollWheel },
        function(e)
            if not state.open then return false end
            local f = canvas.frame()
            if not f then return false end
            local p = e:location()
            local inside = p.x >= f.x and p.x <= f.x + f.w
                and p.y >= f.y and p.y <= f.y + f.h
            local etype = e:getType()

            if etype == etypes.scrollWheel then
                if not inside then return false end
                local n = #state.items
                if n == 0 then return true end
                local momentum = e:getProperty(props.scrollWheelEventMomentumPhase) or 0
                if momentum ~= 0 then return true end
                local isContinuous = e:getProperty(props.scrollWheelEventIsContinuous) or 0
                local step = 0
                if isContinuous == 0 then
                    step = -(e:getProperty(props.scrollWheelEventDeltaAxis1) or 0)
                else
                    local d = e:getProperty(props.scrollWheelEventPointDeltaAxis1) or 0
                    scrollAccum = scrollAccum + d
                    while scrollAccum >= scrollStepPx do
                        step = step - 1
                        scrollAccum = scrollAccum - scrollStepPx
                    end
                    while scrollAccum <= -scrollStepPx do
                        step = step + 1
                        scrollAccum = scrollAccum + scrollStepPx
                    end
                end
                if step ~= 0 then
                    local newFocus = math.max(1, math.min(n, state.focused + step))
                    if newFocus ~= state.focused then
                        state.focused = newFocus
                        clampScroll()
                        canvas.draw(state, hotkeyListForFocused())
                    end
                    -- Drop overshoot at the ends so reversing direction feels immediate.
                    if state.focused == 1 or state.focused == n then
                        scrollAccum = 0
                    end
                end
                return true
            end

            -- Left / right mouseDown from here on.
            if not inside then
                close()
                return false
            end
            local fp  = { x = p.x - f.x, y = p.y - f.y }
            local idx = canvas.hitTestRow(fp)
            if not idx then return true end
            state.focused = idx
            clampScroll()
            if etype == etypes.rightMouseDown then
                canvas.draw(state, hotkeyListForFocused())
                return true
            end
            activateFocused()
            return true
        end
    ):start()
end

local function open()
    if state.open then return end
    state.reset()
    state.open     = true
    state.openedAt = hs.timer.secondsSinceEpoch()

    local raw = {}
    for _, src in ipairs(Palette.config.sources) do
        if not src.dynamic then
            local ok, items, name = pcall(src.list)
            if ok and items then
                if name and state.appName == "" then state.appName = name end
                for _, it in ipairs(items) do raw[#raw + 1] = it end
            end
        end
    end
    state.stage        = "noun"
    state.raw          = raw
    state.scrollOffset = 0

    canvas.show()
    refresh()
    startDismissTap()

    local function moveMode(flags)
        if flags.cmd then return "edge" end
        if flags.alt then return "word" end
        return "char"
    end

    keys.start({
        char = function(c)
            state.query, state.caret = textbuf.insert(state.query, state.caret, c)
            state.focused      = 1
            state.scrollOffset = 0
            refresh()
        end,
        backspace = function(event)
            local flags = event and event:getFlags() or {}
            if flags.cmd and state.stage == "noun" then
                local item = state.items[state.focused]
                if item then
                    recents.forget(item.source, item.id)
                    refresh()
                end
                return
            end
            if state.caret > 0 then
                state.query, state.caret = textbuf.deleteBefore(state.query, state.caret)
                state.focused      = 1
                state.scrollOffset = 0
                refresh()
            end
        end,
        fwddel = function()
            if state.caret < textbuf.charLen(state.query) then
                state.query, state.caret = textbuf.deleteAfter(state.query, state.caret)
                state.focused      = 1
                state.scrollOffset = 0
                refresh()
            end
        end,
        left = function(event)
            local flags = event and event:getFlags() or {}
            state.caret = textbuf.moveLeft(state.query, state.caret, moveMode(flags))
            draw()
        end,
        right = function(event)
            local flags = event and event:getFlags() or {}
            state.caret = textbuf.moveRight(state.query, state.caret, moveMode(flags))
            draw()
        end,
        home = function()
            state.caret = 0
            draw()
        end,
        end_ = function()
            state.caret = textbuf.charLen(state.query)
            draw()
        end,
        up = function()
            if state.focused > 1 then
                state.focused = state.focused - 1
                clampScroll()
                draw()
            end
        end,
        down = function()
            if state.focused < #state.items then
                state.focused = state.focused + 1
                clampScroll()
                draw()
            end
        end,
        ["return"] = function() activateFocused() end,
        tab = function(event)
            local flags = event and event:getFlags() or {}
            if flags.shift then
                if not popStage() then close() end
                return
            end
            if state.stage ~= "noun" then return end
            -- Files-source items autocomplete the query on Tab: rewrite to the
            -- focused row's full path, with a trailing slash on directories so
            -- the listing immediately descends.
            local item = state.items[state.focused]
            if item and item.source == files.id
                and item.payload and item.payload.path then
                local path = item.payload.path
                local newQuery = files.abbreviatePath(path)
                if item.payload.isDir then
                    newQuery = newQuery .. "/"
                    recents.record(files.id, path)
                end
                state.query        = newQuery
                state.caret        = textbuf.charLen(state.query)
                state.focused      = 1
                state.scrollOffset = 0
                refresh()
                return
            end
            advanceFromNoun()
        end,
        escape = function()
            if not popStage() then close() end
        end,
        verbQuickPick = function(n)
            if state.stage ~= "noun" then return end
            local item = state.items[state.focused]
            if not item then return end
            local default = item.defaultVerb or "activate"
            local count = 0
            for _, vid in ipairs(item.verbs or {}) do
                if vid ~= default then
                    count = count + 1
                    if count == n then
                        local verb = verbs[vid]
                        if verb then runVerb(verb, item) end
                        return
                    end
                end
            end
        end,
        itemQuickPick = function(n)
            -- 1..9 selects the Nth visible row (scroll-adjusted) and runs its
            -- default verb. Works on both noun and verb stages.
            local globalIdx = (state.scrollOffset or 0) + n
            local row = state.items[globalIdx]
            if not row then return end
            state.focused = globalIdx
            if state.stage == "noun" then
                local verb = verbs[row.defaultVerb or "activate"]
                if verb then runVerb(verb, row) end
            elseif state.stage == "verb" then
                local verb = row.payload and row.payload.verb
                if verb then runVerb(verb, state.selectedItem) end
            end
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
Palette.isOpen  = function() return state.open end
Palette.verbs   = verbs
Palette._state  = state
Palette._hotkey = hotkeyBinding

return Palette
