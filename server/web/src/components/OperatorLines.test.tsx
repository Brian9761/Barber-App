import { render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { describe, expect, it } from 'vitest';
import { ROUTER_FUTURE } from '../App';
import type { Catalog } from '../api/types';
import { CatalogProvider } from '../data/catalog';
import { catalog } from '../test/api';
import { visibleText } from '../test/text';
import { Footer } from './Layout';
import { emailOf, legalNameOf, operatedByLine, OperatorLines, REFUNDS_HREF } from './OperatorLines';

// Who runs the shop, where, and how to get that by email (Business and Professions Code §17538(d),
// docs/legal/OWNER-CHECKLIST.md §3 item 20): on every page's footer, from the shop's catalog (the
// Kit's ShopInfo, exported to data/catalog.json), with the refund policy ("Refunds") next to the
// Cancellation & No-Show Policy. Until the owner gives the LLC's name and the shop's email, only what
// exists shows, the shop and its address, and nothing made up.

function renderFooter(shop: Partial<Catalog['shop']> = {}) {
  return render(
    <MemoryRouter future={ROUTER_FUTURE}>
      <CatalogProvider initial={{ ...catalog, shop: { ...catalog.shop, ...shop } }}>
        <Footer />
      </CatalogProvider>
    </MemoryRouter>,
  );
}

const GIVEN = { legalName: 'Izzy Clipz Barbershop LLC', email: 'hello@izzyclipz.example' };

describe('who runs the shop, in every page’s footer', () => {
  it('until the owner gives the LLC’s name and the shop’s email, says only what exists: the shop and its address', () => {
    // The catalog as the Kit exports it today: both there, both empty.
    expect(catalog.shop).toMatchObject({ legalName: '', email: '' });
    renderFooter();
    const lines = screen.getByTestId('footer-operator');
    expect(visibleText(lines)).toBe('Izzy Clipz Barbershop, 1919 Mission Ave, Ste 105, Oceanside, CA 92058, United States.');
    expect(lines.textContent).not.toMatch(/operated by|To be added|email/i);
    expect(lines.querySelector('mark, a')).toBeNull();
    // On a row of its own, after the policies and before the copyright line, which names the shop.
    const legal = lines.parentElement!;
    expect(lines.previousElementSibling).toBe(within(legal).getByRole('navigation', { name: 'Legal' }));
    expect(lines.nextElementSibling?.textContent).toMatch(/^Copyright © \d{4} Izzy Clipz Barbershop\. All rights reserved\.$/);
    // The address isn't said twice in a row.
    expect(lines.nextElementSibling?.nextElementSibling).toBeNull();
  });

  it('lists "Refunds" next to the Cancellation & No-Show Policy, going to the Terms’ refunds', () => {
    renderFooter();
    const policies = within(screen.getByRole('navigation', { name: 'Legal' })).getAllByRole('link');
    expect(policies.map((link) => link.textContent)).toEqual(['Privacy Policy', 'Terms of Service', 'Cancellation & No-Show Policy', 'Refunds', 'Accessibility']);
    expect(policies[3]!.getAttribute('href')).toBe('/terms#refunds');
    expect(REFUNDS_HREF).toBe('/terms#refunds');
  });

  it('once given, names the LLC, offers it by email, and puts the LLC’s name in the copyright line', () => {
    renderFooter(GIVEN);
    const lines = screen.getByTestId('footer-operator');
    expect(visibleText(lines)).toBe(
      'Izzy Clipz Barbershop is operated by Izzy Clipz Barbershop LLC, 1919 Mission Ave, Ste 105, Oceanside, CA 92058, United States.' +
        "To get this information by email, email us at hello@izzyclipz.example and we'll send it within 5 days.",
    );
    expect(within(lines).getByRole('link', { name: 'hello@izzyclipz.example' }).getAttribute('href')).toBe('mailto:hello@izzyclipz.example');
    expect(screen.getByText(/^Copyright © \d{4} Izzy Clipz Barbershop LLC\. All rights reserved\.$/)).toBeTruthy();
  });

  it('with only one of them given, shows that one and nothing in place of the other', () => {
    renderFooter({ legalName: 'Izzy Clipz Barbershop LLC', email: '' });
    expect(visibleText(screen.getByTestId('footer-operator'))).toBe(
      'Izzy Clipz Barbershop is operated by Izzy Clipz Barbershop LLC, 1919 Mission Ave, Ste 105, Oceanside, CA 92058, United States.',
    );
  });

  it('waits for the catalog, so nothing is guessed while it loads', () => {
    render(
      <MemoryRouter future={ROUTER_FUTURE}>
        <Footer />
      </MemoryRouter>,
    );
    expect(screen.queryByTestId('footer-operator')).toBeNull();
    expect(screen.getByText(/^Copyright © \d{4} Izzy Clipz Barbershop\. All rights reserved\.$/)).toBeTruthy();
  });
});

describe('the lines themselves', () => {
  it('are the app’s words (the Kit’s ShopInfo), with spaces alone counting as nothing given', () => {
    expect(operatedByLine(catalog.shop)).toBe('Izzy Clipz Barbershop, 1919 Mission Ave, Ste 105, Oceanside, CA 92058, United States.');
    expect(operatedByLine({ ...catalog.shop, ...GIVEN })).toBe(
      'Izzy Clipz Barbershop is operated by Izzy Clipz Barbershop LLC, 1919 Mission Ave, Ste 105, Oceanside, CA 92058, United States.',
    );
    expect(legalNameOf({ legalName: '  ' })).toBeNull();
    expect(emailOf({ email: ' ' })).toBeNull();
    // A catalog from before these were in it reads as nothing given.
    expect(legalNameOf({})).toBeNull();
    expect(emailOf({})).toBeNull();
    expect(legalNameOf({ legalName: ' Izzy Clipz Barbershop LLC ' })).toBe('Izzy Clipz Barbershop LLC');
  });

  it('on "Review and book", put the Cancellation & No-Show Policy and "Refunds" side by side, in new tabs', () => {
    render(
      <MemoryRouter future={ROUTER_FUTURE}>
        <OperatorLines shop={{ ...catalog.shop, ...GIVEN }} testId="lines" policyLinks newTab />
      </MemoryRouter>,
    );
    const policies = screen.getByTestId('lines-policies');
    expect(visibleText(policies)).toBe('Cancellation & No-Show Policy · Refunds');
    const links = within(policies).getAllByRole('link');
    expect(links.map((link) => [link.getAttribute('href'), link.getAttribute('target')])).toEqual([
      ['/cancellation-policy', '_blank'],
      ['/terms#refunds', '_blank'],
    ]);
  });
});
