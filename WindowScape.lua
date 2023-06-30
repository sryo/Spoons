-- This script automatically tiles windows of whitelisted applications.

local application = require("hs.application")
local window = require("hs.window")
local screen = require("hs.screen")
local geometry = require("hs.geometry")
local logger = hs.logger.new("windowTiler", "debug")

local tileGap = 0
local collapsedWindowHeight = 12
local whitelistMode = false -- Set to true to tile only the windows in the whitelist

-- Initialize whitelistedApps as an empty table
local whitelistedApps = {}

local function saveWhitelistToFile()
  local whitelistFile = io.open("whitelist.txt", "w")
  for app, _ in pairs(whitelistedApps) do
    whitelistFile:write(app .. "\n")
  end
  whitelistFile:close()
  print("Whitelist saved to file")
end

local function loadWhitelistFromFile()
  local whitelistFile = io.open("whitelist.txt", "r")
  if whitelistFile then
    for line in whitelistFile:lines() do
      whitelistedApps[line] = true
    end
    whitelistFile:close()
    print("Whitelist loaded from file")
  else
    whitelistedApps["org.hammerspoon.Hammerspoon"] = true
    saveWhitelistToFile()
    print("Whitelist file created with example")
  end
end

loadWhitelistFromFile()

local function isAppWhitelisted(app, win)
  if app == nil then
    print("Application for the window is nil")
    return false
  end

  local bundleID = app and app:bundleID()
  local appName = app:name()
  local isInWhitelist = whitelistedApps[bundleID] or whitelistedApps[appName]
  
  local shouldConsiderApp = win:isStandard() and ((whitelistMode and isInWhitelist) or (not whitelistMode and not isInWhitelist))

  local emoji = shouldConsiderApp and "🫡" or "🫥"
  print(string.format("%s Checking app: %s (%s), Considered: %s", emoji, appName, bundleID, tostring(shouldConsiderApp)))

  if not shouldConsiderApp then
    print("Application " .. appName .. " (" .. bundleID .. ") is not considered")
  end
  
  return shouldConsiderApp
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
    if win:isVisible() and isAppWhitelisted(win:application(), win) then
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
  if win and win:application() then
    local frame = win:frame()
    local windowTitle = win:title() or "No title"
    logger.i(
      string.format(
        "%s %s %s (%d): x=%d, y=%d, w=%d, h=%d",
        actionEmoji,
        win:application():bundleID(),
        windowTitle,
        win:id(),
        frame.x,
        frame.y,
        frame.w,
        frame.h
      )
    )
  end
end

local function printVisibleWindowsInfo()
  local visibleWindows = getVisibleWindows()
  logger.i("Visible windows:")
  for _, win in ipairs(visibleWindows) do
    local frame = win:frame()
    logger.i(
      string.format(
        "🪟  %s (%d): x=%d, y=%d, w=%d, h=%d",
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
    tileWidth = (mainScreenFrame.w - (nonCollapsedWindows) * tileGap) / (nonCollapsedWindows)
    tileHeight = mainScreenFrame.h - (#collapsedWindows > 0 and collapsedWindowHeight + tileGap or 0)
  else
    tileWidth = mainScreenFrame.w
    tileHeight = (mainScreenFrame.h - (#collapsedWindows > 0 and (#collapsedWindows * (collapsedWindowHeight + tileGap) - tileGap) or 0) - (nonCollapsedWindows) * tileGap) / nonCollapsedWindows
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
  if isAppWhitelisted(win:application(), win) then
    logWindowGeometryChange(win, "🆕")
    tileWindows()
  end
end

local prevFocusedWindow = nil

local function handleWindowFocused(win)
  if prevFocusedWindow and prevFocusedWindow:isStandard() and isAppWhitelisted(prevFocusedWindow:application(), prevFocusedWindow) then
    logWindowGeometryChange(prevFocusedWindow, "🙈")
  end
  if isAppWhitelisted(win:application(), win) then
    logWindowGeometryChange(win, "👁️")
    local focusedApp = win:application()
    focusedApp:activate(true)
  end
  tileWindows()
  prevFocusedWindow = win
end

window.filter.default:subscribe(window.filter.windowCreated, handleWindowCreated)
window.filter.default:subscribe(window.filter.windowFocused, handleWindowFocused)
window.filter.default:subscribe(window.filter.windowDestroyed, tileWindows)
window.filter.default:subscribe(window.filter.windowHidden, tileWindows)
window.filter.default:subscribe(window.filter.windowUnhidden, tileWindows)
window.filter.default:subscribe(window.filter.windowMinimized, tileWindows)
window.filter.default:subscribe(window.filter.windowUnminimized, tileWindows)
window.filter.default:subscribe(window.filter.windowMoved, tileWindows)

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

  saveWhitelistToFile()
  tileWindows()
end

local function toggleWhitelistMode()
  whitelistMode = not whitelistMode
  print("Toggled mode to", whitelistMode and "whitelist" or "blacklist")
  tileWindows()
end

local function bindHotkeys()
  hs.hotkey.bind({"cmd"}, "<", function()
    toggleFocusedWindowInWhitelist()
  end)
end

bindHotkeys()
