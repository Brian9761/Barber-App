import type { APIRequestContext, Page } from '@playwright/test';
import { expectBusinessInstallable, expectInSight, navLink, newCode, ownerCall, PHOTO_PNG, shot, signInWithCode, signOutButton } from './business-support.js';
import { expect, expectAccessible, isPhone, tabTo, test } from './support.js';

// Izzy Clipz Business on a computer, against the real API (e2e/serve.ts, with an owner key):
// a code from the app (made here with the key, as the iPhone app does) signs the computer
// in; Today shows a booked appointment; a cash checkout with a product turns it paid;
// Analytics shows the sale, with the leaderboard, the services and the products; the sale
// is voided; a product is added, given a photo, edited and deleted; no-show protection
// saves; Sign out works, and a computer signed out from the iPhone drops back to sign-in.
// Keyboard only, no console errors, no serious axe-core findings, and Chrome finds nothing
// missing to install Izzy Clipz Business. Screenshots of every page, desktop and phone.

const ZONE = 'America/Los_Angeles';

interface Analytics {
  totals: { salesCents: number };
  leaderboard: { name: string; salesCents: number }[];
}

interface Appointment {
  id: string;
  customer: { name: string };
}

/** The shop's wall clock: "2026-11-04" and minutes past midnight. */
function shopClock(instant: Date): { date: string; minutes: number } {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat('en-US', {
      timeZone: ZONE,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      hourCycle: 'h23',
    })
      .formatToParts(instant)
      .map((p) => [p.type, p.value]),
  );
  return { date: `${parts.year}-${parts.month}-${parts.day}`, minutes: Number(parts.hour) * 60 + Number(parts.minute) };
}

/** The instant the shop's clock shows `minutes` past midnight today. */
function todayAt(minutes: number): Date {
  const { date } = shopClock(new Date());
  const [y, m, d] = date.split('-').map(Number) as [number, number, number];
  for (const offset of [7, 8]) {
    const instant = new Date(Date.UTC(y, m - 1, d, Math.floor(minutes / 60) + offset, minutes % 60));
    const clock = shopClock(instant);
    if (clock.date === date && clock.minutes === minutes) return instant;
  }
  throw new Error('No such time today');
}

function money(cents: number): string {
  const dollars = Math.floor(cents / 100)
    .toString()
    .replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return cents % 100 === 0 ? `$${dollars}` : `$${dollars}.${String(cents % 100).padStart(2, '0')}`;
}

/** The barber each screen size books with, so the desktop and phone runs never take each other's times. */
function barberFor(page: Page): { id: string; name: string; offering: string } {
  return page.viewportSize()!.width < 600
    ? { id: 'julian-ramos', name: 'Julian', offering: 'julian-ramos/bbb0c294-87a6-465d-9f55-6f579dcb399a' }
    : { id: 'cristian-ceja', name: 'Cristian', offering: 'cristian-ceja/bbb0c294-87a6-465d-9f55-6f579dcb399a' };
}

/** A walk-in booked at the shop today ($35 haircut, 45 minutes), at the first time the barber is free. */
async function bookToday(request: APIRequestContext, barber: { offering: string }, name: string): Promise<Appointment> {
  for (let minutes = 10 * 60; minutes + 45 <= 18 * 60; minutes += 45) {
    const response = await request.post('/api/owner/appointments', {
      headers: { Authorization: `Bearer ${process.env.E2E_OWNER_KEY || 'e2e-owner-key-for-local-tests-only'}` },
      data: { offeringId: barber.offering, start: todayAt(minutes).toISOString(), customer: { name, phone: '(760) 555-0142' } },
    });
    if (response.status() === 409) continue;
    expect(response.ok(), await response.text()).toBe(true);
    return ((await response.json()) as { appointment: Appointment }).appointment;
  }
  throw new Error('No free time today');
}

test('a code from the app signs in; a cash checkout with a product turns the appointment paid, shows in Analytics, and is voided', async ({
  page,
  request,
}, testInfo) => {
  const barber = barberFor(page);
  const client = `Jordan ${testInfo.project.name === 'phone' ? 'Phone' : 'Desk'}`;
  const product = await ownerCall<{ product: { id: string; name: string } }>(request, 'POST', '/api/owner/products', {
    name: `E2E pomade (${testInfo.project.name})`,
    priceCents: 1800,
    visible: true,
  });
  await bookToday(request, barber, client);

  // Sign in: the page, then a code typed with a space, as people type "483 920".
  await page.goto('/business');
  await expect(page.getByText('Open Izzy Clipz Business on your iPhone.')).toBeVisible();
  await expectAccessible(page, 'sign-in');
  await shot(page, testInfo, 'b01-signin');
  await signInWithCode(page, request);
  await expect(page).toHaveTitle('Today · Izzy Clipz Business');

  // Today: the booked appointment, in its barber's column on a computer, in the list on a phone.
  const card = page.getByTestId('appointment').filter({ hasText: client });
  await expect(card).toContainText('Booked');
  if (!isPhone(testInfo))
    await expect(
      page
        .getByRole('listitem')
        .filter({ has: page.getByRole('heading', { name: barber.name }) })
        .getByText(client),
    ).toBeVisible();
  await expectAccessible(page, 'Today');
  await shot(page, testInfo, 'b02-today');

  // Its details, then Check out: the haircut at its booked price, Sold by its barber.
  await card.click();
  const panel = page.getByTestId('side-panel');
  await expect(panel.getByRole('heading', { name: client })).toBeVisible();
  await expect(panel.getByRole('link', { name: /Call \(760\) 555-0142/ })).toHaveAttribute('href', 'tel:+17605550142');
  await expectAccessible(page, 'an appointment');
  await shot(page, testInfo, 'b03-appointment', { panel: true });
  await panel.getByRole('button', { name: 'Check out' }).click();
  await expect(panel.getByTestId('ticket-total')).toHaveText('$35');
  await expect(panel.getByRole('radio', { name: barber.name })).toBeChecked();
  await expect(panel.getByText('Card payments happen on the iPhone, with Tap to Pay in Izzy Clipz Business.', { exact: false })).toBeVisible();
  await panel.getByRole('button', { name: '+ Product' }).click();
  // What + Product opens is in sight, never under the total and how they're paying.
  const pomade = panel.getByRole('button', { name: new RegExp(product.product.name.replace(/[()]/g, '\\$&')) });
  await expectInSight(pomade, 'the product to add');
  await shot(page, testInfo, 'b12-checkout-products', { panel: true });
  await pomade.click();
  await expect(panel.getByTestId('ticket-total')).toHaveText('$53');
  await expectAccessible(page, 'checkout');
  await shot(page, testInfo, 'b04-checkout', { panel: true });
  await panel.getByRole('button', { name: 'Cash', exact: true }).click();
  const confirm = page.getByTestId('confirm-sale');
  await expect(confirm.getByRole('heading')).toHaveText(`Record a $53 cash sale for ${barber.name}?`);
  await confirm.getByRole('button', { name: 'Record sale' }).click();
  await expect(panel.getByTestId('receipt')).toContainText(`Sold $53 · Cash · ${barber.name}`);
  await shot(page, testInfo, 'b05-sold', { panel: true });
  await page.getByRole('button', { name: 'Done' }).click();
  await expect(card).toContainText('Paid $53 · Cash');
  await expect(page.getByTestId('sale-row').filter({ hasText: client })).toContainText('$53');

  // Analytics: the sale, the barber on the leaderboard, the haircut and the product.
  const today = shopClock(new Date()).date;
  const numbers = await ownerCall<Analytics>(request, 'GET', `/api/owner/analytics?from=${today}&to=${today}`);
  await navLink(page, 'Analytics').click();
  await expect(page.getByRole('heading', { level: 1, name: 'Analytics' })).toBeVisible();
  await expect(page.getByTestId('total-sales-value')).toHaveText(money(numbers.totals.salesCents));
  const row = page.getByTestId('leaderboard-row').filter({ hasText: barber.name });
  await expect(row).toContainText(money(numbers.leaderboard.find((e) => e.name === barber.name)!.salesCents));
  await expect(page.getByTestId('service-row').filter({ hasText: /^Haircut/ })).toBeVisible();
  await expect(page.getByTestId('product-row').filter({ hasText: product.product.name })).toContainText('1 sold');
  await expect(page.getByTestId('live')).toHaveText(/^Live · Updated /);
  await expectAccessible(page, 'Analytics');
  await shot(page, testInfo, 'b06-analytics');
  // The leaderboard by products: the barber who sold the pomade is up there.
  await page.getByTestId('leaderboard').getByRole('radio', { name: 'Products' }).check();
  await expect(row).toContainText(/\d+ products?/);
  // The year, by month: no serious axe-core finding on its chart.
  await page.getByRole('radio', { name: 'Year' }).check();
  await expect(page.getByRole('heading', { name: 'Sales by month' })).toBeVisible();
  await expectAccessible(page, 'Analytics by month');
  await shot(page, testInfo, 'b13-analytics-year');

  // Void it: the sale stops counting, and the appointment is unpaid again.
  await navLink(page, 'Today').click();
  await page.getByRole('button', { name: `Void the $53 sale to ${client}` }).click();
  const dialog = page.getByTestId('confirm-void');
  await dialog.getByLabel(/Reason/).fill('Rang up twice');
  await dialog.getByRole('button', { name: 'Void sale' }).click();
  await expect(page.getByTestId('void-message')).toHaveText('The sale was voided, so it no longer counts in your sales.');
  await expect(page.getByTestId('sale-row').filter({ hasText: client })).toContainText('Voided: Rang up twice');
  await expect(card).not.toContainText('Paid');
  const after = await ownerCall<Analytics>(request, 'GET', `/api/owner/analytics?from=${today}&to=${today}`);
  expect(after.totals.salesCents).toBe(numbers.totals.salesCents - 5300 + 3500);
});

test('a walk-in whose answer was lost is recorded once, also when the ticket is closed and the sale rung up again', async ({
  page,
  request,
  browserConsole,
}, testInfo) => {
  // The browser logs the request the test cuts off.
  browserConsole.allow(/ERR_FAILED|Failed to load resource/);
  await signInWithCode(page, request);
  const name = `Lost answer (${testInfo.project.name})`;
  let cut = false;
  await page.route('**/api/owner/sales', async (route) => {
    if (route.request().method() !== 'POST' || cut) return route.fallback();
    cut = true;
    // The server records the sale, and its answer never reaches the page.
    await route.fetch();
    await route.abort('failed');
  });
  const panel = page.getByTestId('side-panel');
  const ringUp = async () => {
    await page.getByRole('button', { name: 'New sale' }).click();
    await panel.getByRole('radio', { name: 'Carlos' }).check();
    await panel.getByRole('button', { name: '+ Amount' }).click();
    await panel.getByLabel(/^Name/).fill(name);
    await panel.getByLabel('Amount', { exact: true }).fill('12');
    await panel.getByRole('button', { name: 'Add the amount' }).click();
    await panel.getByRole('button', { name: 'Cash', exact: true }).click();
    await page.getByTestId('confirm-sale').getByRole('button', { name: 'Record sale' }).click();
  };
  await ringUp();
  await expect(panel.getByTestId('ticket-failed')).toContainText("Trying again is safe: the same sale can't be recorded twice.");
  // Closed, and rung up again on a new ticket: the server answers with the sale it has.
  await panel.getByRole('button', { name: 'Close' }).click();
  await ringUp();
  await expect(panel.getByTestId('receipt')).toContainText('Sold $12 · Cash · Carlos');
  const { sales } = await ownerCall<{ sales: { items: { name: string }[] }[] }>(request, 'GET', `/api/owner/sales?date=${shopClock(new Date()).date}`);
  expect(sales.filter((sale) => sale.items.some((item) => item.name === name))).toHaveLength(1);
});

test('a product is added, given a photo, edited and deleted', async ({ page, request }, testInfo) => {
  await signInWithCode(page, request);
  await navLink(page, 'Products').click();
  await expect(page.getByRole('heading', { level: 1, name: 'Products' })).toBeVisible();
  const name = `Hair clay (${testInfo.project.name})`;

  await page.getByRole('button', { name: 'Add a product' }).click();
  const editor = page.getByTestId('product-editor');
  await editor.getByLabel('Name').fill(name);
  await editor.getByLabel(/Description/).fill('Strong hold, matte finish.');
  await editor.getByLabel('Price', { exact: true }).fill('22');
  await editor.locator('input[type="file"]').setInputFiles({ name: 'clay.png', mimeType: 'image/png', buffer: PHOTO_PNG });
  await expect(editor.getByRole('img', { name: `Photo of ${name}` })).toBeVisible();
  await expectAccessible(page, 'the product editor');
  await shot(page, testInfo, 'b08-product-editor', { panel: true });
  await editor.getByRole('button', { name: 'Add product' }).click();
  await expect(page.getByTestId('products-message')).toHaveText(`Saved ${name}.`);
  const card = page.getByTestId('product').filter({ hasText: name });
  await expect(card).toContainText('$22');
  await expect(card).toContainText('Shown in the app');
  // The photo went to the server as a JPEG, and shows.
  const photo = card.locator('img');
  await expect(photo).toHaveAttribute('src', /\/__e2e\/blob\/products\/.+\.jpg$/);
  expect(await photo.evaluate((img: HTMLImageElement) => img.complete && img.naturalWidth > 0)).toBe(true);

  // Edit: no price (checkout asks for it), hidden from clients.
  await card.getByRole('button', { name: `Edit ${name}` }).click();
  // Ticked by their words, as people do (the whole box is the label).
  await editor.getByText('No price', { exact: true }).click();
  await expect(editor.getByRole('checkbox', { name: /No price/ })).toBeChecked();
  await editor.getByText('Show in the Izzy Clipz app', { exact: true }).click();
  await expect(editor.getByRole('checkbox', { name: /Show in the Izzy Clipz app/ })).not.toBeChecked();
  await editor.getByRole('button', { name: 'Save changes' }).click();
  await expect(card).toContainText('No price');
  await expect(card).toContainText('Hidden from clients');
  await expectAccessible(page, 'Products');
  await shot(page, testInfo, 'b07-products');

  const { products } = await ownerCall<{ products: { name: string; priceCents: number | null; visible: boolean }[] }>(request, 'GET', '/api/owner/products');
  expect(products.find((p) => p.name === name)).toMatchObject({ priceCents: null, visible: false });

  // Delete, after the question.
  await card.getByRole('button', { name: `Delete ${name}` }).click();
  await page.getByTestId('confirm-delete-product').getByRole('button', { name: 'Delete product' }).click();
  await expect(page.getByTestId('products-message')).toHaveText(`Deleted ${name}. Past sales keep its name.`);
  await expect(card).toHaveCount(0);
});

test('no-show protection saves, and Settings shows Stripe, this computer and the others', async ({ page, request }, testInfo) => {
  const before = (await ownerCall<{ noShowSettings: Record<string, unknown> }>(request, 'GET', '/api/owner/no-show-settings')).noShowSettings;
  try {
    await signInWithCode(page, request);
    await navLink(page, 'Settings').click();
    await expect(page.getByRole('heading', { level: 1, name: 'Settings' })).toBeVisible();
    // This server has no Stripe key: it says so, with nothing to connect.
    await expect(page.getByTestId('stripe-status')).toContainText('Not set up on the server');
    await expect(page.getByTestId('this-computer')).toContainText('Chrome on Linux');

    const section = page.getByTestId('no-show-settings');
    await section.getByRole('checkbox', { name: 'No-show protection' }).check();
    await section.getByRole('radio', { name: 'Flat amount' }).check();
    await section.getByLabel('Flat fee').fill('25');
    await section.getByRole('combobox', { name: 'Cancelling less than' }).selectOption({ label: '2 hours before' });
    await section.getByRole('button', { name: 'Save' }).click();
    await expect(section.getByTestId('no-show-saved')).toHaveText('Saved. New bookings use these settings.');
    const saved = (await ownerCall<{ noShowSettings: Record<string, unknown> }>(request, 'GET', '/api/owner/no-show-settings')).noShowSettings;
    expect(saved).toMatchObject({ enabled: true, feeMode: 'flat', flatCents: 2500, lateCancelWindowMinutes: 120 });
    await expectAccessible(page, 'Settings');
    await shot(page, testInfo, 'b09-settings');
  } finally {
    // The other tests book online as clients do, with the shop's settings as they were.
    await ownerCall(request, 'PATCH', '/api/owner/no-show-settings', before);
  }
});

test('Sign out signs this computer out, and a computer signed out from the iPhone drops back to sign-in', async ({
  page,
  request,
  browserConsole,
}, testInfo) => {
  // The browser logs the server's 401 for the computer signed out from the iPhone.
  browserConsole.allow(/401/);
  await signInWithCode(page, request);
  const signedIn = await ownerCall<{ sessions: unknown[] }>(request, 'GET', '/api/owner/computer-sessions');
  await signOutButton(page, testInfo).click();
  const dialog = page.getByTestId('sign-out-dialog');
  await expect(dialog.getByRole('heading')).toHaveText('Sign out on this computer?');
  await dialog.getByRole('button', { name: 'Sign out', exact: true }).click();
  await expect(page.getByTestId('signed-out-line')).toContainText("You're signed out on this computer.");
  await expect(page.getByRole('heading', { level: 1, name: 'Izzy Clipz Business on your computer' })).toBeVisible();
  expect(await page.evaluate(() => localStorage.getItem('izzy.business.session.v1'))).toBeNull();
  const after = await ownerCall<{ sessions: unknown[] }>(request, 'GET', '/api/owner/computer-sessions');
  expect(after.sessions.length).toBe(signedIn.sessions.length - 1);
  await shot(page, testInfo, 'b10-signed-out');

  // Signed in again, then signed out from the iPhone (every computer): the next page drops back to sign-in.
  await signInWithCode(page, request);
  await ownerCall(request, 'DELETE', '/api/owner/computer-sessions');
  await navLink(page, 'Analytics').click();
  await expect(page.getByTestId('signed-out-line')).toContainText('This computer was signed out.');
  await expect(page.getByLabel('6-digit code')).toBeVisible();
  await expectAccessible(page, 'signed out from the iPhone');
  await shot(page, testInfo, 'b11-signed-out-from-iphone');
});

test('works with the keyboard alone, and installs as Izzy Clipz Business', async ({ page, request }) => {
  const code = await newCode(request);
  await page.goto('/business');
  const field = page.getByLabel('6-digit code');
  await tabTo(page, field);
  await page.keyboard.type(code);
  await page.keyboard.press('Enter');
  await expect(page.getByTestId('today-page')).toBeVisible();
  await tabTo(page, navLink(page, 'Analytics'));
  await page.keyboard.press('Enter');
  await expect(page.getByRole('heading', { level: 1, name: 'Analytics' })).toBeVisible();
  // The period, with the arrow keys of its radio buttons.
  await tabTo(page, page.getByRole('radio', { name: 'Today' }));
  await page.keyboard.press('ArrowRight');
  await expect(page.getByRole('radio', { name: 'Week' })).toBeChecked();
  await expect(page.getByTestId('period-line')).toContainText('This week');

  await page.goto('/business/today?source=app');
  await expect(page.getByTestId('today-page')).toBeVisible();
  await expectBusinessInstallable(page, request);
});

test('the clients’ site keeps its own manifest, and its footer leads to Izzy Clipz Business', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('link[rel="manifest"]')).toHaveAttribute('href', '/manifest.webmanifest');
  await page.getByRole('contentinfo').getByRole('link', { name: 'Izzy Clipz Business' }).click();
  await expect(page.getByRole('heading', { level: 1, name: 'Izzy Clipz Business on your computer' })).toBeVisible();
  // Reached without a page load, the page still names Business's manifest and icons...
  await expect(page.locator('link[rel="manifest"]')).toHaveAttribute('href', '/business/manifest.webmanifest');
  await expect(page.locator('meta[name="robots"]')).toHaveAttribute('content', 'noindex');
  // ...and gives the site's back on the way out.
  await page.goBack();
  await expect(page.locator('link[rel="manifest"]')).toHaveAttribute('href', '/manifest.webmanifest');
});
