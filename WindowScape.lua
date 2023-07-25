-- WindowScape: https://github.com/sryo/Spoons/blob/main/WindowScape.lua
-- This script automatically tiles windows of whitelisted applications.

local application = require("hs.application")
local window = require("hs.window")
local screen = require("hs.screen")
local geometry = require("hs.geometry")
local logger = hs.logger.new("windowTiler", "debug")

local tileGap = 0
local collapsedWindowHeight = 12
local whitelistMode = false -- Set to true to tile only the windows in the whitelist

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
  else
    whitelistedApps["org.hammerspoon.Hammerspoon"] = true
    saveWhitelistToFile()
  end
end

loadWhitelistFromFile()

local function isAppWhitelisted(app, win)
  if app == nil then
    return false
  end

  local bundleID = app and app:bundleID()
  local appName = app:name()
  local isInWhitelist = whitelistedApps[bundleID] or whitelistedApps[appName]

  local shouldConsiderApp = win:isStandard() and ((whitelistMode and isInWhitelist) or (not whitelistMode and not isInWhitelist))

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
  for _, win in ipairs(window.orderedWindows()) do
    if win:isVisible() and not win:isFullScreen() and isAppWhitelisted(win:application(), win) then
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

    win:setFrame(newFrame)
  end
end

local function handleWindowCreated(win)
  if not win:isFullScreen() and isAppWhitelisted(win:application(), win) then
    tileWindows()
  end
end

local function handleWindowFocused(win)
  if not win:isFullScreen() and isAppWhitelisted(win:application(), win) then
    local focusedApp = win:application()
    focusedApp:activate(true)
    tileWindows()
  end
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

tileWindows()

local function toggleFocusedWindowInWhitelist()
  local focusedWindow = window.focusedWindow()
  if focusedWindow:isFullScreen() then
    return
  end

  local focusedApp = focusedWindow:application()
  local bundleID = focusedApp:bundleID()
  local appName = focusedApp:name()

  if whitelistedApps[bundleID] or whitelistedApps[appName] then
    whitelistedApps[bundleID] = nil
    whitelistedApps[appName] = nil
  else
    whitelistedApps[bundleID] = true
  end

  saveWhitelistToFile()
  tileWindows()
end

local function bindHotkeys()
  hs.hotkey.bind({"cmd"}, "<", function()
    toggleFocusedWindowInWhitelist()
  end)
end

bindHotkeys()
