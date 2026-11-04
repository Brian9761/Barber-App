import { screen, within } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { rememberLastBooked } from '../booking/lastBooked';
import { EMPTY_DRAFT, saveDraft } from '../booking/flow';
import { saveAppointment } from '../lib/storage';
import { newToken } from '../lib/tokens';
import { fixtureAppointment, FLOW45, mockApi, policyNotRequired, renderApp, reviewsUnavailable } from '../test/api';
import { isDemo } from './mode';

// The demo version says it's a demo wherever a booking could be taken for the real thing,
// in the apps' words, with the number to call to book for real. The real site never does.

const NOTICE = "Demo version: bookings aren't sent to the shop. To book for real, call (442) 341-3053.";

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(new Date('2026-11-03T16:00:00Z')); // Tuesday, 8 AM at the shop
});

afterEach(() => {
  vi.useRealTimers();
});

function demoVersion() {
  vi.stubEnv('VITE_DEMO_MODE', '1');
  expect(isDemo()).toBe(true);
}

describe('the demo notice', () => {
  it('isn’t on the real site', async () => {
    mockApi([['GET /api/reviews', { body: reviewsUnavailable }]]);
    expect(isDemo()).toBe(false);
    renderApp('/');
    await screen.findByRole('heading', { level: 1, name: /Fresh cuts/ });
    expect(screen.queryByTestId('demo-notice')).toBeNull();
  });

  it('is on Home, under the Book button, and calls the shop', async () => {
    demoVersion();
    mockApi([['GET /api/reviews', { body: reviewsUnavailable }]]);
    renderApp('/');
    const notice = await screen.findByTestId('demo-notice');
    expect(notice.textContent).toBe(NOTICE);
    expect(within(notice).getByRole('link', { name: '(442) 341-3053' }).getAttribute('href')).toBe('tel:+14423413053');
    // In the hero, right after its Book button.
    const hero = notice.closest('section')!;
    expect(within(hero).getByRole('link', { name: 'Book an appointment' })).toBeTruthy();
  });

  it('is on Review, under “No payment now”', async () => {
    demoVersion();
    mockApi([['GET /api/no-show-policy', { body: policyNotRequired }]]);
    saveDraft({
      ...EMPTY_DRAFT,
      serviceId: 'haircut',
      choice: { kind: 'offering', offeringId: FLOW45 },
      start: '2026-11-03T18:00:00Z',
      details: { name: 'Ana Flores', phone: '(442) 555-0123', email: '', note: '', remember: false },
    });
    renderApp('/book/review');
    const notice = await screen.findByTestId('demo-notice');
    expect(notice.textContent).toBe(NOTICE);
    expect(notice.previousElementSibling?.textContent).toContain("No payment now. You'll pay at the shop.");
  });

  it('is on the confirmation, under “No payment now”', async () => {
    demoVersion();
    saveAppointment(fixtureAppointment, newToken());
    rememberLastBooked(fixtureAppointment.id);
    renderApp('/book/confirmed');
    expect(await screen.findByRole('heading', { level: 1, name: "You're booked" })).toBeTruthy();
    const notice = screen.getByTestId('demo-notice');
    expect(notice.textContent).toBe(NOTICE);
    expect(notice.previousElementSibling?.textContent).toContain("No payment now. You'll pay at the shop.");
  });

  it('says on Reviews that the reviews are samples', async () => {
    demoVersion();
    mockApi([['GET /api/reviews', { body: reviewsUnavailable }]]);
    renderApp('/reviews');
    expect((await screen.findByTestId('demo-notice')).textContent).toBe(
      "Demo version: these reviews are samples, not the shop's. The real site shows the shop's reviews from Google and Yelp.",
    );
  });
});
