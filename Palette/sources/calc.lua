-- Calculator source. Emits one synthetic row when the trimmed query parses as
-- an arithmetic expression. Re-emits on every keystroke so the result row
-- updates in place. Always uses id "calc:active" so re-rank replaces the row
-- instead of stacking. Bypasses the fuzzy matcher (the synthetic row would
-- not survive a subsequence test against "= 544").
--
-- Grammar:
--     expr   := term (("+"|"-") term)*
--     term   := factor (("*"|"/"|"%") factor)*
--     factor := unary ("^" factor)?            -- right-associative
--     unary  := ("+"|"-")* atom
--     atom   := number | "(" expr ")" | ident
--     ident  := "pi" | "e"

local M = {}
M.id = "calc"
M.dynamic = true

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function looksMathy(s)
    if not s:find("%d") then return false end
    if s:find("[%+%-%*%/%%%^%(%)]") then return true end
    if s:find("%.") then return true end
    return s:find("pi") ~= nil or s:find("[eE]") ~= nil
end

local function makeLexer(src)
    local pos = 1
    local function skipWs()
        while pos <= #src and src:sub(pos, pos):match("%s") do pos = pos + 1 end
    end
    local function peek()
        skipWs()
        if pos > #src then return nil end
        local c = src:sub(pos, pos)
        if c:match("%d") or c == "." then
            local s, e = src:find("^%d*%.?%d+", pos)
            if not s then return nil end
            return "num", tonumber(src:sub(s, e)), s, e
        end
        if c:match("[%a_]") then
            local s, e = src:find("^[%a_][%a_%d]*", pos)
            return "id", src:sub(s, e):lower(), s, e
        end
        return "op", c, pos, pos
    end
    local function consume()
        local kind, val, s, e = peek()
        if kind then pos = (e or pos) + 1 end
        return kind, val
    end
    local function atEnd()
        skipWs()
        return pos > #src
    end
    return { peek = peek, consume = consume, atEnd = atEnd }
end

local parseExpr

local function parseAtom(lex)
    local kind, val = lex.peek()
    if not kind then return nil, "unexpected end" end
    if kind == "num" then
        lex.consume()
        return val
    end
    if kind == "id" then
        lex.consume()
        if val == "pi" then return math.pi end
        if val == "e" then return math.exp(1) end
        return nil, "unknown identifier " .. val
    end
    if kind == "op" and val == "(" then
        lex.consume()
        local v, err = parseExpr(lex)
        if err then return nil, err end
        local k2, v2 = lex.peek()
        if k2 == "op" and v2 == ")" then
            lex.consume()
            return v
        end
        return nil, "missing close paren"
    end
    return nil, "unexpected token"
end

local function parseUnary(lex)
    local kind, val = lex.peek()
    if kind == "op" and (val == "+" or val == "-") then
        lex.consume()
        local v, err = parseUnary(lex)
        if err then return nil, err end
        return val == "-" and -v or v
    end
    return parseAtom(lex)
end

local function parseFactor(lex)
    local v, err = parseUnary(lex)
    if err then return nil, err end
    local kind, val = lex.peek()
    if kind == "op" and val == "^" then
        lex.consume()
        local rhs, e2 = parseFactor(lex)
        if e2 then return nil, e2 end
        return v ^ rhs
    end
    return v
end

local function parseTerm(lex)
    local v, err = parseFactor(lex)
    if err then return nil, err end
    while true do
        local kind, val = lex.peek()
        if kind ~= "op" or (val ~= "*" and val ~= "/" and val ~= "%") then return v end
        lex.consume()
        local rhs, e2 = parseFactor(lex)
        if e2 then return nil, e2 end
        if val == "*" then v = v * rhs
        elseif val == "/" then v = v / rhs
        else v = v % rhs end
    end
end

parseExpr = function(lex)
    local v, err = parseTerm(lex)
    if err then return nil, err end
    while true do
        local kind, val = lex.peek()
        if kind ~= "op" or (val ~= "+" and val ~= "-") then return v end
        lex.consume()
        local rhs, e2 = parseTerm(lex)
        if e2 then return nil, e2 end
        v = val == "+" and (v + rhs) or (v - rhs)
    end
end

local function evaluate(src)
    local lex = makeLexer(src)
    local v, err = parseExpr(lex)
    if err then return nil, err end
    if not lex.atEnd() then return nil, "trailing input" end
    if type(v) ~= "number" or v ~= v then return nil, "not a number" end
    if v == math.huge or v == -math.huge then return nil, "overflow" end
    return v
end

local function formatNumber(n)
    if n == math.floor(n) and math.abs(n) < 1e15 then
        return tostring(math.floor(n))
    end
    local s = string.format("%.6g", n)
    return s
end

local calcIcon
local function icon()
    if calcIcon then return calcIcon end
    pcall(function()
        calcIcon = hs.image.iconForFile("/System/Applications/Calculator.app")
    end)
    return calcIcon
end

function M.list(query)
    query = query or ""
    local trimmed = trim(query)
    if trimmed == "" or not looksMathy(trimmed) then return {}, nil end
    local value, err = evaluate(trimmed)
    if err or value == nil then return {}, nil end
    local formatted = formatNumber(value)
    return {
        {
            id               = "calc:active",
            title            = "= " .. formatted,
            subtitle         = trimmed,
            icon             = icon(),
            source           = M.id,
            payload          = { expression = trimmed, value = value, formatted = formatted },
            defaultVerb      = "copynumber",
            verbs            = { "copynumber", "askmuse" },
            hideOnEmptyQuery = true,
            bypassMatcher    = true,
        },
    }, nil
end

M._evaluate = evaluate
M._looksMathy = looksMathy
M._formatNumber = formatNumber

return M
