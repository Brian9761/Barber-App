import type { APIRequestContext, Page } from '@playwright/test';
import { expectBusinessInstallable, expectInSight, navLink, PHOTO_PNG, shot, signOutButton } from './business-support.js';
import { expect, expectAccessible, isPhone, test } from './support.js';

// Izzy Clipz Business in the demo version (playwright.demo.config.ts): one button opens it,
// with the sample shop; checking out, voiding, statuses and the no-show fee follow the
// server's rules; Analytics follows along; "Connect Stripe" connects after a pretend step;
// products, no-show settings and computers work; Reset brings the sample shop back; and it
// installs as Izzy Clipz Business. Not one request reaches /api, from the pages or the
// service worker.
//
// The clock is Wednesday, November 4, 2026 at 12:30 PM in Oceanside, so the sample shop is
// the same every run: the morning's appointments are over (most checked out), Kim Sample's
// 12 PM haircut has started, and the afternoon is still to come.

const NOON_THIRTY = new Date('2026-11-04T20:30:00Z');
const DEMO_LINE = 'Demo version: sample data, nothing is sent anywhere.';

/** Every request for /api this browser makes, from the pages and the service worker. */
function watchApi(page: Page): string[] {
  const requests: string[] = [];
  page.context().on('request', (request) => {
    if (new URL(request.url()).pathname.startsWith('/api')) requests.push(`${request.method()} ${request.url()}`);
  });
  return requests;
}

async function serverApiRequests(request: APIRequestContext): Promise<string[]> {
  return ((await (await request.get('/__e2e/api-requests')).json()) as { requests: string[] }).requests;
}

/** Opens the demo with its one button. */
async function openDemo(page: Page): Promise<void> {
  await page.clock.setFixedTime(NOON_THIRTY);
  await page.goto('/business');
  await expect(page.getByTestId('demo-notice')).toHaveText(DEMO_LINE);
  await page.getByRole('button', { name: 'Open the Business demo' }).click();
  await expect(page).toHaveURL(/\/business\/today$/);
  await expect(page.getByTestId('day-summary')).toBeVisible();
}

function appointment(page: Page, name: string) {
  return page.getByTestId('appointment').filter({ hasText: name });
}

/** "$1,234" as a number of cents. */
function cents(text: string): number {
  const match = /\$([\d,]+)(?:\.(\d{2}))?/.exec(text);
  if (!match) throw new Error(`No amount in ${text}`);
  return Number(match[1]!.replace(/,/g, '')) * 100 + Number(match[2] ?? '0');
}

async function analyticsToday(page: Page): Promise<{ total: number; carlos: number }> {
  await navLink(page, 'Analytics').click();
  await expect(page.getByTestId('live')).toHaveText(/^Live · Updated 12:30 PM$/);
  const total = cents((await page.getByTestId('total-sales-value').textContent()) ?? '');
  const carlos = cents((await page.getByTestId('leaderboard-row').filter({ hasText: 'Carlos' }).locator('.biz-rank__value').textContent()) ?? '');
  return { total, carlos };
}

test('one button opens the demo; checking out, voiding, statuses and the no-show fee work like the server, with no request to /api', async ({
  page,
  request,
}, testInfo) => {
  const fromBrowser = watchApi(page);
  const reachedServer = (await serverApiRequests(request)).length;
  await page.clock.setFixedTime(NOON_THIRTY);
  await page.goto('/business');
  await expect(page.getByRole('heading', { level: 1, name: 'Izzy Clipz Business on your computer' })).toBeVisible();
  await expect(page.getByTestId('demo-notice')).toHaveText(DEMO_LINE);
  // No code in the demo: one button.
  await expect(page.getByLabel('6-digit code')).toHaveCount(0);
  await expectAccessible(page, 'the demo’s sign-in');
  await shot(page, testInfo, 'b01-signin');
  await page.getByRole('button', { name: 'Open the Business demo' }).click();

  // Today: the sample shop, the demo's line under the nav.
  await expect(page.getByTestId('biz-demo-notice')).toHaveText(DEMO_LINE);
  await expect(page.getByTestId('appointment')).toHaveCount(12);
  await expect(appointment(page, 'Ruben Sample')).toContainText('Booked');
  await expectAccessible(page, 'the demo’s Today');
  await shot(page, testInfo, 'b02-today');
  const before = await analyticsToday(page);
  await navLink(page, 'Today').click();

  // Check out Ruben's $45 haircut with Carlos, and a $18 sample pomade, paid another way.
  await appointment(page, 'Ruben Sample').click();
  const panel = page.getByTestId('side-panel');
  await expectAccessible(page, 'an appointment in the demo');
  await shot(page, testInfo, 'b03-appointment', { panel: true });
  await panel.getByRole('button', { name: 'Check out' }).click();
  // The panel's new view starts at its heading, with the focus.
  await expect(panel.getByRole('heading', { name: 'Check out' })).toBeFocused();
  await panel.getByRole('button', { name: '+ Product' }).click();
  // What + Product opens is in sight, above the total and how they're paying, never under them.
  await expectInSight(panel.getByRole('button', { name: /Sample pomade/ }), 'the first product');
  await panel.getByRole('button', { name: /Sample pomade/ }).click();
  await expect(panel.getByRole('button', { name: '+ Product' })).toBeFocused();
  await expect(panel.getByTestId('ticket-total')).toHaveText('$63');
  await shot(page, testInfo, 'b04-checkout', { panel: true });
  await panel.getByRole('button', { name: /^Other/ }).click();
  await expect(page.getByTestId('confirm-sale').getByRole('heading')).toHaveText('Record a $63 sale for Carlos, paid another way?');
  await page.getByTestId('confirm-sale').getByRole('button', { name: 'Record sale' }).click();
  await expect(panel.getByTestId('receipt')).toContainText('Sold $63 · Other · Carlos');
  await shot(page, testInfo, 'b05-sold', { panel: true });
  await page.getByRole('button', { name: 'Done' }).click();
  await expect(appointment(page, 'Ruben Sample')).toContainText('Paid $63 · Other');

  // Analytics follows: the shop and Carlos are up $63.
  const after = await analyticsToday(page);
  expect(after.total - before.total).toBe(6300);
  expect(after.carlos - before.carlos).toBe(6300);
  await expect(page.getByTestId('product-row').filter({ hasText: 'Sample pomade' })).toBeVisible();
  await expectAccessible(page, 'the demo’s Analytics');
  await shot(page, testInfo, 'b06-analytics');
  // A week, with its daily chart and its table.
  await page.getByRole('radio', { name: 'Week' }).check();
  await expect(page.getByTestId('period-line')).toHaveText('This week: Nov 2 – Nov 4 · Whole shop');
  // Compared with the same number of days just before, named.
  await expect(page.getByTestId('total-sales-change')).toContainText('Oct 30 – Nov 1');
  // The chart's columns are one stop for the keyboard; the arrow keys move between them.
  const columns = page.getByTestId('daily-sales').locator('[role="button"][aria-pressed]');
  await expect(columns).toHaveCount(3);
  await expect(page.getByTestId('daily-sales').locator('[role="button"][tabindex="0"]')).toHaveCount(1);
  await columns.first().focus();
  await page.keyboard.press('ArrowRight');
  await page.keyboard.press('Enter');
  await expect(columns.nth(1)).toHaveAttribute('aria-pressed', 'true');
  await expect(page.getByTestId('daily-picked')).toContainText('Tue, Nov 3: $');
  await page.getByRole('button', { name: 'Show daily sales as a table' }).click();
  await expect(page.getByTestId('daily-sales').getByRole('row')).toHaveCount(4);
  await shot(page, testInfo, 'b07-analytics-week');
  // The year, by month: no serious axe-core finding on its chart either.
  await page.getByRole('radio', { name: 'Year' }).check();
  await expect(page.getByRole('heading', { name: 'Sales by month' })).toBeVisible();
  await expectAccessible(page, 'the demo’s Analytics by month');

  // Void it: it stops counting as a sale; Ruben's appointment stays done, so it counts at its booked $45.
  await navLink(page, 'Today').click();
  await page.getByRole('button', { name: 'Void the $63 sale to Ruben Sample' }).click();
  await page
    .getByTestId('confirm-void')
    .getByLabel(/Reason/)
    .fill('Rang up by mistake');
  await page.getByTestId('confirm-void').getByRole('button', { name: 'Void sale' }).click();
  await expect(page.getByTestId('void-message')).toHaveText('The sale was voided, so it no longer counts in your sales.');
  await expect(page.getByTestId('sale-row').filter({ hasText: 'Ruben Sample' })).toContainText('Voided: Rang up by mistake');
  const voided = await analyticsToday(page);
  expect(voided.total - before.total).toBe(4500);

  // Statuses: Noah done; Sam cancelled (the question first), then reopened.
  await navLink(page, 'Today').click();
  await appointment(page, 'Noah Sample').click();
  await panel.getByRole('button', { name: 'Mark done' }).click();
  await expect(panel.getByTestId('detail-badges')).toContainText('Completed');
  await panel.getByRole('button', { name: 'Close' }).click();
  await appointment(page, 'Sam Sample').click();
  // Not started yet: no "Mark no-show", and the panel says when it will be.
  await expect(panel.getByRole('button', { name: 'Mark no-show' })).toHaveCount(0);
  await expect(panel.getByTestId('status-hint')).toContainText('You can mark a no-show once the appointment starts at 2:30 PM.');
  await panel.getByRole('button', { name: 'Cancel appointment' }).click();
  const cancel = page.getByTestId('confirm-cancel');
  await expect(cancel.getByRole('heading')).toHaveText("Cancel Sam Sample's appointment?");
  await cancel.getByRole('button', { name: 'Cancel appointment' }).click();
  await expect(panel.getByTestId('detail-badges')).toContainText('Cancelled');
  await panel.getByRole('button', { name: 'Reopen' }).click();
  await expect(panel.getByTestId('detail-badges')).toContainText('Booked');
  await panel.getByRole('button', { name: 'Close' }).click();

  // Kim didn't come to her 12 PM haircut: a no-show, and her card on file charged the agreed fee,
  // once Stripe is connected (the demo pretends that step).
  await appointment(page, 'Kim Sample').click();
  await panel.getByRole('button', { name: 'Mark no-show' }).click();
  await expect(panel.getByTestId('detail-badges')).toContainText('No-show');
  await expect(panel.getByTestId('status-changed')).toHaveText('Marked a no-show.');
  await expect(panel.getByTestId('status-changed')).toBeFocused();
  await panel.getByRole('button', { name: 'Charge no-show fee ($35)' }).click();
  const fee = page.getByTestId('confirm-fee');
  await expect(fee.getByRole('heading')).toHaveText(/^Charge \$35 to Kim Sample's (Visa|Mastercard) •••• 3875\?$/);
  await fee.getByRole('button', { name: 'Charge $35' }).click();
  // Said next to the fee's button, in sight, with the focus, and the way to Settings.
  const refused = panel.getByTestId('fee-error');
  await expect(refused).toContainText('Connect Stripe in Settings to take card payments.');
  await expect(refused).toBeFocused();
  await expectInSight(refused, 'why the fee wasn’t charged');
  await refused.getByRole('link', { name: 'Go to Settings' }).click();

  await expect(page.getByTestId('stripe-status')).toContainText('Not connected');
  await page.getByRole('button', { name: 'Connect Stripe' }).click();
  await expect(page.getByRole('button', { name: 'Connecting to Stripe (demo)…' })).toBeVisible();
  await expect(page.getByTestId('stripe-result')).toHaveText(
    "You're connected. You can take card payments now. This is the demo: no real Stripe account was connected.",
  );
  await expect(page.getByTestId('stripe-status')).toContainText('Connected · Izzy Clipz Barbershop');

  await navLink(page, 'Today').click();
  await appointment(page, 'Kim Sample').click();
  await panel.getByRole('button', { name: 'Charge no-show fee ($35)' }).click();
  await page.getByTestId('confirm-fee').getByRole('button', { name: 'Charge $35' }).click();
  await expect(panel.getByTestId('fee-status')).toContainText('No-show fee charged');
  await expect(panel.getByTestId('fee-status')).toContainText('$35 to');
  await expectAccessible(page, 'a charged fee');
  await shot(page, testInfo, 'b08-fee-charged', { panel: true });
  await panel.getByRole('button', { name: 'Close' }).click();

  // Sign out: the demo opens again with its one button.
  await signOutButton(page, testInfo).click();
  await page.getByTestId('sign-out-dialog').getByRole('button', { name: 'Sign out', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Open the Business demo' })).toBeVisible();

  // Nothing went to /api, from the pages, the service worker or anything else.
  expect(fromBrowser).toEqual([]);
  expect((await serverApiRequests(request)).slice(reachedServer)).toEqual([]);
});

test('products, no-show settings and computers work in the demo, and Reset brings the sample shop back', async ({ page, request }, testInfo) => {
  const fromBrowser = watchApi(page);
  const reachedServer = (await serverApiRequests(request)).length;
  await openDemo(page);
  const totalBefore = await page.getByTestId('sales-totals').textContent();

  // A product with a photo, kept in this browser.
  await navLink(page, 'Products').click();
  await expect(page.getByTestId('product')).toHaveCount(5);
  await page.getByRole('button', { name: 'Add a product' }).click();
  const editor = page.getByTestId('product-editor');
  await editor.getByLabel('Name').fill('Sample hair clay');
  await editor.getByLabel('Price', { exact: true }).fill('22');
  await editor.locator('input[type="file"]').setInputFiles({ name: 'clay.png', mimeType: 'image/png', buffer: PHOTO_PNG });
  await expect(editor.getByRole('img', { name: 'Photo of Sample hair clay' })).toBeVisible();
  await shot(page, testInfo, 'b10-product-editor', { panel: true });
  await editor.getByRole('button', { name: 'Add product' }).click();
  const card = page.getByTestId('product').filter({ hasText: 'Sample hair clay' });
  await expect(card).toContainText('$22');
  await expect(card.locator('img')).toHaveAttribute('src', /^data:image\/jpeg;base64,/);
  await expectAccessible(page, 'the demo’s Products');
  await shot(page, testInfo, 'b09-products');
  await card.getByRole('button', { name: 'Edit Sample hair clay' }).click();
  await editor.getByLabel('Price', { exact: true }).fill('24');
  await editor.getByRole('button', { name: 'Save changes' }).click();
  await expect(card).toContainText('$24');
  // Still there after a reload.
  await page.reload();
  await expect(page.getByTestId('product').filter({ hasText: 'Sample hair clay' })).toContainText('$24');

  // No-show protection saves.
  await navLink(page, 'Settings').click();
  const noShow = page.getByTestId('no-show-settings');
  await noShow.getByRole('checkbox', { name: 'No-show protection' }).check();
  await noShow.getByRole('button', { name: 'Save' }).click();
  await expect(noShow.getByTestId('no-show-saved')).toHaveText('Saved. New bookings use these settings.');
  await expectAccessible(page, 'the demo’s Settings');
  await shot(page, testInfo, 'b11-settings');

  // The other computer (a sample) signs out.
  const others = page.getByTestId('other-computers');
  await others.getByRole('button', { name: 'Sign out Safari on iPad (sample)' }).click();
  await page.getByTestId('confirm-sign-out-computer').getByRole('button', { name: 'Sign out', exact: true }).click();
  await expect(others).toContainText('No other computers are signed in.');

  // Reset: the sample shop as it started.
  await page.getByRole('button', { name: 'Reset the demo' }).click();
  await page.getByTestId('confirm-reset-demo').getByRole('button', { name: 'Reset the demo' }).click();
  await expect(page.getByTestId('demo-reset')).toBeVisible();
  await expect(page.getByTestId('no-show-settings').getByRole('checkbox', { name: 'No-show protection' })).not.toBeChecked();
  await navLink(page, 'Products').click();
  await expect(page.getByTestId('product')).toHaveCount(5);
  await navLink(page, 'Today').click();
  await expect(page.getByTestId('sales-totals')).toHaveText(totalBefore ?? '');

  expect(fromBrowser).toEqual([]);
  expect((await serverApiRequests(request)).slice(reachedServer)).toEqual([]);
});

test('installs as Izzy Clipz Business, with its own manifest and icons, and opens offline', async ({ page, request, context }, testInfo) => {
  await openDemo(page);
  await page.goto('/business/today?source=app');
  await expect(page.getByTestId('today-page')).toBeVisible();
  await expectBusinessInstallable(page, request);
  // The service worker keeps Business's page, and it opens without a connection (the demo needs none).
  await context.setOffline(true);
  await page.goto('/business/analytics');
  await expect(page.getByRole('heading', { level: 1, name: 'Analytics' })).toBeVisible();
  await expect(page.getByTestId('biz-offline')).toHaveText("You're offline. The demo still works: everything stays in this browser.");
  await expect(page.getByTestId('total-sales-value')).toBeVisible();
  if (!isPhone(testInfo)) await shot(page, testInfo, 'b12-offline');
  await context.setOffline(false);
});
