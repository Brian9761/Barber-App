// @vitest-environment node
import { describe, expect, it } from 'vitest';
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
});
