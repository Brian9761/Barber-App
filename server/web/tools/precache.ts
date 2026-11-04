// The service worker's list of files to keep (its precache), made at the end of every build
// (vite.config.ts) and written into /sw.js. Files under /assets/ change their names when they
// change; every other file (the page, the offline page, the icons, the manifest) is listed with
// a revision: a hash of what's in it and of the site's hosting settings (its vercel.json). The
// worker answers pages with the copy it kept, headers and all, so a change to the headers alone
// must make a new version too: then returning visitors get the pages again, with the new headers.

import { createHash } from 'node:crypto';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import type { PrecacheEntry } from '../src/sw/routes.js';

export function sha256(content: string | Buffer): string {
  return createHash('sha256').update(content).digest('hex');
}

/**
 * Files the service worker doesn't keep: the picture link previews show, the file for search
 * engines, the hosting settings and the worker itself; and Inter's alphabets other than Latin,
 * which the site's own words never use (a browser downloads them only if a page needs them).
 */
export function precached(name: string): boolean {
  if (['og-image.png', 'robots.txt', 'vercel.json', 'sw.js'].includes(name) || name.endsWith('.map')) return false;
  return !/^assets\/inter-(?!latin)/.test(name);
}

/** Every file of the build, by its path in it: "index.html", "assets/index-DN70w0ok.js". */
export function builtFiles(outDir: string): string[] {
  const names: string[] = [];
  const walk = (dir: string) => {
    for (const name of readdirSync(dir)) {
      const path = join(dir, name);
      if (statSync(path).isDirectory()) walk(path);
      else names.push(relative(outDir, path).split(sep).join('/'));
    }
  };
  walk(outDir);
  return names.sort();
}

/** The files of the build in `outDir` the worker keeps, each with its revision; `hosting` is the hosting settings as written. */
export function precacheEntries(outDir: string, hosting: string): PrecacheEntry[] {
  const settings = sha256(hosting);
  return builtFiles(outDir)
    .filter(precached)
    .map((name) => ({
      url: `/${name}`,
      revision: name.startsWith('assets/') ? null : sha256(`${sha256(readFileSync(join(outDir, name)))}|${settings}`).slice(0, 16),
    }));
}

/** The worker's version: a new one whenever any file it keeps, or the hosting settings, change. */
export function precacheVersion(entries: PrecacheEntry[]): string {
  return sha256(JSON.stringify(entries)).slice(0, 12);
}
