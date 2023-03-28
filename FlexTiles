local whitelist = {
  "Finder",
  "TextEdit",
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

  for i, window in ipairs(windowsToTile) do
    local newFrame = mainScreenFrame:copy()

    if isHorizontal then
      newFrame.w = mainScreenFrame.w / numWindows
      newFrame.x = mainScreenFrame.x + (i - 1) * newFrame.w
    else
      newFrame.h = mainScreenFrame.h / numWindows
      newFrame.y = mainScreenFrame.y + (i - 1) * newFrame.h
    end

    window:setFrame(newFrame)
  end
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
