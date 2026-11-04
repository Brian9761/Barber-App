import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import react from '@vitejs/plugin-react';
import type { Plugin } from 'vite';
import { defineConfig } from 'vitest/config';

// The website builds into ../public, which Vercel serves next to the API (one
// project, one origin). In development, `npm run dev` here proxies /api to the
// API's own dev server (`npm run dev` in server/, http://localhost:3000).
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
    plugins: [react(), absoluteSocialLinks(), ...(demo ? [demoBackend(), demoHosting()] : [])],
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
