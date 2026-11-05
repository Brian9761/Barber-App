import { readFileSync } from 'node:fs';
import type { APIRequestContext, Page } from '@playwright/test';
import {
  type Client,
  controlledByWorker,
  expect,
  expectAccessible,
  expectStep,
  fillDetails,
  firstTime,
  isPhone,
  screenshot,
  setRetired,
  storedAppointments,
  test,
  unfoldIcs,
  USER_AGENTS,
} from './support.js';

// The demo version (playwright.demo.config.ts): the whole booking, "Demo booking made", My
// appointments after a reload and offline, and cancelling, with not one request to /api,
// from the page or its service worker; it says it's a demo wherever a booking could be taken
// for real, on a phone's first screen and in the calendar file too, and on My appointments,
// where cancelling says nothing was sent to the shop; it keeps none of the client's details;
// the reviews are samples; it's hosted the way its vercel.json says; and it can be retired.

const NOTICE = "Demo version: bookings aren't sent to the shop. To book for real, call (442) 341-3053.";

/** The requests for /api that reached the server so far. */
async function serverApiRequests(request: APIRequestContext): Promise<string[]> {
  return ((await (await request.get('/__e2e/api-requests')).json()) as { requests: string[] }).requests;
}

/** A haircut with Any barber at the first open time, through to "Demo booking made". */
async function bookHaircut(page: Page, client: Client): Promise<void> {
  await page.goto('/book');
  await page.getByTestId('service-haircut').click();
  await page.getByTestId('any-barber').click();
  await (await firstTime(page)).click();
  await page.getByRole('button', { name: 'Continue' }).click();
  await expectStep(page, 4, 'Your details');
  await fillDetails(page, client);
  await page.getByRole('button', { name: 'Continue' }).click();
  await expectStep(page, 5, 'Review and book');
  await page.getByTestId('book-button').click();
  await expect(page.getByTestId('booked-title')).toHaveText('Demo booking made');
}

/** Every request for /api this browser makes, from the pages and the service worker. */
function watchApi(page: Page): string[] {
  const requests: string[] = [];
  page.context().on('request', (request) => {
    if (new URL(request.url()).pathname.startsWith('/api')) requests.push(`${request.method()} ${request.url()}`);
  });
  return requests;
}

test('books and cancels with no request to /api, saying it’s a demo', async ({ page, context, phone, request }, testInfo) => {
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
  // In the demo the details stay on this device, and Remember me says nothing of a saved card.
  await expect(page.getByText(/^This is the demo: your details stay on this (phone|computer) and aren't sent anywhere\.$/)).toBeVisible();
  await expect(page.getByTestId('details-privacy')).toHaveText(
    /^Demo version: your name and number stay on this (phone|computer)\. Nothing is sent to Izzy Clipz or anywhere else\.$/,
  );
  await expect(page.getByText('Your name and number fill in next time you book here. Leave it off on a shared', { exact: false })).toBeVisible();
  await expect(page.getByRole('main')).not.toContainText('a card you add');
  await fillDetails(page, { name: 'Demo Client', phone });
  await screenshot(page, testInfo, '05-book-4-details');
  await page.getByRole('button', { name: 'Continue' }).click();

  await expectStep(page, 5, 'Review and book');
  await expect(page.getByTestId('demo-notice')).toHaveText(NOTICE);
  await expect(page.getByTestId('card-section')).toHaveCount(0);
  await expectAccessible(page, 'the demo’s Review');
  await screenshot(page, testInfo, '06-book-5-review');
  await page.getByTestId('book-button').click();

  // "Demo booking made", and right under it, before the details, that the shop doesn't have it.
  await expect(page.getByTestId('booked-title')).toHaveText('Demo booking made');
  await expect(page.getByTestId('booked-summary')).toContainText(/Flowxbori|Cristian|Julian/);
  await expect(page.getByTestId('demo-notice')).toHaveText(NOTICE);
  expect(await page.getByTestId('demo-notice').evaluate((notice) => notice.previousElementSibling?.getAttribute('data-testid'))).toBe('booked-title');
  await expectAccessible(page, 'the demo’s confirmation');
  await screenshot(page, testInfo, '07-book-6-confirmed');

  // Still there after a reload: the demo keeps it in this browser.
  await page.getByRole('link', { name: 'Manage or cancel' }).click();
  await page.reload();
  const card = page.getByTestId('appointment-card');
  await expect(card.getByTestId('appointment-status')).toHaveText('Next appointment');
  await expect(card).toContainText('Haircut with');
  // Above it, that it's the demo: coming back to it later, nobody should think the shop has it.
  await expect(page.getByTestId('demo-notice')).toHaveText(NOTICE);
  expect(
    await page.getByTestId('demo-notice').evaluate((notice) => {
      const listed = document.querySelector('[data-testid="appointment-card"]');
      return listed !== null && Boolean(notice.compareDocumentPosition(listed) & Node.DOCUMENT_POSITION_FOLLOWING);
    }),
    'the demo notice comes before the booking',
  ).toBe(true);
  await expectAccessible(page, 'the demo’s My appointments');
  await screenshot(page, testInfo, '08-appointments-booked');

  // And offline: the demo's bookings live in this browser, so they're still there, and the line says the demo works.
  await controlledByWorker(page);
  await context.setOffline(true);
  await page.reload();
  await expect(page.getByTestId('offline-notice')).toHaveText("You're offline. The demo still works. To book for real, call the shop: (442) 341-3053");
  await expect(card.getByTestId('appointment-status')).toHaveText('Next appointment');
  await expect(page.getByTestId('appointments-offline')).toHaveCount(0);
  await screenshot(page, testInfo, '08b-appointments-offline');
  await context.setOffline(false);
  await page.reload();

  // Cancelling says the shop hears nothing of it, before and after: it never had the booking.
  await card.getByRole('button', { name: 'Cancel appointment' }).click();
  const dialog = page.getByTestId('cancel-dialog');
  await expect(dialog).toContainText('This is the demo: nothing was sent to the shop.');
  await expect(dialog).not.toContainText('The shop sees it right away');
  await screenshot(page, testInfo, '08c-appointments-cancel-dialog', { fullPage: false });
  await page.getByTestId('confirm-cancel').click();
  await expect(card.getByTestId('appointment-status')).toHaveText('Cancelled');
  await expect(card.getByTestId('cancelled-notice')).toHaveText('Appointment cancelled. This is the demo: nothing was sent to the shop.');
  await expect(page.getByText('The shop sees it right away')).toHaveCount(0);
  await page.reload();
  await expect(page.getByTestId('appointment-card').getByTestId('appointment-status')).toHaveText('Cancelled');
  await screenshot(page, testInfo, '09-appointments-cancelled');
  const [saved] = await storedAppointments(page);
  expect(saved?.appointment.status).toBe('cancelled');

  // Not one request for /api: none from the browser, and none reached the server.
  expect(fromBrowser).toEqual([]);
  expect((await serverApiRequests(request)).slice(reachedServer)).toEqual([]);
});

test.describe('on an iPhone', () => {
  test.use({ userAgent: USER_AGENTS.iphone });

  test('a demo booking says it’s a demo on the first screen, and so does its calendar file', async ({ page, phone }, testInfo) => {
    test.skip(!isPhone(testInfo), 'An iPhone is a phone');
    await page.goto('/book');
    await page.getByTestId('service-haircut').click();
    await page.getByTestId('any-barber').click();
    await (await firstTime(page)).click();
    await page.getByRole('button', { name: 'Continue' }).click();
    await expect(page.getByRole('checkbox', { name: 'Remember me on this phone' })).toBeVisible();
    await fillDetails(page, { name: 'Demo Client', phone });
    await page.getByRole('button', { name: 'Continue' }).click();
    await page.getByTestId('book-button').click();

    // With the Add to Home Screen bar showing too (booked), the notice is still on the first screen.
    await expect(page.getByTestId('booked-title')).toHaveText('Demo booking made');
    await expect(page.getByTestId('install-hint')).toBeVisible();
    const box = (await page.getByTestId('demo-notice').boundingBox())!;
    expect(box.y + box.height, 'the demo notice ends on the first screen').toBeLessThanOrEqual(page.viewportSize()!.height);
    await expect(page.getByText("It's saved in My appointments on this phone, where you can cancel it too.")).toBeVisible();
    await screenshot(page, testInfo, '11-iphone-booked-first-screen', { fullPage: false });

    // The calendar file is no reminder to go to the shop.
    const download = page.waitForEvent('download');
    await page.getByRole('button', { name: 'Add to calendar' }).click();
    const ics = unfoldIcs(readFileSync(await (await download).path(), 'utf8'));
    expect(ics).toContain('SUMMARY:DEMO\\, not booked: Haircut at Izzy Clipz');
    expect(ics).toContain("DESCRIPTION:Demo version: this booking wasn't sent to the shop\\, and Izzy Clipz doesn't have it. To book for real\\, call (442) 341-3053.");
    expect(ics).not.toContain('VALARM');

    // On My appointments too, the notice is on the first screen, above the booking: opened again
    // days later, from the Home Screen say, it's the first thing that says what the booking is.
    await page.getByRole('link', { name: 'Manage or cancel' }).click();
    const card = page.getByTestId('appointment-card');
    await expect(card.getByTestId('appointment-status')).toHaveText('Next appointment');
    const listed = (await page.getByTestId('demo-notice').boundingBox())!;
    expect(listed.y + listed.height, 'the demo notice ends on the first screen').toBeLessThanOrEqual(page.viewportSize()!.height);
    expect(listed.y + listed.height, 'the demo notice is above the booking').toBeLessThanOrEqual((await card.boundingBox())!.y);
    await screenshot(page, testInfo, '12-iphone-appointments-first-screen', { fullPage: false });
  });
});

test('keeps none of the client’s details, and Forget me clears what the demo kept', async ({ page, phone }, testInfo) => {
  test.skip(isPhone(testInfo), 'Once is enough');
  const digits = phone.replace(/\D/g, '');
  // Remember me left off, as on a shared computer.
  await bookHaircut(page, { name: 'Private Person', phone, email: 'private.person@example.com', note: 'gate code 4321' });
  const everything = () => page.evaluate(() => JSON.stringify({ ...localStorage }) + JSON.stringify({ ...sessionStorage }) + document.cookie);
  const kept = await everything();
  for (const detail of ['Private Person', digits, 'private.person', 'gate code']) expect(kept, detail).not.toContain(detail);
  expect(kept).toContain('izzy.demo.v1');

  await page.getByRole('link', { name: 'Manage or cancel' }).click();
  await page.getByRole('button', { name: 'Forget me on this computer' }).click();
  await page.getByTestId('confirm-forget').click();
  await expect(page.getByTestId('forgotten-notice')).toHaveText('Done. This computer no longer keeps anything from the demo.');
  const left = await page.evaluate(() => Object.keys(localStorage));
  expect(left.filter((key) => key.startsWith('izzy.demo'))).toEqual([]);
});

test('shows sample reviews as samples, with none of Google’s labels and no made-up rating', async ({ page }, testInfo) => {
  await page.goto('/reviews');
  await expect(page.getByTestId('demo-notice')).toHaveText(
    "Demo version: these reviews are samples, not the shop's. The real site shows the shop's reviews from Google, and links to Yelp.",
  );
  await expect(page.getByRole('heading', { level: 2, name: 'Sample reviews' })).toBeVisible();
  await expect(page.getByText('Sample reviewer A')).toBeVisible();
  await expect(page.getByText('Sample reviewer B')).toBeVisible();
  await expect(page.locator('.score')).toHaveCount(0);
  for (const label of ['Reviews from Google Maps', 'Most relevant on Google', 'This site shows content from Google Maps']) {
    await expect(page.getByText(label)).toHaveCount(0);
  }
  await expect(page.getByRole('link', { name: /See our reviews on Google Maps/ })).toBeVisible();
  await expectAccessible(page, 'the demo’s reviews');
  await screenshot(page, testInfo, '10-reviews');
});

test('is hosted the way its vercel.json says: every page, the worker never cached, a strict content policy, and out of search results', async ({
  request,
}) => {
  const worker = await request.get('/sw.js');
  expect(worker.headers()['cache-control']).toBe('no-cache');
  expect(worker.headers()['content-type']).toMatch(/javascript/);
  expect((await request.get('/manifest.webmanifest')).headers()['content-type']).toBe('application/manifest+json');

  const deep = await request.get('/book/time');
  expect(deep.status()).toBe(200);
  expect(await deep.text()).toContain('<div id="root"></div>');
  expect(deep.headers()['x-robots-tag']).toBe('noindex');
  // Only its own scripts, styles, fonts and images; never in a frame; no camera, microphone, location or payments.
  expect(deep.headers()['content-security-policy']).toBe(
    "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; manifest-src 'self'; worker-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'",
  );
  expect(deep.headers()['permissions-policy']).toBe('camera=(), microphone=(), geolocation=(), payment=()');
  // Read, but never listed: a search engine that couldn't read a page would never see its noindex.
  const robots = await (await request.get('/robots.txt')).text();
  expect(robots).toContain('The demo version of the Izzy Clipz website');
  expect(robots).toContain('Allow: /');
  expect((await request.get('/assets/no-such-file.js')).status()).toBe(404);
  expect((await request.get('/api/catalog')).status()).toBe(404);
  expect((await request.get('/offline.html')).headers()['content-type']).toMatch(/text\/html/);
});

test('can be retired: at its address in its place, the retired site clears it out and says where Izzy Clipz is now', async ({ page, request }, testInfo) => {
  test.skip(isPhone(testInfo), 'Once is enough');
  await page.goto('/visit');
  await controlledByWorker(page);
  await page.evaluate(() => localStorage.setItem('izzy.details.v1', JSON.stringify({ name: 'Ana Flores', phone: '(442) 555-0123', email: '' })));
  try {
    await setRetired(request, true);
    // The browser looks for a new worker whenever the app opens or comes back on screen; here, now.
    await page.evaluate(() => {
      void navigator.serviceWorker.getRegistration().then((registration) => registration?.update());
    });
    // The retired worker takes over at once and reloads the page, which is now the moved page.
    const moved = page.getByRole('heading', { level: 1, name: 'Izzy Clipz has moved.' });
    await expect(moved).toBeVisible({ timeout: 30_000 });
    await expect(page.getByRole('link', { name: 'Get the new app' })).toHaveAttribute('href', /^https:\/\/[^/]+\/app$/);
    await expect(page.getByRole('link', { name: '(442) 341-3053' })).toHaveAttribute('href', 'tel:+14423413053');
    // Nothing of the demo is left in this browser: no worker, no files, nothing it kept.
    await expect.poll(() => page.evaluate(async () => (await navigator.serviceWorker.getRegistrations()).length)).toBe(0);
    await expect.poll(() => page.evaluate(async () => (await caches.keys()).length)).toBe(0);
    await expect.poll(() => page.evaluate(() => localStorage.length)).toBe(0);
    await expectAccessible(page, 'the retired demo');
    await screenshot(page, testInfo, '40-retired');

    // Every address of the old demo says the same.
    await page.goto('/book/time');
    await expect(moved).toBeVisible();
  } finally {
    await setRetired(request, false);
  }
});
