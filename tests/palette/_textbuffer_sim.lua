-- Deterministic tests for Palette.textbuffer caret math.
-- Returns "N/M" to the shell driver and writes /tmp/palette-textbuffer.log.

local LOG_PATH = "/tmp/palette-textbuffer.log"
local logF = io.open(LOG_PATH, "w")
local function logln(s) if logF then logF:write(s .. "\n") end end

package.loaded["Palette.textbuffer"] = nil
local tb = require("Palette.textbuffer")

local results = {}

local function expect(name, got, want)
    local pass = got == want
    table.insert(results, { name = name, want = tostring(want), got = tostring(got), pass = pass })
    logln(string.format("%s  %s", pass and "PASS" or "FAIL", name))
    if not pass then
        logln("     want: " .. tostring(want))
        logln("     got:  " .. tostring(got))
    end
end

local function expectPair(name, gotA, gotB, wantA, wantB)
    expect(name, gotA .. "|" .. tostring(gotB), wantA .. "|" .. tostring(wantB))
end

-- insert
do
    local b, p = tb.insert("", 0, "a"); expectPair("insert empty", b, p, "a", 1)
    local b, p = tb.insert("abc", 1, "x"); expectPair("insert middle", b, p, "axbc", 2)
    local b, p = tb.insert("abc", 3, "z"); expectPair("insert at end", b, p, "abcz", 4)
    local b, p = tb.insert("abc", 0, "Z"); expectPair("insert at start", b, p, "Zabc", 1)
end

-- deleteBefore (Backspace)
do
    local b, p = tb.deleteBefore("abc", 3); expectPair("backspace at end", b, p, "ab", 2)
    local b, p = tb.deleteBefore("abc", 0); expectPair("backspace at start (noop)", b, p, "abc", 0)
    local b, p = tb.deleteBefore("abc", 2); expectPair("backspace middle", b, p, "ac", 1)
end

-- deleteAfter (Forward Delete)
do
    local b, p = tb.deleteAfter("abc", 0); expectPair("fwddel at start", b, p, "bc", 0)
    local b, p = tb.deleteAfter("abc", 3); expectPair("fwddel at end (noop)", b, p, "abc", 3)
    local b, p = tb.deleteAfter("abc", 1); expectPair("fwddel middle", b, p, "ac", 1)
end

-- moveLeft / moveRight char
do
    expect("moveLeft char", tb.moveLeft("abc", 2, "char"), 1)
    expect("moveRight char", tb.moveRight("abc", 1, "char"), 2)
    expect("moveLeft char at 0 (noop)", tb.moveLeft("abc", 0, "char"), 0)
    expect("moveRight char at end (noop)", tb.moveRight("abc", 3, "char"), 3)
end

-- moveLeft / moveRight word over "foo bar baz" (len 11)
do
    expect("moveLeft word from end",      tb.moveLeft("foo bar baz", 11, "word"), 8)
    expect("moveLeft word from 8 (start of baz)", tb.moveLeft("foo bar baz", 8, "word"), 4)
    expect("moveLeft word from 4 (start of bar)", tb.moveLeft("foo bar baz", 4, "word"), 0)
    expect("moveRight word from 0",       tb.moveRight("foo bar baz", 0, "word"), 3)
    expect("moveRight word from 3 (end of foo)", tb.moveRight("foo bar baz", 3, "word"), 7)
    expect("moveRight word from 7 (end of bar)", tb.moveRight("foo bar baz", 7, "word"), 11)
end

-- edge
do
    expect("moveLeft edge", tb.moveLeft("foo bar", 5, "edge"), 0)
    expect("moveRight edge", tb.moveRight("foo bar", 2, "edge"), 7)
end

-- caretInLines: byte-walking into wrapped lines + wrap-boundary snap.
do
    -- Stub widthOf = byte count, so x == bytes in the prefix. Keeps the test
    -- math obvious; the real function uses pixel measurements.
    local widthOf = function(s) return #s end

    local lines = { "hello ", "world" }  -- 6 + 5 = 11 bytes, no leading ws
    -- caret at byte 0 → (line 1, col 0)
    local li, x = tb.caretInLines(0, lines, widthOf); expectPair("caretInLines at start", li, x, 1, 0)
    -- caret in middle of line 1
    local li, x = tb.caretInLines(3, lines, widthOf); expectPair("caretInLines mid line1", li, x, 1, 3)
    -- caret AT wrap boundary (byte 6 = end of line1 = start of line2). Must snap to line 2.
    local li, x = tb.caretInLines(6, lines, widthOf); expectPair("caretInLines wrap boundary snaps to next", li, x, 2, 0)
    -- caret inside line 2
    local li, x = tb.caretInLines(8, lines, widthOf); expectPair("caretInLines mid line2", li, x, 2, 2)
    -- caret at end of buffer (last line, end)
    local li, x = tb.caretInLines(11, lines, widthOf); expectPair("caretInLines at end", li, x, 2, 5)
    -- caret past end clamps to last line end
    local li, x = tb.caretInLines(99, lines, widthOf); expectPair("caretInLines past end", li, x, 2, 5)

    -- single line: boundary at end has no next line, so stays at end
    local one = { "abc" }
    local li, x = tb.caretInLines(3, one, widthOf); expectPair("caretInLines single-line end", li, x, 1, 3)

    -- three lines, boundary between lines 2 and 3
    local three = { "abc", "def", "ghi" }
    local li, x = tb.caretInLines(6, three, widthOf); expectPair("caretInLines boundary mid-stack", li, x, 3, 0)
end

-- UTF-8: "héllo" (5 chars, but 6 bytes since é is 2 bytes)
do
    local s = "héllo"
    expect("charLen utf8", tb.charLen(s), 5)
    local b, p = tb.insert(s, 2, "X"); expectPair("insert after é", b, p, "héXllo", 3)
    local b, p = tb.deleteBefore(s, 2); expectPair("backspace removes é", b, p, "hllo", 1)
    local b, p = tb.deleteAfter(s, 1); expectPair("fwddel removes é", b, p, "hllo", 1)
end

local failed = 0
for _, r in ipairs(results) do if not r.pass then failed = failed + 1 end end
local passed = #results - failed
logln(string.format("\n%d/%d scenarios passed", passed, #results))
if logF then logF:close() end
return string.format("%d/%d", passed, #results)
