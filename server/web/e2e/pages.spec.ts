import { expectAccessible, expect, expectFits, isPhone, screenshot, setLiveReviews, test } from './support.js';

// Every page opens with its own heading and title, works from the nav on a
// desktop and a phone, logs nothing as an error and has no serious
// accessibility problems. Screenshots of each.

const PAGES = [
  { path: '/', shot: '01-home', heading: 'Fresh cuts. Booked in seconds.', title: 'Izzy Clipz Barbershop in Oceanside' },
  { path: '/services', shot: '02-services', heading: 'Services and prices', title: 'Services and prices · Izzy Clipz Barbershop' },
  { path: '/barbers', shot: '03-barbers', heading: 'Meet the barbers', title: 'Barbers · Izzy Clipz Barbershop' },
  { path: '/reviews', shot: '04-reviews', heading: 'Reviews', title: 'Reviews · Izzy Clipz Barbershop' },
  { path: '/visit', shot: '05-visit', heading: 'Visit the shop', title: 'Visit · Izzy Clipz Barbershop' },
  { path: '/book', shot: '06-book', heading: 'Pick a service', title: 'Step 1 of 5: Pick a service · Izzy Clipz Barbershop' },
  { path: '/appointments', shot: '07-appointments-empty', heading: 'My appointments', title: 'My appointments · Izzy Clipz Barbershop' },
  { path: '/business', shot: '08-business', heading: 'Izzy Clipz Business on your computer — coming next', title: 'Izzy Clipz Business · Izzy Clipz Barbershop' },
  { path: '/no-such-page', shot: '09-not-found', heading: "This page isn't here.", title: 'Page not found · Izzy Clipz Barbershop' },
] as const;

test.describe('every page', () => {
  // As the shop has it: live reviews from Google and Yelp (the server's own test fixtures).
  test.beforeAll(async ({ request }) => setLiveReviews(request, true));
  test.afterAll(async ({ request }) => setLiveReviews(request, false));

  for (const page of PAGES) {
    test(`${page.path} opens with its heading, title and description`, async ({ page: tab }, testInfo) => {
      await tab.goto(page.path);
      await expect(tab.getByRole('heading', { level: 1, name: page.heading })).toBeVisible();
      await expect(tab).toHaveTitle(page.title);
      await expect(tab.locator('meta[name="description"]')).toHaveAttribute('content', /.{40,}/);
      await expect(tab.locator('meta[property="og:title"]')).toHaveAttribute('content', page.title);
      // The phone number is on every page, and calls the shop.
      await expect(tab.locator('a[href="tel:+14423413053"]').first()).toBeAttached();
      if (page.path === '/') {
        await expect(tab.getByTestId('open-today')).toHaveText(/^(Open today|Closed)/);
        // The rating loads once its tile comes near the screen.
        await tab.getByRole('heading', { name: 'What clients say' }).scrollIntoViewIfNeeded();
        await expect(tab.getByTestId('home-rating')).toContainText('4.9');
        await tab.evaluate(() => window.scrollTo(0, 0));
      }
      if (page.path === '/reviews') {
        await expect(tab.getByTestId('google-reviews')).toContainText('Reviews from Google Maps');
        await expect(tab.getByTestId('yelp-reviews')).toContainText('Reviews from Yelp');
      }
      await expectAccessible(tab, page.path);
      await screenshot(tab, testInfo, page.shot);
    });
  }
});

test('every page fits a small phone, 375 pixels wide', async ({ page }, testInfo) => {
  test.skip(!isPhone(testInfo), 'A phone size');
  await page.setViewportSize({ width: 375, height: 812 });
  for (const { path } of PAGES) {
    await page.goto(path);
    await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
    await expectFits(page, `${path} at 375px`);
  }
});

test('reviews that can’t be shown say so kindly and link to Google and Yelp', async ({ page }, testInfo) => {
  await page.goto('/reviews');
  await expect(page.getByTestId('reviews-elsewhere')).toContainText("Reviews can't be shown here right now");
  await expect(page.getByRole('link', { name: /See our reviews on Google Maps/ })).toHaveAttribute('href', /google\.com\/maps/);
  await expect(page.getByRole('link', { name: /Read our reviews on Yelp/ })).toHaveAttribute('href', /yelp\.com/);
  await expectAccessible(page, '/reviews without live reviews');
  await screenshot(page, testInfo, '04-reviews-unavailable');
});

test('the nav goes to every page and back home', async ({ page }, testInfo) => {
  await page.goto('/');
  const nav = page.getByRole('navigation', { name: 'Izzy Clipz' });
  const destinations = [
    { link: 'Services', heading: 'Services and prices' },
    { link: 'Barbers', heading: 'Meet the barbers' },
    { link: 'Reviews', heading: 'Reviews' },
    { link: 'Visit', heading: 'Visit the shop' },
    { link: 'My appointment', heading: 'My appointments' },
  ];
  for (const destination of destinations) {
    if (isPhone(testInfo)) {
      // On a phone the links are in the menu, next to the Book pill.
      await expect(nav.getByRole('link', { name: destination.link, exact: true })).toBeHidden();
      await nav.getByRole('button', { name: 'Menu' }).click();
      await expect(nav.getByRole('button', { name: 'Close' })).toHaveAttribute('aria-expanded', 'true');
      if (destination.link === 'Services') {
        await expectAccessible(page, 'the phone menu');
        await screenshot(page, testInfo, '10-menu-open', { fullPage: false });
      }
    }
    await nav.getByRole('link', { name: destination.link, exact: true }).click();
    await expect(page.getByRole('heading', { level: 1, name: destination.heading })).toBeVisible();
    await expect(page).toHaveURL(new RegExp(`/${destination.link === 'My appointment' ? 'appointments' : destination.link.toLowerCase()}$`));
    if (!isPhone(testInfo)) await expect(nav.getByRole('link', { name: destination.link, exact: true })).toHaveAttribute('aria-current', 'page');
    // The menu closes once the page changes.
    await expect(nav.getByRole('button', { name: 'Close' })).toHaveCount(0);
  }
  await nav.getByRole('link', { name: 'Book an appointment' }).click();
  await expect(page.getByRole('heading', { level: 1, name: 'Pick a service' })).toBeVisible();
  await nav.getByRole('link', { name: 'Izzy Clipz home' }).click();
  await expect(page.getByRole('heading', { level: 1, name: 'Fresh cuts. Booked in seconds.' })).toBeVisible();

  // The footer's "For the shop".
  await page.getByRole('contentinfo').getByRole('link', { name: 'Izzy Clipz Business' }).click();
  await expect(page.getByRole('heading', { level: 1, name: /Izzy Clipz Business on your computer/ })).toBeVisible();
});

test('Home’s actions lead to booking and the services', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('main').getByRole('link', { name: 'See services', exact: true }).click();
  await expect(page.getByRole('heading', { level: 1, name: 'Services and prices' })).toBeVisible();
  await page.getByRole('link', { name: 'Book Haircut', exact: true }).click();
  await expect(page.getByTestId('step-count')).toHaveText('Step 2 of 5');
  await expect(page.getByRole('heading', { level: 1, name: 'Pick a barber' })).toBeVisible();
  await page.goto('/barbers');
  await page.getByRole('link', { name: 'Book with Carlos' }).click();
  await expect(page.getByRole('heading', { level: 1, name: 'Pick a service' })).toBeVisible();
  await expect(page.getByText('Booking with')).toBeVisible();
  await expect(page.getByText('Includes mustache & eyebrows, plus straight-razor detail and styling.').first()).toBeVisible();
});

test('the site’s files are served as they are, and every other address opens the site', async ({ request }) => {
  const robots = await request.get('/robots.txt');
  expect(robots.ok()).toBe(true);
  expect(await robots.text()).toContain('Allow: /');
  const deepLink = await request.get('/book/time');
  expect(deepLink.headers()['content-type']).toContain('text/html');
  const missingAsset = await request.get('/assets/missing-file.js');
  expect(missingAsset.status()).toBe(404);
  const catalog = await request.get('/api/catalog');
  expect(catalog.headers()['cache-control']).toBe('public, max-age=300');
  expect((await catalog.json()).shop.phone.display).toBe('(442) 341-3053');
});
