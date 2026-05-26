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

Muse.config            = {
    backend        = "claudecli", -- "claude" | "openai" | "gemini" | "fabric" | "claudecli" | "apple"
    fallbackOrder  = { "claudecli", "claude", "openai", "gemini", "fabric", "apple" },
    font           = ".AppleSystemUIFontMedium",
    fontSize       = 20,
    rightCmdCode   = 54, -- right ⌘
    backends       = {}, -- per-plugin config: Muse.config.backends[name] = { ... }

    -- Per-backend override at backends[name].systemPrompt. Fabric ignores this
    -- (its patterns ARE the system prompt).
    systemPrompt   = [[You are Muse, a quiet inline assistant invoked next to the user's text caret. Your reply may be pasted directly into the field they were working in.

Reply concisely. No preamble ("Sure!", "Here is...", "Certainly"). No closing offers ("Let me know if...", "Hope this helps"). No meta-commentary about your own response. Match the user's tone, register, and length — short questions get short replies.

Plain text by default. Use Markdown or code fences only when explicitly asked or when the content genuinely requires it (e.g. actual code).

If <context>...</context> appears, that is the text the user wants to discuss. Do not echo it back. Rewrite requests get just the rewritten text. Questions get just the answer.]],

    layout = {
        panelSize      = 320,                 -- fixed-square card edge length
        anchorOffset   = 8,                   -- gap between caret and panel top
        pad            = 16,                  -- inner padding inside the card
        screenMargin   = 8,                   -- min gap between overlay and screen edge

        strokeWidth    = 2,                   -- blue border around the card

        -- Three stacked regions inside the card (top → bottom):
        inputRegionH   = 96,
        hintLineH      = 18,
        matrixRegionH  = 80,                  -- includes a small gap above/below the matrix itself
        -- outputRegionH is derived: panelSize - 2*pad - inputRegionH - hintLineH - matrixRegionH

        chipWidth      = 76,                  -- horizontal budget for the attachment chip (kept; chips still float near input)
        cardSize       = 30,                  -- thumbnail edge length
        cardStep       = 12,                  -- left-edge offset between stacked cards
        cardAlphas     = { 0.55, 0.8, 1.0 },  -- back, middle, front depth

        statusDotW     = 20,                  -- (kept for error/idle paths that still use circle slots)
        dotGap         = 8,
        dotRadius      = 3,

        cornerRadius   = 12,
        cursorWidth    = 2,

        userFontSize       = 18,              -- input slot text size (multi-line wrap)
        assistantFontSize  = 20,              -- output slot text size (multi-line wrap, bold)

        chipSymbolInset = 6,                  -- breathing room around the SF Symbol inside the text-chip card

        hintAlpha       = 0.95,               -- subtext alpha multiplier (applied on top of C.muted's alpha)
        hintSizeScale   = 0.55,               -- subtext font-size scale relative to cfg.fontSize

        matrixUnlitAlpha = 0.12,              -- alpha for the "off" cells so the grid reads as a physical LED panel
    },

    timings = {
        doubleTapMs     = 250,
        continueMs      = 600,
        settledHoldS    = 0.35,   -- after stream ends, hold the comet before fading
        settledFadeS    = 0.25,   -- alpha fade-to-idle duration
        animFrameS      = 0.016,  -- ~60fps timer step
        cursorBlinkS    = 0.53,
        rebuildThrottle = 0.033,  -- ~30fps; smooth stream growth
        pasteInjectS    = 0.04,
        pasteRestoreS   = 0.12,
    },
}

local cfg              = Muse.config

-- Mutated in place by loadAppearance(); don't replace tables — canvas elements
-- capture these refs at creation and re-read on next render.
local C                = {
    bg      = { white = 1,    alpha = 0.98 },
    fg      = { white = 0,    alpha = 1 },
    muted   = { white = 0,    alpha = 0.55 },
    accent  = { red = 0.1, green = 0.3, blue = 0.9, alpha = 1 },
    spinner = { red = 0.1, green = 0.3, blue = 0.9, alpha = 1 },
    error   = { red = 0.85, green = 0.20, blue = 0.20, alpha = 1 },
}

local textShadow       = {
    offset = { h = -1, w = 0 },
    blurRadius = 2,
    color = { alpha = 0 }, -- alpha is flipped to 1 in dark mode
}

-- Sample appearance and mutate C + textShadow in place. Accent/spinner/error
-- stay constant across modes; only bg/fg/muted swap to invert contrast.
local function loadAppearance()
    -- hs.host.interfaceStyle() returns "Dark" when Dark mode is active and
    -- NIL when Light mode is active (macOS only sets AppleInterfaceStyle for
    -- Dark; Light is the absence of the key). Don't default nil → "Dark" —
    -- that's what was hiding light-mode entirely.
    local isDark = hs.host.interfaceStyle() == "Dark"
    if isDark then
        -- Dark mode: near-black bg, near-white fg, muted = dimmed white.
        C.bg.white,    C.bg.alpha    = 0.12, 0.96
        C.fg.white,    C.fg.alpha    = 1,    1
        C.muted.white, C.muted.alpha = 1,    0.55
        textShadow.color.alpha = 1
    else
        -- Light mode: white bg, near-black fg, muted = dimmed black.
        C.bg.white,    C.bg.alpha    = 1,    0.98
        C.fg.white,    C.fg.alpha    = 0,    1
        C.muted.white, C.muted.alpha = 0,    0.55
        textShadow.color.alpha = 0
    end
end

-- SF Symbol for the text-context chip; falls back to nil (border-only) if unresolvable.
local textChipIcon
do
    for _, name in ipairs({ "text.alignleft", "doc.text", "doc.plaintext" }) do
        local ok, img = pcall(hs.image.imageFromName, name)
        if ok and img then textChipIcon = img; break end
    end
end

local function formatCount(n)
    if n < 1000 then return tostring(n) end
    if n < 10000 then return string.format("%.1fk", n / 1000) end
    return string.format("%dk", math.floor(n / 1000 + 0.5))
end

-- Char count of an attached text context. Uses utf8.len so multi-byte chars
-- count as one; falls back to byte length if the string is malformed UTF-8.
local function textContextCount(s)
    if not s or s == "" then return 0 end
    local n = utf8 and utf8.len(s)
    return n or #s
end

-- Backends: each plugin under Muse/backends/*.lua returns
--   { name, available() -> bool,reason, stream(self, prompt, history, atts, onChunk, onDone, onError) -> task }
-- Plugin config: Muse.config.backends[name]. Shared helpers via require("Muse").helpers.
Muse.backends          = {}

-- Color helpers return NEW tables so canvas elements get frozen snapshots,
-- not live views that loadAppearance() would mutate under them.
local function colorAlpha(c, a)
    if c.white ~= nil then
        return { white = c.white, alpha = (c.alpha or 1) * a }
    end
    return { red = c.red, green = c.green, blue = c.blue, alpha = (c.alpha or 1) * a }
end

local function colorLighten(c, p)
    p = math.max(0, math.min(1, p or 0))
    if c.white ~= nil then
        return { white = c.white + (1 - c.white) * p, alpha = c.alpha }
    end
    return {
        red   = c.red + (1 - c.red) * p,
        green = c.green + (1 - c.green) * p,
        blue  = c.blue + (1 - c.blue) * p,
        alpha = c.alpha,
    }
end

local function colorDarken(c, p)
    p = math.max(0, math.min(1, p or 0))
    if c.white ~= nil then
        return { white = c.white * (1 - p), alpha = c.alpha }
    end
    return {
        red   = c.red * (1 - p),
        green = c.green * (1 - p),
        blue  = c.blue * (1 - p),
        alpha = c.alpha,
    }
end

-- 5×5 LED matrix at c[41..65]. All 25 cells stay action="fill"; the lit/unlit
-- distinction is carried entirely by per-cell color (saturated accent vs
-- faded accent), so the grid reads as a physical LED panel.
local MATRIX_SIZE     = 5
local MATRIX_CELLS    = MATRIX_SIZE * MATRIX_SIZE -- 25
local MATRIX_CELL_PX  = 12
local MATRIX_CELL_GAP = 2
local MATRIX_PX       = MATRIX_SIZE * MATRIX_CELL_PX + (MATRIX_SIZE - 1) * MATRIX_CELL_GAP

-- 16-cell clockwise perimeter walk of a 5×5 grid: top → right → bottom → left,
-- corners counted once each.
local PERIMETER = {
    0, 1, 2, 3, 4,    -- top row L→R
    9, 14, 19, 24,    -- right column (skip top-right corner)
    23, 22, 21, 20,   -- bottom row R→L (skip bottom-right corner)
    15, 10, 5,        -- left column (skip bottom-left and top-left corners)
}

-- Comet trail (head + 2-cell tail) chasing the perimeter clockwise.
local MATRIX_FRAMES = {}
for f = 0, #PERIMETER - 1 do
    local lit = 0
    for tail = 0, 2 do
        local p = ((f - tail) % #PERIMETER + #PERIMETER) % #PERIMETER
        lit = lit | (1 << PERIMETER[p + 1])
    end
    MATRIX_FRAMES[f + 1] = lit
end

-- Static glyphs (single-frame bitmasks). 25-bit row-major layout:
--   row 0: cells  0  1  2  3  4
--   row 1: cells  5  6  7  8  9
--   row 2: cells 10 11 12 13 14
--   row 3: cells 15 16 17 18 19
--   row 4: cells 20 21 22 23 24
local IDLE_MASK   = (1 << 12) -- center dot
local CHECK_MASK  = (1 << 4)  | (1 << 8)  | (1 << 10) | (1 << 12) | (1 << 16)
local SAD_MASK    = (1 << 6)  | (1 << 8)  | (1 << 16) | (1 << 17) | (1 << 18)
                  | (1 << 20) | (1 << 24)
local CROSS_MASK  = (1 << 0)  | (1 << 4)  | (1 << 6)  | (1 << 8)  | (1 << 12)
                  | (1 << 16) | (1 << 18) | (1 << 20) | (1 << 24) -- two diagonals
local RETURN_MASK = (1 << 9)  | (1 << 12) | (1 << 14)
                  | (1 << 15) | (1 << 16) | (1 << 17) | (1 << 18)
                  | (1 << 21) -- ↵ shaft + arrowhead

Muse.helpers           = {
    json     = hs.json,
    alert    = hs.alert,
    taskmod  = hs.task,
    eventtap = hs.eventtap,
    color    = {
        alpha   = colorAlpha,
        lighten = colorLighten,
        darken  = colorDarken,
    },
    parseSSE = function(buf, perLine)
        for line in buf:gmatch("[^\r\n]+") do perLine(line) end
    end,
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

local function focusedElement()
    local el
    pcall(function() el = ax.systemWideElement():attributeValue("AXFocusedUIElement") end)
    return el
end

-- Returns nil for unsupported controls (Terminal, Electron) or empty selections.
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

-- Decide overlay placement. Input sits below the caret; slides up if it would
-- overflow the screen — even if that means visually overlapping the caret line.
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

    local panelSz = cfg.layout.panelSize
    local x = leadX
    if x + panelSz > sf.x + sf.w - mar then
        x = trailX - panelSz
    end
    if x < sf.x + mar then x = sf.x + mar end
    if x + panelSz > sf.x + sf.w - mar then
        x = sf.x + sf.w - panelSz - mar
    end

    local inputTop = bottom + cfg.layout.anchorOffset
    if inputTop + panelSz > sf.y + sf.h - mar then
        inputTop = sf.y + sf.h - mar - panelSz
    end
    if inputTop < sf.y + mar then inputTop = sf.y + mar end

    return x, inputTop, sf
end

local function pasteText(text)
    local saved = pb.getContents()
    pb.setContents(text)
    eventtap.keyStroke({ "cmd" }, "v", 0)
    timer.doAfter(cfg.timings.pasteRestoreS, function() if saved then pb.setContents(saved) end end)
end

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
    -- Most-recently-submitted prompt. Displayed in the input slot whenever the
    -- typing buffer is empty (so the card always shows "you said X, I replied Y"
    -- between turns). Cleared on session start; set by submitPrompt.
    lastSubmittedPrompt = nil,
}

local close, submitPrompt, commitResponse, rebuildResponse, applyCanvasFrame

-- Apply a 16-bit bitmask to the 4×4 matrix cells. Bit i lit → cell i uses
-- `litColor`; bit i unlit → cell i uses the faded-accent "off" tint. All 16
-- cells stay at action="fill"; the lit/unlit difference is purely color, so
-- the grid always reads as a physical LED panel.
local function applyMatrixMask(mask, litColor)
    local unlit = colorAlpha(C.accent, cfg.layout.matrixUnlitAlpha)
    for i = 0, MATRIX_CELLS - 1 do
        if (mask >> i) & 1 == 1 then
            state.canv[41 + i].fillColor = litColor
        else
            state.canv[41 + i].fillColor = unlit
        end
    end
end

local function setStatus(kind, reposition)
    if not state.canv then return end
    if (not reposition) and state.statusTimer then
        state.statusTimer:stop(); state.statusTimer = nil
    end
    state.statusKind = kind

    if kind == "thinking" then
        -- Comet trail; 100ms/frame, 1.6s cycle.
        applyMatrixMask(MATRIX_FRAMES[1], C.spinner)
        if not reposition then
            local t0      = timer.secondsSinceEpoch()
            local frameMs = 0.1
            state.statusTimer = timer.doEvery(cfg.timings.animFrameS, function()
                if not state.canv then return end
                local frame = math.floor((timer.secondsSinceEpoch() - t0) / frameMs) % #MATRIX_FRAMES + 1
                applyMatrixMask(MATRIX_FRAMES[frame], C.spinner)
            end)
        end
    elseif kind == "success" then
        -- Hold the check briefly, then snap to idle.
        applyMatrixMask(CHECK_MASK, C.accent)
        if not reposition then
            state.statusTimer = timer.doAfter(0.7, function()
                if state.canv and state.statusKind == "success" then
                    setStatus("idle")
                end
            end)
        end
    elseif kind == "ready" then
        applyMatrixMask(RETURN_MASK, C.accent)
    elseif kind == "error" then
        applyMatrixMask(CROSS_MASK, C.error)
    elseif kind == "softError" then
        applyMatrixMask(SAD_MASK, C.error)
    else
        applyMatrixMask(IDLE_MASK, C.accent)
    end
end

-- Reconcile the matrix with the current buffer/task state. Called after every
-- buffer mutation; thinking owns the matrix while a task is running, and a
-- live success-glyph hold should not be cut short by an empty buffer.
local function updateReadyState()
    if state.task and state.task:isRunning() then return end
    local want = (state.buffer ~= "") and "ready" or "idle"
    if state.statusKind == "success" and want == "idle" then return end
    if state.statusKind ~= want then setStatus(want) end
end

-- Position the fixed-region card layout. Called once at open; no per-render
-- geometry math because the panel never resizes for content.
--
-- Vertical bands (top → bottom), all anchored to fixed y offsets:
--   pad
--   input region  (inputRegionH)
--   hint line     (hintLineH)
--   matrix region (matrixRegionH, matrix vertically centered inside)
--   output region (derived: fills the remainder)
--   pad
local function relayout()
    if not state.canv then return end
    local pad         = cfg.layout.pad
    local sz          = cfg.layout.panelSize
    local innerW      = sz - 2 * pad
    local inputY      = pad
    local inputH      = cfg.layout.inputRegionH
    local matrixBandY = inputY + inputH
    local matrixBandH = cfg.layout.matrixRegionH
    local outputY     = matrixBandY + matrixBandH
    local outputH     = sz - pad - outputY

    local hasImages    = (#state.attachments > 0)
    local hasText      = (state.textContext and state.textContext ~= "")
    local imageReserve = hasImages and (cfg.layout.chipWidth + pad) or 0
    local textReserve  = hasText and (cfg.layout.cardSize + pad) or 0
    state.canv[2].frame = {
        x = pad,
        y = inputY,
        w = math.max(0, innerW - imageReserve - textReserve),
        h = inputH,
    }

    local matrixX = math.floor((sz - MATRIX_PX) / 2)
    local matrixY = matrixBandY + math.floor((matrixBandH - MATRIX_PX) / 2)
    for i = 0, MATRIX_CELLS - 1 do
        local row = i // MATRIX_SIZE
        local col = i % MATRIX_SIZE
        state.canv[41 + i].frame = {
            x = matrixX + col * (MATRIX_CELL_PX + MATRIX_CELL_GAP),
            y = matrixY + row * (MATRIX_CELL_PX + MATRIX_CELL_GAP),
            w = MATRIX_CELL_PX,
            h = MATRIX_CELL_PX,
        }
    end

    -- 3-line hint stack — narrow column flush against the left edge of the
    -- matrix, right-aligned text, vertically centered in the matrix band.
    local hintGap    = 12
    local hintBlockH = 56 -- 3 lines × ~14pt + breathing room
    state.canv[39].frame = {
        x = pad,
        y = matrixBandY + math.floor((matrixBandH - hintBlockH) / 2),
        w = math.max(0, matrixX - pad - hintGap),
        h = hintBlockH,
    }

    -- Output text (bottom region). Frame fills the region; styledtext's
    -- right-alignment + bottom-anchoring is handled in rebuildResponse.
    state.canv[6].frame = {
        x = pad,
        y = outputY,
        w = innerW,
        h = outputH,
    }

    -- Chips anchored to the input row's right edge. Stacked top-right.
    local chipRight = sz - pad
    local cardY     = inputY
    state.canv[11].frame = { x = chipRight - cfg.layout.cardSize,                                y = cardY, w = cfg.layout.cardSize, h = cfg.layout.cardSize }
    state.canv[10].frame = { x = chipRight - cfg.layout.cardSize - cfg.layout.cardStep,         y = cardY, w = cfg.layout.cardSize, h = cfg.layout.cardSize }
    state.canv[9].frame  = { x = chipRight - cfg.layout.cardSize - 2 * cfg.layout.cardStep,     y = cardY, w = cfg.layout.cardSize, h = cfg.layout.cardSize }
    state.canv[8].frame  = {
        x = chipRight - cfg.layout.cardSize - 2 * cfg.layout.cardStep - 18,
        y = cardY,
        w = 16,
        h = 18,
    }

    -- Text-context chip: left of the image stack (or at the chips' right anchor
    -- if no images attached).
    local imageStackLeftEdge = chipRight - cfg.layout.cardSize - 2 * cfg.layout.cardStep
    local textChipX = hasImages
        and (imageStackLeftEdge - pad - cfg.layout.cardSize)
        or (chipRight - cfg.layout.cardSize)
    state.canv[12].frame = { x = textChipX, y = cardY, w = cfg.layout.cardSize, h = cfg.layout.cardSize }
    local symbolInset = cfg.layout.chipSymbolInset
    state.canv[13].frame = {
        x = textChipX + symbolInset,
        y = cardY + symbolInset,
        w = cfg.layout.cardSize - 2 * symbolInset,
        h = cfg.layout.cardSize - 2 * symbolInset,
    }
    state.canv[40].frame = {
        x = textChipX,
        y = cardY + math.floor((cfg.layout.cardSize - 14) / 2),
        w = cfg.layout.cardSize,
        h = 14,
    }
    state.canv[40].textAlignment = "center"
end

local function inputStyled(text, color)
    return hs.styledtext.new(text, {
        font = { name = cfg.font, size = cfg.fontSize },
        color = color,
        shadow = textShadow,
    })
end

-- Concatenate styled-text segments into a single styledtext object. Each
-- segment is { text, color, [size] } — size falls back to the row's default.
-- Optional `alignment` (e.g. "left" | "right" | "center") applies to the
-- whole resulting styledtext via paragraphStyle. Returns nil for an empty
-- segment list.
local function styledSegments(segments, defaultSize, alignment)
    local result
    local pStyle = alignment and { alignment = alignment } or nil
    for _, seg in ipairs(segments) do
        local s = hs.styledtext.new(seg.text, {
            font           = { name = cfg.font, size = seg.size or defaultSize },
            color          = seg.color,
            shadow         = textShadow,
            paragraphStyle = pStyle,
        })
        result = result and (result .. s) or s
    end
    return result
end

-- First ~maxChars of the most recent assistant reply in state.history,
-- whitespace-collapsed, truncated UTF-8-safe with an ellipsis. Empty string
-- if no assistant reply exists yet (e.g. only errors so far).
local function lastReplyPreview(maxChars)
    for i = #state.history, 1, -1 do
        if state.history[i].role == "assistant" then
            local s = (state.history[i].content or "")
                :gsub("%s+", " ")
                :gsub("^%s+", "")
            if #s == 0 then return "" end
            local len = utf8 and utf8.len(s)
            if len and len <= maxChars then return s end
            local offset = utf8 and utf8.offset(s, maxChars + 1)
            if offset then return s:sub(1, offset - 1) .. "…" end
            return s:sub(1, maxChars) .. "…"
        end
    end
    return ""
end

-- Placeholder for the current state, returned as a styledtext object so
-- different segments can render in different colours (action affordances in
-- accent, descriptive payload in muted). First match wins.
local function placeholderForState()
    local size = cfg.fontSize
    if state.task and state.task:isRunning() then
        return styledSegments({ { text = "thinking…", color = C.muted } }, size)
    end
    if #state.attachments > 0 then
        local s = (#state.attachments == 1) and "about this image…" or "about these images…"
        return styledSegments({ { text = s, color = C.muted } }, size)
    end
    if state.textContext and state.textContext ~= "" then
        return styledSegments({ { text = "about this selection…", color = C.muted } }, size)
    end
    if #state.history > 0 and not state.lastPrompt then
        local preview = lastReplyPreview(50)
        if preview == "" then
            return styledSegments({ { text = "↵ to insert", color = C.accent } }, size)
        end
        return styledSegments({
            { text = "↵ to insert", color = C.accent },
            { text = ": " .. preview, color = C.muted },
        }, size)
    end
    return styledSegments({ { text = "ask, summarize, rewrite…", color = C.muted } }, size)
end

-- The discoverability subtext shows while the user is composing their first
-- prompt in a session — visible during typing so the shortcuts stay reachable
-- when they're actually relevant. Hides after the first submit, once history
-- exists and the user has obviously already figured out how to use the panel.
local function shouldShowHint()
    if #state.history > 0 then return false end
    if state.lastPrompt then return false end
    if state.task and state.task:isRunning() then return false end
    return true
end

-- 3-line hint stack — each shortcut on its own line, right-aligned so the
-- column sits flush against the left edge of the matrix. Modifier glyphs in
-- accent (the actionable token), verbs in muted (descriptive).
local function hintStyled()
    local size      = math.floor(cfg.fontSize * cfg.layout.hintSizeScale)
    local modColor  = colorAlpha(C.accent, cfg.layout.hintAlpha)
    local verbColor = colorAlpha(C.muted,  cfg.layout.hintAlpha)
    local lines = {
        { "⌘⇧S", "attach" },
        { "⌘⇧V", "paste" },
        { "⌘⌫",  "clear" },
    }
    local segments = {}
    for i, p in ipairs(lines) do
        if i > 1 then
            segments[#segments + 1] = { text = "\n", color = verbColor }
        end
        segments[#segments + 1] = { text = p[1], color = modColor }
        segments[#segments + 1] = { text = " " .. p[2], color = verbColor }
    end
    return styledSegments(segments, size, "right")
end

-- Place the text cursor at the visual end of the buffer's wrapped text inside
-- the input region. Multi-line aware: measures the whole buffer's bounding
-- size at the input frame's width, then walks the last visible line to find
-- where the cursor should sit.
local function rebuildCursor()
    if not state.canv then return end
    local inputFrame = state.canv[2].frame
    local x, y
    local cursorH = cfg.layout.userFontSize + 4
    if state.buffer ~= "" then
        local fullSz = state.canv:minimumTextSize(2, state.buffer)
        local fullH  = (fullSz and fullSz.h) or cursorH
        -- Last-line width: measure from the final newline to end. If no
        -- newline, the buffer is a single visual line and last-line == buffer.
        local lastBreak = state.buffer:find("\n[^\n]*$")
        local lastLine  = lastBreak and state.buffer:sub(lastBreak + 1) or state.buffer
        local lineSz    = state.canv:minimumTextSize(2, lastLine)
        local lineW     = (lineSz and lineSz.w) or 0
        x = inputFrame.x + lineW
        y = inputFrame.y + math.max(0, math.floor(fullH - cursorH))
    else
        x = inputFrame.x
        y = inputFrame.y
    end
    local visible = state.cursorOn and not (state.task and state.task:isRunning())
    state.canv[7].frame     = { x = x, y = y, w = cfg.layout.cursorWidth, h = cursorH }
    state.canv[7].fillColor = colorAlpha(C.accent, visible and 1.0 or 0)
end

-- Force the cursor on and restart the blink phase. Called from open() and from
-- every onInputKey branch that mutates the buffer — the cursor must be visible
-- the instant the user's keystroke lands, not at some arbitrary point in the
-- pre-existing blink phase.
local function startCursorBlink()
    if state.cursorTimer then state.cursorTimer:stop() end
    state.cursorOn = true
    rebuildCursor()
    state.cursorTimer = timer.doEvery(cfg.timings.cursorBlinkS, function()
        state.cursorOn = not state.cursorOn
        rebuildCursor()
    end)
end

-- Region height of the output slot (the band between the matrix and the
-- bottom pad). Computed once from layout constants — must NOT be read from
-- state.canv[6].frame.h, because rebuildResponse shrinks that frame to fit.
local function outputRegionH()
    return cfg.layout.panelSize
         - 2 * cfg.layout.pad
         - cfg.layout.inputRegionH
         - cfg.layout.matrixRegionH
end

-- Estimate the height a styledtext will occupy when wrapped to wrapW. Uses
-- the probe element to measure the natural single-line w/h (hs.canvas's
-- minimumTextSize ignores wrap), then estimates wrapped lines as
-- ceil(naturalW / wrapW). Conservative for multi-paragraph text — overshoots
-- slightly, which is safer than truncating the last line.
local function estimateWrappedH(styled, wrapW, probeIdx)
    if wrapW <= 0 then wrapW = 1 end
    state.canv[probeIdx].text = styled
    local sz       = state.canv:minimumTextSize(probeIdx, styled)
    local naturalW = (sz and sz.w) or 0
    local naturalH = (sz and sz.h) or 0
    local lines    = math.max(1, math.ceil(naturalW / wrapW))
    return naturalH * lines
end

-- Build a styledtext at the largest font size that fits inside regionH at the
-- probe element's current frame width.
local function fitText(content, probeIdx, regionH, fontName, maxSize, minSize, color, alignment)
    local wrapW = state.canv[probeIdx].frame.w
    local size  = maxSize
    while true do
        local s = hs.styledtext.new(content, {
            font           = { name = fontName, size = size },
            color          = color,
            shadow         = textShadow,
            paragraphStyle = { alignment = alignment, lineBreak = "wordWrap" },
        })
        if estimateWrappedH(s, wrapW, probeIdx) <= regionH or size <= minSize then
            return s
        end
        size = size - 1
    end
end

local function inputText()
    local content = state.buffer
    if content == "" then
        if state.lastSubmittedPrompt and state.lastSubmittedPrompt ~= "" then
            content = state.lastSubmittedPrompt
        else
            return placeholderForState()
        end
    end
    return fitText(content, 2, cfg.layout.inputRegionH, cfg.font,
                   cfg.layout.userFontSize, 11, C.muted, "left")
end

local function outputText()
    local content = state.response
    if content == "" then
        for i = #state.history, 1, -1 do
            if state.history[i].role == "assistant" then
                content = state.history[i].content or ""
                break
            end
        end
    end
    if not content or content == "" then return nil end
    return fitText(content, 6, outputRegionH(), ".AppleSystemUIFontBold",
                   cfg.layout.assistantFontSize, 12, C.fg, "right")
end

local function rebuildInput()
    if not state.canv then return end
    state.canv[2].text = inputText()

    -- Image attachments: front (c[11]) shows the newest; alpha dims older cards.
    local n      = #state.attachments
    local alphas = cfg.layout.cardAlphas
    for slot = 0, 2 do
        local idx = 9 + slot
        local stepsFromFront = 2 - slot
        local attIdx = n - stepsFromFront
        local att = (attIdx >= 1) and state.attachments[attIdx] or nil
        if att and att.img then
            state.canv[idx].action     = "fill"
            state.canv[idx].image      = att.img
            state.canv[idx].imageAlpha = alphas[slot + 1]
        else
            state.canv[idx].action = "skip"
            state.canv[idx].image  = nil
        end
    end
    if n > 3 then
        state.canv[8].action = "fill"
        state.canv[8].text   = hs.styledtext.new("+" .. (n - 3), {
            font           = { name = cfg.font, size = 11 },
            color          = C.accent,
            paragraphStyle = { alignment = "right" },
        })
    else
        state.canv[8].action = "skip"
        state.canv[8].text   = ""
    end

    -- Text-context chip + count badge.
    local hasText = (state.textContext and state.textContext ~= "")
    if hasText then
        state.canv[12].action = "strokeAndFill"
        state.canv[13].action = "skip"
        state.canv[40].action = "fill"
        state.canv[40].text   = formatCount(textContextCount(state.textContext))
    else
        state.canv[12].action = "skip"
        state.canv[13].action = "skip"
        state.canv[40].action = "skip"
    end

    -- Discoverability subtext.
    local showHint = shouldShowHint()
    state.canv[39].action = showHint and "fill" or "skip"
    if showHint then state.canv[39].text = hintStyled() end

    relayout()
    -- relayout() resets c[6].frame to the full output region; the actual
    -- bottom-anchored y is computed in rebuildResponse, so re-apply it after
    -- every input rebuild — otherwise the reply jumps to the top of the region.
    rebuildResponse()
    rebuildCursor()
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

-- Place the fixed-square canvas at the caret anchor. If the bottom would
-- overflow the screen, shift the whole card up so it still fits.
applyCanvasFrame = function()
    if not state.canv then return end
    local sz  = cfg.layout.panelSize
    local sf  = state.screenFrame
    local mar = cfg.layout.screenMargin
    local y   = state.inputTop
    if sf then
        local maxBottom = sf.y + sf.h - mar
        if y + sz > maxBottom then y = maxBottom - sz end
        if y < sf.y + mar then y = sf.y + mar end
    end
    state.canv:frame({ x = state.anchorX, y = y, w = sz, h = sz })
    relayout()
end

-- Push the current output text into c[6]. Called from submitPrompt, every
-- streaming chunk (throttled), and onDone. The frame is fixed by relayout;
-- text wraps inside, right-aligned, bottom-anchored via paragraphStyle.
rebuildResponse = function()
    if not state.canv then return end
    local styled = outputText()
    state.canv[6].text = styled or ""
    -- Anchor text to the bottom of the output region by computing the styled
    -- text's actual rendered height inside the region width, then shifting
    -- the frame's y down so the text bottom aligns with the region bottom.
    if styled then
        local regionFrame = state.canv[6].frame
        local regionW     = regionFrame.w
        local regionH     = regionFrame.h
        -- Use estimated wrapped height (not the natural single-line h that
        -- minimumTextSize would return) so multiline replies get a frame
        -- tall enough to actually render lines 2+.
        local wrappedH = estimateWrappedH(styled, regionW, 6)
        local textH    = math.min(wrappedH, regionH)
        local baseY    = regionFrame.y + (regionH - textH)
        state.canv[6].frame = {
            x = regionFrame.x,
            y = baseY,
            w = regionW,
            h = textH,
        }
    end
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
    -- Fixed-square card. No content-flex resizing; canvas is always panelSize×panelSize.
    local sz = cfg.layout.panelSize
    local c = canvas.new({
        x = state.anchorX,
        y = state.inputTop,
        w = sz,
        h = sz,
    })
    -- c[1]: card background + blue stroke border. Inset by half the stroke
    -- width so the entire stroke lives inside the canvas window — without
    -- this, hs.canvas centers the stroke on the rect's path, so half the
    -- stroke draws outside the canvas bounds and gets clipped (visible
    -- thickness ends up at strokeWidth/2).
    local strokeInset = cfg.layout.strokeWidth / 2
    c[1] = {
        type = "rectangle",
        action = "strokeAndFill",
        fillColor = C.bg,
        strokeColor = C.accent,
        strokeWidth = cfg.layout.strokeWidth,
        roundedRectRadii = { xRadius = cfg.layout.cornerRadius, yRadius = cfg.layout.cornerRadius },
        frame = {
            x = strokeInset,
            y = strokeInset,
            w = sz - 2 * strokeInset,
            h = sz - 2 * strokeInset,
        },
    }
    c[2] = {
        type = "text",
        text = "",
        textFont = cfg.font,
        textSize = cfg.layout.userFontSize,
        textColor = C.muted,
        textLineBreak = "wordWrap",
        frame = { x = 0, y = 0, w = 0, h = 0 }, -- set by relayout
    }
    -- c[3..5]: inert placeholders. hs.canvas requires contiguous element
    -- indices, so we can't skip these slots even though the redesign no
    -- longer uses them. Cleanup pass will renumber everything end-to-end.
    for i = 3, 5 do
        c[i] = {
            type = "rectangle",
            action = "skip",
            fillColor = { white = 0, alpha = 0 },
            frame = { x = 0, y = 0, w = 0, h = 0 },
        }
    end
    c[6] = {
        type = "text",
        text = "",
        textFont = cfg.font,
        textSize = cfg.layout.assistantFontSize,
        textColor = C.fg,
        textLineBreak = "wordWrap",
        frame = { x = 0, y = 0, w = 0, h = 0 }, -- set by relayout
    }
    -- c[7]: cursor (thin rectangle).
    c[7] = {
        type = "rectangle",
        action = "fill",
        fillColor = { white = 1, alpha = 0 },
        frame = { x = 0, y = 0, w = cfg.layout.cursorWidth, h = cfg.layout.userFontSize + 4 },
    }
    -- c[8]: "+N" overflow label for stacked image attachments.
    c[8] = {
        type = "text",
        text = "",
        action = "skip",
        textFont = cfg.font,
        textSize = 11,
        textColor = C.accent,
        frame = { x = 0, y = 0, w = 14, h = 18 },
    }
    -- c[9..11]: thumbnail card stack (back → front).
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
    -- c[12, 13]: text-context chip (rect + SF Symbol fallback). c[40] count badge replaces the icon when attached.
    c[12] = {
        type = "rectangle",
        action = "skip",
        fillColor = colorAlpha(C.accent, 0.10),
        strokeColor = C.accent,
        strokeWidth = 0.6,
        roundedRectRadii = { xRadius = 3, yRadius = 3 },
        frame = { x = 0, y = 0, w = cfg.layout.cardSize, h = cfg.layout.cardSize },
    }
    c[13] = {
        type = "image",
        action = "skip",
        image = textChipIcon,
        imageAlignment = "center",
        imageScaling = "scaleProportionally",
        imageAlpha = 1.0,
        frame = { x = 0, y = 0, w = cfg.layout.cardSize, h = cfg.layout.cardSize },
    }
    -- c[14..38]: inert placeholders for indices the old rail / enter-glyph /
    -- fade-mask slots used to occupy. Same reason as c[3..5] — hs.canvas needs
    -- contiguous indices. Cleanup pass will renumber.
    for i = 14, 38 do
        c[i] = {
            type = "rectangle",
            action = "skip",
            fillColor = { white = 0, alpha = 0 },
            frame = { x = 0, y = 0, w = 0, h = 0 },
        }
    end
    -- c[39]: discoverability hint subtext. Position set by relayout.
    c[39] = {
        type = "text",
        action = "skip",
        text = "",
        textFont = cfg.font,
        textSize = math.floor(cfg.fontSize * cfg.layout.hintSizeScale),
        textColor = C.muted,
        frame = { x = 0, y = 0, w = 0, h = cfg.layout.hintLineH },
    }
    -- c[40]: text-context chip count badge.
    c[40] = {
        type = "text",
        action = "skip",
        text = "",
        textFont = cfg.font,
        textSize = 11,
        textColor = C.accent,
        frame = { x = 0, y = 0, w = cfg.layout.cardSize, h = 14 },
    }
    -- c[41..56]: 4×4 LED matrix cells. Always rendered (action="fill"); lit vs
    -- unlit carried entirely by fillColor. Positions set by relayout.
    for i = 0, MATRIX_CELLS - 1 do
        c[41 + i] = {
            type = "rectangle",
            action = "fill",
            fillColor = colorAlpha(C.accent, cfg.layout.matrixUnlitAlpha),
            frame = { x = 0, y = 0, w = MATRIX_CELL_PX, h = MATRIX_CELL_PX },
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

-- Navigation / function keys that must never be inserted as text. macOS's
-- NSEvent reports these as Private-Use Area characters (F700–F7FF) whose UTF-8
-- encoding starts with 0xEF (239) — that passes the b >= 32 printable filter
-- below, so without an explicit denylist arrow keys appear in the buffer.
local NON_TEXT_KEYS = {
    up = true, down = true, left = true, right = true,
    pageup = true, pagedown = true, home = true, ["end"] = true,
    forwarddelete = true, help = true,
    f1 = true, f2 = true, f3 = true, f4 = true, f5 = true, f6 = true,
    f7 = true, f8 = true, f9 = true, f10 = true, f11 = true, f12 = true,
    f13 = true, f14 = true, f15 = true, f16 = true, f17 = true, f18 = true,
    f19 = true, f20 = true,
}

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

    -- Navigation / function keys: swallow so they never insert as text. The
    -- single-line / wrapped input doesn't have cursor navigation, and the
    -- card design has no transcript scroll.
    if key and NON_TEXT_KEYS[key] then
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
        startCursorBlink()
        updateReadyState()
        return true
    end

    -- Printable input (no modifiers other than shift/alt-for-accents)
    if chars and #chars > 0 and not flags.cmd and not flags.ctrl then
        local b = chars:byte(1)
        if b and b >= 32 and b ~= 127 then
            state.buffer = state.buffer .. chars
            rebuildInput()
            startCursorBlink()
            updateReadyState()
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
    -- Sample appearance first so newOverlay() picks up the right palette and
    -- mid-session-stale color references in other functions see fresh values.
    loadAppearance()
    local x, inputTop, sf = placeOverlay()

    state.open               = true
    state.buffer             = ""
    state.response           = ""
    state.attachments        = {}
    state.textContext        = nil
    state.lastPrompt         = nil
    state.anchorX            = x
    state.inputTop           = inputTop
    state.screenFrame        = sf
    state.statusKind         = "idle"
    if not opts.continued then
        state.history = {}
        state.sessionId = nil
        state.lastSubmittedPrompt = nil
    end
    -- Auto-attach the current selection as context. AX returns nothing for
    -- unsupported controls (Terminal etc.) — user falls back to ⌘⇧V for those.
    local sel = selectedText()
    if sel and sel ~= "" then state.textContext = sel end

    state.canv = newOverlay()
    applyCanvasFrame()  -- screen-fit-clamps + calls relayout
    rebuildInput()
    rebuildResponse()
    setStatus("idle")
    startCursorBlink()
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
        setStatus("softError")
        return
    end

    state.response            = ""
    state.lastPrompt          = userText ~= "" and userText or finalPrompt
    state.lastSubmittedPrompt = userText
    state.buffer              = ""
    rebuildInput()
    rebuildResponse()
    setStatus("thinking")

    local function onChunk(text)
        state.response = state.response .. text
        rebuildResponseThrottled()
    end

    local function onDone()
        if not state.open then return end
        table.insert(state.history, { role = "user", content = finalPrompt })
        table.insert(state.history, { role = "assistant", content = state.response })
        setStatus("success")
        -- Card-mode: keep the just-finished reply visible. state.response is
        -- cleared so outputText() falls back to the last assistant turn in
        -- history (same content, just a different lookup path).
        state.response   = ""
        state.lastPrompt = nil
        state.buffer     = ""
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
