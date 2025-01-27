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
        return velocity * 0.5 -- Precise movement
    elseif velocity < 5 then
        return velocity * 1.2 -- Moderate
    else
        return velocity ^ 1.5 -- Fast
    end
end

local function moveMouseRelative(dx, dy)
    local current = mouse.getAbsolutePosition()
    local velocity = math.sqrt(dx ^ 2 + dy ^ 2)
    local scaledVelocity = accelerationCurve(velocity)
    local factor = scaledVelocity / (velocity + 0.01) -- Avoid divide by zero
    dx = dx * factor
    dy = dy * factor

    mouse.setAbsolutePosition({
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

local function getLocalIP()
    local addresses = network.addresses() or {}
    for _, addr in ipairs(addresses) do
        if addr:match("^%d+%.%d+%.%d+%.%d+$") and not addr:match("^127%.") then
            return addr
        end
    end
    return nil
end

local html = [[
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CloudPad</title>
    <link rel="manifest" href="/manifest.json">
    <link rel="stylesheet" href="/app.css">
</head>
<body>
    <div class="keyboard">
        <!-- Keyboard layout remains unchanged from previous version -->
        <div class="row">
            <button data-key="`" class="key">`</button>
            <button data-key="1" class="key">1</button>
            <button data-key="2" class="key">2</button>
            <button data-key="3" class="key">3</button>
            <button data-key="4" class="key">4</button>
            <button data-key="5" class="key">5</button>
            <button data-key="6" class="key">6</button>
            <button data-key="7" class="key">7</button>
            <button data-key="8" class="key">8</button>
            <button data-key="9" class="key">9</button>
            <button data-key="0" class="key">0</button>
            <button data-key="delete" class="key">⌫</button>
        </div>

        <div class="row">
            <button data-key="tab" class="key">Tab</button>
            <button data-key="q" class="key">q</button>
            <button data-key="w" class="key">w</button>
            <button data-key="e" class="key">e</button>
            <button data-key="r" class="key">r</button>
            <button data-key="t" class="key">t</button>
            <button data-key="y" class="key">y</button>
            <button data-key="u" class="key">u</button>
            <button data-key="i" class="key">i</button>
            <button data-key="o" class="key">o</button>
            <button data-key="p" class="key">p</button>
            <button data-key="[" class="key">[</button>
            <button data-key="]" class="key">]</button>
        </div>

        <div class="row">
            <button data-key="capslock" class="key">Caps</button>
            <button data-key="a" class="key">a</button>
            <button data-key="s" class="key">s</button>
            <button data-key="d" class="key">d</button>
            <button data-key="f" class="key">f</button>
            <button data-key="g" class="key">g</button>
            <button data-key="h" class="key">h</button>
            <button data-key="j" class="key">j</button>
            <button data-key="k" class="key">k</button>
            <button data-key="l" class="key">l</button>
            <button data-key=";" class="key">;</button>
            <button data-key="'" class="key">'</button>
            <button data-key="return" class="key">⏎</button>
        </div>

        <div class="row">
            <button data-modifier="shift" class="key mod">⇧</button>
            <button data-key="z" class="key">z</button>
            <button data-key="x" class="key">x</button>
            <button data-key="c" class="key">c</button>
            <button data-key="v" class="key">v</button>
            <button data-key="b" class="key">b</button>
            <button data-key="n" class="key">n</button>
            <button data-key="m" class="key">m</button>
            <button data-key="," class="key">,</button>
            <button data-key="." class="key">.</button>
            <button data-key="/" class="key">/</button>
            <button data-modifier="shift" class="key mod">⇧</button>
        </div>

        <div class="row">
            <button data-modifier="ctrl" class="key mod">ctrl</button>
            <button data-modifier="cmd" class="key mod">⌘</button>
            <button data-modifier="alt" class="key mod">⌥</button>
            <button data-key="space" class="key space">␣</button>
            <button data-modifier="alt" class="key mod">⌥</button>
            <button data-modifier="cmd" class="key mod">⌘</button>
            <button data-modifier="ctrl" class="key mod">ctrl</button>
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
    touch-action: manipulation;
}

html {
    overscroll-behavior: none;
    user-select: none;
}

body {
    background: #333;
    height: 100vh;
    display: flex;
    justify-content: center;
    align-items: center;
}

.keyboard {
    width: 100%;
    height: 100%;
    display: flex;
    flex-direction: column;
    transition: opacity 0.2s;
}

.mouse-mode .keyboard {
    opacity: 0.7;
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
    padding: 12px;
    font-size: 16px;
    cursor: pointer;
    flex: 1;
}

.key:active {
    background: #666;
}

.key.active {
    background: #007AFF;
}

.space {
    flex: 8;
}

.mod {
    flex: 2;
    background: #444;
}

#cursor {
    position: fixed;
    width: 10px;
    height: 10px;
    background: rgba(255,255,255,0.7);
    border-radius: 50%;
    pointer-events: none;
    transform: translate(-50%, -50%);
    display: none;
}
]]

local js = [[
const state = {
    modifiers: new Set(),
    mouseMode: false,
    activeTouches: new Map(),
    lastClickTime: 0
};

const TOUCH_THRESHOLD = 5;
const LONG_PRESS_DURATION = 500;

let wakeLock = null;

async function requestWakeLock() {
    try {
        if ('wakeLock' in navigator) {
            wakeLock = await navigator.wakeLock.request('screen');
            console.log('Wake Lock acquired');

            wakeLock.addEventListener('release', () => {
                console.log('Wake Lock released');
            });
        }
    } catch (err) {
        console.error('Error acquiring Wake Lock:', err);
    }
}

// Request Wake Lock on initial load
document.addEventListener('DOMContentLoaded', requestWakeLock);

// Re-acquire Wake Lock when page becomes visible
document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible' && wakeLock === null) {
        requestWakeLock();
    }
});

// Request Wake Lock on any touch interaction
document.addEventListener('touchstart', () => {
    if (wakeLock === null) {
        requestWakeLock();
    }
}, { once: true });

function toggleModifier(modifier) {
    state.modifiers.has(modifier) ?
        state.modifiers.delete(modifier) :
        state.modifiers.add(modifier);
    updateModifierUI(modifier);
}

function updateModifierUI(modifier) {
    document.querySelectorAll(`[data-modifier="${modifier}"]`).forEach(btn => {
        btn.classList.toggle('active', state.modifiers.has(modifier));
    });
}

function sendKey(key) {
    const modifiers = Array.from(state.modifiers);
    fetch('/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ type: 'key', key, modifiers })
    }).catch(console.error);
}

function sendMouseEvent(type, data = {}) {
    fetch('/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ type, ...data })
    }).catch(console.error);
}

document.querySelectorAll('.key').forEach(btn => {
    btn.addEventListener('touchstart', e => {
        e.preventDefault();
        const modifier = btn.dataset.modifier;

        Array.from(e.touches).forEach(touch => {
            state.activeTouches.set(touch.identifier, {
                x: touch.clientX,
                y: touch.clientY,
                startTime: Date.now(),
                longPressTimer: modifier ? null : setTimeout(() => {
                    if (e.touches.length === 2) sendMouseEvent('rightclick');
                }, LONG_PRESS_DURATION)
            });
        });

        modifier ? toggleModifier(modifier) : (e.touches.length === 1 && (state.mouseMode = false));
    });

    btn.addEventListener('touchmove', e => {
        if (!state.activeTouches.size) return;

        if (e.touches.length === 1) {
            const touch = e.touches[0];
            const initial = state.activeTouches.get(touch.identifier);
            const dx = touch.clientX - initial.x;
            const dy = touch.clientY - initial.y;

            if (!state.mouseMode && (Math.abs(dx) > TOUCH_THRESHOLD || Math.abs(dy) > TOUCH_THRESHOLD)) {
                state.mouseMode = true;
                document.body.classList.add('mouse-mode');
            }

            if (state.mouseMode) {
                sendMouseEvent('move', { dx, dy });
                initial.x = touch.clientX;
                initial.y = touch.clientY;
            }
        }
    });

    btn.addEventListener('touchend', e => {
        e.preventDefault();
        const key = btn.dataset.key;
        const modifier = btn.dataset.modifier;

        Array.from(e.changedTouches).forEach(touch => {
            const t = state.activeTouches.get(touch.identifier);
            t && (clearTimeout(t.longPressTimer), state.activeTouches.delete(touch.identifier));
        });

        // Hide cursor when touch ends
        cursor.style.display = 'none';

        if (!state.mouseMode && !modifier) sendKey(key);

        if (!state.mouseMode) {
            const now = Date.now();
            const touchCount = state.activeTouches.size + e.changedTouches.length;

            if (touchCount === 2) {
                const eventType = (now - state.lastClickTime < 300) ? 'doubleclick' : 'leftclick';
                sendMouseEvent(eventType);
                state.lastClickTime = now;
            }
        }

        // Add the following code to trigger left click on mouse mode release
        if (state.mouseMode && e.changedTouches.length === 1) {
            const now = Date.now();
            sendMouseEvent('leftclick');
            state.lastClickTime = now;
        }

        state.activeTouches.size || (state.mouseMode = false, document.body.classList.remove('mouse-mode'));
    });
});

const cursor = document.createElement('div');
cursor.id = 'cursor';
document.body.appendChild(cursor);

document.addEventListener('touchmove', e => {
    if (state.mouseMode && e.touches.length === 1) {
        const touch = e.touches[0];
        cursor.style.display = 'block';
        cursor.style.left = `${touch.clientX}px`;
        cursor.style.top = `${touch.clientY}px`;
    } else {
        cursor.style.display = 'none';
    }
}, { passive: true });

document.addEventListener('contextmenu', e => e.preventDefault());

if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
        navigator.serviceWorker.register('/sw.js')
            .then(reg => console.log('Service Worker registered'))
            .catch(console.error);
    });
}
]]

local manifest = [[
{
    "name": "CloudPad",
    "short_name": "CloudPad",
    "start_url": "/",
    "display": "standalone",
    "background_color": "#333333",
    "theme_color": "#333333",
    "icons": [
        {
            "src": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAMAAAADACAMAAABlApw1AAAAA1BMVEUAAACnej3aAAAALElEQVR4nO3BMQEAAADCIPuntsUuYAAAAAAAAAAAAAAAAAAAAAAAAAAAAJA5dw8AAa0h7lUAAAAASUVORK5CYII=",
            "sizes": "192x192",
            "type": "image/png"
        },
        {
            "src": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAZAAAAGQAQMAAAC6caSPAAAAA1BMVEUAAACnej3aAAAANUlEQVR4nO3BAQ0AAADCoPdPbQ43oAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJAGDvQAAAFGtB5jAAAAAElFTkSuQmCC",
            "sizes": "512x512",
            "type": "image/png"
        }
    ]
}
]]

local sw = [[
self.addEventListener('install', e => {
    e.waitUntil(caches.open('cloudpad-v1')
        .then(cache => cache.addAll(['/', '/app.css', '/app.js', '/manifest.json'])));
});

self.addEventListener('fetch', e => {
    e.respondWith(caches.match(e.request).then(response => response || fetch(e.request)));
});
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
print("CloudPad server running at http://localhost:" .. PORT)

local ipAddress = getLocalIP()
if ipAddress then
    local url = "http://" .. ipAddress .. ":" .. PORT
    hotkey.bind({ "cmd", "ctrl" }, "C", function()
        pasteboard.setContents(url)
        alert.show("URL copied to clipboard!\n" .. url, 2)
    end)
    print("Use ⌘⌃C to copy server URL: " .. url)
else
    print("Could not determine IP address - URL copying disabled")
end

return server
