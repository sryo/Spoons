-- Canvas-backed card renderer. Mirrors Muse's pattern: hs.canvas, theme via
-- hs.host.interfaceStyle, fixed geometry, fully redrawn each frame. The
-- caller is responsible for triggering draw() on state change.

local canvas = hs.canvas
local screen = hs.screen

local M = {}

local cfg = {
    width            = 360,
    height           = 400,
    pad              = 16,
    cornerRadius     = 12,
    strokeWidth      = 2,
    inputHeight      = 36,
    rowHeight        = 40,
    rows             = 6,
    footerHeight     = 24,
    iconSize         = 32,
    titleFontSize    = 14,
    subtitleFontSize = 11,
    inputFontSize    = 18,
    breadcrumbH      = 18,
    dotSize          = 6,
    dotGap           = 6,
}

local C = {
    bg     = { white = 1, alpha = 0.98 },
    fg     = { white = 0, alpha = 1 },
    muted  = { white = 0, alpha = 0.55 },
    accent = { red = 0.1, green = 0.3, blue = 0.9, alpha = 1 },
    hilite = { red = 0.1, green = 0.3, blue = 0.9, alpha = 0.12 },
}

local card = nil

local function loadAppearance()
    local isDark = hs.host.interfaceStyle() == "Dark"
    if isDark then
        C.bg.white,    C.bg.alpha    = 0.12, 0.96
        C.fg.white,    C.fg.alpha    = 1,    1
        C.muted.white, C.muted.alpha = 1,    0.55
        C.hilite = { red = 0.4, green = 0.6, blue = 1, alpha = 0.22 }
    else
        C.bg.white,    C.bg.alpha    = 1,    0.98
        C.fg.white,    C.fg.alpha    = 0,    1
        C.muted.white, C.muted.alpha = 0,    0.55
        C.hilite = { red = 0.1, green = 0.3, blue = 0.9, alpha = 0.12 }
    end
end

local function centerFrame()
    local s = screen.mainScreen():frame()
    return {
        x = s.x + (s.w - cfg.width) / 2,
        y = s.y + (s.h - cfg.height) / 2 - 60,
        w = cfg.width,
        h = cfg.height,
    }
end

function M.show()
    loadAppearance()
    if card then card:delete(); card = nil end
    card = canvas.new(centerFrame())
    card:level(canvas.windowLevels.modalPanel)
    card:behavior({ "canJoinAllSpaces", "stationary" })
    card:show()
end

function M.hide()
    if card then card:delete(); card = nil end
end

function M.isShown()
    return card ~= nil
end

local function clear()
    while #card > 0 do card:removeElement(#card) end
end

local STAGES = { "noun", "verb", "prep" }
local STAGE_INDEX = { noun = 1, verb = 2, prep = 3 }

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
        return state.query ~= "" and "No matches" or "Loading…"
    end
    if state.stage == "noun" then
        return "↩ Activate · ⇥ Verb · Esc Close"
    elseif state.stage == "verb" then
        return "↩ Run · ⇧⇥ Back · Esc Back"
    else
        return "↩ Run · ⇧⇥ Back · Esc Back"
    end
end

function M.draw(state)
    if not card then return end
    clear()

    -- Background
    card[#card + 1] = {
        type             = "rectangle",
        action           = "fill",
        roundedRectRadii = { xRadius = cfg.cornerRadius, yRadius = cfg.cornerRadius },
        fillColor        = C.bg,
        strokeColor      = C.accent,
        strokeWidth      = cfg.strokeWidth,
        frame            = { x = 0, y = 0, w = "100%", h = "100%" },
    }

    -- Top strip: breadcrumb on left, stage dots on right.
    local topY = cfg.pad
    local activeStage = STAGE_INDEX[state.stage] or 1

    -- Stage dots (always present, right-aligned)
    local dotsW = #STAGES * cfg.dotSize + (#STAGES - 1) * cfg.dotGap
    local dotsX = cfg.width - cfg.pad - dotsW
    for i = 1, #STAGES do
        local cx = dotsX + (i - 1) * (cfg.dotSize + cfg.dotGap) + cfg.dotSize / 2
        local cy = topY + cfg.dotSize / 2 + 4
        local filled = i <= activeStage
        card[#card + 1] = {
            type        = "circle",
            action      = filled and "fill" or "stroke",
            radius      = cfg.dotSize / 2,
            fillColor   = filled and C.accent or C.bg,
            strokeColor = filled and C.accent or C.muted,
            strokeWidth = 1,
            center      = { x = cx, y = cy },
        }
    end

    -- Breadcrumb (selected noun + selected verb when applicable)
    local crumb = ""
    if state.selectedItem then crumb = state.selectedItem.title or "" end
    if state.selectedVerb then crumb = crumb .. " › " .. (state.selectedVerb.label or "") end
    if crumb ~= "" then
        card[#card + 1] = {
            type          = "text",
            text          = crumb .. " ›",
            textColor     = C.muted,
            textSize      = 11,
            textLineBreak = "truncateMiddle",
            frame         = { x = cfg.pad, y = topY, w = dotsX - cfg.pad - 8, h = cfg.breadcrumbH },
        }
        topY = topY + cfg.breadcrumbH + 2
    else
        topY = topY + 4
    end

    -- Input
    local inputY = topY
    local placeholder = placeholderFor(state)
    local inputText = state.query ~= "" and (state.query .. "▎") or placeholder
    card[#card + 1] = {
        type      = "text",
        text      = inputText,
        textColor = state.query ~= "" and C.fg or C.muted,
        textSize  = cfg.inputFontSize,
        frame     = { x = cfg.pad, y = inputY, w = cfg.width - 2 * cfg.pad, h = cfg.inputHeight },
    }

    -- Separator
    card[#card + 1] = {
        type      = "rectangle",
        action    = "fill",
        fillColor = C.muted,
        frame     = { x = cfg.pad, y = inputY + cfg.inputHeight + 2, w = cfg.width - 2 * cfg.pad, h = 1 },
    }

    -- Item rows
    local listY = inputY + cfg.inputHeight + 12
    local visible = math.min(#state.items, cfg.rows)
    for i = 1, visible do
        local it = state.items[i]
        local rowY = listY + (i - 1) * cfg.rowHeight

        if i == state.focused then
            card[#card + 1] = {
                type             = "rectangle",
                action           = "fill",
                roundedRectRadii = { xRadius = 6, yRadius = 6 },
                fillColor        = C.hilite,
                frame            = { x = cfg.pad - 6, y = rowY - 2, w = cfg.width - 2 * (cfg.pad - 6), h = cfg.rowHeight - 4 },
            }
        end

        local hasIcon = it.icon ~= nil
        if hasIcon then
            card[#card + 1] = {
                type         = "image",
                image        = it.icon,
                imageScaling = "scaleProportionally",
                frame        = { x = cfg.width - cfg.pad - cfg.iconSize, y = rowY, w = cfg.iconSize, h = cfg.iconSize },
            }
        end

        local textW = hasIcon
            and (cfg.width - 2 * cfg.pad - cfg.iconSize - 8)
            or (cfg.width - 2 * cfg.pad)

        card[#card + 1] = {
            type          = "text",
            text          = it.title or "",
            textColor     = C.fg,
            textSize      = cfg.titleFontSize,
            textLineBreak = "truncateTail",
            frame         = { x = cfg.pad, y = rowY, w = textW, h = 18 },
        }
        if it.subtitle and it.subtitle ~= "" then
            card[#card + 1] = {
                type          = "text",
                text          = it.subtitle,
                textColor     = C.muted,
                textSize      = cfg.subtitleFontSize,
                textLineBreak = "truncateTail",
                frame         = { x = cfg.pad, y = rowY + 18, w = textW, h = 14 },
            }
        end
    end

    -- Footer
    card[#card + 1] = {
        type          = "text",
        text          = footerFor(state),
        textColor     = C.muted,
        textSize      = 11,
        textAlignment = "center",
        frame         = {
            x = cfg.pad,
            y = cfg.height - cfg.footerHeight - 4,
            w = cfg.width - 2 * cfg.pad,
            h = cfg.footerHeight,
        },
    }
end

return M
