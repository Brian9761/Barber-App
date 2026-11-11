import { render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { describe, expect, it, vi } from 'vitest';
import { ROUTER_FUTURE } from '../App';
import { renderApp } from '../test/api';
import type { LegalDocumentId } from './documents';
import { LegalArticle, numberHref } from './LegalPage';
import { legalDraft } from './mode';
import { LEGAL_TEXTS } from './texts';

// The four legal pages, drawn from docs/legal: as drafts (every build but a strict one), with the
// note at the top, "Not in effect yet" for their dates and each placeholder as a note; and as the
// shop publishes them (a strict build, only once nothing is left to fill in).

/** A document as docs/legal has it ("privacy.md"), as the site builds it in. */
const read = (file: string) => LEGAL_TEXTS[file.replace(/\.md$/, '') as LegalDocumentId];

/** A document as the shop might finish it. */
function filledIn(text: string): string {
  return text.replace(/\[TO FILL IN:([^\]]*)\]/g, (_, what: string) => {
    if (/email/.test(what)) return 'hello@izzyclipz.example';
    if (/\bday\b/.test(what)) return 'December 1, 2026';
    return '';
  });
}

const PAGES = [
  ['/privacy', 'Privacy Policy', 'Privacy Policy · Izzy Clipz Barbershop'],
  ['/terms', 'Terms of Service', 'Terms of Service · Izzy Clipz Barbershop'],
  ['/cancellation-policy', 'Cancellation & No-Show Policy', 'Cancellation & No-Show Policy · Izzy Clipz Barbershop'],
  ['/accessibility', 'Accessibility Statement', 'Accessibility · Izzy Clipz Barbershop'],
] as const;

const main = () => within(screen.queryByRole('main') ?? screen.getByTestId('legal-page'));

/** A document's page from Markdown of the test's own, as a draft or as published. */
const renderArticle = (source: string, draft: boolean) =>
  render(
    <MemoryRouter future={ROUTER_FUTURE}>
      <LegalArticle source={source} draft={draft} demo={false} />
    </MemoryRouter>,
  );

describe('the legal pages, as drafts', () => {
  it.each(PAGES)('%s: one main heading, its title, the draft note, and no placeholder or checklist left in its words', async (path, heading, title) => {
    renderApp(path);
    expect((await screen.findByRole('heading', { level: 1 })).textContent).toBe(heading);
    expect(screen.getAllByRole('heading', { level: 1 })).toHaveLength(1);
    await waitFor(() => expect(document.title).toBe(title));
    const note = screen.getByTestId('legal-draft');
    expect(note.textContent).toBe('Draft: not in effect yet.The shop will publish this when online booking opens.');
    // The note comes first, then the title.
    expect(note.compareDocumentPosition(screen.getByRole('heading', { level: 1 })) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    const dates = screen.getByTestId('legal-dates').textContent;
    expect(dates).toContain('Effective date: Not in effect yet');
    expect(dates).toContain('Last updated: Not in effect yet');
    const words = screen.getByTestId('legal-page').textContent ?? '';
    expect(words).not.toContain('TO FILL IN');
    expect(words).not.toContain('OWNER-CHECKLIST');
    expect(words).not.toMatch(/\*\*|\]\(|\|---/);
  });

  it('shows each placeholder as a note of what the shop will add', async () => {
    renderApp('/terms');
    await screen.findByRole('heading', { level: 1, name: 'Terms of Service' });
    const notes = Array.from(document.querySelectorAll('mark.legal__placeholder')).map((mark) => mark.textContent);
    expect(notes).toContain("To be added by the shop: the shop's refund policy for services and for products.");
    expect(notes).toContain("To be added by the shop: the shop's email address");
    expect(notes.every((note) => note?.startsWith('To be added by the shop'))).toBe(true);
    // The refund note ends its sentence: the next one doesn't run on from it.
    expect(screen.getByText(/^To be added by the shop: the shop's refund policy/).closest('li')?.textContent).toBe(
      "Refunds. To be added by the shop: the shop's refund policy for services and for products. Card refunds go back to the card you paid with.",
    );
  });

  it.each(PAGES)('%s: names the business behind the shop in its first paragraph, as a note until the shop adds its name', async (path, heading) => {
    renderApp(path);
    await screen.findByRole('heading', { level: 1, name: heading });
    expect(screen.getByTestId('legal-page').textContent).toContain(
      "Izzy Clipz Barbershop is operated by To be added by the shop: the LLC's exact registered name, a limited liability company.",
    );
  });

  it('shows an instruction to the owner only as “To be confirmed by the shop”', () => {
    // The documents have none today (the shop confirmed its number takes calls only), so this is
    // checked with words of its own, as an instruction to the owner would read.
    renderArticle(
      [
        '# Accessibility Statement',
        '',
        '- **If anything gets in your way:** call (442) 341-3053, text us [TO FILL IN: remove "text us" unless texts are confirmed] or email us.',
        "- **Text us at (442) 341-3053.** [TO FILL IN: keep this line only once you've confirmed this number takes texts; otherwise delete every mention of texting us.]",
      ].join('\n'),
      true,
    );
    const words = screen.getByTestId('legal-page').textContent ?? '';
    expect(words).not.toMatch(/keep this line|remove "text us"|otherwise delete|you've confirmed/);
    const notes = Array.from(document.querySelectorAll('mark.legal__placeholder')).map((mark) => mark.textContent);
    expect(notes).toEqual(['To be confirmed by the shop', 'To be confirmed by the shop.']);
    expect(words).toContain('call (442) 341-3053, text us To be confirmed by the shop or email us.');
  });

  it('the Accessibility Statement offers calls, relay calls and email, and no texts: the shop’s number takes calls only', async () => {
    renderApp('/accessibility');
    await screen.findByRole('heading', { level: 1, name: 'Accessibility Statement' });
    const words = screen.getByTestId('legal-page').textContent ?? '';
    const notes = Array.from(document.querySelectorAll('mark.legal__placeholder')).map((mark) => mark.textContent);
    expect(notes.filter((note) => note?.startsWith('To be confirmed by the shop'))).toEqual([]);
    expect(words).not.toMatch(/\btext us\b|\bText:|text you the details/i);
    expect(words).toContain(
      'call (442) 341-3053, call through a relay service by dialing 711, or email us (see "Other ways to book and get help").',
    );
  });

  it('in the demo, says it’s the demo too', async () => {
    vi.stubEnv('VITE_DEMO_MODE', '1');
    renderApp('/privacy');
    expect((await screen.findByTestId('legal-draft')).textContent).toBe(
      'Draft: not in effect yet.The shop will publish this when online booking opens. This is the demo version of the website.',
    );
  });

  it('lists its sections under “On this page”, each a link to its heading', async () => {
    renderApp('/privacy');
    await screen.findByRole('heading', { level: 1, name: 'Privacy Policy' });
    const contents = screen.getByRole('navigation', { name: 'On this page' });
    const links = within(contents).getAllByRole('link', { hidden: true });
    const sections = within(screen.getByTestId('legal-page')).getAllByRole('heading', { level: 2 });
    expect(links.map((link) => link.textContent)).toEqual(sections.map((h2) => h2.textContent));
    expect(links.map((link) => link.getAttribute('href'))).toEqual(sections.map((h2) => `#${h2.id}`));
    expect(links[0]?.getAttribute('href')).toBe('#the-short-version');
    expect(sections.map((h2) => h2.id)).toContain('cookies-and-storage-on-your-device');
  });

  it('links the other documents to their pages here, and leaves other sites’ links as they are', async () => {
    renderApp('/terms');
    await screen.findByRole('heading', { level: 1, name: 'Terms of Service' });
    expect(main().getAllByRole('link', { name: 'Cancellation & No-Show Policy' })[0]?.getAttribute('href')).toBe('/cancellation-policy');
    expect(main().getByRole('link', { name: 'Privacy Policy' }).getAttribute('href')).toBe('/privacy');
    expect(main().getByRole('link', { name: 'Accessibility Statement' }).getAttribute('href')).toBe('/accessibility');
    expect(main().getByRole('link', { name: 'Google Maps End User Additional Terms of Service' }).getAttribute('href')).toBe('https://maps.google.com/help/terms_maps/');
    // No link to a Markdown file is left.
    expect(Array.from(document.querySelectorAll('a')).some((a) => a.getAttribute('href')?.includes('.md'))).toBe(false);
  });

  it('calls the shop from its number, and never links the older website or Squire', async () => {
    renderApp('/privacy');
    await screen.findByRole('heading', { level: 1, name: 'Privacy Policy' });
    const calls = main().getAllByRole('link', { name: '(442) 341-3053' });
    expect(calls.length).toBeGreaterThan(2);
    expect(calls.every((link) => link.getAttribute('href') === 'tel:+14423413053')).toBe(true);
    // They're named, as the policy names what it doesn't cover, but never linked.
    expect(screen.getByTestId('legal-page').textContent).toContain('izzyclipzbarbershop.net');
    const hrefs = Array.from(document.querySelectorAll('a')).map((a) => a.getAttribute('href') ?? '');
    expect(hrefs.filter((href) => /izzyclipzbarbershop|squire/i.test(href))).toEqual([]);
  });

  it('opens a new text message from a number offered for texts, and a call from the others', () => {
    // With words of its own: the documents offer no texts today.
    renderArticle(
      [
        '# Accessibility Statement',
        '',
        '- **Call us at (442) 341-3053** during opening hours.',
        '- **Text us at (442) 341-3053.**',
        '- **Text:** (442) 341-3053',
        '- **Call:** (442) 341-3053, or dial 711 to call through a relay service',
      ].join('\n'),
      false,
    );
    const numbers = main().getAllByRole('link', { name: '(442) 341-3053' });
    const hrefOf = (words: RegExp) => numbers.filter((link) => words.test(link.closest('li, p')?.textContent ?? '')).map((link) => link.getAttribute('href'));
    // "Text us at (442) 341-3053." and "Text: (442) 341-3053" text; "Call us at…", "Call: … or dial 711" call.
    expect(hrefOf(/^Text us at/)).toEqual(['sms:+14423413053']);
    expect(hrefOf(/^Text:/)).toEqual(['sms:+14423413053']);
    expect(hrefOf(/^Call/)).toEqual(['tel:+14423413053', 'tel:+14423413053']);
    expect(numberHref('4423413053', 'Questions? Call us at ')).toBe('tel:+14423413053');
    expect(numberHref('4423413053', 'If anything gets in your way, text us at ')).toBe('sms:+14423413053');
    expect(numberHref('4423413053', 'Some context, then ')).toBe('tel:+14423413053');
  });

  it('the Accessibility Statement’s numbers all call: it offers no texts', async () => {
    renderApp('/accessibility');
    await screen.findByRole('heading', { level: 1, name: 'Accessibility Statement' });
    const numbers = main().getAllByRole('link', { name: '(442) 341-3053' });
    expect(numbers.length).toBeGreaterThan(1);
    expect(numbers.map((link) => link.getAttribute('href')).every((href) => href === 'tel:+14423413053')).toBe(true);
    expect(document.querySelector('a[href^="sms:"]')).toBeNull();
  });

  it('draws tables with their headers, the first column naming each row, and quotes and code', async () => {
    renderApp('/privacy');
    await screen.findByRole('heading', { level: 1, name: 'Privacy Policy' });
    const tables = screen.getAllByRole('table');
    expect(tables).toHaveLength(3);
    const storage = tables[1]!;
    expect(within(storage).getAllByRole('columnheader').map((th) => th.textContent)).toEqual(['What', "When it's removed"]);
    expect(within(storage).getAllByRole('rowheader')).toHaveLength(7);
    expect(screen.getByText('izzy_appointments').tagName).toBe('CODE');

    renderApp('/cancellation-policy');
    const quote = (await screen.findAllByText(/^No payment now\. If you cancel less than 1 hour/)).find((p) => p.closest('blockquote'));
    expect(quote).toBeDefined();
  });

  it('opened at a section, starts there', async () => {
    renderApp('/privacy#saved-cards');
    const heading = await screen.findByRole('heading', { level: 3, name: 'Saved cards' });
    await waitFor(() => expect(document.activeElement).toBe(heading));
  });
});

describe('a strict build, as the pages see it', () => {
  it('has no draft note: the build’s VITE_LEGAL_STRICT reaches the page', async () => {
    expect(legalDraft()).toBe(true);
    vi.stubEnv('VITE_LEGAL_STRICT', '1');
    expect(legalDraft()).toBe(false);
    renderApp('/privacy');
    await screen.findByRole('heading', { level: 1, name: 'Privacy Policy' });
    expect(screen.queryByTestId('legal-draft')).toBeNull();
    expect(screen.queryByText(/Not in effect yet/)).toBeNull();
  });
});

describe('a legal page, as the shop publishes it (a strict build)', () => {
  it('has no draft note, and its dates as the shop wrote them', () => {
    renderArticle(filledIn(read('privacy.md')), false);
    expect(screen.queryByTestId('legal-draft')).toBeNull();
    expect(screen.getByTestId('legal-dates').textContent).toBe('Effective date: December 1, 2026Last updated: December 1, 2026');
    expect(screen.queryByText(/Not in effect yet/)).toBeNull();
    expect(document.querySelector('mark')).toBeNull();
    // The shop's email address writes to it.
    const email = screen.getAllByRole('link', { name: 'hello@izzyclipz.example' });
    expect(email[0]?.getAttribute('href')).toBe('mailto:hello@izzyclipz.example');
  });

  it('as a draft, the same finished words still say it isn’t in effect', () => {
    renderArticle(filledIn(read('terms.md')), true);
    expect(screen.getByTestId('legal-draft')).toBeTruthy();
  });
});

describe('links to the documents', () => {
  it('the footer of every page has all four, with “Privacy” in the Privacy Policy’s', () => {
    renderApp('/services');
    const legal = within(screen.getByRole('contentinfo')).getByRole('navigation', { name: 'Legal' });
    expect(within(legal).getAllByRole('link').map((a) => [a.textContent, a.getAttribute('href')])).toEqual([
      ['Privacy Policy', '/privacy'],
      ['Terms of Service', '/terms'],
      ['Cancellation & No-Show Policy', '/cancellation-policy'],
      ['Accessibility', '/accessibility'],
    ]);
    expect(within(screen.getByRole('contentinfo')).getByText(/© \d{4} Izzy Clipz Barbershop/)).toBeTruthy();
  });
});
