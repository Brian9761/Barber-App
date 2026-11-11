// @vitest-environment node
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { rewriteFor, rewritesOf, sourcePattern } from './hosting.js';
import { LEGAL_PAGE_FILES } from './prerender.js';

// The hosting's rewrites, as the end-to-end servers apply them, with the site's real settings:
// the shop's (../vercel.json) and the demo's (vercel.json here). A file of the build is always
// served first; these say what an address without one opens.

const SHOP = rewritesOf(readFileSync(new URL('../../vercel.json', import.meta.url), 'utf8'));
const DEMO = rewritesOf(readFileSync(new URL('../vercel.json', import.meta.url), 'utf8'));

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
