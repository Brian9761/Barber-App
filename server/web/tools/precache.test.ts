// @vitest-environment node
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { precached, precacheEntries, precacheVersion } from './precache.js';

// What the service worker keeps, and its version: a change to a page, or to the hosting
// settings alone, makes a new version, so returning visitors get the pages again with the
// headers they're served with now.

let dir: string;

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'izzy-precache-'));
  mkdirSync(join(dir, 'assets'));
  const files: Record<string, string> = {
    'index.html': '<!doctype html><div id="root"></div>',
    'offline.html': "<h1>You're offline.</h1>",
    'manifest.webmanifest': '{"name":"Izzy Clipz"}',
    'icon-192.png': 'png',
    'og-image.png': 'png',
    'robots.txt': 'User-agent: *',
    'vercel.json': '{}',
    'sw.js': 'self',
    'assets/index-abc123.js': 'console.log(1)',
    'assets/index-abc123.js.map': '{}',
    'assets/inter-latin-wght-normal-x.woff2': 'font',
    'assets/inter-cyrillic-wght-normal-x.woff2': 'font',
    'privacy/index.html': '<!doctype html><div id="root"><h1>Privacy Policy</h1></div>',
  };
  mkdirSync(join(dir, 'privacy'));
  for (const [name, content] of Object.entries(files)) writeFileSync(join(dir, name), content);
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

const HOSTING = '{"headers":[{"source":"/(.*)","headers":[{"key":"x-frame-options","value":"DENY"}]}]}';

describe('the service worker’s files', () => {
  it('are the site’s own, not the share image, the robots file, the hosting settings, the worker, the legal pages’ plain HTML or other alphabets', () => {
    expect(precacheEntries(dir, HOSTING).map((entry) => entry.url)).toEqual([
      '/assets/index-abc123.js',
      '/assets/inter-latin-wght-normal-x.woff2',
      '/icon-192.png',
      '/index.html',
      '/manifest.webmanifest',
      '/offline.html',
    ]);
    // Online the worker asks the network for a legal page first, and offline the app's own page opens it.
    for (const name of ['privacy/index.html', 'terms/index.html', 'cancellation-policy/index.html', 'accessibility/index.html']) expect(precached(name), name).toBe(false);
    expect(precached('business/index.html')).toBe(true);
    expect(precached('assets/inter-latin-ext-wght-normal-x.woff2')).toBe(true);
    expect(precached('assets/inter-greek-wght-normal-x.woff2')).toBe(false);
  });

  it('name files under /assets/ by their names alone, and the others by what’s in them and the hosting settings', () => {
    const entries = precacheEntries(dir, HOSTING);
    expect(entries.find((e) => e.url === '/assets/index-abc123.js')!.revision).toBeNull();
    for (const entry of entries.filter((e) => !e.url.startsWith('/assets/'))) expect(entry.revision, entry.url).toMatch(/^[0-9a-f]{16}$/);
  });

  it('make a new version when a page changes', () => {
    const before = precacheEntries(dir, HOSTING);
    writeFileSync(join(dir, 'index.html'), '<!doctype html><div id="root"></div><!-- new -->');
    const after = precacheEntries(dir, HOSTING);
    expect(after.find((e) => e.url === '/index.html')!.revision).not.toBe(before.find((e) => e.url === '/index.html')!.revision);
    expect(precacheVersion(after)).not.toBe(precacheVersion(before));
  });

  it('make a new version when only the headers change, with every page downloaded again', () => {
    const before = precacheEntries(dir, HOSTING);
    const after = precacheEntries(dir, HOSTING.replace('DENY', 'SAMEORIGIN'));
    expect(precacheVersion(after)).not.toBe(precacheVersion(before));
    for (const url of ['/index.html', '/offline.html', '/manifest.webmanifest', '/icon-192.png']) {
      expect(after.find((e) => e.url === url)!.revision, url).not.toBe(before.find((e) => e.url === url)!.revision);
    }
    // The hashed files keep their names, and their copies.
    expect(after.find((e) => e.url === '/assets/index-abc123.js')).toEqual(before.find((e) => e.url === '/assets/index-abc123.js'));
  });

  it('stay the same version when nothing changed', () => {
    expect(precacheVersion(precacheEntries(dir, HOSTING))).toBe(precacheVersion(precacheEntries(dir, HOSTING)));
  });
});
