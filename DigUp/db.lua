-- DigUp: remember everything you've seen on screen.
-- https://github.com/sryo/Spoons/blob/main/DigUp/db.lua - SQLite schema, FTS search, frame queries
local ok_sql, sqlite3 = pcall(require, "hs.sqlite3")
if not ok_sql then
    hs.alert.show("DigUp requires hs.sqlite3")
    print("[DigUp] FATAL: hs.sqlite3 not found. Install from: https://github.com/nicowilliams/lsqlite3")
    return {
        init = function() return false end,
        insertFrame = function() end,
        insertFrameText = function() end,
        updateFrameFullText = function() end,
        findMatchInFrame = function() return {} end,
        search = function() return {} end,
        getTimelineFrames = function() return {} end,
        getFrameById = function() end,
        getOldestFrames = function() return {} end,
        getAdjacentFrame = function() end,
        getDistinctApps = function() return {} end,
        getStats = function() return { totalFrames = 0, totalOCR = 0, distinctApps = 0 } end,
        deleteOldFrames = function() return {} end,
        rebuildFTS = function() end,
        close = function() end,
    }
end

local cfg = require("DigUp.config")

local db = {}
local conn
local hasTrigramTable = false

-- Prepare a statement with nil guard and error logging
local function safePrepare(sql)
    if not conn then return nil end
    local stmt = conn:prepare(sql)
    if not stmt then
        print("[DigUp] prepare failed: " .. (conn:errmsg() or "unknown") .. " | " .. sql:sub(1, 80))
    end
    return stmt
end

-- Space-optimized Levenshtein edit distance
local function levenshtein(s, t)
    local slen, tlen = #s, #t
    if slen == 0 then return tlen end
    if tlen == 0 then return slen end
    if slen > tlen then s, t, slen, tlen = t, s, tlen, slen end
    local prev, curr = {}, {}
    for j = 0, slen do prev[j] = j end
    for i = 1, tlen do
        curr[0] = i
        local tb = t:byte(i)
        for j = 1, slen do
            local cost = (s:byte(j) == tb) and 0 or 1
            curr[j] = math.min(prev[j] + 1, curr[j-1] + 1, prev[j-1] + cost)
        end
        prev, curr = curr, prev
    end
    return prev[slen]
end

function db.init()
    conn = sqlite3.open(cfg.dbPath)
    if not conn then
        print("[DigUp] FATAL: could not open database at " .. cfg.dbPath)
        return false
    end
    conn:exec("PRAGMA journal_mode = WAL")
    conn:exec("PRAGMA synchronous = NORMAL")

    -- Base tables (unchanged)
    conn:exec([[
        CREATE TABLE IF NOT EXISTS frames (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp       REAL    NOT NULL,
            app_bundle      TEXT,
            app_name        TEXT,
            window_title    TEXT,
            screenshot_path TEXT    NOT NULL,
            hash            TEXT    NOT NULL,
            pixel_diff      REAL    DEFAULT 0.0
        );
        CREATE INDEX IF NOT EXISTS idx_frames_timestamp  ON frames(timestamp);
        CREATE INDEX IF NOT EXISTS idx_frames_app_bundle ON frames(app_bundle);

        CREATE TABLE IF NOT EXISTS frame_text (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            frame_id   INTEGER NOT NULL REFERENCES frames(id),
            text       TEXT    NOT NULL,
            x          REAL,
            y          REAL,
            width      REAL,
            height     REAL,
            confidence REAL
        );
        CREATE INDEX IF NOT EXISTS idx_frame_text_frame_id ON frame_text(frame_id);
    ]])

    -- Migration: add full_text column, frame_fts, frame_trigram
    local hasFullText = false
    local hasClipboardText = false
    local pragmaStmt = safePrepare("PRAGMA table_info(frames)")
    if pragmaStmt then
        while pragmaStmt:step() == sqlite3.ROW do
            local colName = pragmaStmt:get_value(1)
            if colName == "full_text" then hasFullText = true end
            if colName == "clipboard_text" then hasClipboardText = true end
        end
        pragmaStmt:finalize()
    end

    -- Add missing columns (handles partial migration from crash)
    if not hasFullText then
        conn:exec("ALTER TABLE frames ADD COLUMN full_text TEXT DEFAULT ''")
    end
    if not hasClipboardText then
        conn:exec("ALTER TABLE frames ADD COLUMN clipboard_text TEXT DEFAULT ''")
    end

    if not hasFullText then
        print("[DigUp] Running schema migration: adding frame_fts")

        -- Drop old per-region FTS and its triggers
        conn:exec("DROP TRIGGER IF EXISTS frame_text_ai")
        conn:exec("DROP TRIGGER IF EXISTS frame_text_ad")
        conn:exec("DROP TRIGGER IF EXISTS frame_text_au")
        conn:exec("DROP TABLE IF EXISTS frame_text_fts")

        -- Create per-frame FTS4 on frames.full_text
        conn:exec("CREATE VIRTUAL TABLE IF NOT EXISTS frame_fts USING fts4(content='frames', full_text)")

        -- Backfill full_text from existing frame_text rows
        conn:exec("UPDATE frames SET full_text = COALESCE((SELECT group_concat(text, ' ') FROM frame_text WHERE frame_id = frames.id), '')")

        -- Populate FTS index
        conn:exec("INSERT INTO frame_fts(frame_fts) VALUES('rebuild')")

        -- Triggers to keep frame_fts in sync with frames.full_text
        conn:exec([[
            CREATE TRIGGER IF NOT EXISTS frame_fts_ai AFTER INSERT ON frames BEGIN
                INSERT INTO frame_fts(docid, full_text) VALUES (new.id, new.full_text);
            END;
        ]])
        conn:exec([[
            CREATE TRIGGER IF NOT EXISTS frame_fts_ad AFTER DELETE ON frames BEGIN
                INSERT INTO frame_fts(frame_fts, docid, full_text) VALUES('delete', old.id, old.full_text);
            END;
        ]])
        conn:exec([[
            CREATE TRIGGER IF NOT EXISTS frame_fts_au AFTER UPDATE OF full_text ON frames BEGIN
                INSERT INTO frame_fts(frame_fts, docid, full_text) VALUES('delete', old.id, old.full_text);
                INSERT INTO frame_fts(docid, full_text) VALUES (new.id, new.full_text);
            END;
        ]])

        print("[DigUp] Schema migration complete")
    else
        -- Ensure FTS4 table and triggers exist (idempotent, for existing migrated DBs)
        conn:exec("CREATE VIRTUAL TABLE IF NOT EXISTS frame_fts USING fts4(content='frames', full_text)")
        conn:exec([[
            CREATE TRIGGER IF NOT EXISTS frame_fts_ai AFTER INSERT ON frames BEGIN
                INSERT INTO frame_fts(docid, full_text) VALUES (new.id, new.full_text);
            END;
        ]])
        conn:exec([[
            CREATE TRIGGER IF NOT EXISTS frame_fts_ad AFTER DELETE ON frames BEGIN
                INSERT INTO frame_fts(frame_fts, docid, full_text) VALUES('delete', old.id, old.full_text);
            END;
        ]])
        conn:exec([[
            CREATE TRIGGER IF NOT EXISTS frame_fts_au AFTER UPDATE OF full_text ON frames BEGIN
                INSERT INTO frame_fts(frame_fts, docid, full_text) VALUES('delete', old.id, old.full_text);
                INSERT INTO frame_fts(docid, full_text) VALUES (new.id, new.full_text);
            END;
        ]])
    end

    -- Backfill: fix frames that have OCR text but empty full_text (caused by trigger failures).
    -- IMPORTANT: runs BEFORE trigram rebuild so the trigram index includes corrected text.
    local backfilled = 0
    local bstmt = safePrepare([[
        UPDATE frames SET full_text = COALESCE(
            (SELECT group_concat(text, char(10)) FROM frame_text WHERE frame_id = frames.id), ''
        ) WHERE full_text = '' AND EXISTS (SELECT 1 FROM frame_text WHERE frame_id = frames.id)
    ]])
    if bstmt then
        bstmt:step()
        bstmt:finalize()
        backfilled = conn:changes() or 0
        if backfilled > 0 then
            print("[DigUp] Backfilled full_text for " .. backfilled .. " frames")
            conn:exec("INSERT INTO frame_fts(frame_fts) VALUES('rebuild')")
        end
    end

    -- FTS5 trigram table for fuzzy substring matching (may not be available).
    -- IMPORTANT: no triggers -- FTS5 trigger failures block the parent UPDATE/INSERT/DELETE,
    -- which was causing full_text to never get set. Trigram is synced manually instead.
    local ok5 = pcall(function()
        -- Drop any leftover trigram triggers from previous versions
        conn:exec("DROP TRIGGER IF EXISTS frame_trigram_ai")
        conn:exec("DROP TRIGGER IF EXISTS frame_trigram_ad")
        conn:exec("DROP TRIGGER IF EXISTS frame_trigram_au")
        conn:exec("CREATE VIRTUAL TABLE IF NOT EXISTS frame_trigram USING fts5(full_text, content='frames', content_rowid='id', tokenize='trigram')")
        conn:exec("INSERT INTO frame_trigram(frame_trigram) VALUES('rebuild')")
    end)
    if ok5 then
        hasTrigramTable = true
        print("[DigUp] FTS5 trigram table available")
    else
        print("[DigUp] FTS5 trigram not available, fuzzy search will use char-drop fallback")
    end

    return true
end

function db.insertFrame(timestamp, appBundle, appName, windowTitle, screenshotPath, hash, pixelDiff, clipboardText)
    local stmt = safePrepare([[
        INSERT INTO frames (timestamp, app_bundle, app_name, window_title, screenshot_path, hash, pixel_diff, clipboard_text)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]])
    if not stmt then return nil end
    stmt:bind_values(timestamp, appBundle, appName, windowTitle, screenshotPath, hash, pixelDiff or 0.0, clipboardText or "")
    stmt:step()
    stmt:finalize()
    return conn:last_insert_rowid()
end

function db.insertFrameText(frameId, text, x, y, width, height, confidence)
    local stmt = safePrepare([[
        INSERT INTO frame_text (frame_id, text, x, y, width, height, confidence)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]])
    if not stmt then return end
    stmt:bind_values(frameId, text, x, y, width, height, confidence)
    stmt:step()
    stmt:finalize()
end

function db.updateFrameFullText(frameId, fullText)
    fullText = fullText or ""
    -- Core UPDATE: triggers frame_fts_au (FTS4, reliable). No trigram trigger.
    local stmt = safePrepare("UPDATE frames SET full_text = ? WHERE id = ?")
    if not stmt then return end
    stmt:bind_values(fullText, frameId)
    stmt:step()
    stmt:finalize()

    -- Manually sync FTS5 trigram (pcall so failure never blocks core indexing)
    if hasTrigramTable then
        pcall(function()
            -- Delete old entry (empty string from insertFrame's DEFAULT '')
            local d = conn:prepare("INSERT INTO frame_trigram(frame_trigram, rowid, full_text) VALUES('delete', ?, ?)")
            if d then
                d:bind_values(frameId, "")
                d:step()
                d:finalize()
            end
            -- Insert new entry with actual text
            local i = conn:prepare("INSERT INTO frame_trigram(rowid, full_text) VALUES (?, ?)")
            if i then
                i:bind_values(frameId, fullText)
                i:step()
                i:finalize()
            end
        end)
    end
end

-- Find all matching OCR regions in a specific frame for a query.
-- Uses LIKE on frame_text (per-region table) for highlight positioning.
-- Returns array of {x, y, w, h} (empty table if no matches).
function db.findMatchInFrame(frameId, query)
    local all = {}
    for w in query:gmatch("%S+") do all[#all + 1] = w end
    if #all == 0 then return {} end

    -- Filter out short words to avoid highlighting every region.
    -- In "status of the project", "of" and "the" match nearly everything.
    local hasLong = false
    for _, w in ipairs(all) do if #w >= 4 then hasLong = true; break end end

    local words = {}
    local minLen = hasLong and 4 or 3
    if #all > 1 then
        for _, w in ipairs(all) do
            if #w >= minLen then words[#words + 1] = w end
        end
    end
    -- Fallback: single word or all words were too short
    if #words == 0 then words = all end

    -- Build OR conditions: find any region matching any query word
    local conditions = {}
    local binds = { frameId }
    for _, w in ipairs(words) do
        conditions[#conditions + 1] = "text LIKE ?"
        binds[#binds + 1] = "%" .. w .. "%"
    end

    local sql = "SELECT DISTINCT x, y, width, height FROM frame_text WHERE frame_id = ? AND ("
        .. table.concat(conditions, " OR ") .. ")"
    local stmt = safePrepare(sql)
    if not stmt then return {} end
    stmt:bind_values(table.unpack(binds))
    local results = {}
    while stmt:step() == sqlite3.ROW do
        local vals = stmt:get_values()
        results[#results + 1] = { x = vals[1], y = vals[2], w = vals[3], h = vals[4] }
    end
    stmt:finalize()
    return results
end

-- Split query into words, each with prefix matching, ANDed together.
-- "hello world" -> "hello* world*"
-- Single-char words are dropped in multi-word queries (e.g. "had someone t"
-- becomes "had* someone*") because a prefix like "t*" matches nearly every
-- token and floods the result set with noise.
local function buildMatchExpr(query)
    local all = {}
    for w in query:gmatch("%S+") do all[#all + 1] = w end

    local words = {}
    if #all > 1 then
        for _, w in ipairs(all) do
            w = w:gsub("[^%w]", "")  -- strip punctuation
            if #w >= 2 then words[#words + 1] = w .. "*" end
        end
    end
    -- Fallback: single-word query, or all words were single-char
    if #words == 0 then
        for _, w in ipairs(all) do
            w = w:gsub("[^%w]", "")  -- strip punctuation
            if #w > 0 then words[#words + 1] = w .. "*" end
        end
    end
    return table.concat(words, " ")
end

-- Search frame_fts (per-frame full_text) instead of per-region frame_text_fts
local function runSearch(matchExpr, limit)
    local results = {}
    local stmt = safePrepare([[
        SELECT f.id, f.timestamp, f.app_name, f.window_title, f.screenshot_path,
               CASE WHEN f.full_text = '' OR f.full_text IS NULL
                    THEN (SELECT group_concat(text, ' ') FROM frame_text WHERE frame_id = f.id)
                    ELSE f.full_text
               END AS full_text
        FROM frame_fts fts
        JOIN frames f ON f.id = fts.docid
        WHERE fts.full_text MATCH ?
        ORDER BY f.timestamp DESC
        LIMIT ?
    ]])
    if not stmt then return results end
    stmt:bind_values(matchExpr, limit)
    while stmt:step() == sqlite3.ROW do
        local vals = stmt:get_values()
        results[#results + 1] = {
            frameId        = vals[1],
            timestamp      = vals[2],
            appName        = vals[3],
            windowTitle    = vals[4],
            screenshotPath = vals[5],
            matchedText    = vals[6],
        }
    end
    stmt:finalize()
    return results
end

-- Search frame_trigram (FTS5 trigram) for fuzzy substring matching
local function runTrigramSearch(query, limit)
    local results = {}
    if not hasTrigramTable then return results end
    local stmt = safePrepare([[
        SELECT f.id, f.timestamp, f.app_name, f.window_title, f.screenshot_path,
               CASE WHEN f.full_text = '' OR f.full_text IS NULL
                    THEN (SELECT group_concat(text, ' ') FROM frame_text WHERE frame_id = f.id)
                    ELSE f.full_text
               END AS full_text
        FROM frame_trigram tri
        JOIN frames f ON f.id = tri.rowid
        WHERE frame_trigram MATCH ?
        ORDER BY f.timestamp DESC
        LIMIT ?
    ]])
    if not stmt then return results end
    -- Quote the query for trigram matching
    stmt:bind_values('"' .. query:gsub('"', '') .. '"', limit)
    while stmt:step() == sqlite3.ROW do
        local vals = stmt:get_values()
        results[#results + 1] = {
            frameId        = vals[1],
            timestamp      = vals[2],
            appName        = vals[3],
            windowTitle    = vals[4],
            screenshotPath = vals[5],
            matchedText    = vals[6],
        }
    end
    stmt:finalize()
    return results
end

-- Merge consecutive results from the same window into events with duration.
-- Results must be timestamp DESC. Same (appName, windowTitle) within mergeGap
-- seconds collapse into one event with firstTimestamp/lastTimestamp/frameCount.
local function mergeIntoEvents(results, mergeGap)
    mergeGap = mergeGap or cfg.eventMergeGap or 10
    local events = {}
    local lastKey
    local currentEvent

    for _, r in ipairs(results) do
        local key = (r.appName or "") .. "\0" .. (r.windowTitle or "")
        local ts = r.timestamp or 0

        local shouldMerge = false
        if currentEvent and key == lastKey then
            local gap = currentEvent.firstTimestamp - ts
            if gap >= 0 and gap <= mergeGap then
                shouldMerge = true
            end
        end

        if shouldMerge then
            currentEvent.firstTimestamp = ts
            currentEvent.frameCount = currentEvent.frameCount + 1
            -- Prefer non-empty text when the leading frame had none
            if (not currentEvent.matchedText or currentEvent.matchedText == "") and r.matchedText and r.matchedText ~= "" then
                currentEvent.matchedText = r.matchedText
            end
        else
            currentEvent = {
                frameId        = r.frameId,
                timestamp      = r.timestamp,
                lastTimestamp  = r.timestamp,
                firstTimestamp = r.timestamp,
                appName        = r.appName,
                windowTitle    = r.windowTitle,
                screenshotPath = r.screenshotPath,
                matchedText    = r.matchedText,
                frameCount     = 1,
            }
            events[#events + 1] = currentEvent
        end
        lastKey = key
    end

    -- Compute duration for each event
    for _, e in ipairs(events) do
        e.duration = e.lastTimestamp - e.firstTimestamp
    end

    return events
end

-- Composite scoring: relevance (edit distance) + keyword boost + recency
local function scoreAndRank(results, query)
    local queryLower = query:lower()
    local queryLen = #queryLower
    if queryLen == 0 then return results end

    -- 1. Edit distance (best match against any word in full_text)
    for _, r in ipairs(results) do
        local best = queryLen + 1
        local text = (r.matchedText or ""):lower()
        for word in text:gmatch("%S+") do
            local d = levenshtein(queryLower, word)
            if d < best then best = d end
        end
        r._editDist = best
    end

    -- 2. Timestamp range for relative recency
    local minTs, maxTs = math.huge, 0
    for _, r in ipairs(results) do
        local ts = r.timestamp or 0
        if ts < minTs then minTs = ts end
        if ts > maxTs then maxTs = ts end
    end
    local tsRange = maxTs - minTs
    if tsRange == 0 then tsRange = 1 end

    -- 3. Composite score per result
    for _, r in ipairs(results) do
        -- Relevance: 1.0 for exact match, 0.0 for editDist >= queryLen
        local relevance = math.max(0, 1 - r._editDist / queryLen)

        -- Keyword boost: 0.5 for exact substring, 0.3 scaled for partial words
        local text = (r.matchedText or ""):lower()
        local keywordBoost = 0
        if text:find(queryLower, 1, true) then
            keywordBoost = 0.5
        else
            local qWords = {}
            for w in queryLower:gmatch("%S+") do
                if #w >= 3 then qWords[#qWords + 1] = w end
            end
            if #qWords > 0 then
                local matched = 0
                for _, w in ipairs(qWords) do
                    if text:find(w, 1, true) then matched = matched + 1 end
                end
                if matched > 0 then
                    keywordBoost = 0.3 * matched / #qWords
                end
            end
        end

        -- Recency: [0, 0.1] within result set (mild tiebreaker)
        local recency = 0.1 * ((r.timestamp or 0) - minTs) / tsRange

        r._score = relevance + keywordBoost + recency
    end

    table.sort(results, function(a, b) return a._score > b._score end)
    return results
end

function db.search(query, limit)
    limit = limit or 50

    -- Tier 1: FTS4 prefix match (fast path)
    local expr = buildMatchExpr(query)
    local raw = runSearch(expr, limit * 5)
    local results = mergeIntoEvents(raw)

    -- Tier 2: FTS5 trigram substring match (if no results and query >= 3 chars)
    if #results == 0 and #query >= 3 and hasTrigramTable then
        raw = runTrigramSearch(query, limit * 3)
        results = mergeIntoEvents(raw)
        if #results > 0 then
            results = scoreAndRank(results, query)
        end
    end

    -- Trim to requested limit
    while #results > limit do table.remove(results) end
    return results
end

function db.getTimelineFrames(limit, offset)
    limit = limit or 50
    offset = offset or 0
    local results = {}
    local stmt = safePrepare([[
        SELECT id, timestamp, app_name, window_title, screenshot_path
        FROM frames
        ORDER BY timestamp DESC
        LIMIT ? OFFSET ?
    ]])
    if not stmt then return results end
    stmt:bind_values(limit, offset)
    while stmt:step() == sqlite3.ROW do
        local vals = stmt:get_values()
        results[#results + 1] = {
            frameId        = vals[1],
            timestamp      = vals[2],
            appName        = vals[3],
            windowTitle    = vals[4],
            screenshotPath = vals[5],
        }
    end
    stmt:finalize()
    return results
end

function db.getFrameById(frameId)
    local stmt = safePrepare([[
        SELECT id, timestamp, app_name, window_title, screenshot_path
        FROM frames WHERE id = ?
    ]])
    if not stmt then return nil end
    stmt:bind_values(frameId)
    local result
    if stmt:step() == sqlite3.ROW then
        local vals = stmt:get_values()
        result = {
            id             = vals[1],
            timestamp      = vals[2],
            appName        = vals[3],
            windowTitle    = vals[4],
            screenshotPath = vals[5],
        }
    end
    stmt:finalize()
    return result
end

function db.getOldestFrames(limit)
    limit = limit or 50
    local results = {}
    local stmt = safePrepare([[
        SELECT id, timestamp, app_name, window_title, screenshot_path
        FROM frames
        ORDER BY timestamp ASC
        LIMIT ?
    ]])
    if not stmt then return results end
    stmt:bind_values(limit)
    while stmt:step() == sqlite3.ROW do
        local vals = stmt:get_values()
        results[#results + 1] = {
            id             = vals[1],
            timestamp      = vals[2],
            appName        = vals[3],
            windowTitle    = vals[4],
            screenshotPath = vals[5],
        }
    end
    stmt:finalize()
    return results
end

function db.getAdjacentFrame(frameId, direction)
    if type(direction) ~= "number" then return nil end
    local stmt
    if direction > 0 then
        stmt = safePrepare([[
            SELECT id, timestamp, app_name, window_title, screenshot_path
            FROM frames WHERE id > ? ORDER BY id ASC LIMIT 1
        ]])
    else
        stmt = safePrepare([[
            SELECT id, timestamp, app_name, window_title, screenshot_path
            FROM frames WHERE id < ? ORDER BY id DESC LIMIT 1
        ]])
    end
    if not stmt then return nil end
    stmt:bind_values(frameId)
    local result
    if stmt:step() == sqlite3.ROW then
        local vals = stmt:get_values()
        result = {
            id             = vals[1],
            timestamp      = vals[2],
            appName        = vals[3],
            windowTitle    = vals[4],
            screenshotPath = vals[5],
        }
    end
    stmt:finalize()
    return result
end

function db.getDistinctApps()
    local apps = {}
    local stmt = safePrepare("SELECT DISTINCT app_bundle, app_name FROM frames ORDER BY app_name")
    if not stmt then return apps end
    while stmt:step() == sqlite3.ROW do
        local vals = stmt:get_values()
        apps[#apps + 1] = { bundle = vals[1], name = vals[2] }
    end
    stmt:finalize()
    return apps
end

function db.getStats()
    local stats = {}
    local function scalar(sql)
        local stmt = safePrepare(sql)
        if not stmt then return nil end
        stmt:step()
        local val = stmt:get_value(0)
        stmt:finalize()
        return val
    end
    stats.totalFrames = scalar("SELECT count(*) FROM frames") or 0
    stats.totalOCR    = scalar("SELECT count(*) FROM frame_text") or 0
    stats.distinctApps = scalar("SELECT count(DISTINCT app_bundle) FROM frames") or 0
    stats.oldestFrame = scalar("SELECT min(timestamp) FROM frames")
    stats.newestFrame = scalar("SELECT max(timestamp) FROM frames")
    return stats
end

function db.deleteOldFrames(timestamp)
    local paths = {}
    local stmt = safePrepare("SELECT screenshot_path FROM frames WHERE timestamp < ?")
    if not stmt then return paths end
    stmt:bind_values(timestamp)
    while stmt:step() == sqlite3.ROW do
        local vals = stmt:get_values()
        if vals[1] then
            table.insert(paths, vals[1])
        end
    end
    stmt:finalize()

    if #paths > 0 then
        conn:exec("BEGIN TRANSACTION;")
        local ok = true

        -- Delete OCR text (per-region data for highlighting)
        local stmt1 = safePrepare("DELETE FROM frame_text WHERE frame_id IN (SELECT id FROM frames WHERE timestamp < ?)")
        if stmt1 then
            stmt1:bind_values(timestamp)
            if stmt1:step() ~= sqlite3.DONE then ok = false end
            stmt1:finalize()
        else
            ok = false
        end

        -- Delete frames (triggers handle frame_fts and frame_trigram cleanup)
        if ok then
            local stmt2 = safePrepare("DELETE FROM frames WHERE timestamp < ?")
            if stmt2 then
                stmt2:bind_values(timestamp)
                stmt2:step()
                stmt2:finalize()
            end
        end

        conn:exec(ok and "COMMIT;" or "ROLLBACK;")
    end

    return paths
end

-- Rebuild FTS indices (useful after crashes or corruption)
function db.rebuildFTS()
    if not conn then return end
    conn:exec("INSERT INTO frame_fts(frame_fts) VALUES('rebuild')")
    if hasTrigramTable then
        pcall(function()
            conn:exec("INSERT INTO frame_trigram(frame_trigram) VALUES('rebuild')")
        end)
    end
end

function db.close()
    if conn then conn:close() end
end

return db
