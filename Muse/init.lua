-- Muse: an inline AI companion. Double-tap right ⌘ to summon near the text caret.
--
-- Commit keys while overlay is open:
--   ⌘↵ paste-replace the field, ⌘↓ paste-append at caret, ⌘C copy, esc cancel.
-- ⌥ tapped alone over a selection → rewrite mode (pre-seeded with selection).
-- Double-tap right ⌘ within continueMs of last close → conversation continues.

local Muse = {}
-- Break a recursive-require cycle: backends do `require("Muse")` at their top
-- level. autoloadBackends() runs before this module returns, so package.loaded
-- isn't set yet — without this line each backend re-executes Muse from scratch,
-- creating duplicate state tables and orphan eventtaps until the C stack overflows.
package.loaded["Muse"] = Muse

local eventtap = hs.eventtap
local etypes   = eventtap.event.types
local canvas   = hs.canvas
local timer    = hs.timer
local ax       = hs.axuielement
local taskmod  = hs.task
local alert    = hs.alert
local pb       = hs.pasteboard
local json     = hs.json
local screen   = hs.screen
local keymap   = hs.keycodes.map

----------------------------------------------------------------------
-- Config
----------------------------------------------------------------------

Muse.config = {
  backend        = "claudecli",     -- "claude" | "openai" | "gemini" | "fabric" | "claudecli" | "apple"
  fallbackOrder  = { "claudecli", "claude", "openai", "gemini", "fabric", "apple" },
  doubleTapMs    = 250,
  continueMs     = 600,
  altTapMs       = 250,
  anchorOffset   = 8,
  overlayWidth   = 480,
  inputHeight    = 30,
  responseHeight = 220,
  font           = ".AppleSystemUIFont",
  fontSize       = 14,
  rightCmdCode   = 54,              -- right ⌘
  rewriteOnAlt   = true,
  backends       = {},              -- per-plugin config: Muse.config.backends[name] = { ... }
}

local cfg = Muse.config

local C = {
  bg     = { red = 0.10, green = 0.10, blue = 0.11, alpha = 0.97 },
  fg     = { white = 1, alpha = 1 },
  muted  = { white = 1, alpha = 0.45 },
  accent = { red = 0.40, green = 0.78, blue = 1.00, alpha = 1 },
  spinner = { red = 0.10, green = 0.30, blue = 0.90, alpha = 0.80 },  -- match WindowScape outlineColor
  error  = { red = 1.00, green = 0.40, blue = 0.40, alpha = 1 },
}

----------------------------------------------------------------------
-- Backends: registry, helpers, autoload
--   Each plugin under ~/.hammerspoon/Muse/backends/*.lua returns:
--     { name = "...", available = fn -> bool,reason, stream = fn(self, prompt, history, onChunk, onDone, onError) -> task }
--   Plugin config lives in Muse.config.backends[name]; plugins seed their own defaults.
--   Shared helpers exposed via Muse.helpers; access from a plugin via:
--     local M = require("Muse"); local h = M.helpers
----------------------------------------------------------------------

Muse.backends = {}

Muse.helpers = {
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

local function chooseBackend()
  local primary = Muse.backends[cfg.backend]
  if primary then
    local ok, why = primary.available()
    if ok then return primary end
    print("Muse: " .. cfg.backend .. " unavailable (" .. (why or "?") .. "), trying fallbacks")
  end
  for _, n in ipairs(cfg.fallbackOrder) do
    local b = Muse.backends[n]
    if b and b ~= primary then
      local ok = b.available()
      if ok then return b end
    end
  end
  return nil
end

----------------------------------------------------------------------
-- Anchor: caret rect with fallbacks
----------------------------------------------------------------------

local function isTypingRole(role)
  return role == "AXTextField" or role == "AXTextArea" or role == "AXComboBox"
      or role == "AXSearchField" or role == "AXWebArea"
end

local function focusedElement()
  local el
  pcall(function() el = ax.systemWideElement():attributeValue("AXFocusedUIElement") end)
  return el
end

local function anchorPoint()
  local x, y
  pcall(function()
    local el = focusedElement()
    if not el then return end
    local range = el:attributeValue("AXSelectedTextRange")
    if range then
      local b = el:parameterizedAttributeValue("AXBoundsForRange", range)
      if b and b.x and b.h then
        x, y = b.x, b.y + b.h + cfg.anchorOffset
        return
      end
    end
    local frame = el:attributeValue("AXFrame")
    if frame then x, y = frame.x, frame.y + frame.h + cfg.anchorOffset end
  end)
  if not x or not y then
    local p = hs.mouse.absolutePosition()
    x, y = p.x, p.y + cfg.anchorOffset
  end
  local scr = screen.mainScreen()
  for _, s in ipairs(screen.allScreens()) do
    local f = s:fullFrame()
    if x >= f.x and x < f.x + f.w and y >= f.y and y < f.y + f.h then scr = s; break end
  end
  local sf = scr:fullFrame()
  if x + cfg.overlayWidth > sf.x + sf.w then x = sf.x + sf.w - cfg.overlayWidth - 8 end
  if x < sf.x + 8 then x = sf.x + 8 end
  -- Reserve room for the full expanded canvas (input + response). Flip above
  -- the caret if there's not enough room below.
  local maxH = cfg.inputHeight + 6 + cfg.responseHeight
  if y + maxH > sf.y + sf.h - 8 then y = sf.y + sf.h - 8 - maxH end
  if y < sf.y + 8 then y = sf.y + 8 end
  return x, y
end

----------------------------------------------------------------------
-- Selection read + paste-injection (clipboard hack, like AnyComplete)
----------------------------------------------------------------------

local function readSelectionIfTyping()
  local el = focusedElement()
  if not el then return nil end
  local ok, role = pcall(function() return el:attributeValue("AXRole") end)
  if not ok or not isTypingRole(role) then return nil end

  local saved = pb.getContents()
  pb.clearContents()
  eventtap.keyStroke({ "cmd" }, "c", 0)
  local sel
  for _ = 1, 12 do
    timer.usleep(15000)
    local now = pb.getContents()
    if now and now ~= "" then sel = now; break end
  end
  timer.doAfter(0.12, function() if saved then pb.setContents(saved) end end)
  return sel
end

local function pasteText(text, append)
  local saved = pb.getContents()
  pb.setContents(text)
  if append then
    -- move caret to end of selection (right arrow deselects to end), then paste
    eventtap.keyStroke({}, "right", 0)
  end
  eventtap.keyStroke({ "cmd" }, "v", 0)
  timer.doAfter(0.12, function() if saved then pb.setContents(saved) end end)
end

----------------------------------------------------------------------
-- Overlay
----------------------------------------------------------------------

local state = {
  open          = false,
  canv          = nil,
  inputTap      = nil,
  buffer        = "",
  response      = "",
  history       = {},
  rewriteOf     = nil,
  task          = nil,
  queuedCommit  = nil,
  lastClose     = 0,
  lastRCmdEdge  = 0,
  rCmdHeld      = false,
  altDownAt     = nil,
  altClean      = false,
}

local close, submitPrompt, commitResponse, rebuildResponse

local function setStatus(kind)
  if not state.canv then return end
  if state.statusTimer then state.statusTimer:stop(); state.statusTimer = nil end
  local dotRight = cfg.overlayWidth - 12
  local dotGap   = 7
  local dotY     = cfg.inputHeight / 2
  if kind == "active" then
    local t0 = timer.secondsSinceEpoch()
    local period       = 1.1   -- full cycle for the wave to pass all 3 dots
    local bounceHeight = 4     -- pixels up at peak
    local sigma        = 0.08  -- width of each bounce (fraction of period)
    for i = 0, 2 do
      state.canv[3 + i].fillColor = C.spinner
    end
    state.statusTimer = timer.doEvery(0.016, function()
      if not state.canv then return end
      local t = ((timer.secondsSinceEpoch() - t0) / period) % 1
      for i = 0, 2 do
        local peakAt = (i + 0.5) / 3       -- 1/6, 3/6, 5/6 through cycle
        local d = t - peakAt
        if d > 0.5 then d = d - 1 elseif d < -0.5 then d = d + 1 end
        local lift = bounceHeight * math.exp(-(d * d) / (2 * sigma * sigma))
        state.canv[3 + i].center = {
          x = dotRight - (2 - i) * dotGap,
          y = dotY - lift,
        }
      end
    end)
  else
    local c = kind == "error" and C.error or C.muted
    for i = 0, 2 do
      state.canv[3 + i].fillColor = c
      state.canv[3 + i].center = { x = dotRight - (2 - i) * dotGap, y = dotY }
    end
  end
end

local function rebuildCursor()
  if not state.canv then return end
  local x = 12
  if state.buffer ~= "" then
    local sz = state.canv:minimumTextSize(2, state.buffer)
    if sz and sz.w then x = 12 + sz.w end
  end
  local cursorH = cfg.inputHeight - 16
  local cursorY = (cfg.inputHeight - cursorH) / 2
  local visible = state.cursorOn and not (state.task and state.task:isRunning())
  state.canv[7].frame = { x = x, y = cursorY, w = 1.5, h = cursorH }
  state.canv[7].fillColor = { white = 1, alpha = visible and 1.0 or 0 }
end

local function rebuildInput()
  if not state.canv then return end
  local placeholder
  if state.rewriteOf then
    local s = state.rewriteOf:gsub("%s+", " ")
    if #s > 60 then s = s:sub(1, 60) .. "…" end
    placeholder = "rewrite: " .. s
  else
    placeholder = "ask anything…"
  end
  local nowEmpty = (state.buffer == "")
  if nowEmpty then
    state.canv[2].text = placeholder
    state.canv[2].textColor = C.muted
  else
    state.canv[2].text = state.buffer
    state.canv[2].textColor = C.fg
  end
  rebuildCursor()
  -- Toggle the "Enter target" highlight on the latest reply when buffer
  -- emptiness flips (empty → Enter pastes; non-empty → Enter submits).
  if state.bufferWasEmpty ~= nowEmpty then
    state.bufferWasEmpty = nowEmpty
    if state.canv and state.canv[6] then rebuildResponse() end
  end
end

local function animateCanvasTo(targetH)
  if not state.canv then return end
  if state.sizeAnim then state.sizeAnim:stop(); state.sizeAnim = nil end
  local startF = state.canv:frame()
  local startH = startF.h
  if math.abs(startH - targetH) < 1 then return end
  local t0 = timer.secondsSinceEpoch()
  local duration = 0.18
  state.sizeAnim = timer.doEvery(0.016, function()
    if not state.canv then
      if state.sizeAnim then state.sizeAnim:stop(); state.sizeAnim = nil end
      return
    end
    local t = math.min((timer.secondsSinceEpoch() - t0) / duration, 1)
    local ease = 1 - (1 - t) * (1 - t) * (1 - t)
    state.canv:size({ w = cfg.overlayWidth, h = startH + (targetH - startH) * ease })
    if t >= 1 then state.sizeAnim:stop(); state.sizeAnim = nil end
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
    }
  end
  local userA   = mkAttrs("right")
  local aiA     = mkAttrs("left")
  -- "Enter target": when the buffer is empty, plain Enter commits the latest
  -- assistant reply. Highlight that reply in spinner blue so the user sees
  -- what will be pasted. Suppress when buffer has text (Enter then submits).
  local highlightLatest = (state.buffer == "")
  local aiLatest = mkAttrs("left", C.spinner)
  local latestAiIdx = nil
  if highlightLatest then
    for i = #state.history, (skipTurns or 0) + 1, -1 do
      if state.history[i].role == "assistant" then latestAiIdx = i; break end
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
  local maxH = cfg.responseHeight
  local frameW = cfg.overlayWidth - 24
  -- Iteratively drop oldest turns until the styled transcript fits the cap.
  local skip = 0
  local styled, measuredH
  while true do
    styled = buildTranscript(skip)
    if not styled then measuredH = 0; break end
    state.canv[6].frame = { x = 12, y = cfg.inputHeight + 4, w = frameW, h = maxH }
    state.canv[6].text = styled
    local sz = state.canv:minimumTextSize(6, styled)
    measuredH = (sz and sz.h) or 0
    if measuredH <= maxH then break end
    if skip + 2 > #state.history then break end  -- can't drop pending turn
    skip = skip + 2
  end
  if not styled then state.canv[6].text = "" end
  local contentH = math.min(math.ceil(measuredH) + 4, maxH)
  if measuredH <= 0 then contentH = 0 end
  state.canv[6].frame = { x = 12, y = cfg.inputHeight + 4, w = frameW, h = contentH }
  local targetCanvasH = cfg.inputHeight + (contentH > 0 and 6 + contentH or 0)
  animateCanvasTo(targetCanvasH)
end

local rebuildPendingTimer = nil
local rebuildLastAt = 0
local function rebuildResponseThrottled()
  local now = timer.secondsSinceEpoch()
  if now - rebuildLastAt >= 0.1 then
    if rebuildPendingTimer then rebuildPendingTimer:stop(); rebuildPendingTimer = nil end
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

local function newOverlay(x, y)
  local c = canvas.new({ x = x, y = y, w = cfg.overlayWidth, h = cfg.inputHeight })
  c[1] = {
    type = "rectangle", action = "fill", fillColor = C.bg,
    roundedRectRadii = { xRadius = 7, yRadius = 7 },
  }
  c[2] = {
    type = "text", text = "",
    textFont = cfg.font, textSize = cfg.fontSize, textColor = C.muted,
    frame = { x = 12, y = 6, w = cfg.overlayWidth - 60, h = cfg.inputHeight - 10 },
  }
  -- Three-dots "typing" indicator. Indices 3-5 are the dots (right-aligned).
  -- See setStatus() for the staggered fade animation.
  local dotR     = 2.5
  local dotGap   = 7
  local dotRight = cfg.overlayWidth - 12
  local dotY     = cfg.inputHeight / 2
  for i = 0, 2 do
    c[3 + i] = {
      type = "circle", action = "fill", fillColor = C.muted,
      center = { x = dotRight - (2 - i) * dotGap, y = dotY },
      radius = dotR,
    }
  end
  c[6] = {
    type = "text", text = "",
    textFont = cfg.font, textSize = cfg.fontSize, textColor = C.fg,
    frame = { x = 12, y = cfg.inputHeight + 4, w = cfg.overlayWidth - 24, h = 0 },
  }
  -- Text cursor: a thin rectangle drawn separately from the text element so
  -- blinking it on/off can't shift the placeholder layout.
  c[7] = {
    type = "rectangle", action = "fill", fillColor = { white = 1, alpha = 0 },
    frame = { x = 12, y = 8, w = 1.5, h = cfg.inputHeight - 16 },
  }
  c:level(canvas.windowLevels.overlay)
  c:behaviorAsLabels({ "canJoinAllSpaces", "stationary" })
  c:show()
  return c
end

----------------------------------------------------------------------
-- Input eventtap (active only while overlay is open)
----------------------------------------------------------------------

local function onCommitKey(mode)
  if state.task and state.task:isRunning() then
    state.queuedCommit = mode
  elseif state.response ~= "" then
    commitResponse(mode)
  else
    state.queuedCommit = mode
    submitPrompt()
  end
end

local function onInputKey(event)
  if not state.open then return false end
  local code  = event:getKeyCode()
  local flags = event:getFlags()
  local key   = keymap[code]
  local chars = event:getCharacters(true) or ""

  local cmdOnly = flags.cmd and not flags.alt and not flags.ctrl and not flags.shift

  if cmdOnly then
    if key == "return" then onCommitKey("replace"); return true end
    if key == "down"   then onCommitKey("append");  return true end
    if key == "c"      then onCommitKey("copy");    return true end
  end

  if key == "escape" then close(); return true end

  if key == "return" and not (flags.cmd or flags.alt or flags.ctrl) then
    if state.task and state.task:isRunning() then return true end
    if state.buffer ~= "" then
      submitPrompt()
    else
      -- Empty buffer + Enter → paste-commit the latest reply, like ⌘↵.
      commitResponse("replace")
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
  opts = opts or {}
  local x, y = anchorPoint()

  state.open         = true
  state.buffer       = ""
  state.response     = ""
  state.lastPrompt   = nil
  state.rewriteOf    = opts.selection
  state.queuedCommit = nil
  if not opts.continued then
    state.history = {}
    state.sessionId = nil
  end

  state.canv = newOverlay(x, y)
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
    local insideX = p.x >= f.x and p.x <= f.x + f.w
    local insideY = p.y >= f.y and p.y <= f.y + f.h
    if not (insideX and insideY) then
      close()
    elseif (p.y - f.y) > cfg.inputHeight then
      -- Click in response area → preload input with the latest assistant reply.
      -- (v1: per-turn hit-testing not implemented; always uses the latest.)
      for i = #state.history, 1, -1 do
        if state.history[i].role == "assistant" then
          state.buffer = state.history[i].content
          rebuildInput()
          break
        end
      end
    end
    return false
  end):start()
end

close = function()
  if not state.open then return end
  state.open = false
  if state.statusTimer then state.statusTimer:stop(); state.statusTimer = nil end
  if state.cursorTimer then state.cursorTimer:stop(); state.cursorTimer = nil end
  if state.sizeAnim then state.sizeAnim:stop(); state.sizeAnim = nil end
  if rebuildPendingTimer then rebuildPendingTimer:stop(); rebuildPendingTimer = nil end
  if state.inputTap then state.inputTap:stop(); state.inputTap = nil end
  if state.dismissTap then state.dismissTap:stop(); state.dismissTap = nil end
  if state.task and state.task:isRunning() then pcall(function() state.task:terminate() end) end
  state.task = nil
  if state.canv then state.canv:delete(); state.canv = nil end
  state.lastClose = timer.secondsSinceEpoch()
end

commitResponse = function(mode)
  -- In chat mode state.response is "" between turns; fall back to the most
  -- recent assistant message in history so Enter/⌘↵/⌘C still commit cleanly.
  local out = state.response
  if (not out or out == "") then
    for i = #state.history, 1, -1 do
      if state.history[i].role == "assistant" then
        out = state.history[i].content
        break
      end
    end
  end
  if not out or out == "" then close(); return end
  if mode == "copy" then
    pb.setContents(out)
    close()
    alert.show("Muse: copied", 0.6)
    return
  end
  close()
  timer.doAfter(0.04, function() pasteText(out, mode == "append") end)
end

submitPrompt = function()
  local userText = state.buffer
  local finalPrompt
  if state.rewriteOf and userText == "" then
    finalPrompt = "Rewrite the following text. Reply with only the rewritten text, no preamble:\n\n" .. state.rewriteOf
  elseif state.rewriteOf then
    finalPrompt = userText .. "\n\nApply the above to the following text. Reply with only the result, no preamble:\n\n" .. state.rewriteOf
  else
    finalPrompt = userText
  end
  if not finalPrompt or finalPrompt == "" then return end

  local backend = chooseBackend()
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
    local q = state.queuedCommit
    state.queuedCommit = nil
    if q then
      commitResponse(q)
      return
    end
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

  state.task = backend:stream(finalPrompt, state.history, onChunk, onDone, onError)
end

----------------------------------------------------------------------
-- Trigger eventtap: double-tap right ⌘, ⌥ tap on selection
----------------------------------------------------------------------

local rightCmdMask = eventtap.event.rawFlagMasks.deviceRightCommand

local function onFlags(event)
  local code  = event:getKeyCode()
  local flags = event:getFlags()
  local now   = timer.secondsSinceEpoch()

  if code == cfg.rightCmdCode then
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

  if cfg.rewriteOnAlt then
    local altOnly = flags.alt and not flags.cmd and not flags.ctrl and not flags.shift
    if altOnly and not state.altDownAt then
      state.altDownAt = now
      state.altClean = true
    elseif (not flags.alt) and state.altDownAt then
      local held = (now - state.altDownAt) * 1000
      local clean = state.altClean
      state.altDownAt = nil
      state.altClean = false
      if clean and held <= cfg.altTapMs and not state.open then
        local sel = readSelectionIfTyping()
        if sel and sel ~= "" then
          timer.doAfter(0.05, function() open({ selection = sel }) end)
        end
      end
    elseif flags.alt and (flags.cmd or flags.ctrl or flags.shift) then
      state.altClean = false
    end
  end

  return false
end

local function onAnyKey()
  -- If a key is pressed while alt is held, it's a chord, not a tap.
  if state.altDownAt then state.altClean = false end
  return false
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function Muse:start()
  if self._tap then return end
  self._tap     = eventtap.new({ etypes.flagsChanged }, onFlags):start()
  self._chordTap = eventtap.new({ etypes.keyDown }, onAnyKey):start()
end

function Muse:stop()
  if self._tap then self._tap:stop(); self._tap = nil end
  if self._chordTap then self._chordTap:stop(); self._chordTap = nil end
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
