import react from '@vitejs/plugin-react';
import type { Plugin } from 'vite';
import { defineConfig } from 'vitest/config';

// The website builds into ../public, which Vercel serves next to the API (one
// project, one origin). In development, `npm run dev` here proxies /api to the
// API's own dev server (`npm run dev` in server/, http://localhost:3000).

const API_DEV_SERVER = 'http://localhost:3000';

/**
 * The site's public address, for the few links that must be absolute in the
 * HTML itself (the Open Graph image that link previews show). It's the API's
 * PUBLIC_BASE_URL, since the site and the API share one origin. Unset: the
 * links stay relative.
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
      return origin ? html.replaceAll('content="/og-image.jpg"', `content="${origin}/og-image.jpg"`) : html;
    },
  };
}

export default defineConfig({
  plugins: [react(), absoluteSocialLinks()],
  build: {
    outDir: '../public',
    // ../public is outside this folder, so Vite only clears it when asked.
    emptyOutDir: true,
  },
  server: {
    proxy: { '/api': API_DEV_SERVER },
  },
  preview: {
    proxy: { '/api': API_DEV_SERVER },
  },
  test: {
    environment: 'jsdom',
    include: ['src/**/*.test.{ts,tsx}'],
    setupFiles: ['src/test/setup.ts'],
    restoreMocks: true,
    unstubGlobals: true,
  },
});
