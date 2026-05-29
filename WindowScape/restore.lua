-- WindowScape session restore: persist per-space window order + weights to a
-- JSON sidecar so the hand-arranged layout survives hs.reload().
--
-- Save shape:
--   { "<spaceID>": [ { bundleID, title, weight }, ... ], ... }
--
-- spaceID is the integer hs.spaces returns, stringified by JSON. Title is the
-- first 40 chars and is used only as a tiebreaker when multiple windows of the
-- same app are live in the same space.

local json  = require("hs.json")
local timer = require("hs.timer")

local M = {}

local cfg
local core
local tiler

local path
local saveTimer
local SAVE_DEBOUNCE = 0.5
local TITLE_HINT_LEN = 40

local function titleHint(win)
    if not win then return "" end
    local t = win:title() or ""
    return string.sub(t, 1, TITLE_HINT_LEN)
end

local function bundleIDOf(win)
    if not win then return nil end
    local app = core.safeGetApplication(win)
    if not app then return nil end
    return app:bundleID()
end

-- Atomic write so a failed write doesn't lose the sidecar.
local function writeSync()
    if not path then return end
    local payload = {}
    for spaceId, order in pairs(core.windowOrderBySpace) do
        local slots = {}
        for _, win in ipairs(order) do
            local bid = bundleIDOf(win)
            local winId = win:id()
            if bid and winId then
                table.insert(slots, {
                    bundleID = bid,
                    title    = titleHint(win),
                    weight   = core.windowWeights[winId] or cfg.widthDefault or 1.0,
                })
            end
        end
        if #slots > 0 then
            payload[tostring(spaceId)] = slots
        end
    end

    local tmp = path .. ".tmp"
    local ok, err = json.write(payload, tmp, true, true)
    if not ok then
        core.warn("Failed to write layout sidecar: " .. tostring(err))
        return
    end
    local renamed, renameErr = os.rename(tmp, path)
    if not renamed then
        core.warn("Failed to rename layout sidecar: " .. tostring(renameErr))
        os.remove(tmp)
    end
end
M.writeSync = writeSync

function M.scheduleSave()
    if not path then return end
    if saveTimer then saveTimer:stop() end
    saveTimer = timer.doAfter(SAVE_DEBOUNCE, writeSync)
end

-- Read the sidecar and reorder core.windowOrderBySpace + restore weights for
-- windows currently live. Unmatched saved slots are dropped; live windows not
-- claimed by any slot keep their existing position appended after the matched ones.
function M.load()
    if not path then return end
    local payload = json.read(path)
    if type(payload) ~= "table" then return end

    for spaceKey, slots in pairs(payload) do
        local spaceId = tonumber(spaceKey) or spaceKey
        local liveOrder = core.windowOrderBySpace[spaceId]
        if liveOrder and #liveOrder > 0 and type(slots) == "table" then
            local claimed = {}  -- winId -> true
            local matched = {}  -- in saved-slot order

            -- Pass 1: prefer windows whose title starts with the saved hint.
            for _, slot in ipairs(slots) do
                local target = slot.bundleID
                local hint   = slot.title or ""
                local pick
                for _, win in ipairs(liveOrder) do
                    local winId = win:id()
                    if winId and not claimed[winId] and bundleIDOf(win) == target then
                        if hint ~= "" and string.sub(win:title() or "", 1, TITLE_HINT_LEN) == hint then
                            pick = win
                            break
                        end
                    end
                end
                -- Pass 2: any window with the right bundleID.
                if not pick then
                    for _, win in ipairs(liveOrder) do
                        local winId = win:id()
                        if winId and not claimed[winId] and bundleIDOf(win) == target then
                            pick = win
                            break
                        end
                    end
                end
                if pick then
                    claimed[pick:id()] = true
                    table.insert(matched, { win = pick, weight = slot.weight })
                end
            end

            local newOrder = {}
            for _, m in ipairs(matched) do
                table.insert(newOrder, m.win)
                if m.weight and m.win:id() then
                    core.windowWeights[m.win:id()] = m.weight
                end
            end
            for _, win in ipairs(liveOrder) do
                local winId = win:id()
                if winId and not claimed[winId] then
                    table.insert(newOrder, win)
                end
            end

            core.windowOrderBySpace[spaceId] = newOrder
        end
    end
end

function M.init(config, deps)
    cfg   = config
    core  = deps.core
    tiler = deps.tiler
    path  = (hs and hs.configdir or os.getenv("HOME") .. "/.hammerspoon") .. "/WindowScape_layout.json"
end

function M.getPath()
    return path
end

function M.cleanup()
    if saveTimer then saveTimer:stop(); saveTimer = nil end
end

return M
