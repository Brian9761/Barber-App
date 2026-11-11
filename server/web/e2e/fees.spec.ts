import { randomBytes } from 'node:crypto';
import { mkdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import type { APIRequestContext, Page, TestInfo } from '@playwright/test';
import { navLink, ownerCall, ownerFetch, signInWithCode } from './business-support.js';
import {
  expect,
  expectAccessible,
  expectFits,
  expectStep,
  fillDetails,
  firstTime,
  isDemo,
  isPhone,
  manageToken,
  setProtection,
  settle,
  SHOTS_DIR,
  test,
} from './support.js';

// The fee rules the shop's Cancellation & No-Show Policy promises, on the real site
// (playwright.config.ts, the real API on PGlite) and in the demo (playwright.demo.config.ts),
// at a computer's size and a phone's:
//
// - A time already less than the cutoff away says so while it's picked, on Review and under
//   Book appointment, in the server's words, and cancelling it within 15 minutes of booking is
//   free (My appointments asks nothing about a fee, and neither does the server).
// - A flat fee over a service's price is capped at that price in the notice clients see and in
//   what they agree to.
// - Izzy Clipz Business offers "Mark no-show" for a booking with a card on file only once it
//   has ended, offers a charge until 7 days after the appointment and none after (saying why in
//   a plain line), never offers it for a visit that was completed and reopened (saying why in
//   the server's words, which the server also answers), and previews a flat fee capped at each
//   service's price, which clients "may be charged". The demo's in-browser API follows the same
//   rules, with no request.
//
// On the real site, bookings with a card are made through the API (a card saved on the e2e
// server's stand-in for Stripe's page) and moved back in time with /__e2e/appointments/move.
// The demo's clock is fixed at Wednesday, November 4, 2026, 12:30 PM in Oceanside (then 12:50 PM,
// once Kim Sample's 12 PM haircut is over), so its sample shop is the same every run. Screenshots go to E2E_LEGAL_SHOTS_DIR (or with the
// others), named "<run>-fees-…".

const LEGAL_SHOTS = resolve(process.env.E2E_LEGAL_SHOTS_DIR || SHOTS_DIR);
const ZONE = 'America/Los_Angeles';

/** What the screen shows now (or the whole page), as the owner or client sees it. */
async function view(page: Page, testInfo: TestInfo, name: string, options: { fullPage?: boolean } = {}): Promise<void> {
  mkdirSync(LEGAL_SHOTS, { recursive: true });
  await settle(page);
  await expectFits(page, name);
  await page.mouse.move(0, 0);
  // A whole page from the top, so the sticky nav is where a visitor first sees it.
  if (options.fullPage) await page.evaluate(() => window.scrollTo(0, 0));
  await page.screenshot({ path: join(LEGAL_SHOTS, `${testInfo.project.name}-fees-${name}.png`), fullPage: options.fullPage ?? false, animations: 'disabled' });
}

/** The shop's day ("2026-11-04") of an instant. */
function shopDate(instant: Date): string {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat('en-US', { timeZone: ZONE, year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(instant).map((p) => [p.type, p.value]),
  );
  return `${parts.year}-${parts.month}-${parts.day}`;
}

/** "2026-11-24": `days` after today, on the shop's calendar. */
function daysFromToday(days: number): string {
  return shopDate(new Date(Date.now() + days * 86_400_000));
}

// ------------------------------------------------------------ The real site

/** The barber each screen size books with, so the desktop and phone runs never take each other's times. */
function barberFor(testInfo: TestInfo): { id: string; name: string; offering: string } {
  return isPhone(testInfo)
    ? { id: 'carlos-rafael', name: 'Carlos', offering: 'carlos-rafael/9343fc67-b196-4604-987e-a4a9b6b4cc41' }
    : { id: 'israel-flores', name: 'Izzy', offering: 'israel-flores/0d069a9e-c5ea-4cca-ae34-3f38bf668940' };
}

interface Booked {
  id: string;
  start: string;
  end: string;
  createdAt: string;
}

/** A card saved on the stand-in for Stripe's page, as Review's "Add a card" does: its token. */
async function saveCard(request: APIRequestContext, offeringId: string): Promise<string> {
  const token = randomBytes(32).toString('base64url');
  const checkout = await request.post('/api/cards/checkout', { headers: { 'X-Card-Token': token }, data: { offeringId, returnTo: 'web' } });
  expect(checkout.ok(), await checkout.text()).toBe(true);
  const { sessionId } = (await checkout.json()) as { sessionId: string };
  // The client taps Save on Stripe's page (the stand-in), which sends them back to the server.
  const saved = await request.post(`/__e2e/stripe/${sessionId}/save`, { maxRedirects: 0 });
  expect(saved.status()).toBe(303);
  const card = await request.post('/api/cards', { headers: { 'X-Card-Token': token }, data: { sessionId } });
  expect(card.status(), await card.text()).toBe(201);
  return token;
}

/** A client's booking with that card, at the first free time `fromDay` (agreeing to the shop's policy as Review shows it). */
async function bookWithCard(request: APIRequestContext, offeringId: string, cardToken: string, client: { name: string; phone: string }, fromDay: string): Promise<Booked> {
  const policy = (await (await request.get(`/api/no-show-policy?offeringId=${encodeURIComponent(offeringId)}`)).json()) as { required: boolean; policyText: string };
  expect(policy.required).toBe(true);
  const availability = (await (await request.get(`/api/availability?offeringId=${encodeURIComponent(offeringId)}&from=${fromDay}&days=7`)).json()) as {
    days: { slots: { start: string }[] }[];
  };
  const start = availability.days.flatMap((d) => d.slots)[0]?.start;
  if (!start) throw new Error(`No free time from ${fromDay}`);
  const response = await request.post('/api/appointments', {
    headers: { 'X-Card-Token': cardToken, 'X-Manage-Token': manageToken() },
    data: { offeringId, start, customer: client, noShowPolicy: policy.policyText },
  });
  expect(response.status(), await response.text()).toBe(201);
  return ((await response.json()) as { appointment: Booked }).appointment;
}

/** Moves a booking back by whole days (its booking and consent times with it), as if it had been booked and had happened then. */
async function moveBack(request: APIRequestContext, booked: Booked, days: number): Promise<Booked> {
  const response = await request.post('/__e2e/appointments/move', { data: { id: booked.id, minutes: -days * 1440 } });
  expect(response.ok(), await response.text()).toBe(true);
  const by = (iso: string) => new Date(Date.parse(iso) - days * 86_400_000).toISOString();
  return { ...booked, start: by(booked.start), end: by(booked.end), createdAt: by(booked.createdAt) };
}

/** How many days back from its start a booking has to move to start `daysAgo` days before today (same time of day). */
function daysBackTo(booked: Booked, daysAgo: number): number {
  const day = shopDate(new Date(booked.start));
  return Math.round((Date.parse(`${day}T12:00:00Z`) - Date.parse(`${daysFromToday(0)}T12:00:00Z`)) / 86_400_000) + daysAgo;
}

/** Opens a booking's details in Izzy Clipz Business, on the day it's on. */
async function openInBusiness(page: Page, booked: Booked, name: string) {
  await page.goto(`/business/today?date=${shopDate(new Date(booked.start))}`);
  await page.getByTestId('appointment').filter({ hasText: name }).click();
  const panel = page.getByTestId('side-panel');
  await expect(panel.getByTestId('appointment-details')).toBeVisible();
  return panel;
}

test.describe('on the real site', () => {
  test.beforeEach(async ({}, testInfo) => {
    test.skip(isDemo(testInfo), 'The demo never asks for a card (no-show protection is off there); its Business rules are checked below.');
  });

  test('a time already inside the cancellation window says so in the server’s words, and cancelling within 15 minutes of booking is free', async ({
    page,
    request,
    phone,
  }, testInfo) => {
    const before = (await ownerCall<{ noShowSettings: Record<string, unknown> }>(request, 'GET', '/api/owner/no-show-settings')).noShowSettings;
    await setProtection(request, true);
    // A 48-hour cutoff, so whatever time is first free (bookings open 30 minutes ahead) is inside it.
    await ownerCall(request, 'PATCH', '/api/owner/no-show-settings', { lateCancelWindowMinutes: 2880 });
    try {
      const barber = barberFor(testInfo);
      await page.goto(`/book?barber=${barber.id}&service=haircut`);
      await expectStep(page, 3, 'Pick a day and time');
      const notice = page.getByTestId('fee-warning');
      // The shop's notice: it "may be charged".
      await expect(notice).toContainText('Cancelling less than 48 hours before your appointment, or not showing up, may be charged the full service price');
      await (await firstTime(page)).click();
      const inside = notice.locator('.notice__strong');
      await expect(inside).toHaveText(/^This time is less than 48 hours away, so cancelling it more than 15 minutes after booking may be charged \$\d+(\.\d\d)?\.$/);
      const line = (await inside.textContent())!;
      await expectAccessible(page, 'the times, with a time inside the cutoff');
      await inside.scrollIntoViewIfNeeded();
      await view(page, testInfo, '01-time-inside-window');

      await page.getByRole('button', { name: 'Continue' }).click();
      await expectStep(page, 4, 'Your details');
      await fillDetails(page, { name: 'Gracie Grace', phone });
      await page.getByRole('button', { name: 'Continue' }).click();
      await expectStep(page, 5, 'Review and book');
      await page.getByTestId('card-section').getByRole('button', { name: 'Add a card' }).click();
      await page.getByRole('button', { name: 'Save card' }).click();
      await expectStep(page, 5, 'Review and book');
      await expect(page.getByTestId('card-label')).toHaveText('Visa •••• 4242');
      // On Review, the same line in the notice and under Book appointment.
      await expect(page.getByTestId('fee-warning').locator('.notice__strong')).toHaveText(line);
      await expect(page.getByTestId('book-note')).toHaveText(`Nothing is charged now. ${line}`);
      await expectAccessible(page, 'Review, with a time inside the cutoff');
      await view(page, testInfo, '02-review-inside-window', { fullPage: true });
      await page.getByTestId('book-button').click();
      await expect(page.getByTestId('booked-title')).toHaveText("You're booked");

      // Changed their mind right away: within 15 minutes of booking it's free, past the cutoff or not.
      await page.getByRole('link', { name: 'Manage or cancel' }).click();
      const card = page.getByTestId('appointment-card');
      await card.getByRole('button', { name: 'Cancel appointment' }).click();
      const dialog = page.getByTestId('cancel-dialog');
      await expect(dialog).toBeVisible();
      await expect(dialog.getByTestId('late-cancel-warning')).toHaveCount(0);
      await view(page, testInfo, '03-cancel-within-15-minutes');
      const cancelled = page.waitForResponse((r) => r.url().includes('/cancel') && r.request().method() === 'POST');
      await page.getByTestId('confirm-cancel').click();
      // The server agrees: cancelled at once, without asking about a fee (no 409 late_cancel_fee).
      expect((await cancelled).status()).toBe(200);
      await expect(card.getByTestId('appointment-status')).toHaveText('Cancelled');
      await expect(page.getByTestId('cancel-dialog')).toBeHidden();
    } finally {
      await ownerCall(request, 'PATCH', '/api/owner/no-show-settings', before);
      await setProtection(request, false);
    }
  });

  test('Izzy Clipz Business: a no-show only after the end, nothing charged after 7 days, a completed visit never a no-show', async ({
    page,
    request,
    phone,
  }, testInfo) => {
    await setProtection(request, true);
    try {
      const barber = barberFor(testInfo);
      const token = await saveCard(request, barber.offering);
      // Names of their own on each screen size: both runs' bookings can land on the same day.
      const who = isPhone(testInfo) ? 'Phone' : 'Desk';
      const client = (name: string) => ({ name: `${name} ${who}`, phone });

      // Coming up: no "Mark no-show" until it has ended, and the panel says when.
      const upcoming = await bookWithCard(request, barber.offering, token, client('Ahead'), daysFromToday(20));
      // Over yesterday (the client didn't come): marked a no-show here, then the fee can be charged, until 7 days after.
      const missed = await bookWithCard(request, barber.offering, token, client('Missed'), daysFromToday(21));
      const yesterday = await moveBack(request, missed, daysBackTo(missed, 1));
      // Eight days ago, a no-show whose fee was never charged: too late now.
      const old = await bookWithCard(request, barber.offering, token, client('Late'), daysFromToday(22));
      const eightDaysAgo = await moveBack(request, old, daysBackTo(old, 8));
      await ownerCall(request, 'PATCH', `/api/owner/appointments/${eightDaysAgo.id}`, { status: 'noShow' });
      // Two days ago, a visit marked done, then reopened.
      const came = await bookWithCard(request, barber.offering, token, client('Came'), daysFromToday(23));
      const twoDaysAgo = await moveBack(request, came, daysBackTo(came, 2));
      await ownerCall(request, 'PATCH', `/api/owner/appointments/${twoDaysAgo.id}`, { status: 'completed' });

      await signInWithCode(page, request);

      let panel = await openInBusiness(page, upcoming, `Ahead ${who}`);
      await expect(panel.getByRole('button', { name: 'Mark no-show' })).toHaveCount(0);
      await expect(panel.getByTestId('status-hint')).toContainText('You can mark a no-show once the appointment ends on');
      await expect(panel.getByTestId('status-hint')).toContainText('Until it starts, the client can still cancel in the app.');
      await expect(panel.getByTestId('fee-status')).toHaveText(
        "If the client doesn't come, you can mark a no-show once the appointment has ended. Then you can charge the fee.",
      );
      await expectAccessible(page, 'a booking with a card on file, before its end');
      await view(page, testInfo, '04-business-before-the-end');

      panel = await openInBusiness(page, yesterday, `Missed ${who}`);
      await panel.getByRole('button', { name: 'Mark no-show' }).click();
      await expect(panel.getByTestId('status-changed')).toHaveText('Marked a no-show.');
      const charge = panel.getByRole('button', { name: /^Charge no-show fee \(\$\d+\)$/ });
      await expect(charge).toBeVisible();
      await expect(panel.getByTestId('fee-panel')).toContainText(/It can be charged until .+, 7 days after the appointment\./);
      await expectAccessible(page, 'a no-show fee that can be charged');
      await panel.getByTestId('fee-panel').scrollIntoViewIfNeeded();
      await view(page, testInfo, '05-business-charge-within-7-days');
      // Asked first, naming the card; not charged here (the stand-in for Stripe takes no payments).
      await charge.click();
      const confirm = page.getByTestId('confirm-fee');
      await expect(confirm.getByRole('heading')).toHaveText(new RegExp(`^Charge \\$\\d+ to Missed ${who}'s Visa •••• 4242\\?$`));
      await confirm.getByRole('button', { name: "Don't charge" }).click();

      panel = await openInBusiness(page, eightDaysAgo, `Late ${who}`);
      await expect(panel.getByTestId('fee-status')).toHaveText("It's more than 7 days after the appointment, so the fee can't be charged.");
      await expect(panel.getByTestId('fee-panel').getByRole('button')).toHaveCount(0);
      await expectAccessible(page, 'a fee past the 7 days');
      await panel.getByTestId('fee-panel').scrollIntoViewIfNeeded();
      await view(page, testInfo, '06-business-after-7-days');

      // Done, then reopened: it says first that it still can't become a no-show…
      panel = await openInBusiness(page, twoDaysAgo, `Came ${who}`);
      await panel.getByRole('button', { name: 'Reopen' }).click();
      const reopen = page.getByTestId('confirm-reopen');
      await expect(reopen).toContainText("It was marked done, so even once it's reopened, it can't be marked a no-show or charged a no-show fee: the client came.");
      await view(page, testInfo, '07-business-reopen-completed');
      await reopen.getByRole('button', { name: 'Reopen' }).click();
      await expect(panel.getByTestId('status-changed')).toHaveText('Reopened: it’s booked again.');
      // …and once it's reopened, after its end, "Mark no-show" isn't offered, nor a fee: the server's
      // owner view says it was completed (completedAt), and the panel says why in the server's words.
      const completedLine = "This appointment was marked completed, so it can't become a no-show.";
      await expect(panel.getByTestId('detail-badges')).toContainText('Booked');
      await expect(panel.getByRole('button', { name: 'Mark done' })).toBeVisible();
      await expect(panel.getByRole('button', { name: 'Mark no-show' })).toHaveCount(0);
      await expect(panel.getByTestId('status-hint')).toContainText(completedLine);
      await expect(panel.getByTestId('fee-status')).toHaveText(completedLine);
      await expect(panel.getByTestId('fee-panel').getByRole('button')).toHaveCount(0);
      await expect(panel).not.toContainText('Then you can charge the fee');
      await expectAccessible(page, 'a visit that was completed, reopened');
      await panel.getByTestId('fee-panel').scrollIntoViewIfNeeded();
      await view(page, testInfo, '07b-business-reopened-completed');
      // The server refuses it all the same.
      const refused = await ownerFetch(request, 'PATCH', `/api/owner/appointments/${twoDaysAgo.id}`, { status: 'noShow' });
      expect(refused.status()).toBe(409);
      expect((await refused.json()).error).toEqual({ code: 'already_completed', message: completedLine });
    } finally {
      await setProtection(request, false);
    }
  });

  test('clients see a flat fee capped at the price of what they book, in the notice and in what they agree to', async ({ page, request, phone }, testInfo) => {
    const before = (await ownerCall<{ noShowSettings: Record<string, unknown> }>(request, 'GET', '/api/owner/no-show-settings')).noShowSettings;
    await setProtection(request, true);
    // A $25 flat fee, with the usual 1-hour cutoff.
    await ownerCall(request, 'PATCH', '/api/owner/no-show-settings', { feeMode: 'flat', flatCents: 2500, lateCancelEnabled: true, lateCancelWindowMinutes: 60 });
    try {
      // Carlos's $5 hot lather shave: $5, never the $25.
      await page.goto('/book?barber=carlos-rafael&service=hot-lather-shave');
      await expectStep(page, 3, 'Pick a day and time');
      const notice = page.getByTestId('fee-warning');
      await expect(notice.locator('.notice__title')).toHaveText('Late Cancellation & No-Show Fee');
      await expect(notice).toContainText(
        'Cancelling less than 1 hour before your appointment, or not showing up, may be charged $5. Cancelling in the app more than 1 hour before is free.',
      );
      await (await firstTime(page)).click();
      await expect(notice).not.toContainText('$25');
      await page.getByRole('button', { name: 'Continue' }).click();
      await expectStep(page, 4, 'Your details');
      await fillDetails(page, { name: 'Shea Shave', phone });
      await page.getByRole('button', { name: 'Continue' }).click();
      await expectStep(page, 5, 'Review and book');
      await expect(page.getByTestId('fee-warning')).toContainText('may be charged $5.');
      await expect(page.getByTestId('fee-warning')).not.toContainText('$25');
      // What they agree to by booking: the same $5.
      await expect(page.getByTestId('card-section')).toContainText(
        "No payment now. If you cancel less than 1 hour before your appointment, or don't come, Izzy Clipz may charge $5 to this card. Cancelling in the app more than 1 hour before is free.",
      );
      await expectAccessible(page, 'Review, with a flat fee capped at the price');
      await page.getByTestId('fee-warning').scrollIntoViewIfNeeded();
      await view(page, testInfo, '09-review-flat-fee-capped');
    } finally {
      await ownerCall(request, 'PATCH', '/api/owner/no-show-settings', before);
      await setProtection(request, false);
    }
  });

  test('Izzy Clipz Business previews a flat fee capped at each service’s price, which clients may be charged', async ({ page, request }, testInfo) => {
    const before = (await ownerCall<{ noShowSettings: Record<string, unknown> }>(request, 'GET', '/api/owner/no-show-settings')).noShowSettings;
    try {
      await signInWithCode(page, request);
      await navLink(page, 'Settings').click();
      const section = page.getByTestId('no-show-settings');
      await section.getByRole('checkbox', { name: 'No-show protection' }).check();
      await section.getByRole('radio', { name: 'Flat amount' }).check();
      await section.getByLabel('Flat fee').fill('25');
      await expect(section).toContainText("never more than the service's price");
      // $25 on a $5 shave is $5: the same as the server charges it.
      await expect(section.locator('.biz-example')).toContainText('A $40 haircut: $25');
      await expect(section.locator('.biz-example')).toContainText('A $5 hot lather shave: $5');
      await expect(section.locator('.biz-client-view')).toContainText('or not showing up, may be charged $25.');
      await expect(section).toContainText('Cancelling earlier, or within 15 minutes of booking, is free');
      await expectAccessible(page, 'the no-show settings with a flat fee');
      await section.locator('.biz-example').scrollIntoViewIfNeeded();
      await view(page, testInfo, '08-business-settings-fee-cap');
    } finally {
      await ownerCall(request, 'PATCH', '/api/owner/no-show-settings', before);
    }
  });
});

// ------------------------------------------------------------------ The demo

const NOON_THIRTY = new Date('2026-11-04T20:30:00Z');
/** Once Kim Sample's 12 PM haircut (12 to 12:45) is over. */
const TWELVE_FIFTY = new Date('2026-11-04T20:50:00Z');

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

test.describe('in the demo', () => {
  test.beforeEach(async ({}, testInfo) => {
    test.skip(!isDemo(testInfo), 'The demo’s own rules: its in-browser API');
  });

  test('Izzy Clipz Business follows the same rules: a no-show after the end, a completed visit never one, nothing after 7 days, a flat fee capped', async ({
    page,
    request,
  }, testInfo) => {
    const fromBrowser = watchApi(page);
    const reachedServer = (await serverApiRequests(request)).length;
    await page.clock.setFixedTime(NOON_THIRTY);
    await page.goto('/business');
    await page.getByRole('button', { name: 'Open the Business demo' }).click();
    await expect(page).toHaveURL(/\/business\/today$/);
    const panel = page.getByTestId('side-panel');

    // Kim Sample's 12 PM haircut, with a card on file, runs to 12:45: she may still come.
    await page.getByTestId('appointment').filter({ hasText: 'Kim Sample' }).click();
    await expect(panel.getByRole('button', { name: 'Mark no-show' })).toHaveCount(0);
    await expect(panel.getByTestId('status-hint')).toContainText(
      "You can mark a no-show once the appointment ends at 12:45 PM. A client who comes before then isn't a no-show.",
    );
    await expectAccessible(page, 'the demo: a no-show only after the end');
    await view(page, testInfo, '04-business-before-the-end');
    await panel.getByRole('button', { name: 'Close' }).click();

    // At 12:50 she hasn't come: a no-show, whose fee can be charged until 7 days after the appointment.
    await page.clock.setFixedTime(TWELVE_FIFTY);
    await page.reload();
    await page.getByTestId('appointment').filter({ hasText: 'Kim Sample' }).click();
    await panel.getByRole('button', { name: 'Mark no-show' }).click();
    await expect(panel.getByTestId('status-changed')).toHaveText('Marked a no-show.');
    await expect(panel.getByRole('button', { name: 'Charge no-show fee ($35)' })).toBeVisible();
    await expect(panel.getByTestId('fee-panel')).toContainText('It can be charged until Wed, Nov 11 at 12 PM, 7 days after the appointment.');
    await expectAccessible(page, 'the demo: a no-show fee that can be charged');
    await panel.getByTestId('fee-panel').scrollIntoViewIfNeeded();
    await view(page, testInfo, '05-business-charge-within-7-days');

    // Reopened and marked done after all: even reopened again, the visit never becomes a no-show.
    await panel.getByRole('button', { name: 'Reopen' }).click();
    await expect(panel.getByTestId('status-changed')).toHaveText('Reopened: it’s booked again.');
    await panel.getByRole('button', { name: 'Mark done' }).click();
    await expect(panel.getByTestId('status-changed')).toHaveText('Marked done.');
    await panel.getByRole('button', { name: 'Reopen' }).click();
    const reopen = page.getByTestId('confirm-reopen');
    await expect(reopen).toContainText("It was marked done, so even once it's reopened, it can't be marked a no-show or charged a no-show fee: the client came.");
    await view(page, testInfo, '07-business-reopen-completed');
    await reopen.getByRole('button', { name: 'Reopen' }).click();
    await expect(panel.getByTestId('status-changed')).toHaveText('Reopened: it’s booked again.');
    // Reopened after its end: no "Mark no-show", no fee, and why, in the server's words.
    const completedLine = "This appointment was marked completed, so it can't become a no-show.";
    await expect(panel.getByTestId('detail-badges')).toContainText('Booked');
    await expect(panel.getByRole('button', { name: 'Mark no-show' })).toHaveCount(0);
    await expect(panel.getByTestId('status-hint')).toContainText(completedLine);
    await expect(panel.getByTestId('fee-status')).toHaveText(completedLine);
    await expect(panel.getByTestId('fee-panel').getByRole('button')).toHaveCount(0);
    await expect(panel).not.toContainText('Then you can charge the fee');
    await expectAccessible(page, 'the demo: a visit that was completed, reopened');
    await panel.getByTestId('fee-panel').scrollIntoViewIfNeeded();
    await view(page, testInfo, '07b-business-reopened-completed');
    // Still so after a reload: the demo's stand-in keeps when it was first completed.
    await page.reload();
    await page.getByTestId('appointment').filter({ hasText: 'Kim Sample' }).click();
    await expect(panel.getByRole('button', { name: 'Mark no-show' })).toHaveCount(0);
    await expect(panel.getByTestId('fee-status')).toHaveText(completedLine);
    await panel.getByRole('button', { name: 'Close' }).click();

    // A late cancellation two weeks ago whose fee was never charged: too late now.
    await page.goto('/business/today?date=2026-10-20');
    await page.getByTestId('appointment').filter({ hasText: 'Oscar Sample' }).filter({ hasText: 'Cancelled late' }).click();
    await expect(panel.getByTestId('fee-status')).toHaveText("It's more than 7 days after the appointment, so the fee can't be charged.");
    await expect(panel.getByTestId('fee-panel').getByRole('button')).toHaveCount(0);
    await expectAccessible(page, 'the demo: a fee past the 7 days');
    await panel.getByTestId('fee-panel').scrollIntoViewIfNeeded();
    await view(page, testInfo, '06-business-after-7-days');
    await panel.getByRole('button', { name: 'Close' }).click();

    // Settings: a $25 flat fee is $5 on a $5 shave.
    await navLink(page, 'Settings').click();
    const section = page.getByTestId('no-show-settings');
    await section.getByRole('checkbox', { name: 'No-show protection' }).check();
    await section.getByRole('radio', { name: 'Flat amount' }).check();
    await section.getByLabel('Flat fee').fill('25');
    await expect(section.locator('.biz-example')).toContainText('A $5 hot lather shave: $5');
    await expect(section.locator('.biz-client-view')).toContainText('may be charged $25.');
    await section.locator('.biz-example').scrollIntoViewIfNeeded();
    await view(page, testInfo, '08-business-settings-fee-cap');

    expect(fromBrowser).toEqual([]);
    expect((await serverApiRequests(request)).slice(reachedServer)).toEqual([]);
  });

  test('"Forget me" asks the demo’s own stand-in to delete a saved card’s key, with no request, and forgets it', async ({ page, request }, testInfo) => {
    test.skip(isPhone(testInfo), 'Once is enough');
    const fromBrowser = watchApi(page);
    const reachedServer = (await serverApiRequests(request)).length;
    await page.goto('/');
    // The demo never saves a card; this browser holds a key anyway (say, from the real site at this address).
    await page.evaluate(() =>
      localStorage.setItem(
        'izzy.card.v1',
        JSON.stringify({ token: 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE', card: { brand: 'visa', last4: '4242', expMonth: 12, expYear: 2030 }, phone: '+17605550100' }),
      ),
    );
    await page.goto('/appointments');
    await page.getByRole('button', { name: 'Forget me on this computer' }).click();
    await page.getByTestId('confirm-forget').click();
    await expect(page.getByTestId('forgotten-notice')).toHaveText("Done. This computer no longer keeps your details, the demo's bookings or Izzy Clipz Business's sample shop. The copies of the site's own pages stay, so it still works offline.");
    expect(await page.evaluate(() => localStorage.getItem('izzy.card.v1') ?? sessionStorage.getItem('izzy.card.v1'))).toBeNull();
    // Nothing more to say (no card behind the key), and nothing went to /api.
    await expect(page.getByTestId('card-removal')).toHaveCount(0);
    expect(fromBrowser).toEqual([]);
    expect((await serverApiRequests(request)).slice(reachedServer)).toEqual([]);
  });
});
