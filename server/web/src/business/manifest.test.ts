import { renderHook } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';
import businessHtml from '../../business/index.html?raw';
import manifestText from '../../public/business/manifest.webmanifest?raw';
import siteManifestText from '../../public/manifest.webmanifest?raw';
import { useBusinessHead } from './hooks';

// Izzy Clipz Business installs as an app of its own: its own manifest (scope /business/,
// opening on Today), its own icons (the Business app's: the logo on black with the red
// "Business" pill), and its own page, which links them instead of the clients' ones. The
// end-to-end tests check that Chrome finds nothing missing to install it, and the icons' sizes.

interface ManifestIcon {
  src: string;
  sizes: string;
  type: string;
  purpose: string;
}

const manifest = JSON.parse(manifestText) as Record<string, unknown> & { icons: ManifestIcon[] };
const site = JSON.parse(siteManifestText) as Record<string, unknown>;

describe('Izzy Clipz Business’s manifest', () => {
  it('is an app of its own, for /business/, opening on Today', () => {
    expect(manifest).toMatchObject({
      id: '/business/',
      name: 'Izzy Clipz Business',
      short_name: 'IC Business',
      start_url: '/business/today?source=app',
      scope: '/business/',
      display: 'standalone',
      background_color: '#000000',
      theme_color: '#000000',
    });
    expect(manifest.description).toMatch(/.{40,}\.$/);
    // Not the clients' app: another id and scope, so both can be installed side by side.
    expect(manifest.id).not.toBe(site.id);
    // Used on computers and tablets too, so it turns with the screen.
    expect(manifest).not.toHaveProperty('orientation');
    expect(manifest).not.toHaveProperty('prefer_related_applications');
  });

  it('has the Business icon at 192 and 512 pixels, and a 512 one with room for Android to crop', () => {
    expect(manifest.icons).toEqual([
      { src: '/business/icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
      { src: '/business/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
      { src: '/business/icon-maskable-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
    ]);
  });
});

describe('Izzy Clipz Business’s page', () => {
  const head = new DOMParser().parseFromString(businessHtml, 'text/html').head;
  const meta = (name: string) => head.querySelector(`meta[name="${name}"]`)?.getAttribute('content');

  it('links its own manifest and iPhone icon, not the clients’', () => {
    expect(head.querySelector('link[rel="manifest"]')?.getAttribute('href')).toBe('/business/manifest.webmanifest');
    const touchIcon = head.querySelector('link[rel="apple-touch-icon"]');
    expect(touchIcon?.getAttribute('href')).toBe('/business/apple-touch-icon.png');
    expect(touchIcon?.getAttribute('sizes')).toBe('180x180');
  });

  it('opens full screen as IC Business, under a black bar, and isn’t listed by search engines', () => {
    expect(meta('apple-mobile-web-app-capable')).toBe('yes');
    expect(meta('mobile-web-app-capable')).toBe('yes');
    expect(meta('apple-mobile-web-app-status-bar-style')).toBe('black');
    expect(meta('apple-mobile-web-app-title')).toBe('IC Business');
    expect(meta('theme-color')).toBe('#000000');
    expect(meta('robots')).toBe('noindex');
    expect(meta('viewport')).toContain('viewport-fit=cover');
    expect(head.querySelector('title')?.textContent).toBe('Izzy Clipz Business');
  });

  it('runs the same script as the site', () => {
    expect(businessHtml).toContain('<script type="module" src="/src/main.tsx"></script>');
  });
});

describe('Izzy Clipz Business drawn in a clients’ page, without a page load', () => {
  // The clients' footer opens Business as a page of its own, but should the site's router ever
  // draw it in a clients' page (Back and Forward within one page, say), it still installs as
  // Izzy Clipz Business, and the site's own manifest and icon come back once it's left.
  const head = (selector: string, attribute: string) => document.head.querySelector(selector)?.getAttribute(attribute) ?? null;
  afterEach(() => {
    document.head.innerHTML = '';
  });

  it('puts its own manifest, icon, name and "noindex" in place, and the site’s back when it’s left', () => {
    document.head.innerHTML =
      '<link rel="manifest" href="/manifest.webmanifest"><link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png"><meta name="apple-mobile-web-app-title" content="Izzy Clipz">';
    const { unmount } = renderHook(() => useBusinessHead());
    expect(head('link[rel="manifest"]', 'href')).toBe('/business/manifest.webmanifest');
    expect(head('link[rel="apple-touch-icon"]', 'href')).toBe('/business/apple-touch-icon.png');
    expect(head('meta[name="apple-mobile-web-app-title"]', 'content')).toBe('IC Business');
    expect(head('meta[name="robots"]', 'content')).toBe('noindex');
    unmount();
    expect(head('link[rel="manifest"]', 'href')).toBe('/manifest.webmanifest');
    expect(head('link[rel="apple-touch-icon"]', 'href')).toBe('/apple-touch-icon.png');
    expect(head('meta[name="apple-mobile-web-app-title"]', 'content')).toBe('Izzy Clipz');
    // The clients' pages are for search results: no "noindex" left behind.
    expect(document.head.querySelector('meta[name="robots"]')).toBeNull();
  });
});
