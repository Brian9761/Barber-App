// @vitest-environment node
import { describe, expect, it } from 'vitest';
import { LEGAL_PAGE_FILES, legalPageHtml, type LegalPageContent } from './prerender.js';

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
