-- UTF-8 aware caret math for single-string text buffers. Positions are
-- 1-based logical character indices: 0 = before the first char, utf8.len(buf)
-- = after the last char. All ops clamp out-of-range arguments.

local M = {}

local function clen(buf)
    return utf8.len(buf) or 0
end

-- Byte index in `buf` corresponding to the boundary `pos`. Compatible with
-- string.sub: `buf:sub(1, byteOffset(buf, pos) - 1)` is the prefix of `pos`
-- chars; `buf:sub(byteOffset(buf, pos))` is the suffix.
function M.byteOffset(buf, pos)
    if pos <= 0 then return 1 end
    local n = clen(buf)
    if pos >= n then return #buf + 1 end
    return utf8.offset(buf, pos + 1)
end

function M.charLen(buf)
    return clen(buf)
end

local function isWhitespaceAt(buf, charPos)
    if charPos < 1 or charPos > clen(buf) then return false end
    local b = utf8.offset(buf, charPos)
    local cp = utf8.codepoint(buf, b)
    return cp == 32 or cp == 9 or cp == 10 or cp == 13 or cp == 0xA0
end

function M.insert(buf, pos, chars)
    if not chars or chars == "" then return buf, pos end
    pos = math.max(0, math.min(pos, clen(buf)))
    local b = M.byteOffset(buf, pos)
    local newBuf = buf:sub(1, b - 1) .. chars .. buf:sub(b)
    return newBuf, pos + (utf8.len(chars) or #chars)
end

function M.deleteBefore(buf, pos)
    pos = math.max(0, math.min(pos, clen(buf)))
    if pos == 0 then return buf, 0 end
    local bStart = M.byteOffset(buf, pos - 1)
    local bEnd   = M.byteOffset(buf, pos) - 1
    return buf:sub(1, bStart - 1) .. buf:sub(bEnd + 1), pos - 1
end

function M.deleteAfter(buf, pos)
    local n = clen(buf)
    pos = math.max(0, math.min(pos, n))
    if pos >= n then return buf, pos end
    local bStart = M.byteOffset(buf, pos)
    local bEnd   = M.byteOffset(buf, pos + 1) - 1
    return buf:sub(1, bStart - 1) .. buf:sub(bEnd + 1), pos
end

-- mode: "char" | "word" | "edge"
function M.moveLeft(buf, pos, mode)
    local n = clen(buf)
    pos = math.max(0, math.min(pos, n))
    if mode == "edge" then return 0 end
    if pos == 0 then return 0 end
    if mode == "word" then
        while pos > 0 and isWhitespaceAt(buf, pos) do pos = pos - 1 end
        while pos > 0 and not isWhitespaceAt(buf, pos) do pos = pos - 1 end
        return pos
    end
    return pos - 1
end

function M.moveRight(buf, pos, mode)
    local n = clen(buf)
    pos = math.max(0, math.min(pos, n))
    if mode == "edge" then return n end
    if pos >= n then return n end
    if mode == "word" then
        while pos < n and isWhitespaceAt(buf, pos + 1) do pos = pos + 1 end
        while pos < n and not isWhitespaceAt(buf, pos + 1) do pos = pos + 1 end
        return pos
    end
    return pos + 1
end

return M
