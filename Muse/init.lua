-- Muse: an inline AI companion. Double-tap right ⌘ to summon near the text caret.
--
-- Commit keys while overlay is open:
--   ⌘↵ paste-replace the field, ⌘↓ paste-append at caret, ⌘C copy, esc cancel.
-- ⌥ tapped alone over a selection → rewrite mode (pre-seeded with selection).
-- Double-tap right ⌘ within continueMs of last close → conversation continues.

local Muse = {}

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
        alert.show("Muse: failed to load " .. modname .. ": " .. tostring(result):sub(1, 80), 2)
      elseif type(result) == "table" and result.name and not Muse.backends[result.name] then
        Muse.register(result)
      end
    end
  end
end

local function reportBackendStatus()
  for name, b in pairs(Muse.backends) do
    local ok, why = b.available()
    if not ok then
      alert.show("Muse [" .. name .. "]: " .. (why or "unavailable"), 2)
    end
  end
end

local function chooseBackend()
  local primary = Muse.backends[cfg.backend]
  if primary then
    local ok, why = primary.available()
    if ok then return primary end
    alert.show("Muse: " .. cfg.backend .. " unavailable (" .. (why or "?") .. ")", 1.5)
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

local close, submitPrompt, commitResponse

local function setStatus(kind)
  if not state.canv then return end
  local c = C.muted
  if kind == "active" then c = C.accent end
  if kind == "error"  then c = C.error end
  state.canv[3].fillColor = c
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
  if state.buffer == "" then
    state.canv[2].text = placeholder
    state.canv[2].textColor = C.muted
  else
    state.canv[2].text = state.buffer
    state.canv[2].textColor = C.fg
  end
end

local function rebuildResponse()
  if not state.canv then return end
  state.canv[4].text = state.response
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
    frame = { x = 12, y = 6, w = cfg.overlayWidth - 40, h = cfg.inputHeight - 10 },
  }
  c[3] = {
    type = "circle", action = "fill", fillColor = C.muted,
    center = { x = cfg.overlayWidth - 14, y = cfg.inputHeight / 2 },
    radius = 3,
  }
  c[4] = {
    type = "text", text = "",
    textFont = cfg.font, textSize = cfg.fontSize, textColor = C.fg,
    frame = { x = 12, y = cfg.inputHeight + 4, w = cfg.overlayWidth - 24, h = 0 },
  }
  c:level(canvas.windowLevels.overlay)
  c:behaviorAsLabels({ "canJoinAllSpaces", "stationary" })
  c:show()
  return c
end

local function growForResponse()
  if not state.canv then return end
  state.canv:size({ w = cfg.overlayWidth, h = cfg.inputHeight + 6 + cfg.responseHeight })
  state.canv[4].frame = { x = 12, y = cfg.inputHeight + 4, w = cfg.overlayWidth - 24, h = cfg.responseHeight - 8 }
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
    if not (state.task and state.task:isRunning()) then submitPrompt() end
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
  state.rewriteOf    = opts.selection
  state.queuedCommit = nil
  if not opts.continued then state.history = {} end

  state.canv = newOverlay(x, y)
  rebuildInput()
  setStatus("idle")
  state.inputTap = eventtap.new({ etypes.keyDown }, onInputKey):start()
end

close = function()
  if not state.open then return end
  state.open = false
  if state.inputTap then state.inputTap:stop(); state.inputTap = nil end
  if state.task and state.task:isRunning() then pcall(function() state.task:terminate() end) end
  state.task = nil
  if state.canv then state.canv:delete(); state.canv = nil end
  state.lastClose = timer.secondsSinceEpoch()
end

commitResponse = function(mode)
  local out = state.response
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
    alert.show("Muse: no backend available", 1.5)
    close()
    return
  end

  state.response = ""
  growForResponse()
  rebuildResponse()
  setStatus("active")

  local function onChunk(text)
    state.response = state.response .. text
    rebuildResponse()
  end

  local function onDone()
    if not state.open then return end
    table.insert(state.history, { role = "user", content = finalPrompt })
    table.insert(state.history, { role = "assistant", content = state.response })
    setStatus("idle")
    local q = state.queuedCommit
    state.queuedCommit = nil
    if q then commitResponse(q) end
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

local function rightCmdDown()
  local m = eventtap.checkKeyboardModifiers(true)
  return m and m.rightCmd
end

local function onFlags(event)
  local code  = event:getKeyCode()
  local flags = event:getFlags()
  local now   = timer.secondsSinceEpoch()

  if code == cfg.rightCmdCode then
    local downNow = rightCmdDown()
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

return Muse
