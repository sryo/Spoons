// Bootstrap: register the service worker, request a wake lock, and surface
// connection state via a small offline banner if /health stops responding.
(function () {
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('/sw.js', { scope: '/' }).catch(() => {});
  }

  let wakeLock = null;
  async function acquireWakeLock() {
    try {
      if ('wakeLock' in navigator && !wakeLock) {
        wakeLock = await navigator.wakeLock.request('screen');
        wakeLock.addEventListener('release', () => { wakeLock = null; });
      }
    } catch (_) {}
  }
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') acquireWakeLock();
  });
  document.addEventListener('touchstart', acquireWakeLock, { once: true, passive: true });

  // Cheap heartbeat to surface "server gone" state. Doesn't matter much on
  // LAN but stops the UI from looking responsive when it isn't.
  setInterval(() => {
    fetch('/health', { cache: 'no-store' })
      .then((r) => r.ok)
      .then((ok) => document.body.classList.toggle('offline', !ok))
      .catch(() => document.body.classList.add('offline'));
  }, 5000);
})();
