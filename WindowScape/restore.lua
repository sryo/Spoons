-- WindowScape session restore: persist per-space window order + weights and
-- the currently-minimized snapshots to a JSON sidecar so the hand-arranged
-- layout and minimize state survive hs.reload().
--
-- Save shape (v2):
--   {
--     spaces    = { "<spaceID>": [ { bundleID, title, weight }, ... ], ... },
--     snapshots = [ { winId, bundleID, title, originalFrame, screenId, snapSize }, ... ],
--   }
--
-- Legacy v1 (a bare spaces map with no wrapper) is read transparently.
--
-- Snapshots match on winId only (`hs.window.get`). winIds survive hs.reload
-- but not app close or system reboot. Layout slots fall back to bundleID +
-- title so layout restoration is more forgiving across restarts.

local json   = require("hs.json")
local timer  = require("hs.timer")
local window = require("hs.window")

local M = {}

local cfg
local core
local tiler
local snapshotCreate

local path
local saveTimer
local SAVE_DEBOUNCE = 0.5
local TITLE_HINT_LEN = 40

local function titleHint(win)
    if not win then return "" end
    return string.sub(win:title() or "", 1, TITLE_HINT_LEN)
end

local function bundleIDOf(win)
    if not win then return nil end
    local app = core.safeGetApplication(win)
    if not app then return nil end
    return app:bundleID()
end

local function writeSync()
    if not path then return end

    local payload = { spaces = {}, snapshots = {} }

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
            payload.spaces[tostring(spaceId)] = slots
        end
    end

    if core.snapshotsState then
        for _, winId in ipairs(core.snapshotsState.order) do
            local data = core.snapshotsState.windows[winId]
            local win = data and data.win
            local bid = win and bundleIDOf(win)
            if data and win and bid and data.originalFrame and data.snapSize then
                table.insert(payload.snapshots, {
                    winId         = winId,
                    bundleID      = bid,
                    title         = titleHint(win),
                    originalFrame = {
                        x = data.originalFrame.x, y = data.originalFrame.y,
                        w = data.originalFrame.w, h = data.originalFrame.h,
                    },
                    screenId      = data.screenId,
                    snapSize      = { w = data.snapSize.w, h = data.snapSize.h },
                })
            end
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

-- Returns (spacesMap, snapshotsArray). Handles both v2 (wrapped) and v1 (flat)
-- save shapes; on v1, snapshotsArray is empty.
function M.readPayload()
    if not path then return {}, {} end
    local raw = json.read(path)
    if type(raw) ~= "table" then return {}, {} end
    if raw.spaces or raw.snapshots then
        return raw.spaces or {}, raw.snapshots or {}
    end
    return raw, {}
end

-- Iterate saved snapshots, find the matching live window by winId, and
-- re-register the snapshot via snapshotCreate.createSnapshot in restore mode.
-- Must run BEFORE core.updateWindowOrder so the rehydrated windows are
-- excluded from tiling (core.isAppIncluded skips winIds present in
-- snapshotsState.windows).
function M.loadSnapshots(snapshotPayload)
    if not snapshotCreate then return end
    if snapshotPayload == nil then
        _, snapshotPayload = M.readPayload()
    end
    for _, entry in ipairs(snapshotPayload) do
        local savedWinId = entry.winId
        if savedWinId then
            local win = window.get(savedWinId)
            if win and bundleIDOf(win) == entry.bundleID then
                snapshotCreate.createSnapshot(win, {
                    originalFrame = entry.originalFrame,
                    snapSize      = entry.snapSize,
                    screenId      = entry.screenId,
                })
            end
        end
    end
end

-- Reorder core.windowOrderBySpace + restore weights for windows present in the
-- spaces payload. Must run AFTER core.updateWindowOrder so windowOrderBySpace
-- is populated. Unmatched saved slots are dropped; live windows not claimed by
-- any slot keep their existing position appended after the matched ones.
function M.loadLayout(spacesPayload)
    if spacesPayload == nil then
        spacesPayload = M.readPayload()
    end

    for spaceKey, slots in pairs(spacesPayload) do
        local spaceId = tonumber(spaceKey) or spaceKey
        local liveOrder = core.windowOrderBySpace[spaceId]
        if liveOrder and #liveOrder > 0 and type(slots) == "table" then
            local claimed = {}
            local matched = {}

            for _, slot in ipairs(slots) do
                local target = slot.bundleID
                local hint   = slot.title or ""
                local pick

                if hint ~= "" then
                    for _, win in ipairs(liveOrder) do
                        local winId = win:id()
                        if winId and not claimed[winId] and bundleIDOf(win) == target then
                            if string.sub(win:title() or "", 1, TITLE_HINT_LEN) == hint then
                                pick = win
                                break
                            end
                        end
                    end
                end
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

-- Legacy single-call API kept for any external caller; equivalent to loadLayout.
function M.load() M.loadLayout() end

function M.init(config, deps)
    cfg            = config
    core           = deps.core
    tiler          = deps.tiler
    snapshotCreate = deps.snapshotCreate
    path = (hs and hs.configdir or os.getenv("HOME") .. "/.hammerspoon") .. "/WindowScape_layout.json"
end

function M.getPath() return path end

function M.cleanup()
    if saveTimer then saveTimer:stop(); saveTimer = nil end
end

return M
