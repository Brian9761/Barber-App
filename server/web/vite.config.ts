import { createHash } from 'node:crypto';
import { readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import react from '@vitejs/plugin-react';
import { build as viteBuild, type Plugin, type Rollup } from 'vite';
import { defineConfig } from 'vitest/config';

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
 * src/api/backend.ts (the shop's server, over the network), it gets src/demo/backend.ts. So the
 * demo has no code that calls /api, and the normal build has none of the demo's.
 */
function demoBackend(): Plugin {
  const real = here('./src/api/backend.ts');
  const demo = here('./src/demo/backend.ts');
  return {
    name: 'izzy-demo-backend',
    enforce: 'pre',
    async resolveId(source, importer, options) {
      if (!/(^|\/)backend(\.ts)?$/.test(source)) return null;
      const resolved = await this.resolve(source, importer, { ...options, skipSelf: true });
      return resolved?.id === real ? demo : null;
    },
  };
}

/**
 * Files the service worker doesn't keep: the picture link previews show, the file for search
 * engines, the hosting settings and the worker itself; and Inter's alphabets other than Latin,
 * which the site's own words never use (a browser downloads them only if a page needs them).
 */
function precached(name: string): boolean {
  if (['og-image.png', 'robots.txt', 'vercel.json', 'sw.js'].includes(name) || name.endsWith('.map')) return false;
  return !/^assets\/inter-(?!latin)/.test(name);
}

function sha256(content: string | Buffer): string {
  return createHash('sha256').update(content).digest('hex');
}

/** Every file of the build, by its address: "/index.html", "/assets/index-DN70w0ok.js". */
function builtFiles(outDir: string): string[] {
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

/**
 * The service worker, built last (once everything else is written): src/sw/sw.ts in one plain
 * script, /sw.js, with this version's files and a version number made from them written in, and
 * whether it may ask the shop's server for its catalog (never in the demo, which has no /api).
 * Files under /assets/ change their names when they change; every other file (the page, the
 * icons, the manifest, the offline page) is listed with a hash of what's in it.
 */
function serviceWorker({ api }: { api: boolean }): Plugin {
  return {
    name: 'izzy-service-worker',
    apply: 'build',
    async writeBundle(options) {
      const outDir = options.dir;
      if (!outDir) throw new Error('The service worker needs the build folder');
      const entries = builtFiles(outDir)
        .filter(precached)
        .map((name) => ({ url: `/${name}`, revision: name.startsWith('assets/') ? null : sha256(readFileSync(join(outDir, name))).slice(0, 16) }));
      const version = sha256(JSON.stringify(entries)).slice(0, 12);
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

/** The demo's hosting settings (vercel.demo.json), as dist-demo/vercel.json. */
function demoHosting(): Plugin {
  return {
    name: 'izzy-demo-hosting',
    apply: 'build',
    generateBundle() {
      this.emitFile({ type: 'asset', fileName: 'vercel.json', source: readFileSync(here('./vercel.demo.json'), 'utf8') });
    },
  };
}

export default defineConfig(({ mode }) => {
  // `--mode demo` and VITE_DEMO_MODE=1 both make the demo; the site reads it as import.meta.env.VITE_DEMO_MODE.
  if (mode === 'demo') process.env.VITE_DEMO_MODE = '1';
  const demo = process.env.VITE_DEMO_MODE === '1';
  // The demo has no API to reach: it answers in the browser.
  const proxy: Record<string, string> = demo ? {} : { '/api': API_DEV_SERVER };
  return {
    plugins: [react(), absoluteSocialLinks(), ...(demo ? [demoBackend(), demoHosting()] : []), serviceWorker({ api: !demo })],
    build: {
      outDir: demo ? 'dist-demo' : '../public',
      // ../public is outside this folder, so Vite only clears it when asked.
      emptyOutDir: true,
    },
    server: {
      proxy,
      // The demo reads the shop's catalog from the server's own data/catalog.json.
      fs: { allow: ['.', '../data'] },
    },
    preview: { proxy },
    test: {
      environment: 'jsdom',
      include: ['src/**/*.test.{ts,tsx}'],
      setupFiles: ['src/test/setup.ts'],
      restoreMocks: true,
      unstubGlobals: true,
      unstubEnvs: true,
    },
  };
});
