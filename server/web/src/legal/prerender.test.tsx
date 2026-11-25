// @vitest-environment node
import { describe, expect, it } from 'vitest';
import catalogData from '../../../data/catalog.json';
import { MENU_BUTTON_ID, NOT_IN_APP } from '../components/Layout';
import { LEGAL_DOCUMENTS } from './documents';
import { DEMO_DRAFT_LINE, DRAFT_LINE, DRAFT_TITLE } from './LegalPage';
import { PLACEHOLDER_START } from './placeholders';
import { renderLegalPages } from './prerender';

// The legal pages as the build writes them in plain HTML (tools/prerender.ts): in Node, with no
// browser, the pages' own article under a nav and footer that need no script.

/** The page's text, without its markup. */
function textOf(html: string): string {
  return html
    .replace(/<[^>]+>/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#x27;/g, "'")
    .replace(/\s+/g, ' ');
}

describe('the legal pages in plain HTML', () => {
  it('are the four documents, each with its title as its one main heading, its sections and its words, as a draft', () => {
    const pages = renderLegalPages({ draft: true, demo: false });
    expect(pages.map((page) => [page.path, page.file])).toEqual(LEGAL_DOCUMENTS.map((document) => [document.path, `${document.id}/index.html`]));
    for (const [index, page] of pages.entries()) {
      const document = LEGAL_DOCUMENTS[index]!;
      expect(page.title).toBe(`${document.title} · Izzy Clipz Barbershop`);
      expect(page.description).toBe(document.description);
      expect(page.body.match(/<h1[\s>]/g), page.path).toHaveLength(1);
      expect(page.body, page.path).toMatch(/<h2 id="[a-z0-9-]+" class="legal__h2" tabindex="-1">/);
      const text = textOf(page.body);
      expect(text, page.path).toContain(`${DRAFT_TITLE} ${DRAFT_LINE}`);
      expect(text, page.path).not.toContain(DEMO_DRAFT_LINE);
      expect(text, page.path).toContain('Effective date: Not in effect yet');
      // Every placeholder shows as a note, never as written.
      expect(page.body, page.path).not.toContain(PLACEHOLDER_START);
      expect(page.body, page.path).not.toContain('OWNER-CHECKLIST');
    }
    const privacy = textOf(pages[0]!.body);
    expect(privacy).toContain('Privacy Policy');
    expect(privacy).toContain('This policy explains what information Izzy Clipz Barbershop');
  });

  it('says it’s the demo in the demo’s draft, and has no draft note once the shop publishes them', () => {
    const [demo] = renderLegalPages({ draft: true, demo: true });
    expect(textOf(demo!.body)).toContain(`${DRAFT_TITLE} ${DRAFT_LINE} ${DEMO_DRAFT_LINE}`);
    const [published] = renderLegalPages({ draft: false, demo: false });
    expect(published!.body).not.toContain('data-testid="legal-draft"');
  });

  it('link the other documents, the shop’s number and the site with plain links, under a nav and footer with no script', () => {
    const page = renderLegalPages({ draft: true, demo: false }).find((p) => p.path === '/cancellation-policy')!;
    expect(page.body).toContain('href="/privacy"');
    expect(page.body).toContain('href="/terms"');
    expect(page.body).toContain('href="tel:+14423413053"');
    expect(page.body).toMatch(/^<a class="skip-link" href="#main">Skip to main content<\/a><nav class="globalnav" aria-label="Izzy Clipz">/);
    expect(page.body).toContain('<a class="globalnav__logo" href="/">');
    // No menu button: it needs the script.
    expect(page.body).not.toContain('globalnav__menu-button');
    expect(page.body).toContain('<main id="main" tabindex="-1" data-prerendered="">');
    expect(page.body).toContain('<nav class="globalfooter__policies" aria-label="Legal">');
    expect(page.body).not.toContain('<script');
  });

  it('draw the site’s own nav bar, so nothing in it moves when the site takes over: Book with its pill, and “Menu” going to the footer’s site directory', () => {
    for (const page of renderLegalPages({ draft: true, demo: false })) {
      const nav = page.body.slice(0, page.body.indexOf('</nav>')).replace(/<svg[\s\S]*?<\/svg>/g, '<svg/>');
      // The logo home, the site's pages (shown on a computer), Book, and the Menu stand-in (shown on a phone), in GlobalNav's order.
      expect(nav, page.path).toMatch(
        /<a class="globalnav__logo" href="\/">.*<ul class="globalnav__links">.*<\/ul><a class="globalnav__book" aria-label="Book an appointment" href="\/book"><span class="globalnav__book-pill" aria-hidden="true">Book<\/span><\/a><a id="globalnav-menu-button" href="#site-directory" class="globalnav__menu-standin"/,
      );
      // "Menu" works without the script: it goes to the footer's site directory, which says where it goes.
      // It has the site's Menu button's id, so the keyboard on it is on that button once the site takes over.
      expect(MENU_BUTTON_ID).toBe('globalnav-menu-button');
      expect(nav, page.path).toContain(
        '<a id="globalnav-menu-button" href="#site-directory" class="globalnav__menu-standin" aria-label="Menu: the site&#x27;s pages, at the bottom of this page"><svg/><span>Menu</span></a>',
      );
      expect(page.body, page.path).toContain('<nav id="site-directory" class="globalfooter__directory" aria-label="Site directory">');
    }
  });

  it('have “Get the app” in the nav and the footer as the site does, marked for the styles to hide when it’s open as the app', () => {
    for (const page of renderLegalPages({ draft: true, demo: false })) {
      const [nav, rest] = [page.body.slice(0, page.body.indexOf('</nav>')), page.body.slice(page.body.indexOf('<footer'))];
      expect(nav, page.path).toContain(`<li class="${NOT_IN_APP}"><a class="globalnav__link" href="/app">Get the app</a></li>`);
      expect(rest, page.path).toContain(`<li class="${NOT_IN_APP}"><a href="/app">Get the app</a></li>`);
      // Only it: every other page in the nav stays.
      expect(page.body.match(new RegExp(`class="${NOT_IN_APP}"`, 'g')), page.path).toHaveLength(2);
      // No Back: the site draws none over the plain HTML either (components/Layout.tsx).
      expect(page.body, page.path).not.toContain('globalnav__back');
    }
  });

  it('carry the catalog they were drawn with, the build’s, for the site’s first draw over them', () => {
    for (const page of renderLegalPages({ draft: true, demo: false })) expect(page.catalog, page.path).toEqual(catalogData);
  });

  it('give the shop’s hours and who runs the shop in the footer, from the catalog the build serves', () => {
    for (const page of renderLegalPages({ draft: true, demo: false })) {
      const text = textOf(page.body);
      // Without JavaScript too: the Accessibility Statement asks people to call "during opening hours".
      expect(page.body, page.path).toContain('class="globalfooter__list globalfooter__hours" aria-label="Hours"');
      expect(text, page.path).toContain('Monday–Saturday: 10 AM – 7 PM');
      expect(text, page.path).toContain('Sunday: 10 AM – 6 PM');
      // Who runs the shop and where (the LLC's name and the shop's email aren't given yet: only what
      // exists, the shop and its address), and the refund policy next to the Cancellation & No-Show Policy.
      expect(page.body, page.path).toContain('data-testid="footer-operator"');
      const footer = textOf(page.body.slice(page.body.indexOf('<footer')));
      expect(footer, page.path).toContain('Izzy Clipz Barbershop, 1919 Mission Ave, Ste 105, Oceanside, CA 92058, United States.');
      expect(footer, page.path).not.toMatch(/operated by|To be added|To get this information by email/);
      expect(page.body, page.path).toContain('<a href="/cancellation-policy">Cancellation &amp; No-Show Policy</a></li><li><a href="/terms#refunds">Refunds</a>');
    }
  });
});
