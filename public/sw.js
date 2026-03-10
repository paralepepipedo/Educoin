// ============================================================
// sw.js — Service Worker EduCoins
// VERSIÓN: 1.0.0 — 2026-03-08
// Propósito: hacer la app instalable como PWA
// Estrategia: network-first (siempre datos frescos)
// ============================================================

const CACHE_NAME = 'educoins-v1';

// Archivos estáticos a cachear para offline básico
const PRECACHE = [
  '/',
  '/dashboard/dashboard.html',
  '/shared/shared.css',
  '/manifest.json',
];

// ── Instalar: precachear estáticos ──
self.addEventListener('install', function(event) {
  event.waitUntil(
    caches.open(CACHE_NAME).then(function(cache) {
      return cache.addAll(PRECACHE).catch(function() {
        // Si falla alguno, continuar igual
        return Promise.resolve();
      });
    })
  );
  self.skipWaiting();
});

// ── Activar: limpiar caches viejos ──
self.addEventListener('activate', function(event) {
  event.waitUntil(
    caches.keys().then(function(keys) {
      return Promise.all(
        keys.filter(function(k) { return k !== CACHE_NAME; })
            .map(function(k) { return caches.delete(k); })
      );
    })
  );
  self.clients.claim();
});

// ── Fetch: network-first, fallback a cache ──
self.addEventListener('fetch', function(event) {
  // Solo interceptar GET, no APIs
  if (event.request.method !== 'GET') return;
  if (event.request.url.includes('/api/')) return;
  if (event.request.url.includes('clerk')) return;

  event.respondWith(
    fetch(event.request)
      .then(function(response) {
        // Guardar copia en cache si es válida
        if (response && response.status === 200 && response.type === 'basic') {
          var clone = response.clone();
          caches.open(CACHE_NAME).then(function(cache) {
            cache.put(event.request, clone);
          });
        }
        return response;
      })
      .catch(function() {
        // Sin red → intentar cache
        return caches.match(event.request);
      })
  );
});
