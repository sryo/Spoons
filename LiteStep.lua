--[[
  LiteStep.lua - LiteStep shell reimplementation for Hammerspoon
  Compatible with xLabel, xTaskbar, xTray, xPopup via xPaintClass

  Supported RC syntax:
    KeyName Value              -- simple key-value
    *KeyName Value             -- command line (repeatable)
    ; comment                  -- comments
    $variable$                 -- variable expansion
    $expr+expr$                -- math expression evaluation
    include "file.rc"          -- include files
    If condition / Else / EndIf -- conditionals
    ~Value                     -- relative from screen edge

  xPaintClass compatibility:
    - PaintingMode (.image, .singlecolor, .multicolor, .icon, etc.)
    - ImageMode (.stretch, .tile, .tile-horizontal, etc.)
    - ImageEdges (9-slice scaling)
    - GradientType (.horizontal, .vertical, .radial, etc.)
    - ShapeMode (.rectangle, .ellipse, .rounded)
    - FontShadow, FontOutline, FontBorders
]]

local LiteStep = {}

-- Module registry
LiteStep.modules = {}
LiteStep.windows = {}
LiteStep.labels = {}
LiteStep.settings = {}
LiteStep.variables = {}
LiteStep.commandLines = {}
LiteStep.bangCommands = {}
LiteStep.timers = {}

-- Screen dimensions for relative calculations
local function getScreenRect()
    local screen = hs.screen.mainScreen()
    if screen then
        return screen:fullFrame()
    end
    return {x = 0, y = 0, w = 1920, h = 1080}
end

--------------------------------------------------------------------------------
-- MATH EXPRESSION EVALUATOR
--------------------------------------------------------------------------------

local function evaluateMathExpression(expr, variables)
    if not expr or expr == "" then return nil end

    -- Replace variable references with their values
    local resolved = expr:gsub("([%a_][%w_]*)", function(varName)
        local val = variables[varName:lower()]
        if val then
            return tostring(val)
        end
        return varName
    end)

    -- Simple math expression parser supporting +, -, *, /, ()
    local function parseExpression(str)
        str = str:match("^%s*(.-)%s*$") or str

        -- Try to evaluate using Lua's load (safe subset)
        local sanitized = str:gsub("[^%d%.%+%-%*%/%(%)]", "")
        if sanitized == str then
            local fn, err = load("return " .. str)
            if fn then
                local ok, result = pcall(fn)
                if ok and type(result) == "number" then
                    return result
                end
            end
        end

        -- Fallback: try simple number
        return tonumber(str)
    end

    return parseExpression(resolved)
end

--------------------------------------------------------------------------------
-- RC PARSER (Enhanced)
--------------------------------------------------------------------------------

local RCParser = {}
RCParser.__index = RCParser

function RCParser.new()
    local self = setmetatable({}, RCParser)
    self.settings = {}
    self.commandLines = {}
    self.variables = {}
    self.prefixStack = {}
    self.includedFiles = {}
    self.conditionalStack = {} -- Track if/else state
    self.basePath = os.getenv("HOME") .. "/.hammerspoon/"

    -- Built-in variables
    local screen = getScreenRect()
    self.variables["resolutionx"] = screen.w
    self.variables["resolutiony"] = screen.h
    self.variables["screenwidth"] = screen.w
    self.variables["screenheight"] = screen.h
    self.variables["nl"] = "\n"
    self.variables["cr"] = "\r"
    self.variables["tab"] = "\t"
    self.variables["sq"] = "'"
    self.variables["dq"] = '"'

    -- Platform detection (for compatibility with Windows themes)
    -- On macOS, we define Darwin=true, Win64=false, Win32=false
    self.variables["darwin"] = "true"
    self.variables["macos"] = "true"
    self.variables["win64"] = nil  -- Not defined = false in conditionals
    self.variables["win32"] = nil
    self.variables["windows"] = nil

    -- Architecture
    local arch = io.popen("uname -m"):read("*l") or "unknown"
    if arch == "arm64" or arch == "aarch64" then
        self.variables["arm64"] = "true"
        self.variables["x64"] = nil
    else
        self.variables["x64"] = "true"
        self.variables["arm64"] = nil
    end

    -- Home directory
    self.variables["homedir"] = os.getenv("HOME") or ""
    self.variables["userdir"] = os.getenv("HOME") or ""
    self.variables["username"] = os.getenv("USER") or ""

    -- Store commands to run on load
    self.onLoadCommands = {}

    return self
end

-- Expand $variable$ and $expr$ references
function RCParser:expandVariables(str)
    if not str then return "" end

    local result = str
    local maxIterations = 20
    local iteration = 0

    while iteration < maxIterations do
        local expanded = result:gsub("%$([^%$]+)%$", function(content)
            -- Check if it's a math expression (contains operators)
            if content:match("[%+%-%*/]") then
                local val = evaluateMathExpression(content, self.variables)
                if val then
                    return tostring(math.floor(val + 0.5))
                end
            end

            -- Simple variable lookup
            local value = self.variables[content:lower()]
            if value then
                return tostring(value)
            end

            -- Environment variable
            local envValue = os.getenv(content)
            if envValue then
                return envValue
            end

            return "$" .. content .. "$"
        end)

        if expanded == result then break end
        result = expanded
        iteration = iteration + 1
    end

    return result
end

-- Strip comments and whitespace
function RCParser:stripLine(line)
    if not line then return "" end

    line = line:match("^%s*(.-)%s*$")

    -- Handle comments (respect quotes)
    local inQuote = false
    local quoteChar = nil
    local result = ""

    for i = 1, #line do
        local c = line:sub(i, i)

        if not inQuote and (c == '"' or c == "'") then
            inQuote = true
            quoteChar = c
            result = result .. c
        elseif inQuote and c == quoteChar then
            inQuote = false
            quoteChar = nil
            result = result .. c
        elseif not inQuote and c == ";" then
            break
        else
            result = result .. c
        end
    end

    return result:match("^%s*(.-)%s*$") or ""
end

-- Parse a token (handle quotes)
function RCParser:parseToken(str)
    if not str then return nil, "" end

    str = str:match("^%s*(.-)%s*$") or ""
    if str == "" then return nil, "" end

    local token, rest

    if str:sub(1, 1) == '"' then
        local endQuote = str:find('"', 2, true)
        if endQuote then
            token = str:sub(2, endQuote - 1)
            rest = str:sub(endQuote + 1)
        else
            token = str:sub(2)
            rest = ""
        end
    elseif str:sub(1, 1) == "'" then
        local endQuote = str:find("'", 2, true)
        if endQuote then
            token = str:sub(2, endQuote - 1)
            rest = str:sub(endQuote + 1)
        else
            token = str:sub(2)
            rest = ""
        end
    else
        local space = str:find("%s")
        if space then
            token = str:sub(1, space - 1)
            rest = str:sub(space + 1)
        else
            token = str
            rest = ""
        end
    end

    return token, rest:match("^%s*(.-)%s*$") or ""
end

-- Evaluate conditional expression
function RCParser:evaluateCondition(expr)
    expr = self:expandVariables(expr)

    -- Handle "Win64" style checks
    if expr:lower() == "win64" then
        return false -- We're on macOS
    end

    -- Handle equality: "VarName = Value"
    local var, op, val = expr:match("^(%S+)%s*([=<>!]+)%s*(.+)$")
    if var and op and val then
        local varValue = tostring(self.variables[var:lower()] or var)
        val = val:match("^%s*(.-)%s*$")

        if op == "=" or op == "==" then
            return varValue == val
        elseif op == "!=" or op == "<>" then
            return varValue ~= val
        elseif op == "<" then
            return (tonumber(varValue) or 0) < (tonumber(val) or 0)
        elseif op == ">" then
            return (tonumber(varValue) or 0) > (tonumber(val) or 0)
        elseif op == "<=" then
            return (tonumber(varValue) or 0) <= (tonumber(val) or 0)
        elseif op == ">=" then
            return (tonumber(varValue) or 0) >= (tonumber(val) or 0)
        end
    end

    -- Check if variable exists and is truthy
    local varValue = self.variables[expr:lower()]
    if varValue ~= nil then
        local lower = tostring(varValue):lower()
        return lower ~= "false" and lower ~= "0" and lower ~= "" and lower ~= "nil"
    end

    return false
end

-- Check if we should process current line based on conditional state
function RCParser:shouldProcessLine()
    for _, state in ipairs(self.conditionalStack) do
        if not state.active then
            return false
        end
    end
    return true
end

-- Get current prefix from stack
function RCParser:getCurrentPrefix()
    local prefix = ""
    for i = 1, #self.prefixStack do
        prefix = prefix .. self.prefixStack[i]
    end
    return prefix
end

-- Process a single line
function RCParser:processLine(key, value, lineNumber)
    local lowerKey = key:lower()

    -- Handle special directives
    if lowerKey == "include" then
        local filename = self:parseToken(value)
        if filename then
            filename = self:expandVariables(filename)
            self:parseFile(filename)
        end
        return
    end

    -- Build full key with prefix
    local isCommand = key:sub(1, 1) == "*"
    local fullKey

    if isCommand then
        fullKey = "*" .. self:getCurrentPrefix() .. key:sub(2)
    else
        fullKey = self:getCurrentPrefix() .. key
    end

    -- Expand variables in value
    value = self:expandVariables(value)

    -- Handle special command directives
    if isCommand then
        local cmdName = key:sub(2):lower()

        -- *mzVarFile - load mzscript variable file
        if cmdName == "mzvarfile" then
            local filename = self:parseToken(value)
            if filename then
                filename = self:expandVariables(filename)
                self:parseFile(filename)
            end
            return
        end
    end

    -- Handle NetLoadModuleOnLoad (command to run when modules are loaded)
    if lowerKey == "netloadmoduleonload" then
        table.insert(self.onLoadCommands, value)
        -- Also store as regular setting
    end

    -- Store the setting
    if isCommand then
        local cmdKey = fullKey:sub(2):lower()
        if not self.commandLines[cmdKey] then
            self.commandLines[cmdKey] = {}
        end
        table.insert(self.commandLines[cmdKey], value)
    else
        local lowerFullKey = fullKey:lower()
        -- Settings can be overwritten (last wins, unlike original LS)
        self.settings[lowerFullKey] = value
        self.variables[lowerFullKey] = value
    end
end

-- Parse a file
function RCParser:parseFile(filename)
    local fullPath = filename
    if not filename:match("^/") then
        fullPath = self.basePath .. filename
    end

    -- Handle path variables
    fullPath = fullPath:gsub("%$ThemeDir%$", self.basePath .. "litestep/themes/current/")
    fullPath = fullPath:gsub("%$ConfigDir%$", self.basePath .. "litestep/config/")
    fullPath = fullPath:gsub("%$LSImageFolder%$", self.basePath .. "litestep/images/")

    if self.includedFiles[fullPath] then
        return
    end
    self.includedFiles[fullPath] = true

    local file = io.open(fullPath, "r")
    if not file then
        print("LiteStep: Could not open file: " .. fullPath)
        return
    end

    local lineNumber = 0

    for line in file:lines() do
        lineNumber = lineNumber + 1
        line = self:stripLine(line)

        if line ~= "" then
            local key, rest = self:parseToken(line)
            if key then
                local lowerKey = key:lower()

                -- Handle conditionals
                if lowerKey == "if" then
                    local condition = self:evaluateCondition(rest)
                    table.insert(self.conditionalStack, {
                        active = condition and self:shouldProcessLine(),
                        wasTrue = condition
                    })
                elseif lowerKey == "elseif" then
                    if #self.conditionalStack > 0 then
                        local state = self.conditionalStack[#self.conditionalStack]
                        if not state.wasTrue and self:shouldProcessLine() then
                            local condition = self:evaluateCondition(rest)
                            state.active = condition
                            state.wasTrue = state.wasTrue or condition
                        else
                            state.active = false
                        end
                    end
                elseif lowerKey == "else" then
                    if #self.conditionalStack > 0 then
                        local state = self.conditionalStack[#self.conditionalStack]
                        state.active = not state.wasTrue
                    end
                elseif lowerKey == "endif" then
                    if #self.conditionalStack > 0 then
                        table.remove(self.conditionalStack)
                    end
                elseif line == "}" then
                    if #self.prefixStack > 0 then
                        table.remove(self.prefixStack)
                    end
                elseif line:sub(-1) == "{" then
                    local blockPrefix = line:sub(1, -2):match("^%s*(.-)%s*$")
                    table.insert(self.prefixStack, blockPrefix)
                elseif self:shouldProcessLine() then
                    self:processLine(key, rest, lineNumber)
                end
            end
        end
    end

    file:close()
    self.includedFiles[fullPath] = nil
end

--------------------------------------------------------------------------------
-- SETTINGS
--------------------------------------------------------------------------------

local Settings = {}
Settings.__index = Settings

function Settings.new(prefix, parser, defaults)
    local self = setmetatable({}, Settings)
    self.prefix = prefix or ""
    self.parser = parser
    self.defaults = defaults or {}

    -- Load group setting for inheritance
    local groupName = self:getString("Group", nil)
    if groupName and groupName ~= "" then
        self.group = Settings.new(groupName, parser)
    end

    return self
end

function Settings:getFullKey(key)
    return (self.prefix .. key):lower()
end

function Settings:getString(key, default)
    local value = self.parser.settings[self:getFullKey(key)]
    if value ~= nil then
        return value
    end
    if self.group then
        return self.group:getString(key, default)
    end
    return self.defaults[key:lower()] or default
end

function Settings:getInt(key, default)
    local str = self:getString(key, nil)
    if str then
        -- Handle tilde prefix (relative from bottom/right)
        if str:sub(1, 1) == "~" then
            local val = tonumber(str:sub(2)) or 0
            return -val -- Signal to caller to subtract from screen
        end
        return math.floor(tonumber(str) or default)
    end
    return default
end

function Settings:getFloat(key, default)
    local str = self:getString(key, nil)
    if str then
        return tonumber(str) or default
    end
    return default
end

function Settings:getBool(key, default)
    local str = self:getString(key, nil)
    if str then
        local lower = str:lower()
        if lower == "true" or lower == "on" or lower == "yes" or lower == "1" then
            return true
        elseif lower == "false" or lower == "off" or lower == "no" or lower == "0" then
            return false
        end
    end
    return default
end

function Settings:getColor(key, default)
    local str = self:getString(key, nil)
    if str then
        return LiteStep.parseColor(str) or default
    end
    return default
end

function Settings:getEnum(key, default)
    local str = self:getString(key, nil)
    if str then
        -- Remove leading dot if present
        if str:sub(1, 1) == "." then
            return str:sub(2):lower()
        end
        return str:lower()
    end
    return default
end

function Settings:getRect(defaults)
    defaults = defaults or {l = 0, t = 0, r = 0, b = 0}

    local bordersStr = self:getString("Borders", nil)
    if bordersStr then
        local parts = {}
        for part in bordersStr:gmatch("%S+") do
            table.insert(parts, tonumber(part) or 0)
        end
        if #parts == 4 then
            return {l = parts[1], t = parts[2], r = parts[3], b = parts[4]}
        elseif #parts == 2 then
            return {l = parts[1], t = parts[2], r = parts[1], b = parts[2]}
        elseif #parts == 1 then
            return {l = parts[1], t = parts[1], r = parts[1], b = parts[1]}
        end
    end

    return {
        l = self:getInt("LeftBorder", defaults.l),
        t = self:getInt("TopBorder", defaults.t),
        r = self:getInt("RightBorder", defaults.r),
        b = self:getInt("BottomBorder", defaults.b),
    }
end

function Settings:createChild(suffix)
    return Settings.new(self.prefix .. suffix, self.parser, self.defaults)
end

function Settings:iterateCommandLines(key, callback)
    local fullKey = (self.prefix .. key):lower()
    local lines = self.parser.commandLines[fullKey]
    if lines then
        for _, line in ipairs(lines) do
            callback(line)
        end
    end
    if self.group then
        self.group:iterateCommandLines(key, callback)
    end
end

--------------------------------------------------------------------------------
-- COLOR PARSING
--------------------------------------------------------------------------------

function LiteStep.parseColor(str)
    if not str then return nil end

    str = str:match("^%s*(.-)%s*$") or ""
    if str == "" then return nil end

    -- Named colors
    local namedColors = {
        black = {red = 0, green = 0, blue = 0, alpha = 1},
        white = {red = 1, green = 1, blue = 1, alpha = 1},
        red = {red = 1, green = 0, blue = 0, alpha = 1},
        green = {red = 0, green = 0.5, blue = 0, alpha = 1},
        blue = {red = 0, green = 0, blue = 1, alpha = 1},
        yellow = {red = 1, green = 1, blue = 0, alpha = 1},
        cyan = {red = 0, green = 1, blue = 1, alpha = 1},
        magenta = {red = 1, green = 0, blue = 1, alpha = 1},
        gray = {red = 0.5, green = 0.5, blue = 0.5, alpha = 1},
        grey = {red = 0.5, green = 0.5, blue = 0.5, alpha = 1},
        transparent = {red = 0, green = 0, blue = 0, alpha = 0},
    }

    local lower = str:lower()
    if namedColors[lower] then
        return namedColors[lower]
    end

    -- Hex color with # prefix
    local hex = str:match("^#(%x+)$")
    if not hex then
        -- Try without # (LiteStep format)
        hex = str:match("^(%x+)$")
    end

    if hex then
        local r, g, b, a = 0, 0, 0, 1

        if #hex == 3 then
            r = tonumber(hex:sub(1, 1), 16) / 15
            g = tonumber(hex:sub(2, 2), 16) / 15
            b = tonumber(hex:sub(3, 3), 16) / 15
        elseif #hex == 4 then
            a = tonumber(hex:sub(1, 1), 16) / 15
            r = tonumber(hex:sub(2, 2), 16) / 15
            g = tonumber(hex:sub(3, 3), 16) / 15
            b = tonumber(hex:sub(4, 4), 16) / 15
        elseif #hex == 6 then
            r = tonumber(hex:sub(1, 2), 16) / 255
            g = tonumber(hex:sub(3, 4), 16) / 255
            b = tonumber(hex:sub(5, 6), 16) / 255
        elseif #hex == 8 then
            -- AARRGGBB format (LiteStep standard)
            a = tonumber(hex:sub(1, 2), 16) / 255
            r = tonumber(hex:sub(3, 4), 16) / 255
            g = tonumber(hex:sub(5, 6), 16) / 255
            b = tonumber(hex:sub(7, 8), 16) / 255
        end

        return {red = r, green = g, blue = b, alpha = a}
    end

    -- RGB triplet: "255 128 0"
    local parts = {}
    for part in str:gmatch("%d+") do
        table.insert(parts, tonumber(part))
    end
    if #parts >= 3 then
        return {
            red = (parts[1] or 0) / 255,
            green = (parts[2] or 0) / 255,
            blue = (parts[3] or 0) / 255,
            alpha = parts[4] and (parts[4] / 255) or 1
        }
    end

    return nil
end

--------------------------------------------------------------------------------
-- xPaintClass: TEXTURE (Background painting)
--------------------------------------------------------------------------------

local Texture = {}
Texture.__index = Texture

function Texture.new(settings, prefix)
    local self = setmetatable({}, Texture)

    prefix = prefix or ""
    local s = settings:createChild(prefix)

    -- Painting mode
    self.paintingMode = s:getEnum("PaintingMode", "none")

    -- Position & size
    self.textureX = s:getInt("TextureX", 0)
    self.textureY = s:getInt("TextureY", 0)
    self.textureWidth = s:getString("TextureWidth", "100%")
    self.textureHeight = s:getString("TextureHeight", "100%")

    -- Solid color
    self.color = s:getColor("Color", {red = 0, green = 0, blue = 0, alpha = 0})

    -- Image settings
    self.image = s:getString("Image", nil)
    self.imageMode = s:getEnum("ImageMode", "stretch")
    self.imageEdges = s:getString("ImageEdges", nil) -- "L T R B" for 9-slice

    -- Transparency
    self.alphaTransparency = s:getInt("AlphaTransparency", 255)
    self.textureAlphaTransparency = s:getInt("TextureAlphaTransparency", 255)
    self.trueTransparency = s:getBool("TrueTransparency", false)

    -- Gradient settings
    self.gradientType = s:getEnum("GradientType", "horizontal")
    self.gradientColors = self:parseGradientColors(s:getString("GradientColors", nil))
    self.gradientStops = self:parseGradientStops(s:getString("GradientStops", nil))

    -- Gradient position (for radial)
    self.gradientCenterX = s:getFloat("GradientCenterX", 0.5)
    self.gradientCenterY = s:getFloat("GradientCenterY", 0.5)
    self.gradientRadiusX = s:getFloat("GradientRadiusX", 0.5)
    self.gradientRadiusY = s:getFloat("GradientRadiusY", 0.5)

    -- Shape
    self.shapeMode = s:getEnum("ShapeMode", "rectangle")
    self.roundedEdges = s:getString("RoundedEdges", "0")
    self.cornerRadiusX = s:getFloat("CornerRadiusX", 0)
    self.cornerRadiusY = s:getFloat("CornerRadiusY", 0)

    -- Parse rounded edges
    if self.roundedEdges ~= "0" then
        local parts = {}
        for part in self.roundedEdges:gmatch("%S+") do
            table.insert(parts, tonumber(part) or 0)
        end
        if #parts >= 1 then
            self.cornerRadiusX = parts[1]
            self.cornerRadiusY = parts[2] or parts[1]
        end
    end

    -- Border
    self.borderMethod = s:getEnum("BorderMethod", "none")
    self.bevels = s:getString("Bevels", "0 0 0 0")

    -- Hue tinting (xPaintClass)
    self.hueIntensity = s:getInt("HueIntensity", 0) -- 0-100
    self.hueColor = s:getColor("HueColor", nil)

    -- Alpha map (for transparency)
    self.alphaMap = s:getBool("AlphaMap", false)

    -- Brush type (nModules style)
    local brushType = s:getEnum("BrushType", nil)
    if brushType then
        if brushType == "solidcolor" then
            self.paintingMode = "singlecolor"
        elseif brushType == "radialgradient" or brushType == "lineargradient" then
            self.paintingMode = "multicolor"
            if brushType == "radialgradient" then
                self.gradientType = "radial"
            else
                self.gradientType = "horizontal"
            end
        elseif brushType == "image" then
            self.paintingMode = "image"
        end
    end

    return self
end

function Texture:parseGradientColors(str)
    if not str then return {} end
    local colors = {}
    for colorStr in str:gmatch("[#%x]+") do
        local color = LiteStep.parseColor(colorStr)
        if color then
            table.insert(colors, color)
        end
    end
    return colors
end

function Texture:parseGradientStops(str)
    if not str then return {} end
    local stops = {}
    for stopStr in str:gmatch("[%d%.]+") do
        table.insert(stops, tonumber(stopStr) or 0)
    end
    return stops
end

function Texture:toCanvasElements(rect, parentWidth, parentHeight)
    local elements = {}
    local alpha = self.alphaTransparency / 255

    if self.paintingMode == "none" or self.paintingMode == "-1" then
        return elements
    end

    if self.paintingMode == "singlecolor" or self.paintingMode == "3" then
        local color = {
            red = self.color.red,
            green = self.color.green,
            blue = self.color.blue,
            alpha = self.color.alpha * alpha
        }

        local elem = {
            type = "rectangle",
            fillColor = color,
            strokeColor = {alpha = 0},
            frame = rect,
        }

        if self.cornerRadiusX > 0 or self.cornerRadiusY > 0 then
            elem.roundedRectRadii = {
                xRadius = self.cornerRadiusX,
                yRadius = self.cornerRadiusY
            }
        end

        table.insert(elements, elem)

    elseif self.paintingMode == "multicolor" or self.paintingMode == "2" then
        -- Gradient - approximate with rectangles
        if #self.gradientColors >= 2 then
            if self.gradientType == "radial" then
                -- Radial gradient approximation
                local steps = 15
                local cx = self.gradientCenterX
                local cy = self.gradientCenterY
                local rx = self.gradientRadiusX
                local ry = self.gradientRadiusY

                -- Scale to actual pixels if > 1
                if cx > 1 then cx = cx / rect.w end
                if cy > 1 then cy = cy / rect.h end
                if rx > 1 then rx = rx / rect.w end
                if ry > 1 then ry = ry / rect.h end

                for i = steps, 1, -1 do
                    local t = i / steps
                    local colorIdx = math.floor(t * (#self.gradientColors - 1)) + 1
                    local nextIdx = math.min(colorIdx + 1, #self.gradientColors)
                    local localT = (t * (#self.gradientColors - 1)) - (colorIdx - 1)

                    local c1 = self.gradientColors[colorIdx]
                    local c2 = self.gradientColors[nextIdx]

                    local color = {
                        red = c1.red + (c2.red - c1.red) * localT,
                        green = c1.green + (c2.green - c1.green) * localT,
                        blue = c1.blue + (c2.blue - c1.blue) * localT,
                        alpha = (c1.alpha + (c2.alpha - c1.alpha) * localT) * alpha
                    }

                    local size = t
                    table.insert(elements, {
                        type = "oval",
                        fillColor = color,
                        strokeColor = {alpha = 0},
                        frame = {
                            x = rect.x + (cx - rx * size) * rect.w,
                            y = rect.y + (cy - ry * size) * rect.h,
                            w = rx * 2 * size * rect.w,
                            h = ry * 2 * size * rect.h
                        }
                    })
                end
            else
                -- Linear gradient (horizontal/vertical)
                local steps = 20
                local isVertical = self.gradientType == "vertical"

                for i = 0, steps - 1 do
                    local t = i / (steps - 1)
                    local colorIdx = math.floor(t * (#self.gradientColors - 1)) + 1
                    local nextIdx = math.min(colorIdx + 1, #self.gradientColors)
                    local localT = (t * (#self.gradientColors - 1)) - (colorIdx - 1)

                    local c1 = self.gradientColors[colorIdx]
                    local c2 = self.gradientColors[nextIdx]

                    local color = {
                        red = c1.red + (c2.red - c1.red) * localT,
                        green = c1.green + (c2.green - c1.green) * localT,
                        blue = c1.blue + (c2.blue - c1.blue) * localT,
                        alpha = (c1.alpha + (c2.alpha - c1.alpha) * localT) * alpha
                    }

                    local elemRect
                    if isVertical then
                        local stepH = rect.h / steps
                        elemRect = {x = rect.x, y = rect.y + i * stepH, w = rect.w, h = stepH + 1}
                    else
                        local stepW = rect.w / steps
                        elemRect = {x = rect.x + i * stepW, y = rect.y, w = stepW + 1, h = rect.h}
                    end

                    table.insert(elements, {
                        type = "rectangle",
                        fillColor = color,
                        strokeColor = {alpha = 0},
                        frame = elemRect
                    })
                end
            end
        end

    elseif self.paintingMode == "image" or self.paintingMode == "0" then
        if self.image then
            local imgPath = self.image
            if not imgPath:match("^/") then
                imgPath = LiteStep.basePath .. imgPath
            end

            local img = hs.image.imageFromPath(imgPath)
            if img then
                -- Check for 9-slice (ImageEdges)
                if self.imageEdges then
                    -- Parse "L T R B" format
                    local edges = {}
                    for edge in self.imageEdges:gmatch("%S+") do
                        table.insert(edges, tonumber(edge) or 0)
                    end

                    if #edges >= 4 then
                        local l, t, r, b = edges[1], edges[2], edges[3], edges[4]
                        local imgSize = img:size()
                        local iw, ih = imgSize.w, imgSize.h

                        -- 9-slice: draw corners (no scaling), edges (1D scale), center (2D scale)
                        -- We'll use hs.canvas image cropping capabilities

                        -- Top-left corner
                        if l > 0 and t > 0 then
                            table.insert(elements, {
                                type = "image",
                                image = img,
                                frame = {x = rect.x, y = rect.y, w = l, h = t},
                                imageAlpha = alpha,
                                imageScaling = "none",
                            })
                        end

                        -- Top-right corner
                        if r > 0 and t > 0 then
                            table.insert(elements, {
                                type = "image",
                                image = img,
                                frame = {x = rect.x + rect.w - r, y = rect.y, w = r, h = t},
                                imageAlpha = alpha,
                                imageScaling = "none",
                            })
                        end

                        -- Bottom-left corner
                        if l > 0 and b > 0 then
                            table.insert(elements, {
                                type = "image",
                                image = img,
                                frame = {x = rect.x, y = rect.y + rect.h - b, w = l, h = b},
                                imageAlpha = alpha,
                                imageScaling = "none",
                            })
                        end

                        -- Bottom-right corner
                        if r > 0 and b > 0 then
                            table.insert(elements, {
                                type = "image",
                                image = img,
                                frame = {x = rect.x + rect.w - r, y = rect.y + rect.h - b, w = r, h = b},
                                imageAlpha = alpha,
                                imageScaling = "none",
                            })
                        end

                        -- Center (stretched)
                        local centerW = rect.w - l - r
                        local centerH = rect.h - t - b
                        if centerW > 0 and centerH > 0 then
                            table.insert(elements, {
                                type = "image",
                                image = img,
                                frame = {x = rect.x + l, y = rect.y + t, w = centerW, h = centerH},
                                imageAlpha = alpha,
                                imageScaling = "scaleToFit",
                            })
                        end

                        -- Top edge (horizontal stretch)
                        if t > 0 and centerW > 0 then
                            table.insert(elements, {
                                type = "image",
                                image = img,
                                frame = {x = rect.x + l, y = rect.y, w = centerW, h = t},
                                imageAlpha = alpha,
                                imageScaling = "scaleToFit",
                            })
                        end

                        -- Bottom edge
                        if b > 0 and centerW > 0 then
                            table.insert(elements, {
                                type = "image",
                                image = img,
                                frame = {x = rect.x + l, y = rect.y + rect.h - b, w = centerW, h = b},
                                imageAlpha = alpha,
                                imageScaling = "scaleToFit",
                            })
                        end

                        -- Left edge (vertical stretch)
                        if l > 0 and centerH > 0 then
                            table.insert(elements, {
                                type = "image",
                                image = img,
                                frame = {x = rect.x, y = rect.y + t, w = l, h = centerH},
                                imageAlpha = alpha,
                                imageScaling = "scaleToFit",
                            })
                        end

                        -- Right edge
                        if r > 0 and centerH > 0 then
                            table.insert(elements, {
                                type = "image",
                                image = img,
                                frame = {x = rect.x + rect.w - r, y = rect.y + t, w = r, h = centerH},
                                imageAlpha = alpha,
                                imageScaling = "scaleToFit",
                            })
                        end
                    else
                        -- Fallback to normal image
                        table.insert(elements, {
                            type = "image",
                            image = img,
                            frame = rect,
                            imageAlpha = alpha,
                            imageScaling = self.imageMode == "tile" and "none" or "scaleToFit"
                        })
                    end
                else
                    -- No 9-slice, normal image
                    table.insert(elements, {
                        type = "image",
                        image = img,
                        frame = rect,
                        imageAlpha = alpha,
                        imageScaling = self.imageMode == "tile" and "none" or "scaleToFit"
                    })
                end

                -- Add hue tint overlay if specified
                if self.hueIntensity > 0 and self.hueColor then
                    local tintAlpha = (self.hueIntensity / 100) * alpha
                    table.insert(elements, {
                        type = "rectangle",
                        fillColor = {
                            red = self.hueColor.red,
                            green = self.hueColor.green,
                            blue = self.hueColor.blue,
                            alpha = tintAlpha
                        },
                        strokeColor = {alpha = 0},
                        frame = rect,
                        compositeRule = "multiply"
                    })
                end
            end
        end
    end

    return elements
end

--------------------------------------------------------------------------------
-- xPaintClass: TEXT
--------------------------------------------------------------------------------

local TextStyle = {}
TextStyle.__index = TextStyle

function TextStyle.new(settings, prefix)
    local self = setmetatable({}, TextStyle)

    prefix = prefix or ""
    local s = settings:createChild(prefix)

    self.font = s:getString("Font", "SF Pro Display")
    self.fontHeight = s:getInt("FontHeight", 14)
    self.fontSize = s:getInt("FontSize", self.fontHeight)
    self.fontColor = s:getColor("FontColor", {red = 1, green = 1, blue = 1, alpha = 1})
    self.fontBold = s:getBool("FontBold", false)
    self.fontItalic = s:getBool("FontItalic", false)
    self.fontUnderline = s:getBool("FontUnderline", false)
    self.fontVisible = s:getBool("FontVisible", true)

    -- Alignment
    self.fontAlign = s:getEnum("FontAlign", "left")
    self.textAlign = s:getEnum("TextAlign", self.fontAlign)
    self.fontVertAlign = s:getEnum("FontVertAlign", "center")
    self.textVerticalAlign = s:getEnum("TextVerticalAlign", self.fontVertAlign)

    -- Borders (padding)
    local borders = s:getRect({l = 0, t = 0, r = 0, b = 0})
    self.fontLeftBorder = s:getInt("FontLeftBorder", borders.l)
    self.fontTopBorder = s:getInt("FontTopBorder", borders.t)
    self.fontRightBorder = s:getInt("FontRightBorder", borders.r)
    self.fontBottomBorder = s:getInt("FontBottomBorder", borders.b)

    -- Also check TextOffset* (nModules style)
    self.textOffsetLeft = s:getInt("TextOffsetLeft", self.fontLeftBorder)
    self.textOffsetTop = s:getInt("TextOffsetTop", self.fontTopBorder)
    self.textOffsetRight = s:getInt("TextOffsetRight", self.fontRightBorder)
    self.textOffsetBottom = s:getInt("TextOffsetBottom", self.fontBottomBorder)

    -- Shadow
    self.fontShadow = s:getBool("FontShadow", false)
    self.fontShadowColor = s:getColor("FontShadowColor", {red = 0, green = 0, blue = 0, alpha = 0.5})
    self.fontShadowX = s:getInt("FontShadowX", 1)
    self.fontShadowY = s:getInt("FontShadowY", 1)

    -- Outline
    self.fontOutline = s:getBool("FontOutline", false)
    self.fontOutlineColor = s:getColor("FontOutlineColor", {red = 0, green = 0, blue = 0, alpha = 1})

    -- Alpha
    self.fontAlphaTransparency = s:getInt("FontAlphaTransparency", 255)

    -- Font weight (nModules)
    local fontWeight = s:getEnum("FontWeight", "normal")
    if fontWeight == "bold" then
        self.fontBold = true
    end

    -- Text anti-aliasing mode (nModules)
    self.textAntiAliasMode = s:getEnum("TextAntiAliasMode", "default")
    -- Values: Default, ClearType, GrayScale, Aliased

    return self
end

function TextStyle:toCanvasElements(text, rect)
    local elements = {}

    if not self.fontVisible or not text or text == "" then
        return elements
    end

    local alpha = self.fontAlphaTransparency / 255

    -- Calculate text rect with padding
    local textRect = {
        x = rect.x + self.textOffsetLeft,
        y = rect.y + self.textOffsetTop,
        w = rect.w - self.textOffsetLeft - self.textOffsetRight,
        h = rect.h - self.textOffsetTop - self.textOffsetBottom
    }

    -- Alignment
    local textAlignment = "left"
    if self.textAlign == "center" then textAlignment = "center"
    elseif self.textAlign == "right" then textAlignment = "right" end

    -- Shadow
    if self.fontShadow then
        table.insert(elements, {
            type = "text",
            text = text,
            textColor = {
                red = self.fontShadowColor.red,
                green = self.fontShadowColor.green,
                blue = self.fontShadowColor.blue,
                alpha = self.fontShadowColor.alpha * alpha
            },
            textFont = self.font,
            textSize = self.fontSize,
            textAlignment = textAlignment,
            frame = {
                x = textRect.x + self.fontShadowX,
                y = textRect.y + self.fontShadowY,
                w = textRect.w,
                h = textRect.h
            }
        })
    end

    -- Main text
    table.insert(elements, {
        type = "text",
        text = text,
        textColor = {
            red = self.fontColor.red,
            green = self.fontColor.green,
            blue = self.fontColor.blue,
            alpha = self.fontColor.alpha * alpha
        },
        textFont = self.font,
        textSize = self.fontSize,
        textAlignment = textAlignment,
        frame = textRect
    })

    return elements
end

--------------------------------------------------------------------------------
-- xPaintClass: ICON
--------------------------------------------------------------------------------

local IconStyle = {}
IconStyle.__index = IconStyle

function IconStyle.new(settings, prefix)
    local self = setmetatable({}, IconStyle)

    prefix = prefix or ""
    local s = settings:createChild(prefix)

    self.iconVisible = s:getBool("IconVisible", true)
    self.iconX = s:getInt("IconX", 4)
    self.iconY = s:getInt("IconY", 4)
    self.iconSize = s:getInt("IconSize", 16)
    self.iconAlphaTransparency = s:getInt("IconAlphaTransparency", 255)

    -- Color effects
    self.iconHueColor = s:getColor("IconHueColor", nil)
    self.iconHueIntensity = s:getInt("IconHueIntensity", 0)
    self.iconSaturationIntensity = s:getInt("IconSaturationIntensity", 100)
    self.iconLuminanceIntensity = s:getInt("IconLuminanceIntensity", 0)

    return self
end

function IconStyle:toCanvasElement(icon, baseRect)
    if not self.iconVisible or not icon then
        return nil
    end

    return {
        type = "image",
        image = icon,
        frame = {
            x = baseRect.x + self.iconX,
            y = baseRect.y + self.iconY,
            w = self.iconSize,
            h = self.iconSize
        },
        imageAlpha = self.iconAlphaTransparency / 255
    }
end

--------------------------------------------------------------------------------
-- STATE (combines texture + text + icon for a visual state)
--------------------------------------------------------------------------------

local State = {}
State.__index = State

function State.new(settings, prefix)
    local self = setmetatable({}, State)

    prefix = prefix or ""

    self.texture = Texture.new(settings, prefix)
    self.text = TextStyle.new(settings, prefix)
    self.icon = IconStyle.new(settings, prefix)

    -- Outline
    local s = settings:createChild(prefix)
    self.outlineWidth = s:getFloat("OutlineWidth", 0)
    self.outlineColor = s:getColor("OutlineColor", {red = 0.5, green = 0.5, blue = 0.5, alpha = 1})

    return self
end

--------------------------------------------------------------------------------
-- WINDOW (Drawable)
--------------------------------------------------------------------------------

local Window = {}
Window.__index = Window

function Window.new(settings, name)
    local self = setmetatable({}, Window)

    self.name = name or settings.prefix
    self.settings = settings
    self.canvas = nil
    self.children = {}
    self.parent = nil
    self.parentName = nil
    self.visible = true
    self.states = {}
    self.currentState = "base"
    self.text = ""
    self.icon = nil

    local screen = getScreenRect()

    -- Load position/size with relative support
    local xStr = settings:getString("X", "0")
    local yStr = settings:getString("Y", "0")
    local wStr = settings:getString("Width", "100")
    local hStr = settings:getString("Height", "100")

    self.x = self:parseCoordinate(xStr, screen.w, false)
    self.y = self:parseCoordinate(yStr, screen.h, true)
    self.width = self:parseDimension(wStr, screen.w)
    self.height = self:parseDimension(hStr, screen.h)

    -- Behavior
    self.alwaysOnTop = settings:getBool("AlwaysOnTop", false)
    self.clickThrough = settings:getBool("Ghosted", false)
    self.hidden = settings:getBool("Hidden", false) or settings:getBool("StartHidden", false)
    self.moveable = settings:getString("Moveable", nil)

    -- Parent
    self.parentName = settings:getString("Parent", nil)

    -- Text
    self.text = settings:getString("Text", "")

    -- Alpha fade animation
    self.alphaFade = settings:getBool("AlphaFade", false)
    local customFade = settings:getString("CustomAlphaFade", nil)
    if customFade then
        local step, delay = customFade:match("(%d+)%s+(%d+)")
        self.fadeStep = tonumber(step) or 30
        self.fadeDelay = tonumber(delay) or 10
    else
        self.fadeStep = 30
        self.fadeDelay = 10
    end

    -- Group membership
    self.group = settings:getString("AddToGroup", nil)

    -- Load base state
    self.states.base = State.new(settings, "")

    -- Event handlers
    self.events = {}
    self:loadEvents(settings)

    return self
end

function Window:parseCoordinate(str, screenSize, isY)
    if not str then return 0 end

    -- Handle tilde prefix (relative from bottom/right)
    if str:sub(1, 1) == "~" then
        local val = tonumber(str:sub(2)) or 0
        return screenSize - val
    end

    -- Handle percentage
    local percent = str:match("^(%d+)%%$")
    if percent then
        return math.floor(screenSize * tonumber(percent) / 100)
    end

    -- Handle percentage with offset: "100% - 50"
    local pct, op, offset = str:match("^(%d+)%%%s*([%+%-])%s*(%d+)$")
    if pct and op and offset then
        local base = screenSize * tonumber(pct) / 100
        if op == "+" then
            return math.floor(base + tonumber(offset))
        else
            return math.floor(base - tonumber(offset))
        end
    end

    -- Handle negative (from edge)
    local val = tonumber(str)
    if val then
        if val < 0 then
            return screenSize + val
        end
        return val
    end

    return 0
end

function Window:parseDimension(str, screenSize)
    if not str then return 100 end

    -- Handle ".image" (auto from image size)
    if str:lower() == ".image" then
        return 0 -- Will be set from image
    end

    -- Handle percentage
    local percent = str:match("^(%d+)%%$")
    if percent then
        return math.floor(screenSize * tonumber(percent) / 100)
    end

    -- Handle percentage with offset
    local pct, op, offset = str:match("^(%d+)%%%s*([%+%-])%s*(%d+)$")
    if pct and op and offset then
        local base = screenSize * tonumber(pct) / 100
        if op == "+" then
            return math.floor(base + tonumber(offset))
        else
            return math.floor(base - tonumber(offset))
        end
    end

    return tonumber(str) or 100
end

function Window:loadEvents(settings)
    local eventTypes = {
        "OnLeftClick", "OnLeftClickDown", "OnLeftClickUp", "OnLeftDoubleClick",
        "OnRightClick", "OnRightClickDown", "OnRightClickUp",
        "OnMiddleClick", "OnMiddleClickDown", "OnMiddleClickUp",
        "OnWheelUp", "OnWheelDown",
        "OnEnter", "OnLeave",
        "OnShow", "OnHide", "OnMove", "OnResize"
    }

    for _, eventType in ipairs(eventTypes) do
        local cmd = settings:getString(eventType, nil)
        if cmd then
            self.events[eventType:lower()] = cmd
        end
    end

    -- Also check *<Name>On format
    settings:iterateCommandLines("On", function(line)
        local event, modifier, cmd = line:match("^(%S+)%s+(%S+)%s+(.+)$")
        if event and cmd then
            self.events["on" .. event:lower()] = cmd
        end
    end)
end

function Window:addState(name, prefix)
    self.states[name] = State.new(self.settings, prefix)
end

function Window:setState(stateName)
    if self.states[stateName] then
        self.currentState = stateName
        self:render()
    end
end

function Window:create()
    if self.canvas then
        self.canvas:delete()
    end

    self.canvas = hs.canvas.new({
        x = self.x,
        y = self.y,
        w = self.width,
        h = self.height
    })

    if self.alwaysOnTop then
        self.canvas:level(hs.canvas.windowLevels.floating)
    end

    if self.clickThrough then
        self.canvas:clickActivating(false)
        self.canvas:canvasMouseEvents(false)
    else
        self.canvas:canvasMouseEvents(true, true, false, true)

        local this = self
        self.canvas:mouseCallback(function(canvas, event, id, x, y)
            this:handleMouseEvent(event, x, y)
        end)
    end

    self:render()

    if not self.hidden then
        self.canvas:show()
        self:fireEvent("onshow")
    end

    -- Register in global labels
    LiteStep.labels[self.name:lower()] = self

    return self
end

function Window:handleMouseEvent(event, x, y)
    if event == "mouseEnter" then
        if self.states.hover then
            self:setState("hover")
        end
        self:fireEvent("onenter")
    elseif event == "mouseExit" then
        self:setState("base")
        self:fireEvent("onleave")
    elseif event == "mouseDown" then
        if self.states.pressed then
            self:setState("pressed")
        end
        self:fireEvent("onleftclickdown")
    elseif event == "mouseUp" then
        if self.states.hover then
            self:setState("hover")
        else
            self:setState("base")
        end
        self:fireEvent("onleftclickup")
        self:fireEvent("onleftclick")
    end
end

function Window:fireEvent(eventName)
    local cmd = self.events[eventName]
    if cmd then
        LiteStep.executeBang(cmd)
    end
end

function Window:render()
    if not self.canvas then return end

    while self.canvas:elementCount() > 0 do
        self.canvas:removeElement(1)
    end

    local state = self.states[self.currentState] or self.states.base
    if not state then return end

    local rect = {x = 0, y = 0, w = self.width, h = self.height}

    -- Draw background texture
    local bgElements = state.texture:toCanvasElements(rect, self.width, self.height)
    for _, elem in ipairs(bgElements) do
        self.canvas:appendElements(elem)
    end

    -- Draw outline
    if state.outlineWidth > 0 then
        local outlineElem = {
            type = "rectangle",
            fillColor = {alpha = 0},
            strokeColor = state.outlineColor,
            strokeWidth = state.outlineWidth,
            frame = rect,
        }
        if state.texture.cornerRadiusX > 0 or state.texture.cornerRadiusY > 0 then
            outlineElem.roundedRectRadii = {
                xRadius = state.texture.cornerRadiusX,
                yRadius = state.texture.cornerRadiusY
            }
        end
        self.canvas:appendElements(outlineElem)
    end

    -- Draw icon
    if self.icon then
        local iconElem = state.icon:toCanvasElement(self.icon, rect)
        if iconElem then
            self.canvas:appendElements(iconElem)
        end
    end

    -- Draw text
    local textElements = state.text:toCanvasElements(self.text, rect)
    for _, elem in ipairs(textElements) do
        self.canvas:appendElements(elem)
    end
end

function Window:show()
    if self.canvas then
        if self.alphaFade and self.fadeStep > 0 then
            -- Fade in animation
            self.canvas:alpha(0)
            self.canvas:show()
            self.visible = true

            local currentAlpha = 0
            local targetAlpha = 1
            local step = self.fadeStep / 255
            local delay = self.fadeDelay / 1000

            if self.fadeTimer then self.fadeTimer:stop() end
            self.fadeTimer = hs.timer.doEvery(delay, function()
                currentAlpha = math.min(currentAlpha + step, targetAlpha)
                if self.canvas then
                    self.canvas:alpha(currentAlpha)
                end
                if currentAlpha >= targetAlpha then
                    if self.fadeTimer then
                        self.fadeTimer:stop()
                        self.fadeTimer = nil
                    end
                end
            end)
        else
            self.canvas:show()
            self.visible = true
        end
        self:fireEvent("onshow")
    end
end

function Window:hide()
    if self.canvas then
        if self.alphaFade and self.fadeStep > 0 then
            -- Fade out animation
            local currentAlpha = self.canvas:alpha() or 1
            local targetAlpha = 0
            local step = self.fadeStep / 255
            local delay = self.fadeDelay / 1000

            if self.fadeTimer then self.fadeTimer:stop() end
            self.fadeTimer = hs.timer.doEvery(delay, function()
                currentAlpha = math.max(currentAlpha - step, targetAlpha)
                if self.canvas then
                    self.canvas:alpha(currentAlpha)
                end
                if currentAlpha <= targetAlpha then
                    if self.fadeTimer then
                        self.fadeTimer:stop()
                        self.fadeTimer = nil
                    end
                    if self.canvas then
                        self.canvas:hide()
                        self.canvas:alpha(1) -- Reset for next show
                    end
                    self.visible = false
                end
            end)
        else
            self.canvas:hide()
            self.visible = false
        end
        self:fireEvent("onhide")
    end
end

function Window:toggle()
    if self.visible then
        self:hide()
    else
        self:show()
    end
end

function Window:destroy()
    if self.canvas then
        self.canvas:delete()
        self.canvas = nil
    end
    for _, child in ipairs(self.children) do
        child:destroy()
    end
    self.children = {}
    LiteStep.labels[self.name:lower()] = nil
end

function Window:move(x, y, steps, time)
    self.x = x
    self.y = y
    if self.canvas then
        -- TODO: Animate with steps/time
        self.canvas:topLeft({x = x, y = y})
        self:fireEvent("onmove")
    end
end

function Window:moveBy(dx, dy, steps, time)
    self:move(self.x + dx, self.y + dy, steps, time)
end

function Window:resize(w, h, steps, time)
    self.width = w
    self.height = h
    if self.canvas then
        self.canvas:size({w = w, h = h})
        self:render()
        self:fireEvent("onresize")
    end
end

function Window:resizeBy(dw, dh, steps, time)
    self:resize(self.width + dw, self.height + dh, steps, time)
end

function Window:setPosition(x, y)
    self:move(x, y)
end

function Window:setSize(w, h)
    self:resize(w, h)
end

function Window:setText(text)
    self.text = text
    self:render()
end

function Window:setAlpha(alpha, step, delay)
    if self.canvas then
        self.canvas:alpha(alpha / 255)
    end
end

--------------------------------------------------------------------------------
-- MODULE: nLabel / xLabel
--------------------------------------------------------------------------------

local Label = {}
Label.__index = Label

function Label.new(settings, name)
    local self = setmetatable({}, Label)

    self.window = Window.new(settings, name)
    self.window:addState("hover", "Hover")
    self.window:addState("pressed", "Pressed")

    -- Overlays
    self.overlays = {}
    settings:iterateCommandLines("OverlayLabel", function(line)
        -- Parse: "X Y W H Name [Mode] [Condition]"
        local parts = {}
        for part in line:gmatch("%S+") do
            table.insert(parts, part)
        end
        if #parts >= 5 then
            local overlayName = parts[5]
            local overlaySettings = Settings.new(overlayName, settings.parser)
            local overlay = Window.new(overlaySettings, overlayName)
            overlay:addState("hover", "Hover")
            overlay:addState("pressed", "Pressed")
            table.insert(self.overlays, overlay)
        end
    end)

    return self
end

function Label:create()
    self.window:create()
    for _, overlay in ipairs(self.overlays) do
        overlay:create()
    end
    return self
end

function Label:destroy()
    self.window:destroy()
    for _, overlay in ipairs(self.overlays) do
        overlay:destroy()
    end
end

--------------------------------------------------------------------------------
-- MODULE: nTaskbar / xTaskbar
--------------------------------------------------------------------------------

local Taskbar = {}
Taskbar.__index = Taskbar

function Taskbar.new(settings, name)
    local self = setmetatable({}, Taskbar)

    self.name = name
    self.settings = settings
    self.window = Window.new(settings, name)
    self.window:addState("hover", "Hover")
    self.window:addState("pressed", "Pressed")

    self.taskButtons = {}

    -- Button settings
    self.buttonWidth = settings:getInt("ButtonWidth", 150)
    self.buttonHeight = settings:getInt("ButtonHeight", 40)
    self.maxTaskWidth = settings:getInt("MaxTaskWidth", self.buttonWidth)
    self.maxTaskHeight = settings:getInt("MaxTaskHeight", self.buttonHeight)

    -- Layout
    self.layout = settings:getEnum("Layout", "horizontal")
    self.direction = settings:getEnum("Direction", "right")
    self.xSpacing = settings:getInt("xSpacing", 2)
    self.ySpacing = settings:getInt("ySpacing", 2)

    -- Borders
    local borders = settings:getRect({l = 0, t = 0, r = 0, b = 0})
    self.leftBorder = borders.l
    self.topBorder = borders.t
    self.rightBorder = borders.r
    self.bottomBorder = borders.b

    -- Display options
    self.showIcon = settings:getBool("ShowIcon", true)
    self.showText = settings:getBool("ShowText", true)
    self.hideIfEmpty = settings:getBool("HideIfEmpty", false)

    -- Button state settings
    self.buttonSettings = settings:createChild("Button")

    -- Window filter
    self.windowFilter = hs.window.filter.default

    return self
end

function Taskbar:create()
    self.window:create()
    self:updateTasks()

    self.windowFilter:subscribe({
        hs.window.filter.windowCreated,
        hs.window.filter.windowDestroyed,
        hs.window.filter.windowFocused,
        hs.window.filter.windowUnfocused,
        hs.window.filter.windowTitleChanged,
        hs.window.filter.windowMinimized,
        hs.window.filter.windowUnminimized,
    }, function()
        self:updateTasks()
    end)

    return self
end

function Taskbar:updateTasks()
    for _, btn in ipairs(self.taskButtons) do
        btn:destroy()
    end
    self.taskButtons = {}

    local windows = hs.window.visibleWindows()
    local x = self.leftBorder
    local y = self.topBorder
    local focusedWin = hs.window.focusedWindow()

    for i, win in ipairs(windows) do
        if win:isStandard() then
            local btnSettings = Settings.new(self.name .. "Button", self.settings.parser)
            local btn = Window.new(btnSettings, self.name .. "Button" .. i)

            btn.x = self.window.x + x
            btn.y = self.window.y + y
            btn.width = self.maxTaskWidth
            btn.height = self.maxTaskHeight

            -- States
            btn.states.base = State.new(self.settings, "Button")
            btn.states.hover = State.new(self.settings, "ButtonHover")
            btn.states.pressed = State.new(self.settings, "ButtonPressed")

            -- Active state for focused window
            if focusedWin and win:id() == focusedWin:id() then
                btn.states.base = State.new(self.settings, "ButtonActive")
            end

            -- Minimized state
            if win:isMinimized() then
                btn.states.base = State.new(self.settings, "ButtonMinimized")
            end

            -- Text and icon
            if self.showText then
                btn.text = win:title():sub(1, 25)
            end
            if self.showIcon then
                local app = win:application()
                if app then
                    btn.icon = hs.image.imageFromAppBundle(app:bundleID())
                end
            end

            -- Click handler
            local targetWin = win
            btn.events["onleftclick"] = function()
                if targetWin:isMinimized() then
                    targetWin:unminimize()
                end
                targetWin:focus()
            end

            btn:create()
            table.insert(self.taskButtons, btn)

            -- Advance position
            if self.layout == "horizontal" then
                x = x + self.maxTaskWidth + self.xSpacing
            else
                y = y + self.maxTaskHeight + self.ySpacing
            end
        end
    end

    -- Handle hideIfEmpty
    if self.hideIfEmpty then
        if #self.taskButtons == 0 then
            self.window:hide()
        else
            self.window:show()
        end
    end
end

function Taskbar:destroy()
    self.window:destroy()
    for _, btn in ipairs(self.taskButtons) do
        btn:destroy()
    end
    self.taskButtons = {}
    self.windowFilter:unsubscribeAll()
end

--------------------------------------------------------------------------------
-- MODULE: nClock (Analog clock with rotating hands)
--------------------------------------------------------------------------------

local Clock = {}
Clock.__index = Clock

function Clock.new(settings, name)
    local self = setmetatable({}, Clock)

    self.name = name
    self.settings = settings
    self.window = Window.new(settings, name)

    -- Clock hands configuration
    self.hands = {}

    -- Hour hand
    local hourSettings = settings:createChild("HourHand")
    self.hands.hour = {
        brush = Texture.new(settings, "HourHand"),
        length = hourSettings:getInt("Length", 30),
        thickness = hourSettings:getInt("Thickness", 8),
        offset = hourSettings:getInt("Offset", 0),
        smooth = hourSettings:getBool("SmoothMovement", false),
    }

    -- Minute hand
    local minuteSettings = settings:createChild("MinuteHand")
    self.hands.minute = {
        brush = Texture.new(settings, "MinuteHand"),
        length = minuteSettings:getInt("Length", 40),
        thickness = minuteSettings:getInt("Thickness", 6),
        offset = minuteSettings:getInt("Offset", 0),
        smooth = minuteSettings:getBool("SmoothMovement", false),
    }

    -- Second hand
    local secondSettings = settings:createChild("SecondHand")
    self.hands.second = {
        brush = Texture.new(settings, "SecondHand"),
        length = secondSettings:getInt("Length", 45),
        thickness = secondSettings:getInt("Thickness", 2),
        offset = secondSettings:getInt("Offset", 0),
        visible = secondSettings:getBool("Visible", true),
    }

    -- Center point
    self.centerX = settings:getInt("CenterX", self.window.width / 2)
    self.centerY = settings:getInt("CenterY", self.window.height / 2)

    -- Time offset
    self.timeOffset = settings:getInt("TimeOffset", 0)

    -- Update timer
    self.timer = nil

    return self
end

function Clock:create()
    self.window:create()

    -- Start update timer
    self.timer = hs.timer.doEvery(1, function()
        self:updateHands()
    end)

    self:updateHands()
    return self
end

function Clock:updateHands()
    if not self.window.canvas then return end

    local time = os.date("*t")
    local hours = time.hour % 12
    local minutes = time.min
    local seconds = time.sec

    -- Calculate angles (0 = 12 o'clock, clockwise)
    local hourAngle = (hours + minutes / 60) * 30 -- 360/12 = 30 degrees per hour
    local minuteAngle = (minutes + seconds / 60) * 6 -- 360/60 = 6 degrees per minute
    local secondAngle = seconds * 6

    -- Convert to radians (0 = up, clockwise)
    local hourRad = math.rad(hourAngle - 90)
    local minuteRad = math.rad(minuteAngle - 90)
    local secondRad = math.rad(secondAngle - 90)

    -- Re-render background first
    self.window:render()

    local cx = self.centerX
    local cy = self.centerY

    -- Draw hour hand
    if self.hands.hour.length > 0 then
        local len = self.hands.hour.length
        local thick = self.hands.hour.thickness
        local x2 = cx + math.cos(hourRad) * len
        local y2 = cy + math.sin(hourRad) * len

        self.window.canvas:appendElements({
            type = "segments",
            coordinates = {{x = cx, y = cy}, {x = x2, y = y2}},
            strokeColor = self.hands.hour.brush.color,
            strokeWidth = thick,
            strokeCapStyle = "round",
        })
    end

    -- Draw minute hand
    if self.hands.minute.length > 0 then
        local len = self.hands.minute.length
        local thick = self.hands.minute.thickness
        local x2 = cx + math.cos(minuteRad) * len
        local y2 = cy + math.sin(minuteRad) * len

        self.window.canvas:appendElements({
            type = "segments",
            coordinates = {{x = cx, y = cy}, {x = x2, y = y2}},
            strokeColor = self.hands.minute.brush.color,
            strokeWidth = thick,
            strokeCapStyle = "round",
        })
    end

    -- Draw second hand
    if self.hands.second.visible and self.hands.second.length > 0 then
        local len = self.hands.second.length
        local thick = self.hands.second.thickness
        local x2 = cx + math.cos(secondRad) * len
        local y2 = cy + math.sin(secondRad) * len

        self.window.canvas:appendElements({
            type = "segments",
            coordinates = {{x = cx, y = cy}, {x = x2, y = y2}},
            strokeColor = self.hands.second.brush.color,
            strokeWidth = thick,
            strokeCapStyle = "round",
        })
    end
end

function Clock:destroy()
    if self.timer then
        self.timer:stop()
        self.timer = nil
    end
    self.window:destroy()
end

--------------------------------------------------------------------------------
-- MODULE: nPopup (Context menus)
--------------------------------------------------------------------------------

local Popup = {}
Popup.__index = Popup

LiteStep.popups = {}
LiteStep.popupMenus = {} -- Menu definitions

function Popup.new(settings, name)
    local self = setmetatable({}, Popup)

    self.name = name
    self.settings = settings
    self.visible = false
    self.pinned = false
    self.canvas = nil
    self.entries = {}
    self.activeEntry = nil

    -- Position & size
    self.x = settings:getInt("X", 0)
    self.y = settings:getInt("Y", 0)
    self.maxWidth = settings:getInt("MaxWidth", 300)
    self.maxHeight = settings:getInt("MaxHeight", 600)
    self.minWidth = settings:getInt("MinWidth", 100)

    -- Borders
    self.leftBorder = settings:getInt("LeftBorder", 5)
    self.topBorder = settings:getInt("TopBorder", 5)
    self.rightBorder = settings:getInt("RightBorder", 5)
    self.bottomBorder = settings:getInt("BottomBorder", 5)

    -- Entry dimensions
    self.entryHeight = settings:getInt("EntryHeight", 22)
    self.separatorHeight = settings:getInt("SeparatorHeight", 5)
    self.xSpacing = settings:getInt("xSpacing", 0)
    self.ySpacing = settings:getInt("ySpacing", 2)

    -- Appearance
    self.alphaTransparency = settings:getInt("AlphaTransparency", 255) / 255

    -- Textures
    self.popupTexture = Texture.new(settings, "Popup")
    self.entryTexture = Texture.new(settings, "Entry")
    self.activeEntryTexture = Texture.new(settings, "ActiveEntry")
    self.separatorTexture = Texture.new(settings, "Separator")
    self.titleTexture = Texture.new(settings, "Title")

    -- Text styles
    self.entryText = TextStyle.new(settings, "Entry")
    self.activeEntryText = TextStyle.new(settings, "ActiveEntry")
    self.titleText = TextStyle.new(settings, "Title")

    -- Behavior
    self.autoHide = settings:getBool("AutoHide", true)
    self.hideDelay = settings:getInt("HideDelay", 250)
    self.closeAfterAction = settings:getBool("CloseAfterAction", true)

    -- Events
    self.onOpen = settings:getString("OnOpen", nil)
    self.onClose = settings:getString("OnClose", nil)

    self.hideTimer = nil

    return self
end

function Popup:loadEntries()
    -- Load from *Popup <name> lines
    if LiteStep.parser then
        local popupKey = "popup" .. self.name:lower()
        local lines = LiteStep.parser.commandLines[popupKey]
        if lines then
            for _, line in ipairs(lines) do
                self:parseEntry(line)
            end
        end
    end
end

function Popup:parseEntry(line)
    -- Format: Icon Caption !Action
    -- Or: - - - for separator
    local icon, caption, action = line:match('^"?([^"]*)"?%s+"?([^"]*)"?%s+(.+)$')
    if not icon then
        -- Try simpler format
        icon, caption, action = line:match("^(%S+)%s+(%S+)%s+(.+)$")
    end

    if icon == "-" or caption == "-" then
        table.insert(self.entries, {type = "separator"})
    elseif caption and action then
        table.insert(self.entries, {
            type = "entry",
            icon = icon ~= "." and icon or nil,
            caption = caption,
            action = action,
        })
    end
end

function Popup:addEntry(caption, action, icon)
    table.insert(self.entries, {
        type = "entry",
        icon = icon,
        caption = caption,
        action = action,
    })
end

function Popup:addSeparator()
    table.insert(self.entries, {type = "separator"})
end

function Popup:calculateSize()
    local width = self.minWidth
    local height = self.topBorder + self.bottomBorder

    for _, entry in ipairs(self.entries) do
        if entry.type == "separator" then
            height = height + self.separatorHeight + self.ySpacing
        else
            height = height + self.entryHeight + self.ySpacing
            -- Could calculate text width here for auto-width
        end
    end

    self.width = math.min(width, self.maxWidth)
    self.height = math.min(height, self.maxHeight)
end

function Popup:show(x, y)
    if x then self.x = x end
    if y then self.y = y end

    self:calculateSize()

    -- Create canvas
    if self.canvas then
        self.canvas:delete()
    end

    self.canvas = hs.canvas.new({
        x = self.x,
        y = self.y,
        w = self.width,
        h = self.height
    })

    self.canvas:level(hs.canvas.windowLevels.popUpMenu)
    self.canvas:alpha(self.alphaTransparency)

    -- Enable mouse tracking
    self.canvas:canvasMouseEvents(true, true, false, true)

    local this = self
    self.canvas:mouseCallback(function(canvas, event, id, mx, my)
        this:handleMouse(event, mx, my)
    end)

    self:render()
    self.canvas:show()
    self.visible = true

    -- Fire onOpen event
    if self.onOpen then
        LiteStep.executeBang(self.onOpen)
    end

    -- Export position variables
    if LiteStep.parser then
        LiteStep.parser.variables[self.name:lower() .. "currentx"] = self.x
        LiteStep.parser.variables[self.name:lower() .. "currenty"] = self.y
    end

    LiteStep.popups[self.name:lower()] = self
end

function Popup:hide()
    if self.canvas then
        self.canvas:hide()
        self.canvas:delete()
        self.canvas = nil
    end
    self.visible = false

    if self.hideTimer then
        self.hideTimer:stop()
        self.hideTimer = nil
    end

    -- Fire onClose event
    if self.onClose then
        LiteStep.executeBang(self.onClose)
    end

    LiteStep.popups[self.name:lower()] = nil
end

function Popup:toggle(x, y)
    if self.visible then
        self:hide()
    else
        self:show(x, y)
    end
end

function Popup:handleMouse(event, mx, my)
    if event == "mouseExit" then
        if self.autoHide and not self.pinned then
            self.hideTimer = hs.timer.doAfter(self.hideDelay / 1000, function()
                self:hide()
            end)
        end
        self.activeEntry = nil
        self:render()
    elseif event == "mouseEnter" then
        if self.hideTimer then
            self.hideTimer:stop()
            self.hideTimer = nil
        end
    elseif event == "mouseUp" then
        local entry = self:getEntryAt(my)
        if entry and entry.type == "entry" and entry.action then
            LiteStep.executeBang(entry.action)
            if self.closeAfterAction then
                self:hide()
            end
        end
    else
        -- Track hover
        local entry = self:getEntryAt(my)
        if entry ~= self.activeEntry then
            self.activeEntry = entry
            self:render()
        end
    end
end

function Popup:getEntryAt(y)
    local currentY = self.topBorder

    for _, entry in ipairs(self.entries) do
        local entryH = entry.type == "separator" and self.separatorHeight or self.entryHeight

        if y >= currentY and y < currentY + entryH then
            return entry
        end

        currentY = currentY + entryH + self.ySpacing
    end

    return nil
end

function Popup:render()
    if not self.canvas then return end

    while self.canvas:elementCount() > 0 do
        self.canvas:removeElement(1)
    end

    local rect = {x = 0, y = 0, w = self.width, h = self.height}

    -- Draw popup background
    local bgElements = self.popupTexture:toCanvasElements(rect, self.width, self.height)
    for _, elem in ipairs(bgElements) do
        self.canvas:appendElements(elem)
    end

    -- Draw entries
    local y = self.topBorder

    for _, entry in ipairs(self.entries) do
        if entry.type == "separator" then
            local sepRect = {
                x = self.leftBorder,
                y = y,
                w = self.width - self.leftBorder - self.rightBorder,
                h = self.separatorHeight
            }
            local sepElements = self.separatorTexture:toCanvasElements(sepRect, self.width, self.height)
            for _, elem in ipairs(sepElements) do
                self.canvas:appendElements(elem)
            end
            y = y + self.separatorHeight + self.ySpacing
        else
            local entryRect = {
                x = self.leftBorder,
                y = y,
                w = self.width - self.leftBorder - self.rightBorder,
                h = self.entryHeight
            }

            local isActive = (entry == self.activeEntry)
            local texture = isActive and self.activeEntryTexture or self.entryTexture
            local textStyle = isActive and self.activeEntryText or self.entryText

            -- Draw entry background
            local entryElements = texture:toCanvasElements(entryRect, self.width, self.height)
            for _, elem in ipairs(entryElements) do
                self.canvas:appendElements(elem)
            end

            -- Draw entry text
            local textElements = textStyle:toCanvasElements(entry.caption or "", entryRect)
            for _, elem in ipairs(textElements) do
                self.canvas:appendElements(elem)
            end

            y = y + self.entryHeight + self.ySpacing
        end
    end
end

function Popup:destroy()
    self:hide()
end

--------------------------------------------------------------------------------
-- MODULE: nDesk (Desktop click handlers)
--------------------------------------------------------------------------------

local Desk = {}
Desk.__index = Desk

function Desk.new(settings, name)
    local self = setmetatable({}, Desk)

    self.name = name or "nDesk"
    self.settings = settings
    self.eventTap = nil
    self.events = {}

    -- Load event handlers from *nDeskOn lines
    if LiteStep.parser then
        local deskOnLines = LiteStep.parser.commandLines["ndeskon"]
        if deskOnLines then
            for _, line in ipairs(deskOnLines) do
                local event, modifier, cmd = line:match("^(%S+)%s+(%S+)%s+(.+)$")
                if event and cmd then
                    self.events[event:lower()] = {
                        modifier = modifier,
                        command = cmd
                    }
                end
            end
        end
    end

    return self
end

function Desk:create()
    -- Create event tap for desktop clicks
    self.eventTap = hs.eventtap.new({
        hs.eventtap.event.types.rightMouseUp,
        hs.eventtap.event.types.leftMouseUp,
        hs.eventtap.event.types.otherMouseUp,
    }, function(event)
        return self:handleClick(event)
    end)

    self.eventTap:start()
    return self
end

function Desk:handleClick(event)
    -- Check if click is on desktop (no window under cursor)
    local pos = hs.mouse.absolutePosition()
    local windowUnderMouse = hs.window.find(function(w)
        local frame = w:frame()
        return pos.x >= frame.x and pos.x <= frame.x + frame.w
           and pos.y >= frame.y and pos.y <= frame.y + frame.h
           and w:isVisible() and w:isStandard()
    end)

    -- If there's a window under the mouse, don't handle
    if windowUnderMouse then
        return false
    end

    local eventType = event:getType()
    local eventName = nil

    if eventType == hs.eventtap.event.types.rightMouseUp then
        eventName = "rightclickup"
    elseif eventType == hs.eventtap.event.types.leftMouseUp then
        eventName = "leftclickup"
    elseif eventType == hs.eventtap.event.types.otherMouseUp then
        eventName = "middleclickup"
    end

    if eventName and self.events[eventName] then
        local handler = self.events[eventName]
        local cmd = handler.command

        -- Expand runtime variables
        cmd = self:expandRuntimeVars(cmd)

        LiteStep.executeBang(cmd)
        return true -- Consume event
    end

    return false
end

function Desk:expandRuntimeVars(cmd)
    local pos = hs.mouse.absolutePosition()

    -- Replace %{mousex}% and %{mousey}%
    cmd = cmd:gsub("%%{mousex}%%", tostring(math.floor(pos.x)))
    cmd = cmd:gsub("%%{mousey}%%", tostring(math.floor(pos.y)))

    -- Replace %#expr%# with evaluated expression
    cmd = cmd:gsub("%%#([^%%]+)%%#", function(expr)
        -- Substitute variables first
        expr = expr:gsub("mousex", tostring(math.floor(pos.x)))
        expr = expr:gsub("mousey", tostring(math.floor(pos.y)))

        -- Substitute other variables
        if LiteStep.parser then
            expr = expr:gsub("([%a_][%w_]*)", function(varName)
                local val = LiteStep.parser.variables[varName:lower()]
                if val then return tostring(val) end
                return varName
            end)
        end

        -- Evaluate expression
        local result = evaluateMathExpression(expr, LiteStep.parser and LiteStep.parser.variables or {})
        if result then
            return tostring(math.floor(result))
        end
        return expr
    end)

    return cmd
end

function Desk:destroy()
    if self.eventTap then
        self.eventTap:stop()
        self.eventTap = nil
    end
end

--------------------------------------------------------------------------------
-- PARENT/CHILD Window Relationships
--------------------------------------------------------------------------------

-- Track parent-child relationships
LiteStep.windowParents = {}

function LiteStep.setWindowParent(childName, parentName)
    LiteStep.windowParents[childName:lower()] = parentName:lower()
end

function LiteStep.updateChildPositions(parentName)
    local parentLower = parentName:lower()
    local parent = LiteStep.labels[parentLower]
    if not parent then return end

    local parentWin = parent.window or parent
    if not parentWin then return end

    for childName, pName in pairs(LiteStep.windowParents) do
        if pName == parentLower then
            local child = LiteStep.labels[childName]
            if child then
                local childWin = child.window or child
                if childWin and childWin.relativeX and childWin.relativeY then
                    childWin:setPosition(
                        parentWin.x + childWin.relativeX,
                        parentWin.y + childWin.relativeY
                    )
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- DYNAMIC VARIABLES (%{var}% and %#expr%#)
--------------------------------------------------------------------------------

-- Get current mouse position
function LiteStep.getMouseX()
    return math.floor(hs.mouse.absolutePosition().x)
end

function LiteStep.getMouseY()
    return math.floor(hs.mouse.absolutePosition().y)
end

-- Expand runtime variables in a string
function LiteStep.expandRuntimeVars(str)
    if not str then return str end

    local pos = hs.mouse.absolutePosition()

    -- %{mousex}% and %{mousey}%
    str = str:gsub("%%{mousex}%%", tostring(math.floor(pos.x)))
    str = str:gsub("%%{mousey}%%", tostring(math.floor(pos.y)))

    -- %{screenwidth}% and %{screenheight}%
    local screen = getScreenRect()
    str = str:gsub("%%{screenwidth}%%", tostring(screen.w))
    str = str:gsub("%%{screenheight}%%", tostring(screen.h))

    -- %#expr%# runtime expression evaluation
    str = str:gsub("%%#([^%%]+)%%#", function(expr)
        -- Replace dynamic vars in expression
        expr = expr:gsub("mousex", tostring(math.floor(pos.x)))
        expr = expr:gsub("mousey", tostring(math.floor(pos.y)))

        -- Substitute variables
        if LiteStep.parser then
            expr = expr:gsub("([%a_][%w_]*)", function(varName)
                local val = LiteStep.parser.variables[varName:lower()]
                if val then return tostring(val) end
                return varName
            end)
        end

        -- Evaluate
        local result = evaluateMathExpression(expr, LiteStep.parser and LiteStep.parser.variables or {})
        if result then
            return tostring(math.floor(result))
        end
        return expr
    end)

    return str
end

--------------------------------------------------------------------------------
-- BANG COMMANDS
--------------------------------------------------------------------------------

function LiteStep.registerBangCommand(name, handler)
    LiteStep.bangCommands[name:lower()] = handler
end

function LiteStep.executeBang(cmd)
    if not cmd then return end

    -- Expand runtime variables (%{mousex}%, %#expr%#, etc.)
    cmd = LiteStep.expandRuntimeVars(cmd)

    -- Handle compound commands: !Execute [cmd1][cmd2]
    if cmd:match("^!Execute%s+") then
        local inner = cmd:match("^!Execute%s+(.+)$")
        if inner then
            for subCmd in inner:gmatch("%[([^%]]+)%]") do
                LiteStep.executeBang(subCmd)
            end
        end
        return
    end

    -- Parse: !BangName args
    local bangName, args = cmd:match("^!(%S+)%s*(.*)$")
    if not bangName then return end

    local handler = LiteStep.bangCommands[bangName:lower()]
    if handler then
        handler(args)
    else
        print("LiteStep: Unknown bang command: !" .. bangName)
    end
end

-- Register standard bang commands
LiteStep.registerBangCommand("LabelShow", function(args)
    local name = args:match("^(%S+)")
    if name then
        local label = LiteStep.labels[name:lower()]
        if label then
            if label.window then label.window:show()
            elseif label.show then label:show() end
        end
    end
end)

LiteStep.registerBangCommand("LabelHide", function(args)
    local name = args:match("^(%S+)")
    if name then
        local label = LiteStep.labels[name:lower()]
        if label then
            if label.window then label.window:hide()
            elseif label.hide then label:hide() end
        end
    end
end)

LiteStep.registerBangCommand("LabelToggle", function(args)
    local name = args:match("^(%S+)")
    if name then
        local label = LiteStep.labels[name:lower()]
        if label then
            if label.window then label.window:toggle()
            elseif label.toggle then label:toggle() end
        end
    end
end)

LiteStep.registerBangCommand("LabelMove", function(args)
    local name, x, y = args:match("^(%S+)%s+(%S+)%s+(%S+)")
    if name and x and y then
        local label = LiteStep.labels[name:lower()]
        if label then
            local win = label.window or label
            win:move(tonumber(x) or 0, tonumber(y) or 0)
        end
    end
end)

LiteStep.registerBangCommand("LabelMoveBy", function(args)
    local name, dx, dy = args:match("^(%S+)%s+(%S+)%s+(%S+)")
    if name and dx and dy then
        local label = LiteStep.labels[name:lower()]
        if label then
            local win = label.window or label
            win:moveBy(tonumber(dx) or 0, tonumber(dy) or 0)
        end
    end
end)

LiteStep.registerBangCommand("LabelSetText", function(args)
    local name, text = args:match('^(%S+)%s+"([^"]*)"')
    if not name then
        name, text = args:match("^(%S+)%s+(.+)$")
    end
    if name and text then
        local label = LiteStep.labels[name:lower()]
        if label then
            local win = label.window or label
            win:setText(text)
        end
    end
end)

LiteStep.registerBangCommand("LabelSetAlpha", function(args)
    local name, alpha = args:match("^(%S+)%s+(%d+)")
    if name and alpha then
        local label = LiteStep.labels[name:lower()]
        if label then
            local win = label.window or label
            win:setAlpha(tonumber(alpha) or 255)
        end
    end
end)

LiteStep.registerBangCommand("LabelRefresh", function(args)
    local name = args:match("^(%S+)")
    if name then
        local label = LiteStep.labels[name:lower()]
        if label then
            local win = label.window or label
            win:render()
        end
    end
end)

-- Group management - store groups
LiteStep.groups = {}

-- Helper to get all labels in a group
local function getGroupLabels(groupName)
    groupName = groupName:lower()
    local labels = {}
    for name, label in pairs(LiteStep.labels) do
        local win = label.window or label
        if win.group and win.group:lower() == groupName then
            table.insert(labels, label)
        end
    end
    return labels
end

-- !GroupShow - show all labels in a group
LiteStep.registerBangCommand("GroupShow", function(args)
    local groupName = args:match("^(%S+)")
    if groupName then
        for _, label in ipairs(getGroupLabels(groupName)) do
            local win = label.window or label
            win:show()
        end
    end
end)

-- !GroupHide - hide all labels in a group
LiteStep.registerBangCommand("GroupHide", function(args)
    local groupName = args:match("^(%S+)")
    if groupName then
        for _, label in ipairs(getGroupLabels(groupName)) do
            local win = label.window or label
            win:hide()
        end
    end
end)

-- !GroupToggle - toggle visibility of all labels in a group
LiteStep.registerBangCommand("GroupToggle", function(args)
    local groupName = args:match("^(%S+)")
    if groupName then
        for _, label in ipairs(getGroupLabels(groupName)) do
            local win = label.window or label
            win:toggle()
        end
    end
end)

-- !GroupMove - move all labels in a group
LiteStep.registerBangCommand("GroupMove", function(args)
    local groupName, x, y = args:match("^(%S+)%s+(%S+)%s+(%S+)")
    if groupName and x and y then
        for _, label in ipairs(getGroupLabels(groupName)) do
            local win = label.window or label
            win:move(tonumber(x) or 0, tonumber(y) or 0)
        end
    end
end)

-- !GroupMoveBy - move all labels in a group by offset
LiteStep.registerBangCommand("GroupMoveBy", function(args)
    local groupName, dx, dy = args:match("^(%S+)%s+(%S+)%s+(%S+)")
    if groupName and dx and dy then
        for _, label in ipairs(getGroupLabels(groupName)) do
            local win = label.window or label
            win:moveBy(tonumber(dx) or 0, tonumber(dy) or 0)
        end
    end
end)

-- !GroupSetAlpha - set alpha for all labels in a group
LiteStep.registerBangCommand("GroupSetAlpha", function(args)
    local groupName, alpha = args:match("^(%S+)%s+(%d+)")
    if groupName and alpha then
        for _, label in ipairs(getGroupLabels(groupName)) do
            local win = label.window or label
            win:setAlpha(tonumber(alpha) or 255)
        end
    end
end)

-- Exec command
LiteStep.registerBangCommand("Exec", function(args)
    if args then
        hs.execute(args)
    end
end)

-- !Recycle - reload the theme
LiteStep.registerBangCommand("Recycle", function(args)
    LiteStep.destroyAll()
    if LiteStep.lastThemeFile then
        LiteStep.init(LiteStep.lastThemeFile)
    end
end)

-- !Refresh - refresh all labels
LiteStep.registerBangCommand("Refresh", function(args)
    for _, label in pairs(LiteStep.labels) do
        local win = label.window or label
        win:render()
    end
end)

-- !Quit - quit the application
LiteStep.registerBangCommand("Quit", function(args)
    LiteStep.destroyAll()
end)

-- !Alert - show an alert message
LiteStep.registerBangCommand("Alert", function(args)
    if args then
        hs.alert.show(args, 3)
    end
end)

-- !Confirm - show a confirmation dialog
LiteStep.registerBangCommand("Confirm", function(args)
    -- Parse: "message" yesCommand noCommand
    local message, yesCmd, noCmd = args:match('^"([^"]+)"%s+(.-)%s*|%s*(.*)$')
    if not message then
        message = args
    end
    if message then
        hs.dialog.alert(100, 100, function(result)
            if result == "OK" and yesCmd then
                LiteStep.executeBang(yesCmd)
            elseif noCmd then
                LiteStep.executeBang(noCmd)
            end
        end, message, "Confirm", "OK", "Cancel")
    end
end)

-- !Run - run a command/application
LiteStep.registerBangCommand("Run", function(args)
    if args then
        hs.execute("open " .. args)
    end
end)

-- !Open - open a file/URL
LiteStep.registerBangCommand("Open", function(args)
    if args then
        hs.urlevent.openURL(args)
    end
end)

-- !FocusCommand - focus the command input (noop for now, just for compatibility)
LiteStep.registerBangCommand("FocusCommand", function(args)
    -- This would focus a command input box in original LiteStep
    -- For compatibility, we can trigger Spotlight
    hs.eventtap.keyStroke({"cmd"}, "space")
end)

-- !MinuteUpdate - compatibility bang (usually triggers time-based updates)
LiteStep.registerBangCommand("MinuteUpdate", function(args)
    -- Update all labels that have time-based text
    for _, label in pairs(LiteStep.labels) do
        local win = label.window or label
        win:render()
    end
end)

-- xTray commands (stub implementations for compatibility)
LiteStep.registerBangCommand("xTrayShow", function(args)
    local label = LiteStep.labels["xtray"]
    if label then
        local win = label.window or label
        win:show()
    end
end)

LiteStep.registerBangCommand("xTrayHide", function(args)
    local label = LiteStep.labels["xtray"]
    if label then
        local win = label.window or label
        win:hide()
    end
end)

LiteStep.registerBangCommand("xTrayMove", function(args)
    local x, y = args:match("^(%S+)%s+(%S+)")
    if x and y then
        local label = LiteStep.labels["xtray"]
        if label then
            local win = label.window or label
            win:move(tonumber(x) or 0, tonumber(y) or 0)
        end
    end
end)

LiteStep.registerBangCommand("xTrayResize", function(args)
    local parts = {}
    for part in args:gmatch("%S+") do
        table.insert(parts, tonumber(part) or 0)
    end
    if #parts >= 2 then
        local label = LiteStep.labels["xtray"]
        if label then
            local win = label.window or label
            win:resize(parts[1], parts[2])
        end
    end
end)

LiteStep.registerBangCommand("xTrayAlwaysOnTop", function(args)
    local enable = args:lower() == "true" or args == "1"
    local label = LiteStep.labels["xtray"]
    if label then
        local win = label.window or label
        if win.canvas then
            win.canvas:level(enable and hs.canvas.windowLevels.floating or hs.canvas.windowLevels.normal)
        end
    end
end)

-- Task management stubs for compatibility
LiteStep.registerBangCommand("TasksAdd", function(args)
    -- Stub for task added event
end)

LiteStep.registerBangCommand("TasksDel", function(args)
    -- Stub for task deleted event
end)

-- Popup commands
LiteStep.registerBangCommand("PopUp", function(args)
    -- !PopUp [x] [y] or !PopUp MenuName [x] [y]
    local x, y, name

    -- Parse arguments
    local parts = {}
    for part in args:gmatch("%S+") do
        table.insert(parts, part)
    end

    if #parts == 0 then
        -- No args - show default popup at mouse position
        local pos = hs.mouse.absolutePosition()
        x, y = pos.x, pos.y
        name = "popup"
    elseif #parts == 2 and tonumber(parts[1]) then
        -- !PopUp x y
        x, y = tonumber(parts[1]), tonumber(parts[2])
        name = "popup"
    elseif #parts >= 1 then
        -- !PopUp MenuName [x] [y]
        name = parts[1]
        if #parts >= 3 then
            x, y = tonumber(parts[2]), tonumber(parts[3])
        else
            local pos = hs.mouse.absolutePosition()
            x, y = pos.x, pos.y
        end
    end

    -- Find or create popup
    local popup = LiteStep.popups[name:lower()]
    if not popup then
        local settings = LiteStep.createSettings(name)
        if settings then
            popup = Popup.new(settings, name)
            popup:loadEntries()
        end
    end

    if popup then
        popup:show(x, y)
    end
end)

LiteStep.registerBangCommand("PopUpHide", function(args)
    local name = args:match("^(%S+)")
    if name then
        local popup = LiteStep.popups[name:lower()]
        if popup then popup:hide() end
    else
        -- Hide all popups
        for _, popup in pairs(LiteStep.popups) do
            popup:hide()
        end
    end
end)

LiteStep.registerBangCommand("PopUpToggle", function(args)
    local parts = {}
    for part in args:gmatch("%S+") do
        table.insert(parts, part)
    end

    local name = parts[1] or "popup"
    local x = parts[2] and tonumber(parts[2])
    local y = parts[3] and tonumber(parts[3])

    local popup = LiteStep.popups[name:lower()]
    if popup and popup.visible then
        popup:hide()
    else
        LiteStep.executeBang("!PopUp " .. args)
    end
end)

--------------------------------------------------------------------------------
-- MODULE: Alias
--------------------------------------------------------------------------------

LiteStep.aliases = {}

-- Parse alias definition: [defaults] !AliasName format with %1 %2 etc.
local function parseAliasDefinition(line)
    local defaults = {}
    local aliasName = nil
    local format = nil

    -- Find the bang name
    local bangStart = line:find("!")
    if not bangStart then return nil end

    -- Extract defaults (everything before the bang)
    local defaultsStr = line:sub(1, bangStart - 1):match("^%s*(.-)%s*$")
    if defaultsStr and defaultsStr ~= "" then
        for token in defaultsStr:gmatch("%S+") do
            table.insert(defaults, token)
        end
    end

    -- Extract alias name and format
    local rest = line:sub(bangStart)
    aliasName = rest:match("^(!%S+)")
    if aliasName then
        format = rest:sub(#aliasName + 1):match("^%s*(.-)%s*$")
    end

    if aliasName and format then
        return {
            name = aliasName,
            format = format,
            defaults = defaults,
            numVars = 0
        }
    end
    return nil
end

-- Count the highest %N parameter in the format string
local function countAliasVariables(format)
    local highest = 0
    for num in format:gmatch("%%(%d+)") do
        local n = tonumber(num)
        if n and n > highest then
            highest = n
        end
    end
    return highest
end

-- Execute an alias with given arguments
local function executeAlias(alias, args)
    -- Parse arguments
    local argList = {}
    local remaining = args or ""

    while remaining ~= "" do
        local token, rest
        remaining = remaining:match("^%s*(.-)%s*$") or ""
        if remaining == "" then break end

        if remaining:sub(1, 1) == '"' then
            local endQuote = remaining:find('"', 2, true)
            if endQuote then
                token = remaining:sub(2, endQuote - 1)
                rest = remaining:sub(endQuote + 1)
            else
                token = remaining:sub(2)
                rest = ""
            end
        else
            local space = remaining:find("%s")
            if space then
                token = remaining:sub(1, space - 1)
                rest = remaining:sub(space + 1)
            else
                token = remaining
                rest = ""
            end
        end

        table.insert(argList, token)
        remaining = rest
    end

    -- Fill in defaults for missing arguments
    for i = #argList + 1, alias.numVars do
        local defaultIdx = i - #argList
        if alias.defaults[defaultIdx] then
            table.insert(argList, alias.defaults[defaultIdx])
        else
            table.insert(argList, "")
        end
    end

    -- Substitute %1, %2, etc. in format string
    local result = alias.format
    for i, arg in ipairs(argList) do
        result = result:gsub("%%" .. i, arg)
    end

    -- Execute the resulting command
    LiteStep.executeBang(result)
end

-- !Alias bang command - define a new alias
LiteStep.registerBangCommand("Alias", function(args)
    local alias = parseAliasDefinition(args)
    if alias then
        alias.numVars = countAliasVariables(alias.format)
        LiteStep.aliases[alias.name:lower()] = alias

        -- Register the bang command
        local aliasName = alias.name:sub(2) -- Remove the !
        LiteStep.registerBangCommand(aliasName, function(bangArgs)
            executeAlias(alias, bangArgs)
        end)
    end
end)

-- Load aliases from *Alias lines after theme load
function LiteStep.loadAliases()
    if not LiteStep.parser then return end

    local aliasLines = LiteStep.parser.commandLines["alias"]
    if aliasLines then
        for _, line in ipairs(aliasLines) do
            LiteStep.executeBang("!Alias " .. line)
        end
    end
end

--------------------------------------------------------------------------------
-- MODULE: AnyKey (Hotkeys)
--------------------------------------------------------------------------------

LiteStep.hotkeys = {}
LiteStep.hotkeyBindings = {}

-- Parse modifier string like "CTRL+SHIFT+ALT"
local function parseModifiers(modStr)
    local mods = {}
    modStr = modStr:upper()

    if modStr:find("CTRL") or modStr:find("CONTROL") then
        table.insert(mods, "ctrl")
    end
    if modStr:find("SHIFT") then
        table.insert(mods, "shift")
    end
    if modStr:find("ALT") then
        table.insert(mods, "alt")
    end
    if modStr:find("WIN") or modStr:find("CMD") or modStr:find("COMMAND") then
        table.insert(mods, "cmd")
    end

    return mods
end

-- Convert key name to Hammerspoon key code
local function parseKeyName(keyName)
    keyName = keyName:upper()

    -- Special keys mapping
    local keyMap = {
        ["RETURN"] = "return", ["ENTER"] = "return",
        ["ESCAPE"] = "escape", ["ESC"] = "escape",
        ["SPACE"] = "space",
        ["TAB"] = "tab",
        ["BACKSPACE"] = "delete", ["BACK"] = "delete",
        ["DELETE"] = "forwarddelete", ["DEL"] = "forwarddelete",
        ["INSERT"] = "help",
        ["HOME"] = "home",
        ["END"] = "end",
        ["PAGEUP"] = "pageup", ["PGUP"] = "pageup",
        ["PAGEDOWN"] = "pagedown", ["PGDN"] = "pagedown",
        ["LEFT"] = "left", ["RIGHT"] = "right",
        ["UP"] = "up", ["DOWN"] = "down",
        ["F1"] = "f1", ["F2"] = "f2", ["F3"] = "f3", ["F4"] = "f4",
        ["F5"] = "f5", ["F6"] = "f6", ["F7"] = "f7", ["F8"] = "f8",
        ["F9"] = "f9", ["F10"] = "f10", ["F11"] = "f11", ["F12"] = "f12",
        ["F13"] = "f13", ["F14"] = "f14", ["F15"] = "f15",
        ["NUMPAD0"] = "pad0", ["NUMPAD1"] = "pad1", ["NUMPAD2"] = "pad2",
        ["NUMPAD3"] = "pad3", ["NUMPAD4"] = "pad4", ["NUMPAD5"] = "pad5",
        ["NUMPAD6"] = "pad6", ["NUMPAD7"] = "pad7", ["NUMPAD8"] = "pad8",
        ["NUMPAD9"] = "pad9",
        ["MULTIPLY"] = "pad*", ["ADD"] = "pad+",
        ["SUBTRACT"] = "pad-", ["DECIMAL"] = "pad.",
        ["DIVIDE"] = "pad/",
        ["CAPSLOCK"] = "capslock",
        ["PRINTSCREEN"] = "f13", ["SCROLLLOCK"] = "f14",
        ["PAUSE"] = "f15",
    }

    if keyMap[keyName] then
        return keyMap[keyName]
    end

    -- Single character
    if #keyName == 1 then
        return keyName:lower()
    end

    return keyName:lower()
end

-- Register a hotkey
function LiteStep.registerHotkey(modifiers, key, command)
    local mods = parseModifiers(modifiers)
    local keyCode = parseKeyName(key)

    local binding = hs.hotkey.new(mods, keyCode, function()
        LiteStep.executeBang(command)
    end)

    if binding then
        binding:enable()
        table.insert(LiteStep.hotkeyBindings, binding)
        return true
    end
    return false
end

-- Load hotkeys from theme
function LiteStep.loadHotkeys()
    if not LiteStep.parser then return end

    -- Load *Hotkey lines
    local hotkeyLines = LiteStep.parser.commandLines["hotkey"]
    if hotkeyLines then
        for _, line in ipairs(hotkeyLines) do
            local mods, key, cmd = line:match("^(%S+)%s+(%S+)%s+(.+)$")
            if mods and key and cmd then
                LiteStep.registerHotkey(mods, key, cmd)
            end
        end
    end

    -- Handle AnyKeyLWinKey / AnyKeyRWinKey
    local lwinCmd = LiteStep.getString("AnyKeyLWinKey", nil)
    if lwinCmd then
        LiteStep.registerHotkey("", "cmd", lwinCmd)
    end

    local rwinCmd = LiteStep.getString("AnyKeyRWinKey", nil)
    if rwinCmd then
        -- Note: Hammerspoon can't distinguish left/right cmd, so we use this as fallback
        -- Users should use *Hotkey for more control
    end
end

-- Unload all hotkeys
function LiteStep.unloadHotkeys()
    for _, binding in ipairs(LiteStep.hotkeyBindings) do
        binding:delete()
    end
    LiteStep.hotkeyBindings = {}
end

--------------------------------------------------------------------------------
-- MODULE: xTextEdit (File manipulation)
--------------------------------------------------------------------------------

-- Parse @token@ format (xTextEdit uses @ as delimiter)
local function parseXTextToken(str)
    if not str then return nil, "" end
    str = str:match("^%s*(.-)%s*$") or ""
    if str == "" then return nil, "" end

    local token, rest

    if str:sub(1, 1) == "@" then
        local endAt = str:find("@", 2, true)
        if endAt then
            token = str:sub(2, endAt - 1)
            rest = str:sub(endAt + 1)
        else
            token = str:sub(2)
            rest = ""
        end
    else
        local space = str:find("%s")
        if space then
            token = str:sub(1, space - 1)
            rest = str:sub(space + 1)
        else
            token = str
            rest = ""
        end
    end

    return token, rest:match("^%s*(.-)%s*$") or ""
end

-- !xTextAppend - append text to file
LiteStep.registerBangCommand("xTextAppend", function(args)
    local filename, rest = parseXTextToken(args)
    local text = parseXTextToken(rest)

    if filename and text then
        local file = io.open(filename, "a")
        if file then
            file:write(text .. "\n")
            file:close()
        else
            print("LiteStep: xTextAppend - Could not open file: " .. filename)
        end
    end
end)

-- !xTextReplace - replace text in file using regex
LiteStep.registerBangCommand("xTextReplace", function(args)
    local filename, rest = parseXTextToken(args)
    local pattern, rest2 = parseXTextToken(rest)
    local replacement = parseXTextToken(rest2)

    if filename and pattern and replacement then
        local file = io.open(filename, "r")
        if file then
            local content = file:read("*all")
            file:close()

            -- Convert regex-style pattern to Lua pattern (basic conversion)
            local luaPattern = pattern:gsub("%.", "%%.")
                                      :gsub("%*", ".*")
                                      :gsub("%+", ".+")
                                      :gsub("%?", ".?")

            local newContent, count = content:gsub(luaPattern, replacement, 1)

            if count > 0 then
                local outFile = io.open(filename, "w")
                if outFile then
                    outFile:write(newContent)
                    outFile:close()
                end
            end
        else
            print("LiteStep: xTextReplace - Could not open file: " .. filename)
        end
    end
end)

-- !xTextReplaceAll - replace all occurrences
LiteStep.registerBangCommand("xTextReplaceAll", function(args)
    local filename, rest = parseXTextToken(args)
    local pattern, rest2 = parseXTextToken(rest)
    local replacement = parseXTextToken(rest2)

    if filename and pattern and replacement then
        local file = io.open(filename, "r")
        if file then
            local content = file:read("*all")
            file:close()

            local luaPattern = pattern:gsub("%.", "%%.")
                                      :gsub("%*", ".*")
                                      :gsub("%+", ".+")
                                      :gsub("%?", ".?")

            local newContent = content:gsub(luaPattern, replacement)

            local outFile = io.open(filename, "w")
            if outFile then
                outFile:write(newContent)
                outFile:close()
            end
        else
            print("LiteStep: xTextReplaceAll - Could not open file: " .. filename)
        end
    end
end)

-- !xTextDelete - delete line matching pattern
LiteStep.registerBangCommand("xTextDelete", function(args)
    local filename, rest = parseXTextToken(args)
    local pattern = parseXTextToken(rest)

    if filename and pattern then
        local file = io.open(filename, "r")
        if file then
            local lines = {}
            local found = false

            for line in file:lines() do
                if not found and line:find(pattern) then
                    found = true -- Skip this line (delete it)
                else
                    table.insert(lines, line)
                end
            end
            file:close()

            local outFile = io.open(filename, "w")
            if outFile then
                outFile:write(table.concat(lines, "\n"))
                if #lines > 0 then outFile:write("\n") end
                outFile:close()
            end
        end
    end
end)

-- !xTextDeleteAll - delete all lines matching pattern
LiteStep.registerBangCommand("xTextDeleteAll", function(args)
    local filename, rest = parseXTextToken(args)
    local pattern = parseXTextToken(rest)

    if filename and pattern then
        local file = io.open(filename, "r")
        if file then
            local lines = {}

            for line in file:lines() do
                if not line:find(pattern) then
                    table.insert(lines, line)
                end
            end
            file:close()

            local outFile = io.open(filename, "w")
            if outFile then
                outFile:write(table.concat(lines, "\n"))
                if #lines > 0 then outFile:write("\n") end
                outFile:close()
            end
        end
    end
end)

-- !xTextInsertAfter - insert text after matching line
LiteStep.registerBangCommand("xTextInsertAfter", function(args)
    local filename, rest = parseXTextToken(args)
    local pattern, rest2 = parseXTextToken(rest)
    local insert = parseXTextToken(rest2)

    if filename and pattern and insert then
        local file = io.open(filename, "r")
        if file then
            local lines = {}
            local found = false

            for line in file:lines() do
                table.insert(lines, line)
                if not found and line:find(pattern) then
                    table.insert(lines, insert)
                    found = true
                end
            end
            file:close()

            local outFile = io.open(filename, "w")
            if outFile then
                outFile:write(table.concat(lines, "\n"))
                if #lines > 0 then outFile:write("\n") end
                outFile:close()
            end
        end
    end
end)

-- !xTextInsertBefore - insert text before matching line
LiteStep.registerBangCommand("xTextInsertBefore", function(args)
    local filename, rest = parseXTextToken(args)
    local pattern, rest2 = parseXTextToken(rest)
    local insert = parseXTextToken(rest2)

    if filename and pattern and insert then
        local file = io.open(filename, "r")
        if file then
            local lines = {}
            local found = false

            for line in file:lines() do
                if not found and line:find(pattern) then
                    table.insert(lines, insert)
                    found = true
                end
                table.insert(lines, line)
            end
            file:close()

            local outFile = io.open(filename, "w")
            if outFile then
                outFile:write(table.concat(lines, "\n"))
                if #lines > 0 then outFile:write("\n") end
                outFile:close()
            end
        end
    end
end)

-- !xTextSaveEvar - save variable to file (update existing or append)
LiteStep.registerBangCommand("xTextSaveEvar", function(args)
    local filename, rest = parseXTextToken(args)
    local varName, rest2 = parseXTextToken(rest)
    local value = parseXTextToken(rest2)

    if filename and varName then
        -- If no value provided, get current value from variables
        if not value or value == "" then
            value = LiteStep.variables[varName:lower()] or ""
        end

        -- Try to update existing line, otherwise append
        local file = io.open(filename, "r")
        if file then
            local lines = {}
            local found = false
            local pattern = "^%s*" .. varName:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1") .. "%s+"

            for line in file:lines() do
                if not found and line:match(pattern) then
                    table.insert(lines, varName .. ' "' .. value .. '"')
                    found = true
                else
                    table.insert(lines, line)
                end
            end
            file:close()

            if not found then
                table.insert(lines, varName .. ' "' .. value .. '"')
            end

            local outFile = io.open(filename, "w")
            if outFile then
                outFile:write(table.concat(lines, "\n"))
                if #lines > 0 then outFile:write("\n") end
                outFile:close()
            end
        else
            -- File doesn't exist, create it
            local outFile = io.open(filename, "w")
            if outFile then
                outFile:write(varName .. ' "' .. value .. '"\n')
                outFile:close()
            end
        end
    end
end)

-- !ParseEvars - re-expand variables in command and execute
LiteStep.registerBangCommand("ParseEvars", function(args)
    if LiteStep.parser and args then
        local expanded = LiteStep.parser:expandVariables(args)
        LiteStep.executeBang(expanded)
    end
end)

--------------------------------------------------------------------------------
-- MODULE: Timer (Periodic command execution)
--------------------------------------------------------------------------------

LiteStep.timerObjects = {}
LiteStep.labelStates = {}  -- Track state cycling for !LabelNext

-- Parse interval string (e.g., "3s", "500ms", "1m", "1h")
local function parseTimerInterval(str)
    if not str then return 1 end

    local num, unit = str:match("^(%d+)(%a*)$")
    num = tonumber(num) or 1
    unit = (unit or ""):lower()

    if unit == "ms" then
        return num / 1000
    elseif unit == "m" then
        return num * 60
    elseif unit == "h" then
        return num * 3600
    else -- default seconds
        return num
    end
end

-- Timer class
local Timer = {}
Timer.__index = Timer

function Timer.new(name, interval, command, flags)
    local self = setmetatable({}, Timer)
    self.name = name
    self.interval = interval
    self.command = command
    self.flags = flags or {}
    self.timer = nil
    self.running = false
    self.direction = 1  -- For #r (reversible) flag
    return self
end

function Timer:start()
    if self.running then return end

    self.timer = hs.timer.doEvery(self.interval, function()
        LiteStep.executeBang(self.command)
    end)
    self.running = true
end

function Timer:stop()
    if self.timer then
        self.timer:stop()
        self.timer = nil
    end
    self.running = false
end

function Timer:trigger()
    -- Execute command immediately
    LiteStep.executeBang(self.command)
end

function Timer:destroy()
    self:stop()
end

-- Load timers from theme
function LiteStep.loadTimers()
    if not LiteStep.parser then return end

    local timerLines = LiteStep.parser.commandLines["timer"]
    if not timerLines then return end

    for _, line in ipairs(timerLines) do
        -- Format: *Timer <name> [flags] <interval> <command>
        -- Flags: #sl (slideshow), #h (hidden/start stopped), #r (reversible)
        local parts = {}
        local inQuote = false
        local current = ""

        for i = 1, #line do
            local c = line:sub(i, i)
            if c == '"' then
                inQuote = not inQuote
                current = current .. c
            elseif c == " " and not inQuote then
                if #current > 0 then
                    table.insert(parts, current)
                    current = ""
                end
            else
                current = current .. c
            end
        end
        if #current > 0 then
            table.insert(parts, current)
        end

        if #parts >= 3 then
            local name = parts[1]
            local flags = {}
            local intervalIdx = 2

            -- Parse flags
            while parts[intervalIdx] and parts[intervalIdx]:sub(1, 1) == "#" do
                local flag = parts[intervalIdx]:sub(2):lower()
                flags[flag] = true
                intervalIdx = intervalIdx + 1
            end

            local interval = parseTimerInterval(parts[intervalIdx])
            local command = table.concat(parts, " ", intervalIdx + 1)

            local timer = Timer.new(name, interval, command, flags)
            LiteStep.timerObjects[name:lower()] = timer

            -- Start unless #h (hidden/stopped) flag
            if not flags.h then
                timer:start()
            end
        end
    end
end

-- Timer bang commands
LiteStep.registerBangCommand("TimerStart", function(args)
    local name = args:match("^(%S+)")
    if name then
        local timer = LiteStep.timerObjects[name:lower()]
        if timer then timer:start() end
    end
end)

LiteStep.registerBangCommand("TimerStop", function(args)
    local name = args:match("^(%S+)")
    if name then
        local timer = LiteStep.timerObjects[name:lower()]
        if timer then timer:stop() end
    end
end)

LiteStep.registerBangCommand("TimerToggle", function(args)
    local name = args:match("^(%S+)")
    if name then
        local timer = LiteStep.timerObjects[name:lower()]
        if timer then
            if timer.running then
                timer:stop()
            else
                timer:start()
            end
        end
    end
end)

LiteStep.registerBangCommand("TimerTrigger", function(args)
    local name = args:match("^(%S+)")
    if name then
        local timer = LiteStep.timerObjects[name:lower()]
        if timer then timer:trigger() end
    end
end)

-- !LabelNext - cycle to next state (used with slideshows)
LiteStep.registerBangCommand("LabelNext", function(args)
    local name = args:match("^(%S+)")
    if not name then return end

    local label = LiteStep.labels[name:lower()]
    if not label then return end

    local win = label.window or label

    -- Get current state index
    local stateList = LiteStep.labelStates[name:lower()]
    if not stateList then
        -- Build state list from settings
        stateList = {states = {}, current = 1}

        -- Look for numbered states: State1, State2, etc. or sl1, sl2, etc.
        local settings = win.settings
        if settings then
            for i = 1, 100 do
                local stateName = "State" .. i
                local slName = "sl" .. i

                -- Check if state exists
                if settings:getString(stateName, nil) or
                   settings:getString(slName, nil) or
                   settings.parser.settings[(settings.prefix .. stateName):lower()] or
                   settings.parser.settings[(settings.prefix .. slName):lower()] then
                    table.insert(stateList.states, stateName)
                else
                    break
                end
            end
        end

        -- If no numbered states, use hover/pressed as fallback
        if #stateList.states == 0 then
            stateList.states = {"base", "hover", "pressed"}
        end

        LiteStep.labelStates[name:lower()] = stateList
    end

    -- Cycle to next state
    stateList.current = stateList.current + 1
    if stateList.current > #stateList.states then
        stateList.current = 1
    end

    local newState = stateList.states[stateList.current]

    -- Add state if not exists and render
    if not win.states[newState] then
        win:addState(newState, newState)
    end
    win:setState(newState)
end)

-- !LabelPrev - cycle to previous state
LiteStep.registerBangCommand("LabelPrev", function(args)
    local name = args:match("^(%S+)")
    if not name then return end

    local label = LiteStep.labels[name:lower()]
    if not label then return end

    local win = label.window or label
    local stateList = LiteStep.labelStates[name:lower()]

    if stateList and #stateList.states > 0 then
        stateList.current = stateList.current - 1
        if stateList.current < 1 then
            stateList.current = #stateList.states
        end

        local newState = stateList.states[stateList.current]
        if not win.states[newState] then
            win:addState(newState, newState)
        end
        win:setState(newState)
    end
end)

-- !LabelSetState - set specific state by name or index
LiteStep.registerBangCommand("LabelSetState", function(args)
    local name, state = args:match("^(%S+)%s+(%S+)")
    if not name or not state then return end

    local label = LiteStep.labels[name:lower()]
    if not label then return end

    local win = label.window or label

    -- Check if state is numeric
    local stateIdx = tonumber(state)
    if stateIdx then
        local stateList = LiteStep.labelStates[name:lower()]
        if stateList and stateList.states[stateIdx] then
            state = stateList.states[stateIdx]
            stateList.current = stateIdx
        end
    end

    if not win.states[state] then
        win:addState(state, state)
    end
    win:setState(state)
end)

--------------------------------------------------------------------------------
-- MODULE: mzscript (Variables and scripting)
--------------------------------------------------------------------------------

LiteStep.mzVariables = {}

-- Get mzscript internal variable value
function LiteStep.getMzVariable(name)
    name = name:lower()

    -- Check user-defined variables first
    if LiteStep.mzVariables[name] then
        return LiteStep.mzVariables[name]
    end

    -- Built-in variables
    if name == "mousex" then
        return tostring(math.floor(hs.mouse.absolutePosition().x))
    elseif name == "mousey" then
        return tostring(math.floor(hs.mouse.absolutePosition().y))
    elseif name == "year" then
        return os.date("%Y")
    elseif name == "month" then
        return os.date("%m")
    elseif name == "day" then
        return os.date("%d")
    elseif name == "hour" then
        return os.date("%H")
    elseif name == "min" or name == "minute" then
        return os.date("%M")
    elseif name == "sec" or name == "second" then
        return os.date("%S")
    elseif name == "milli" then
        -- Milliseconds (0-999)
        local time = hs.timer.absoluteTime() / 1000000 -- nanoseconds to milliseconds
        return tostring(math.floor(time % 1000))
    elseif name == "weekday" then
        return os.date("%w")
    elseif name == "yearday" then
        return os.date("%j")
    elseif name == "date" then
        return os.date("%Y-%m-%d")
    elseif name == "time" then
        return os.date("%H:%M:%S")
    elseif name == "screenwidth" or name == "xresolution" then
        local screen = getScreenRect()
        return tostring(screen.w)
    elseif name == "screenheight" or name == "yresolution" then
        local screen = getScreenRect()
        return tostring(screen.h)
    elseif name == "bpp" then
        -- Bits per pixel (macOS is typically 32-bit color)
        return "32"
    elseif name == "random" then
        return tostring(math.random(0, 32767))
    elseif name == "clipboard" then
        return hs.pasteboard.getContents() or ""
    elseif name == "hostname" then
        return hs.host.localizedName() or ""
    elseif name == "username" then
        return os.getenv("USER") or ""
    elseif name == "homedir" then
        return os.getenv("HOME") or ""
    end

    -- Check parser variables
    if LiteStep.variables and LiteStep.variables[name] then
        return LiteStep.variables[name]
    end

    return ""
end

-- Set mzscript variable
function LiteStep.setMzVariable(name, value)
    LiteStep.mzVariables[name:lower()] = tostring(value)
end

-- !varSet - set a variable
LiteStep.registerBangCommand("varSet", function(args)
    local name, value = args:match("^(%S+)%s+(.+)$")
    if name then
        LiteStep.setMzVariable(name, value or "")
    end
end)

-- !varAdd - add to numeric variable
LiteStep.registerBangCommand("varAdd", function(args)
    local name, value = args:match("^(%S+)%s+(%S+)")
    if name then
        local current = tonumber(LiteStep.getMzVariable(name)) or 0
        local add = tonumber(value) or 0
        LiteStep.setMzVariable(name, current + add)
    end
end)

-- !varSub - subtract from numeric variable
LiteStep.registerBangCommand("varSub", function(args)
    local name, value = args:match("^(%S+)%s+(%S+)")
    if name then
        local current = tonumber(LiteStep.getMzVariable(name)) or 0
        local sub = tonumber(value) or 0
        LiteStep.setMzVariable(name, current - sub)
    end
end)

-- !varMul - multiply numeric variable
LiteStep.registerBangCommand("varMul", function(args)
    local name, value = args:match("^(%S+)%s+(%S+)")
    if name then
        local current = tonumber(LiteStep.getMzVariable(name)) or 0
        local mul = tonumber(value) or 1
        LiteStep.setMzVariable(name, current * mul)
    end
end)

-- !varDiv - divide numeric variable
LiteStep.registerBangCommand("varDiv", function(args)
    local name, value = args:match("^(%S+)%s+(%S+)")
    if name then
        local current = tonumber(LiteStep.getMzVariable(name)) or 0
        local div = tonumber(value) or 1
        if div ~= 0 then
            LiteStep.setMzVariable(name, current / div)
        end
    end
end)

-- !varInt - convert to integer (rounds >=0.5 up, like mzscript)
LiteStep.registerBangCommand("varInt", function(args)
    local name = args:match("^(%S+)")
    if name then
        local current = tonumber(LiteStep.getMzVariable(name)) or 0
        local intPart = math.floor(current)
        local fracPart = current - intPart
        if fracPart >= 0.5 then
            intPart = intPart + 1
        end
        LiteStep.setMzVariable(name, intPart)
    end
end)

-- !varRnd - set to random value (mzscript compatible)
-- With 2 args: returns 1 to max (integer)
-- With 1 arg: returns 0.0 to 1.0 (float)
LiteStep.registerBangCommand("varRnd", function(args)
    local name, maxVal = args:match("^(%S+)%s*(%S*)")
    if name then
        if maxVal and maxVal ~= "" then
            local max = tonumber(maxVal) or 100
            LiteStep.setMzVariable(name, math.random(1, max))
        else
            LiteStep.setMzVariable(name, math.random())
        end
    end
end)

-- !varCopy - copy one variable to another
LiteStep.registerBangCommand("varCopy", function(args)
    local dest, src = args:match("^(%S+)%s+(%S+)")
    if dest and src then
        LiteStep.setMzVariable(dest, LiteStep.getMzVariable(src))
    end
end)

-- !varConcat - concatenate strings
LiteStep.registerBangCommand("varConcat", function(args)
    local dest, value = args:match("^(%S+)%s+(.+)$")
    if dest then
        local current = LiteStep.getMzVariable(dest)
        LiteStep.setMzVariable(dest, current .. (value or ""))
    end
end)

-- !if - conditional execution
LiteStep.registerBangCommand("if", function(args)
    -- Format: !if <var> <op> <value> <command>
    local var, op, value, cmd = args:match("^(%S+)%s+(%S+)%s+(%S+)%s+(.+)$")
    if not var or not op or not value or not cmd then return end

    local varVal = LiteStep.getMzVariable(var)
    local varNum = tonumber(varVal)
    local valNum = tonumber(value)

    local result = false
    op = op:lower()

    if op == "=" or op == "==" or op == "eq" then
        if varNum and valNum then
            result = varNum == valNum
        else
            result = varVal == value
        end
    elseif op == "!=" or op == "<>" or op == "ne" then
        if varNum and valNum then
            result = varNum ~= valNum
        else
            result = varVal ~= value
        end
    elseif op == "<" or op == "lt" then
        result = (varNum or 0) < (valNum or 0)
    elseif op == ">" or op == "gt" then
        result = (varNum or 0) > (valNum or 0)
    elseif op == "<=" or op == "le" then
        result = (varNum or 0) <= (valNum or 0)
    elseif op == ">=" or op == "ge" then
        result = (varNum or 0) >= (valNum or 0)
    end

    if result then
        LiteStep.executeBang(cmd)
    end
end)

-- !ifExist - check if variable exists
LiteStep.registerBangCommand("ifExist", function(args)
    local var, cmd = args:match("^(%S+)%s+(.+)$")
    if var and cmd then
        local val = LiteStep.getMzVariable(var)
        if val and val ~= "" then
            LiteStep.executeBang(cmd)
        end
    end
end)

-- !ifNotExist - check if variable doesn't exist
LiteStep.registerBangCommand("ifNotExist", function(args)
    local var, cmd = args:match("^(%S+)%s+(.+)$")
    if var and cmd then
        local val = LiteStep.getMzVariable(var)
        if not val or val == "" then
            LiteStep.executeBang(cmd)
        end
    end
end)

-- !varIncr - increment by 1
LiteStep.registerBangCommand("varIncr", function(args)
    local name = args:match("^(%S+)")
    if name then
        local current = tonumber(LiteStep.getMzVariable(name)) or 0
        LiteStep.setMzVariable(name, current + 1)
    end
end)

-- !varDecr - decrement by 1
LiteStep.registerBangCommand("varDecr", function(args)
    local name = args:match("^(%S+)")
    if name then
        local current = tonumber(LiteStep.getMzVariable(name)) or 0
        LiteStep.setMzVariable(name, current - 1)
    end
end)

-- !varMod - modulus operation
LiteStep.registerBangCommand("varMod", function(args)
    local name, value = args:match("^(%S+)%s+(%S+)")
    if name and value then
        local current = tonumber(LiteStep.getMzVariable(name)) or 0
        local mod = tonumber(value) or 1
        if mod ~= 0 then
            LiteStep.setMzVariable(name, math.floor(current) % math.floor(mod))
        end
    end
end)

-- !varRemove - remove a variable
LiteStep.registerBangCommand("varRemove", function(args)
    for name in args:gmatch("%S+") do
        LiteStep.mzVariables[name:lower()] = nil
    end
end)

-- !varShow - show variable value in alert
LiteStep.registerBangCommand("varShow", function(args)
    local name = args:match("^(%S+)")
    if name then
        local value = LiteStep.getMzVariable(name)
        if value and value ~= "" then
            hs.alert.show(name .. " = " .. value, 5)
        else
            hs.alert.show("Variable \"" .. name .. "\" does not exist.", 3)
        end
    end
end)

-- !varRun - execute variable value as command
LiteStep.registerBangCommand("varRun", function(args)
    local name = args:match("^(%S+)")
    if name then
        local value = LiteStep.getMzVariable(name)
        if value and value ~= "" then
            LiteStep.executeBang(value)
        end
    end
end)

-- !varDump - dump all variables to file
LiteStep.registerBangCommand("varDump", function(args)
    local filename = args:match("^(%S+)")
    if filename then
        local path = filename
        if not path:match("^/") then
            path = LiteStep.basePath .. filename
        end
        local file = io.open(path, "w")
        if file then
            file:write("; mzscript variable dump\n")
            file:write("; Generated: " .. os.date() .. "\n\n")
            for name, value in pairs(LiteStep.mzVariables) do
                file:write(name .. " " .. tostring(value) .. "\n")
            end
            file:close()
            print("LiteStep: Variables dumped to " .. path)
        end
    end
end)

-- !varSave - save a single variable to file
LiteStep.registerBangCommand("varSave", function(args)
    local name = args:match("^(%S+)")
    if name then
        local value = LiteStep.getMzVariable(name)
        if value then
            local path = LiteStep.basePath .. "litestep/vars/" .. name .. ".mz"
            local file = io.open(path, "w")
            if file then
                file:write(name .. " " .. tostring(value) .. "\n")
                file:close()
            end
        end
    end
end)

-- !varSaveAll - save all variables to their files
LiteStep.registerBangCommand("varSaveAll", function(args)
    for name, value in pairs(LiteStep.mzVariables) do
        local path = LiteStep.basePath .. "litestep/vars/" .. name .. ".mz"
        local file = io.open(path, "w")
        if file then
            file:write(name .. " " .. tostring(value) .. "\n")
            file:close()
        end
    end
end)

-- !msgbox - show message box
LiteStep.registerBangCommand("msgbox", function(args)
    if args and args ~= "" then
        hs.dialog.alert(100, 100, function() end, args, "mzscript", "OK")
    end
end)

-- !mzLoadVarFile - load variable file at runtime
LiteStep.registerBangCommand("mzLoadVarFile", function(args)
    local filename = args:match("^(%S+)")
    if filename and LiteStep.parser then
        filename = LiteStep.parser:expandVariables(filename)
        LiteStep.parser:parseFile(filename)
    end
end)

-- !pause - pause execution for milliseconds
LiteStep.registerBangCommand("pause", function(args)
    local ms = tonumber(args:match("^(%d+)"))
    if ms and ms > 0 then
        -- Use hs.timer.usleep for millisecond precision
        hs.timer.usleep(ms * 1000)
    end
end)

-- !exec (mzscript version) - execute with variable expansion
LiteStep.registerBangCommand("mzExec", function(args)
    if args then
        local expanded = LiteStep.expandRuntimeVars(args)
        LiteStep.executeBang(expanded)
    end
end)

-- Update expandRuntimeVars to include mzscript variables
local originalExpandRuntimeVars = LiteStep.expandRuntimeVars
LiteStep.expandRuntimeVars = function(str)
    if not str then return str end

    -- First expand standard runtime vars
    str = originalExpandRuntimeVars(str)

    -- Expand mzscript %{var} format
    str = str:gsub("%%{([^}]+)}%%?", function(varName)
        return LiteStep.getMzVariable(varName)
    end)

    return str
end

-- !TimerKill - stop and remove a timer
LiteStep.registerBangCommand("TimerKill", function(args)
    local name = args:match("^(%S+)")
    if name then
        local timer = LiteStep.timerObjects[name:lower()]
        if timer then
            timer:destroy()
            LiteStep.timerObjects[name:lower()] = nil
        end
    end
end)

--------------------------------------------------------------------------------
-- MODULE: xStatsClass (Dynamic content functions)
--------------------------------------------------------------------------------

-- CPU usage tracking (simplified for macOS)
local cpuUsageCache = {value = 0, lastUpdate = 0}

local function getCPUUsage()
    local now = os.time()
    if now - cpuUsageCache.lastUpdate < 2 then
        return cpuUsageCache.value
    end

    local handle = io.popen("top -l 1 -n 0 | grep 'CPU usage' | awk '{print $3}' | tr -d '%'")
    if handle then
        local result = handle:read("*a")
        handle:close()
        cpuUsageCache.value = tonumber(result) or 0
        cpuUsageCache.lastUpdate = now
    end
    return cpuUsageCache.value
end

-- Memory info
local function getMemoryInfo()
    local info = {total = 0, available = 0, inuse = 0}

    -- Get total memory
    local handle = io.popen("sysctl -n hw.memsize")
    if handle then
        local bytes = tonumber(handle:read("*a")) or 0
        info.total = math.floor(bytes / (1024 * 1024)) -- MB
        handle:close()
    end

    -- Get memory pressure/available
    local handle2 = io.popen("vm_stat | grep 'Pages free' | awk '{print $3}' | tr -d '.'")
    if handle2 then
        local pages = tonumber(handle2:read("*a")) or 0
        info.available = math.floor(pages * 4096 / (1024 * 1024)) -- MB
        handle2:close()
    end

    info.inuse = info.total - info.available
    return info
end

-- Battery info
local function getBatteryInfo()
    local info = {percent = 100, charging = false, source = "AC"}

    local battery = hs.battery.percentage()
    if battery then
        info.percent = math.floor(battery)
    end

    info.charging = hs.battery.isCharging() or false
    info.source = hs.battery.powerSource() or "AC"

    return info
end

-- Disk info
local function getDiskInfo(path)
    path = path or "/"
    local info = {total = 0, available = 0, inuse = 0}

    local handle = io.popen("df -k '" .. path .. "' | tail -1")
    if handle then
        local line = handle:read("*a")
        handle:close()

        local parts = {}
        for part in line:gmatch("%S+") do
            table.insert(parts, part)
        end

        if #parts >= 4 then
            info.total = math.floor((tonumber(parts[2]) or 0) / 1024) -- MB
            info.inuse = math.floor((tonumber(parts[3]) or 0) / 1024)
            info.available = math.floor((tonumber(parts[4]) or 0) / 1024)
        end
    end

    return info
end

-- Format bytes with units
local function formatBytes(bytes, unit)
    unit = (unit or ""):lower()
    if unit == "kb" or unit == "2" then
        return string.format("%.1f", bytes / 1024)
    elseif unit == "mb" or unit == "3" then
        return string.format("%.1f", bytes / (1024 * 1024))
    elseif unit == "gb" or unit == "4" then
        return string.format("%.2f", bytes / (1024 * 1024 * 1024))
    elseif unit == "%" or unit == "5" then
        return tostring(bytes) -- Percentage is already calculated
    end
    return tostring(bytes)
end

-- xStatsClass function registry
local statsFunctions = {}

-- Date/Time functions
statsFunctions["time"] = function(format)
    format = format or "%H:%M:%S"
    -- Convert common format codes
    format = format:gsub("'", "")
    if format == "H" then format = "%H"
    elseif format == "h" then format = "%I"
    elseif format == "n" then format = "%M"
    elseif format == "s" then format = "%S"
    elseif format == "p" then format = "%p"
    elseif format == "HH:nn" then format = "%H:%M"
    elseif format == "hh:nn" then format = "%I:%M"
    elseif format == "HH:nn:ss" then format = "%H:%M:%S"
    end
    return os.date(format)
end

statsFunctions["date"] = function(format)
    format = format or "%Y-%m-%d"
    format = format:gsub("'", "")
    if format == "d" then format = "%d"
    elseif format == "dd" then format = "%d"
    elseif format == "m" then format = "%m"
    elseif format == "mm" then format = "%m"
    elseif format == "mmm" then format = "%b"
    elseif format == "mmmm" then format = "%B"
    elseif format == "yy" then format = "%y"
    elseif format == "yyyy" then format = "%Y"
    elseif format == "ddd" then format = "%a"
    elseif format == "dddd" then format = "%A"
    end
    return os.date(format)
end

statsFunctions["itime"] = function()
    -- Swatch Internet Time
    local utc = os.time(os.date("!*t"))
    local beats = math.floor(((utc + 3600) % 86400) / 86.4)
    return string.format("@%03d", beats)
end

-- System functions
statsFunctions["cpu"] = function(core)
    return string.format("%.0f", getCPUUsage())
end

statsFunctions["memtotal"] = function()
    return tostring(getMemoryInfo().total)
end

statsFunctions["memavailable"] = function()
    return tostring(getMemoryInfo().available)
end

statsFunctions["meminuse"] = function()
    return tostring(getMemoryInfo().inuse)
end

statsFunctions["battery"] = function()
    return tostring(getBatteryInfo().percent)
end

statsFunctions["powersource"] = function()
    return getBatteryInfo().source
end

statsFunctions["uptime"] = function()
    local handle = io.popen("uptime | sed 's/.*up //' | sed 's/,.*//'")
    if handle then
        local result = handle:read("*a"):gsub("%s+$", "")
        handle:close()
        return result
    end
    return ""
end

statsFunctions["os"] = function()
    return "macOS"
end

statsFunctions["osex"] = function()
    local handle = io.popen("sw_vers -productVersion")
    if handle then
        local result = handle:read("*a"):gsub("%s+$", "")
        handle:close()
        return "macOS " .. result
    end
    return "macOS"
end

statsFunctions["computername"] = function()
    return hs.host.localizedName() or ""
end

statsFunctions["username"] = function()
    return os.getenv("USER") or ""
end

statsFunctions["hostname"] = function()
    local handle = io.popen("hostname")
    if handle then
        local result = handle:read("*a"):gsub("%s+$", "")
        handle:close()
        return result
    end
    return ""
end

-- Disk functions
statsFunctions["disktotal"] = function(path, unit)
    local info = getDiskInfo(path)
    return formatBytes(info.total * 1024 * 1024, unit)
end

statsFunctions["diskavailable"] = function(path, unit)
    local info = getDiskInfo(path)
    return formatBytes(info.available * 1024 * 1024, unit)
end

statsFunctions["diskinuse"] = function(path, unit)
    local info = getDiskInfo(path)
    return formatBytes(info.inuse * 1024 * 1024, unit)
end

-- Window/Task functions
statsFunctions["activetask"] = function(fallback)
    local win = hs.window.focusedWindow()
    if win then
        local app = win:application()
        if app then
            return app:name()
        end
    end
    return fallback or ""
end

statsFunctions["windowtitle"] = function()
    local win = hs.window.focusedWindow()
    if win then
        return win:title() or ""
    end
    return ""
end

-- Clipboard
statsFunctions["clipboardtext"] = function()
    return hs.pasteboard.getContents() or ""
end

-- Mouse position
statsFunctions["mousepos"] = function()
    local pos = hs.mouse.absolutePosition()
    return string.format("%d,%d", math.floor(pos.x), math.floor(pos.y))
end

-- Volume
statsFunctions["volume"] = function()
    local vol = hs.audiodevice.defaultOutputDevice()
    if vol then
        return string.format("%.0f", vol:volume() or 0)
    end
    return "0"
end

statsFunctions["mute"] = function()
    local vol = hs.audiodevice.defaultOutputDevice()
    if vol and vol:muted() then
        return "1"
    end
    return "0"
end

-- Text utilities
statsFunctions["uppercase"] = function(text)
    return (text or ""):upper()
end

statsFunctions["lowercase"] = function(text)
    return (text or ""):lower()
end

statsFunctions["capitalize"] = function(text)
    if not text then return "" end
    return text:gsub("^%l", string.upper)
end

statsFunctions["trim"] = function(text)
    if not text then return "" end
    return text:match("^%s*(.-)%s*$")
end

statsFunctions["replace"] = function(text, search, replacement)
    if not text or not search then return text or "" end
    return text:gsub(search, replacement or "")
end

statsFunctions["remove"] = function(text, target)
    if not text or not target then return text or "" end
    return text:gsub(target, "")
end

statsFunctions["after"] = function(text, search)
    if not text or not search then return "" end
    local pos = text:find(search, 1, true)
    if pos then
        return text:sub(pos + #search)
    end
    return ""
end

statsFunctions["before"] = function(text, search)
    if not text or not search then return text or "" end
    local pos = text:find(search, 1, true)
    if pos then
        return text:sub(1, pos - 1)
    end
    return text
end

statsFunctions["between"] = function(text, startStr, endStr, default)
    if not text or not startStr or not endStr then return default or "" end
    local s = text:find(startStr, 1, true)
    if s then
        local e = text:find(endStr, s + #startStr, true)
        if e then
            return text:sub(s + #startStr, e - 1)
        end
    end
    return default or ""
end

statsFunctions["hideifempty"] = function(text)
    if not text or text == "" then return "" end
    return text
end

statsFunctions["empty"] = function(text)
    return (not text or text == "") and "1" or "0"
end

statsFunctions["notempty"] = function(text)
    return (text and text ~= "") and "1" or "0"
end

statsFunctions["semicolon"] = function()
    return ";"
end

statsFunctions["dollar"] = function()
    return "$"
end

-- File functions
statsFunctions["fileexists"] = function(path)
    if not path then return "0" end
    local f = io.open(path, "r")
    if f then
        f:close()
        return "1"
    end
    return "0"
end

statsFunctions["firstline"] = function(path)
    if not path then return "" end
    local f = io.open(path, "r")
    if f then
        local line = f:read("*l") or ""
        f:close()
        return line
    end
    return ""
end

statsFunctions["lastline"] = function(path)
    if not path then return "" end
    local f = io.open(path, "r")
    if f then
        local last = ""
        for line in f:lines() do
            last = line
        end
        f:close()
        return last
    end
    return ""
end

statsFunctions["linecount"] = function(path)
    if not path then return "0" end
    local f = io.open(path, "r")
    if f then
        local count = 0
        for _ in f:lines() do
            count = count + 1
        end
        f:close()
        return tostring(count)
    end
    return "0"
end

statsFunctions["randomline"] = function(path)
    if not path then return "" end
    local f = io.open(path, "r")
    if f then
        local lines = {}
        for line in f:lines() do
            table.insert(lines, line)
        end
        f:close()
        if #lines > 0 then
            return lines[math.random(1, #lines)]
        end
    end
    return ""
end

-- Evar export
statsFunctions["exportedevar"] = function(name)
    if LiteStep.variables and name then
        return LiteStep.variables[name:lower()] or ""
    end
    return ""
end

-- Process [function(args)] syntax
function LiteStep.processStatsRequest(str)
    if not str then return str end

    -- Handle nested functions by processing innermost first
    local maxIterations = 10
    local iteration = 0

    while str:find("%[") and iteration < maxIterations do
        iteration = iteration + 1

        str = str:gsub("%[([^%[%]]+)%]", function(content)
            -- Parse function name and arguments
            local funcName, argsStr = content:match("^([%w_]+)%((.*)%)$")
            if not funcName then
                funcName = content:match("^([%w_]+)$")
                argsStr = ""
            end

            if funcName then
                funcName = funcName:lower()
                local handler = statsFunctions[funcName]

                if handler then
                    -- Parse arguments (comma-separated, respect quotes)
                    local args = {}
                    if argsStr and argsStr ~= "" then
                        local current = ""
                        local inQuote = false
                        local quoteChar = nil

                        for i = 1, #argsStr do
                            local c = argsStr:sub(i, i)
                            if (c == '"' or c == "'") and not inQuote then
                                inQuote = true
                                quoteChar = c
                            elseif c == quoteChar and inQuote then
                                inQuote = false
                                quoteChar = nil
                            elseif c == "," and not inQuote then
                                table.insert(args, current:match("^%s*(.-)%s*$"))
                                current = ""
                            else
                                current = current .. c
                            end
                        end
                        if current ~= "" then
                            table.insert(args, current:match("^%s*(.-)%s*$"))
                        end
                    end

                    -- Call function with arguments
                    local result = handler(table.unpack(args))
                    return result or ""
                end
            end

            return "[" .. content .. "]"
        end)
    end

    return str
end

-- Integrate stats processing into text rendering
local originalSetText = Window.setText
if originalSetText then
    Window.setText = function(self, text)
        -- Process stats functions before setting text
        text = LiteStep.processStatsRequest(text)
        return originalSetText(self, text)
    end
end

--------------------------------------------------------------------------------
-- MAIN API
--------------------------------------------------------------------------------

LiteStep.basePath = os.getenv("HOME") .. "/.hammerspoon/"

function LiteStep.loadTheme(filename)
    local parser = RCParser.new()
    parser.basePath = LiteStep.basePath
    parser:parseFile(filename)

    LiteStep.parser = parser
    LiteStep.settings = parser.settings
    LiteStep.variables = parser.variables
    LiteStep.commandLines = parser.commandLines

    return parser
end

function LiteStep.createSettings(prefix)
    if not LiteStep.parser then
        print("LiteStep: No theme loaded. Call loadTheme first.")
        return nil
    end
    return Settings.new(prefix, LiteStep.parser)
end

function LiteStep.createWindow(prefix)
    local settings = LiteStep.createSettings(prefix)
    if settings then
        local win = Window.new(settings, prefix)
        LiteStep.windows[prefix] = win
        return win
    end
    return nil
end

function LiteStep.createLabel(name)
    local settings = LiteStep.createSettings(name)
    if settings then
        local label = Label.new(settings, name)
        LiteStep.modules[name] = label
        return label
    end
    return nil
end

function LiteStep.createTaskbar(name)
    local settings = LiteStep.createSettings(name)
    if settings then
        local taskbar = Taskbar.new(settings, name)
        LiteStep.modules[name] = taskbar
        return taskbar
    end
    return nil
end

function LiteStep.createClock(name)
    local settings = LiteStep.createSettings(name)
    if settings then
        local clock = Clock.new(settings, name)
        LiteStep.modules[name] = clock
        return clock
    end
    return nil
end

function LiteStep.createPopup(name)
    local settings = LiteStep.createSettings(name)
    if settings then
        local popup = Popup.new(settings, name)
        popup:loadEntries()
        LiteStep.modules[name] = popup
        return popup
    end
    return nil
end

function LiteStep.createDesk(name)
    local settings = LiteStep.createSettings(name or "nDesk")
    if settings then
        local desk = Desk.new(settings, name or "nDesk")
        LiteStep.modules[name or "nDesk"] = desk
        return desk
    end
    return nil
end

function LiteStep.destroyAll()
    for _, win in pairs(LiteStep.windows) do
        win:destroy()
    end
    LiteStep.windows = {}

    for _, mod in pairs(LiteStep.modules) do
        if mod.destroy then
            mod:destroy()
        end
    end
    LiteStep.modules = {}

    for _, label in pairs(LiteStep.labels) do
        if label.destroy then
            label:destroy()
        end
    end
    LiteStep.labels = {}

    for _, popup in pairs(LiteStep.popups) do
        if popup.destroy then
            popup:destroy()
        end
    end
    LiteStep.popups = {}

    for _, timer in pairs(LiteStep.timers) do
        timer:stop()
    end
    LiteStep.timers = {}

    -- Stop timer objects (from Timer module)
    for _, timer in pairs(LiteStep.timerObjects) do
        timer:destroy()
    end
    LiteStep.timerObjects = {}

    -- Clear mzscript variables
    LiteStep.mzVariables = {}
    LiteStep.labelStates = {}

    -- Unload hotkeys
    LiteStep.unloadHotkeys()
end

function LiteStep.getString(key, default)
    if LiteStep.settings then
        return LiteStep.settings[key:lower()] or default
    end
    return default
end

function LiteStep.getInt(key, default)
    local str = LiteStep.getString(key, nil)
    if str then
        return math.floor(tonumber(str) or default)
    end
    return default
end

-- Initialize theme with all modules
function LiteStep.init(themeFile)
    -- Store for !Recycle
    LiteStep.lastThemeFile = themeFile

    -- Load the theme
    LiteStep.loadTheme(themeFile)

    -- Load aliases
    LiteStep.loadAliases()

    -- Load hotkeys
    LiteStep.loadHotkeys()

    -- Create nDesk (desktop handler)
    local desk = LiteStep.createDesk()
    if desk then desk:create() end

    -- Load labels from *Label lines
    if LiteStep.parser.commandLines["label"] then
        for _, labelName in ipairs(LiteStep.parser.commandLines["label"]) do
            local label = LiteStep.createLabel(labelName)
            if label then label:create() end
        end
    end

    -- Load nLabel from *nLabel lines
    if LiteStep.parser.commandLines["nlabel"] then
        for _, labelName in ipairs(LiteStep.parser.commandLines["nlabel"]) do
            local label = LiteStep.createLabel(labelName)
            if label then label:create() end
        end
    end

    -- Load clocks from *nClock lines
    if LiteStep.parser.commandLines["nclock"] then
        for _, clockName in ipairs(LiteStep.parser.commandLines["nclock"]) do
            local clock = LiteStep.createClock(clockName)
            if clock then clock:create() end
        end
    end

    -- Load taskbars from *nTaskbar lines
    if LiteStep.parser.commandLines["ntaskbar"] then
        for _, taskName in ipairs(LiteStep.parser.commandLines["ntaskbar"]) do
            local taskbar = LiteStep.createTaskbar(taskName)
            if taskbar then taskbar:create() end
        end
    end

    -- Load timers from *Timer lines
    LiteStep.loadTimers()

    -- Execute NetLoadModuleOnLoad commands
    if LiteStep.parser.onLoadCommands then
        for _, cmd in ipairs(LiteStep.parser.onLoadCommands) do
            LiteStep.executeBang(cmd)
        end
    end

    print("LiteStep: Theme loaded successfully!")
    return true
end

-- Export classes
LiteStep.RCParser = RCParser
LiteStep.Settings = Settings
LiteStep.Texture = Texture
LiteStep.TextStyle = TextStyle
LiteStep.IconStyle = IconStyle
LiteStep.State = State
LiteStep.Window = Window
LiteStep.Label = Label
LiteStep.Taskbar = Taskbar
LiteStep.Clock = Clock
LiteStep.Popup = Popup
LiteStep.Desk = Desk
LiteStep.Timer = Timer

return LiteStep
