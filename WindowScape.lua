-- WindowScape: https://github.com/sryo/Spoons/blob/main/WindowScape.lua
-- This script automatically tiles windows of whitelisted applications.

local window = require("hs.window")
local screen = require("hs.screen")
local geometry = require("hs.geometry")
local drawing = require("hs.drawing")

local activeWindowOutline = nil
local outlineColor = {red = .1, green = .3, blue = .9, alpha = 0.9}
local outlineThickness = 16

local tileGap = 0
local collapsedWindowHeight = 12
local whitelistMode = false -- Set to true to tile only the windows in the whitelist

local whitelistedApps = {}
local whitelistFile = "whitelist.txt"

local function saveWhitelistToFile()
  local file = io.open(whitelistFile, "w")
  for app in pairs(whitelistedApps) do
    file:write(app .. "\n")
  end
  file:close()
end

local function loadWhitelistFromFile()
  local file = io.open(whitelistFile, "r")
  if not file then
    whitelistedApps["org.hammerspoon.Hammerspoon"] = true
    saveWhitelistToFile()
    return
  end
  for line in file:lines() do
    whitelistedApps[line] = true
  end
  file:close()
end

loadWhitelistFromFile()

local function isAppWhitelisted(app, win)
  local bundleID = app and app:bundleID()
  local appName = app:name()
  local isInWhitelist = whitelistedApps[bundleID] or whitelistedApps[appName]

  return win:isStandard() and ((whitelistMode and isInWhitelist) or (not whitelistMode and not isInWhitelist))
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
  visibleWindows = hs.fnutils.filter(visibleWindows, function(win)
    return not win:isFullScreen()
  end)
  local collapsedWindows = getCollapsedWindows(visibleWindows)
  local nonCollapsedWindows = #visibleWindows - #collapsedWindows

  if #visibleWindows == 0 then
    return  -- No windows to tile
  end

  local mainScreen = screen.mainScreen()
  local mainScreenFrame = mainScreen:frame()
  local tileWidth, tileHeight

  if orientation == "horizontal" then
    tileWidth = (mainScreenFrame.w - (nonCollapsedWindows - 1) * tileGap) / nonCollapsedWindows
    tileHeight = mainScreenFrame.h - (#collapsedWindows > 0 and collapsedWindowHeight + tileGap or 0)
  else
    tileWidth = mainScreenFrame.w
    tileHeight = (mainScreenFrame.h - (#collapsedWindows > 0 and (#collapsedWindows * (collapsedWindowHeight + tileGap) - tileGap) or 0) - (nonCollapsedWindows - 1) * tileGap) / nonCollapsedWindows
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
    local isCollapsed = win:size().h <= collapsedWindowHeight
    local newFrame

    if isCollapsed then
      if orientation == "horizontal" then
        newFrame = {
          x = collapsedWinX,
          y = collapsedWinY,
          w = initialCollapsedWidth,
          h = collapsedWindowHeight
        }
        collapsedWinX = collapsedWinX + initialCollapsedWidth + tileGap
      else
        newFrame = {
          x = collapsedWinX,
          y = collapsedWinY,
          w = tileWidth,
          h = collapsedWindowHeight
        }
        collapsedWinY = collapsedWinY - collapsedWindowHeight - tileGap
      end
    else
      newFrame = {
        x = nonCollapsedWinX,
        y = nonCollapsedWinY,
        w = tileWidth,
        h = tileHeight
      }
      if orientation == "horizontal" then
        nonCollapsedWinX = nonCollapsedWinX + tileWidth + tileGap
      else
        nonCollapsedWinY = nonCollapsedWinY + tileHeight + tileGap
      end
    end
    win:setFrame(geometry.rect(newFrame), 0)
  end
end

local function isDesktop(win)
  return win:application():name() == "Finder" and win:title() == "Desktop"
end

local function drawActiveWindowOutline(win)
  if win and win:isVisible() and not win:isFullScreen() and not isDesktop(win) then
    local frame = win:frame()
    local adjustedFrame = {
      x = frame.x - outlineThickness / 4,
      y = frame.y - outlineThickness / 4,
      w = frame.w + outlineThickness / 2,
      h = frame.h + outlineThickness / 2
    }

    if not activeWindowOutline then
      activeWindowOutline = drawing.rectangle(geometry.rect(adjustedFrame))
      activeWindowOutline:setStrokeColor(outlineColor)
      activeWindowOutline:setFill(false)
      activeWindowOutline:setStrokeWidth(outlineThickness)
      activeWindowOutline:setRoundedRectRadii(12, 12)
      activeWindowOutline:setLevel(drawing.windowLevels.popUpMenu)
    else
      activeWindowOutline:setFrame(geometry.rect(adjustedFrame))
    end

    activeWindowOutline:show()
  else
    -- If the window is not valid for outlining, hide the outline
    if activeWindowOutline then
      activeWindowOutline:hide()
    end
  end
end

local function handleWindowFocused(win)
  if win and win:isVisible() and not win:isFullScreen() and not isDesktop(win) then
    if isAppWhitelisted(win:application(), win) then
      tileWindows()
    end
    drawActiveWindowOutline(win)
  else
    -- If the focused window is not valid for outlining, hide the outline
    if activeWindowOutline then
      activeWindowOutline:hide()
    end
  end
end

local function handleWindowDestroyed(win)
  tileWindows()
  -- After a window is destroyed, get the new focused window and update the outline
  local newFocusedWindow = window.focusedWindow()
  if newFocusedWindow then
    handleWindowFocused(newFocusedWindow)
  else
    -- If no window is focused, hide the outline
    if activeWindowOutline then
      activeWindowOutline:hide()
    end
  end
end

window.filter.default:subscribe({
  window.filter.windowCreated,
  window.filter.windowHidden,
  window.filter.windowUnhidden,
  window.filter.windowMinimized,
  window.filter.windowUnminimized,
  window.filter.windowMoved,
  window.filter.windowsChanged
}, function(win)
  tileWindows()
  local focusedWindow = window.focusedWindow()
  if focusedWindow then
    drawActiveWindowOutline(focusedWindow)
  end
end)

window.filter.default:subscribe(window.filter.windowDestroyed, handleWindowDestroyed)
window.filter.default:subscribe(window.filter.windowFocused, handleWindowFocused)

tileWindows()
local initialFocusedWindow = window.focusedWindow()
if initialFocusedWindow then
  drawActiveWindowOutline(initialFocusedWindow)
end

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
