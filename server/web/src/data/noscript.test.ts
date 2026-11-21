// @vitest-environment node
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { hoursSummary } from '../lib/shopTime';
import { catalog } from '../test/api';

// The note every page starts with when JavaScript is off (index.html's <noscript>): how to book
// without the site, with the shop's number, address and hours as the catalog the server sends has
// them (the Accessibility Statement asks people to call "during opening hours"). It's written out
// by hand, so this keeps it in step with the catalog.

const page = readFileSync(new URL('../../index.html', import.meta.url), 'utf8');
const note = (page.match(/<noscript>([\s\S]*?)<\/noscript>/)?.[1] ?? '').replace(/<[^>]+>/g, '').replace(/\s+/g, ' ');

describe('the note for browsers without JavaScript', () => {
  it('gives the shop’s number, address and opening hours, as the catalog has them', () => {
    expect(note).toContain(`call Izzy Clipz Barbershop at ${catalog.shop.phone.display}`);
    expect(page).toContain(`href="tel:${catalog.shop.phone.e164}"`);
    expect(note).toContain(`come by ${catalog.shop.address.lines.join(', ')}.`);
    // The site's labels keep "10 AM" together with a no-break space; the note is plain text.
    expect(note).toContain(`Open ${hoursSummary(catalog.hours).join('; ').replace(/\u00a0/g, ' ')}.`);
    expect(note).toContain('Open Monday–Saturday: 10 AM – 7 PM; Sunday: 10 AM – 6 PM.');
  });
});

describe('the note’s place on the page', () => {
  const business = readFileSync(new URL('../../business/index.html', import.meta.url), 'utf8');

  it('is a landmark of its own, named for screen readers, with the class print styles hide, on the site’s pages and Business’s', () => {
    for (const [what, html] of [
      ['the site', page],
      ['Business', business],
    ] as const) {
      const inside = html.match(/<noscript>\s*([\s\S]*?)\s*<\/noscript>/)?.[1] ?? '';
      expect(inside, what).toMatch(/^<aside\s+class="noscript-note"\s+aria-label="Without JavaScript"\s+data-testid="noscript"/);
      expect(inside.trimEnd().endsWith('</aside>'), what).toBe(true);
    }
  });
});
