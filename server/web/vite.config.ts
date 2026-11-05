import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import react from '@vitejs/plugin-react';
import { build as viteBuild, type Plugin, type Rollup } from 'vite';
import { defineConfig } from 'vitest/config';
import { legalDocuments, legalStrict } from './tools/legal.js';
import { precacheEntries, precacheVersion } from './tools/precache.js';

// The website builds into ../public, which Vercel serves next to the API (one
// project, one origin). In development, `npm run dev` here proxies /api to the
// API's own dev server (`npm run dev` in server/, http://localhost:3000).
//
// Every build ends with the service worker, /sw.js (src/sw/), which keeps the
// files of the version it was built with, so the site opens like an app from the
// Home Screen, also offline.
//
// The demo version (`npm run build:demo`, or VITE_DEMO_MODE=1) builds into
// dist-demo/ instead: the same site, answering its own API calls in the browser
// (src/demo/), with a vercel.json to host it as a static site of its own.

const API_DEV_SERVER = 'http://localhost:3000';

const here = (path: string) => fileURLToPath(new URL(path, import.meta.url));

/**
 * The site's public address, for the few links that must be absolute in the
 * HTML itself (the share image that link previews show, og:image and
 * twitter:image). It's the API's PUBLIC_BASE_URL, since the site and the API
 * share one origin. Unset: the links stay relative.
 */
function siteOrigin(): string {
  const configured = process.env.PUBLIC_BASE_URL?.trim();
  if (!configured) return '';
  try {
    const url = new URL(configured);
    return url.protocol === 'https:' ? url.origin : '';
  } catch {
    return '';
  }
}

function absoluteSocialLinks(): Plugin {
  return {
    name: 'izzy-absolute-social-links',
    transformIndexHtml(html) {
      const origin = siteOrigin();
      return origin ? html.replaceAll('content="/og-image.png"', `content="${origin}/og-image.png"`) : html;
    },
  };
}

/**
 * The demo version answers the site's API calls in the browser: wherever the site imports
 * src/api/backend.ts (the shop's server, over the network), it gets src/demo/backend.ts, and
 * wherever Izzy Clipz Business imports src/business/api/backend.ts, src/demo/owner/backend.ts.
 * So the demo has no code that calls /api, and the normal build has none of the demo's.
 */
function demoBackend(): Plugin {
  const swaps = new Map([
    [here('./src/api/backend.ts'), here('./src/demo/backend.ts')],
    [here('./src/business/api/backend.ts'), here('./src/demo/owner/backend.ts')],
  ]);
  return {
    name: 'izzy-demo-backend',
    enforce: 'pre',
    async resolveId(source, importer, options) {
      if (!/(^|\/)backend(\.ts)?$/.test(source)) return null;
      const resolved = await this.resolve(source, importer, { ...options, skipSelf: true });
      return resolved ? (swaps.get(resolved.id) ?? null) : null;
    },
  };
}

/** Izzy Clipz Business's pages (/business and everything under it): its own page, with its own manifest and icons. */
const BUSINESS_PAGE = /^\/business(\/[^.?]*)?(\?.*)?$/;

/**
 * In development, /business and its pages open business/index.html (the page that links Izzy
 * Clipz Business's manifest), as the hosting does (vercel.json); every other page index.html.
 */
function businessPages(): Plugin {
  const rewrite = (req: { url?: string }, _res: unknown, next: () => void) => {
    if (req.url && BUSINESS_PAGE.test(req.url)) req.url = '/business/index.html';
    next();
  };
  return {
    name: 'izzy-business-pages',
    configureServer(server) {
      server.middlewares.use(rewrite);
    },
    configurePreviewServer(server) {
      server.middlewares.use(rewrite);
    },
  };
}

/**
 * The service worker, built last (once everything else is written): src/sw/sw.ts in one plain
 * script, /sw.js, with this version's files and a version number made from them written in, and
 * whether it may ask the shop's server for its catalog (never in the demo, which has no /api).
 * Files under /assets/ change their names when they change; every other file (the page, the
 * icons, the manifest, the offline page) is listed with a hash of what's in it and of the
 * hosting settings (`hosting`, the vercel.json the build is served with), so new headers make
 * a new version too (tools/precache.ts).
 */
function serviceWorker({ api, hosting }: { api: boolean; hosting: string }): Plugin {
  return {
    name: 'izzy-service-worker',
    apply: 'build',
    async writeBundle(options) {
      const outDir = options.dir;
      if (!outDir) throw new Error('The service worker needs the build folder');
      const entries = precacheEntries(outDir, readFileSync(hosting, 'utf8'));
      const version = precacheVersion(entries);
      const built = await viteBuild({
        configFile: false,
        envFile: false,
        publicDir: false,
        logLevel: 'warn',
        define: { __PRECACHE__: JSON.stringify(entries), __VERSION__: JSON.stringify(version), __API__: JSON.stringify(api) },
        build: {
          write: false,
          minify: true,
          target: 'es2020',
          reportCompressedSize: false,
          lib: { entry: here('./src/sw/sw.ts'), formats: ['iife'], name: 'izzyServiceWorker', fileName: () => 'sw.js' },
        },
      });
      const outputs = (Array.isArray(built) ? built : [built]) as Rollup.RollupOutput[];
      const chunk = outputs.flatMap((output) => output.output).find((item): item is Rollup.OutputChunk => item.type === 'chunk');
      if (!chunk) throw new Error('The service worker didn’t build');
      writeFileSync(join(outDir, 'sw.js'), chunk.code);
    },
  };
}

/**
 * The shop's legal documents, which the legal pages render (src/legal/texts.ts). A strict build
 * (tools/legal.ts) publishes them as they are, so it stops, saying which file and line, while
 * any "[TO FILL IN: …]" is left in them. Every other build is a draft.
 */
const LEGAL_DIR = here('../../docs/legal');

/**
 * The demo's robots.txt. Search engines may read its pages, which all answer with
 * X-Robots-Tag: noindex, so none is listed: a page they weren't allowed to read could still be
 * listed from links elsewhere, since they'd never see its noindex.
 */
const DEMO_ROBOTS = `# The demo version of the Izzy Clipz website, not the shop's own site.
# Every page answers with X-Robots-Tag: noindex (vercel.json), so none of it is listed in
# search results. Reading stays allowed, so search engines see that noindex.
User-agent: *
Allow: /
`;

/** The demo's hosting settings (this folder's vercel.json, which Vercel also reads when it builds the demo from Git) as dist-demo/vercel.json, and its own robots.txt. */
function demoHosting(): Plugin {
  return {
    name: 'izzy-demo-hosting',
    apply: 'build',
    generateBundle() {
      this.emitFile({ type: 'asset', fileName: 'vercel.json', source: readFileSync(here('./vercel.json'), 'utf8') });
    },
    writeBundle(options) {
      // public/robots.txt is the shop's own site's; the demo's replaces it.
      if (options.dir) writeFileSync(join(options.dir, 'robots.txt'), DEMO_ROBOTS);
    },
  };
}

export default defineConfig(({ mode }) => {
  // `--mode demo` and VITE_DEMO_MODE=1 both make the demo; the site reads it as import.meta.env.VITE_DEMO_MODE.
  if (mode === 'demo') process.env.VITE_DEMO_MODE = '1';
  const demo = process.env.VITE_DEMO_MODE === '1';
  // The legal pages are drafts unless the build is strict; the site reads it as import.meta.env.VITE_LEGAL_STRICT.
  const strict = legalStrict(process.env, demo);
  process.env.VITE_LEGAL_STRICT = strict ? '1' : '';
  // The demo has no API to reach: it answers in the browser.
  const proxy: Record<string, string> = demo ? {} : { '/api': API_DEV_SERVER };
  return {
    plugins: [
      react(),
      legalDocuments({ strict, dir: LEGAL_DIR }),
      absoluteSocialLinks(),
      businessPages(),
      ...(demo ? [demoBackend(), demoHosting()] : []),
      serviceWorker({ api: !demo, hosting: here(demo ? './vercel.json' : '../vercel.json') }),
    ],
    build: {
      outDir: demo ? 'dist-demo' : '../public',
      // ../public is outside this folder, so Vite only clears it when asked.
      emptyOutDir: true,
      rollupOptions: {
        // Two pages: the site's, and Izzy Clipz Business's (/business/), each linking its own
        // manifest and icons. They share one script; Business's own code loads when it's opened.
        input: { main: here('./index.html'), business: here('./business/index.html') },
      },
    },
    server: {
      proxy,
      // The demo reads the shop's catalog from the server's own data/catalog.json, and the legal
      // pages the shop's documents from docs/legal.
      fs: { allow: ['.', '../data', '../../docs/legal'] },
    },
    preview: { proxy },
    test: {
      environment: 'jsdom',
      // tools/: the build's own helpers, which run in Node (their tests say so).
      include: ['src/**/*.test.{ts,tsx}', 'tools/**/*.test.ts'],
      setupFiles: ['src/test/setup.ts'],
      restoreMocks: true,
      unstubGlobals: true,
      unstubEnvs: true,
    },
  };
});
