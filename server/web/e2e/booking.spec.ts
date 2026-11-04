import { readFileSync } from 'node:fs';
import type { Page } from '@playwright/test';
import {
  detailsFields,
  expect,
  expectAccessible,
  expectStep,
  fillDetails,
  firstTime,
  icsTime,
  isPhone,
  manageToken,
  screenshot,
  storedAppointments,
  tabTo,
  test,
  timeChips,
  unfoldIcs,
} from './support.js';

// Booking on the real API with no Stripe key, so no card: the five steps,
// "You're booked", My appointments and cancelling; a time someone else takes
// mid-flow; and the whole booking with the keyboard alone.

/** The open time's start, as the server listed it (its test id is "time-<start>"). */
async function startOf(chip: ReturnType<Page['locator']>): Promise<string> {
  const id = await chip.getAttribute('data-testid');
  if (!id?.startsWith('time-')) throw new Error(`Not a time chip: ${id}`);
  return id.slice('time-'.length);
}

test('a haircut with any barber: booked, in My appointments, and cancelled', async ({ page, phone, request }, testInfo) => {
  await page.goto('/');
  await page.getByRole('main').getByRole('link', { name: 'Book an appointment' }).first().click();

  // 1. Service
  await expectStep(page, 1, 'Pick a service');
  await expect(page.getByTestId('summary-card')).toContainText('Not picked yet');
  await expectAccessible(page, 'step 1');
  await screenshot(page, testInfo, '11-book-1-service');
  await page.getByTestId('service-haircut').click();

  // 2. Barber, "Any barber" first
  await expectStep(page, 2, 'Pick a barber');
  await expect(page.getByTestId('summary-card')).toContainText('Haircut');
  await expect(page.getByTestId('any-barber')).toContainText('Whoever is free first: Flowxbori, Cristian or Julian');
  await expectAccessible(page, 'step 2');
  await screenshot(page, testInfo, '12-book-2-barber');
  await page.getByTestId('any-barber').click();

  // 3. Day and time: the first open day is picked to start with
  await expectStep(page, 3, 'Pick a day and time');
  await expect(page.getByRole('button', { name: 'Continue' })).toBeDisabled();
  await expect(page.getByTestId('fee-warning')).toHaveCount(0);
  const time = await firstTime(page);
  const start = await startOf(time);
  await time.click();
  await expect(time).toHaveAttribute('aria-pressed', 'true');
  await expect(page.getByTestId('summary-card')).toContainText('Any barber');
  await expectAccessible(page, 'step 3');
  await screenshot(page, testInfo, '13-book-3-time');
  await page.getByRole('button', { name: 'Continue' }).click();

  // 4. Your details: problems show once the client continues
  await expectStep(page, 4, 'Your details');
  await page.getByRole('button', { name: 'Continue' }).click();
  await expect(page.getByText("Enter your name so the shop knows who's coming.")).toBeVisible();
  await expect(detailsFields(page).name).toBeFocused();
  await fillDetails(page, { name: 'Jordan Test', phone: phone.replace(/\D/g, '').replace(/^(\d{3})(\d{3})/, '$1.$2.'), email: 'jordan.test@example.com' });
  await expectAccessible(page, 'step 4');
  await screenshot(page, testInfo, '14-book-4-details');
  await page.getByRole('button', { name: 'Continue' }).click();

  // 5. Review: everything, pay at the shop, and no card without Stripe
  await expectStep(page, 5, 'Review and book');
  await expect(page.getByText("No payment now. You'll pay at the shop.")).toBeVisible();
  await expect(page.getByText(phone)).toBeVisible();
  await expect(page.getByTestId('card-section')).toHaveCount(0);
  await expectAccessible(page, 'step 5');
  await screenshot(page, testInfo, '15-book-5-review');
  await page.getByTestId('book-button').click();

  // You're booked, with the barber the shop picked
  await expect(page.getByTestId('booked-title')).toHaveText("You're booked");
  const summary = page.getByTestId('booked-summary');
  await expect(summary).toContainText('Haircut');
  await expect(summary).toContainText(/Flowxbori|Cristian|Julian/);
  await expect(summary).toContainText('1919 Mission Ave, Ste 105');
  await expectAccessible(page, 'the confirmation');
  await screenshot(page, testInfo, '16-book-6-confirmed');

  // Add to calendar: an .ics with the time and the shop's address
  const download = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Add to calendar' }).click();
  const file = await download;
  expect(file.suggestedFilename()).toBe('izzy-clipz-appointment.ics');
  const ics = unfoldIcs(readFileSync(await file.path(), 'utf8'));
  expect(ics).toContain('BEGIN:VCALENDAR');
  expect(ics).toContain(`DTSTART:${icsTime(start)}`);
  expect(ics).toContain('LOCATION:Izzy Clipz Barbershop\\, 1919 Mission Ave\\, Ste 105\\, Oceanside\\, CA 92058');

  // My appointments
  await page.getByRole('link', { name: 'Manage or cancel' }).click();
  await expect(page.getByRole('heading', { level: 1, name: 'My appointments' })).toBeVisible();
  const card = page.getByTestId('appointment-card');
  await expect(card).toHaveCount(1);
  await expect(card.getByTestId('appointment-status')).toHaveText('Next appointment');
  await expect(card).toContainText('Haircut with');
  await expectAccessible(page, 'My appointments');
  await screenshot(page, testInfo, '17-appointments-booked');

  // In an app added to an iPhone's Home Screen, with website data of its own: only the cookies
  // were copied from Safari. The booking's id and manage token came along in one (the server
  // never reads it), and My appointments brings the appointment in from the shop.
  const [booked] = await storedAppointments(page);
  const carried = (await page.context().cookies()).find((cookie) => cookie.name === 'izzy_appointments');
  expect(carried).toMatchObject({ path: '/', sameSite: 'Strict', httpOnly: false });
  expect(carried!.value.startsWith(`${booked!.id}.${booked!.manageToken}.`)).toBe(true);
  await page.evaluate(() => {
    localStorage.clear();
    sessionStorage.clear();
  });
  await page.reload();
  await expect(card.getByTestId('appointment-status')).toHaveText('Next appointment');
  expect((await storedAppointments(page)).map((s) => [s.id, s.manageToken])).toEqual([[booked!.id, booked!.manageToken]]);

  // Cancel, after a question that puts "Keep appointment" first
  await card.getByRole('button', { name: 'Cancel appointment' }).click();
  const dialog = page.getByTestId('cancel-dialog');
  await expect(dialog.getByRole('heading', { name: 'Cancel this appointment?' })).toBeVisible();
  await expect(dialog.getByRole('button', { name: 'Keep appointment' })).toBeFocused();
  await expect(dialog.getByTestId('late-cancel-warning')).toHaveCount(0);
  await expectAccessible(page, 'the cancel question');
  await screenshot(page, testInfo, '18-appointments-cancel-question', { fullPage: false });
  await dialog.getByTestId('confirm-cancel').click();
  await expect(card.getByTestId('appointment-status')).toHaveText('Cancelled');
  await expect(card.getByText('Appointment cancelled. The shop sees it right away.')).toBeVisible();
  await expectAccessible(page, 'a cancelled appointment');
  await screenshot(page, testInfo, '19-appointments-cancelled');

  // The shop has it cancelled too.
  const [saved] = await storedAppointments(page);
  expect(saved).toBeDefined();
  const answer = await request.get(`/api/appointments/${saved!.id}`, { headers: { 'X-Manage-Token': saved!.manageToken } });
  expect((await answer.json()).appointment).toMatchObject({ status: 'cancelled', cancelledBy: 'customer' });
});

test('a time someone else books first sends the client back to the times, saying so', async ({ page, phone, request, browserConsole }, testInfo) => {
  // The browser logs the server's 409 for the taken time; the page handles it.
  browserConsole.allow(/status of 409/);
  await page.goto('/book?service=haircut');
  await expectStep(page, 2, 'Pick a barber');
  const izzy = page.locator('[data-testid^="barber-israel-flores/"]');
  const offeringId = (await izzy.getAttribute('data-testid'))!.slice('barber-'.length);
  await izzy.click();

  await expectStep(page, 3, 'Pick a day and time');
  const time = await firstTime(page);
  const start = await startOf(time);
  const label = (await time.innerText()).trim();
  await time.click();
  await page.getByRole('button', { name: 'Continue' }).click();
  await expectStep(page, 4, 'Your details');
  await fillDetails(page, { name: 'Sam Test', phone });
  await page.getByRole('button', { name: 'Continue' }).click();
  await expectStep(page, 5, 'Review and book');

  // Meanwhile someone else books that time with Izzy.
  const other = await request.post('/api/appointments', {
    data: { offeringId, start, customer: { name: 'Someone Else', phone: `(619) 555-${String(1000 + Math.floor(Math.random() * 9000))}` } },
    headers: { 'X-Manage-Token': manageToken() },
  });
  expect(other.status()).toBe(201);

  await page.getByTestId('book-button').click();
  await expectStep(page, 3, 'Pick a day and time');
  await expect(page.getByTestId('time-notice')).toHaveText(`Someone just booked ${label}. Pick another time.`);
  // The times were checked again: that one is gone, and nothing is picked.
  await expect(page.getByTestId(`time-${start}`)).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Continue' })).toBeDisabled();
  await expectAccessible(page, 'the times after a taken time');
  await screenshot(page, testInfo, '20-book-time-taken');

  // Another time books fine, with the details kept.
  await (await firstTime(page)).click();
  await page.getByRole('button', { name: 'Continue' }).click();
  await expect(detailsFields(page).name).toHaveValue('Sam Test');
  await page.getByRole('button', { name: 'Continue' }).click();
  await page.getByTestId('book-button').click();
  await expect(page.getByTestId('booked-title')).toHaveText("You're booked");
});

test('booking with the keyboard alone', async ({ page, phone }, testInfo) => {
  test.skip(isPhone(testInfo), 'A phone has no keyboard to Tab with.');
  await page.goto('/book');
  await expectStep(page, 1, 'Pick a service');

  // The skip link comes first and goes straight to the page.
  await page.keyboard.press('Tab');
  await expect(page.getByRole('link', { name: 'Skip to main content' })).toBeFocused();
  await page.keyboard.press('Enter');

  await tabTo(page, page.getByTestId('service-haircut'));
  await page.keyboard.press('Enter');
  await expectStep(page, 2, 'Pick a barber');

  await tabTo(page, page.getByTestId('any-barber'));
  await page.keyboard.press('Enter');
  await expectStep(page, 3, 'Pick a day and time');
  await firstTime(page);

  // The calendar is one stop, and the arrow keys move between the open days.
  const dayStop = page.locator('.calendar__day[tabindex="0"]');
  await tabTo(page, dayStop);
  const openDays = await page.locator('.calendar__day.is-open').count();
  const before = await page.evaluate(() => document.activeElement?.getAttribute('data-testid'));
  await page.keyboard.press('ArrowRight');
  const after = await page.evaluate(() => document.activeElement?.getAttribute('data-testid'));
  expect(after).toMatch(/^day-/);
  if (openDays > 1) expect(after).not.toBe(before);
  await page.keyboard.press('Enter');
  await expect(page.getByTestId(after!)).toHaveAttribute('aria-pressed', 'true');

  const chip = timeChips(page).first();
  await tabTo(page, chip);
  await page.keyboard.press('Space');
  await expect(chip).toHaveAttribute('aria-pressed', 'true');
  await tabTo(page, page.getByRole('button', { name: 'Continue' }));
  await page.keyboard.press('Enter');

  await expectStep(page, 4, 'Your details');
  const fields = detailsFields(page);
  await tabTo(page, fields.name);
  await page.keyboard.type('Kim Keyboard');
  await tabTo(page, fields.phone);
  await page.keyboard.type(phone);
  // "Remember me" starts off (a computer can be shared); Space turns it on.
  await tabTo(page, fields.remember);
  await expect(fields.remember).not.toBeChecked();
  await page.keyboard.press('Space');
  await expect(fields.remember).toBeChecked();
  await tabTo(page, page.getByRole('button', { name: 'Continue' }));
  await page.keyboard.press('Enter');

  await expectStep(page, 5, 'Review and book');
  await tabTo(page, page.getByTestId('book-button'));
  await screenshot(page, testInfo, '21-book-keyboard-focus', { fullPage: false });
  await page.keyboard.press('Enter');
  await expect(page.getByTestId('booked-title')).toHaveText("You're booked");
  await tabTo(page, page.getByRole('link', { name: 'Manage or cancel' }));
  await page.keyboard.press('Enter');
  await expect(page.getByRole('heading', { level: 1, name: 'My appointments' })).toBeVisible();
});
