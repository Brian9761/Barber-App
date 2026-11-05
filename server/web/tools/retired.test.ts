// @vitest-environment node
import { describe, expect, it } from 'vitest';
import { movedToOrigin, retiredFiles } from './retired.js';

// The retired demo: what takes the demo's place at its address once the real site is live
// somewhere else.

const PHONE = { display: '(442) 341-3053', e164: '+14423413053' };

describe('the retired demo', () => {
  it('needs the real site’s https address', () => {
    expect(movedToOrigin('https://izzyclipz.example/')).toBe('https://izzyclipz.example');
    expect(movedToOrigin(' https://izzy-clipz-api.vercel.app/app?x=1 ')).toBe('https://izzy-clipz-api.vercel.app');
    expect(() => movedToOrigin(undefined)).toThrow('DEMO_MOVED_TO=https://');
    expect(() => movedToOrigin('')).toThrow('DEMO_MOVED_TO=https://');
    expect(() => movedToOrigin('izzyclipz.example')).toThrow("isn't a web address");
    expect(() => movedToOrigin('http://izzyclipz.example')).toThrow('must start with https://');
    expect(() => movedToOrigin('javascript:alert(1)')).toThrow('must start with https://');
    expect(() => movedToOrigin('https://user:secret@izzyclipz.example')).toThrow('must start with https://');
  });

  it('shows one page everywhere: where Izzy Clipz is now, a button to get the new app, and the phone number', () => {
    const files = retiredFiles('https://izzyclipz.example', PHONE);
    const page = files['index.html']!;
    expect(page).toContain('<h1>Izzy Clipz has moved.</h1>');
    expect(page).toContain('<strong>izzyclipz.example</strong>');
    expect(page).toContain('<a class="button" href="https://izzyclipz.example/app">Get the new app</a>');
    expect(page).toContain('<a href="tel:+14423413053">(442) 341-3053</a>');
    // The real site's Privacy Policy, from every address the old demo had.
    expect(page).toContain('<p class="legal"><a href="https://izzyclipz.example/privacy">Privacy Policy</a></p>');
    expect(page).toContain('<meta name="robots" content="noindex" />');
    // No script but its own file, which the page's policy allows.
    expect(page.match(/<script/g)).toHaveLength(1);
    expect(page).toContain('<script src="/moved.js"></script>');
    const hosting = JSON.parse(files['vercel.json']!) as { rewrites: { source: string; destination: string }[]; headers: { source: string; headers: { key: string; value: string }[] }[] };
    expect(hosting.rewrites).toEqual([{ source: '/((?!assets/).*)', destination: '/index.html' }]);
    const all = Object.fromEntries(hosting.headers.find((rule) => rule.source === '/(.*)')!.headers.map((h) => [h.key, h.value]));
    expect(all['x-robots-tag']).toBe('noindex');
    expect(all['content-security-policy']).toContain("script-src 'self'");
    expect(hosting.headers.find((rule) => rule.source === '/sw.js')!.headers).toContainEqual({ key: 'cache-control', value: 'no-cache' });
  });

  it('takes the demo worker’s place at once, clears its files, steps aside and reloads its pages', () => {
    const worker = retiredFiles('https://izzyclipz.example', PHONE)['sw.js']!;
    expect(worker).toContain('self.skipWaiting()');
    expect(worker).toContain('caches.delete(name)');
    expect(worker).toContain('self.registration.unregister()');
    expect(worker).toContain('page.navigate(page.url)');
    // It answers no requests itself: the reloaded pages come from the network.
    expect(worker).not.toContain("addEventListener('fetch'");
    const cleanup = retiredFiles('https://izzyclipz.example', PHONE)['moved.js']!;
    expect(cleanup).toContain('localStorage.clear()');
    expect(cleanup).toContain('r.unregister()');
  });
});
