import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { forgetReviews } from '../data/reviews';
import { catalog, mockApi, renderApp, reviews, reviewsUnavailable } from '../test/api';
import { times } from '../test/text';

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
      ['Izzy Clipz', '/'],
      ['Services', '/services'],
      ['Barbers', '/barbers'],
      ['Reviews', '/reviews'],
      ['Visit', '/visit'],
      ['My appointments', '/appointments'],
      ['Get the app', '/app'],
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
    expect(screen.getByTestId('open-today').textContent).toBe(times('Open today until 7 PM'));
    expect(main().getAllByRole('link', { name: /Book an appointment/ })[0]!.getAttribute('href')).toBe('/book');
  });

  it('shows the Google rating when the server has it', async () => {
    mockApi([['GET /api/reviews', { body: reviews }]]);
    renderApp('/');
    const rating = await screen.findByTestId('home-rating');
    expect(rating.textContent).toContain('4.9');
    expect(rating.textContent).toContain('59 reviews on Google');
    // Never Yelp's rating, even though the server sent one (Yelp's reviews are only linked).
    expect(document.body.textContent).not.toMatch(/on Yelp|4\.5|12 reviews/);
  });

  it('links to the reviews where they were written when they can’t be shown', async () => {
    const api = mockApi([['GET /api/reviews', { body: reviewsUnavailable }]]);
    renderApp('/');
    await waitFor(() => expect(api.calls.some((c) => c.path === '/api/reviews')).toBe(true));
    expect(screen.queryByTestId('home-rating')).toBeNull();
    expect(screen.getByText('Read them where clients wrote them.')).toBeTruthy();
    expect(screen.getByRole('link', { name: 'Yelp reviews' }).getAttribute('href')).toBe('https://www.yelp.com/biz/izzy-clipz-barbershop-oceanside');
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
  it('shows Google’s reviews with Google’s attribution, and only links to Yelp, whatever the server sends', async () => {
    mockApi([['GET /api/reviews', { body: reviews }]]);
    renderApp('/reviews');
    expect(await screen.findByText('Fixture Reviewer One')).toBeTruthy();
    expect(screen.getByRole('heading', { name: 'Reviews from Google Maps' })).toBeTruthy();
    // The server sent Yelp's rating and three of its reviews: none of it shows, not even who wrote them.
    expect(screen.queryByText('Fixture A.')).toBeNull();
    expect(reviews.yelp.available).toBe(true);
    expect(reviews.yelp.reviews.length).toBeGreaterThan(0);
    for (const review of reviews.yelp.reviews) expect(document.body.textContent).not.toContain(review.text!.slice(0, 30));
    expect(screen.queryByTestId('yelp-reviews')).toBeNull();
    expect(screen.queryByText(/Reviews from Yelp/)).toBeNull();
    // Yelp's 4.5 from 12 reviews, nowhere.
    expect(document.body.textContent).not.toMatch(/4\.5|12 reviews/);
    // A plain link instead, to the shop's page on Yelp (not the address with Yelp's API tracking).
    const elsewhere = screen.getByTestId('reviews-elsewhere');
    expect(within(elsewhere).getByRole('heading', { name: 'More reviews' })).toBeTruthy();
    expect(within(elsewhere).getByRole('link', { name: 'Read our reviews on Yelp' }).getAttribute('href')).toBe(
      'https://www.yelp.com/biz/izzy-clipz-barbershop-oceanside',
    );
    expect(document.querySelectorAll('a[href*="yelp.com"]')).toHaveLength(1);
  });

  it('says so, with links, when Google’s can’t be shown', async () => {
    mockApi([['GET /api/reviews', { body: reviewsUnavailable }]]);
    renderApp('/reviews');
    expect(await screen.findByText("Reviews can't be shown here right now")).toBeTruthy();
    expect(screen.queryByRole('heading', { name: 'Reviews from Google Maps' })).toBeNull();
    expect(screen.getByRole('link', { name: 'See our reviews on Google Maps' }).getAttribute('href')).toBe(reviewsUnavailable.google.url);
    expect(screen.getByRole('link', { name: 'Read our reviews on Yelp' })).toBeTruthy();
  });

  it('says it shows Google’s reviews, not Google’s and Yelp’s', async () => {
    mockApi([['GET /api/reviews', { body: reviews }]]);
    renderApp('/reviews');
    expect(screen.getByText('What clients say about Izzy Clipz on Google, as they wrote it.')).toBeTruthy();
    await waitFor(() => expect(document.querySelector('meta[name="description"]')?.getAttribute('content')).not.toContain('Google and Yelp'));
  });
});

describe('Visit', () => {
  it('has the address with directions, today’s hours marked, and the phone number', () => {
    renderApp('/visit');
    // The street on its own line, then the suite with the city.
    expect(main().getByRole('heading', { level: 2, name: '1919 Mission Ave' })).toBeTruthy();
    expect(main().getByText('Ste 105, Oceanside, CA 92058')).toBeTruthy();
    expect(main().getByRole('link', { name: /Apple Maps/ }).getAttribute('href')).toBe(catalog.shop.appleMapsDirectionsUrl);
    expect(main().getByRole('link', { name: /Google Maps/ }).getAttribute('href')).toBe(catalog.shop.googleMapsDirectionsUrl);
    const today = screen.getByRole('row', { current: 'date' });
    expect(today.textContent).toContain('Tuesday');
    expect(today.textContent).toContain(times('10 AM – 7 PM'));
    expect(main().getAllByRole('link', { name: /\(442\) 341-3053/ })[0]!.getAttribute('href')).toBe('tel:+14423413053');
    // Paid at the shop; a card the shop may hold isn't "never online", so it doesn't say so.
    expect(main().getByText('Credit card · Gift card. You pay at the shop.')).toBeTruthy();
    expect(document.body.textContent).not.toContain('never online');
  });
});

describe('the phone number', () => {
  it.each(['/services', '/barbers', '/reviews', '/appointments'])('is right under the heading on %s', (path) => {
    mockApi([['GET /api/reviews', { body: reviews }]]);
    renderApp(path);
    const header = screen.getByRole('heading', { level: 1 }).closest('header') as HTMLElement;
    expect(header.textContent).toContain('Prefer to call?');
    expect(within(header).getByRole('link', { name: '(442) 341-3053' }).getAttribute('href')).toBe('tel:+14423413053');
  });

  it('is in the hero on Home', () => {
    mockApi([['GET /api/reviews', { body: reviews }]]);
    renderApp('/');
    const hero = screen.getByRole('heading', { level: 1 }).closest('section') as HTMLElement;
    expect(within(hero).getByRole('link', { name: '(442) 341-3053' }).getAttribute('href')).toBe('tel:+14423413053');
  });
});

describe('Home’s photos', () => {
  // The six photos of clients' cuts are off until the shop has each person's written permission
  // (docs/legal/OWNER-CHECKLIST.md). Only the storefront is shown.
  it('show only the storefront in the hero', () => {
    mockApi([['GET /api/reviews', { body: reviews }]]);
    renderApp('/');
    const hero = screen.getByRole('heading', { level: 1 }).closest('section') as HTMLElement;
    const images = within(hero).getAllByRole('img').filter((img) => img.tagName === 'IMG' && img.getAttribute('alt'));
    expect(images.map((img) => img.getAttribute('alt'))).toContain(
      "The Izzy Clipz storefront at 1919 Mission Ave, with the shop's sign over the windows",
    );
    expect(within(hero).queryByRole('img', { name: /cut at Izzy Clipz/ })).toBeNull();
  });

  it('have no gallery of clients', () => {
    mockApi([['GET /api/reviews', { body: reviews }]]);
    renderApp('/');
    expect(screen.queryByRole('heading', { name: 'Fresh from the chair.' })).toBeNull();
    expect(document.querySelector('img[src*="gallery"]')).toBeNull();
  });
});

describe('the logo', () => {
  it.each([
    ['/', 4], // the nav, the hero, the Visit tile and the footer
    ['/visit', 3], // the nav, the sticker on the storefront photo and the footer
    ['/services', 2], // the nav and the footer
  ])('on %s, is the nav’s link home, named “Izzy Clipz”, and decoration everywhere else', (path, count) => {
    mockApi([['GET /api/reviews', { body: reviews }]]);
    renderApp(path);
    const nav = screen.getByRole('navigation', { name: 'Izzy Clipz' });
    const home = within(nav).getByRole('link', { name: 'Izzy Clipz' });
    expect(home.getAttribute('href')).toBe('/');
    expect(within(home).getByRole('img', { name: 'Izzy Clipz' }).matches('svg.logo')).toBe(true);
    // Screen readers hear the shop's name once, from the link; every other logo is decoration.
    expect(screen.getAllByRole('img', { name: 'Izzy Clipz' })).toHaveLength(1);
    const logos = Array.from(document.querySelectorAll('svg.logo'));
    expect(logos).toHaveLength(count);
    for (const logo of logos.filter((logo) => !nav.contains(logo))) expect(logo.getAttribute('aria-hidden')).toBe('true');
    expect(screen.getByRole('contentinfo').querySelector('svg.logo')).not.toBeNull();
    // The old logo pictures (the mascot, the logo on a white sticker) are gone; only photos are pictures.
    for (const image of Array.from(document.images)) expect(image.getAttribute('src')).not.toMatch(/logo|mascot/i);
  });
});

describe('the phone menu', () => {
  it('keeps the page under it out of reach while it’s open, and gives it back on the next page', async () => {
    mockApi([['GET /api/reviews', { body: reviews }]]);
    renderApp('/services');
    await userEvent.click(screen.getByRole('button', { name: 'Menu' }));
    const menu = document.getElementById('globalnav-menu') as HTMLElement;
    expect(menu).toBeTruthy();
    expect(screen.getByRole('main').hasAttribute('inert')).toBe(true);
    expect(document.querySelector('.globalfooter')!.hasAttribute('inert')).toBe(true);

    await userEvent.click(within(menu).getByRole('link', { name: 'Barbers' }));
    expect(h1()).toBe('Meet the barbers');
    expect(document.getElementById('globalnav-menu')).toBeNull();
    expect(screen.getByRole('main').hasAttribute('inert')).toBe(false);
    expect(document.querySelector('.globalfooter')!.hasAttribute('inert')).toBe(false);
    expect(document.activeElement).toBe(screen.getByRole('main'));
  });

  it('closes with Escape, back on the Menu button', async () => {
    mockApi([['GET /api/reviews', { body: reviews }]]);
    renderApp('/services');
    await userEvent.click(screen.getByRole('button', { name: 'Menu' }));
    await userEvent.keyboard('{Escape}');
    expect(document.getElementById('globalnav-menu')).toBeNull();
    expect(screen.getByRole('main').hasAttribute('inert')).toBe(false);
    expect(document.activeElement).toBe(screen.getByRole('button', { name: 'Menu' }));
  });
});
