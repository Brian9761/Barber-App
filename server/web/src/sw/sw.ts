// The service worker: the site opens like an app from the Home Screen, also
// offline, and never shows anyone's appointments from a cache. The rules for each
// request are in ./routes.ts. The build (vite.config.ts) bundles this file into
// /sw.js with the list of this version's files written in.
//
// A new version installs quietly next to the one in use and waits: the page shows
// "A new version is ready · Reload", and only when someone taps Reload does it
// take over (src/pwa/register.ts). Nothing reloads by itself.

import { CATALOG_CACHE, CATALOG_PATH, cacheKey, OFFLINE_PAGE, PRECACHE_PREFIX, routeFor, SHELL, SKIP_WAITING, type PrecacheEntry } from './routes';

declare const self: ServiceWorkerGlobalScope;
/** This version's files, written in by the build. */
declare const __PRECACHE__: PrecacheEntry[];
/** A hash of that list: a new version whenever any file changes. */
declare const __VERSION__: string;
/** Whether this build talks to the shop's server; the demo answers in the page and never asks /api. */
declare const __API__: boolean;

const PRECACHE = `${PRECACHE_PREFIX}${__VERSION__}`;
const FILES: ReadonlyMap<string, string> = new Map(__PRECACHE__.map((entry) => [entry.url, cacheKey(entry)]));
/** How long the catalog may take before the last copy is used instead, on a poor signal. */
const CATALOG_PATIENCE_MS = 4000;

/** What shows if even the offline page isn't in the cache. */
const OFFLINE_TEXT = "You're offline. To book, call the shop: (442) 341-3053";

self.addEventListener('install', (event) => {
  event.waitUntil(Promise.all([precache(), __API__ ? keepCatalog() : undefined]));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(takeOver());
});

self.addEventListener('message', (event) => {
  const data: unknown = event.data;
  if (typeof data === 'object' && data !== null && (data as { type?: unknown }).type === SKIP_WAITING) void self.skipWaiting();
});

self.addEventListener('fetch', (event) => {
  const route = routeFor(event.request, self.location.origin, FILES);
  switch (route.kind) {
    case 'browser':
      return;
    case 'shell':
      event.respondWith(shell(event.request));
      return;
    case 'file':
      event.respondWith(file(route.key, event.request));
      return;
    case 'page':
      event.respondWith(page(event.request));
      return;
    case 'catalog':
      event.respondWith(catalog(event));
      return;
  }
});

/** Downloads this version's files, or takes them from an earlier version when they haven't changed. */
async function precache(): Promise<void> {
  const cache = await caches.open(PRECACHE);
  await Promise.all(
    __PRECACHE__.map(async (entry) => {
      const key = cacheKey(entry);
      if (await cache.match(key)) return;
      const earlier = await caches.match(key);
      if (earlier) {
        await cache.put(key, earlier);
        return;
      }
      const response = await fetch(new Request(entry.url, { cache: 'reload', credentials: 'same-origin' }));
      if (!response.ok) throw new Error(`Couldn't download ${entry.url} (${response.status})`);
      await cache.put(key, await withoutRedirect(response));
    }),
  );
}

/**
 * A first copy of the shop's catalog (public: the menu, team and hours), so the app opens offline
 * with them right after the first visit. Without a connection it's kept the next time it's asked for.
 */
async function keepCatalog(): Promise<void> {
  try {
    const response = await fetch(CATALOG_PATH, { cache: 'no-store', credentials: 'same-origin', headers: { Accept: 'application/json' } });
    if (response.ok) await (await caches.open(CATALOG_CACHE)).put(CATALOG_PATH, response);
  } catch {
    // Kept next time instead.
  }
}

/** The new version in charge: older versions' files go, and the open pages are this worker's. */
async function takeOver(): Promise<void> {
  for (const name of await caches.keys()) {
    if (name.startsWith(PRECACHE_PREFIX) && name !== PRECACHE) await caches.delete(name);
  }
  await self.clients.claim();
}

/** A page may not be answered with a response that was redirected, so it's copied without the redirect. */
async function withoutRedirect(response: Response): Promise<Response> {
  if (!response.redirected) return response;
  return new Response(await response.blob(), { status: response.status, statusText: response.statusText, headers: response.headers });
}

async function fromCache(key: string): Promise<Response | undefined> {
  return (await caches.open(PRECACHE)).match(key);
}

async function offlinePage(): Promise<Response> {
  const key = FILES.get(OFFLINE_PAGE);
  const cached = key ? await fromCache(key) : undefined;
  return cached ?? new Response(OFFLINE_TEXT, { status: 503, headers: { 'content-type': 'text/plain; charset=utf-8' } });
}

/** One of the site's pages: this version's page, so it opens offline and matches this version's files. */
async function shell(request: Request): Promise<Response> {
  const key = FILES.get(SHELL);
  const cached = key ? await fromCache(key) : undefined;
  return cached ?? page(request);
}

async function file(key: string, request: Request): Promise<Response> {
  return (await fromCache(key)) ?? fetch(request);
}

/** A page this version doesn't know: the network's, or the offline page when there's no network. */
async function page(request: Request): Promise<Response> {
  try {
    return await fetch(request);
  } catch {
    return offlinePage();
  }
}

/**
 * The shop's catalog (public: the menu, team and hours): the network's, kept for next time; the
 * last copy when there's no network, or when the network takes too long and there is one.
 */
async function catalog(event: FetchEvent): Promise<Response> {
  const cache = await caches.open(CATALOG_CACHE);
  const fresh = fetch(event.request).then(async (response) => {
    if (response.ok) await cache.put(CATALOG_PATH, response.clone());
    return response;
  });
  event.waitUntil(fresh.then(() => undefined, () => undefined));
  const saved = await cache.match(CATALOG_PATH);
  if (!saved) return fresh;
  const patience = new Promise<Response>((resolve) => setTimeout(() => resolve(saved.clone()), CATALOG_PATIENCE_MS));
  return Promise.race([fresh.catch(() => saved), patience]);
}
