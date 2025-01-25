-- CloudPad: A web keyboard for Hammerspoon.

local http = require("hs.httpserver")
local eventtap = require("hs.eventtap")
local keycodes = require("hs.keycodes")
local json = require("hs.json")
local network = require("hs.network")
local pasteboard = require("hs.pasteboard")
local hotkey = require("hs.hotkey")
local alert = require("hs.alert")

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

body {
    background: #333;
    height: 100vh;
    display: flex;
    justify-content: center;
    align-items: center;
}

.keyboard {
    width: 100%;
    max-width: 800px;
    padding: 10px;
}

.row {
    display: flex;
    justify-content: center;
    margin: 4px 0;
}

.key {
    background: #666;
    color: white;
    border: none;
    border-radius: 4px;
    margin: 2px;
    padding: 12px;
    min-width: 40px;
    font-size: 16px;
    cursor: pointer;
    flex: 1;
}

.key:active {
    background: #999;
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
]]

local js = [[
const state = {
    modifiers: new Set()
};

function toggleModifier(modifier) {
    if (state.modifiers.has(modifier)) {
        state.modifiers.delete(modifier);
    } else {
        state.modifiers.add(modifier);
    }
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
        body: JSON.stringify({ key, modifiers })
    }).catch(err => console.error('Error:', err));
}

document.querySelectorAll('.key').forEach(btn => {
    btn.addEventListener('touchstart', (e) => {
        e.preventDefault();
        const key = btn.dataset.key;
        const modifier = btn.dataset.modifier;

        if (modifier) {
            toggleModifier(modifier);
        }
    });

    btn.addEventListener('touchend', (e) => {
        e.preventDefault();
        const key = btn.dataset.key;
        const modifier = btn.dataset.modifier;

        if (!modifier) {
            sendKey(key);
        }
    });
});

if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
        navigator.serviceWorker.register('/sw.js')
            .then(reg => console.log('Service Worker registered'))
            .catch(err => console.log('Service Worker failed:', err));
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

-- Service Worker Content
local sw = [[
self.addEventListener('install', (e) => {
    e.waitUntil(
        caches.open('cloudpad-v1').then(cache => {
            return cache.addAll([
                '/',
                '/app.css',
                '/app.js',
                '/manifest.json'
            ]);
        })
    );
});

self.addEventListener('fetch', (e) => {
    e.respondWith(
        caches.match(e.request).then(response => {
            return response || fetch(e.request);
        })
    );
});
]]

local server = http.new(false, false)
server:setPort(8080)
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
        if path == "/" then
            return html, 200, { ["Content-Type"] = "text/html" }
        elseif path == "/app.css" then
            return css, 200, { ["Content-Type"] = "text/css" }
        elseif path == "/app.js" then
            return js, 200, { ["Content-Type"] = "application/javascript" }
        elseif path == "/manifest.json" then
            return manifest, 200, { ["Content-Type"] = "application/json" }
        elseif path == "/sw.js" then
            return sw, 200, { ["Content-Type"] = "application/javascript" }
        else
            return "Not Found", 404, responseHeaders
        end
    elseif method == "POST" and path == "/" then
        local ok, data = pcall(json.decode, body)
        if ok and data.key then
            -- Convert modifiers to eventtap flags
            local modifiers = {}
            for _, mod in ipairs(data.modifiers or {}) do
                local normalizedMod = mod:lower()
                if modifierMap[normalizedMod] then
                    table.insert(modifiers, modifierMap[normalizedMod])
                end
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
            else
                print("Unknown key:", keyName)
                return "Bad Request", 400, responseHeaders
            end
        end
        return "Bad Request", 400, responseHeaders
    end
    return "Not Found", 404, responseHeaders
end)

server:start()
print("CloudPad server running at http://localhost:8080")

local ipAddress = getLocalIP()
if ipAddress then
    local url = "http://" .. ipAddress .. ":8080"

    hotkey.bind({ "cmd", "ctrl" }, "C", function()
        pasteboard.setContents(url)
        alert.show("URL copied to clipboard!\n" .. url, 2)
    end)

    print("Use ⌘⌃C to copy server URL: " .. url)
else
    print("Could not determine IP address - URL copying disabled")
end

return server
