-- WindowScape configuration

local cfg = {
    outlineColor          = { red = .1, green = .3, blue = .9, alpha = 0.8 },
    outlineColorPinned    = { red = .9, green = .6, blue = .1, alpha = 0.8 },
    outlineThickness      = 16,  -- active window border thickness
    tileGap               = 0,   -- pixels between tiled windows
    collapsedWindowHeight = 12,  -- windows this height or less stack at bottom
    mods                  = { "ctrl", "cmd" },          -- window operation hotkeys
    screenMods            = { "ctrl", "cmd", "option" }, -- move window between screens
    -- true = apps in list are EXCLUDED from tiling (deny list)
    -- false = apps in list are INCLUDED for tiling (allow list)
    exclusionMode         = true,
    eventDebounceSeconds  = 0.2, -- debounce for bursty window events
    enableAnimations      = true,
    animationDuration     = 0.15, -- seconds
    animationFPS          = 60,
    showPinButton         = false, -- pin button (right of traffic lights) toggles app in/out of tiling
    debugLogging          = false, -- verbose tier; toggle with Ctrl+Cmd+D
}

local CONST = {
    ANIMATION_STEPS          = 12,     -- frames per snapshot animation
    ANIMATION_INTERVAL       = 0.016,  -- seconds between animation frames
    OUTLINE_REFRESH_INTERVAL = 0.016,  -- seconds between outline position updates
    SNAPSHOT_ZOOM_SCALE      = 1.1,    -- hover zoom multiplier for thumbnails
    SNAPSHOT_DRAG_THRESHOLD  = 5,      -- pixels before thumbnail drag starts
    SNAPSHOT_CLOSE_SIZE      = 20,     -- close button hit area in pixels
}

return { cfg = cfg, CONST = CONST }
