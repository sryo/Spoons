-- Sssssssscroll bindings — sound name → action table.
--
-- Contract:
--   * Handlers run on the Hammerspoon main thread (same thread as the
--     hs.task stream callback that dispatched the event). Do not block.
--   * Handlers receive no arguments.
--   * Sustained sounds use { start = fn, stop = fn } — start fires once on
--     onset, stop fires once on offset.
--   * Transient sounds use { trigger = fn } — fires once per detection.
--   * Detector enforces mutual exclusion between sustained sounds and
--     suppresses transients while any sustained is active, so handlers
--     don't need to coordinate.

local timer    = hs.timer
local eventtap = hs.eventtap
local mouse    = hs.mouse

local M = {}

----------------------------------------------------------------------
-- hiss → continuous scroll down
----------------------------------------------------------------------

local hissTimer = nil

M.hiss = {
  start = function()
    if hissTimer then hissTimer:stop() end
    hissTimer = timer.doEvery(0.02, function()
      eventtap.scrollWheel({ 0, -20 }, {}, "pixel")
    end)
  end,
  stop = function()
    if hissTimer then hissTimer:stop(); hissTimer = nil end
  end,
}

----------------------------------------------------------------------
-- shhh → continuous scroll up (mirror of hiss)
----------------------------------------------------------------------

local shhhTimer = nil

M.shhh = {
  start = function()
    if shhhTimer then shhhTimer:stop() end
    shhhTimer = timer.doEvery(0.02, function()
      eventtap.scrollWheel({ 0, 20 }, {}, "pixel")
    end)
  end,
  stop = function()
    if shhhTimer then shhhTimer:stop(); shhhTimer = nil end
  end,
}

----------------------------------------------------------------------
-- pop → left click at cursor
----------------------------------------------------------------------

M.pop = {
  trigger = function()
    eventtap.leftClick(mouse.absolutePosition())
  end,
}

----------------------------------------------------------------------
-- tongue_click → right click at cursor
----------------------------------------------------------------------

M.tongue_click = {
  trigger = function()
    eventtap.rightClick(mouse.absolutePosition())
  end,
}

----------------------------------------------------------------------
-- mmm → hold spacebar (press on start, release on stop)
----------------------------------------------------------------------

M.mmm = {
  start = function()
    eventtap.event.newKeyEvent("space", true):post()
  end,
  stop = function()
    eventtap.event.newKeyEvent("space", false):post()
  end,
}

return M
