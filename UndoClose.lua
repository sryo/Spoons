-- UndoClose.lua: Reopen recently closed applications

local UndoClose = {}
local log = hs.logger.new('UndoClose', 'info')

UndoClose.config = {
    hotkey = { { "cmd", "option" }, "z" },
    timeout = 5,
}

local activationKey = nil
local timeoutTimer = nil
local currentAlert = nil
local finderPaths = {}

local function styleText(text, attributes)
    return hs.styledtext.new(text, attributes)
end

local function cleanup()
    if activationKey then
        activationKey:delete(); activationKey = nil
    end
    if timeoutTimer then
        timeoutTimer:stop(); timeoutTimer = nil
    end
    if currentAlert then
        hs.alert.closeSpecific(currentAlert); currentAlert = nil
    end
end

local function startUndoWatcher(label, callback)
    cleanup()
    local timeLeft = UndoClose.config.timeout

    local function showCountdown()
        if currentAlert then hs.alert.closeSpecific(currentAlert) end

        local baseStyle  = { font = { name = ".AppleSystemUIFont", size = 14 }, color = { white = 0.8 } }
        local boldStyle  = { font = { name = ".AppleSystemUIFont", size = 18 }, color = { white = 1.0 } }
        local dimStyle   = { font = { name = ".AppleSystemUIFont", size = 14 }, color = { white = 0.8 } }

        local message    = styleText("Undo close ", baseStyle)
            .. styleText(label, boldStyle)
            .. styleText("  ⌘⌥Z  ", boldStyle)
            .. styleText(tostring(timeLeft) .. "s", dimStyle)

        local alertStyle = {
            strokeColor = { white = 0, alpha = 0 },
            fillColor   = { white = 0, alpha = 0.75 },
            radius      = 10,
            padding     = 12,
        }

        currentAlert     = hs.alert.show(message, alertStyle, 1.1)
    end

    showCountdown()

    activationKey = hs.hotkey.bind(UndoClose.config.hotkey[1], UndoClose.config.hotkey[2], function()
        callback()
        cleanup()
    end)

    timeoutTimer = hs.timer.doEvery(1, function()
        timeLeft = timeLeft - 1
        if timeLeft > 0 then showCountdown() else cleanup() end
    end)
end

UndoClose.finderFilter = hs.window.filter.new('Finder')

local function getCurrentFinderPath()
    local script = [[
        tell application "Finder"
            try
                return POSIX path of (target of front window as alias)
            on error
                return ""
            end try
        end tell
    ]]
    local ok, result = hs.osascript.applescript(script)
    if ok and result ~= "" then
        return result
    else
        return nil
    end
end

local function updatePath(win)
    if not win then return end

    hs.timer.doAfter(0.2, function()
        if hs.window.focusedWindow() and hs.window.focusedWindow():id() == win:id() then
            local path = getCurrentFinderPath()
            if path then
                log.i("Captured Path: " .. path)
                finderPaths[win:id()] = path
            else
                log.w("Could not get path (Might be 'Recents' or 'AirDrop')")
            end
        end
    end)
end

UndoClose.finderFilter:subscribe(hs.window.filter.windowFocused, updatePath)
UndoClose.finderFilter:subscribe(hs.window.filter.windowTitleChanged, updatePath)

UndoClose.finderFilter:subscribe(hs.window.filter.windowDestroyed, function(win)
    local id = win:id()
    local path = finderPaths[id]

    if path then
        finderPaths[id] = nil
        local folderName = string.match(path, "([^/]+)/?$") or "Folder"

        startUndoWatcher("Finder: " .. folderName, function()
            hs.open(path)
        end)
    else
        log.w("Finder window closed, but no path was saved.")
    end
end)

local function scanOpenWindows()
    local finder = hs.appfinder.appFromName("Finder")
    if finder then
        local win = finder:focusedWindow()
        if win then updatePath(win) end
    end
end
scanOpenWindows()

UndoClose.appWatcher = hs.application.watcher.new(function(appName, event, app)
    if event == hs.application.watcher.terminated then
        if app and app:bundleID() then
            startUndoWatcher(appName, function()
                hs.application.launchOrFocusByBundleID(app:bundleID())
            end)
        end
    end
end)

UndoClose.appWatcher:start()

return UndoClose
