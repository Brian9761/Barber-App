import type { APIRequestContext, Page, TestInfo } from '@playwright/test';
import { detailsFields, expect, expectAccessible, expectStep, fillDetails, firstTime, screenshot, setProtection, test } from './support.js';

// With the shop's no-show protection on, a booking needs a card on file. The
// end-to-end server has no Stripe key: serve.ts turns protection on with a
// stand-in for Stripe's card page, whose Save and Back go where the server told
// Stripe to send the client (success_url and cancel_url). On a server that
// sends Stripe's page back to the website (returnTo "web"), that's
// /api/cards/return…&to=web, then /book/card-return; a server without that way
// back sends it to the iPhone app, and the tests of coming back are skipped.

const NO_WEB_RETURN =
  'This server sends Stripe’s card page back only to the iPhone app: the way back to the website (returnTo "web", /api/cards/return?…&to=web) comes with the server’s Stripe Connect and computers work.';

/** Whether this server sends Stripe's card page back to the website, asked of its own /api/cards/cancel. */
async function returnsToWebsite(request: APIRequestContext): Promise<boolean> {
  const response = await request.get('/__e2e/card-return');
  expect(response.ok()).toBe(true);
  return ((await response.json()) as { web: boolean }).web;
}

interface CardState {
  found: boolean;
  deleteRequested: boolean;
  removed: boolean;
  deletedAtStripe: boolean;
}

/** What became of the card saved under `token`, at the server and at the stand-in for Stripe (serve.ts). */
async function cardState(request: APIRequestContext, token: string): Promise<CardState> {
  const response = await request.get(`/__e2e/card?token=${encodeURIComponent(token)}`);
  expect(response.ok()).toBe(true);
  return (await response.json()) as CardState;
}

/** The token of the card this browser keeps (with Remember me, or for this visit). */
async function keptCardToken(page: Page): Promise<string> {
  const token = await page.evaluate(() => {
    const kept = window.localStorage.getItem('izzy.card.v1') ?? window.sessionStorage.getItem('izzy.card.v1');
    return kept ? (JSON.parse(kept) as { token: string }).token : null;
  });
  expect(token).toMatch(/^[A-Za-z0-9_-]{43}$/);
  return token!;
}

/** Adds a card on the stand-in for Stripe's page, back at Review with it. */
async function addCard(page: Page): Promise<void> {
  await page.getByTestId('card-section').getByRole('button', { name: 'Add a card' }).click();
  await expect(page.getByRole('heading', { name: 'Test card page' })).toBeVisible();
  await page.getByRole('button', { name: 'Save card' }).click();
  await expectStep(page, 5, 'Review and book');
  await expect(page.getByTestId('card-label')).toHaveText('Visa •••• 4242');
}

/**
 * Carlos's haircut on the first open day next month (well outside the late-cancellation
 * window) for `name`, up to Review. Screenshots of the fee notice and of Review with `shots`.
 */
async function toReview(page: Page, testInfo: TestInfo, client: { name: string; phone: string; remember?: boolean }, shots = false): Promise<void> {
  await page.goto('/book?barber=carlos-rafael&service=haircut');
  // Carlos has one haircut, so it goes straight to the times.
  await expectStep(page, 3, 'Pick a day and time');
  const notice = page.getByTestId('fee-warning');
  await expect(notice).toContainText('Full Service Cancellation & No-Show Fee');
  await expect(notice).toContainText('charged the full service price');
  await expect(notice).toContainText('Cancelling on this website, under My appointments, works the same as cancelling in the app.');

  const month = page.getByTestId('calendar-month');
  const thisMonth = await month.innerText();
  await page.getByRole('button', { name: 'Next month' }).click();
  await expect(month).not.toHaveText(thisMonth);
  const nextMonth = (await month.innerText()).split(' ')[0]!;
  await expect(page.locator('.times__day')).toContainText(nextMonth);
  await (await firstTime(page)).click();
  if (shots) {
    await expectAccessible(page, 'step 3 with the fee notice');
    await screenshot(page, testInfo, '22-book-3-time-fee-notice');
  }
  await page.getByRole('button', { name: 'Continue' }).click();

  await expectStep(page, 4, 'Your details');
  await fillDetails(page, client);
  const remember = detailsFields(page).remember;
  if (client.remember !== undefined && (await remember.isChecked()) !== client.remember) {
    // The label covers the box, so a click anywhere on it ticks it, as a visitor would.
    await page.locator('label.checkbox__label').click();
    await expect(remember).toBeChecked({ checked: client.remember });
  }
  await page.getByRole('button', { name: 'Continue' }).click();
  await expectStep(page, 5, 'Review and book');
}

test.describe('with no-show protection on', () => {
  test.beforeAll(async ({ request }) => setProtection(request, true));
  test.afterAll(async ({ request }) => setProtection(request, false));

  test('the fee notice shows, and Review waits for a card from Stripe’s page', async ({ page, phone }, testInfo) => {
    await toReview(page, testInfo, { name: 'Casey Card', phone }, true);

    // Review: the notice, what the client agrees to, and Book waits for a card.
    await expect(page.getByTestId('fee-warning')).toBeVisible();
    const cardSection = page.getByTestId('card-section');
    await expect(cardSection).toContainText('This time needs a card on file to hold it. Nothing is charged now.');
    await expect(cardSection).toContainText('What you agree to by booking');
    await expect(page.getByTestId('book-button')).toBeDisabled();
    await expect(page.getByTestId('book-note')).toHaveText('Add a card first to book this time.');
    await expectAccessible(page, 'step 5 needing a card');
    await screenshot(page, testInfo, '23-book-5-review-card-needed');

    // "Add a card" opens Stripe's page (the stand-in here), with the booking kept in this tab.
    await cardSection.getByRole('button', { name: 'Add a card' }).click();
    await expect(page.getByRole('heading', { name: 'Test card page' })).toBeVisible();
    const kept = await page.evaluate(() => JSON.parse(window.sessionStorage.getItem('izzy.cardCheckout.v1') ?? 'null'));
    expect(kept).toMatchObject({ remember: false, sessionId: expect.stringMatching(/^cs_test_/) });
  });

  test('a card added on Stripe’s page holds the booking', async ({ page, phone, request }, testInfo) => {
    test.skip(!(await returnsToWebsite(request)), NO_WEB_RETURN);
    await toReview(page, testInfo, { name: 'Casey Card', phone });
    const cardSection = page.getByTestId('card-section');

    // Going back from Stripe's page without a card says so, through the server's /api/cards/cancel.
    await cardSection.getByRole('button', { name: 'Add a card' }).click();
    await expect(page.getByRole('heading', { name: 'Test card page' })).toBeVisible();
    await page.getByRole('button', { name: 'Back' }).click();
    await expectStep(page, 5, 'Review and book');
    await expect(cardSection).toContainText("Your card wasn't added. Add a card to book this time.");

    // Saving it comes back through the server's /api/cards/return to Review, with the card.
    await cardSection.getByRole('button', { name: 'Add a card' }).click();
    await expect(page.getByRole('heading', { name: 'Test card page' })).toBeVisible();
    await page.getByRole('button', { name: 'Save card' }).click();
    await expectStep(page, 5, 'Review and book');
    await expect(page.getByTestId('card-label')).toHaveText('Visa •••• 4242');
    await expect(cardSection.getByRole('button', { name: 'Change card' })).toBeVisible();
    await expect(page.getByText('Casey Card')).toBeVisible();
    await expect(page.getByTestId('book-button')).toBeEnabled();
    // Until when cancelling is free, never "any time" when a fee applies.
    await expect(page.getByTestId('book-note')).toContainText('Nothing is charged now. Cancelling online is free until');
    await expectAccessible(page, 'step 5 with a card');
    await screenshot(page, testInfo, '24-book-5-review-card-added');

    const token = await keptCardToken(page);
    const deleted = page.waitForResponse((r) => r.url().endsWith('/api/cards') && r.request().method() === 'DELETE');
    await page.getByTestId('book-button').click();
    await expect(page.getByTestId('booked-title')).toHaveText("You're booked");
    await expect(page.getByTestId('booked-summary')).toContainText('Visa •••• 4242');
    await expect(page.getByTestId('booked-summary')).toContainText('Carlos');
    await screenshot(page, testInfo, '25-book-6-confirmed-with-card');
    // "Remember me" was off: the card is gone from this browser once it's booked, and the shop is
    // asked to delete it: it keeps it only while this booking can still be charged ("scheduled").
    expect(await page.evaluate(() => window.sessionStorage.getItem('izzy.card.v1') ?? window.localStorage.getItem('izzy.card.v1'))).toBeNull();
    const answer = await deleted;
    expect(answer.status()).toBe(200);
    expect(await answer.json()).toEqual({
      cardDeletion: { status: 'scheduled', message: 'Your card will be deleted as soon as your appointments no longer need it.' },
    });
    expect(await cardState(request, token)).toMatchObject({ found: true, deleteRequested: true, removed: false });

    await page.getByRole('link', { name: 'Manage or cancel' }).click();
    const card = page.getByTestId('appointment-card');
    await expect(card).toContainText('Card on file: Visa •••• 4242');
    await screenshot(page, testInfo, '26-appointments-with-card');

    // Days away, cancelling is free: no warning.
    await card.getByRole('button', { name: 'Cancel appointment' }).click();
    await expect(page.getByTestId('cancel-dialog').getByTestId('late-cancel-warning')).toHaveCount(0);
    await page.getByTestId('confirm-cancel').click();
    await expect(card.getByTestId('appointment-status')).toHaveText('Cancelled');
  });

  test('a card added without “Remember me” is for that booking only, even if the connection drops right after booking', async ({
    page,
    phone,
    request,
    browserConsole,
  }, testInfo) => {
    test.skip(!(await returnsToWebsite(request)), NO_WEB_RETURN);
    browserConsole.allow(/Failed to load resource|ERR_FAILED/);
    await toReview(page, testInfo, { name: 'Dee Dropped', phone, remember: false });
    await addCard(page);
    const token = await keptCardToken(page);
    // The connection is lost as soon as the booking is made: the request asking the shop to delete
    // the card never gets there (both tries).
    let deletesTried = 0;
    await page.route('**/api/cards', (route) => {
      if (route.request().method() !== 'DELETE') return route.fallback();
      deletesTried += 1;
      return route.abort('failed');
    });
    const booked = page.waitForRequest((r) => r.url().endsWith('/api/appointments') && r.method() === 'POST');
    await page.getByTestId('book-button').click();
    await expect(page.getByTestId('booked-title')).toHaveText("You're booked");
    // The booking itself said the card was for it only…
    expect((await booked).postDataJSON()).toMatchObject({ keepCard: false });
    await expect.poll(() => deletesTried).toBe(2);
    // …so the shop has it marked for deletion all the same: kept only while this booking can be
    // charged, then deleted. And this browser keeps no key to it.
    expect(await cardState(request, token)).toMatchObject({ found: true, deleteRequested: true, removed: false });
    expect(await page.evaluate(() => window.sessionStorage.getItem('izzy.card.v1') ?? window.localStorage.getItem('izzy.card.v1'))).toBeNull();
  });

  test('on a shared computer, the next client never books with the last one’s card', async ({ page, phone, request }, testInfo) => {
    test.skip(!(await returnsToWebsite(request)), NO_WEB_RETURN);
    // Alex asks to be remembered and adds a card.
    await toReview(page, testInfo, { name: 'Alex Ames', phone, remember: true });
    await addCard(page);
    const alexCard = await keptCardToken(page);
    await page.getByTestId('book-button').click();
    await expect(page.getByTestId('booked-title')).toHaveText("You're booked");
    // Remembered: kept here, and at the shop.
    expect(await cardState(request, alexCard)).toMatchObject({ found: true, deleteRequested: false, removed: false });

    // Bea, at the same computer: Alex's details are offered with "Not you?", and Alex's card isn't hers.
    await page.goto('/book?barber=carlos-rafael&service=haircut');
    await expectStep(page, 3, 'Pick a day and time');
    await page.getByRole('button', { name: 'Next month' }).click();
    await (await firstTime(page)).click();
    await page.getByRole('button', { name: 'Continue' }).click();
    await expectStep(page, 4, 'Your details');
    await expect(page.getByTestId('remembered-note')).toContainText('Welcome back, Alex.');
    await page.getByRole('button', { name: 'Not you? Forget me on this computer' }).click();
    await expect(detailsFields(page).name).toHaveValue('');
    await expect(detailsFields(page).remember).not.toBeChecked();
    // Alex's card is gone from here, and the shop deletes it once his appointment no longer needs it.
    await expect(page.getByTestId('card-removal')).toHaveText(
      'The shop will delete the saved card as soon as the appointments booked with it no longer need it.',
    );
    expect(await cardState(request, alexCard)).toMatchObject({ found: true, deleteRequested: true, removed: false });
    await screenshot(page, testInfo, '28-book-4-details-not-you');
    await fillDetails(page, { name: 'Bea Bell', phone: phone.replace(/\d$/, (d) => String((Number(d) + 1) % 10)) });
    await page.getByRole('button', { name: 'Continue' }).click();
    await expectStep(page, 5, 'Review and book');
    await expect(page.getByTestId('card-section')).toContainText('This time needs a card on file to hold it.');
    await expect(page.getByTestId('card-label')).toHaveCount(0);
    await expect(page.getByTestId('book-button')).toBeDisabled();
  });
});

test.describe('removing a saved card', () => {
  test.beforeAll(async ({ request }) => setProtection(request, true));
  test.afterAll(async ({ request }) => setProtection(request, false));

  test('“Forget me” deletes a card no booking needs, at Stripe too, and says so', async ({ page, phone, request }, testInfo) => {
    test.skip(!(await returnsToWebsite(request)), NO_WEB_RETURN);
    // Dana asks to be remembered and adds a card, then doesn't book after all.
    await toReview(page, testInfo, { name: 'Dana Drew', phone, remember: true });
    await addCard(page);
    const token = await keptCardToken(page);
    await page.goto('/appointments');
    await page.getByRole('button', { name: /^Forget me on this (computer|phone)$/ }).click();
    await expect(page.getByTestId('forget-dialog')).toContainText('The shop also deletes the saved card, as soon as no appointment needs it.');
    await page.getByTestId('confirm-forget').click();
    await expect(page.getByTestId('card-removal')).toHaveText("Your saved card is deleted. It can't be charged any more.");
    expect(await page.evaluate(() => window.localStorage.getItem('izzy.card.v1') ?? window.sessionStorage.getItem('izzy.card.v1'))).toBeNull();
    expect(await cardState(request, token)).toMatchObject({ found: true, removed: true, deletedAtStripe: true });
    await expectAccessible(page, 'My appointments after Forget me');
    await screenshot(page, testInfo, '29-appointments-forget-me-card-deleted');
  });

  test('“Forget me” forgets the card here even when the shop can’t be reached, and says to call', async ({ page, phone, request, browserConsole }, testInfo) => {
    test.skip(!(await returnsToWebsite(request)), NO_WEB_RETURN);
    browserConsole.allow(/Failed to load resource|ERR_FAILED/);
    await toReview(page, testInfo, { name: 'Evan Ellis', phone, remember: true });
    await addCard(page);
    const token = await keptCardToken(page);
    await page.route('**/api/cards', (route) => (route.request().method() === 'DELETE' ? route.abort('failed') : route.fallback()));
    await page.goto('/appointments');
    await page.getByRole('button', { name: /^Forget me on this (computer|phone)$/ }).click();
    await page.getByTestId('confirm-forget').click();
    await expect(page.getByTestId('card-removal')).toHaveText(
      "We couldn't reach the shop to delete your saved card. To have it removed, call the shop at (442) 341-3053.",
    );
    expect(await page.evaluate(() => window.localStorage.getItem('izzy.card.v1') ?? window.sessionStorage.getItem('izzy.card.v1'))).toBeNull();
    // The shop still has it, as the page says.
    expect(await cardState(request, token)).toMatchObject({ found: true, deleteRequested: false, removed: false });
  });
});

test('coming back from the card page without the booking says what to do', async ({ page }, testInfo) => {
  await page.goto('/book/card-return?status=saved&session_id=cs_test_e2eUnknown');
  await expect(page.getByRole('heading', { level: 1, name: "Your card wasn't added" })).toBeVisible();
  await expect(page.getByText('This browser lost track of the card you were adding.')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Back to your booking' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Try again' })).toHaveCount(0);
  await expectAccessible(page, 'the card return without a booking');
  await screenshot(page, testInfo, '27-card-return-problem');
});
