-- Turn your trackpad sideways (very buggy)

local obj = {}

-- Configuration options
local config = {
    rotateClockwise = true,  -- Set to false for counterclockwise rotation
    invertX = false,         -- Set to true to invert X axis
    invertY = false,         -- Set to true to invert Y axis
    baseSensitivity = 3.0,   -- Base sensitivity multiplier
    accelerationFactor = 2.0 -- Factor for non-linear acceleration
}

-- Variables to store the last touch position
local lastX, lastY = 0, 0

-- Function to apply non-linear acceleration
local function applyAcceleration(value)
    local sign = value > 0 and 1 or -1
    return sign * math.pow(math.abs(value) * config.baseSensitivity, config.accelerationFactor)
end

-- Function to adjust movement based on rotation and inversion settings
local function adjustMovement(dx, dy)
    local newDx, newDy
    if config.rotateClockwise then
        newDx, newDy = dy, -dx
    else
        newDx, newDy = -dy, dx
    end
    
    if config.invertX then newDx = -newDx end
    if config.invertY then newDy = -newDy end
    
    return applyAcceleration(newDx), applyAcceleration(newDy)
end

-- Intercept and modify trackpad events
local function handleGesture(event)
    local touches = event:getTouches()
    if touches and #touches > 0 then
        local touch = touches[1]  -- We'll use the first touch point
        local x, y = touch.normalizedPosition.x, touch.normalizedPosition.y
        
        if lastX ~= 0 and lastY ~= 0 then
            -- Calculate the delta movement
            local dx = x - lastX
            local dy = y - lastY
            
            -- Adjust the delta based on rotation and inversion settings
            local newDx, newDy = adjustMovement(dx, dy)
            
            -- Get current mouse position
            local currentPos = hs.mouse.getAbsolutePosition()
            
            -- Calculate new position
            local newX = currentPos.x + newDx * hs.screen.mainScreen():frame().w
            local newY = currentPos.y + newDy * hs.screen.mainScreen():frame().h
            
            -- Move the mouse
            hs.mouse.setAbsolutePosition({x = newX, y = newY})
        end
        
        -- Update last position
        lastX, lastY = x, y
    else
        -- Reset last position when all fingers are lifted
        lastX, lastY = 0, 0
    end
    
    -- Allow the original event to be processed
    return false
end

function obj:start()
    if not self.eventTap then
        self.eventTap = hs.eventtap.new({hs.eventtap.event.types.gesture}, handleGesture)
    end
    self.eventTap:start()
    print("VerticalTrackpad event tap started")  -- Debug print
end

function obj:stop()
    if self.eventTap then
        self.eventTap:stop()
        print("VerticalTrackpad event tap stopped")  -- Debug print
    end
end

-- Automatically start when the module is loaded
obj:start()

return obj
