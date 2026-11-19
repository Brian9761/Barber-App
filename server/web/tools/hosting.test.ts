// @vitest-environment node
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { redirectFor, redirectsOf, rewriteFor, rewritesOf, sourcePattern } from './hosting.js';
import { LEGAL_PAGE_FILES } from './prerender.js';

// The hosting's rewrites, as the end-to-end servers apply them, with the site's real settings:
// the shop's (../vercel.json) and the demo's (vercel.json here). A file of the build is always
// served first; these say what an address without one opens.

const SHOP_HOSTING = readFileSync(new URL('../../vercel.json', import.meta.url), 'utf8');
const DEMO_HOSTING = readFileSync(new URL('../vercel.json', import.meta.url), 'utf8');
const SHOP = rewritesOf(SHOP_HOSTING);
const DEMO = rewritesOf(DEMO_HOSTING);

describe('a vercel.json source', () => {
  it('reads paths, ":name*" for the rest of the path, and regular expressions in parentheses', () => {
    expect(sourcePattern('/business').test('/business')).toBe(true);
    expect(sourcePattern('/business').test('/business/today')).toBe(false);
    const rest = sourcePattern('/business/:path*');
    for (const path of ['/business', '/business/', '/business/today', '/business/a/b']) expect(rest.test(path), path).toBe(true);
    expect(rest.test('/businesses')).toBe(false);
    expect(sourcePattern('/product/:id').test('/product/42')).toBe(true);
    expect(sourcePattern('/product/:id').test('/product/42/more')).toBe(false);
    const page = sourcePattern('/((?!api/|assets/).*)');
    expect(page.test('/book/time')).toBe(true);
    expect(page.test('/assets/main.js')).toBe(false);
    expect(page.test('/api/catalog')).toBe(false);
    expect(sourcePattern('/privacy.html').test('/privacyxhtml')).toBe(false);
  });
});

describe('a vercel.json redirect', () => {
  it('is permanent (308) unless it says otherwise (307), and leaves every other path alone', () => {
    const redirects = redirectsOf(
      JSON.stringify({
        redirects: [
          { source: '/old', destination: '/new', permanent: true },
          { source: '/for-now', destination: '/later', permanent: false },
          { source: '/plain', destination: '/elsewhere' },
        ],
      }),
    );
    expect(redirectFor(redirects, '/old')).toEqual({ destination: '/new', status: 308 });
    expect(redirectFor(redirects, '/for-now')).toEqual({ destination: '/later', status: 307 });
    expect(redirectFor(redirects, '/plain')).toEqual({ destination: '/elsewhere', status: 308 });
    expect(redirectFor(redirects, '/old/more')).toBeNull();
    expect(redirectsOf(JSON.stringify({ rewrites: [] }))).toEqual([]);
  });
});

describe.each([
  ['the shop’s site', SHOP_HOSTING],
  ['the demo', DEMO_HOSTING],
])('the redirects of %s', (_name, hosting) => {
  // Its plain HTML is a file at "/privacy/index.html" too: that address goes to the page itself, so
  // it's never the policy without JavaScript and "This page isn't here." with it.
  it('send each legal page’s file address to the page’s own, for good, before any file is served', () => {
    const redirects = redirectsOf(hosting);
    for (const file of LEGAL_PAGE_FILES) {
      const path = `/${file.replace(/\/index\.html$/, '')}`;
      expect(redirectFor(redirects, `/${file}`), file).toEqual({ destination: path, status: 308 });
      expect(redirectFor(redirects, path), path).toBeNull();
      expect(redirectFor(redirects, `${path}/`), `${path}/`).toBeNull();
    }
    for (const path of ['/', '/book/time', '/business', '/business/', '/business/today']) expect(redirectFor(redirects, path), path).toBeNull();
  });

  // The site's and Business's own pages are files too ("/index.html", "/business/index.html"): those
  // addresses go to the page's own, for good, so they never open "This page isn't here.".
  it('send the site’s and Business’s page files to their own addresses, for good', () => {
    const redirects = redirectsOf(hosting);
    expect(redirectFor(redirects, '/index.html')).toEqual({ destination: '/', status: 308 });
    expect(redirectFor(redirects, '/business/index.html')).toEqual({ destination: '/business/', status: 308 });
    // Nothing else that ends that way.
    for (const path of ['/book/index.html', '/assets/index.html', '/index.htm']) expect(redirectFor(redirects, path), path).toBeNull();
  });
});

describe.each([
  ['the shop’s site', SHOP],
  ['the demo', DEMO],
])('the hosting of %s', (_name, rewrites) => {
  it('opens each legal page’s plain HTML at its address, with or without a trailing slash', () => {
    for (const file of LEGAL_PAGE_FILES) {
      const path = `/${file.replace(/\/index\.html$/, '')}`;
      expect(rewriteFor(rewrites, path), path).toBe(`/${file}`);
      expect(rewriteFor(rewrites, `${path}/`), `${path}/`).toBe(`/${file}`);
    }
  });

  it('opens the site’s page everywhere else, Business’s under /business, and nothing for a missing file under /assets/', () => {
    for (const path of ['/', '/book/time', '/appointments', '/Privacy', '/privacy/more']) expect(rewriteFor(rewrites, path), path).toBe('/index.html');
    for (const path of ['/business', '/business/today']) expect(rewriteFor(rewrites, path), path).toBe('/business/index.html');
    expect(rewriteFor(rewrites, '/assets/main-missing.js')).toBeNull();
  });
});
