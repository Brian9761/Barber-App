import type { APIRequestContext, Page } from '@playwright/test';
import { expect, expectAccessible, expectStep, fillDetails, firstTime, screenshot, storedAppointments, test } from './support.js';

// The demo version (playwright.demo.config.ts): the whole booking, "You're booked", My
// appointments after a reload, and cancelling, with not one request to /api, from the page
// or its service worker; it says it's a demo wherever a booking could be taken for real;
// the reviews are samples; and it's hosted the way its vercel.json says.

const NOTICE = "Demo version: bookings aren't sent to the shop. To book for real, call (442) 341-3053.";

/** The requests for /api that reached the server so far. */
async function serverApiRequests(request: APIRequestContext): Promise<string[]> {
  return ((await (await request.get('/__e2e/api-requests')).json()) as { requests: string[] }).requests;
}

/** Every request for /api this browser makes, from the pages and the service worker. */
function watchApi(page: Page): string[] {
  const requests: string[] = [];
  page.context().on('request', (request) => {
    if (new URL(request.url()).pathname.startsWith('/api')) requests.push(`${request.method()} ${request.url()}`);
  });
  return requests;
}

test('books and cancels with no request to /api, saying it’s a demo', async ({ page, phone, request }, testInfo) => {
  const fromBrowser = watchApi(page);
  const reachedServer = (await serverApiRequests(request)).length;
  await page.goto('/');
  const notice = page.getByTestId('demo-notice');
  await expect(notice).toHaveText(NOTICE);
  await expect(notice.getByRole('link', { name: '(442) 341-3053' })).toHaveAttribute('href', 'tel:+14423413053');
  await expect(page.getByTestId('open-today')).toHaveText(/^(Open today|Closed)/);
  await expectAccessible(page, 'the demo’s Home');
  await screenshot(page, testInfo, '01-home');

  await page.getByRole('main').getByRole('link', { name: 'Book an appointment' }).first().click();
  await expectStep(page, 1, 'Pick a service');
  await screenshot(page, testInfo, '02-book-1-service');
  await page.getByTestId('service-haircut').click();

  await expectStep(page, 2, 'Pick a barber');
  await expect(page.getByTestId('any-barber')).toContainText('Whoever is free first: Flowxbori, Cristian or Julian');
  await screenshot(page, testInfo, '03-book-2-barber');
  await page.getByTestId('any-barber').click();

  // The shop's own hours on its clock, with some times already taken by the sample bookings.
  await expectStep(page, 3, 'Pick a day and time');
  const time = await firstTime(page);
  await time.click();
  await expect(time).toHaveAttribute('aria-pressed', 'true');
  await expectAccessible(page, 'the demo’s times');
  await screenshot(page, testInfo, '04-book-3-time');
  await page.getByRole('button', { name: 'Continue' }).click();

  await expectStep(page, 4, 'Your details');
  await fillDetails(page, { name: 'Demo Client', phone });
  await screenshot(page, testInfo, '05-book-4-details');
  await page.getByRole('button', { name: 'Continue' }).click();

  await expectStep(page, 5, 'Review and book');
  await expect(page.getByTestId('demo-notice')).toHaveText(NOTICE);
  await expect(page.getByTestId('card-section')).toHaveCount(0);
  await expectAccessible(page, 'the demo’s Review');
  await screenshot(page, testInfo, '06-book-5-review');
  await page.getByTestId('book-button').click();

  await expect(page.getByTestId('booked-title')).toHaveText("You're booked");
  await expect(page.getByTestId('booked-summary')).toContainText(/Flowxbori|Cristian|Julian/);
  await expect(page.getByTestId('demo-notice')).toHaveText(NOTICE);
  await expectAccessible(page, 'the demo’s confirmation');
  await screenshot(page, testInfo, '07-book-6-confirmed');

  // Still there after a reload: the demo keeps it in this browser.
  await page.getByRole('link', { name: 'Manage or cancel' }).click();
  await page.reload();
  const card = page.getByTestId('appointment-card');
  await expect(card.getByTestId('appointment-status')).toHaveText('Next appointment');
  await expect(card).toContainText('Haircut with');
  await screenshot(page, testInfo, '08-appointments-booked');

  await card.getByRole('button', { name: 'Cancel appointment' }).click();
  await page.getByTestId('confirm-cancel').click();
  await expect(card.getByTestId('appointment-status')).toHaveText('Cancelled');
  await page.reload();
  await expect(page.getByTestId('appointment-card').getByTestId('appointment-status')).toHaveText('Cancelled');
  await screenshot(page, testInfo, '09-appointments-cancelled');
  const [saved] = await storedAppointments(page);
  expect(saved?.appointment.status).toBe('cancelled');

  // Not one request for /api: none from the browser, and none reached the server.
  expect(fromBrowser).toEqual([]);
  expect((await serverApiRequests(request)).slice(reachedServer)).toEqual([]);
});

test('shows sample reviews that say they’re samples, and no made-up rating', async ({ page }, testInfo) => {
  await page.goto('/reviews');
  await expect(page.getByTestId('demo-notice')).toHaveText(
    "Demo version: these reviews are samples, not the shop's. The real site shows the shop's reviews from Google and Yelp.",
  );
  await expect(page.getByText('Sample reviewer A')).toBeVisible();
  await expect(page.getByText('Sample reviewer B')).toBeVisible();
  await expect(page.locator('.score')).toHaveCount(0);
  await expectAccessible(page, 'the demo’s reviews');
  await screenshot(page, testInfo, '10-reviews');
});

test('is hosted the way its vercel.json says: every page, the worker never cached, and out of search results', async ({ request }) => {
  const worker = await request.get('/sw.js');
  expect(worker.headers()['cache-control']).toBe('no-cache');
  expect(worker.headers()['content-type']).toMatch(/javascript/);
  expect((await request.get('/manifest.webmanifest')).headers()['content-type']).toBe('application/manifest+json');

  const deep = await request.get('/book/time');
  expect(deep.status()).toBe(200);
  expect(await deep.text()).toContain('<div id="root"></div>');
  expect(deep.headers()['x-robots-tag']).toBe('noindex');
  expect((await request.get('/assets/no-such-file.js')).status()).toBe(404);
  expect((await request.get('/api/catalog')).status()).toBe(404);
  expect((await request.get('/offline.html')).headers()['content-type']).toMatch(/text\/html/);
});
