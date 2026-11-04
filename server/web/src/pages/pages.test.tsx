import { screen, waitFor, within } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { forgetReviews } from '../data/reviews';
import { catalog, mockApi, renderApp, reviews, reviewsUnavailable } from '../test/api';

beforeEach(() => {
  forgetReviews();
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(new Date('2026-11-03T18:00:00Z')); // Tuesday 10 AM at the shop
});

afterEach(() => {
  vi.useRealTimers();
});

const main = () => within(screen.getByRole('main'));
const h1 = () => screen.getByRole('heading', { level: 1 }).textContent;

describe('every page', () => {
  it.each([
    ['/', 'Fresh cuts. Booked in seconds.', 'Izzy Clipz Barbershop in Oceanside'],
    ['/services', 'Services and prices', 'Services and prices · Izzy Clipz Barbershop'],
    ['/barbers', 'Meet the barbers', 'Barbers · Izzy Clipz Barbershop'],
    ['/reviews', 'Reviews', 'Reviews · Izzy Clipz Barbershop'],
    ['/visit', 'Visit the shop', 'Visit · Izzy Clipz Barbershop'],
    ['/business', 'Izzy Clipz Business on your computer — coming next', 'Izzy Clipz Business · Izzy Clipz Barbershop'],
    ['/no-such-page', "This page isn't here.", 'Page not found · Izzy Clipz Barbershop'],
  ])('%s opens with its heading and title', async (path, heading, title) => {
    mockApi([['GET /api/reviews', { body: reviews }]]);
    renderApp(path);
    expect(h1()).toBe(heading);
    await waitFor(() => expect(document.title).toBe(title));
  });

  it('has the global nav, with the page it’s on marked and Book always there', () => {
    mockApi([['GET /api/reviews', { body: reviews }]]);
    renderApp('/visit');
    const nav = screen.getByRole('navigation', { name: 'Izzy Clipz' });
    const links = [
      ['Izzy Clipz home', '/'],
      ['Services', '/services'],
      ['Barbers', '/barbers'],
      ['Reviews', '/reviews'],
      ['Visit', '/visit'],
      ['My appointment', '/appointments'],
      ['Book an appointment', '/book'],
    ];
    expect(within(nav).getAllByRole('link').map((a) => a.getAttribute('href'))).toEqual(links.map(([, href]) => href));
    for (const [name, href] of links) expect(within(nav).getByRole('link', { name }).getAttribute('href')).toBe(href);
    expect(within(nav).getByRole('link', { name: 'Visit' }).getAttribute('aria-current')).toBe('page');
    expect(within(nav).getByRole('link', { name: 'Services' }).getAttribute('aria-current')).toBeNull();
  });
});

describe('Home', () => {
  it('says whether the shop is open now, on the shop’s clock', () => {
    mockApi([['GET /api/reviews', { body: reviews }]]);
    renderApp('/');
    expect(screen.getByTestId('open-today').textContent).toBe('Open today until 7 PM');
    expect(main().getAllByRole('link', { name: /Book an appointment/ })[0]!.getAttribute('href')).toBe('/book');
  });

  it('shows the Google rating when the server has it', async () => {
    mockApi([['GET /api/reviews', { body: reviews }]]);
    renderApp('/');
    const rating = await screen.findByTestId('home-rating');
    expect(rating.textContent).toContain('4.9');
    expect(rating.textContent).toContain('59 reviews on Google');
    expect(screen.getByText('4.5 on Yelp · 12 reviews')).toBeTruthy();
  });

  it('links to the reviews where they were written when they can’t be shown', async () => {
    const api = mockApi([['GET /api/reviews', { body: reviewsUnavailable }]]);
    renderApp('/');
    await waitFor(() => expect(api.calls.some((c) => c.path === '/api/reviews')).toBe(true));
    expect(screen.queryByTestId('home-rating')).toBeNull();
    expect(screen.getByText('Read them where clients wrote them.')).toBeTruthy();
    expect(screen.getByRole('link', { name: 'Yelp reviews' }).getAttribute('href')).toBe(reviewsUnavailable.yelp.url);
  });
});

describe('Services', () => {
  it('lists each service with its price and length, booking it in one click', () => {
    renderApp('/services');
    const card = (name: string) => screen.getByRole('heading', { level: 3, name }).closest('li')!;
    const haircut = card('Haircut');
    expect(haircut.textContent).toContain('From $35');
    expect(haircut.textContent).toContain('45 min – 1 hr');
    expect(within(haircut).getByRole('link', { name: 'Book Haircut' }).getAttribute('href')).toBe('/book?service=haircut');
    expect(card('VIP').textContent).toContain('Only Izzy offers it.');
  });
});

describe('Barbers', () => {
  it('shows each barber with their own menu and a way to book them', () => {
    renderApp('/barbers');
    for (const barber of catalog.barbers) {
      const card = screen.getByRole('heading', { level: 2, name: barber.name }).closest('li')!;
      expect(card.textContent).toContain(barber.title);
      expect(within(card).getByRole('link', { name: `Book with ${barber.name}` }).getAttribute('href')).toBe(`/book?barber=${barber.id}`);
    }
  });
});

describe('Reviews', () => {
  it('shows Google’s reviews with Google’s attribution, and Yelp’s', async () => {
    mockApi([['GET /api/reviews', { body: reviews }]]);
    renderApp('/reviews');
    expect(await screen.findByText('Fixture Reviewer One')).toBeTruthy();
    expect(screen.getByRole('heading', { name: 'Reviews from Google Maps' })).toBeTruthy();
    expect(screen.getByText('Fixture A.')).toBeTruthy();
  });

  it('says so, with links, when neither can be shown', async () => {
    mockApi([['GET /api/reviews', { body: reviewsUnavailable }]]);
    renderApp('/reviews');
    expect(await screen.findByText("Reviews can't be shown here right now")).toBeTruthy();
    expect(screen.queryByRole('heading', { name: 'Reviews from Google Maps' })).toBeNull();
  });
});

describe('Visit', () => {
  it('has the address with directions, today’s hours marked, and the phone number', () => {
    renderApp('/visit');
    // The street keeps its last two words together ("Ste\u00a0105").
    const street = main().getByRole('heading', { level: 2, name: /^1919 Mission Ave/ });
    expect(street.textContent?.replace(/\u00a0/g, ' ')).toBe(catalog.shop.address.lines[0]);
    expect(main().getByRole('link', { name: /Apple Maps/ }).getAttribute('href')).toBe(catalog.shop.appleMapsDirectionsUrl);
    expect(main().getByRole('link', { name: /Google Maps/ }).getAttribute('href')).toBe(catalog.shop.googleMapsDirectionsUrl);
    const today = screen.getByRole('row', { current: 'date' });
    expect(today.textContent).toContain('Tuesday');
    expect(today.textContent).toContain('10 AM – 7 PM');
    expect(main().getAllByRole('link', { name: /\(442\) 341-3053/ })[0]!.getAttribute('href')).toBe('tel:+14423413053');
  });
});
