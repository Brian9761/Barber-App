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
  if (client.remember && !(await remember.isChecked())) await remember.check();
  if (client.remember === false && (await remember.isChecked())) await remember.uncheck();
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

    await page.getByTestId('book-button').click();
    await expect(page.getByTestId('booked-title')).toHaveText("You're booked");
    await expect(page.getByTestId('booked-summary')).toContainText('Visa •••• 4242');
    await expect(page.getByTestId('booked-summary')).toContainText('Carlos');
    await screenshot(page, testInfo, '25-book-6-confirmed-with-card');
    // "Remember me" was off: the card is gone from this browser once it's booked.
    expect(await page.evaluate(() => window.sessionStorage.getItem('izzy.card.v1') ?? window.localStorage.getItem('izzy.card.v1'))).toBeNull();

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

  test('on a shared computer, the next client never books with the last one’s card', async ({ page, phone, request }, testInfo) => {
    test.skip(!(await returnsToWebsite(request)), NO_WEB_RETURN);
    // Alex asks to be remembered and adds a card.
    await toReview(page, testInfo, { name: 'Alex Ames', phone, remember: true });
    await page.getByTestId('card-section').getByRole('button', { name: 'Add a card' }).click();
    await page.getByRole('button', { name: 'Save card' }).click();
    await expect(page.getByTestId('card-label')).toHaveText('Visa •••• 4242');
    await page.getByTestId('book-button').click();
    await expect(page.getByTestId('booked-title')).toHaveText("You're booked");

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
    await screenshot(page, testInfo, '28-book-4-details-not-you');
    await fillDetails(page, { name: 'Bea Bell', phone: phone.replace(/\d$/, (d) => String((Number(d) + 1) % 10)) });
    await page.getByRole('button', { name: 'Continue' }).click();
    await expectStep(page, 5, 'Review and book');
    await expect(page.getByTestId('card-section')).toContainText('This time needs a card on file to hold it.');
    await expect(page.getByTestId('card-label')).toHaveCount(0);
    await expect(page.getByTestId('book-button')).toBeDisabled();
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
