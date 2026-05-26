-- Muse: an inline AI companion. Double-tap right ⌘ to summon near the text caret.
-- If text is selected when summoned, it's auto-attached as context.
--
-- While the overlay is open:
--   type → ask, Enter → submit (or, with empty buffer, paste the latest reply
--   into the focused field), Esc → cancel.
--   ⌘⇧S → capture a region and attach as image.
--   ⌘⇧V → attach clipboard contents as text context.
--   ⌘⌫ → clear attachments and context.
-- Double-tap right ⌘ within continueMs of last close → conversation continues.

local Muse             = {}
-- Break a recursive-require cycle: backends do `require("Muse")` at their top
-- level. autoloadBackends() runs before this module returns, so package.loaded
-- isn't set yet — without this line each backend re-executes Muse from scratch,
-- creating duplicate state tables and orphan eventtaps until the C stack overflows.
package.loaded["Muse"] = Muse

local eventtap         = hs.eventtap
local etypes           = eventtap.event.types
local canvas           = hs.canvas
local timer            = hs.timer
local ax               = hs.axuielement
local taskmod          = hs.task
local alert            = hs.alert
local pb               = hs.pasteboard
local json             = hs.json
local screen           = hs.screen
local keymap           = hs.keycodes.map

----------------------------------------------------------------------
-- Config
----------------------------------------------------------------------

Muse.config            = {
    backend        = "claudecli", -- "claude" | "openai" | "gemini" | "fabric" | "claudecli" | "apple"
    fallbackOrder  = { "claudecli", "claude", "openai", "gemini", "fabric", "apple" },
    font           = ".AppleSystemUIFontMedium",
    fontSize       = 20,
    rightCmdCode   = 54, -- right ⌘
    backends       = {}, -- per-plugin config: Muse.config.backends[name] = { ... }

    -- House-style system prompt tuned for the Enter-paste flow. Set to nil to
    -- disable globally; per-backend override lives at
    -- Muse.config.backends[<name>].systemPrompt. Fabric ignores this (patterns
    -- ARE its system prompt).
    systemPrompt   = [[You are Muse, a quiet inline assistant invoked next to the user's text caret. Your reply may be pasted directly into the field they were working in.

Reply concisely. No preamble ("Sure!", "Here is...", "Certainly"). No closing offers ("Let me know if...", "Hope this helps"). No meta-commentary about your own response. Match the user's tone, register, and length — short questions get short replies.

Plain text by default. Use Markdown or code fences only when explicitly asked or when the content genuinely requires it (e.g. actual code).

If <context>...</context> appears, that is the text the user wants to discuss. Do not echo it back. Rewrite requests get just the rewritten text. Questions get just the answer.]],

    layout = {
        overlayWidth   = 540,
        inputHeight    = 46,
        responseHeight = 260,
        anchorOffset   = 8,
        pad            = 8,
        screenMargin   = 8,                   -- min gap between overlay and screen edge

        chipWidth      = 76,                  -- horizontal budget for the attachment chip
        cardSize       = 30,                  -- thumbnail edge length
        cardStep       = 12,                  -- left-edge offset between stacked cards
        cardAlphas     = { 0.55, 0.8, 1.0 },  -- back, middle, front depth

        statusDotW     = 20,
        dotGap         = 8,
        dotRadius      = 3,
        dotRowH        = 14,                  -- extra canvas row reserved for streaming-dots beneath the AI reply

        cornerRadius   = 4,
        cursorWidth    = 1.5,

        userFontSize   = 17,                  -- two-tier type: user prompts smaller than AI replies
        userAlpha      = 0.7,                 -- and dimmer; AI replies stay at fg/spinner full alpha

        pairAlphas     = { 1.0, 0.55, 0.35 }, -- per-turn-pair opacity falloff (latest → older)

        railWidth      = 2,
        railInset      = 2,                   -- distance from canvas edge to rail
        railMaxTurns   = 12,                  -- pre-allocated rail slots (visible cap is well below this)

        enterGlyphSize = 12,                  -- "↵" affordance beside the latest AI reply

        fadeMaskStrips = 6,                   -- stacked alpha strips approximating a gradient at the top
        fadeMaskTotalH = 18,
    },

    timings = {
        doubleTapMs     = 250,
        continueMs      = 600,
        bouncePeriod    = 1.1,    -- status-dot wave period (s)
        bounceSigma     = 0.08,   -- Gaussian width of each bounce peak
        settledHoldS    = 0.35,   -- after stream ends, hold the dot before fading
        settledFadeS    = 0.25,   -- alpha fade-to-zero duration
        animFrameS      = 0.016,  -- ~60fps timer step
        sizeAnimS       = 0.18,   -- canvas resize tween duration
        cursorBlinkS    = 0.53,
        rebuildThrottle = 0.1,
        pasteInjectS    = 0.04,
        pasteRestoreS   = 0.12,
    },
}

local cfg              = Muse.config

local C                = {
    bg      = { white = 0, alpha = 0.95 },
    fg      = { white = 1, alpha = 1 },
    muted   = { white = 1, alpha = 0.55 },
    accent  = { red = 0.40, green = 0.78, blue = 1.00, alpha = 1 },
    spinner = { red = 0.10, green = 0.30, blue = 0.90, alpha = 0.80 }, -- match WindowScape outlineColor
    error   = { red = 1.00, green = 0.40, blue = 0.40, alpha = 1 },
}

local textShadow       = {
    offset = { h = -1, w = 0 },
    blurRadius = 2,
    color = { alpha = 1 },
}

----------------------------------------------------------------------
-- Backends: registry, helpers, autoload
--   Each plugin under ~/.hammerspoon/Muse/backends/*.lua returns:
--     { name = "...", available = fn -> bool,reason, stream = fn(self, prompt, history, onChunk, onDone, onError) -> task }
--   Plugin config lives in Muse.config.backends[name]; plugins seed their own defaults.
--   Shared helpers exposed via Muse.helpers; access from a plugin via:
--     local M = require("Muse"); local h = M.helpers
----------------------------------------------------------------------

Muse.backends          = {}

Muse.helpers           = {
    json     = hs.json,
    alert    = hs.alert,
    taskmod  = hs.task,
    eventtap = hs.eventtap,
    parseSSE = function(buf, perLine)
        for line in buf:gmatch("[^\r\n]+") do perLine(line) end
    end,
    -- Per-backend override wins, then the global default, then nil. Backends
    -- call this and apply the result natively (system field, --system flag, etc.).
    systemPrompt = function(backendName)
        local bcfg = Muse.config.backends[backendName]
        if bcfg and bcfg.systemPrompt ~= nil then return bcfg.systemPrompt end
        return Muse.config.systemPrompt
    end,
    -- POSIX-safe single-quote shell quoting for embedding strings in shell command
    -- lines. `'foo'\''bar'` is the standard escape for an embedded apostrophe.
    shellQuote = function(s)
        return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
    end,
    newTask  = function(cmd, args, stdin, onLine, onDone, onError)
        local t = taskmod.new(cmd,
            function(code, _, stderr)
                if code ~= 0 and onError then onError(stderr ~= "" and stderr or ("exit " .. code)) end
                if onDone then onDone() end
            end,
            function(_, stdout, _)
                if stdout and #stdout > 0 then onLine(stdout) end
                return true
            end,
            args)
        if stdin then t:setInput(stdin) end
        t:start()
        -- Without closeInput, hs.task leaves the child's stdin open, so subprocesses
        -- that read until EOF (claude CLI, fabric, etc.) hang forever.
        if stdin then t:closeInput() end
        return t
    end,
}

function Muse.register(b)
    assert(type(b) == "table", "Muse.register: expected table")
    assert(type(b.name) == "string" and b.name ~= "", "Muse.register: missing name")
    assert(type(b.available) == "function", "Muse.register: missing available()")
    assert(type(b.stream) == "function", "Muse.register: missing stream()")
    Muse.backends[b.name] = b
    return b
end

local function autoloadBackends()
    local dir = os.getenv("HOME") .. "/.hammerspoon/Muse/backends"
    local iter, dirobj = hs.fs.dir(dir)
    if not iter then return end
    for name in iter, dirobj do
        if name:match("%.lua$") then
            local modname = "Muse.backends." .. name:sub(1, -5)
            local ok, result = pcall(require, modname)
            if not ok then
                print("Muse: failed to load " .. modname .. ": " .. tostring(result))
            elseif type(result) == "table" and result.name and not Muse.backends[result.name] then
                Muse.register(result)
            end
        end
    end
end

local function reportBackendStatus()
    local ready = {}
    for name, b in pairs(Muse.backends) do
        local ok = b.available()
        if ok then ready[#ready + 1] = name end
    end
    table.sort(ready)
    if #ready > 0 then
        print("Muse: ready backends: " .. table.concat(ready, ", "))
    else
        print("Muse: no backends ready (open overlay for setup hints)")
    end
end

local function chooseBackend(opts)
    local needsVision = opts and opts.needsVision
    local function ok(b)
        if not b then return false end
        if needsVision and not b.multimodal then return false end
        local available = b.available()
        return available and true or false
    end
    local primary = Muse.backends[cfg.backend]
    if ok(primary) then return primary end
    if primary and not needsVision then
        local _, why = primary.available()
        print("Muse: " .. cfg.backend .. " unavailable (" .. (why or "?") .. "), trying fallbacks")
    end
    for _, n in ipairs(cfg.fallbackOrder) do
        local b = Muse.backends[n]
        if b ~= primary and ok(b) then return b end
    end
    return nil
end

----------------------------------------------------------------------
-- Anchor: caret rect with fallbacks
----------------------------------------------------------------------

local function focusedElement()
    local el
    pcall(function() el = ax.systemWideElement():attributeValue("AXFocusedUIElement") end)
    return el
end

-- Pull the currently-selected text from the focused UI element via AX.
-- Returns nil for unsupported controls (Terminal, many Electron apps) or empty
-- selections — caller falls back to ⌘⇧V (clipboard) for those cases.
local function selectedText()
    local s
    pcall(function()
        local el = focusedElement()
        if not el then return end
        local v = el:attributeValue("AXSelectedText")
        if type(v) == "string" and v ~= "" then s = v end
    end)
    return s
end

-- Reject degenerate rects. AX returns {0,0,0,0} for empty docs, dead pids,
-- and Terminal — Lua treats 0 as truthy, so a plain presence check accepts
-- them and pins the overlay to the top-left.
local function rectValid(r)
    return type(r) == "table"
        and type(r.x) == "number" and type(r.y) == "number"
        and (r.w or 0) > 0 and (r.h or 0) > 0
end

local function screenContaining(x, y)
    for _, s in ipairs(screen.allScreens()) do
        local f = s:fullFrame()
        if x >= f.x and x < f.x + f.w and y >= f.y and y < f.y + f.h then return s end
    end
    return nil
end

local function focusedWindowFrame()
    local frame
    pcall(function()
        local app = hs.application.frontmostApplication()
        local win = app and app:focusedWindow()
        if win then frame = win:frame() end
    end)
    return frame
end

-- Best-effort caret / selection / focused-element / focused-window rect.
-- Returns nil if nothing usable can be found.
local function anchorRect()
    local rect
    pcall(function()
        local el = focusedElement()
        if not el then return end
        local range = el:attributeValue("AXSelectedTextRange")
        if range then
            local b = el:parameterizedAttributeValue("AXBoundsForRange", range)
            if rectValid(b) then
                rect = b; return
            end
        end
        local frame = el:attributeValue("AXFrame")
        if rectValid(frame) then rect = frame end
    end)
    if rect then return rect end
    local wf = focusedWindowFrame()
    if rectValid(wf) then return wf end
    return nil
end

-- Decide overlay placement: leading-x, pinned input-top y, and the screen
-- frame to clamp future growth against. Input always sits below the caret;
-- if there isn't enough room, the overlay slides up to stay inside the
-- screen — even if that means visually overlapping the caret line.
local function placeOverlay()
    local r = anchorRect()
    local leadX, trailX, bottom
    if r then
        leadX, trailX = r.x, r.x + r.w
        bottom = r.y + r.h
    else
        local p = hs.mouse.absolutePosition()
        leadX, trailX = p.x, p.x
        bottom = p.y
    end

    local scr = screenContaining(leadX, bottom)
    if not scr then
        local p = hs.mouse.absolutePosition()
        scr = screenContaining(p.x, p.y) or screen.mainScreen()
        leadX, trailX = p.x, p.x
        bottom = p.y
    end
    local sf = scr:fullFrame()
    local mar = cfg.layout.screenMargin

    -- Horizontal: prefer leading-edge alignment with the caret. If the overlay
    -- would overflow the right edge, right-align its right edge to the trailing
    -- edge of the caret/selection so the visual anchor stays meaningful.
    local x = leadX
    if x + cfg.layout.overlayWidth > sf.x + sf.w - mar then
        x = trailX - cfg.layout.overlayWidth
    end
    if x < sf.x + mar then x = sf.x + mar end
    if x + cfg.layout.overlayWidth > sf.x + sf.w - mar then
        x = sf.x + sf.w - cfg.layout.overlayWidth - mar
    end

    -- Vertical: always below the caret; slide up only enough to keep the input
    -- inside the screen.
    local inputTop = bottom + cfg.layout.anchorOffset
    if inputTop + cfg.layout.inputHeight > sf.y + sf.h - mar then
        inputTop = sf.y + sf.h - mar - cfg.layout.inputHeight
    end
    if inputTop < sf.y + mar then inputTop = sf.y + mar end

    return x, inputTop, sf
end

----------------------------------------------------------------------
-- Paste-injection (clipboard hack, like AnyComplete)
----------------------------------------------------------------------

local function pasteText(text)
    local saved = pb.getContents()
    pb.setContents(text)
    eventtap.keyStroke({ "cmd" }, "v", 0)
    timer.doAfter(cfg.timings.pasteRestoreS, function() if saved then pb.setContents(saved) end end)
end

----------------------------------------------------------------------
-- Overlay
----------------------------------------------------------------------

local state = {
    open         = false,
    canv         = nil,
    inputTap     = nil,
    buffer       = "",
    response     = "",
    history      = {},
    attachments  = {},
    textContext  = nil, -- selection or clipboard text attached as context
    capturing    = false,
    expanded     = false,
    task         = nil,
    lastClose    = 0,
    lastRCmdEdge = 0,
    rCmdHeld     = false,
    anchorX      = 0,
    inputTop     = 0,
    screenFrame  = nil,
    statusKind   = "idle",
    streamDotY   = nil, -- y-position where the bouncing dots should ride (below streaming response); nil = input row
    pulseActive  = false, -- true while the active→idle fade is playing; keeps dotRow reserved during the fade
}

local close, submitPrompt, commitResponse, rebuildResponse, applyCanvasFrame

-- Where the i-th bouncing dot (0..2) should sit. When streamDotY is set, the
-- row hangs below the streaming response (dots aligned to the left padding).
-- Otherwise the dots ride at the right edge of the input row.
local function activeDotCenter(i)
    local frameW = state.canv:frame().w
    local gap    = cfg.layout.dotGap
    local r      = cfg.layout.dotRadius
    if state.streamDotY then
        local baseX = cfg.layout.pad + r
        return baseX + i * gap, state.streamDotY
    end
    local baseX = frameW - cfg.layout.pad - r
    return baseX - (2 - i) * gap, cfg.layout.inputHeight / 2
end

local function setStatus(kind, reposition)
    if not state.canv then return end
    local prevKind = state.statusKind
    if (not reposition) and state.statusTimer then
        state.statusTimer:stop(); state.statusTimer = nil
    end
    state.statusKind = kind
    local dotR = cfg.layout.dotRadius
    if kind == "active" then
        -- Three-dot bouncing wave during streaming. Position recomputed each
        -- frame so the dots ride beneath the streaming AI reply once
        -- state.streamDotY is set.
        for i = 0, 2 do
            state.canv[3 + i].action    = "fill"
            state.canv[3 + i].radius    = dotR
            state.canv[3 + i].fillColor = C.spinner
        end
        if reposition then
            for i = 0, 2 do
                local cx, cy = activeDotCenter(i)
                state.canv[3 + i].center = { x = cx, y = cy }
            end
        else
            local t0           = timer.secondsSinceEpoch()
            local period       = cfg.timings.bouncePeriod
            local bounceHeight = 4
            local sigma        = cfg.timings.bounceSigma
            state.statusTimer  = timer.doEvery(cfg.timings.animFrameS, function()
                if not state.canv then return end
                local t = ((timer.secondsSinceEpoch() - t0) / period) % 1
                for i = 0, 2 do
                    local peakAt = (i + 0.5) / 3
                    local d = t - peakAt
                    if d > 0.5 then d = d - 1 elseif d < -0.5 then d = d + 1 end
                    local lift = bounceHeight * math.exp(-(d * d) / (2 * sigma * sigma))
                    local cx, cy = activeDotCenter(i)
                    state.canv[3 + i].center = { x = cx, y = cy - lift }
                end
            end)
        end
    elseif kind == "error" then
        -- Errors are surfaced via the input row regardless of streamDotY —
        -- the response area may already hold a partial stream when this fires.
        local frameW = state.canv:frame().w
        state.canv[3].action    = "fill"
        state.canv[3].radius    = dotR + 0.5
        state.canv[3].fillColor = C.error
        state.canv[3].center    = { x = frameW - cfg.layout.pad - dotR, y = cfg.layout.inputHeight / 2 }
        state.canv[4].action    = "skip"
        state.canv[5].action    = "skip"
    else
        -- Idle: empty by default. Pulse-then-fade only when punctuating a
        -- completed stream (active → idle); other paths stay silent.
        if (not reposition) and prevKind == "active" then
            -- Snapshot the dot's center now; state.streamDotY may change as
            -- onDone rebuilds the panel with state.response cleared.
            local pulseCx, pulseCy  = activeDotCenter(2)
            state.pulseActive       = true
            state.canv[3].action    = "fill"
            state.canv[3].radius    = dotR + 0.5
            state.canv[3].fillColor = C.spinner
            state.canv[3].center    = { x = pulseCx, y = pulseCy }
            state.canv[4].action    = "skip"
            state.canv[5].action    = "skip"
            local t0    = timer.secondsSinceEpoch()
            local holdS = cfg.timings.settledHoldS
            local fadeS = cfg.timings.settledFadeS
            local base  = C.spinner
            state.statusTimer = timer.doEvery(cfg.timings.animFrameS, function()
                if not state.canv then return end
                local elapsed = timer.secondsSinceEpoch() - t0
                if elapsed >= holdS + fadeS then
                    state.canv[3].action    = "skip"
                    state.canv[3].fillColor = base
                    if state.statusTimer then state.statusTimer:stop(); state.statusTimer = nil end
                    state.pulseActive = false
                    -- Shrink the canvas now that the dot row is no longer needed.
                    if rebuildResponse then rebuildResponse() end
                    return
                end
                local alpha = (elapsed < holdS) and 1 or (1 - (elapsed - holdS) / fadeS)
                state.canv[3].fillColor = {
                    red   = base.red,
                    green = base.green,
                    blue  = base.blue,
                    alpha = (base.alpha or 1) * alpha,
                }
            end)
        else
            state.canv[3].action = "skip"
            state.canv[4].action = "skip"
            state.canv[5].action = "skip"
        end
    end
end

-- Position input-row elements (input text + status dots) inside the canvas.
-- Input always sits at the top of the canvas; called once at open and after
-- every resize.
local function relayout()
    if not state.canv then return end
    local frameW        = state.canv:frame().w
    local inputTextY    = math.floor((cfg.layout.inputHeight - cfg.fontSize) / 2) - 2
    -- Right edge reserves space for status dot plus chips when visible.
    local hasImages     = (#state.attachments > 0)
    local hasText       = (state.textContext and state.textContext ~= "")
    local imageReserved = hasImages and (cfg.layout.chipWidth + cfg.layout.pad) or 0
    local textReserved  = hasText and (cfg.layout.cardSize + cfg.layout.pad) or 0
    local rightReserve  = cfg.layout.statusDotW + imageReserved + textReserved
    state.canv[2].frame = {
        x = cfg.layout.pad,
        y = inputTextY,
        w = math.max(0, frameW - cfg.layout.pad - rightReserve),
        h = cfg.fontSize + 8,
    }
    local chipRight = frameW - cfg.layout.pad - 20
    local cardY = math.floor((cfg.layout.inputHeight - cfg.layout.cardSize) / 2)
    -- c[9..11] = back→front; cards overlap so they read as a stack.
    state.canv[11].frame = { x = chipRight - cfg.layout.cardSize,                    y = cardY, w = cfg.layout.cardSize, h = cfg.layout.cardSize }
    state.canv[10].frame = { x = chipRight - cfg.layout.cardSize - cfg.layout.cardStep,     y = cardY, w = cfg.layout.cardSize, h = cfg.layout.cardSize }
    state.canv[9].frame  = { x = chipRight - cfg.layout.cardSize - 2 * cfg.layout.cardStep, y = cardY, w = cfg.layout.cardSize, h = cfg.layout.cardSize }
    state.canv[8].frame = {
        x = chipRight - cfg.layout.cardSize - 2 * cfg.layout.cardStep - 18,
        y = math.floor((cfg.layout.inputHeight - 13) / 2) - 1,
        w = 16,
        h = 13 + 6,
    }
    -- Text-context chip: single card placed left of the image stack (or at the
    -- image stack's right-anchor when no images are present).
    local imageStackLeftEdge = chipRight - cfg.layout.cardSize - 2 * cfg.layout.cardStep
    local textChipX = hasImages
        and (imageStackLeftEdge - cfg.layout.pad - cfg.layout.cardSize)
        or (chipRight - cfg.layout.cardSize)
    state.canv[12].frame = { x = textChipX, y = cardY, w = cfg.layout.cardSize, h = cfg.layout.cardSize }
    -- c[13] label is shorter than the card; offset y to center it vertically.
    state.canv[13].frame = { x = textChipX, y = cardY + math.floor((cfg.layout.cardSize - 14) / 2), w = cfg.layout.cardSize, h = 16 }
    setStatus(state.statusKind or "idle", true)
end

local function inputStyled(text, color)
    return hs.styledtext.new(text, {
        font = { name = cfg.font, size = cfg.fontSize },
        color = color,
        shadow = textShadow,
    })
end

-- Decide the placeholder text + color for the current state. First match wins.
-- The "↵ paste reply" variant doubles as the Enter-paste affordance.
local function placeholderForState()
    if state.task and state.task:isRunning() then
        return "thinking…", C.muted
    end
    if #state.attachments > 0 then
        local s = (#state.attachments == 1) and "ask about the image…" or "ask about the images…"
        return s, C.muted
    end
    if state.textContext and state.textContext ~= "" then
        return "ask about the selection…", C.muted
    end
    if #state.history > 0 and not state.lastPrompt then
        return "↵ to insert · type to refine", C.accent
    end
    return "ask anything · ⌘⇧S to attach", C.muted
end

local function rebuildCursor()
    if not state.canv then return end
    local x = cfg.layout.pad
    if state.buffer ~= "" then
        local sz = state.canv:minimumTextSize(2, state.buffer)
        if sz and sz.w then x = cfg.layout.pad + sz.w end
    end
    local cursorH = cfg.fontSize + 4
    local cursorY = (cfg.layout.inputHeight - cursorH) / 2
    local visible = state.cursorOn and not (state.task and state.task:isRunning())
    state.canv[7].frame = { x = x, y = cursorY, w = cfg.layout.cursorWidth, h = cursorH }
    state.canv[7].fillColor = { white = 1, alpha = visible and 1.0 or 0 }
end

local function computeInputWidth()
    local probe = state.buffer ~= "" and state.buffer or placeholderForState()
    local styled = inputStyled(probe, C.fg)
    local sz = hs.drawing.getTextDrawingSize(styled)
    local textW = (sz and sz.w) or 100
    local imageChipW = (#state.attachments > 0) and (cfg.layout.chipWidth + cfg.layout.pad) or 0
    local textChipW = (state.textContext and state.textContext ~= "") and (cfg.layout.cardSize + cfg.layout.pad) or 0
    local dotW = cfg.layout.statusDotW
    local w = math.ceil(textW) + 2 * cfg.layout.pad + imageChipW + textChipW + dotW
    return math.min(cfg.layout.overlayWidth, w)
end

local function rebuildInput()
    if not state.canv then return end
    local nowEmpty = (state.buffer == "")
    if nowEmpty then
        local ph, color = placeholderForState()
        state.canv[2].text = inputStyled(ph, color)
    else
        state.canv[2].text = inputStyled(state.buffer, C.fg)
    end
    local n = #state.attachments
    -- Front (c[11]) shows the newest attachment; alpha dims older cards for depth.
    local alphas = cfg.layout.cardAlphas
    for slot = 0, 2 do
        local idx = 9 + slot
        local stepsFromFront = 2 - slot  -- slot 0 = back = 2 prior; slot 2 = front = newest
        local attIdx = n - stepsFromFront
        local att = (attIdx >= 1) and state.attachments[attIdx] or nil
        if att and att.img then
            state.canv[idx].action = "fill"
            state.canv[idx].image = att.img
            state.canv[idx].imageAlpha = alphas[slot + 1]
        else
            state.canv[idx].action = "skip"
            state.canv[idx].image = nil
        end
    end
    if n > 3 then
        state.canv[8].action = "fill"
        state.canv[8].text = hs.styledtext.new("+" .. (n - 3), {
            font = { name = cfg.font, size = 11 },
            color = C.accent,
            paragraphStyle = { alignment = "right" },
        })
    else
        state.canv[8].action = "skip"
        state.canv[8].text = ""
    end
    -- Text-context chip: a single card showing "T·<chars>" when context is attached.
    local hasText = (state.textContext and state.textContext ~= "")
    if hasText then
        state.canv[12].action = "strokeAndFill"
        state.canv[13].action = "fill"
        state.canv[13].text = hs.styledtext.new(string.format("T·%d", #state.textContext), {
            font = { name = cfg.font, size = 11 },
            color = C.accent,
            paragraphStyle = { alignment = "center" },
            shadow = textShadow,
        })
    else
        state.canv[12].action = "skip"
        state.canv[13].action = "skip"
        state.canv[13].text = ""
    end
    -- Re-run relayout in case chip presence changed: reserved widths and chip
    -- positions both depend on textContext/attachments, and in expanded mode the
    -- canvas width doesn't change here so applyCanvasFrame won't be invoked.
    relayout()
    if not state.expanded then
        local desiredW = computeInputWidth()
        local f = state.canv:frame()
        if math.abs(f.w - desiredW) >= 1 then
            applyCanvasFrame(desiredW, f.h)
        end
    end
    rebuildCursor()
    -- Toggle the "Enter target" highlight on the latest reply when buffer
    -- emptiness flips (empty → Enter pastes; non-empty → Enter submits).
    if state.bufferWasEmpty ~= nowEmpty then
        state.bufferWasEmpty = nowEmpty
        if state.canv and state.canv[6] then rebuildResponse() end
    end
end

local function captureRegion()
    if state.capturing or not state.canv then return end
    state.capturing = true
    local path = string.format("/tmp/muse-cap-%d-%d.png",
        hs.processInfo and hs.processInfo.processID or 0,
        math.floor(timer.secondsSinceEpoch() * 1000))
    -- Hide overlay so it doesn't appear in the shot; pause dismissTap so a
    -- mouse-up from screencapture's drag can't bubble up as an outside click.
    if state.dismissTap then state.dismissTap:stop() end
    state.canv:hide()
    local t = taskmod.new("/usr/sbin/screencapture",
        function(code, _, _)
            if state.canv then state.canv:show() end
            if state.dismissTap then state.dismissTap:start() end
            state.capturing = false
            if code ~= 0 then return end
            if not hs.fs.attributes(path) then return end
            local ok, img = pcall(hs.image.imageFromPath, path)
            if ok and img then
                local okEnc, url = pcall(function() return img:encodeAsURLString(false) end)
                if okEnc and type(url) == "string" then
                    local prefix = "data:image/png;base64,"
                    if url:sub(1, #prefix) == prefix then
                        table.insert(state.attachments, {
                            mime = "image/png",
                            base64 = url:sub(#prefix + 1),
                            img = img,
                        })
                        if state.canv then rebuildInput() end
                    end
                end
            end
            pcall(os.remove, path)
        end,
        { "-i", "-x", "-t", "png", path })
    t:start()
end

applyCanvasFrame = function(w, h)
    -- Prefer dropping below the caret (state.inputTop); if the canvas would
    -- overflow the screen bottom, shift the whole thing up so it still fits.
    local sf = state.screenFrame
    local mar = cfg.layout.screenMargin
    local y = state.inputTop
    if sf then
        local maxBottom = sf.y + sf.h - mar
        if y + h > maxBottom then y = maxBottom - h end
        if y < sf.y + mar then y = sf.y + mar end
    end
    state.canv:frame({
        x = state.anchorX,
        y = y,
        w = w,
        h = h,
    })
    relayout()
end

local function animateCanvasTo(targetW, targetH)
    if not state.canv then return end
    if state.sizeAnim then
        state.sizeAnim:stop(); state.sizeAnim = nil
    end
    local startF = state.canv:frame()
    local startW, startH = startF.w, startF.h
    if math.abs(startW - targetW) < 1 and math.abs(startH - targetH) < 1 then
        applyCanvasFrame(startW, startH)
        return
    end
    local t0 = timer.secondsSinceEpoch()
    local duration = cfg.timings.sizeAnimS
    state.sizeAnim = timer.doEvery(cfg.timings.animFrameS, function()
        if not state.canv then
            if state.sizeAnim then
                state.sizeAnim:stop(); state.sizeAnim = nil
            end
            return
        end
        local t = math.min((timer.secondsSinceEpoch() - t0) / duration, 1)
        local ease = 1 - (1 - t) * (1 - t) * (1 - t)
        applyCanvasFrame(
            startW + (targetW - startW) * ease,
            startH + (targetH - startH) * ease)
        if t >= 1 then
            state.sizeAnim:stop(); state.sizeAnim = nil
        end
    end)
end

-- Two-tier type: user prompts smaller and dimmer than AI replies. Opacity
-- falloff dims older turn-pairs (pairsBack 0 = latest pair, 1 = one back, …).
local function turnAttrs(kind, pairsBack)
    local pa    = cfg.layout.pairAlphas
    local alpha = pa[math.min(pairsBack + 1, #pa)]
    if kind == "user" then
        return {
            font           = { name = cfg.font, size = cfg.layout.userFontSize },
            color          = { white = 1, alpha = alpha * cfg.layout.userAlpha },
            paragraphStyle = { alignment = "right" },
            shadow         = textShadow,
        }
    end
    return {
        font           = { name = cfg.font, size = cfg.fontSize },
        color          = { white = 1, alpha = alpha },
        paragraphStyle = { alignment = "left" },
        shadow         = textShadow,
    }
end

-- composeTurns flattens history + pending prompt/response into a normalized
-- list of { kind, content, isLatest } entries (kind = "user" | "assistant").
local function composeTurns(skipTurns)
    local turns = {}
    for i = (skipTurns or 0) + 1, #state.history do
        local msg = state.history[i]
        turns[#turns + 1] = { kind = msg.role, content = msg.content }
    end
    if state.lastPrompt then
        turns[#turns + 1] = { kind = "user", content = state.lastPrompt }
        if state.response ~= "" then
            turns[#turns + 1] = { kind = "assistant", content = state.response }
        end
    elseif state.response ~= "" then
        -- No pending prompt → response is guidance/error text; render as AI.
        turns[#turns + 1] = { kind = "assistant", content = state.response }
    end
    for i = #turns, 1, -1 do
        if turns[i].kind == "assistant" then
            turns[i].isLatest = true; break
        end
    end
    return turns
end

-- buildTurns builds the full styledtext transcript AND measures each turn's
-- cumulative y-offset + height inside c[6], so rails and the Enter glyph can be
-- positioned per-turn. Requires c[6].frame.w to be set before invocation —
-- minimumTextSize uses the element's current width for wrap calculations.
local function buildTurns(turns)
    local accStyled, accH = nil, 0
    local measured = {}
    for i, turn in ipairs(turns) do
        local pairsBack = math.floor((#turns - i) / 2)
        local attrs = turnAttrs(turn.kind, pairsBack)
        local text = turn.content
        if i < #turns then text = text .. "\n\n" end
        local s = hs.styledtext.new(text, attrs)
        accStyled = accStyled and (accStyled .. s) or s
        local sz = state.canv:minimumTextSize(6, accStyled)
        local newH = (sz and sz.h) or 0
        measured[i] = {
            kind     = turn.kind,
            isLatest = turn.isLatest,
            y        = accH,
            h        = newH - accH,
        }
        accH = newH
    end
    return accStyled, measured, accH
end

rebuildResponse = function()
    if not state.canv then return end
    -- Decide target width: once any response/history is present, expand to
    -- cfg.layout.overlayWidth and stay there for the rest of the session.
    local hasContent = (#state.history > 0) or state.response ~= "" or state.lastPrompt
    local targetW
    if hasContent then
        state.expanded = true
        targetW = cfg.layout.overlayWidth
    else
        targetW = computeInputWidth()
    end
    -- Cap response height by absolute screen height (minus input + margins).
    -- The canvas shifts upward when it would overflow the bottom edge — see
    -- applyCanvasFrame — so we don't need to reserve only the space below.
    local sf = state.screenFrame
    local mar = cfg.layout.screenMargin
    local availH = sf.h - 2 * mar - cfg.layout.inputHeight - 6
    if availH < 0 then availH = 0 end
    local maxH = math.min(cfg.layout.responseHeight, availH)
    local frameW = targetW - 2 * cfg.layout.pad
    local respY = cfg.layout.inputHeight + 4
    -- Frame width must be set before measurement so styledtext wraps correctly.
    state.canv[6].frame = { x = cfg.layout.pad, y = respY, w = frameW, h = maxH }

    -- Iteratively drop oldest turns until the styled transcript fits the cap.
    local skip = 0
    local turns, styled, measured, measuredH = {}, nil, {}, 0
    while true do
        turns = composeTurns(skip)
        if #turns == 0 then break end
        styled, measured, measuredH = buildTurns(turns)
        if measuredH <= maxH then break end
        if skip + 2 > #state.history then break end -- can't drop the pending turn
        skip = skip + 2
    end
    state.canv[6].text = styled or ""
    local contentH = math.min(math.ceil(measuredH) + 4, maxH)
    if measuredH <= 0 then contentH = 0 end
    state.canv[6].frame = { x = cfg.layout.pad, y = respY, w = frameW, h = contentH }

    -- Author rails for AI turns only. User prompts already read as user via
    -- right-alignment + smaller/dimmer text; a second rail there was visual
    -- noise. Brightness follows pairAlphas so the latest AI pops.
    local railBase  = 14
    local railSlots = cfg.layout.railMaxTurns
    local pa        = cfg.layout.pairAlphas
    for slot = 0, railSlots - 1 do
        local idx  = railBase + slot
        local turn = measured[slot + 1]
        if turn and turn.kind == "assistant" then
            local pairsBack = math.floor((#measured - (slot + 1)) / 2)
            local alpha     = pa[math.min(pairsBack + 1, #pa)]
            state.canv[idx].action    = "fill"
            state.canv[idx].fillColor = {
                red   = C.spinner.red,
                green = C.spinner.green,
                blue  = C.spinner.blue,
                alpha = (C.spinner.alpha or 1) * alpha,
            }
            state.canv[idx].frame = {
                x = cfg.layout.railInset,
                y = respY + turn.y,
                w = cfg.layout.railWidth,
                h = math.max(turn.h - 6, 4),
            }
        else
            state.canv[idx].action = "skip"
        end
    end

    -- The Enter-paste affordance lives in the input-row placeholder
    -- ("↵ to insert · type to refine") when buffer is empty + history exists.
    -- No glyph in the response area — that was redundant.
    state.canv[railBase + railSlots].action = "skip"
    local streaming = state.task and state.task:isRunning()

    -- Top fade-mask: visible only when we dropped older turns to fit. Stacked
    -- alpha strips approximate a black→transparent gradient at the top of the
    -- response area, signalling "there's more above" instead of silently lying.
    local fadeBase  = enterIdx + 1
    local nStrips   = cfg.layout.fadeMaskStrips
    if skip > 0 and contentH > 0 then
        local stripH = cfg.layout.fadeMaskTotalH / nStrips
        for s = 0, nStrips - 1 do
            local stripAlpha = (1 - s / (nStrips - 1)) * (C.bg.alpha or 1)
            state.canv[fadeBase + s].action    = "fill"
            state.canv[fadeBase + s].fillColor = { white = 0, alpha = stripAlpha }
            state.canv[fadeBase + s].frame     = {
                x = 0, y = respY + s * stripH, w = targetW, h = stripH + 1,
            }
        end
    else
        for s = 0, nStrips - 1 do
            state.canv[fadeBase + s].action = "skip"
        end
    end

    -- Reserve a row beneath the response for the streaming dots when the AI is
    -- writing into the panel. Kept active during the post-stream pulse-fade so
    -- the dots don't fly back to the input row mid-animation.
    local needsDotRow = (state.response ~= "" and streaming) or state.pulseActive
    local dotRowH     = needsDotRow and cfg.layout.dotRowH or 0
    if needsDotRow then
        state.streamDotY = respY + contentH + math.floor(dotRowH / 2)
    else
        state.streamDotY = nil
    end

    local targetCanvasH = cfg.layout.inputHeight
        + (contentH > 0 and 6 + contentH or 0)
        + dotRowH
    animateCanvasTo(targetW, targetCanvasH)
end

local rebuildPendingTimer = nil
local rebuildLastAt = 0
local function rebuildResponseThrottled()
    local now = timer.secondsSinceEpoch()
    if now - rebuildLastAt >= cfg.timings.rebuildThrottle then
        if rebuildPendingTimer then
            rebuildPendingTimer:stop(); rebuildPendingTimer = nil
        end
        rebuildLastAt = now
        rebuildResponse()
    elseif not rebuildPendingTimer then
        rebuildPendingTimer = timer.doAfter(cfg.timings.rebuildThrottle - (now - rebuildLastAt), function()
            rebuildPendingTimer = nil
            rebuildLastAt = timer.secondsSinceEpoch()
            rebuildResponse()
        end)
    end
end

local function newOverlay()
    -- Initial canvas covers just the input row. Width starts as fit-to-text
    -- when the session is fresh; expanded state (set by rebuildResponse) jumps
    -- straight to cfg.layout.overlayWidth.
    local initW = state.expanded and cfg.layout.overlayWidth or computeInputWidth()
    local c = canvas.new({
        x = state.anchorX,
        y = state.inputTop,
        w = initW,
        h = cfg.layout.inputHeight,
    })
    c[1] = {
        type = "rectangle",
        action = "fill",
        fillColor = C.bg,
        roundedRectRadii = { xRadius = cfg.layout.cornerRadius, yRadius = cfg.layout.cornerRadius },
    }
    c[2] = {
        type = "text",
        text = "",
        textFont = cfg.font,
        textSize = cfg.fontSize,
        textColor = C.muted,
        frame = { x = cfg.layout.pad, y = 0, w = math.max(0, initW - cfg.layout.pad - 20), h = cfg.fontSize + 8 },
    }
    -- Status indicator slots (3-5). One dot shown idle/error, three animated for "active".
    for i = 0, 2 do
        c[3 + i] = {
            type = "circle",
            action = "skip",
            fillColor = C.spinner,
            center = { x = 0, y = 0 },
            radius = 3,
        }
    end
    c[6] = {
        type = "text",
        text = "",
        textFont = cfg.font,
        textSize = cfg.fontSize,
        textColor = C.fg,
        frame = { x = cfg.layout.pad, y = cfg.layout.inputHeight + 4, w = math.max(0, initW - 2 * cfg.layout.pad), h = 0 },
    }
    -- Text cursor: a thin rectangle drawn separately from the text element so
    -- blinking it on/off can't shift the placeholder layout.
    c[7] = {
        type = "rectangle",
        action = "fill",
        fillColor = { white = 1, alpha = 0 },
        frame = { x = cfg.layout.pad, y = 0, w = cfg.layout.cursorWidth, h = cfg.fontSize + 4 },
    }
    -- Attachment chip: c[8] = "+N" overflow; c[9..11] = thumbnail cards (back→front).
    -- Frames set in relayout(); image + visibility set in rebuildInput().
    c[8] = {
        type = "text",
        text = "",
        action = "skip",
        textFont = cfg.font,
        textSize = 11,
        textColor = C.accent,
        frame = { x = 0, y = 0, w = 14, h = cfg.layout.inputHeight },
    }
    for i = 0, 2 do
        c[9 + i] = {
            type = "image",
            action = "skip",
            image = nil,
            imageAlignment = "center",
            imageScaling = "scaleToFit",
            imageAlpha = 1.0,
            frame = { x = 0, y = 0, w = cfg.layout.cardSize, h = cfg.layout.cardSize },
        }
    end
    -- Text-context chip: c[12] rect + c[13] "T·N" label. Visibility/position set
    -- in rebuildInput() and relayout(); only one chip ever shows.
    c[12] = {
        type = "rectangle",
        action = "skip",
        fillColor = { white = 0.18, alpha = 0.95 },
        strokeColor = C.accent,
        strokeWidth = 0.6,
        roundedRectRadii = { xRadius = 3, yRadius = 3 },
        frame = { x = 0, y = 0, w = cfg.layout.cardSize, h = cfg.layout.cardSize },
    }
    c[13] = {
        type = "text",
        action = "skip",
        text = "",
        textFont = cfg.font,
        textSize = 11,
        textColor = C.accent,
        frame = { x = 0, y = 0, w = cfg.layout.cardSize, h = 16 },
    }
    -- Author rails: pre-allocated rail slots positioned per-turn by rebuildResponse.
    -- Color and side are decided at render-time based on turn kind (user/AI).
    local railBase = 14
    for i = 0, cfg.layout.railMaxTurns - 1 do
        c[railBase + i] = {
            type = "rectangle",
            action = "skip",
            fillColor = C.muted,
            frame = { x = 0, y = 0, w = cfg.layout.railWidth, h = 0 },
        }
    end
    -- Enter-target glyph: small "↵" beside the latest AI reply when buffer is empty.
    -- Index sits right after the rail block so additions are easy to spot.
    local enterIdx = railBase + cfg.layout.railMaxTurns -- c[26]
    c[enterIdx] = {
        type = "text",
        action = "skip",
        text = "",
        textFont = cfg.font,
        textSize = cfg.layout.enterGlyphSize,
        textColor = C.spinner,
        frame = { x = 0, y = 0, w = 14, h = cfg.layout.enterGlyphSize + 4 },
    }
    -- Top fade-mask: stacked alpha strips approximating a gradient. Visible only
    -- when buildTranscript dropped older turns to fit the vertical cap.
    local fadeBase = enterIdx + 1 -- c[27..]
    for i = 0, cfg.layout.fadeMaskStrips - 1 do
        c[fadeBase + i] = {
            type = "rectangle",
            action = "skip",
            fillColor = { white = 0, alpha = 0 },
            frame = { x = 0, y = 0, w = 0, h = 0 },
        }
    end
    c:level(canvas.windowLevels.overlay)
    c:behaviorAsLabels({ "canJoinAllSpaces", "stationary" })
    c:show()
    return c
end

----------------------------------------------------------------------
-- Input eventtap (active only while overlay is open)
----------------------------------------------------------------------

local function onInputKey(event)
    if not state.open then return false end
    local code         = event:getKeyCode()
    local flags        = event:getFlags()
    local key          = keymap[code]
    local chars        = event:getCharacters(true) or ""

    local cmdOnly      = flags.cmd and not flags.alt and not flags.ctrl and not flags.shift
    local cmdShiftOnly = flags.cmd and flags.shift and not flags.alt and not flags.ctrl

    if cmdShiftOnly and key == "s" then
        captureRegion()
        return true
    end

    if cmdShiftOnly and key == "v" then
        local clip = pb.getContents()
        if clip and clip ~= "" then
            state.textContext = clip
            rebuildInput()
        end
        return true
    end

    if cmdOnly and key == "delete" then
        if #state.attachments > 0 or (state.textContext and state.textContext ~= "") then
            state.attachments = {}
            state.textContext = nil
            rebuildInput()
        end
        return true
    end

    if key == "escape" then
        close(); return true
    end

    if key == "return" and not (flags.cmd or flags.alt or flags.ctrl) then
        if state.task and state.task:isRunning() then return true end
        if state.buffer ~= "" then
            submitPrompt()
        else
            -- Empty buffer + Enter → paste the latest reply into the focused field.
            commitResponse()
        end
        return true
    end

    if key == "delete" then
        state.buffer = state.buffer:sub(1, -2)
        rebuildInput()
        return true
    end

    -- Printable input (no modifiers other than shift/alt-for-accents)
    if chars and #chars > 0 and not flags.cmd and not flags.ctrl then
        local b = chars:byte(1)
        if b and b >= 32 and b ~= 127 then
            state.buffer = state.buffer .. chars
            rebuildInput()
            return true
        end
    end

    return true
end

----------------------------------------------------------------------
-- Open / close / submit / commit
----------------------------------------------------------------------

local function open(opts)
    if state.open then return end
    opts                  = opts or {}
    local x, inputTop, sf = placeOverlay()

    state.open            = true
    state.buffer          = ""
    state.response        = ""
    state.attachments     = {}
    state.textContext     = nil
    state.lastPrompt      = nil
    state.anchorX         = x
    state.inputTop        = inputTop
    state.screenFrame     = sf
    state.statusKind      = "idle"
    if not opts.continued then
        state.history = {}
        state.sessionId = nil
    end
    -- Auto-attach the current selection as context. AX returns nothing for
    -- unsupported controls (Terminal etc.) — user falls back to ⌘⇧V for those.
    local sel = selectedText()
    if sel and sel ~= "" then state.textContext = sel end
    -- Continued sessions reopen at full width (history will fill the response
    -- area); fresh sessions start narrow and grow with the input text.
    state.expanded = opts.continued and #state.history > 0

    state.canv = newOverlay()
    relayout()
    rebuildInput()
    setStatus("idle")
    state.cursorOn = true
    state.cursorTimer = timer.doEvery(cfg.timings.cursorBlinkS, function()
        state.cursorOn = not state.cursorOn
        rebuildCursor()
    end)
    state.inputTap = eventtap.new({ etypes.keyDown }, onInputKey):start()
    state.dismissTap = eventtap.new({ etypes.leftMouseDown, etypes.rightMouseDown }, function(e)
        if not state.open or not state.canv then return false end
        local p = e:location()
        local f = state.canv:frame()
        local inside = p.x >= f.x and p.x <= f.x + f.w
            and p.y >= f.y and p.y <= f.y + f.h
        if not inside then close() end
        return false
    end):start()
end

close = function()
    if not state.open then return end
    state.open = false
    if state.statusTimer then
        state.statusTimer:stop(); state.statusTimer = nil
    end
    if state.cursorTimer then
        state.cursorTimer:stop(); state.cursorTimer = nil
    end
    if state.sizeAnim then
        state.sizeAnim:stop(); state.sizeAnim = nil
    end
    if rebuildPendingTimer then
        rebuildPendingTimer:stop(); rebuildPendingTimer = nil
    end
    if state.inputTap then
        state.inputTap:stop(); state.inputTap = nil
    end
    if state.dismissTap then
        state.dismissTap:stop(); state.dismissTap = nil
    end
    if state.task and state.task:isRunning() then pcall(function() state.task:terminate() end) end
    state.task = nil
    state.attachments = {}
    state.textContext = nil
    state.expanded = false
    if state.canv then
        state.canv:delete(); state.canv = nil
    end
    state.lastClose = timer.secondsSinceEpoch()
end

commitResponse = function()
    -- In chat mode state.response is "" between turns; fall back to the most
    -- recent assistant message in history so Enter still pastes cleanly.
    local out = state.response
    if (not out or out == "") then
        for i = #state.history, 1, -1 do
            if state.history[i].role == "assistant" then
                out = state.history[i].content
                break
            end
        end
    end
    if not out or out == "" then
        close(); return
    end
    close()
    timer.doAfter(cfg.timings.pasteInjectS, function() pasteText(out) end)
end

submitPrompt = function()
    local userText = state.buffer
    if userText == "" then return end
    local ctx = state.textContext
    state.textContext = nil
    local finalPrompt = userText
    if ctx and ctx ~= "" then
        finalPrompt = "<context>\n" .. ctx .. "\n</context>\n\n" .. userText
    end

    local atts = state.attachments
    state.attachments = {}
    local backend
    if #atts > 0 then
        backend = chooseBackend({ needsVision = true }) or chooseBackend()
        if backend and not backend.multimodal then
            atts = {} -- no vision backend available; drop silently
        end
    else
        backend = chooseBackend()
    end
    if not backend then
        local lines = { "No backend configured. Set up one of:" }
        local seen = {}
        local function addBackend(name)
            if seen[name] then return end
            seen[name] = true
            local b = Muse.backends[name]
            if not b then return end
            local hint = b.guidance or "(no setup hint provided)"
            lines[#lines + 1] = "  • " .. name .. " — " .. hint
        end
        for _, n in ipairs(cfg.fallbackOrder) do addBackend(n) end
        for n in pairs(Muse.backends) do addBackend(n) end
        state.response = table.concat(lines, "\n")
        rebuildResponse()
        setStatus("error")
        return
    end

    state.response = ""
    state.lastPrompt = userText ~= "" and userText or finalPrompt
    state.buffer = ""
    rebuildInput()
    rebuildResponse()
    setStatus("active")

    local function onChunk(text)
        state.response = state.response .. text
        rebuildResponseThrottled()
    end

    local function onDone()
        if not state.open then return end
        table.insert(state.history, { role = "user", content = finalPrompt })
        table.insert(state.history, { role = "assistant", content = state.response })
        setStatus("idle")
        -- Chat-mode: keep open, fold the in-flight turn into history, clear the
        -- in-flight slots so the next prompt renders cleanly.
        state.response = ""
        state.lastPrompt = nil
        state.buffer = ""
        rebuildInput()
        rebuildResponse()
    end

    local function onError(msg)
        setStatus("error")
        alert.show("Muse [" .. backend.name .. "]: " .. tostring(msg):sub(1, 100), 2)
    end

    state.task = backend:stream(finalPrompt, state.history, atts, onChunk, onDone, onError)
    -- Flip placeholder to "thinking…" now that state.task is live.
    if state.canv then rebuildInput() end
end

----------------------------------------------------------------------
-- Trigger eventtap: double-tap right ⌘
----------------------------------------------------------------------

local rightCmdMask = eventtap.event.rawFlagMasks.deviceRightCommand

local function onFlags(event)
    local code = event:getKeyCode()
    if code ~= cfg.rightCmdCode then return false end
    local now = timer.secondsSinceEpoch()
    local downNow = (event:rawFlags() & rightCmdMask) ~= 0
    if downNow and not state.rCmdHeld then
        state.rCmdHeld = true
        local elapsed = (now - state.lastRCmdEdge) * 1000
        if elapsed <= cfg.timings.doubleTapMs and state.lastRCmdEdge > 0 then
            if state.open then
                close()
            else
                local continued = #state.history > 0
                    and ((now - state.lastClose) * 1000 <= cfg.timings.continueMs)
                open({ continued = continued })
            end
            state.lastRCmdEdge = 0
        else
            state.lastRCmdEdge = now
        end
    elseif (not downNow) and state.rCmdHeld then
        state.rCmdHeld = false
        state.lastRCmdEdge = now
    end
    return false
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function Muse:start()
    if self._tap then return end
    self._tap = eventtap.new({ etypes.flagsChanged }, onFlags):start()
end

function Muse:stop()
    if self._tap then
        self._tap:stop(); self._tap = nil
    end
    close()
end

autoloadBackends()
reportBackendStatus()
Muse:start()

-- Chain a shutdown callback so eventtaps from this load are stopped on reload.
-- Without this, hs.reload() leaves orphan flagsChanged/keyDown taps running with
-- stale state closures, causing the open/close storm we saw during debugging.
do
    local prev = hs.shutdownCallback
    hs.shutdownCallback = function()
        Muse:stop()
        if prev then prev() end
    end
end

return Muse
