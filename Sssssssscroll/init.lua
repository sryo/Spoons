-- Sssssssscroll: voice/mouth-sound input system.
--
-- Spawns a Python detector via hs.task that listens to the mic and emits
-- one event per line on stdout (`start hiss`, `stop hiss`, `trigger pop`).
-- Each event is dispatched to a handler in bindings.lua.
--
-- Hotkey: ⌃⌥⌘N toggles the detector.

local task   = hs.task
local fs     = hs.fs
local alert  = hs.alert
local hotkey = hs.hotkey

local Sssssssscroll = {}

Sssssssscroll.config = {
  python       = os.getenv("HOME") .. "/.hammerspoon/.venv/bin/python",
  detectorPath = os.getenv("HOME") .. "/.hammerspoon/Sssssssscroll/detector.py",
  debug        = true,  -- when true, print every dispatched event to console
}

local cfg = Sssssssscroll.config

----------------------------------------------------------------------
-- Module-level state. These MUST stay reachable from the module table
-- (or via these upvalues, since the module table itself is returned and
-- held by require's package.loaded). Hammerspoon hs.task instances and
-- canvases get GC'd silently if dropped — see project memory.
----------------------------------------------------------------------

local audioTask  = nil
local lineBuffer = ""
local bindings   = nil

----------------------------------------------------------------------
-- Bindings loader
----------------------------------------------------------------------

local function loadBindings()
  local path = os.getenv("HOME") .. "/.hammerspoon/Sssssssscroll/bindings.lua"
  local ok, result = pcall(dofile, path)
  if not ok then
    print("[Sssssssscroll] failed to load bindings: " .. tostring(result))
    return {}
  end
  if type(result) ~= "table" then
    print("[Sssssssscroll] bindings.lua must return a table")
    return {}
  end
  return result
end

----------------------------------------------------------------------
-- Event dispatch
----------------------------------------------------------------------

local function dispatch(line)
  local verb, sound = line:match("^(%S+)%s+(%S+)$")
  if not verb or not sound then
    if cfg.debug then print("[Sssssssscroll] bad event: " .. line) end
    return
  end

  if cfg.debug then print("[Sssssssscroll] " .. verb .. " " .. sound) end

  local entry = bindings and bindings[sound]
  if not entry then
    if cfg.debug then print("[Sssssssscroll] no binding for " .. sound) end
    return
  end
  local fn = entry[verb]
  if type(fn) ~= "function" then
    if cfg.debug then print("[Sssssssscroll] no " .. verb .. " handler for " .. sound) end
    return
  end
  local ok, err = pcall(fn)
  if not ok then
    print("[Sssssssscroll] handler error for " .. line .. ": " .. tostring(err))
  end
end

----------------------------------------------------------------------
-- hs.task callbacks
----------------------------------------------------------------------

local function streamCb(_task, stdOut, stdErr)
  if stdOut and #stdOut > 0 then
    lineBuffer = lineBuffer .. stdOut
    while true do
      local nl = lineBuffer:find("\n")
      if not nl then break end
      local line = lineBuffer:sub(1, nl - 1)
      lineBuffer = lineBuffer:sub(nl + 1)
      -- strip trailing CR if any
      if line:sub(-1) == "\r" then line = line:sub(1, -2) end
      if #line > 0 then dispatch(line) end
    end
  end
  if stdErr and #stdErr > 0 then
    print("[Sssssssscroll] " .. stdErr)
  end
  return true
end

local function completionCb(exitCode, _stdOut, _stdErr)
  print("[Sssssssscroll] detector exited (code " .. tostring(exitCode) .. ")")
  alert.show("Sssssssscroll: detector stopped")
  audioTask = nil
  lineBuffer = ""
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function Sssssssscroll:start()
  if audioTask and audioTask:isRunning() then
    if cfg.debug then print("[Sssssssscroll] already running") end
    return
  end

  if not fs.attributes(cfg.python) then
    alert.show("Sssssssscroll: python not found\n" .. cfg.python)
    return
  end
  if not fs.attributes(cfg.detectorPath) then
    alert.show("Sssssssscroll: detector.py missing")
    return
  end

  bindings   = loadBindings()
  lineBuffer = ""

  -- hs.task.new(launchPath, completionFn, streamCallbackFn, arguments).
  -- The `-u` flag is mandatory: without it, Python block-buffers stdout
  -- and events arrive in multi-second bursts.
  audioTask = task.new(cfg.python, completionCb, streamCb,
    { "-u", cfg.detectorPath })
  audioTask:start()
  alert.show("Sssssssscroll: listening")
end

function Sssssssscroll:stop()
  -- Stop any active sustained handlers (best-effort) so timers don't leak.
  if bindings then
    for _, entry in pairs(bindings) do
      if type(entry.stop) == "function" then pcall(entry.stop) end
    end
  end
  if audioTask then
    pcall(function() audioTask:terminate() end)
    audioTask = nil
  end
  lineBuffer = ""
  alert.show("Sssssssscroll: stopped")
end

function Sssssssscroll:toggle()
  if audioTask and audioTask:isRunning() then
    self:stop()
  else
    self:start()
  end
end

----------------------------------------------------------------------
-- Hotkey: ⌃⌥⌘N
----------------------------------------------------------------------

Sssssssscroll._hotkey = hotkey.bind({ "ctrl", "alt", "cmd" }, "N", function()
  Sssssssscroll:toggle()
end)

return Sssssssscroll
