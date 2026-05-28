-- Canvas-backed card renderer with two-box layout. Left box hosts the input
-- and ranked list; right box hosts the focused item's preview and the
-- shortcuts that act on it. Visual treatment mirrors Muse: blue accent
-- stroke around each box, theme-aware bg, .AppleSystemUIFontMedium typography,
-- alpha-blink cursor, dark-mode text shadow.

local canvas    = hs.canvas
local screen    = hs.screen
local timer     = hs.timer
local styledtxt = hs.styledtext
local drawing   = hs.drawing
local textbuf   = require("Palette.textbuffer")

local M = {}

-- Set by drawLeftBox so M.hitTestRow can answer clicks without re-deriving
-- listY (which depends on the wrapped input height).
local lastListLayout = nil

local cfg = {
    width             = 500,
    height            = 330,
    boxGap            = 8,

    leftBoxW          = 320,
    -- rightBoxW = width - leftBoxW - boxGap = 172

    pad               = 16,
    cornerRadius      = 12,
    strokeWidth       = 2,

    font              = ".AppleSystemUIFontMedium",
    inputFontSize     = 20,
    inputMinFontSize  = 12,
    titleFontSize     = 16,
    subtitleFontSize  = 12,
    accessoryFontSize = 14,
    crumbFontSize     = 11,
    footerFontSize    = 11,

    previewTitleSize  = 16,
    previewSubSize    = 11,
    verbLabelSize     = 16,
    verbHotkeySize    = 18,

    cursorWidth       = 2,

    crumbH            = 18,
    -- inputHCompact is the single-line input height used in non-noun stages
    -- and the visual minimum reserve for the input area on the noun stage. On
    -- the noun stage the input can grow up to the full left-box interior;
    -- fitText only starts shrinking the font when even that's exceeded.
    inputHCompact     = 36,

    rows              = 5,
    rowH              = 48,
    iconSize          = 28,
    accentBarW        = 3,

    footerH           = 22,
}

local C = {
    bg     = { white = 1, alpha = 0.98 },
    fg     = { white = 0, alpha = 1 },
    muted  = { white = 0, alpha = 0.55 },
    accent = { red = 0.1, green = 0.3, blue = 0.9, alpha = 1 },
    hilite = { red = 0.1, green = 0.3, blue = 0.9, alpha = 0.10 },
}

local textShadow = {
    offset     = { h = -1, w = 0 },
    blurRadius = 2,
    color      = { alpha = 0 },
}

local function loadAppearance()
    local isDark = hs.host.interfaceStyle() == "Dark"
    if isDark then
        C.bg.white,    C.bg.alpha    = 0.12, 0.96
        C.fg.white,    C.fg.alpha    = 1,    1
        C.muted.white, C.muted.alpha = 1,    0.55
        C.hilite      = { red = 0.45, green = 0.65, blue = 1.0, alpha = 0.16 }
        textShadow.color.alpha = 1
    else
        C.bg.white,    C.bg.alpha    = 1,    0.98
        C.fg.white,    C.fg.alpha    = 0,    1
        C.muted.white, C.muted.alpha = 0,    0.55
        C.hilite      = { red = 0.1, green = 0.3, blue = 0.9, alpha = 0.10 }
        textShadow.color.alpha = 0
    end
end

-- Anchor near the mouse cursor, then clamp inside the cursor's screen.
local function mouseAnchorFrame()
    local mouseScreen = hs.mouse.getCurrentScreen() or screen.mainScreen()
    local sf          = mouseScreen:frame()
    local m           = hs.mouse.absolutePosition()
    local margin      = 8
    local x = m.x - cfg.width / 2
    local y = m.y + 12
    if x < sf.x + margin then x = sf.x + margin end
    if x + cfg.width > sf.x + sf.w - margin then x = sf.x + sf.w - cfg.width - margin end
    if y + cfg.height > sf.y + sf.h - margin then y = sf.y + sf.h - cfg.height - margin end
    if y < sf.y + margin then y = sf.y + margin end
    return { x = x, y = y, w = cfg.width, h = cfg.height }
end

local card           = nil
local cursorAlpha    = 1.0
local cursorTimer    = nil
local cursorElemIdx  = nil  -- canvas element index of the cursor rect; blink mutates only this

local function measureSize(text, fontName, fontSize)
    local s = styledtxt.new(text == "" and "M" or text,
        { font = { name = fontName, size = fontSize } })
    local sz = drawing.getTextDrawingSize(s)
    if text == "" then
        return { w = 0, h = (sz and sz.h) or (fontSize + 4) }
    end
    return sz or { w = 0, h = fontSize + 4 }
end

-- Line height depends on font+size only; memoise so fitText's descending-size
-- probe loop and the blink-time empty-buffer branch don't re-measure "M".
local lineHCache = {}
local function lineHeightFor(fontName, fontSize)
    local key = fontName .. "@" .. fontSize
    local h = lineHCache[key]
    if not h then
        h = measureSize("", fontName, fontSize).h
        lineHCache[key] = h
    end
    return h
end

-- Word-wrap content into lines that fit wrapW at the given font; falls back to
-- character wrap for tokens wider than wrapW. Returns lines, lineH, widthOf.
local function wrapLines(content, wrapW, fontName, fontSize)
    if wrapW <= 0 then wrapW = 1 end
    local function widthOf(text)
        if text == "" then return 0 end
        return measureSize(text, fontName, fontSize).w
    end
    local lineH = lineHeightFor(fontName, fontSize)

    local function charWrap(token, lines)
        local run = ""
        for _, cp in utf8.codes(token) do
            local ch = utf8.char(cp)
            if run ~= "" and widthOf(run .. ch) > wrapW then
                lines[#lines + 1] = run
                run = ch
            else
                run = run .. ch
            end
        end
        return run
    end

    local lines = {}
    for paragraph in (content .. "\n"):gmatch("([^\n]*)\n") do
        local current = ""
        for word, spaces in paragraph:gmatch("(%S+)(%s*)") do
            local candidate = current .. word
            if widthOf(candidate) > wrapW then
                if current ~= "" then
                    lines[#lines + 1] = current
                    current = ""
                end
                if widthOf(word) > wrapW then
                    current = charWrap(word, lines) .. spaces
                else
                    current = word .. spaces
                end
            else
                current = candidate .. spaces
            end
        end
        lines[#lines + 1] = current
    end
    return lines, lineH, widthOf
end

-- Pick the largest font size at which wrapped content fits in regionH.
local function fitText(content, wrapW, regionH, fontName, maxSize, minSize)
    if wrapW <= 0 then wrapW = 1 end
    local size = maxSize
    while true do
        local lines, lineH, widthOf = wrapLines(content, wrapW, fontName, size)
        if (#lines * lineH) <= regionH or size <= minSize then
            return lines, lineH, size, widthOf
        end
        size = size - 1
    end
end

local function startCursorBlink()
    if cursorTimer then return end
    cursorAlpha = 1.0
    cursorTimer = timer.doEvery(0.53, function()
        cursorAlpha = (cursorAlpha > 0.5) and 0.0 or 1.0
        if card and cursorElemIdx and card[cursorElemIdx] then
            card[cursorElemIdx].fillColor = {
                red   = C.accent.red,
                green = C.accent.green,
                blue  = C.accent.blue,
                alpha = cursorAlpha,
            }
        end
    end)
end

local function stopCursorBlink()
    if cursorTimer then cursorTimer:stop(); cursorTimer = nil end
    cursorAlpha = 1.0
end

function M.show()
    loadAppearance()
    if card then card:delete(); card = nil end
    card = canvas.new(mouseAnchorFrame())
    card:level(canvas.windowLevels.modalPanel)
    card:behavior({ "canJoinAllSpaces", "stationary" })
    card:show()
    startCursorBlink()
end

function M.hide()
    stopCursorBlink()
    if card then card:delete(); card = nil end
    cursorElemIdx = nil
    lastListLayout = nil
end

-- The 4px row gap is a dead zone so clicks match the visual.
function M.hitTestRow(p)
    local L = lastListLayout
    if not L then return nil end
    if p.x < L.innerX or p.x > L.innerX + L.innerW then return nil end
    for i = 1, L.rowsToShow do
        local rowTop = L.listY + (i - 1) * L.rowH
        local rowBot = rowTop + L.rowH - 4
        if p.y >= rowTop and p.y <= rowBot then
            return L.scroll + i
        end
    end
    return nil
end

function M.isShown()
    return card ~= nil
end

function M.frame()
    return card and card:frame() or nil
end

function M.visibleRows()
    return cfg.rows
end

local function clear()
    while #card > 0 do card:removeElement(#card) end
end

local function styled(text, color, size, lineBreak)
    return styledtxt.new(text or "", {
        font           = { name = cfg.font, size = size },
        color          = color,
        shadow         = textShadow,
        paragraphStyle = { lineBreak = lineBreak or "truncateTail" },
    })
end

local function placeholderFor(state)
    if state.stage == "noun" then
        return state.appName ~= "" and ("Search " .. state.appName) or "Search…"
    elseif state.stage == "verb" then
        return "Verb…"
    else
        return "Choose…"
    end
end

local function footerFor(state)
    if #state.items == 0 then
        return state.query ~= "" and "No matches" or " "
    end
    if state.stage == "noun" then
        return "⏎ activate   ⇥ verb   esc close"
    end
    return "⏎ run   ⇧⇥ back   esc back"
end

-- ---------------- Drawing helpers (per-box, take box origin) ----------------

local function drawBox(x, y, w, h)
    local strokeInset = cfg.strokeWidth / 2
    card[#card + 1] = {
        type             = "rectangle",
        action           = "strokeAndFill",
        fillColor        = C.bg,
        strokeColor      = C.accent,
        strokeWidth      = cfg.strokeWidth,
        roundedRectRadii = { xRadius = cfg.cornerRadius, yRadius = cfg.cornerRadius },
        frame            = {
            x = x + strokeInset,
            y = y + strokeInset,
            w = w - 2 * strokeInset,
            h = h - 2 * strokeInset,
        },
    }
end

local function drawLeftBox(state)
    local boxX = 0
    local boxY = 0
    local boxW = cfg.leftBoxW
    local boxH = cfg.height
    drawBox(boxX, boxY, boxW, boxH)

    local pad = cfg.pad
    local innerX = boxX + pad
    local innerW = boxW - 2 * pad

    -- Breadcrumb (shown when past noun stage)
    local topY = boxY + pad
    local crumb = ""
    if state.selectedItem then crumb = state.selectedItem.title or "" end
    if state.selectedVerb then crumb = crumb .. " › " .. (state.selectedVerb.label or "") end
    if crumb ~= "" then
        card[#card + 1] = {
            type  = "text",
            text  = styled(crumb .. " ›", C.muted, cfg.crumbFontSize),
            frame = { x = innerX, y = topY, w = innerW, h = cfg.crumbH },
        }
        topY = topY + cfg.crumbH + 2
    end

    -- Input + cursor. The input may grow to take the whole left box if the
    -- wrapped text needs that much room; the list below shrinks (and can fall
    -- to zero visible rows). Only when wrapped text would exceed even the
    -- full box does the font start shrinking (down to inputMinFontSize). In
    -- verb / prep stages we cap to a single-line compact region — those
    -- queries are short.
    local inputY = topY + 4
    local placeholder = placeholderFor(state)
    local showingPlaceholder = state.query == ""

    local inputMaxH
    if state.stage == "noun" then
        inputMaxH = boxY + boxH - pad - inputY
    else
        inputMaxH = cfg.inputHCompact
    end
    if inputMaxH < cfg.inputHCompact then inputMaxH = cfg.inputHCompact end

    local renderSize, cursorLineH, cursorLastLineW, cursorNumLines, inputH

    if showingPlaceholder then
        renderSize      = cfg.inputFontSize
        cursorLineH     = measureSize("M", cfg.font, renderSize).h
        cursorLastLineW = 0
        cursorNumLines  = 1
        inputH          = cursorLineH

        card[#card + 1] = {
            type  = "text",
            text  = styled(placeholder, C.muted, renderSize),
            frame = { x = innerX, y = inputY, w = innerW, h = math.max(inputH, cfg.inputHCompact) },
        }
    else
        local lines, lineH, size, widthOf = fitText(
            state.query, innerW, inputMaxH, cfg.font,
            cfg.inputFontSize, cfg.inputMinFontSize
        )
        renderSize  = size
        cursorLineH = lineH
        inputH      = math.min(#lines * lineH, inputMaxH)

        -- Locate the caret inside the *full-buffer* wrap so multi-line wrap
        -- boundaries snap to the start of the next visible line (the prefix-
        -- wrap approach put the cursor at end-of-previous-line, which is wrong
        -- once the buffer wraps).
        local byteBefore = textbuf.byteOffset(state.query, state.caret or 0) - 1
        cursorNumLines, cursorLastLineW = textbuf.caretInLines(byteBefore, lines, widthOf)

        local inputStyled = styledtxt.new(state.query, {
            font           = { name = cfg.font, size = renderSize },
            color          = C.fg,
            shadow         = textShadow,
            paragraphStyle = { lineBreak = "wordWrap" },
        })
        card[#card + 1] = {
            type  = "text",
            text  = inputStyled,
            frame = { x = innerX, y = inputY, w = innerW, h = math.max(inputH, cursorLineH) },
        }
    end

    local cursorX = innerX + cursorLastLineW + 1
    local cursorY = inputY + (cursorNumLines - 1) * cursorLineH
    local maxCursorY = inputY + math.max(0, inputH - cursorLineH)
    if cursorY > maxCursorY then cursorY = maxCursorY end
    card[#card + 1] = {
        type      = "rectangle",
        action    = "fill",
        fillColor = { red = C.accent.red, green = C.accent.green, blue = C.accent.blue, alpha = cursorAlpha },
        frame     = { x = cursorX, y = cursorY, w = cfg.cursorWidth, h = cursorLineH },
    }
    cursorElemIdx = #card

    -- Item rows. listY follows the actual rendered input height so as the
    -- input grows the list slides down. The row count is also clipped by the
    -- remaining vertical space so rows never overflow the bottom pad — zero
    -- rows is a valid state (the right pane handles the Ask-Muse fallback).
    local listY        = inputY + math.max(inputH, cfg.inputHCompact) + 10
    local availForList = (boxY + boxH - pad) - listY
    local maxRowsByH   = math.max(0, math.floor(availForList / cfg.rowH))
    local scroll       = state.scrollOffset or 0
    local rowsToShow   = math.min(cfg.rows, #state.items - scroll, maxRowsByH)
    for i = 1, rowsToShow do
        local globalIdx = scroll + i
        local it        = state.items[globalIdx]
        if not it then break end
        local rowY      = listY + (i - 1) * cfg.rowH
        local focused   = (globalIdx == state.focused)

        if focused then
            card[#card + 1] = {
                type             = "rectangle",
                action           = "fill",
                roundedRectRadii = { xRadius = 6, yRadius = 6 },
                fillColor        = C.hilite,
                frame            = { x = innerX, y = rowY, w = innerW, h = cfg.rowH - 4 },
            }
            card[#card + 1] = {
                type             = "rectangle",
                action           = "fill",
                roundedRectRadii = { xRadius = 1.5, yRadius = 1.5 },
                fillColor        = C.accent,
                frame            = { x = innerX, y = rowY + 6, w = cfg.accentBarW, h = cfg.rowH - 16 },
            }
        end

        local textLeft = innerX + cfg.accentBarW + 8

        -- Row number badge (1..9) for bare-digit quick-pick.
        if i <= 9 then
            card[#card + 1] = {
                type          = "text",
                text          = styled(tostring(i), C.accent, 18),
                textAlignment = "right",
                frame         = { x = textLeft, y = rowY + 6, w = 20, h = 24 },
            }
            textLeft = textLeft + 20 + 8
        end

        if it.icon then
            card[#card + 1] = {
                type         = "image",
                image        = it.icon,
                imageScaling = "scaleProportionally",
                frame        = {
                    x = textLeft,
                    y = rowY + (cfg.rowH - cfg.iconSize) / 2 - 2,
                    w = cfg.iconSize,
                    h = cfg.iconSize,
                },
            }
            textLeft = textLeft + cfg.iconSize + 8
        end

        -- Menu-item state mark (✓ on, • current). Sits before the title at
        -- the same baseline.
        if it.markChar then
            card[#card + 1] = {
                type          = "text",
                text          = styled(it.markChar, C.accent, 14),
                textAlignment = "left",
                frame         = { x = textLeft, y = rowY + 5, w = 14, h = 22 },
            }
            textLeft = textLeft + 14 + 4
        end

        -- History indicator at the trailing edge of the row.
        local trailingReserved = 0
        if it.fromHistory then
            card[#card + 1] = {
                type          = "text",
                text          = styled("↺", C.accent, 14),
                textAlignment = "center",
                frame         = { x = innerX + innerW - 18, y = rowY + 14, w = 16, h = 20 },
            }
            trailingReserved = 22
        end

        local textW      = math.max(0, innerX + innerW - textLeft - trailingReserved)
        local titleColor = (it.enabled == false) and C.muted or C.fg
        card[#card + 1] = {
            type  = "text",
            text  = styled(it.title or "", titleColor, cfg.titleFontSize, "truncateMiddle"),
            frame = { x = textLeft, y = rowY + 5, w = textW, h = 22 },
        }
        if it.subtitle and it.subtitle ~= "" then
            card[#card + 1] = {
                type  = "text",
                text  = styled(it.subtitle, C.muted, cfg.subtitleFontSize),
                frame = { x = textLeft, y = rowY + 27, w = textW, h = 16 },
            }
        end
    end

    lastListLayout = {
        innerX     = innerX,
        innerW     = innerW,
        listY      = listY,
        rowsToShow = rowsToShow,
        scroll     = scroll,
        rowH       = cfg.rowH,
    }
end

-- Right box: focused item preview + hotkeys (default verb on ⏎, others on
-- ⌘1..⌘9). The actual key wiring is in init.lua; this function only renders.
local function drawRightBox(state, hotkeyList)
    local boxX = cfg.leftBoxW + cfg.boxGap
    local boxY = 0
    local boxW = cfg.width - boxX
    local boxH = cfg.height
    drawBox(boxX, boxY, boxW, boxH)

    local pad = cfg.pad
    local innerX = boxX + pad
    local innerW = boxW - 2 * pad

    local focusedItem = state.items[state.focused]

    -- Synthesize a pseudo-item for the Ask Muse fallback so the rest of this
    -- function draws it with exactly the same layout as a real focused item.
    if not focusedItem and state.query ~= "" and state.stage == "noun" then
        focusedItem = { title = state.query, icon = nil, accessory = nil }
        if not hotkeyList or #hotkeyList == 0 then
            hotkeyList = { { hotkey = "⏎", label = "Ask Muse" } }
        end
    end

    if not focusedItem then
        card[#card + 1] = {
            type          = "text",
            text          = styled("Nothing focused", C.muted, cfg.verbLabelSize),
            textAlignment = "center",
            frame         = { x = innerX, y = boxY + pad + 20, w = innerW, h = 20 },
        }
        return
    end

    local cursorY = boxY + pad

    -- Big-ish icon if the item has one (apps). For accessory-only items
    -- (menu shortcuts), render the accessory glyph as oversized text instead.
    if focusedItem.icon then
        local sz = 56
        card[#card + 1] = {
            type         = "image",
            image        = focusedItem.icon,
            imageScaling = "scaleProportionally",
            frame        = { x = innerX + (innerW - sz) / 2, y = cursorY, w = sz, h = sz },
        }
        cursorY = cursorY + sz + 8
    elseif focusedItem.accessory then
        card[#card + 1] = {
            type          = "text",
            text          = styled(focusedItem.accessory, C.accent, 28),
            textAlignment = "center",
            frame         = { x = innerX, y = cursorY + 6, w = innerW, h = 40 },
        }
        cursorY = cursorY + 56
    else
        cursorY = cursorY + 8
    end

    -- Title only — the subtitle (menu path / window count / etc) is already
    -- shown in the left row, no need to repeat it.
    card[#card + 1] = {
        type          = "text",
        text          = styled(focusedItem.title or "", C.fg, cfg.previewTitleSize),
        textAlignment = "center",
        frame         = { x = innerX, y = cursorY, w = innerW, h = 22 },
    }
    cursorY = cursorY + 22 + 14

    -- Hotkey list. hotkeyList is built by init.lua and looks like
    -- { { hotkey = "⏎", label = "Activate" }, { hotkey = "⌘1", label = "Ask Muse" }, ... }
    if hotkeyList and #hotkeyList > 0 then
        local rowH = 24
        local hkColW = 36
        for _, hk in ipairs(hotkeyList) do
            card[#card + 1] = {
                type          = "text",
                text          = styled(hk.hotkey or "", C.accent, cfg.verbHotkeySize),
                textAlignment = "right",
                frame         = { x = innerX, y = cursorY + 4, w = hkColW, h = rowH },
            }
            card[#card + 1] = {
                type  = "text",
                text  = styled(hk.label or "", C.fg, cfg.verbLabelSize),
                frame = { x = innerX + hkColW + 10, y = cursorY + 4, w = innerW - hkColW - 10, h = rowH },
            }
            cursorY = cursorY + rowH
        end
    end
end

function M.draw(state, hotkeyList)
    if not card then return end
    clear()
    cursorElemIdx = nil
    drawLeftBox(state)
    drawRightBox(state, hotkeyList)
end

return M
