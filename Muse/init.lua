-- Muse: an inline AI companion. Double-tap right ⌘ to summon near the text caret.
--
-- While the overlay is open:
--   type → ask, Enter → submit (or, with empty buffer, paste the latest reply
--   into the focused field), Esc → cancel.
--   ⌘⇧S → capture a region and attach as image. ⌘⌫ → clear attachments.
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
    doubleTapMs    = 250,
    continueMs     = 600,
    anchorOffset   = 8,
    overlayWidth   = 540,
    inputHeight    = 46,
    responseHeight = 260,
    pad            = 8,
    font           = ".AppleSystemUIFontMedium",
    fontSize       = 20,
    rightCmdCode   = 54, -- right ⌘
    backends       = {}, -- per-plugin config: Muse.config.backends[name] = { ... }
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
    local mar = 8

    -- Horizontal: prefer leading-edge alignment with the caret. If the overlay
    -- would overflow the right edge, right-align its right edge to the trailing
    -- edge of the caret/selection so the visual anchor stays meaningful.
    local x = leadX
    if x + cfg.overlayWidth > sf.x + sf.w - mar then
        x = trailX - cfg.overlayWidth
    end
    if x < sf.x + mar then x = sf.x + mar end
    if x + cfg.overlayWidth > sf.x + sf.w - mar then
        x = sf.x + sf.w - cfg.overlayWidth - mar
    end

    -- Vertical: always below the caret; slide up only enough to keep the input
    -- inside the screen.
    local inputTop = bottom + cfg.anchorOffset
    if inputTop + cfg.inputHeight > sf.y + sf.h - mar then
        inputTop = sf.y + sf.h - mar - cfg.inputHeight
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
    timer.doAfter(0.12, function() if saved then pb.setContents(saved) end end)
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
}

local close, submitPrompt, commitResponse, rebuildResponse, applyCanvasFrame

local function setStatus(kind, reposition)
    if not state.canv then return end
    if (not reposition) and state.statusTimer then
        state.statusTimer:stop(); state.statusTimer = nil
    end
    state.statusKind = kind
    local frameW     = state.canv:frame().w
    local dotRight   = frameW - cfg.pad
    local dotGap     = 8
    local dotR       = 3
    local dotY       = cfg.inputHeight / 2
    if kind == "active" then
        -- Three-dot bouncing wave during streaming.
        for i = 0, 2 do
            state.canv[3 + i].action = "fill"
            state.canv[3 + i].radius = dotR
            state.canv[3 + i].fillColor = C.spinner
        end
        if reposition then
            for i = 0, 2 do
                state.canv[3 + i].center = { x = dotRight - (2 - i) * dotGap, y = dotY }
            end
        else
            local t0           = timer.secondsSinceEpoch()
            local period       = 1.1
            local bounceHeight = 4
            local sigma        = 0.08
            state.statusTimer  = timer.doEvery(0.016, function()
                if not state.canv then return end
                local t = ((timer.secondsSinceEpoch() - t0) / period) % 1
                for i = 0, 2 do
                    local peakAt = (i + 0.5) / 3
                    local d = t - peakAt
                    if d > 0.5 then d = d - 1 elseif d < -0.5 then d = d + 1 end
                    local lift = bounceHeight * math.exp(-(d * d) / (2 * sigma * sigma))
                    state.canv[3 + i].center = {
                        x = dotRight - (2 - i) * dotGap,
                        y = dotY - lift,
                    }
                end
            end)
        end
    else
        -- Idle / error: a single solid dot, the other two skipped.
        local color = (kind == "error") and C.error or C.spinner
        state.canv[3].action = "fill"
        state.canv[3].radius = dotR + 0.5
        state.canv[3].fillColor = color
        state.canv[3].center = { x = dotRight - dotR, y = dotY }
        state.canv[4].action = "skip"
        state.canv[5].action = "skip"
    end
end

-- Position input-row elements (input text + status dots) inside the canvas.
-- Input always sits at the top of the canvas; called once at open and after
-- every resize.
local function relayout()
    if not state.canv then return end
    local frameW     = state.canv:frame().w
    local inputTextY = math.floor((cfg.inputHeight - cfg.fontSize) / 2) - 2
    -- Right edge reserves space for status dot (~20px) plus chip when visible.
    local chipReserved = (#state.attachments > 0) and (76 + cfg.pad) or 0
    local rightReserve = 20 + chipReserved
    state.canv[2].frame = {
        x = cfg.pad,
        y = inputTextY,
        w = math.max(0, frameW - cfg.pad - rightReserve),
        h = cfg.fontSize + 8,
    }
    local chipRight = frameW - cfg.pad - 20
    local cardSize = 30
    local cardStep = 12
    local cardY = math.floor((cfg.inputHeight - cardSize) / 2)
    -- Cards: c[11]=front (rightmost), c[10]=middle, c[9]=back (leftmost).
    -- 12px step between left edges overlaps cards by 18px for a stack read.
    state.canv[11].frame = { x = chipRight - cardSize,                y = cardY, w = cardSize, h = cardSize }
    state.canv[10].frame = { x = chipRight - cardSize - cardStep,     y = cardY, w = cardSize, h = cardSize }
    state.canv[9].frame  = { x = chipRight - cardSize - 2 * cardStep, y = cardY, w = cardSize, h = cardSize }
    -- "+N" overflow label sits left of the back card.
    state.canv[8].frame = {
        x = chipRight - cardSize - 2 * cardStep - 18,
        y = math.floor((cfg.inputHeight - 13) / 2) - 1,
        w = 16,
        h = 13 + 6,
    }
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
    if #state.history > 0 and not state.lastPrompt then
        return "↵ to insert · type to refine", C.accent
    end
    return "ask anything · ⌘⇧S to attach", C.muted
end

local function rebuildCursor()
    if not state.canv then return end
    local x = cfg.pad
    if state.buffer ~= "" then
        local sz = state.canv:minimumTextSize(2, state.buffer)
        if sz and sz.w then x = cfg.pad + sz.w end
    end
    local cursorH = cfg.fontSize + 4
    local cursorY = (cfg.inputHeight - cursorH) / 2
    local visible = state.cursorOn and not (state.task and state.task:isRunning())
    state.canv[7].frame = { x = x, y = cursorY, w = 1.5, h = cursorH }
    state.canv[7].fillColor = { white = 1, alpha = visible and 1.0 or 0 }
end

local function computeInputWidth()
    local probe = state.buffer ~= "" and state.buffer or placeholderForState()
    local styled = inputStyled(probe, C.fg)
    local sz = hs.drawing.getTextDrawingSize(styled)
    local textW = (sz and sz.w) or 100
    local chipW = (#state.attachments > 0) and (76 + cfg.pad) or 0
    local dotW = 20
    local w = math.ceil(textW) + 2 * cfg.pad + chipW + dotW
    return math.min(cfg.overlayWidth, w)
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
    -- Card slots render thumbnails of the 3 most recent attachments. Front
    -- (c[11], rightmost) is the newest; back (c[9]) is two-prior. Back cards
    -- dim via imageAlpha to imply depth.
    local alphas = { 0.55, 0.8, 1.0 }  -- back, middle, front
    for slot = 0, 2 do
        local idx = 9 + slot
        local stepsFromFront = 2 - slot          -- front=0, middle=1, back=2
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
    local mar = 8
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
    local duration = 0.18
    state.sizeAnim = timer.doEvery(0.016, function()
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

local function buildTranscript(skipTurns)
    -- Build a styledtext transcript with per-paragraph alignment:
    -- user prompts left, AI replies right. Optional skipTurns trims the oldest
    -- N entries from state.history (for overflow handling).
    local function mkAttrs(align, color)
        return {
            font = { name = cfg.font, size = cfg.fontSize },
            color = color or C.fg,
            paragraphStyle = { alignment = align },
            shadow = textShadow,
        }
    end
    local userA           = mkAttrs("right")
    local aiA             = mkAttrs("left")
    -- "Enter target": when the buffer is empty, plain Enter commits the latest
    -- assistant reply. Highlight that reply in spinner blue so the user sees
    -- what will be pasted. Suppress when buffer has text (Enter then submits).
    local highlightLatest = (state.buffer == "")
    local aiLatest        = mkAttrs("left", C.spinner)
    local latestAiIdx     = nil
    if highlightLatest then
        for i = #state.history, (skipTurns or 0) + 1, -1 do
            if state.history[i].role == "assistant" then
                latestAiIdx = i; break
            end
        end
    end
    local segs = {}
    for i = (skipTurns or 0) + 1, #state.history do
        local msg = state.history[i]
        local attrs
        if msg.role == "user" then
            attrs = userA
        elseif i == latestAiIdx then
            attrs = aiLatest
        else
            attrs = aiA
        end
        segs[#segs + 1] = { text = msg.content, attrs = attrs }
    end
    if state.lastPrompt then
        segs[#segs + 1] = { text = state.lastPrompt, attrs = userA }
        if state.response ~= "" then
            segs[#segs + 1] = { text = state.response, attrs = aiA }
        end
    elseif state.response ~= "" then
        -- No pending prompt → response is guidance/error text; left-align it
        -- regardless of the user/ai alignment scheme.
        segs[#segs + 1] = { text = state.response, attrs = mkAttrs("left") }
    end
    if #segs == 0 then return nil end
    local result = nil
    for i, seg in ipairs(segs) do
        local text = seg.text
        if i < #segs then text = text .. "\n\n" end
        local s = hs.styledtext.new(text, seg.attrs)
        result = result and (result .. s) or s
    end
    return result
end

rebuildResponse = function()
    if not state.canv then return end
    -- Decide target width: once any response/history is present, expand to
    -- cfg.overlayWidth and stay there for the rest of the session.
    local hasContent = (#state.history > 0) or state.response ~= "" or state.lastPrompt
    local targetW
    if hasContent then
        state.expanded = true
        targetW = cfg.overlayWidth
    else
        targetW = computeInputWidth()
    end
    -- Cap response height by absolute screen height (minus input + margins).
    -- The canvas shifts upward when it would overflow the bottom edge — see
    -- applyCanvasFrame — so we don't need to reserve only the space below.
    local sf = state.screenFrame
    local mar = 8
    local availH = sf.h - 2 * mar - cfg.inputHeight - 6
    if availH < 0 then availH = 0 end
    local maxH = math.min(cfg.responseHeight, availH)
    local frameW = targetW - 2 * cfg.pad
    local respY = cfg.inputHeight + 4
    -- Iteratively drop oldest turns until the styled transcript fits the cap.
    local skip = 0
    local styled, measuredH
    while true do
        styled = buildTranscript(skip)
        if not styled then
            measuredH = 0; break
        end
        state.canv[6].frame = { x = cfg.pad, y = respY, w = frameW, h = maxH }
        state.canv[6].text = styled
        local sz = state.canv:minimumTextSize(6, styled)
        measuredH = (sz and sz.h) or 0
        if measuredH <= maxH then break end
        if skip + 2 > #state.history then break end -- can't drop pending turn
        skip = skip + 2
    end
    if not styled then state.canv[6].text = "" end
    local contentH = math.min(math.ceil(measuredH) + 4, maxH)
    if measuredH <= 0 then contentH = 0 end
    state.canv[6].frame = { x = cfg.pad, y = respY, w = frameW, h = contentH }
    local targetCanvasH = cfg.inputHeight + (contentH > 0 and 6 + contentH or 0)
    animateCanvasTo(targetW, targetCanvasH)
end

local rebuildPendingTimer = nil
local rebuildLastAt = 0
local function rebuildResponseThrottled()
    local now = timer.secondsSinceEpoch()
    if now - rebuildLastAt >= 0.1 then
        if rebuildPendingTimer then
            rebuildPendingTimer:stop(); rebuildPendingTimer = nil
        end
        rebuildLastAt = now
        rebuildResponse()
    elseif not rebuildPendingTimer then
        rebuildPendingTimer = timer.doAfter(0.1 - (now - rebuildLastAt), function()
            rebuildPendingTimer = nil
            rebuildLastAt = timer.secondsSinceEpoch()
            rebuildResponse()
        end)
    end
end

local function newOverlay()
    -- Initial canvas covers just the input row. Width starts as fit-to-text
    -- when the session is fresh; expanded state (set by rebuildResponse) jumps
    -- straight to cfg.overlayWidth.
    local initW = state.expanded and cfg.overlayWidth or computeInputWidth()
    local c = canvas.new({
        x = state.anchorX,
        y = state.inputTop,
        w = initW,
        h = cfg.inputHeight,
    })
    c[1] = {
        type = "rectangle",
        action = "fill",
        fillColor = C.bg,
        roundedRectRadii = { xRadius = 4, yRadius = 4 },
    }
    c[2] = {
        type = "text",
        text = "",
        textFont = cfg.font,
        textSize = cfg.fontSize,
        textColor = C.muted,
        frame = { x = cfg.pad, y = 0, w = math.max(0, initW - cfg.pad - 20), h = cfg.fontSize + 8 },
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
        frame = { x = cfg.pad, y = cfg.inputHeight + 4, w = math.max(0, initW - 2 * cfg.pad), h = 0 },
    }
    -- Text cursor: a thin rectangle drawn separately from the text element so
    -- blinking it on/off can't shift the placeholder layout.
    c[7] = {
        type = "rectangle",
        action = "fill",
        fillColor = { white = 1, alpha = 0 },
        frame = { x = cfg.pad, y = 0, w = 1.5, h = cfg.fontSize + 4 },
    }
    -- Attachment chip: stack-of-cards visual shown in the input row when
    -- state.attachments is non-empty. c[9..11] are the cards (back→front),
    -- c[8] is the "+N" overflow label rendered when n > 3. Positioned in
    -- relayout(), state-flipped in rebuildInput().
    c[8] = {
        type = "text",
        text = "",
        action = "skip",
        textFont = cfg.font,
        textSize = 11,
        textColor = C.accent,
        frame = { x = 0, y = 0, w = 14, h = cfg.inputHeight },
    }
    for i = 0, 2 do
        c[9 + i] = {
            type = "image",
            action = "skip",
            image = nil,
            imageAlignment = "center",
            imageScaling = "scaleToFit",
            imageAlpha = 1.0,
            frame = { x = 0, y = 0, w = 30, h = 30 },
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

    if cmdOnly and key == "delete" then
        if #state.attachments > 0 then
            state.attachments = {}
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
    state.lastPrompt      = nil
    state.anchorX         = x
    state.inputTop        = inputTop
    state.screenFrame     = sf
    state.statusKind      = "idle"
    if not opts.continued then
        state.history = {}
        state.sessionId = nil
    end
    -- Continued sessions reopen at full width (history will fill the response
    -- area); fresh sessions start narrow and grow with the input text.
    state.expanded = opts.continued and #state.history > 0

    state.canv = newOverlay()
    relayout()
    rebuildInput()
    setStatus("idle")
    state.cursorOn = true
    state.cursorTimer = timer.doEvery(0.53, function()
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
    timer.doAfter(0.04, function() pasteText(out) end)
end

submitPrompt = function()
    local userText = state.buffer
    if userText == "" then return end
    local finalPrompt = userText

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
        if elapsed <= cfg.doubleTapMs and state.lastRCmdEdge > 0 then
            if state.open then
                close()
            else
                local continued = #state.history > 0
                    and ((now - state.lastClose) * 1000 <= cfg.continueMs)
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
