// @vitest-environment node
import { describe, expect, it } from 'vitest';
import { BUILD_CATALOG_ID } from '../src/legal/takeover.js';
import { jsonDataBlock, LEGAL_PAGE_FILES, legalPageHtml, SKIP_LINK, type LegalPageContent } from './prerender.js';

// The legal pages' plain HTML, made from the built index.html: their own title and description,
// their markup in #root, the legal pages' styles and script linked, and nothing else changed.

const BUILT = `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>Izzy Clipz Barbershop in Oceanside</title>
    <meta name="description" content="Izzy Clipz Barbershop in Oceanside. Pick your barber and a time online, and pay at the shop." />
    <meta property="og:title" content="Izzy Clipz Barbershop in Oceanside" />
    <meta property="og:description" content="Pick your barber and a time online, and pay at the shop." />
    <script type="module" crossorigin src="/assets/main-abc.js"></script>
    <link rel="stylesheet" crossorigin href="/assets/main-abc.css">
  </head>
  <body>
    <noscript><div data-testid="noscript">This website needs JavaScript…</div></noscript>
    <div id="root"></div>
  </body>
</html>
`;

const PAGE: LegalPageContent = {
  path: '/cancellation-policy',
  file: 'cancellation-policy/index.html',
  title: 'Cancellation & No-Show Policy · Izzy Clipz Barbershop',
  description: 'How to cancel an appointment at Izzy Clipz Barbershop, and when a fee may be charged for cancelling late or not coming.',
  body: '<main id="main"><h1>Cancellation &amp; No-Show Policy</h1><p>A late cancellation may be charged $35, or $& of it.</p></main>',
};

const EXTRAS = { stylesheets: ['/assets/LegalPage-x.css'], preloads: ['/assets/LegalPage-y.js'], origin: '' };

describe('a legal page’s plain HTML', () => {
  it('has the page’s own title and description, also for link previews, escaped', () => {
    const html = legalPageHtml(BUILT, PAGE, EXTRAS);
    expect(html).toContain('<title>Cancellation &amp; No-Show Policy · Izzy Clipz Barbershop</title>');
    expect(html).toContain(`<meta name="description" content="${PAGE.description}" />`);
    expect(html).toContain('<meta property="og:title" content="Cancellation &amp; No-Show Policy · Izzy Clipz Barbershop" />');
    expect(html).toContain(`<meta property="og:description" content="${PAGE.description}" />`);
    expect(html).not.toContain('Izzy Clipz Barbershop in Oceanside');
  });

  it('has its words in #root, as they are (a "$" stays a "$"), after the note for browsers without JavaScript', () => {
    const html = legalPageHtml(BUILT, PAGE, EXTRAS);
    expect(html).toContain(`<div id="root">${PAGE.body}</div>`);
    expect(html).toContain('may be charged $35, or $& of it.');
    expect(html.indexOf('data-testid="noscript"')).toBeLessThan(html.indexOf('<div id="root">'));
  });

  it('keeps the site’s script, so the site takes over, and links the legal pages’ own styles and script', () => {
    const html = legalPageHtml(BUILT, PAGE, EXTRAS);
    expect(html).toContain('<script type="module" crossorigin src="/assets/main-abc.js"></script>');
    expect(html).toContain('<link rel="stylesheet" crossorigin href="/assets/main-abc.css">');
    const head = html.slice(0, html.indexOf('</head>'));
    expect(head).toContain('<link rel="stylesheet" crossorigin href="/assets/LegalPage-x.css">');
    expect(head).toContain('<link rel="modulepreload" crossorigin href="/assets/LegalPage-y.js">');
    expect(head).not.toContain('rel="canonical"');
  });

  it('carries the catalog it was drawn with right after #root, as data the browser never runs, for the site’s first draw over it', () => {
    const catalog = { shop: { name: 'Izzy Clipz', note: 'Walk-ins </script><script>alert(1)</script> & <!-- welcome -->' }, hours: { '2': { opens: '10:00', closes: '19:00' } } };
    const html = legalPageHtml(BUILT, { ...PAGE, catalog }, EXTRAS);
    const block = jsonDataBlock(BUILD_CATALOG_ID, catalog);
    expect(block.startsWith(`<script type="application/json" id="${BUILD_CATALOG_ID}">`)).toBe(true);
    expect(html).toContain(`<div id="root">${PAGE.body}</div>${block}`);
    // Nothing in it can end the element or open a comment: no "<" at all, and it reads back as it was.
    const json = block.slice(block.indexOf('>') + 1, block.lastIndexOf('</script>'));
    expect(json).not.toContain('<');
    expect(JSON.parse(json)).toEqual(catalog);
    expect(html.match(/<\/script>/g)).toHaveLength(2);
    // Without one, there's nothing after #root.
    expect(legalPageHtml(BUILT, PAGE, EXTRAS)).toContain(`<div id="root">${PAGE.body}</div>\n`);
    expect(legalPageHtml(BUILT, PAGE, EXTRAS)).not.toContain(BUILD_CATALOG_ID);
  });

  it('starts, without JavaScript, with “Skip to main content”, before the note for browsers without it, as the page’s own link', () => {
    const html = legalPageHtml(BUILT, PAGE, EXTRAS);
    expect(html).toContain(`<noscript>${SKIP_LINK}<div data-testid="noscript">`);
    expect(html.indexOf(SKIP_LINK)).toBeLessThan(html.indexOf('data-testid="noscript"'));
    // The same link the page draws first, to the same place (src/legal/prerender.test.tsx checks the page's).
    expect(SKIP_LINK).toBe('<a class="skip-link" href="#main">Skip to main content</a>');
    expect(() => legalPageHtml(BUILT.replace(/<\/?noscript>/g, ''), PAGE, EXTRAS)).toThrow('has no <noscript>');
  });

  it('names its address when the site’s is known', () => {
    const html = legalPageHtml(BUILT, PAGE, { ...EXTRAS, origin: 'https://izzy-clipz.example' });
    expect(html).toContain('<link rel="canonical" href="https://izzy-clipz.example/cancellation-policy">');
  });

  it('stops, saying what’s missing, when the built page changed shape', () => {
    expect(() => legalPageHtml(BUILT.replace('<div id="root"></div>', '<div id="app"></div>'), PAGE, EXTRAS)).toThrow(
      'The built index.html has no empty <div id="root">, so cancellation-policy/index.html can\'t be made from it.',
    );
    expect(() => legalPageHtml(BUILT.replace(/<title>.*<\/title>/, ''), PAGE, EXTRAS)).toThrow('has no <title>');
  });

  it('are the four documents, each at its own address', () => {
    expect(LEGAL_PAGE_FILES).toEqual(['privacy/index.html', 'terms/index.html', 'cancellation-policy/index.html', 'accessibility/index.html']);
  });
});
