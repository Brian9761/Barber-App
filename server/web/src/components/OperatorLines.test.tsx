import { render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { describe, expect, it } from 'vitest';
import { ROUTER_FUTURE } from '../App';
import type { Catalog } from '../api/types';
import { CatalogProvider } from '../data/catalog';
import { catalog } from '../test/api';
import { visibleText } from '../test/text';
import { Footer } from './Layout';

// Who runs the shop, where, and how to get that by email (Business and Professions Code §17538(d),
// docs/legal/OWNER-CHECKLIST.md §3 item 20): on every page's footer, from the shop's catalog (the
// Kit's ShopInfo, exported to data/catalog.json), with the refund policy a link away. Until the owner
// gives the LLC's name and the shop's email, each is marked as still to be added.

function renderFooter(shop: Partial<Catalog['shop']> = {}) {
  return render(
    <MemoryRouter future={ROUTER_FUTURE}>
      <CatalogProvider initial={{ ...catalog, shop: { ...catalog.shop, ...shop } }}>
        <Footer />
      </CatalogProvider>
    </MemoryRouter>,
  );
}

describe('who runs the shop, in every page’s footer', () => {
  it('until the owner gives them, marks the LLC’s name and the shop’s email as still to be added', () => {
    renderFooter();
    const lines = screen.getByTestId('footer-operator');
    expect(visibleText(lines)).toBe(
      "Izzy Clipz Barbershop is operated by To be added by the shop: the LLC's registered name, 1919 Mission Ave, Ste 105, Oceanside, CA 92058, United States." +
        "To get this information by email, email us at To be added by the shop: the shop's email address and we'll send it within 5 days." +
        'Our refund policy is in section 4 of our Terms of Service.',
    );
    expect(lines.querySelectorAll('mark.operator__placeholder')).toHaveLength(2);
    expect(within(lines).getByRole('link', { name: 'Terms of Service' }).getAttribute('href')).toBe('/terms#4-prices-and-paying');
    // On a row of its own, after the policies and before the copyright line.
    const legal = lines.parentElement!;
    expect(lines.previousElementSibling).toBe(within(legal).getByRole('navigation', { name: 'Legal' }));
    expect(lines.nextElementSibling?.textContent).toMatch(/^Copyright © \d{4} Izzy Clipz Barbershop\. All rights reserved\.$/);
  });

  it('once given, names the LLC, writes to the shop’s email, and puts the LLC’s name in the copyright line', () => {
    renderFooter({ operatorName: 'Izzy Clipz Barbershop LLC', email: 'hello@izzyclipz.example' });
    const lines = screen.getByTestId('footer-operator');
    expect(visibleText(lines)).toBe(
      'Izzy Clipz Barbershop is operated by Izzy Clipz Barbershop LLC, 1919 Mission Ave, Ste 105, Oceanside, CA 92058, United States.' +
        "To get this information by email, email us at hello@izzyclipz.example and we'll send it within 5 days." +
        'Our refund policy is in section 4 of our Terms of Service.',
    );
    expect(lines.querySelector('mark')).toBeNull();
    expect(within(lines).getByRole('link', { name: 'hello@izzyclipz.example' }).getAttribute('href')).toBe('mailto:hello@izzyclipz.example');
    expect(screen.getByText(/^Copyright © \d{4} Izzy Clipz Barbershop LLC\. All rights reserved\.$/)).toBeTruthy();
  });

  it('waits for the catalog, so a published site never shows "To be added" while it loads', () => {
    render(
      <MemoryRouter future={ROUTER_FUTURE}>
        <Footer />
      </MemoryRouter>,
    );
    expect(screen.queryByTestId('footer-operator')).toBeNull();
  });
});
