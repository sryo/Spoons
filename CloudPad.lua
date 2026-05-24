local http = require("hs.httpserver")
local eventtap = require("hs.eventtap")
local keycodes = require("hs.keycodes")
local json = require("hs.json")
local pasteboard = require("hs.pasteboard")
local hotkey = require("hs.hotkey")
local alert = require("hs.alert")
local mouse = require("hs.mouse")
local screen = require("hs.screen")
local image = require("hs.image")

-- ==========================================
--               CONFIGURATION
-- ==========================================
local SCROLL_AMOUNT = 15
local PORT = 1984
-- Width to resize screenshot to (smaller = faster)
-- 480px is plenty for a phone screen preview
local PREVIEW_WIDTH = 480
-- ==========================================

-- Capture Full Screen, Resize it, Return it
local function captureFullScreenPreview()
    -- 1. Find screen with mouse
    local mousePos = mouse.absolutePosition()
    local targetScreen = mouse.getCurrentScreen()

    -- Fallback mechanism
    if not targetScreen then
        targetScreen = screen.mainScreen()
    end

    -- 2. Snapshot
    local snap = targetScreen:snapshot()
    if not snap then return nil end

    -- 3. Resize for Performance (Crucial Step)
    -- Calculate height to maintain aspect ratio
    local size = snap:size()
    local ratio = size.h / size.w
    local newHeight = math.floor(PREVIEW_WIDTH * ratio)

    -- Resize the image object in memory
    snap:setSize({ w = PREVIEW_WIDTH, h = newHeight })

    -- 4. Return image + Cursor Position (0.0 - 1.0) relative to that screen
    local frame = targetScreen:fullFrame()
    local relX = (mousePos.x - frame.x) / frame.w
    local relY = (mousePos.y - frame.y) / frame.h

    return snap, relX, relY
end

-- Mouse Movement Logic
local function moveMouseRelative(dx, dy)
    local current = mouse.absolutePosition()

    -- Standard Acceleration Curve
    local velocity = math.sqrt(dx ^ 2 + dy ^ 2)
    local multiplier = 1.2
    if velocity > 5.0 then multiplier = 2.5 end
    if velocity > 20.0 then multiplier = 5.0 end

    local newX = current.x + (dx * multiplier)
    local newY = current.y + (dy * multiplier)
    mouse.absolutePosition({ x = newX, y = newY })
end

local keyCodes = setmetatable({}, { __index = function(_, key) return keycodes.map[key] end })
local modifierMap = { shift = "shift", ctrl = "ctrl", cmd = "cmd", alt = "alt", fn = "fn" }

local html = [[
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width, viewport-fit=cover, initial-scale=1.0, maximum-scale=1.0, user-scalable=no"/>
<title>CloudPad</title>
<link rel="manifest" href="/manifest.json">
<link rel="stylesheet" href="/app.css">
<script>
if ('serviceWorker' in navigator) { navigator.serviceWorker.register('/sw.js', { scope: '/' }); }
</script>
</head>
<body>

<div class="screenshot-container">
  <div id="screenshot"></div>
  <div id="server-cursor"></div>
</div>

<div id="local-cursor"></div>

<div class="keyboard main active">
<div class="row"><button data-key="1" data-shift="!" data-option="|" class="key">1</button><button data-key="2" data-shift="/"" data-option="@" class="key">2</button><button data-key="3" data-shift="·" data-option="#" class="key">3</button><button data-key="4" data-shift="$" data-option="¢" class="key">4</button><button data-key="5" data-shift="%" data-option="∞" class="key">5</button><button data-key="6" data-shift="&" data-option="¬" class="key">6</button><button data-key="7" data-shift="/" data-option="÷" class="key">7</button><button data-key="8" data-shift="(" data-option="“" class="key">8</button><button data-key="9" data-shift=")" data-option="”" class="key">9</button><button data-key="0" data-shift="=" data-option="≠" class="key">0</button></div>
<div class="row"><button data-key="q" data-shift="Q" data-option="œ" class="key">q</button><button data-key="w" data-shift="W" data-option="æ" class="key">w</button><button data-key="e" data-shift="E" data-option="€" class="key">e</button><button data-key="r" data-shift="R" data-option="®" class="key">r</button><button data-key="t" data-shift="T" data-option="†" class="key">t</button><button data-key="y" data-shift="Y" data-option="¥" class="key">y</button><button data-key="u" data-shift="U" data-option=" " class="key">u</button><button data-key="i" data-shift="I" data-option=" " class="key">i</button><button data-key="o" data-shift="O" data-option="ø" class="key">o</button><button data-key="p" data-shift="P" data-option="π" class="key">p</button></div>
<div class="row"><button data-key="a" data-shift="A" data-option="å" class="key">a</button><button data-key="s" data-shift="S" data-option="∫" class="key">s</button><button data-key="d" data-shift="D" data-option="∂" class="key">d</button><button data-key="f" data-shift="F" data-option="ƒ" class="key">f</button><button data-key="g" data-shift="G" data-option="" class="key">g</button><button data-key="h" data-shift="H" data-option="™" class="key">h</button><button data-key="j" data-shift="J" data-option="¶" class="key">j</button><button data-key="k" data-shift="K" data-option="§" class="key">k</button><button data-key="l" data-shift="L" data-option=" " class="key">l</button><button data-key="ñ" data-shift="Ñ" data-option="~" class="key">ñ</button></div>
<div class="row"><button data-modifier="shift" class="key mod">⇧</button><button data-key="z" data-shift="Z" data-option="Ω" class="key">z</button><button data-key="x" data-shift="X" data-option="∑" class="key">x</button><button data-key="c" data-shift="C" data-option="©" class="key">c</button><button data-key="v" data-shift="V" data-option="√" class="key">v</button><button data-key="b" data-shift="B" data-option="ß" class="key">b</button><button data-key="n" data-shift="N" data-option=" " class="key">n</button><button data-key="m" data-shift="M" data-option="µ" class="key">m</button><button data-key="." data-shift=":" data-option="…" class="key">.</button><button data-key="backspace" class="key">⌫</button></div>
<div class="row"><button data-key="escape" class="key">⎋</button><button data-modifier="ctrl" class="key mod">⌃</button><button data-modifier="symbols" class="key mod">#</button><button data-modifier="alt" class="key mod">⌥</button><button data-modifier="cmd" class="key mod">⌘</button><button data-key="space" class="key space">␣</button><button data-modifier="fn" class="key">fn</button><button data-key="return" class="key">↵</button></div>
</div>
<div class="keyboard symbols">
<div class="row"><button data-key="left" class="key">←</button><button data-key="right" class="key">→</button><button data-key="up" class="key">↑</button><button data-key="down" class="key">↓</button><button data-mouse="scrollup" class="key">🠉</button><button data-mouse="scrolldown" class="key">🠋</button><button data-mouse="doubleclick" class="key">️L</button><button data-mouse="middleclick" class="key">M</button><button data-mouse="rightclick" class="key"> R</button><button data-key="delete" class="key">⌦</button></div>
<div class="row"><button data-key="tab" class="key">⇥</button><button data-modifier="ctrl" class="key mod">⌃</button><button data-modifier="symbols" class="key mod">#</button><button data-modifier="alt" class="key mod">⌥</button><button data-modifier="cmd" class="key mod">⌘</button><button data-key="space" class="key space"></button><button data-key="fn" class="key">fn</button><button data-key="return" class="key">⏎</button></div>
</div>
<script src="/app.js"></script>
</body>
</html>
]]

local css = [[
* { margin: 0; padding: 0; box-sizing: border-box; touch-action: none; }
html { user-select: none; }
body { background: #111; height: 100vh; display: flex; justify-content: center; align-items: center; margin: 4px; overscroll-behavior: none; overflow: hidden; }
.keyboard { display: none; position: absolute; width: 100%; height: 100%; flex-direction: column; transition: opacity 0.2s; padding: env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left); }
.keyboard.active { display: flex; }
.mouse-mode .keyboard { opacity: 0.1; pointer-events: none; }
.row { display: flex; justify-content: center; flex-grow: 1; }
.key { background: #000; color: white; border: none; border-radius: 10px; margin: 2px; padding: 0px; font-size: clamp(12px, 6vw, 48px); text-box-trim: trim-both; cursor: pointer; flex: 1; transition: all 0.1s; }
.key:not(.mod).active { background: #666; scale: 2; translate: 0 -20vh; transition: all 0s; }
.mod.active { background: #007AFF; }
.space { flex: 3; }
.mod { flex: 1; background: #222; }

/* PREVIEW CONTAINER */
.screenshot-container {
    position: fixed; top: 0; left: 0; width: 100vw; height: 100vh;
    overflow: hidden; pointer-events: none; display: none;
    background: #000;
    display: flex; justify-content: center; align-items: center;
}
#screenshot {
    width: 100%; height: 100%;
    background-repeat: no-repeat;
    background-position: center;
    background-size: contain; /* Shows full screen scaled down */
}

/* Red Dot: Local Finger Position */
#local-cursor {
    position: fixed; width: 40px; height: 40px;
    border: 2px solid rgba(255, 0, 0, 0.8);
    border-radius: 50%; pointer-events: none;
    transform: translate(-50%, -50%); z-index: 10000; display: none;
}

/* Blue Dot: Server Mouse Position (Relative to screen) */
#server-cursor {
    position: absolute; width: 10px; height: 10px;
    background: cyan; border-radius: 50%;
    box-shadow: 0 0 5px cyan;
    transform: translate(-50%, -50%);
    /* We will set left/top via JS percentage */
    display: none;
}
]]

local js = [[
const state = { activeTouches: new Map(), activeModifiers: new Set(), mouseMode: false, lastClickTime: 0, pendingKeys: new Map(), scrollSpeed: 3, currentLayer: 'main', layers: { main: document.querySelector('.main'), symbols: document.querySelector('.symbols') }, lastTouchX: window.innerWidth / 2, lastTouchY: window.innerHeight / 2 };
const TOUCH_THRESHOLD = 5;
const LONG_PRESS_DURATION = 500;

// === MOUSE QUEUE (INSTANT) ===
let mouseState = { dx: 0, dy: 0, isSending: false };
function queueMouseMovement(dx, dy) {
    mouseState.dx += dx;
    mouseState.dy += dy;
    processMouseQueue();
}
function processMouseQueue() {
    if (mouseState.isSending) return;
    if (mouseState.dx === 0 && mouseState.dy === 0) return;
    mouseState.isSending = true;
    const payload = { dx: mouseState.dx, dy: mouseState.dy };
    mouseState.dx = 0;
    mouseState.dy = 0;
    sendMouseEvent('move', payload).finally(() => {
        mouseState.isSending = false;
        if (mouseState.dx !== 0 || mouseState.dy !== 0) requestAnimationFrame(processMouseQueue);
    });
}

// === SCREENSHOT LOOP (PERIODIC) ===
let screenState = { isFetching: false, loopId: null };
function startScreenshotLoop() {
    if (screenState.loopId) return;
    const loop = () => {
        if (!state.mouseMode) return;
        if (screenState.isFetching) return; // Drop frame if busy

        screenState.isFetching = true;
        fetch('/screenshot', { cache: 'no-store' })
            .then(r => {
                if (!r.ok) throw new Error('Status ' + r.status);
                return Promise.all([r.blob(), parseFloat(r.headers.get('X-Cursor-Pct-X')), parseFloat(r.headers.get('X-Cursor-Pct-Y'))]);
            })
            .then(([blob, pctX, pctY]) => {
                updateScreenshotDOM(blob, pctX, pctY);
            })
            .catch(console.error)
            .finally(() => {
                screenState.isFetching = false;
                // 500ms Refresh Rate = 2 FPS (Plenty for context, saves battery/network)
                if(state.mouseMode) screenState.loopId = setTimeout(loop, 500);
            });
    };
    loop();
}

function stopScreenshotLoop() {
    clearTimeout(screenState.loopId);
    screenState.loopId = null;
    screenState.isFetching = false;
}

function updateScreenshotDOM(blob, pctX, pctY) {
    const el = document.getElementById('screenshot');
    const url = URL.createObjectURL(blob);

    // Show Full Screen Image
    el.style.backgroundImage = `url(${url})`;

    // Update "Server Cursor" (Blue Dot) position on the image
    // Note: This is approximate because 'contain' sizing makes math hard in CSS alone
    // But strictly speaking, the user cares about the Red Dot (Finger)

    if(el.dataset.lastUrl) URL.revokeObjectURL(el.dataset.lastUrl);
    el.dataset.lastUrl = url;
}

let wakeLock = null;
let cursor = document.getElementById('local-cursor'); // Re-bind later

function updateKeyLabels() { const friendlyMapping = { "backspace": "⌫", "delete": "⌦", "space": "␣", "return": "↵", "escape": "⎋", "tab": "⇥", "shift": "⇧" }; const mainKeys = document.querySelectorAll('.main .key[data-key]:not([data-modifier])'); mainKeys.forEach(key => { const shiftActive = state.activeModifiers.has('shift'); const optionActive = state.activeModifiers.has('alt'); let displayText = key.dataset.key; if(shiftActive && key.dataset.shift){ displayText = key.dataset.shift; } else if(optionActive && key.dataset.option){ displayText = key.dataset.option; } else if(friendlyMapping[displayText]){ displayText = friendlyMapping[displayText]; } key.textContent = displayText; }); }
document.addEventListener('DOMContentLoaded', () => {
    cursor = document.getElementById('local-cursor');
    document.querySelectorAll('.keyboard').forEach(layer => { layer.addEventListener('touchstart', onTouchStart); layer.addEventListener('touchmove', onTouchMove); layer.addEventListener('touchend', onTouchEnd); layer.addEventListener('touchcancel', onTouchEnd); });
    updateKeyLabels();
    requestWakeLock();
});

function toggleLayers(){ state.currentLayer = state.currentLayer==='main'?'symbols':'main'; Object.entries(state.layers).forEach(([name, element])=>{ element.classList.toggle('active', name===state.currentLayer); }); updateKeyLabels(); }
function onTouchStart(e){ e.preventDefault(); Array.from(e.touches).forEach(touch=>{ const element = document.elementFromPoint(touch.clientX, touch.clientY); if(!element || !element.classList.contains('key')) return; if(element.dataset.mouse){ sendMouseEvent(element.dataset.mouse); element.classList.add('active'); setTimeout(()=>element.classList.remove('active'),200); return; } state.activeTouches.set(touch.identifier, { x: touch.clientX, y: touch.clientY, element, longPressTimer: setTimeout(()=>{ if(e.touches.length===3) sendMouseEvent('rightclick'); }, LONG_PRESS_DURATION) }); updateTouch(element, touch.identifier, true); }); }

function onTouchMove(e) {
    e.preventDefault();
    Array.from(e.touches).forEach(touch => {
        const touchData = state.activeTouches.get(touch.identifier);
        if (!touchData) return;
        if (!state.mouseMode && e.touches.length === 1) {
            const dx = touch.clientX - touchData.x;
            const dy = touch.clientY - touchData.y;
            if (Math.hypot(dx, dy) > TOUCH_THRESHOLD) enterMouseMode(touch);
        }
        if (state.mouseMode && e.touches.length === 1) {
            // Send raw deltas (no Zoom factor division needed for pure relative trackpad feel)
            const dx = (touch.clientX - touchData.x);
            const dy = (touch.clientY - touchData.y);

            touchData.x = touch.clientX;
            touchData.y = touch.clientY;

            queueMouseMovement(dx, dy);

            cursor.style.left = `${touch.clientX}px`;
            cursor.style.top = `${touch.clientY}px`;
        }
    });
}

function onTouchEnd(e){ e.preventDefault(); Array.from(e.changedTouches).forEach(touch=>{ const touchData = state.activeTouches.get(touch.identifier); if(!touchData)return; clearTimeout(touchData.longPressTimer); updateTouch(touchData.element, touch.identifier, false); state.activeTouches.delete(touch.identifier); if(state.mouseMode){ if(e.touches.length!==1) exitMouseMode(); if(e.changedTouches.length===1){ sendMouseEvent('leftclick'); } } }); }
function updateTouch(element, touchId, isActive){ if(element.dataset.modifier==='symbols' && isActive){ toggleLayers(); return; } if(element.dataset.mouse)return; if(element.dataset.modifier){ updateMod(element, isActive); } else { updateKey(element, touchId, isActive); } }
function updateMod(element, isActive){ let modifier = element.dataset.modifier; if(modifier==='symbols'){ if(isActive){ element.classList.toggle('active', state.currentLayer==='symbols'); } return; } if(isActive){ if(state.activeModifiers.has(modifier)){ state.activeModifiers.delete(modifier); } else { state.activeModifiers.add(modifier); } document.querySelectorAll(`[data-modifier="${element.dataset.modifier}"]`).forEach(btn=>{ btn.classList.toggle('active', state.activeModifiers.has(modifier)); }); updateKeyLabels(); } }
function updateKey(element, touchId, isActive){ element.classList.toggle('active', isActive); if(isActive){ state.pendingKeys.set(touchId, { element, key: element.dataset.key }); } else { const keyData = state.pendingKeys.get(touchId); if(keyData){ sendKey(keyData.key); state.pendingKeys.delete(touchId); } } }

function enterMouseMode(touch){
    state.mouseMode = true;
    state.pendingKeys.clear();
    document.body.classList.add('mouse-mode');

    cursor.style.display = 'block';
    cursor.style.left = `${touch.clientX}px`;
    cursor.style.top = `${touch.clientY}px`;

    document.querySelector('.keyboard').style.display = 'none';
    document.querySelector('.screenshot-container').style.display = 'flex'; // Show container

    startScreenshotLoop();
}

function exitMouseMode(){
    state.mouseMode = false;
    document.body.classList.remove('mouse-mode');
    cursor.style.display = 'none';

    stopScreenshotLoop();

    document.querySelector('.keyboard').style.display = 'flex';
    document.querySelector('.screenshot-container').style.display = 'none';
}

function sendKey(key){ const modifiers = Array.from(state.activeModifiers); fetch('/', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ type: 'key', key, modifiers }) }).catch(console.error); }
function sendMouseEvent(type, data = {}){ const payload = { type, ...data }; return fetch('/', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) }).catch(console.error); }
async function requestWakeLock(){ try{ if('wakeLock' in navigator && !wakeLock){ wakeLock = await navigator.wakeLock.request('screen'); wakeLock.addEventListener('release', ()=>wakeLock=null); } } catch(err){ console.error(err); } }
]]

local server = http.new(false, false)
server:setPort(PORT)
server:setCallback(function(method, path, headers, body)
    local responseHeaders = { ["Content-Type"] = "text/plain", ["Access-Control-Allow-Origin"] = "*" }

    if method == "OPTIONS" then
        return "", 200,
            { ["Access-Control-Allow-Headers"] = "Content-Type", ["Access-Control-Allow-Methods"] = "POST, GET, OPTIONS" }
    end

    if method == "GET" then
        if path == "/" then
            return html, 200, { ["Content-Type"] = "text/html" }
        elseif path == "/app.css" then
            return css, 200, { ["Content-Type"] = "text/css" }
        elseif path == "/app.js" then
            return js, 200, { ["Content-Type"] = "application/javascript" }
        elseif path == "/manifest.json" then
            return "{}", 200, { ["Content-Type"] = "application/json" }
        elseif path == "/sw.js" then
            return "", 200, { ["Content-Type"] = "application/javascript" }
        elseif path == "/screenshot" then
            local snap, pctX, pctY = captureFullScreenPreview()

            if not snap then
                return "Screen Error", 500, { ["Content-Type"] = "text/plain" }
            end

            local scHeaders = {
                ["Content-Type"] = "image/jpeg",
                ["Cache-Control"] = "no-store",
                ["X-Cursor-Pct-X"] = tostring(pctX),
                ["X-Cursor-Pct-Y"] = tostring(pctY)
            }

            local tmp = os.tmpname() .. ".jpg"
            -- Save as JPEG (inferred from extension)
            local ok = snap:saveToFile(tmp)

            if not ok then return "Error saving file", 500, scHeaders end
            local f = io.open(tmp, "rb")
            if not f then return "Error reading file", 500, scHeaders end
            local data = f:read("*a")
            f:close()
            os.remove(tmp)
            return data, 200, scHeaders
        else
            return "Not Found", 404, { ["Content-Type"] = "text/plain" }
        end
    elseif method == "POST" and path == "/" then
        local ok, data = pcall(json.decode, body)
        if ok then
            if data.type == 'key' then
                if not data.key then return "Bad Request: Missing key", 400, { ["Content-Type"] = "text/plain" } end
                local modifiers = {}
                for _, mod in ipairs(data.modifiers or {}) do
                    local normalized = mod:lower()
                    if modifierMap[normalized] then table.insert(modifiers, modifierMap[normalized]) end
                end
                local key = data.key:lower()
                local keyName = key
                if keyCodes[keyName] then
                    eventtap.keyStroke(modifiers, keyName, 0)
                    return "OK", 200, responseHeaders
                end
            elseif data.type == 'move' then
                moveMouseRelative(data.dx, data.dy)
                return "OK", 200, responseHeaders
            elseif data.type == 'leftclick' then
                eventtap.leftClick(mouse.absolutePosition())
                return "OK", 200, responseHeaders
            elseif data.type == 'rightclick' then
                eventtap.rightClick(mouse.absolutePosition())
                return "OK", 200, responseHeaders
            elseif data.type == 'doubleclick' then
                local pos = mouse.absolutePosition()
                eventtap.leftClick(pos)
                eventtap.leftClick(pos)
                return "OK", 200, responseHeaders
            elseif data.type == 'scroll' then
                local amounts = { x = 0, y = 0 }
                if data.direction == 'up' then amounts.y = -SCROLL_AMOUNT elseif data.direction == 'down' then amounts.y =
                    SCROLL_AMOUNT elseif data.direction == 'left' then amounts.x = -SCROLL_AMOUNT elseif data.direction == 'right' then amounts.x =
                    SCROLL_AMOUNT end
                eventtap.scrollWheel(amounts, {}, 'pixel')
                return "OK", 200, responseHeaders
            end
            return "Bad Request", 400, { ["Content-Type"] = "text/plain" }
        else
            return "Bad Request", 400, { ["Content-Type"] = "text/plain" }
        end
    else
        return "Not Found", 404, { ["Content-Type"] = "text/plain" }
    end
end)
server:start()
local function getHostname()
    local f = io.popen("/bin/hostname")
    local hostname = f:read("*a") or ""
    f:close()
    hostname = string.gsub(hostname, "\n$", "")
    return hostname
end
local hostname = getHostname()
if hostname and #hostname > 0 then
    local url = "http://" .. hostname .. ":" .. PORT
    hotkey.bind({ "cmd", "ctrl" }, "C",
        function()
            pasteboard.setContents(url)
            alert.show("URL copied to clipboard!\n" .. url, 2)
        end)
    print("CloudPad running at " .. url .. ". Press ⌘⌃C to copy.")
else
    print("Could not determine hostname - No URL for you.")
end
return server
