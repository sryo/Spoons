local whitelist = {
  "Finder",
  "Notas Adhesivas",
  -- Add more app names to the whitelist here
}

function isAppInWhitelist(appName)
  for _, whitelistedAppName in ipairs(whitelist) do
      if appName == whitelistedAppName then
          return true
      end
  end
  return false
end

function tileWindows()
  local mainScreen = hs.screen.mainScreen()
  local mainScreenFrame = mainScreen:frame()

  -- Determine if the screen is horizontal or vertical
  local isHorizontal = mainScreenFrame.w > mainScreenFrame.h

  local apps = hs.application.runningApplications()
  local windowsToTile = {}

  for _, app in ipairs(apps) do
      if isAppInWhitelist(app:name()) then
          local windows = app:allWindows()
          for _, window in ipairs(windows) do
              if window:isVisible() and not window:isFullscreen() then
                  table.insert(windowsToTile, window)
              end
          end
      end
  end

  local numWindows = #windowsToTile
  if numWindows == 0 then return end

  local gap = 10 -- Set the gap size between windows

  for i, window in ipairs(windowsToTile) do
      local newFrame = mainScreenFrame:copy()

      if isHorizontal then
          newFrame.w = (mainScreenFrame.w - (numWindows - 1) * gap) / numWindows
          newFrame.x = mainScreenFrame.x + (i - 1) * (newFrame.w + gap)
      else
          newFrame.h = (mainScreenFrame.h - (numWindows - 1) * gap) / numWindows
          newFrame.y = mainScreenFrame.y + (i - 1) * (newFrame.h + gap)
      end

      window:setFrame(newFrame)
  end
end

local previousFocusedAppName = nil
local lastWindowRaiseTimestamps = {}

function raiseNonFocusedWindowsForNewApp(currentFocusedAppName, focusedWindow)
    if focusedWindow and isAppInWhitelist(focusedWindow:application():name()) then
        local currentTime = os.time()
        local lastRaiseTimestamp = lastWindowRaiseTimestamps[currentFocusedAppName] or 0
        if previousFocusedAppName ~= currentFocusedAppName or currentTime - lastRaiseTimestamp > 1 then
            local windowsFromSameApp = focusedWindow:application():allWindows()
            for _, otherWindow in ipairs(windowsFromSameApp) do
                if otherWindow:isVisible() and not otherWindow:isFullscreen() and otherWindow:id() ~= focusedWindow:id() then
                    otherWindow:raise()
                end
            end
            focusedWindow:focus() -- Focus on the selected window at the end
            lastWindowRaiseTimestamps[currentFocusedAppName] = currentTime
        end
    end
    previousFocusedAppName = currentFocusedAppName
end


-- Tile windows when the configuration is loaded
tileWindows()

-- Tile windows when a new window is added or removed
hs.window.filter.new()
    :setDefaultFilter{visible=true, fullscreen=false}
    :subscribe(hs.window.filter.windowCreated, function()
        tileWindows()
    end)
    :subscribe(hs.window.filter.windowDestroyed, function()
        tileWindows()
    end)
    :subscribe(hs.window.filter.windowFocused, function(window)
      local currentFocusedAppName = window:application():name()
      if isAppInWhitelist(currentFocusedAppName) then
          raiseNonFocusedWindowsForNewApp(currentFocusedAppName, window)
      end
  end)
