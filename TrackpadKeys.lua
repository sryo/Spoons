-- TrackpadKeys: https://github.com/sryo/Spoons/blob/main/TrackpadKeys.lua
-- This adds a row of keys to the top of the trackpad.

local TrackpadKeys = {}

local isEnabled = false
local clickWatcher
local gestureEventtap, escapeEventtap

TrackpadKeys.config = {
	showKeyPreview = true,
	keyPreviewDuration = 1,
	cornerActivationArea = 0.15,
	messageDuration = 1,
	debug = false
}

local keyboard = {
	"escape", "q", "a", "z", "w", "s", "x", "e", "d", "c", "r", "f", "v", "t", "g", "b", "y", "h", "n", "u", "j", "m",
	"i", "k", ",", "o", "l", ".", "p", "ñ", "-", "space", "delete", "return"
}

local symbols = {
	space = "___",
	["return"] = "↵",
	delete = "⌫",
	escape = "⎋"
}

local keyboardZone = {
	y = 0.97,
	height = 0.03
}

local cornerZone = {
	y = 0,
	height = 0.15,
	leftWidth = 0.15,
	rightWidth = 0.15
}

local currentKey = nil
local isKeyEmitted = false
local keyboardTouch = nil
local cornerTouch = nil
local circleFillTimer = nil
local lastTouchPosition = nil
local lastTouchCount = 0

local function debugPrint(message)
	if TrackpadKeys.config.debug then
		print(os.date("%H:%M:%S") .. " [TrackpadKeys] " .. message)
	end
end

local function getKeyPreviewPosition()
	local screenSize = hs.screen.mainScreen():frame()
	return (screenSize.w - 30) / 2, screenSize.h - 100
end

local keyPreviewX, keyPreviewY = getKeyPreviewPosition()

local keyPreview = hs.canvas.new({ x = keyPreviewX, y = keyPreviewY, w = 250, h = 50 })
keyPreview[1] = {
	type = "rectangle",
	action = "fill",
	roundedRectRadii = { xRadius = 4, yRadius = 4 },
	fillColor = { white = 0, alpha = 0.75 }
}

for i = 1, 5 do
	keyPreview[i + 1] = {
		type = "text",
		text = "",
		textColor = { white = 1, alpha = 1 },
		textAlignment = "center",
		textSize = 20,
		frame = { x = (i - 1) * 50, y = 10, w = 50, h = 30 }
	}
end

keyPreview[7] = {
	type = "circle",
	action = "stroke",
	strokeColor = { red = 1, green = 1, blue = 0, alpha = 1 },
	strokeWidth = 2,
	center = { x = 125, y = 25 },
	radius = 0
}

local messageCanvas = hs.canvas.new({ x = keyPreviewX, y = keyPreviewY, w = 250, h = 50 })
messageCanvas[1] = {
	type = "rectangle",
	action = "fill",
	roundedRectRadii = { xRadius = 4, yRadius = 4 },
	fillColor = { white = 0, alpha = 0.75 }
}
messageCanvas[2] = {
	type = "text",
	text = "",
	textColor = { white = 1, alpha = 1 },
	textAlignment = "center",
	textSize = 16,
	frame = { x = 0, y = 15, w = 250, h = 20 }
}

local function showMessage(message)
	messageCanvas[2].text = message
	messageCanvas:show()

	if messageTimer then
		messageTimer:stop()
	end

	messageTimer = hs.timer.doAfter(TrackpadKeys.config.messageDuration, function()
		messageCanvas:hide()
	end)
end

local function updatePressureCircle(pressure, fill)
	local maxRadius = 1
	local radius = pressure * maxRadius
	keyPreview[7].radius = radius
	keyPreview[7].action = "stroke"
	keyPreview[7].strokeColor = { red = 1, green = 1, blue = 0, alpha = 1 }
	keyPreview:show()
end

local function getSelectedKey(pos)
	local index = math.floor(pos.x * #keyboard) + 1
	return math.min(index, #keyboard)
end

local function showKeyPreview(index, isModified)
	if keyPreviewTimer then
		keyPreviewTimer:stop()
	end

	keyPreviewTimer = hs.timer.doAfter(TrackpadKeys.config.keyPreviewDuration, function()
		keyPreview:hide()
	end)

	for i = 1, 5 do
		local keyIndex = index - 3 + i
		if keyIndex >= 1 and keyIndex <= #keyboard then
			local key = keyboard[keyIndex]
			local displayKey = symbols[key] or key
			if isModified and #key == 1 then
				displayKey = displayKey:upper()
			else
				displayKey = displayKey:lower()
			end
			keyPreview[i + 1].text = displayKey
			keyPreview[i + 1].textColor = (i == 3) and
				(isKeyEmitted and { white = 1, alpha = 1 } or { red = 1, green = 1, blue = 0, alpha = 1 }) or
				{ white = 1, alpha = 1 }
		else
			keyPreview[i + 1].text = ""
		end
	end

	keyPreview:show()
end

local function emitKey(key, isModified, touchPosition)
	local modifiers = isModified and { "shift" } or {}
	local emittedKey = isModified and key:upper() or key

	hs.eventtap.keyStroke(modifiers, emittedKey)
	debugPrint("Emitting key: " .. emittedKey)

	isKeyEmitted = true
	updatePressureCircle(1, false)
	showKeyPreview(getSelectedKey(touchPosition), isModified)


	return emittedKey
end

local function isInCorner(pos)
	return (pos.y <= cornerZone.y + cornerZone.height) and
		(pos.x <= cornerZone.leftWidth or pos.x >= 1 - cornerZone.rightWidth)
end

local function resetState()
	currentKey = nil
	isKeyEmitted = false
	keyboardTouch = nil
	cornerTouch = nil
	lastTouchPosition = nil
	if circleFillTimer then
		circleFillTimer:stop()
	end
	keyPreview:hide()
	messageCanvas:hide()
	debugPrint("TrackpadKeys state reset")
end

local function handleTouches(touches)
	local newKeyboardTouch = nil
	local newCornerTouch = nil
	local gestureEnded = (#touches == 0)

	for _, touch in ipairs(touches) do
		if touch.type == "indirect" and touch.normalizedPosition then
			if touch.normalizedPosition.y >= keyboardZone.y and
				touch.normalizedPosition.y <= keyboardZone.y + keyboardZone.height then
				newKeyboardTouch = touch
			elseif isInCorner(touch.normalizedPosition) then
				newCornerTouch = touch
			end
		end
	end

	local isModified = newCornerTouch ~= nil

	if newKeyboardTouch then
		local index = getSelectedKey(newKeyboardTouch.normalizedPosition)
		local newKey = keyboard[index]

		if newKey ~= currentKey or lastTouchPosition == nil or isModified ~= (cornerTouch ~= nil) then
			currentKey = newKey
			showKeyPreview(index, isModified)
			debugPrint("Key selected: " .. currentKey .. ", Modified: " .. tostring(isModified))
		end

		updatePressureCircle(newKeyboardTouch.force, isKeyEmitted)

		debugPrint("Touch position: y=" ..
			newKeyboardTouch.normalizedPosition.y .. ", Pressure: " .. newKeyboardTouch.force)
		lastTouchPosition = newKeyboardTouch.normalizedPosition
	elseif currentKey and (isModified ~= (cornerTouch ~= nil)) then
		showKeyPreview(getSelectedKey(lastTouchPosition), isModified)
	end

	local touchCount = #touches
	debugPrint("Touch count: " .. touchCount .. ", Last touch count: " .. lastTouchCount)

	if keyboardTouch and not newKeyboardTouch and touchCount < lastTouchCount then
		debugPrint("Touch ended. Last position: " .. (lastTouchPosition and ("y=" .. lastTouchPosition.y) or "unknown"))
		if currentKey and lastTouchPosition and
			lastTouchPosition.y >= keyboardZone.y and
			lastTouchPosition.y <= keyboardZone.y + keyboardZone.height then
			debugPrint("Finger lifted in key zone. Emitting key: " .. currentKey)
			local emittedKey = emitKey(currentKey, isModified, lastTouchPosition)
		else
			debugPrint("Touch ended outside key zone or no key selected. No key emitted.")
			keyPreview:hide()
			showMessage("No key emitted")
		end
		currentKey = nil
	elseif keyboardTouch and not newKeyboardTouch then
		debugPrint("Touch moved out of keyboard zone. Cancelling key emission.")
		keyPreview:hide()
		showMessage("Key cancelled")
		currentKey = nil
	elseif keyboardTouch and newKeyboardTouch then
		if lastTouchPosition and
			(lastTouchPosition.y < keyboardZone.y or lastTouchPosition.y > keyboardZone.y + keyboardZone.height) and
			(newKeyboardTouch.normalizedPosition.y >= keyboardZone.y and newKeyboardTouch.normalizedPosition.y <= keyboardZone.y + keyboardZone.height) then
			debugPrint("Finger moved into keyboard zone.")
		end
	end

	keyboardTouch = newKeyboardTouch
	cornerTouch = newCornerTouch
	lastTouchPosition = newKeyboardTouch and newKeyboardTouch.normalizedPosition or lastTouchPosition
	lastTouchCount = touchCount

	if gestureEnded then
		resetState()
	end
end

local function isInputFieldFocused()
	local elem = hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement")
	if elem then
		local role = elem:attributeValue("AXRole")
		local subrole = elem:attributeValue("AXSubrole")
		local canFocus = elem:attributeValue("AXFocused")
		local editable = elem:attributeValue("AXEditable")

		debugPrint("Focused element - Role: " .. tostring(role) ..
			", Subrole: " .. tostring(subrole) ..
			", Can Focus: " .. tostring(canFocus) ..
			", Editable: " .. tostring(editable))

		-- Check for any element that can potentially accept text input
		local isInputLike = role == "AXTextField" or
			role == "AXTextArea" or
			role == "AXComboBox" or
			role == "AXSearchField" or
			role == "AXButton" or
			(role == "AXWebArea" and subrole == "AXContentEditable") or
			(role == "AXStaticText" and canFocus == true) or
			(canFocus and editable)

		debugPrint("Is input-like element: " .. tostring(isInputLike))
		return isInputLike
	end
	debugPrint("No focused element found")
	return false
end

local function checkInputFocus()
	debugPrint("Checking input focus")
	hs.timer.doAfter(0.1, function()
		local inputFocused = isInputFieldFocused()
		debugPrint("Input-like element focused: " ..
			tostring(inputFocused) .. ", Currently enabled: " .. tostring(isEnabled))
		if inputFocused then
			if not isEnabled then
				isEnabled = true
				showMessage("TrackpadKeys Enabled")
				debugPrint("TrackpadKeys Enabled")
			else
				debugPrint("TrackpadKeys already enabled")
			end
		else
			if isEnabled then
				isEnabled = false
				showMessage("TrackpadKeys Disabled")
				debugPrint("TrackpadKeys Disabled")
			else
				debugPrint("TrackpadKeys already disabled")
			end
		end
	end)
end

function TrackpadKeys.toggle()
	if clickWatcher then
		clickWatcher:stop()
		clickWatcher = nil
		if gestureEventtap then
			gestureEventtap:stop()
		end
		if escapeEventtap then
			escapeEventtap:stop()
		end
		isEnabled = false
		debugPrint("TrackpadKeys stopped")
		showMessage("TrackpadKeys Stopped")
	else
		clickWatcher = hs.eventtap.new({ hs.eventtap.event.types.leftMouseDown, hs.eventtap.event.types.rightMouseDown },
			function(event)
				debugPrint("Mouse click detected")
				hs.timer.doAfter(0.3, function()
					for i = 1, 3 do
						hs.timer.doAfter(i * 0.3, checkInputFocus)
					end
				end)
				return false
			end)
		clickWatcher:start()

		gestureEventtap = hs.eventtap.new({ hs.eventtap.event.types.gesture }, function(e)
			local touches = e:getTouches()
			if touches and isEnabled then
				handleTouches(touches)
			end
		end)

		escapeEventtap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
			local keyCode = e:getKeyCode()
			if keyCode == hs.keycodes.map.escape then
				resetState()
				return true
			end
			return false
		end)

		gestureEventtap:start()
		escapeEventtap:start()
		debugPrint("TrackpadKeys started")
		showMessage("TrackpadKeys Started")
		checkInputFocus()
	end
end

debugPrint("TrackpadKeys loaded")
TrackpadKeys.toggle()

return TrackpadKeys
