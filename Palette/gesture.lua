-- 5-finger trackpad tap → open the Palette. wasOpened guards against re-fire
-- while fingers are still down.

local eventtap = hs.eventtap
local etypes   = eventtap.event.types

local M = {}

local cfg
local Palette
local touchState = { wasOpened = false }
local tap

local function onGesture(event)
    if not cfg or not Palette then return false end
    local n = cfg.numberOfFingersToOpen or 0
    if n <= 0 then return false end
    local touches = event:getTouches()
    if not touches then return false end

    if #touches == n and not touchState.wasOpened and not Palette.isOpen() then
        for _, t in ipairs(touches) do
            if t.phase == "ended" then
                touchState.wasOpened = true
                Palette.open()
                return false
            end
        end
    elseif #touches > n then
        touchState.wasOpened = true
    elseif #touches < n then
        touchState.wasOpened = false
    end
    return false
end

function M.start(config, paletteModule)
    cfg     = config
    Palette = paletteModule
    if tap then tap:stop() end
    tap = eventtap.new({ etypes.gesture }, onGesture)
    tap:start()
    -- Retain on _G so reload doesn't strand the previous instance.
    _G.paletteGestureTap = tap
end

function M.stop()
    if tap then tap:stop(); tap = nil end
    _G.paletteGestureTap = nil
end

return M
