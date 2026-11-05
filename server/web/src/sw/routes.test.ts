import { describe, expect, it } from 'vitest';
import { cacheKey, isAppPage, isBusinessPage, isLegalPage, routeFor, type RequestLike } from './routes';

// What the service worker answers from its cache, and what it never does: nothing with a token
// or personal data, no reviews (Google's terms), and nothing from other sites.

const ORIGIN = 'https://izzy-clipz.example';
const FILES = new Map([
  ['/index.html', '/index.html?__rev=aaaa'],
  ['/business/index.html', '/business/index.html?__rev=eeee'],
  ['/business/manifest.webmanifest', '/business/manifest.webmanifest?__rev=ffff'],
  ['/offline.html', '/offline.html?__rev=bbbb'],
  ['/manifest.webmanifest', '/manifest.webmanifest?__rev=cccc'],
  ['/icon-192.png', '/icon-192.png?__rev=dddd'],
  ['/assets/index-DN70w0ok.js', '/assets/index-DN70w0ok.js'],
]);

function request(path: string, init: { method?: string; mode?: string; headers?: Record<string, string>; origin?: string } = {}): RequestLike {
  const headers = new Headers(init.headers);
  return { url: `${init.origin ?? ORIGIN}${path}`, method: init.method ?? 'GET', mode: init.mode ?? 'cors', headers };
}

const route = (path: string, init?: Parameters<typeof request>[1]) => routeFor(request(path, init), ORIGIN, FILES);
const page = (path: string) => route(path, { mode: 'navigate' });

describe('pages', () => {
  it('opens every page of the site from this version’s own page, also offline', () => {
    for (const path of ['/', '/?source=app', '/services', '/barbers', '/reviews', '/visit', '/app', '/appointments', '/book', '/book/time', '/book/confirmed', '/book/card-return?status=saved&session_id=cs_1', '/visit/']) {
      expect(page(path), path).toEqual({ kind: 'shell', page: '/index.html' });
    }
    expect(isAppPage('/booking')).toBe(false);
  });

  it('asks the network for the four legal pages first, so a published change shows at once, and opens them offline too', () => {
    for (const path of ['/privacy', '/terms', '/cancellation-policy', '/accessibility', '/privacy#saved-cards', '/terms/', '/accessibility?from=app']) {
      // "fresh": the network's page, else this version's (the same page every route opens).
      expect(page(path), path).toEqual({ kind: 'fresh', page: '/index.html' });
      expect(isAppPage(path.split(/[?#]/)[0]!), path).toBe(true);
    }
    // Their Markdown files aren't pages of the site; the other pages still open from this version's page.
    expect(isLegalPage('/privacy.md')).toBe(false);
    expect(isAppPage('/privacy.md')).toBe(false);
    expect(isAppPage('/privacy/policy')).toBe(false);
    expect(isLegalPage('/services')).toBe(false);
    expect(page('/business/privacy')).toEqual({ kind: 'shell', page: '/business/index.html' });
  });

  it('opens Izzy Clipz Business from its own page, with its own manifest, also offline', () => {
    for (const path of ['/business', '/business/', '/business/today', '/business/today?source=app', '/business/analytics', '/business/settings?stripe=active', '/business/no-such-page']) {
      expect(page(path), path).toEqual({ kind: 'shell', page: '/business/index.html' });
    }
    // Its own files are files, not pages.
    expect(page('/business/manifest.webmanifest')).toEqual({ kind: 'file', key: '/business/manifest.webmanifest?__rev=ffff' });
    expect(route('/business/manifest.webmanifest')).toEqual({ kind: 'file', key: '/business/manifest.webmanifest?__rev=ffff' });
    expect(isBusinessPage('/businesses')).toBe(false);
  });

  it('asks the network for a page this version doesn’t know, so the offline page can answer when there’s none', () => {
    expect(page('/a-new-page')).toEqual({ kind: 'page' });
    expect(page('/__e2e/stripe/cs_test_1')).toEqual({ kind: 'page' });
  });

  it('opens its own files when they’re asked for as a page', () => {
    expect(page('/offline.html')).toEqual({ kind: 'file', key: '/offline.html?__rev=bbbb' });
  });

  it('leaves the way back from Stripe’s card page, through the server, to the network', () => {
    expect(page('/api/cards/return?session_id=cs_1&to=web')).toEqual({ kind: 'browser' });
    expect(page('/api')).toEqual({ kind: 'browser' });
  });
});

describe('files', () => {
  it('serves this version’s files from its cache, by their own address', () => {
    expect(route('/assets/index-DN70w0ok.js')).toEqual({ kind: 'file', key: '/assets/index-DN70w0ok.js' });
    expect(route('/icon-192.png')).toEqual({ kind: 'file', key: '/icon-192.png?__rev=dddd' });
    expect(route('/manifest.webmanifest')).toEqual({ kind: 'file', key: '/manifest.webmanifest?__rev=cccc' });
  });

  it('leaves files it doesn’t have to the browser', () => {
    expect(route('/assets/index-NEWER.js')).toEqual({ kind: 'browser' });
    expect(route('/og-image.png')).toEqual({ kind: 'browser' });
  });

  it('keeps a file whose name doesn’t change under its revision, so a new one is never mistaken for it', () => {
    expect(cacheKey({ url: '/index.html', revision: 'abc123' })).toBe('/index.html?__rev=abc123');
    expect(cacheKey({ url: '/assets/index-DN70w0ok.js', revision: null })).toBe('/assets/index-DN70w0ok.js');
  });
});

describe('the API', () => {
  it('keeps only the shop’s public catalog (menu, team and hours), to open offline', () => {
    expect(route('/api/catalog')).toEqual({ kind: 'catalog' });
  });

  it('never keeps anything with a token or personal data, the reviews or the open times', () => {
    expect(route('/api/catalog', { headers: { Authorization: 'Bearer x' } })).toEqual({ kind: 'browser' });
    expect(route('/api/catalog', { headers: { 'X-Manage-Token': 'x' } })).toEqual({ kind: 'browser' });
    expect(route('/api/catalog?fresh=1')).toEqual({ kind: 'browser' });
    expect(route('/api/appointments/00000000-0000-4000-8000-000000000005', { headers: { 'X-Manage-Token': 'x' } })).toEqual({ kind: 'browser' });
    expect(route('/api/appointments/00000000-0000-4000-8000-000000000005')).toEqual({ kind: 'browser' });
    expect(route('/api/reviews')).toEqual({ kind: 'browser' });
    expect(route('/api/availability?offeringId=x&from=2026-11-05&days=14')).toEqual({ kind: 'browser' });
    expect(route('/api/no-show-policy?serviceId=haircut&barberId=any')).toEqual({ kind: 'browser' });
    expect(route('/api/owner/appointments', { headers: { Authorization: 'Bearer x' } })).toEqual({ kind: 'browser' });
    expect(route('/api/owner/analytics?from=2026-11-01&to=2026-11-04', { headers: { Authorization: 'Bearer x' } })).toEqual({ kind: 'browser' });
    expect(page('/api/owner/sales')).toEqual({ kind: 'browser' });
  });

  it('leaves bookings, cancellations and cards to the network', () => {
    expect(route('/api/appointments', { method: 'POST', headers: { 'X-Manage-Token': 'x' } })).toEqual({ kind: 'browser' });
    expect(route('/api/appointments/1/cancel', { method: 'POST' })).toEqual({ kind: 'browser' });
    expect(route('/api/cards', { method: 'POST', headers: { 'X-Card-Token': 'x' } })).toEqual({ kind: 'browser' });
  });
});

describe('other sites', () => {
  it('leaves them to the browser: Stripe, maps, Instagram', () => {
    expect(route('/c/pay/cs_test_1', { origin: 'https://checkout.stripe.com', mode: 'navigate' })).toEqual({ kind: 'browser' });
    expect(route('/maps', { origin: 'https://www.google.com' })).toEqual({ kind: 'browser' });
    expect(route('/index.html', { origin: 'https://izzy-clipz.example:8443' })).toEqual({ kind: 'browser' });
  });
});
