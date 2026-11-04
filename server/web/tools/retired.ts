// The demo's way out. Once the shop's real site is live somewhere other than the demo's own
// address, deploy this at the demo's address instead of the demo:
//
//   DEMO_MOVED_TO=https://<the real site> npm run build:retired     (then deploy dist-retired/)
//
// Every browser that opened the demo, and every phone that added it to the Home Screen, gets
// it the next time it's opened: its service worker (sw.js here) takes the demo's place at once,
// clears the demo's files, steps aside and reloads the open pages. Every address then shows one
// page, "Izzy Clipz has moved.", with a button to the real site's Get the app page; that page
// (moved.js) clears what the demo kept in this browser. Without this, a demo that's simply
// deleted keeps opening from the copy its service worker kept, with bookings that go nowhere.

import { copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

export interface ShopPhone {
  display: string;
  e164: string;
}

/** The real site's address: an https origin, nothing else ("https://izzyclipz.com"). */
export function movedToOrigin(address: string | undefined): string {
  if (!address?.trim()) throw new Error('Say where Izzy Clipz moved to: DEMO_MOVED_TO=https://<the real site> npm run build:retired');
  let url: URL;
  try {
    url = new URL(address.trim());
  } catch {
    throw new Error(`"${address}" isn't a web address. Use the real site's, like https://izzyclipz.com`);
  }
  if (url.protocol !== 'https:' || url.username || url.password) throw new Error(`The real site's address must start with https:// (got "${address}")`);
  return url.origin;
}

const escapeHtml = (text: string) => text.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c] ?? c);

/** The page every address of the old demo shows. */
function movedPage(origin: string, phone: ShopPhone): string {
  const host = escapeHtml(new URL(origin).host);
  const app = escapeHtml(`${origin}/app`);
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
    <title>Izzy Clipz has moved</title>
    <meta name="description" content="The Izzy Clipz app has moved to ${host}." />
    <meta name="robots" content="noindex" />
    <meta name="theme-color" content="#000000" />
    <link rel="icon" type="image/png" sizes="32x32" href="/favicon-32.png" />
    <link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png" />
    <style>
      body {
        margin: 0;
        background: #fff;
        color: #1d1d1f;
        font: 17px/1.5 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", "Segoe UI", Arial, sans-serif;
      }
      main {
        max-width: 560px;
        margin: 0 auto;
        padding: max(64px, env(safe-area-inset-top)) max(24px, env(safe-area-inset-right)) max(64px, env(safe-area-inset-bottom)) max(24px, env(safe-area-inset-left));
        text-align: center;
      }
      img {
        width: 96px;
        height: 96px;
        border-radius: 22px;
        box-shadow: 0 6px 20px rgba(0, 0, 0, 0.18);
      }
      h1 {
        margin: 32px 0 12px;
        font: 600 40px/1.1 -apple-system, BlinkMacSystemFont, "SF Pro Display", "Helvetica Neue", "Segoe UI", Arial, sans-serif;
        letter-spacing: -0.01em;
      }
      p {
        margin: 0 0 16px;
      }
      .lead {
        color: #6e6e73;
        font-size: 21px;
      }
      .lead strong {
        color: #1d1d1f;
        font-weight: 600;
        overflow-wrap: anywhere;
      }
      .button {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        min-height: 50px;
        margin: 16px 0 32px;
        padding: 0 28px;
        border-radius: 980px;
        background: #1f4fd8;
        color: #fff;
        font-weight: 600;
        text-decoration: none;
      }
      .button:hover {
        background: #1a43b8;
      }
      a:focus-visible {
        outline: 3px solid #1f4fd8;
        outline-offset: 3px;
      }
      .note {
        color: #6e6e73;
      }
      .call a {
        color: #1f4fd8;
        font-weight: 600;
        white-space: nowrap;
      }
    </style>
  </head>
  <body>
    <main>
      <img src="/icon-192.png" width="96" height="96" alt="" />
      <h1>Izzy Clipz has moved.</h1>
      <p class="lead">This was the demo of the Izzy Clipz app. The real one is at <strong>${host}</strong>, and bookings there go straight to the shop.</p>
      <a class="button" href="${app}">Get the new app</a>
      <p class="note">Added the demo to your Home Screen? You can delete its icon now.</p>
      <p class="call">Prefer to call? <a href="tel:${escapeHtml(phone.e164)}">${escapeHtml(phone.display)}</a></p>
    </main>
    <script src="/moved.js"></script>
  </body>
</html>
`;
}

/** Runs on the moved page: this browser forgets everything the demo kept here. */
const MOVED_SCRIPT = `// The demo has moved (index.html): this browser forgets everything it kept here.
(function () {
  try { localStorage.clear(); } catch (error) {}
  try { sessionStorage.clear(); } catch (error) {}
  if (window.caches) {
    caches.keys().then(function (names) { return Promise.all(names.map(function (name) { return caches.delete(name); })); }).catch(function () {});
  }
  if (navigator.serviceWorker) {
    navigator.serviceWorker.getRegistrations().then(function (all) { return Promise.all(all.map(function (r) { return r.unregister(); })); }).catch(function () {});
  }
})();
`;

/**
 * Takes the demo worker's place in every browser that has it (no waiting for a tap on Reload),
 * clears its files, steps aside, and reloads the pages it had open: they get the moved page.
 */
const RETIRED_WORKER = `// The demo has moved. This worker takes the demo's place, clears its files, steps aside, and
// reloads the open pages, which then show where Izzy Clipz is now.
self.addEventListener('install', function () {
  self.skipWaiting();
});
self.addEventListener('activate', function (event) {
  event.waitUntil((async function () {
    var names = await caches.keys();
    await Promise.all(names.map(function (name) { return caches.delete(name); }));
    var pages = await self.clients.matchAll({ type: 'window' });
    await self.registration.unregister();
    await Promise.all(pages.map(function (page) { return page.navigate(page.url).catch(function () {}); }));
  })());
});
`;

/** Hosted like the demo, every address showing the moved page; nothing kept, nothing listed in searches. */
const RETIRED_HOSTING = {
  $schema: 'https://openapi.vercel.sh/vercel.json',
  framework: null,
  rewrites: [{ source: '/((?!assets/).*)', destination: '/index.html' }],
  headers: [
    {
      source: '/sw.js',
      headers: [
        { key: 'cache-control', value: 'no-cache' },
        { key: 'content-type', value: 'text/javascript; charset=utf-8' },
      ],
    },
    {
      source: '/(.*)',
      headers: [
        { key: 'x-content-type-options', value: 'nosniff' },
        { key: 'referrer-policy', value: 'strict-origin-when-cross-origin' },
        { key: 'x-frame-options', value: 'DENY' },
        { key: 'x-robots-tag', value: 'noindex' },
        {
          key: 'content-security-policy',
          value: "default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; img-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
        },
      ],
    },
  ],
};

/** The icons the moved page and a browser tab show, from public/. */
export const RETIRED_ICONS = ['favicon-32.png', 'favicon-48.png', 'apple-touch-icon.png', 'icon-192.png'];

/** The retired site's own files, by name (the icons are copied besides). */
export function retiredFiles(movedTo: string | undefined, phone: ShopPhone): Record<string, string> {
  const origin = movedToOrigin(movedTo);
  return {
    'index.html': movedPage(origin, phone),
    'moved.js': MOVED_SCRIPT,
    'sw.js': RETIRED_WORKER,
    'vercel.json': `${JSON.stringify(RETIRED_HOSTING, null, 2)}\n`,
    'robots.txt': '# Izzy Clipz has moved: nothing here to list.\nUser-agent: *\nAllow: /\n',
  };
}

/** Writes the retired site into `outDir` (emptied first, the folder itself kept). */
export function buildRetired(outDir: string, movedTo: string | undefined): void {
  const web = fileURLToPath(new URL('..', import.meta.url));
  const catalog = JSON.parse(readFileSync(join(web, '../data/catalog.json'), 'utf8')) as { shop: { phone: ShopPhone } };
  const files = retiredFiles(movedTo, catalog.shop.phone);
  if (existsSync(outDir)) for (const name of readdirSync(outDir)) rmSync(join(outDir, name), { recursive: true, force: true });
  else mkdirSync(outDir, { recursive: true });
  for (const [name, content] of Object.entries(files)) writeFileSync(join(outDir, name), content);
  for (const icon of RETIRED_ICONS) copyFileSync(join(web, 'public', icon), join(outDir, icon));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const outDir = fileURLToPath(new URL('../dist-retired/', import.meta.url));
  try {
    buildRetired(outDir, process.env.DEMO_MOVED_TO ?? process.argv[2]);
    console.log(`The retired demo is in ${outDir}: deploy it at the demo's address, as it is.`);
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    process.exit(1);
  }
}
