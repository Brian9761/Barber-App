// What the service worker (src/sw/sw.ts) does with each request, kept apart from
// the worker so the unit tests can check every rule:
//
// - The site's pages open from this version's own copy of the page (the "app
//   shell"), also offline; Izzy Clipz Business's (/business/…) from its own page,
//   which links its own manifest and icons. A page this version doesn't know (a newer version's,
//   say) is asked for on the network, and the offline page answers when that fails.
// - The four legal pages are asked for on the network first, so a change the shop publishes
//   shows at once (the documents promise "we'll post the new version here"), and open from this
//   version's page offline, or when the network is slow.
// - This version's files (scripts, styles, fonts, photos, icons) come from its cache.
// - The API is never answered from a cache, except the shop's public catalog
//   (menu, team and hours), which is asked for on the network first, and the last
//   copy is used offline. Nothing with a token or personal data is ever kept:
//   appointments, cards, the owner's area and reviews always go to the network.
// - Other sites, and anything that isn't a GET, are left to the browser.

/** One file of this version, downloaded when the worker installs. */
export interface PrecacheEntry {
  /** "/assets/index-DN70w0ok.js", "/index.html". */
  url: string;
  /**
   * A hash of what's in it, for files whose names stay the same when they change (the page,
   * the icons, the manifest); null for /assets/ files, whose names change with what's in them.
   */
  revision: string | null;
}

/** The app shell: the site's page, which opens every route of the site. */
export const SHELL = '/index.html';
/** Izzy Clipz Business's page (/business/), which links its own manifest and icons: it opens every route under /business. */
export const BUSINESS_SHELL = '/business/index.html';
/** "You're offline. To book, call the shop." */
export const OFFLINE_PAGE = '/offline.html';
/** This version's files: one cache per version, the older ones deleted once a new one takes over. */
export const PRECACHE_PREFIX = 'izzy-app-';
/** The last catalog the shop's server answered, so the app opens offline with the menu and hours. */
export const CATALOG_CACHE = 'izzy-catalog-v1';
export const CATALOG_PATH = '/api/catalog';

/** The message a page sends to the new version's waiting worker when someone taps Reload. */
export const SKIP_WAITING = 'SKIP_WAITING';

/** The site's pages (src/App.tsx), the four legal ones included. Anything else is a page this version doesn't know. */
const PAGES = new Set([
  '/',
  '/services',
  '/barbers',
  '/reviews',
  '/visit',
  '/app',
  '/appointments',
  '/book',
  '/privacy',
  '/terms',
  '/cancellation-policy',
  '/accessibility',
  SHELL,
]);
const SECTIONS = ['/book/'];
/** The legal pages (src/legal/documents.ts): the network's first, then this version's. */
const LEGAL_PAGES = new Set(['/privacy', '/terms', '/cancellation-policy', '/accessibility']);

/** Headers that say who's asking: a request with any of them is never answered from a cache. */
const PERSONAL_HEADERS = ['authorization', 'x-manage-token', 'x-card-token'];

function withoutSlash(pathname: string): string {
  return pathname.length > 1 && pathname.endsWith('/') ? pathname.slice(0, -1) : pathname;
}

export function isAppPage(pathname: string): boolean {
  const path = withoutSlash(pathname);
  return PAGES.has(path) || SECTIONS.some((section) => path.startsWith(section));
}

/** One of the four legal pages, whose words change only when the shop publishes a new version. */
export function isLegalPage(pathname: string): boolean {
  return LEGAL_PAGES.has(withoutSlash(pathname));
}

/** Izzy Clipz Business's pages: /business and everything under it (its own files aside). */
export function isBusinessPage(pathname: string): boolean {
  return pathname === '/business' || pathname.startsWith('/business/');
}

/** Where a file is kept in the cache: its address, with its revision when its name doesn't change. */
export function cacheKey(entry: PrecacheEntry): string {
  return entry.revision ? `${entry.url}?__rev=${entry.revision}` : entry.url;
}

export type Route =
  /** Not the worker's to answer: the browser does what it would without it. */
  | { kind: 'browser' }
  /** One of the site's pages: this version's page (the site's, or Business's), from its cache. */
  | { kind: 'shell'; page: typeof SHELL | typeof BUSINESS_SHELL }
  /**
   * A legal page: the network's page first (it loads the documents as the shop last published
   * them), this version's when there's no network or it's slow.
   */
  | { kind: 'fresh'; page: typeof SHELL }
  /** One of this version's files, from its cache. */
  | { kind: 'file'; key: string }
  /** A page this version doesn't know: the network, else the offline page. */
  | { kind: 'page' }
  /** The shop's public catalog: the network first, else the last copy. */
  | { kind: 'catalog' };

/** What the rules read of a request (a Request has all of it). */
export interface RequestLike {
  url: string;
  method: string;
  mode: string;
  headers: { has(name: string): boolean };
}

/**
 * What to do with `request`. `origin` is the site's own; `files` maps each of this version's
 * files (by path) to its cache key.
 */
export function routeFor(request: RequestLike, origin: string, files: ReadonlyMap<string, string>): Route {
  if (request.method !== 'GET') return { kind: 'browser' };
  const url = new URL(request.url);
  if (url.origin !== origin) return { kind: 'browser' };
  const path = url.pathname;

  if (path === '/api' || path.startsWith('/api/')) {
    // Coming back from Stripe's card page goes through the server: a page of the API, never cached.
    if (request.mode === 'navigate') return { kind: 'browser' };
    const personal = PERSONAL_HEADERS.some((name) => request.headers.has(name));
    return path === CATALOG_PATH && url.search === '' && !personal ? { kind: 'catalog' } : { kind: 'browser' };
  }

  if (request.mode === 'navigate') {
    const key = files.get(path);
    if (isBusinessPage(path) && !key) return { kind: 'shell', page: BUSINESS_SHELL };
    if (isLegalPage(path)) return { kind: 'fresh', page: SHELL };
    if (isAppPage(path)) return { kind: 'shell', page: SHELL };
    return key ? { kind: 'file', key } : { kind: 'page' };
  }

  const key = files.get(path);
  return key ? { kind: 'file', key } : { kind: 'browser' };
}
