-- Simulator for HyperlinkHijacker. The module defines a global `handleUrlEvent`
-- whose upvalues are all the module-locals we want to test (passthroughs,
-- browsers, generateChoices, getLastUsedBrowser, saveLastUsedBrowser, ...).
-- We sandbox-load the module per scenario with stubbed hs APIs so the live
-- URL-handler is not touched and `hs.settings` is in-memory.

local LOG_PATH = "/tmp/hyperlinkhijacker-sim.log"
local logF = io.open(LOG_PATH, "w")
local function logln(s) if logF then logF:write(s .. "\n") end end

local L = dofile(hs.configdir .. "/tests/_test_lib.lua")
local deepUpvals = L.deepUpvals

-- ---------- Stub bookkeeping ----------

local realUrleventSetDefault    = hs.urlevent.setDefaultHandler
local realUrleventHttpCallback  = hs.urlevent.httpCallback
local realOpenURLWithBundle     = hs.urlevent.openURLWithBundle
local realSettingsGet           = hs.settings.get
local realSettingsSet           = hs.settings.set
local realChooserNew            = hs.chooser.new
local realCheckKbdMods          = hs.eventtap.checkKeyboardModifiers
local savedHandleUrlEvent       = _G.handleUrlEvent

-- Scenario-scoped state: settings store, last "opened" bundle.
local store          -- in-memory hs.settings backing
local openedBundle   -- string set by stubbed openURLWithBundle
local chooserChoices -- choices passed to the most recent chooser

local function installStubs()
    store = {}
    openedBundle = nil
    chooserChoices = nil

    hs.urlevent.setDefaultHandler = function() end
    hs.urlevent.httpCallback      = nil
    hs.settings.get = function(k) return store[k] end
    hs.settings.set = function(k, v) store[k] = v end
    hs.urlevent.openURLWithBundle = function(_, bundleID) openedBundle = bundleID end
    hs.eventtap.checkKeyboardModifiers = function() return {} end
    -- Capture the chooser so scenarios don't pop UI; return a noop object.
    hs.chooser.new = function(_)
        return {
            choices = function(_, c) chooserChoices = c end,
            show    = function() end,
            delete  = function() end,
            isVisible = function() return false end,
            query   = function() return "" end,
            select  = function() end,
            refreshChoicesCallback = function() end,
        }
    end
end

local function restoreLive()
    hs.urlevent.setDefaultHandler         = realUrleventSetDefault
    hs.urlevent.httpCallback              = realUrleventHttpCallback
    hs.urlevent.openURLWithBundle         = realOpenURLWithBundle
    hs.settings.get                       = realSettingsGet
    hs.settings.set                       = realSettingsSet
    hs.chooser.new                        = realChooserNew
    hs.eventtap.checkKeyboardModifiers    = realCheckKbdMods
    _G.handleUrlEvent                     = savedHandleUrlEvent
end

local function freshModule()
    -- Re-require the module to get a clean closure. Side-effect calls land
    -- in our stubs above.
    package.loaded["HyperlinkHijacker"] = nil
    require("HyperlinkHijacker")
    local handler = _G.handleUrlEvent
    assert(type(handler) == "function", "_G.handleUrlEvent not set after require")
    return handler, deepUpvals(handler)
end

-- ---------- Scenario harness ----------

local results = {}
local function scenario(name, body)
    installStubs()
    local ok, err = pcall(body)
    if not ok then
        table.insert(results, { name = name, pass = false, why = "error: " .. tostring(err) })
        logln(string.format("FAIL  %s", name))
        logln("     error: " .. tostring(err))
        return
    end
    table.insert(results, { name = name, pass = true })
    logln(string.format("PASS  %s", name))
end

local assertEq = L.assertEq

-- ---------- Scenarios ----------

scenario("defaults to first browser as last-used when settings empty", function()
    -- store is empty; expect generateChoices to flag browsers[1] as last-used.
    local _, U = freshModule()
    local choices = U.generateChoices(U.browsers)
    assertEq(choices[1].bundleID, U.browsers[1].bundleID, "first browser is last-used")
    assert(choices[1].subText:find("Last used"), "Last used annotation present")
end)

scenario("settings-stored browser is recognized as last-used after reload", function()
    -- Pre-seed settings, reload, verify the stored browser is at index 1.
    installStubs()
    store["lastUsedBrowser"] = { bundleID = "org.mozilla.firefox", args = { "-private" } }
    local _, U = freshModule()
    local choices = U.generateChoices(U.browsers)
    assertEq(choices[1].bundleID, "org.mozilla.firefox", "Firefox first")
    assertEq(choices[1].args[1], "-private", "Firefox private args preserved")
    assert(choices[1].subText:find("Last used"), "Last used annotation present")
end)

scenario("generateChoices places last-used browser at index 1", function()
    -- Pre-seed settings so a fresh require initializes lastUsedBrowser correctly.
    installStubs()
    store["lastUsedBrowser"] = { bundleID = "com.apple.Safari", args = { "" } }
    local _, U = freshModule()
    local choices = U.generateChoices(U.browsers)
    assertEq(choices[1].bundleID, "com.apple.Safari", "Safari first")
    assert(choices[1].subText:find("Last used"), "Last used annotation present")
    -- All other browsers should still be present; total length unchanged.
    assertEq(#choices, #U.browsers, "choices count == browsers count")
end)

scenario("Spotify URL routes to Spotify passthrough without showing chooser", function()
    local handler, _ = freshModule()
    handler(nil, nil, nil, "https://open.spotify.com/track/abc123")
    assertEq(openedBundle, "com.spotify.client", "Spotify passthrough triggered")
    assert(chooserChoices == nil, "chooser should not have been built for passthrough")
end)

-- ---------- Cleanup ----------

restoreLive()
package.loaded["HyperlinkHijacker"] = nil

local failed = 0
for _, r in ipairs(results) do if not r.pass then failed = failed + 1 end end
local passed = #results - failed
logln(string.format("\n%d/%d scenarios passed", passed, #results))
if logF then logF:close() end
return string.format("%d/%d", passed, #results)
