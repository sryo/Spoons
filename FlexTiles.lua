-- This script automatically tiles windows of whitelisted applications.

local application = require("hs.application")
local window = require("hs.window")
local screen = require("hs.screen")
local geometry = require("hs.geometry")
local logger = hs.logger.new("windowTiler", "debug")

local tileGap = 8
local collapsedWindowHeight = 12

local whitelistedApps = {
    ["com.apple.finder"] = true,
    ["com.apple.Stickies"] = true,
    ["com.apple.Terminal"] = true,
    -- Add more apps here if needed
}

local function isAppWhitelisted(app)
  local bundleID = app:bundleID()
  local appName = app:name()
  local isInWhitelist = whitelistedApps[bundleID] or whitelistedApps[appName]
  print(string.format("Checking app: %s (%s), Whitelisted: %s", appName, bundleID, tostring(isInWhitelist)))
  return isInWhitelist
end

local function getScreenOrientation()
  local mainScreen = screen.mainScreen()
  local mainScreenSize = mainScreen:frame().size

  if mainScreenSize.w > mainScreenSize.h then
    return "horizontal"
  else
    return "vertical"
  end
end

local function getVisibleWindows()
  local visibleWindows = {}
  local focusedWindow = window.focusedWindow()
  for _, win in ipairs(window.orderedWindows()) do
    if win:isVisible() and isAppWhitelisted(win:application()) then
      table.insert(visibleWindows, win)
    end
  end
  -- Sort visible windows based on their window ID
  table.sort(visibleWindows, function(a, b) return a:id() < b:id() end)
  return visibleWindows
end

local function getCollapsedWindows(visibleWindows)
  local collapsedWindows = {}
  for _, win in ipairs(visibleWindows) do
    if win:size().h <= collapsedWindowHeight then
      table.insert(collapsedWindows, win)
    end
  end
  return collapsedWindows
end

local function logWindowGeometryChange(win, actionEmoji)
  local frame = win:frame()
  logger.i(
    string.format(
      "%s %s (%d): x=%d, y=%d, w=%d, h=%d",
      actionEmoji,
      win:application():bundleID(),
      win:id(),
      frame.x,
      frame.y,
      frame.w,
      frame.h
    )
  )
end

local function printVisibleWindowsInfo()
  local visibleWindows = getVisibleWindows()
  logger.i("Visible windows:")
  for _, win in ipairs(visibleWindows) do
    local frame = win:frame()
    logger.i(
      string.format(
        "  %s (%d): x=%d, y=%d, w=%d, h=%d",
        win:application():bundleID(),
        win:id(),
        frame.x,
        frame.y,
        frame.w,
        frame.h
      )
    )
  end
end

local function tileWindows()
  local orientation = getScreenOrientation()
  local visibleWindows = getVisibleWindows()
  local collapsedWindows = getCollapsedWindows(visibleWindows)
  local nonCollapsedWindows = #visibleWindows - #collapsedWindows

  local mainScreen = screen.mainScreen()
  local mainScreenFrame = mainScreen:frame()
  local tileWidth, tileHeight

  if orientation == "horizontal" then
    tileWidth = (mainScreenFrame.w - (nonCollapsedWindows - 1) * tileGap) / (nonCollapsedWindows + 1)
    tileHeight = mainScreenFrame.h - (#collapsedWindows > 0 and collapsedWindowHeight + tileGap or 0)
  else
    tileWidth = mainScreenFrame.w
    tileHeight = (mainScreenFrame.h - (nonCollapsedWindows - 1) * tileGap) / (nonCollapsedWindows + 1)
  end

  print("Orientation:", orientation, "Tile width:", tileWidth, "Tile height:", tileHeight)

  local nonCollapsedWinX, nonCollapsedWinY = mainScreenFrame.x, mainScreenFrame.y
  local collapsedWinX, collapsedWinY
  if orientation == "horizontal" then
    collapsedWinX, collapsedWinY = mainScreenFrame.x, mainScreenFrame.y + mainScreenFrame.h - collapsedWindowHeight
  else
    collapsedWinX, collapsedWinY = mainScreenFrame.x, mainScreenFrame.y + mainScreenFrame.h - collapsedWindowHeight - tileGap
  end

  local initialCollapsedWidth = collapsedWindows[1] and collapsedWindows[1]:frame().w or tileWidth

  for _, win in ipairs(visibleWindows) do
    local winHeight = win:size().h
    local isCollapsed = winHeight <= collapsedWindowHeight
    local newFrame = geometry.rect(nonCollapsedWinX, nonCollapsedWinY, tileWidth, tileHeight)

    if isCollapsed then
      if orientation == "horizontal" then
        newFrame = geometry.rect(collapsedWinX, collapsedWinY, initialCollapsedWidth, collapsedWindowHeight)
        collapsedWinX = collapsedWinX + initialCollapsedWidth + tileGap
      else
        newFrame = geometry.rect(collapsedWinX, collapsedWinY, tileWidth, collapsedWindowHeight)
        collapsedWinY = collapsedWinY - collapsedWindowHeight - tileGap
      end

    else
      if orientation == "horizontal" then
        nonCollapsedWinX = nonCollapsedWinX + tileWidth + tileGap
      else
        nonCollapsedWinY = nonCollapsedWinY + tileHeight + tileGap
      end
    end

    print("Setting frame for", win:application():bundleID(), win:id(), "to", newFrame)
    win:setFrame(newFrame)
    logWindowGeometryChange(win, "📐")
  end
end

local function handleWindowCreated(win)
  if isAppWhitelisted(win:application()) then
    logWindowGeometryChange(win, "🆕")
    tileWindows()
  end
end

local function handleWindowFocused(win)
  if isAppWhitelisted(win:application()) then
    logWindowGeometryChange(win, "👀")

    local focusedApp = win:application()
    focusedApp:activate(true)

    tileWindows()
  end
end

local function handleWindowDestroyed(win)
  if isAppWhitelisted(win:application()) then
    logWindowGeometryChange(win, "🗑")
    tileWindows()
  end
end

window.filter.default:subscribe(window.filter.windowCreated, handleWindowCreated)
window.filter.default:subscribe(window.filter.windowFocused, handleWindowFocused)
window.filter.default:subscribe(window.filter.windowDestroyed, handleWindowDestroyed)

printVisibleWindowsInfo()
tileWindows()

local function toggleFocusedWindowInWhitelist()
  local focusedWindow = window.focusedWindow()
  local focusedApp = focusedWindow:application()
  local bundleID = focusedApp:bundleID()
  local appName = focusedApp:name()
  
  if whitelistedApps[bundleID] or whitelistedApps[appName] then
    whitelistedApps[bundleID] = nil
    whitelistedApps[appName] = nil
    print("Removed", appName, "from whitelist")
  else
    whitelistedApps[bundleID] = true
    print("Added", appName, "to whitelist")
  end

  tileWindows()
end


local function bindHotkeys()
  hs.hotkey.bind({"cmd", "shift"}, "A", function()
    toggleFocusedWindowInWhitelist()
  end)

  hs.hotkey.bind({"cmd", "shift"}, "R", function()
    toggleFocusedWindowInWhitelist()
  end)
end

bindHotkeys()
