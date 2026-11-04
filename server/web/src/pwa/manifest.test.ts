import { describe, expect, it } from 'vitest';
import indexHtml from '../../index.html?raw';
import manifestText from '../../public/manifest.webmanifest?raw';

// What makes the site installable: the web app manifest (Chrome, Edge and Android read it)
// and the tags iPhones read when it's added to the Home Screen. The end-to-end tests check
// that the browser itself finds nothing missing, and that every icon is the size it says.

interface ManifestIcon {
  src: string;
  sizes: string;
  type: string;
  purpose: string;
}

const manifest = JSON.parse(manifestText) as Record<string, unknown> & { icons: ManifestIcon[] };

describe('the web app manifest', () => {
  it('names the app and opens it full screen from the start page, with the whole site in scope', () => {
    expect(manifest).toMatchObject({
      id: '/',
      name: 'Izzy Clipz',
      short_name: 'Izzy Clipz',
      start_url: '/?source=app',
      scope: '/',
      display: 'standalone',
      orientation: 'portrait',
      background_color: '#000000',
      theme_color: '#000000',
    });
    expect(manifest.description).toMatch(/^Book .{40,}\.$/);
    // Android would send people to an app store instead of installing this.
    expect(manifest).not.toHaveProperty('prefer_related_applications');
  });

  it('has the logo on black at 192 and 512 pixels, and a 512 one Android may crop to a circle', () => {
    expect(manifest.icons).toEqual([
      { src: '/icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
      { src: '/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
      { src: '/icon-maskable-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
    ]);
  });
});

describe('the page’s tags for Home Screens', () => {
  const head = new DOMParser().parseFromString(indexHtml, 'text/html').head;
  const meta = (name: string) => head.querySelector(`meta[name="${name}"]`)?.getAttribute('content');

  it('links the manifest and the 180-pixel iPhone icon', () => {
    expect(head.querySelector('link[rel="manifest"]')?.getAttribute('href')).toBe('/manifest.webmanifest');
    const touchIcon = head.querySelector('link[rel="apple-touch-icon"]');
    expect(touchIcon?.getAttribute('href')).toBe('/apple-touch-icon.png');
    expect(touchIcon?.getAttribute('sizes')).toBe('180x180');
  });

  it('opens full screen on iPhones and Android, under a black status bar, named Izzy Clipz', () => {
    expect(meta('apple-mobile-web-app-capable')).toBe('yes');
    expect(meta('mobile-web-app-capable')).toBe('yes');
    expect(meta('apple-mobile-web-app-status-bar-style')).toBe('black');
    expect(meta('apple-mobile-web-app-title')).toBe('Izzy Clipz');
    expect(meta('theme-color')).toBe('#000000');
  });

  it('lets the page reach the screen’s edges, so the safe-area padding keeps it clear of the notch and home bar', () => {
    expect(meta('viewport')).toContain('viewport-fit=cover');
  });
});
