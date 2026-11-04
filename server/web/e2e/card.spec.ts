import { expect, expectAccessible, expectStep, fillDetails, firstTime, screenshot, setProtection, test } from './support.js';

// With the shop's no-show protection on, a booking needs a card on file. The
// end-to-end server has no Stripe key: serve.ts turns protection on with a
// stand-in for Stripe's card page, which sends the browser back to
// /book/card-return the way the server does for the website (returnTo "web").

test.describe('with no-show protection on', () => {
  test.beforeAll(async ({ request }) => setProtection(request, true));
  test.afterAll(async ({ request }) => setProtection(request, false));

  test('the fee notice shows, and a card added on Stripe’s page holds the booking', async ({ page, phone }, testInfo) => {
    await page.goto('/book?barber=carlos-rafael&service=haircut');
    // Carlos has one haircut, so it goes straight to the times.
    await expectStep(page, 3, 'Pick a day and time');
    const notice = page.getByTestId('fee-warning');
    await expect(notice).toContainText('Full Service Cancellation & No-Show Fee');
    await expect(notice).toContainText('charged the full service price');

    // Next month, so the time is well outside the late-cancellation window.
    const month = page.getByTestId('calendar-month');
    const thisMonth = await month.innerText();
    await page.getByRole('button', { name: 'Next month' }).click();
    await expect(month).not.toHaveText(thisMonth);
    const nextMonth = (await month.innerText()).split(' ')[0]!;
    await expect(page.locator('.times__day')).toContainText(nextMonth);
    const time = await firstTime(page);
    await time.click();
    await expectAccessible(page, 'step 3 with the fee notice');
    await screenshot(page, testInfo, '22-book-3-time-fee-notice');
    await page.getByRole('button', { name: 'Continue' }).click();

    await expectStep(page, 4, 'Your details');
    await fillDetails(page, { name: 'Casey Card', phone });
    await page.getByRole('button', { name: 'Continue' }).click();

    // Review: the notice, what the client agrees to, and Book waits for a card.
    await expectStep(page, 5, 'Review and book');
    await expect(page.getByTestId('fee-warning')).toBeVisible();
    const cardSection = page.getByTestId('card-section');
    await expect(cardSection).toContainText('This time needs a card on file to hold it. Nothing is charged now.');
    await expect(cardSection).toContainText('What you agree to by booking');
    await expect(page.getByTestId('book-button')).toBeDisabled();
    await expect(page.getByText('Add a card first to book this time.')).toBeVisible();
    await expectAccessible(page, 'step 5 needing a card');
    await screenshot(page, testInfo, '23-book-5-review-card-needed');

    // Going back from Stripe's page without a card says so.
    await cardSection.getByRole('button', { name: 'Add a card' }).click();
    await expect(page.getByRole('heading', { name: 'Test card page' })).toBeVisible();
    await page.getByRole('button', { name: 'Back' }).click();
    await expectStep(page, 5, 'Review and book');
    await expect(cardSection).toContainText("Your card wasn't added. Add a card to book this time.");

    // Saving it comes back to Review with the card, and the booking was kept.
    await cardSection.getByRole('button', { name: 'Add a card' }).click();
    await expect(page.getByRole('heading', { name: 'Test card page' })).toBeVisible();
    await page.getByRole('button', { name: 'Save card' }).click();
    await expectStep(page, 5, 'Review and book');
    await expect(page.getByTestId('card-label')).toHaveText('Visa •••• 4242');
    await expect(cardSection.getByRole('button', { name: 'Change card' })).toBeVisible();
    await expect(page.getByText('Casey Card')).toBeVisible();
    await expect(page.getByTestId('book-button')).toBeEnabled();
    await expectAccessible(page, 'step 5 with a card');
    await screenshot(page, testInfo, '24-book-5-review-card-added');

    await page.getByTestId('book-button').click();
    await expect(page.getByTestId('booked-title')).toHaveText("You're booked");
    await expect(page.getByTestId('booked-summary')).toContainText('Visa •••• 4242');
    await expect(page.getByTestId('booked-summary')).toContainText('Carlos');
    await screenshot(page, testInfo, '25-book-6-confirmed-with-card');

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
});

test('coming back from the card page without the booking says what to do', async ({ page }, testInfo) => {
  await page.goto('/book/card-return?status=saved&session_id=cs_test_e2eUnknown');
  await expect(page.getByRole('heading', { level: 1, name: "Your card wasn't added" })).toBeVisible();
  await expect(page.getByText('This browser lost track of the card you were adding.')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Back to your booking' })).toBeVisible();
  await expectAccessible(page, 'the card return without a booking');
  await screenshot(page, testInfo, '27-card-return-problem');
});
