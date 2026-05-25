// Minimal cache-first service worker. Network errors fall back to cache.
const CACHE = "cloudpad-v1";
const ASSETS = [
  "/", "/app.css", "/app.js",
  "/transport.js", "/pointer.js", "/keyboard.js", "/bigrams.js",
  "/manifest.json"
];

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(ASSETS)).catch(() => {}));
  self.skipWaiting();
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener("fetch", (e) => {
  const url = new URL(e.request.url);
  // Never cache event POSTs or screenshot stream.
  if (e.request.method !== "GET" || url.pathname === "/screenshot" || url.pathname === "/events" || url.pathname === "/health") {
    return;
  }
  e.respondWith(
    caches.match(e.request).then((hit) => hit || fetch(e.request).then((res) => {
      const copy = res.clone();
      caches.open(CACHE).then((c) => c.put(e.request, copy)).catch(() => {});
      return res;
    }).catch(() => caches.match("/")))
  );
});
