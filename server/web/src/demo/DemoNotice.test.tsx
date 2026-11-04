import { screen, waitFor, within } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { rememberLastBooked } from '../booking/lastBooked';
import { EMPTY_DRAFT, saveDraft } from '../booking/flow';
import { APPOINTMENTS_KEY, CARRY_COOKIE, DEMO_APPOINTMENTS_KEY, saveAppointment } from '../lib/storage';
import { newToken } from '../lib/tokens';
import { fixtureAppointment, FLOW45, mockApi, policyNotRequired, renderApp, reviews, reviewsUnavailable } from '../test/api';
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

  it('is right under the confirmation’s title, which says it’s a demo booking, before the details', async () => {
    demoVersion();
    saveAppointment(fixtureAppointment, newToken());
    rememberLastBooked(fixtureAppointment.id);
    renderApp('/book/confirmed');
    const title = await screen.findByRole('heading', { level: 1, name: 'Demo booking made' });
    const notices = screen.getAllByTestId('demo-notice');
    expect(notices).toHaveLength(1);
    expect(notices[0]!.textContent).toBe(NOTICE);
    expect(notices[0]!.previousElementSibling).toBe(title);
    expect(notices[0]!.compareDocumentPosition(screen.getByTestId('booked-summary')) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(screen.queryByText(/See you at/)).toBeNull();
    await waitFor(() => expect(document.title).toBe('Demo booking made · Izzy Clipz Barbershop'));
  });

  it('is on Get the app, before anyone adds the demo', () => {
    demoVersion();
    renderApp('/app');
    expect(screen.getByTestId('demo-notice').textContent).toBe(NOTICE);
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

describe('the demo’s sample reviews', () => {
  it('show as samples, with none of Google’s labels, attribution or terms, and links to the real reviews', async () => {
    demoVersion();
    // Whatever the reviews say (the demo's own answer has two samples under "google"), they're shown as samples.
    mockApi([['GET /api/reviews', { body: reviews }]]);
    renderApp('/reviews');
    const samples = await screen.findByTestId('sample-reviews');
    expect(within(samples).getByRole('heading', { level: 2 }).textContent).toBe('Sample reviews');
    expect(screen.getByText('On the real site, this page shows what clients say about Izzy Clipz on Google and Yelp.')).toBeTruthy();
    expect(within(samples).getByRole('link', { name: /See our reviews on Google Maps/ })).toBeTruthy();
    expect(within(samples).getByRole('link', { name: /Read our reviews on Yelp/ })).toBeTruthy();
    for (const label of ['Reviews from Google Maps', 'Most relevant on Google', "Up to five reviews that Google picks, in Google's order.", 'Reviews from Yelp']) {
      expect(screen.queryByText(label), label).toBeNull();
    }
    expect(screen.queryByTestId('google-reviews')).toBeNull();
    expect(screen.queryByText(/Google checks for and removes fake content/)).toBeNull();
    expect(screen.queryByText(/This site shows content from Google Maps/)).toBeNull();
    expect(within(samples).queryByRole('link', { name: /View on Google Maps|Read more on Yelp/ })).toBeNull();
  });
});

describe('offline, the demo', () => {
  it('says it still works, and how to book for real', () => {
    demoVersion();
    vi.spyOn(navigator, 'onLine', 'get').mockReturnValue(false);
    mockApi([['GET /api/reviews', { body: reviewsUnavailable }]]);
    renderApp('/visit');
    expect(screen.getByTestId('offline-notice').textContent).toBe("You're offline. The demo still works. To book for real, call the shop: (442) 341-3053");
  });
});

describe('what the demo keeps', () => {
  it('lists its bookings apart from the real site’s, and carries none into an app on the Home Screen', () => {
    demoVersion();
    saveAppointment(fixtureAppointment, newToken());
    expect(localStorage.getItem(APPOINTMENTS_KEY)).toBeNull();
    expect(JSON.parse(localStorage.getItem(DEMO_APPOINTMENTS_KEY)!)).toHaveLength(1);
    expect(document.cookie).not.toContain(CARRY_COOKIE);
  });
});
