-- CloudPad: Web keyboard for Hammerspoon

local http = require("hs.httpserver")
local eventtap = require("hs.eventtap")
local keycodes = require("hs.keycodes")
local json = require("hs.json")
local network = require("hs.network")
local pasteboard = require("hs.pasteboard")
local hotkey = require("hs.hotkey")
local alert = require("hs.alert")
local mouse = require("hs.mouse")

local MOUSE_SENSITIVITY = 1.5
local SCROLL_AMOUNT = 15
local PORT = 1984

local function accelerationCurve(velocity)
    if velocity < 1 then
        return velocity * 0.1 -- Precise
    elseif velocity < 5 then
        return velocity * 1.2 -- Moderate
    else
        return velocity ^ 2   -- Fast
    end
end

local function moveMouseRelative(dx, dy)
    local current = mouse.absolutePosition()
    local velocity = math.sqrt(dx ^ 2 + dy ^ 2)
    local scaledVelocity = accelerationCurve(velocity)
    local factor = scaledVelocity / (velocity + 0.01) -- Avoid divide by zero
    dx = dx * factor
    dy = dy * factor

    mouse.absolutePosition({
        x = current.x + (dx * MOUSE_SENSITIVITY),
        y = current.y + (dy * MOUSE_SENSITIVITY)
    })
end

local keyCodes = setmetatable({}, {
    __index = function(_, key)
        return keycodes.map[key]
    end
})

local modifierMap = {
    shift = "shift",
    ctrl = "ctrl",
    cmd = "cmd",
    alt = "alt"
}

local html = [[
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, viewport-fit=cover, initial-scale=1.0">
    <title>CloudPad</title>
    <link rel="manifest" href="/manifest.json">
    <link rel="stylesheet" href="/app.css">
    <script>
        if ('serviceWorker' in navigator) {
            navigator.serviceWorker.register('/sw.js', { scope: '/' });
        }
    </script>
</head>
<body>
    <div class="keyboard main active">
        <div class="row">
            <button data-key="1" data-shift="!" data-option="|" class="key">1</button>
            <button data-key="2" data-shift="/"" data-option="@" class="key">2</button>
            <button data-key="3" data-shift="·" data-option="#" class="key">3</button>
            <button data-key="4" data-shift="$" data-option="¢" class="key">4</button>
            <button data-key="5" data-shift="%" data-option="∞" class="key">5</button>
            <button data-key="6" data-shift="&" data-option="¬" class="key">6</button>
            <button data-key="7" data-shift="/" data-option="÷" class="key">7</button>
            <button data-key="8" data-shift="(" data-option="“" class="key">8</button>
            <button data-key="9" data-shift=")" data-option="”" class="key">9</button>
            <button data-key="0" data-shift="=" data-option="≠" class="key">0</button>
        </div>
        <div class="row">
            <button data-key="q" data-shift="Q" data-option="œ" class="key">q</button>
            <button data-key="w" data-shift="W" data-option="æ" class="key">w</button>
            <button data-key="e" data-shift="E" data-option="€" class="key">e</button>
            <button data-key="r" data-shift="R" data-option="®" class="key">r</button>
            <button data-key="t" data-shift="T" data-option="†" class="key">t</button>
            <button data-key="y" data-shift="Y" data-option="¥" class="key">y</button>
            <button data-key="u" data-shift="U" data-option=" " class="key">u</button>
            <button data-key="i" data-shift="I" data-option=" " class="key">i</button>
            <button data-key="o" data-shift="O" data-option="ø" class="key">o</button>
            <button data-key="p" data-shift="P" data-option="π" class="key">p</button>
        </div>
        <div class="row">
            <button data-key="a" data-shift="A" data-option="å" class="key">a</button>
            <button data-key="s" data-shift="S" data-option="∫" class="key">s</button>
            <button data-key="d" data-shift="D" data-option="∂" class="key">d</button>
            <button data-key="f" data-shift="F" data-option="ƒ" class="key">f</button>
            <button data-key="g" data-shift="G" data-option="" class="key">g</button>
            <button data-key="h" data-shift="H" data-option="™" class="key">h</button>
            <button data-key="j" data-shift="J" data-option="¶" class="key">j</button>
            <button data-key="k" data-shift="K" data-option="§" class="key">k</button>
            <button data-key="l" data-shift="L" data-option=" " class="key">l</button>
            <button data-key="ñ" data-shift="Ñ" data-option="~" class="key">ñ</button>
        </div>
        <div class="row">
            <button data-modifier="shift" class="key mod">⇧</button>
            <button data-key="z" data-shift="Z" data-option="Ω" class="key">z</button>
            <button data-key="x" data-shift="X" data-option="∑" class="key">x</button>
            <button data-key="c" data-shift="C" data-option="©" class="key">c</button>
            <button data-key="v" data-shift="V" data-option="√" class="key">v</button>
            <button data-key="b" data-shift="B" data-option="ß" class="key">b</button>
            <button data-key="n" data-shift="N" data-option=" " class="key">n</button>
            <button data-key="m" data-shift="M" data-option="µ" class="key">m</button>
            <button data-key="." data-shift=":" data-option="…" class="key">.</button>
            <button data-key="backspace" class="key">⌫</button>
        </div>
        <div class="row">
            <button data-key="escape" class="key">⎋</button>
            <button data-modifier="ctrl" class="key mod">⌃</button>
            <button data-modifier="symbols" class="key mod">#</button>
            <button data-modifier="alt" class="key mod">⌥</button>
            <button data-modifier="cmd" class="key mod">⌘</button>
            <button data-key="space" class="key space">␣</button>
            <button data-modifier="fn" class="key">fn</button>
            <button data-key="return" class="key">↵</button>
        </div>
    </div>
    <div class="keyboard symbols">
        <div class="row">
            <button data-key="" class="key"></button>
            <button data-key="" class="key"></button>
            <button data-key="" class="key"></button>
            <button data-key="" class="key"></button>
            <button data-key="" class="key"></button>
            <button data-key="" class="key"></button>
            <button data-key="" class="key"></button>
            <button data-key="" class="key"></button>
            <button data-key="" class="key"></button>
            <button data-key="" class="key"></button>
        </div>
        <div class="row">
            <button data-key="" class="key"></button>
            <button data-key="" class="key"></button>
            <button data-key="" class="key"></button>
            <button data-key="" class="key"></button>
            <button data-key="" class="key"></button>
            <button data-key="" class="key"></button>
            <button data-key="" class="key"></button>
            <button data-key="" class="key"></button>
            <button data-key="" class="key"></button>
            <button data-key="" class="key"></button>
        </div>
        <div class="row">
            <button data-key="" class="key"></button>
            <button data-key="" class="key"></button>
            <button data-key="" class="key"></button>
            <button data-key="" class="key"></button>
            <button data-key="" class="key"></button>
            <button data-key="" class="key"></button>
            <button data-key="" class="key"></button>
            <button data-key="" class="key"></button>
            <button data-key="" class="key"></button>
            <button data-key="" class="key"></button>
        </div>
        <div class="row">
            <button data-key="left" class="key">←</button>
            <button data-key="right" class="key">→</button>
            <button data-key="up" class="key">↑</button>
            <button data-key="down" class="key">↓</button>
            <button data-mouse="scrollup" class="key">🠉</button>
            <button data-mouse="scrolldown" class="key">🠋</button>
            <button data-mouse="doubleclick" class="key">️L</button>
            <button data-mouse="middleclick" class="key">M</button>
            <button data-mouse="rightclick" class="key"> R</button>
            <button data-key="delete" class="key">⌦</button>
        </div>
        <div class="row">
            <button data-key="tab" class="key">⇥</button>
            <button data-modifier="ctrl" class="key mod">⌃</button>
            <button data-modifier="symbols" class="key mod">#</button>
            <button data-modifier="alt" class="key mod">⌥</button>
            <button data-modifier="cmd" class="key mod">⌘</button>
            <button data-key="space" class="key space"></button>
            <button data-key="fn" class="key">fn</button>
            <button data-key="return" class="key">⏎</button>
        </div>
    </div>

    <script src="/app.js"></script>
</body>
</html>
]]

local css = [[
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
    touch-action: none;
}

html {
    user-select: none;
}

body {
    background: #111;
    height: 100vh;
    display: flex;
    justify-content: center;
    align-items: center;
    margin: 4px;
    overscroll-behavior: none;
    overflow: hidden;
}

.keyboard {
    display: none;
    position: absolute;
    width: 100%;
    height: 100%;
    flex-direction: column;
    transition: opacity 0.2s;
    padding: env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left);
}

.keyboard.active {
    display: flex;
}

.mouse-mode .keyboard {
    opacity: 0.1;
    pointer-events: none;
}

.row {
    display: flex;
    justify-content: center;
    flex-grow: 1;
}

.key {
    background: #000;
    color: white;
    border: none;
    border-radius: 10px;
    margin: 2px;
    padding: 0px;
    font-size: clamp(12px, 6vw, 48px);
    text-box-trim: trim-both;
    cursor: pointer;
    flex: 1;
    transition: all 0.1s;
}

.key:not(.mod).active {
    background: #666;
    scale: 2;
    translate: 0 -20vh;
    transition: all 0s;
}

.mod.active {
    background: #007AFF;
}

.space {
    flex: 3;
}

.mod {
    flex: 1;
    background: #222;
}

#cursor {
    position: fixed;
    width: 42px;
    height: 42px;
    background: rgba(255,255,255,0.7);
    border-radius: 50%;
    pointer-events: none;
    transform: translate(-50%, -50%);
    display: none;
}
]]

local js = [[
const state = {
    activeTouches: new Map(),
    activeModifiers: new Set(),
    mouseMode: false,
    lastClickTime: 0,
    pendingKeys: new Map(),
    scrollSpeed: 3,
    currentLayer: 'main',
    layers: {
        main: document.querySelector('.main'),
        symbols: document.querySelector('.symbols')
    }
};

const TOUCH_THRESHOLD = 5;
const LONG_PRESS_DURATION = 500;
const BASE_SCROLL_AMOUNT = 15;
let wakeLock = null;
let cursor = null;

function updateKeyLabels() {
    const friendlyMapping = {
        "backspace": "⌫",
        "delete": "⌦",
        "space": "␣",
        "return": "↵",
        "escape": "⎋",
        "tab": "⇥",
        "shift": "⇧"
        // Add more mappings as needed.
    };

    const mainKeys = document.querySelectorAll('.main .key[data-key]:not([data-modifier])');
    mainKeys.forEach(key => {
        const shiftActive = state.activeModifiers.has('shift');
        const optionActive = state.activeModifiers.has('alt');
        let displayText = key.dataset.key; // default

        if (shiftActive && key.dataset.shift) {
            displayText = key.dataset.shift;
        } else if (optionActive && key.dataset.option) {
            displayText = key.dataset.option;
        } else if (friendlyMapping[displayText]) {
            displayText = friendlyMapping[displayText];
        }

        key.textContent = displayText;
    });
}

document.addEventListener('DOMContentLoaded', () => {
    const keyboard = document.querySelector('.keyboard');
    cursor = document.createElement('div');
    cursor.id = 'cursor';
    document.body.appendChild(cursor);

    document.querySelectorAll('.keyboard').forEach(layer => {
        layer.addEventListener('touchstart', onTouchStart);
        layer.addEventListener('touchmove', onTouchMove);
        layer.addEventListener('touchend', onTouchEnd);
        layer.addEventListener('touchcancel', onTouchEnd);
    });

    updateKeyLabels();
    requestWakeLock();
    document.addEventListener('visibilitychange', () => {
        if (document.visibilityState === 'visible') requestWakeLock();
    });
});

async function requestWakeLock() {
    try {
        if ('wakeLock' in navigator && !wakeLock) {
            wakeLock = await navigator.wakeLock.request('screen');
            wakeLock.addEventListener('release', () => wakeLock = null);
        }
    } catch (err) {
        console.error('Wake Lock Error:', err);
    }
}

function toggleLayers() {
    state.currentLayer = state.currentLayer === 'main' ? 'symbols' : 'main';
    Object.entries(state.layers).forEach(([name, element]) => {
        element.classList.toggle('active', name === state.currentLayer);
    });
    updateKeyLabels();
}

function onTouchStart(e) {
    e.preventDefault();
    Array.from(e.touches).forEach(touch => {
        const element = document.elementFromPoint(touch.clientX, touch.clientY);
        if (!element?.classList.contains('key')) return;

        if (element.dataset.mouse) {
            sendMouseEvent(element.dataset.mouse);
            element.classList.add('active');
            setTimeout(() => element.classList.remove('active'), 200);
            return;
        }

        state.activeTouches.set(touch.identifier, {
            x: touch.clientX,
            y: touch.clientY,
            element,
            longPressTimer: setTimeout(() => {
                if (e.touches.length === 3) sendMouseEvent('rightclick');
            }, LONG_PRESS_DURATION)
        });

        updateTouch(element, touch.identifier, true);
    });
}

function onTouchMove(e) {
    e.preventDefault();
    Array.from(e.touches).forEach(touch => {
        const touchData = state.activeTouches.get(touch.identifier);
        if (!touchData) return;

        if (state.mouseMode) {
            cursor.style.left = `${touch.clientX}px`;
            cursor.style.top = `${touch.clientY}px`;
        }

        if (!state.mouseMode && e.touches.length === 1) {
            const dx = touch.clientX - touchData.x;
            const dy = touch.clientY - touchData.y;

            if (Math.hypot(dx, dy) > TOUCH_THRESHOLD) {
                enterMouseMode(touch);
            }
        }

        if (state.mouseMode && e.touches.length === 1) {
            const dx = (touch.clientX - touchData.x) * 1.5;
            const dy = (touch.clientY - touchData.y) * 1.5;
            touchData.x = touch.clientX;
            touchData.y = touch.clientY;
            sendMouseEvent('move', { dx, dy });
        }

        const newElement = document.elementFromPoint(touch.clientX, touch.clientY);
        if (newElement !== touchData.element) {
            updateTouch(touchData.element, touch.identifier, false);
            touchData.element = newElement;
            updateTouch(newElement, touch.identifier, true);
        }
    });
}

function onTouchEnd(e) {
    e.preventDefault();
    Array.from(e.changedTouches).forEach(touch => {
        const touchData = state.activeTouches.get(touch.identifier);
        if (!touchData) return;

        clearTimeout(touchData.longPressTimer);
        updateTouch(touchData.element, touch.identifier, false);
        state.activeTouches.delete(touch.identifier);

        if (state.mouseMode) {
            if (e.touches.length !== 1) exitMouseMode();
            if (e.changedTouches.length === 1) {
                sendMouseEvent('leftclick');
            }
        }
    });
}

function updateTouch(element, touchId, isActive) {
    if (element.dataset.modifier === 'symbols' && isActive) {
        toggleLayers();
        return;
    }

    if (element.dataset.mouse) return;

    if (element.dataset.modifier) {
        updateMod(element, isActive);
    } else {
        updateKey(element, touchId, isActive);
    }
}

function updateMod(element, isActive) {
    let modifier = element.dataset.modifier;

    if (modifier === 'symbols') {
        if (isActive) {
            element.classList.toggle('active', state.currentLayer === 'symbols');
        }
        return;
    }

    if (isActive) {
        if (state.activeModifiers.has(modifier)) {
            state.activeModifiers.delete(modifier);
        } else {
            state.activeModifiers.add(modifier);
        }

        document.querySelectorAll(`[data-modifier="${element.dataset.modifier}"]`).forEach(btn => {
            btn.classList.toggle('active', state.activeModifiers.has(modifier));
        });

        updateKeyLabels();
    }
}

function updateKey(element, touchId, isActive) {
    element.classList.toggle('active', isActive);

    if (isActive) {
        state.pendingKeys.set(touchId, {
            element,
            key: element.dataset.key
        });
    } else {
        const keyData = state.pendingKeys.get(touchId);
        if (keyData) {
            sendKey(keyData.key);
            state.pendingKeys.delete(touchId);
        }
    }
}

function enterMouseMode(touch) {
    state.mouseMode = true;
    document.body.classList.add('mouse-mode');
    cursor.style.display = 'block';
    cursor.style.left = `${touch.clientX}px`;
    cursor.style.top = `${touch.clientY}px`;

    state.pendingKeys.forEach((data, id) => {
        data.element.classList.remove('active');
        state.pendingKeys.delete(id);
    });
}

function exitMouseMode() {
    state.mouseMode = false;
    document.body.classList.remove('mouse-mode');
    cursor.style.display = 'none';
}

function sendKey(key) {
    const modifiers = Array.from(state.activeModifiers);
    fetch('/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            type: 'key',
            key,
            modifiers
        })
    }).catch(console.error);
}

function sendMouseEvent(type, data = {}) {
    const payload = { type, ...data };
    if (type === 'scroll') {
        payload.amount = Math.round(BASE_SCROLL_AMOUNT * state.scrollSpeed);
    }

    fetch('/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
    }).catch(console.error);
}

if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
        navigator.serviceWorker.register('/sw.js');
    });
}

document.addEventListener('contextmenu', e => e.preventDefault());
]]

local server = http.new(false, false)
server:setPort(PORT)
server:setCallback(function(method, path, headers, body)
    local responseHeaders = {
        ["Content-Type"] = "text/plain",
        ["Access-Control-Allow-Origin"] = "*"
    }

    if method == "OPTIONS" then
        return "", 200, {
            ["Access-Control-Allow-Headers"] = "Content-Type",
            ["Access-Control-Allow-Methods"] = "POST, GET, OPTIONS"
        }
    end

    if method == "GET" then
        if path == "/" then return html, 200, { ["Content-Type"] = "text/html" } end
        if path == "/app.css" then return css, 200, { ["Content-Type"] = "text/css" } end
        if path == "/app.js" then return js, 200, { ["Content-Type"] = "application/javascript" } end
        if path == "/manifest.json" then return manifest, 200, { ["Content-Type"] = "application/json" } end
        if path == "/sw.js" then return sw, 200, { ["Content-Type"] = "application/javascript" } end
        return "Not Found", 404
    elseif method == "POST" and path == "/" then
        local ok, data = pcall(json.decode, body)
        if ok then
            if data.type == 'key' then
                if not data.key then
                    return "Bad Request: Missing key", 400
                end
                local modifiers = {}
                for _, mod in ipairs(data.modifiers or {}) do
                    local normalized = mod:lower()
                    if modifierMap[normalized] then table.insert(modifiers, modifierMap[normalized]) end
                end

                local key = data.key:lower()
                local specialKeys = {
                    enter = "return",
                    backspace = "delete",
                    space = "space",
                    capslock = "capslock"
                }

                local keyName = specialKeys[key] or key
                if keyCodes[keyName] then
                    eventtap.keyStroke(modifiers, keyName, 100000)
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
                if data.direction == 'up' then
                    amounts.y = -SCROLL_AMOUNT
                elseif data.direction == 'down' then
                    amounts.y = SCROLL_AMOUNT
                elseif data.direction == 'left' then
                    amounts.x = -SCROLL_AMOUNT
                elseif data.direction == 'right' then
                    amounts.x = SCROLL_AMOUNT
                end
                eventtap.scrollWheel(amounts, {}, 'pixel')
                return "OK", 200, responseHeaders
            end
        end
        return "Bad Request", 400
    end
    return "Not Found", 404
end)

server:start()

function getHostname()
    local f = io.popen("/bin/hostname")
    local hostname = f:read("*a") or ""
    f:close()
    hostname = string.gsub(hostname, "\n$", "")
    return hostname
end

local hostname = getHostname()
if hostname then
    local url = "http://" .. hostname .. ":" .. PORT
    hotkey.bind({ "cmd", "ctrl" }, "C", function()
        pasteboard.setContents(url)
        alert.show("URL copied to clipboard!\n" .. url, 2)
    end)
    print("CloudPad running at " .. url .. ". Hit ⌘⌃C and paste it on your device.")
else
    print("Could not determine hostname - No URL for you.")
end

return server
