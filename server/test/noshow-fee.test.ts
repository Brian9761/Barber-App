import Stripe from 'stripe';
import { describe, expect, it } from 'vitest';
import { newManageToken } from '../src/auth.js';
import { AUTHENTICATION_MESSAGE, declineMessage, feeStatusFor, needsTheClient, noShowFeeIdempotencyKey, outcomeOf } from '../src/noshowfee.js';
import { RESPONSES } from './helpers/contract.js';
import { protectionOn, stripeError, useHarness } from './helpers/harness.js';

// Charging the fee to the card on file, for a no-show or a late cancellation, and
// keeping it right from Stripe's webhook. Only a PaymentIntent Stripe reports as
// succeeded is "charged".

// Monday Nov 2 2026, 9:00 AM PST.
const h = useHarness({ now: '2026-11-02T17:00:00Z' });

const FLOW45 = 'flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a';
const TUE10 = '2026-11-03T18:00:00Z';
const WEBHOOK_SECRET = 'whsec_fixture_fee';
const owner = { owner: true } as const;

/** A protected booking for Tuesday 10 AM with a saved Visa 4242 (or the card saved under `cardToken`). */
async function protectedBooking(options: { email?: string; start?: string; cardToken?: string } = {}) {
  await protectionOn(h);
  h.config.stripeWebhookSecret = WEBHOOK_SECRET;
  const token = options.cardToken ?? (await saveCard());
  const policy = (await h.call('GET', `/api/no-show-policy?offeringId=${encodeURIComponent(FLOW45)}`)).body.policyText;
  const res = await h.call('POST', '/api/appointments', {
    headers: { 'x-card-token': token },
    body: {
      offeringId: FLOW45,
      start: options.start ?? TUE10,
      customer: { name: 'Andre Sample', phone: '4425550170', ...(options.email ? { email: options.email } : {}) },
      noShowPolicy: policy,
    },
  });
  expect(res.status, res.text).toBe(201);
  return { id: res.body.appointment.id as string, manageToken: res.body.manageToken as string };
}

/** A card saved the way the app does it (Visa 4242); returns its token. */
async function saveCard(): Promise<string> {
  await protectionOn(h);
  const token = newManageToken();
  const checkout = await h.call('POST', '/api/cards/checkout', { headers: { 'x-card-token': token }, body: { offeringId: FLOW45 }, ip: '192.0.2.201' });
  h.stripe.completeSession(checkout.body.sessionId);
  await h.call('POST', '/api/cards', { headers: { 'x-card-token': token }, body: { sessionId: checkout.body.sessionId }, ip: '192.0.2.201' });
  return token;
}

const charge = (id: string) => h.call('POST', `/api/owner/appointments/${id}/no-show-fee`, owner);
const setStatus = (id: string, status: string) => h.call('PATCH', `/api/owner/appointments/${id}`, { ...owner, body: { status } });
const markNoShow = (id: string) => setStatus(id, 'noShow');
const cancelInApp = (booking: { id: string; manageToken: string }) =>
  h.call('POST', `/api/appointments/${booking.id}/cancel`, { headers: { 'x-manage-token': booking.manageToken } });

/** Tuesday 10:20 AM: the client never came. */
async function noShow(options?: Parameters<typeof protectedBooking>[0]) {
  const appointment = await protectedBooking(options);
  h.setNow('2026-11-03T18:20:00Z');
  expect((await markNoShow(appointment.id)).status).toBe(200);
  return appointment.id;
}

const creates = () => h.stripe.calls.filter((c) => c.method === 'paymentIntents.create' && (c.params as { confirm?: boolean }).confirm);

async function feeRow(id: string) {
  return (await h.database.pool.query('SELECT * FROM appointments WHERE id = $1', [id])).rows[0];
}

describe('what Stripe says, in the fee’s words', () => {
  it('only succeeded is charged', () => {
    expect(feeStatusFor('succeeded')).toBe('charged');
    expect(feeStatusFor('requires_action')).toBe('needs_action');
    expect(feeStatusFor('requires_payment_method')).toBe('declined');
    expect(feeStatusFor('canceled')).toBe('declined');
    for (const status of ['processing', 'requires_confirmation', 'requires_capture', 'something_new']) expect(feeStatusFor(status)).toBe('pending');
  });

  it('decline reasons in plain words, never naming fraud', () => {
    expect(declineMessage({ code: 'card_declined', decline_code: 'insufficient_funds' })).toBe("The card was declined: there isn't enough money on it.");
    expect(declineMessage({ code: 'expired_card' })).toBe('The card has expired.');
    expect(declineMessage({ code: 'incorrect_cvc' })).toBe("The card's details didn't work.");
    expect(declineMessage({ code: 'processing_error' })).toBe("The bank couldn't process the card. Try again in a while.");
    expect(declineMessage({ code: 'card_decline_rate_limit_exceeded' })).toBe('The card was declined too many times today. Try again tomorrow.');
    expect(declineMessage({ code: 'authentication_required' })).toMatch(/^The client's bank wants them to approve this charge/);
    expect(declineMessage({ code: 'card_declined', decline_code: 'authentication_required' })).toMatch(/approve this charge/);
    for (const decline of ['stolen_card', 'lost_card', 'fraudulent', 'generic_decline', 'do_not_honor']) {
      expect(declineMessage({ code: 'card_declined', decline_code: decline })).toBe('The bank declined the card.');
    }
    expect(declineMessage(null)).toBe('The bank declined the card.');
  });

  it('a failed charge the bank wants the client to approve reads as needing the client, not as declined', () => {
    expect(needsTheClient({ code: 'authentication_required' })).toBe(true);
    expect(needsTheClient({ code: 'card_declined', decline_code: 'authentication_required' })).toBe(true);
    expect(needsTheClient({ code: 'card_declined', decline_code: 'insufficient_funds' })).toBe(false);
    expect(needsTheClient(null)).toBe(false);
    // Stripe leaves a failed off-session charge in requires_payment_method, with the reason in last_payment_error.
    const failed = (last_payment_error: { code?: string; decline_code?: string } | null) => ({ id: 'pi_1', status: 'requires_payment_method', last_payment_error });
    expect(outcomeOf(failed({ code: 'authentication_required', decline_code: 'authentication_required' }))).toEqual({
      status: 'needs_action',
      message: AUTHENTICATION_MESSAGE,
    });
    expect(outcomeOf(failed({ code: 'card_declined', decline_code: 'authentication_required' }))).toEqual({ status: 'needs_action', message: AUTHENTICATION_MESSAGE });
    expect(outcomeOf(failed({ code: 'card_declined', decline_code: 'insufficient_funds' }))).toEqual({
      status: 'declined',
      message: "The card was declined: there isn't enough money on it.",
    });
    expect(outcomeOf(failed(null))).toEqual({ status: 'declined', message: 'The bank declined the card.' });
    expect(outcomeOf({ id: 'pi_1', status: 'canceled', last_payment_error: { code: 'authentication_required' } })).toEqual({
      status: 'declined',
      message: 'The charge was cancelled in Stripe.',
    });
    expect(outcomeOf({ id: 'pi_1', status: 'requires_action' })).toEqual({ status: 'needs_action', message: AUTHENTICATION_MESSAGE });
    expect(outcomeOf({ id: 'pi_1', status: 'succeeded' })).toEqual({ status: 'charged', message: null });
    expect(outcomeOf({ id: 'pi_1', status: 'processing' })).toEqual({ status: 'pending', message: null });
  });
});

describe('cancelling in the app before the start is always free', () => {
  const NOT_CHARGEABLE = { code: 'not_chargeable', message: "The client cancelled this booking in the app, so there's no fee." };

  it('a client who cancelled in time is never charged, even after the shop reopens the booking', async () => {
    const booking = await protectedBooking();
    // Tuesday 9:00 AM: the client cancels in the app.
    h.setNow('2026-11-03T17:00:00Z');
    const cancelled = await cancelInApp(booking);
    expect(cancelled.status).toBe(200);
    expect(cancelled.body.appointment).toMatchObject({ status: 'cancelled', cancelledBy: 'customer' });
    expect(cancelled.body.appointment.noShowFee).toEqual({
      amountCents: 3500,
      fullPrice: true,
      status: 'none',
      chargedAt: null,
      message: null,
      customerCancelledAt: '2026-11-03T17:00:00Z',
      lateCancelWindowMinutes: 60,
      // Exactly 1 hour before is still free.
      reason: null,
    });
    // The shop reopens it (say the client called), then they don't come.
    const reopened = await setStatus(booking.id, 'booked');
    expect(reopened.body.appointment.cancelledBy).toBeNull();
    expect(reopened.body.appointment.noShowFee.customerCancelledAt).toBe('2026-11-03T17:00:00Z');
    h.setNow('2026-11-03T18:20:00Z');
    expect((await markNoShow(booking.id)).status).toBe(200);
    const res = await charge(booking.id);
    expect(res.status).toBe(409);
    expect(res.body.error).toEqual(NOT_CHARGEABLE);
    expect(creates()).toHaveLength(0);
    expect((await feeRow(booking.id)).no_show_fee_status).toBe('none');
  });

  it('the shop can’t mark a booking with a card a no-show before it starts, so the client can still cancel', async () => {
    const booking = await protectedBooking();
    // 9:50 AM: too early to call it a no-show.
    h.setNow('2026-11-03T17:50:00Z');
    const early = await markNoShow(booking.id);
    expect(early.status).toBe(409);
    expect(early.body.error).toEqual({ code: 'not_started', message: 'You can mark a no-show once the appointment has started.' });
    // 9:55 AM: the client cancels.
    h.setNow('2026-11-03T17:55:00Z');
    expect((await cancelInApp(booking)).status).toBe(200);
    // 10:05 AM: marked a no-show anyway, but there's nothing to charge.
    h.setNow('2026-11-03T18:05:00Z');
    expect((await markNoShow(booking.id)).status).toBe(200);
    expect((await charge(booking.id)).body.error).toEqual(NOT_CHARGEABLE);
    expect(creates()).toHaveLength(0);
  });

  it('asking to cancel in time counts even when the shop had already marked the booking', async () => {
    const booking = await protectedBooking();
    // 9:50 AM: marked completed by mistake; 9:55 AM: the client tries to cancel.
    h.setNow('2026-11-03T17:50:00Z');
    expect((await setStatus(booking.id, 'completed')).status).toBe(200);
    h.setNow('2026-11-03T17:55:00Z');
    const refused = await cancelInApp(booking);
    expect(refused.status).toBe(409);
    expect(refused.body.error).toEqual({ code: 'not_cancellable', message: "This appointment can't be cancelled any more." });
    expect((await feeRow(booking.id)).customer_cancelled_at.toISOString()).toBe('2026-11-03T17:55:00.000Z');
    // Trying again later doesn't move the time.
    h.setNow('2026-11-03T17:58:00Z');
    await cancelInApp(booking);
    expect((await feeRow(booking.id)).customer_cancelled_at.toISOString()).toBe('2026-11-03T17:55:00.000Z');
    // 10:05 AM: reopened, then marked a no-show.
    h.setNow('2026-11-03T18:05:00Z');
    await setStatus(booking.id, 'booked');
    expect((await markNoShow(booking.id)).status).toBe(200);
    expect((await charge(booking.id)).body.error).toEqual(NOT_CHARGEABLE);
    // And on the shop's list, so the app can say why.
    const day = await h.call('GET', '/api/owner/appointments?date=2026-11-03', owner);
    expect(day.body.appointments[0].noShowFee.customerCancelledAt).toBe('2026-11-03T17:55:00Z');
  });

  it('asking to cancel after the start doesn’t count: the no-show can be charged', async () => {
    const booking = await protectedBooking();
    h.setNow('2026-11-03T18:05:00Z');
    const late = await cancelInApp(booking);
    expect(late.status).toBe(409);
    expect(late.body.error).toEqual({ code: 'not_cancellable', message: 'This appointment has already started. Call the shop if you need help.' });
    expect((await feeRow(booking.id)).customer_cancelled_at).toBeNull();
    await markNoShow(booking.id);
    expect((await charge(booking.id)).body.appointment.noShowFee).toMatchObject({ status: 'charged', customerCancelledAt: null });
  });

  it('a client cancelling and the shop marking at the same moment: one wins, and a cancelled booking is never charged', async () => {
    const booking = await protectedBooking();
    h.setNow('2026-11-03T17:59:00Z');
    const [cancel, mark] = await Promise.all([cancelInApp(booking), setStatus(booking.id, 'completed')]);
    expect(mark.status).toBe(200);
    expect([200, 409]).toContain(cancel.status);
    // Either way the client asked in time.
    expect((await feeRow(booking.id)).customer_cancelled_at).not.toBeNull();
    h.setNow('2026-11-03T18:10:00Z');
    await markNoShow(booking.id);
    expect((await charge(booking.id)).body.error).toEqual(NOT_CHARGEABLE);
  });
});

describe('late cancellations: the client cancels less than the agreed window before the start', () => {
  /** A protected booking for `start`, cancelled in the app at `cancelAt`. */
  async function cancelledAt(cancelAt: string, start = TUE10) {
    const booking = await protectedBooking({ start });
    h.setNow(cancelAt);
    const res = await cancelInApp(booking);
    expect(res.status, res.text).toBe(200);
    return { ...booking, appointment: res.body.appointment };
  }

  it('can be charged the agreed fee right away, as a late cancellation fee', async () => {
    // Tuesday 9:30 AM, half an hour before the 10 AM booking.
    const late = await cancelledAt('2026-11-03T17:30:00Z');
    expect(late.appointment).toMatchObject({ status: 'cancelled', cancelledBy: 'customer' });
    expect(late.appointment.noShowFee).toEqual({
      amountCents: 3500,
      fullPrice: true,
      status: 'none',
      chargedAt: null,
      message: null,
      customerCancelledAt: '2026-11-03T17:30:00Z',
      lateCancelWindowMinutes: 60,
      reason: 'lateCancel',
    });
    // The owner doesn't have to wait for the start.
    h.setNow('2026-11-03T17:31:00Z');
    const res = await charge(late.id);
    expect(res.status, res.text).toBe(200);
    expect(RESPONSES['late-cancel-fee-charged'].safeParse(res.body).success).toBe(true);
    expect(res.body.appointment).toMatchObject({ status: 'cancelled', payment: { status: 'unpaid', amountCents: null, paidAt: null } });
    expect(res.body.appointment.noShowFee).toEqual({
      amountCents: 3500,
      fullPrice: true,
      status: 'charged',
      chargedAt: '2026-11-03T17:31:00Z',
      message: null,
      customerCancelledAt: '2026-11-03T17:30:00Z',
      lateCancelWindowMinutes: 60,
      reason: 'lateCancel',
    });
    const [call] = creates();
    expect(call!.params).toMatchObject({
      amount: 3500,
      currency: 'usd',
      off_session: true,
      confirm: true,
      description: 'Late cancellation fee: Haircut with Flowxbori, Tue, Nov 3 at 10:00 AM',
      metadata: { source: 'izzy-clipz-api', kind: 'late_cancel_fee', appointment_id: late.id, attempt: '1' },
    });
    expect(call!.options).toEqual({ idempotencyKey: noShowFeeIdempotencyKey(late.id, 1) });
    // Payments today labels it.
    expect((await h.call('GET', '/api/owner/payments?date=2026-11-03', owner)).body.payments).toEqual([
      expect.objectContaining({
        amountCents: 3500,
        description: 'Late cancellation fee: Haircut with Flowxbori, Tue, Nov 3 at 10:00 AM',
        appointmentId: late.id,
        status: 'succeeded',
        kind: 'lateCancelFee',
      }),
    ]);
    // Once only, and the client sees it.
    expect((await charge(late.id)).body.appointment.noShowFee.status).toBe('charged');
    expect(creates()).toHaveLength(1);
    const mine = await h.call('GET', `/api/appointments/${late.id}`, { headers: { 'x-manage-token': late.manageToken } });
    expect(mine.body.appointment.noShowFee).toMatchObject({ status: 'charged', reason: 'lateCancel' });
  });

  it('the edge of the window: exactly 1 hour before is free, 59 minutes before is late', async () => {
    const onTime = await cancelledAt('2026-11-03T17:00:00Z');
    expect(onTime.appointment.noShowFee.reason).toBeNull();
    const free = await charge(onTime.id);
    expect(free.status).toBe(409);
    expect(free.body.error).toEqual({ code: 'not_chargeable', message: "The client cancelled at least 1 hour before, so there's no fee." });

    const late = await cancelledAt('2026-11-03T18:01:00Z', '2026-11-03T19:00:00Z');
    expect(late.appointment.noShowFee.reason).toBe('lateCancel');
    expect((await charge(late.id)).body.appointment.noShowFee.status).toBe('charged');
    expect(creates()).toHaveLength(1);
  });

  it('the window the client agreed to counts, not the one in Settings today', async () => {
    // Booked with the 1-hour window; the owner then makes it 3 hours.
    const booking = await protectedBooking();
    await h.call('PATCH', '/api/owner/no-show-settings', { ...owner, body: { lateCancelWindowMinutes: 180 } });
    h.setNow('2026-11-03T16:30:00Z'); // 90 minutes before
    expect((await cancelInApp(booking)).body.appointment.noShowFee).toMatchObject({ lateCancelWindowMinutes: 60, reason: null });
    expect((await charge(booking.id)).body.error.message).toBe("The client cancelled at least 1 hour before, so there's no fee.");

    // Booked under the 3-hour window: 90 minutes before is late.
    h.setNow('2026-11-02T17:00:00Z');
    const later = await cancelledAt('2026-11-03T17:30:00Z', '2026-11-03T19:00:00Z');
    expect(later.appointment.noShowFee).toMatchObject({ lateCancelWindowMinutes: 180, reason: 'lateCancel' });
    expect((await charge(later.id)).body.appointment.noShowFee.status).toBe('charged');
    // And turning late cancellations off later doesn't undo what they agreed to (the owner still decides).
    expect((await h.call('PATCH', '/api/owner/no-show-settings', { ...owner, body: { lateCancelEnabled: false } })).status).toBe(200);
  });

  it('the client’s first cancel time decides: cancelled early, reopened, then cancelled inside the window stays free', async () => {
    const booking = await protectedBooking();
    // Monday 9:00 AM: the client cancels Tuesday's 10 AM, for free.
    const early = await cancelInApp(booking);
    expect(early.body.appointment.noShowFee).toMatchObject({ customerCancelledAt: '2026-11-02T17:00:00Z', reason: null });
    // The shop reopens it (say the client called), and on Tuesday at 9:30 the client cancels again.
    expect((await setStatus(booking.id, 'booked')).body.appointment.status).toBe('booked');
    h.setNow('2026-11-03T17:30:00Z');
    const again = await cancelInApp(booking);
    expect(again.status, again.text).toBe(200);
    expect(again.body.appointment).toMatchObject({ status: 'cancelled', cancelledBy: 'customer' });
    expect(again.body.appointment.noShowFee).toMatchObject({ customerCancelledAt: '2026-11-02T17:00:00Z', reason: null });
    expect((await feeRow(booking.id)).customer_cancelled_at.toISOString()).toBe('2026-11-02T17:00:00.000Z');
    const res = await charge(booking.id);
    expect(res.status).toBe(409);
    expect(res.body.error).toEqual({ code: 'not_chargeable', message: "The client cancelled at least 1 hour before, so there's no fee." });
    // Nor is it a no-show later.
    h.setNow('2026-11-03T18:20:00Z');
    expect((await setStatus(booking.id, 'booked')).status).toBe(200);
    expect((await markNoShow(booking.id)).status).toBe(200);
    expect((await charge(booking.id)).body.error.message).toBe("The client cancelled this booking in the app, so there's no fee.");
    expect(creates()).toHaveLength(0);
  });

  it('booked while late cancellations were off: cancelling in the app is free, however late', async () => {
    await protectionOn(h);
    await h.call('PATCH', '/api/owner/no-show-settings', { ...owner, body: { lateCancelEnabled: false } });
    const booking = await cancelledAt('2026-11-03T17:55:00Z');
    expect(booking.appointment.noShowFee).toMatchObject({ lateCancelWindowMinutes: null, reason: null, customerCancelledAt: '2026-11-03T17:55:00Z' });
    const res = await charge(booking.id);
    expect(res.status).toBe(409);
    expect(res.body.error).toEqual({ code: 'not_chargeable', message: "The client cancelled this booking in the app, so there's no fee." });
    expect(creates()).toHaveLength(0);
  });

  it('a cancellation by the shop is never charged, nor a late one the shop reopened', async () => {
    const SHOP = { code: 'not_chargeable', message: "The shop cancelled this booking, so there's no fee." };
    const shop = await protectedBooking();
    h.setNow('2026-11-03T17:50:00Z');
    const cancelled = await setStatus(shop.id, 'cancelled');
    expect(cancelled.body.appointment).toMatchObject({ status: 'cancelled', cancelledBy: 'shop' });
    expect(cancelled.body.appointment.noShowFee.reason).toBeNull();
    expect((await charge(shop.id)).body.error).toEqual(SHOP);
    // The client tries to cancel it too (refused: it's already cancelled), still the shop's cancellation.
    expect((await cancelInApp(shop)).status).toBe(409);
    expect((await charge(shop.id)).body.error).toEqual(SHOP);

    // A late cancellation the shop reopens (say the client called back) can't be charged any more…
    h.setNow('2026-11-02T17:00:00Z');
    const late = await cancelledAt('2026-11-03T18:40:00Z', '2026-11-03T19:00:00Z');
    expect(late.appointment.noShowFee.reason).toBe('lateCancel');
    const reopened = await setStatus(late.id, 'booked');
    expect(reopened.body.appointment.noShowFee).toMatchObject({ reason: null, customerCancelledAt: '2026-11-03T18:40:00Z' });
    expect((await charge(late.id)).body.error).toEqual({ code: 'not_chargeable', message: "The client cancelled this booking in the app, so there's no fee." });
    // …nor once the shop cancels it again, or marks it a no-show after the start.
    expect((await setStatus(late.id, 'cancelled')).body.appointment.cancelledBy).toBe('shop');
    expect((await charge(late.id)).body.error).toEqual(SHOP);
    h.setNow('2026-11-03T19:10:00Z');
    expect((await markNoShow(late.id)).status).toBe(200);
    expect((await charge(late.id)).body.error.message).toBe("The client cancelled this booking in the app, so there's no fee.");
    expect(creates()).toHaveLength(0);
  });

  it('a declined late-cancellation fee can be tried again, and stays a late cancellation', async () => {
    const late = await cancelledAt('2026-11-03T17:45:00Z');
    h.stripe.nextCharge = 'insufficient_funds';
    const declined = await charge(late.id);
    expect(declined.body.appointment.noShowFee).toMatchObject({
      status: 'declined',
      reason: 'lateCancel',
      message: "The card was declined: there isn't enough money on it.",
    });
    expect((await h.call('GET', '/api/owner/payments?date=2026-11-03', owner)).body.payments[0]).toMatchObject({
      kind: 'lateCancelFee',
      status: 'requires_payment_method',
    });
    expect((await feeRow(late.id)).no_show_fee_reason).toBe('late_cancel');
    h.advance(30);
    const second = await charge(late.id);
    expect(second.body.appointment.noShowFee).toMatchObject({ status: 'charged', reason: 'lateCancel' });
    expect(creates().map((c) => (c.params as { metadata: { kind: string; attempt: string } }).metadata)).toEqual([
      expect.objectContaining({ kind: 'late_cancel_fee', attempt: '1' }),
      expect.objectContaining({ kind: 'late_cancel_fee', attempt: '2' }),
    ]);
  });

  it('a lost answer for a late-cancellation fee is found at Stripe and recorded as one', async () => {
    const late = await cancelledAt('2026-11-03T17:45:00Z');
    h.stripe.loseNextChargeAnswer = true;
    expect((await charge(late.id)).status).toBe(500);
    h.advance(25 * 60);
    h.stripe.forgetIdempotencyKeys();
    const found = await charge(late.id);
    expect(found.body.appointment.noShowFee).toMatchObject({ status: 'charged', reason: 'lateCancel' });
    expect(creates()).toHaveLength(1);
    // Listed on the day Stripe charged it, not the day the server found out.
    expect((await h.call('GET', '/api/owner/payments?date=2026-11-03', owner)).body.payments).toEqual([
      expect.objectContaining({ kind: 'lateCancelFee', status: 'succeeded', appointmentId: late.id, createdAt: '2026-11-03T17:45:00Z' }),
    ]);
    expect((await h.call('GET', '/api/owner/payments?date=2026-11-04', owner)).body.payments).toEqual([]);
  });

  it('a no-show reads as one on the shop’s list before anything is charged', async () => {
    const id = await noShow();
    const day = await h.call('GET', '/api/owner/appointments?date=2026-11-03', owner);
    expect(day.body.appointments[0].noShowFee).toMatchObject({ status: 'none', reason: 'noShow' });
    // A booking that's just booked, or completed, isn't either case.
    expect((await setStatus(id, 'completed')).body.appointment.noShowFee.reason).toBeNull();
    expect((await setStatus(id, 'booked')).body.appointment.noShowFee.reason).toBeNull();
  });
});

describe('POST /api/owner/appointments/:id/no-show-fee', () => {
  it('charges the agreed fee off-session to the card on file, once, with an idempotency key', async () => {
    const id = await noShow({ email: 'andre@example.com' });
    const res = await charge(id);
    expect(res.status).toBe(200);
    expect(RESPONSES['no-show-fee-charged'].safeParse(res.body).success).toBe(true);
    expect(res.body.appointment.noShowFee).toEqual({
      amountCents: 3500,
      fullPrice: true,
      status: 'charged',
      chargedAt: '2026-11-03T18:20:00Z',
      message: null,
      customerCancelledAt: null,
      lateCancelWindowMinutes: 60,
      reason: 'noShow',
    });
    // A no-show fee isn't a payment for the service.
    expect(res.body.appointment.payment).toEqual({ status: 'unpaid', amountCents: null, paidAt: null });

    const [call] = creates();
    const card = await h.database.pool.query('SELECT stripe_customer_id, stripe_payment_method_id FROM saved_cards');
    expect(call!.params).toEqual({
      amount: 3500,
      currency: 'usd',
      customer: card.rows[0].stripe_customer_id,
      payment_method: card.rows[0].stripe_payment_method_id,
      off_session: true,
      confirm: true,
      allowed_payment_method_types: ['card'],
      description: 'No-show fee: Haircut with Flowxbori, Tue, Nov 3 at 10:00 AM',
      metadata: { source: 'izzy-clipz-api', kind: 'no_show_fee', appointment_id: id, attempt: '1' },
    });
    expect(call!.params).not.toHaveProperty('payment_method_types');
    expect(call!.options).toEqual({ idempotencyKey: noShowFeeIdempotencyKey(id, 1) });
    expect(noShowFeeIdempotencyKey(id, 1)).toBe(`izzy-no-show-fee-${id}-1`);

    // Charging again changes nothing and asks Stripe nothing.
    h.advance(5);
    const again = await charge(id);
    expect(again.status).toBe(200);
    expect(again.body).toEqual(res.body);
    expect(creates()).toHaveLength(1);
  });

  it('lists the fee in the day’s payments as a no-show fee', async () => {
    const id = await noShow();
    await charge(id);
    const list = await h.call('GET', '/api/owner/payments?date=2026-11-03', owner);
    expect(list.body.payments).toEqual([
      {
        id: expect.stringMatching(/^pi_/),
        amountCents: 3500,
        description: 'No-show fee: Haircut with Flowxbori, Tue, Nov 3 at 10:00 AM',
        appointmentId: id,
        status: 'succeeded',
        createdAt: '2026-11-03T18:20:00Z',
        kind: 'noShowFee',
      },
    ]);
  });

  it('a later in-person payment for the appointment counts only itself as paid', async () => {
    const id = await noShow();
    await charge(id);
    // Reopened and paid at the shop after all.
    await h.call('PATCH', `/api/owner/appointments/${id}`, { ...owner, body: { status: 'completed' } });
    const pay = await h.call('POST', '/api/owner/payments', { ...owner, body: { amountCents: 3500, appointmentId: id } });
    h.stripe.succeed(pay.body.paymentIntentId);
    await h.call('POST', `/api/owner/payments/${pay.body.paymentIntentId}/complete`, owner);
    const day = await h.call('GET', '/api/owner/appointments?date=2026-11-03', owner);
    const appointment = day.body.appointments.find((a: { id: string }) => a.id === id);
    expect(appointment.payment).toMatchObject({ status: 'paid', amountCents: 3500 });
    // Reopening doesn't refund (that's done in the Stripe Dashboard): the fee stays charged.
    expect(appointment.noShowFee.status).toBe('charged');
    expect(appointment.status).toBe('completed');
  });

  it('declined: says why, records the attempt, and a new try makes a new PaymentIntent', async () => {
    const id = await noShow();
    h.stripe.nextCharge = 'insufficient_funds';
    const declined = await charge(id);
    expect(declined.status).toBe(200);
    expect(declined.body.appointment.noShowFee).toEqual({
      amountCents: 3500,
      fullPrice: true,
      status: 'declined',
      chargedAt: null,
      message: "The card was declined: there isn't enough money on it.",
      customerCancelledAt: null,
      lateCancelWindowMinutes: 60,
      reason: 'noShow',
    });
    const attempt1 = (await feeRow(id)).no_show_fee_payment_intent_id;
    expect(attempt1).toMatch(/^pi_/);
    expect((await h.call('GET', '/api/owner/payments?date=2026-11-03', owner)).body.payments[0]).toMatchObject({
      id: attempt1,
      status: 'requires_payment_method',
      kind: 'noShowFee',
    });
    expect(h.logs.at(-1)).toMatchObject({ level: 'warn', message: 'Stripe declined a no-show fee' });

    h.advance(60);
    const second = await charge(id);
    expect(second.body.appointment.noShowFee.status).toBe('charged');
    expect(creates().map((c) => (c.options as { idempotencyKey: string }).idempotencyKey)).toEqual([
      noShowFeeIdempotencyKey(id, 1),
      noShowFeeIdempotencyKey(id, 2),
    ]);
    expect((await feeRow(id)).no_show_fee_payment_intent_id).not.toBe(attempt1);
  });

  it('a generic decline, and a card that was removed from Stripe', async () => {
    const id = await noShow();
    h.stripe.nextCharge = 'decline';
    expect((await charge(id)).body.appointment.noShowFee).toMatchObject({ status: 'declined', message: 'The bank declined the card.' });
    h.stripe.nextCharge = 'card_removed';
    const removed = await charge(id);
    expect(removed.status).toBe(200);
    expect(removed.body.appointment.noShowFee).toMatchObject({
      status: 'declined',
      message: "Stripe couldn't use the saved card. Ask the client to pay at the shop.",
    });
  });

  it('the bank wants the client to approve it: needsAction, with what to do', async () => {
    const id = await noShow();
    h.stripe.nextCharge = 'authentication_required';
    const res = await charge(id);
    expect(res.status).toBe(200);
    expect(res.body.appointment.noShowFee).toEqual({
      amountCents: 3500,
      fullPrice: true,
      status: 'needsAction',
      chargedAt: null,
      message: "The client's bank wants them to approve this charge, so it can't go through from here. Ask them to pay at the shop.",
      customerCancelledAt: null,
      lateCancelWindowMinutes: 60,
      reason: 'noShow',
    });
    // A PaymentIntent left needing action (never with off_session in practice) reads the same.
    const other = (await protectedBooking({ start: '2026-11-03T19:00:00Z' })).id;
    h.setNow('2026-11-03T19:20:00Z');
    expect((await markNoShow(other)).status).toBe(200);
    h.stripe.nextCharge = 'requires_action';
    expect((await charge(other)).body.appointment.noShowFee.status).toBe('needsAction');
  });

  it('processing: pending until Stripe says how it went; charging again asks Stripe instead of charging again', async () => {
    const id = await noShow();
    h.stripe.nextCharge = 'processing';
    const pending = await charge(id);
    expect(pending.body.appointment.noShowFee).toMatchObject({ status: 'pending', chargedAt: null });
    const piId = (await feeRow(id)).no_show_fee_payment_intent_id;
    // Still processing.
    expect((await charge(id)).body.appointment.noShowFee.status).toBe('pending');
    h.stripe.succeed(piId);
    h.advance(2);
    const done = await charge(id);
    expect(done.body.appointment.noShowFee).toMatchObject({ status: 'charged', chargedAt: '2026-11-03T18:22:00Z' });
    expect(creates()).toHaveLength(1);
    expect(h.stripe.calls.filter((c) => c.method === 'paymentIntents.retrieve')).toHaveLength(2);
  });

  it('checking a fee with …/complete (like an in-person payment) keeps the fee right and never marks the appointment paid', async () => {
    const id = await noShow();
    h.stripe.nextCharge = 'processing';
    await charge(id);
    const piId = (await feeRow(id)).no_show_fee_payment_intent_id;
    h.stripe.succeed(piId);
    const res = await h.call('POST', `/api/owner/payments/${piId}/complete`, owner);
    expect(res.status).toBe(200);
    expect(res.body.payment).toMatchObject({ id: piId, status: 'succeeded', kind: 'noShowFee', appointmentId: id });
    const day = await h.call('GET', '/api/owner/appointments?date=2026-11-03', owner);
    expect(day.body.appointments[0].noShowFee.status).toBe('charged');
    expect(day.body.appointments[0].payment).toEqual({ status: 'unpaid', amountCents: null, paidAt: null });
  });

  it('a lost answer leaves it pending; charging again finds that charge at Stripe instead of charging again', async () => {
    const id = await noShow();
    h.stripe.loseNextChargeAnswer = true;
    const lost = await charge(id);
    expect(lost.status).toBe(500);
    expect(lost.body.error).toEqual({ code: 'server_error', message: "We couldn't reach Stripe. Please try again." });
    expect(await feeRow(id)).toMatchObject({ no_show_fee_status: 'pending', no_show_fee_attempt: 1, no_show_fee_payment_intent_id: null });
    expect((await feeRow(id)).no_show_fee_attempt_at.toISOString()).toBe('2026-11-03T18:20:00.000Z');
    const day = await h.call('GET', '/api/owner/appointments?date=2026-11-03', owner);
    expect(day.body.appointments[0].noShowFee.status).toBe('pending');

    h.advance(3);
    const retry = await charge(id);
    expect(retry.body.appointment.noShowFee).toMatchObject({ status: 'charged', chargedAt: '2026-11-03T18:23:00Z' });
    // Asked Stripe for this attempt's PaymentIntent: the card's own Customer, since the attempt began.
    const card = await h.database.pool.query('SELECT stripe_customer_id FROM saved_cards');
    const lists = h.stripe.calls.filter((c) => c.method === 'paymentIntents.list');
    expect(lists.map((c) => c.params)).toEqual([
      { customer: card.rows[0].stripe_customer_id, created: { gte: Date.parse('2026-11-03T18:20:00Z') / 1000 - 3600 }, limit: 100 },
    ]);
    // One request at Stripe, one PaymentIntent: the money moved once.
    expect(creates().map((c) => (c.options as { idempotencyKey: string }).idempotencyKey)).toEqual([noShowFeeIdempotencyKey(id, 1)]);
    expect([...h.stripe.intents.values()].filter((pi) => pi.metadata.kind === 'no_show_fee')).toHaveLength(1);
    expect((await h.call('GET', '/api/owner/payments?date=2026-11-03', owner)).body.payments).toEqual([
      expect.objectContaining({ kind: 'noShowFee', status: 'succeeded', appointmentId: id }),
    ]);
  });

  it('a lost answer retried days later, after Stripe forgot the key, still charges once', async () => {
    const id = await noShow();
    h.stripe.loseNextChargeAnswer = true;
    expect((await charge(id)).status).toBe(500);
    // 25 hours on: Stripe may have pruned the key, so the same key would now make a second charge.
    h.advance(25 * 60);
    h.stripe.forgetIdempotencyKeys();
    const retry = await charge(id);
    expect(retry.status).toBe(200);
    expect(retry.body.appointment.noShowFee.status).toBe('charged');
    expect(creates()).toHaveLength(1);
    const fees = [...h.stripe.intents.values()].filter((pi) => pi.metadata.kind === 'no_show_fee');
    expect(fees).toHaveLength(1);
    expect(fees[0]!.status).toBe('succeeded');
    // And again: nothing new at Stripe.
    expect((await charge(id)).body.appointment.noShowFee.status).toBe('charged');
    expect(creates()).toHaveLength(1);
  });

  it('a try that never reached Stripe, retried after the key was forgotten, charges (once)', async () => {
    const id = await noShow();
    h.stripe.nextError = stripeError('StripeConnectionError', {}, 'socket hang up');
    expect((await charge(id)).status).toBe(500);
    h.advance(25 * 60);
    h.stripe.forgetIdempotencyKeys();
    expect((await charge(id)).body.appointment.noShowFee.status).toBe('charged');
    expect(creates().map((c) => (c.options as { idempotencyKey: string }).idempotencyKey)).toEqual([
      noShowFeeIdempotencyKey(id, 1),
      noShowFeeIdempotencyKey(id, 1),
    ]);
    expect([...h.stripe.intents.values()].filter((pi) => pi.metadata.kind === 'no_show_fee')).toHaveLength(1);
  });

  it('the look-up finds only this appointment’s current attempt, even among many of the card’s PaymentIntents', async () => {
    const card = await saveCard();
    // The same client no-showed earlier the same day and paid that fee.
    const first = (await protectedBooking({ cardToken: card })).id;
    const second = (await protectedBooking({ cardToken: card, start: '2026-11-03T19:00:00Z' })).id;
    h.setNow('2026-11-03T18:20:00Z');
    await markNoShow(first);
    expect((await charge(first)).body.appointment.noShowFee.status).toBe('charged');
    h.setNow('2026-11-03T19:20:00Z');
    await markNoShow(second);
    // Attempt 1 declined, attempt 2 never reached Stripe.
    h.stripe.nextCharge = 'decline';
    expect((await charge(second)).body.appointment.noShowFee.status).toBe('declined');
    h.stripe.nextError = stripeError('StripeConnectionError', {}, 'socket hang up');
    expect((await charge(second)).status).toBe(500);
    // Plenty of other PaymentIntents on the card's Customer since then, so the look-up needs more than one page.
    const customer = (await h.database.pool.query('SELECT stripe_customer_id FROM saved_cards')).rows[0].stripe_customer_id;
    for (let i = 0; i < 150; i++) await h.stripe.paymentIntents.create({ amount: 100, currency: 'usd', customer });
    h.advance(1);
    const retry = await charge(second);
    expect(retry.body.appointment.noShowFee.status).toBe('charged');
    expect(h.stripe.calls.filter((c) => c.method === 'paymentIntents.list').length).toBeGreaterThanOrEqual(2);
    const fees = [...h.stripe.intents.values()].filter((pi) => pi.metadata.kind === 'no_show_fee');
    expect(fees.map((pi) => [pi.metadata.appointment_id, pi.metadata.attempt, pi.status])).toEqual([
      [first, '1', 'succeeded'],
      [second, '1', 'requires_payment_method'],
      [second, '2', 'succeeded'],
    ]);
  });

  it('a lost answer whose charge was declined is recorded as declined; the next try is a new attempt', async () => {
    const id = await noShow();
    h.stripe.nextCharge = 'insufficient_funds';
    // Stripe declined it, but the answer never came back.
    const realCreate = h.stripe.paymentIntents.create;
    h.stripe.paymentIntents.create = async (params, options) => {
      h.stripe.paymentIntents.create = realCreate;
      await realCreate(params, options).catch(() => undefined);
      throw stripeError('StripeConnectionError', {}, 'socket hang up');
    };
    expect((await charge(id)).status).toBe(500);
    const found = await charge(id);
    expect(found.body.appointment.noShowFee).toMatchObject({ status: 'declined', message: "The card was declined: there isn't enough money on it." });
    expect(creates()).toHaveLength(1);
    expect((await charge(id)).body.appointment.noShowFee.status).toBe('charged');
    expect(creates().map((c) => (c.options as { idempotencyKey: string }).idempotencyKey)).toEqual([
      noShowFeeIdempotencyKey(id, 1),
      noShowFeeIdempotencyKey(id, 2),
    ]);
  });

  it('when Stripe can’t be asked, nothing is sent again and the fee stays pending', async () => {
    const id = await noShow();
    h.stripe.loseNextChargeAnswer = true;
    await charge(id);
    h.stripe.nextError = stripeError('StripeConnectionError', {}, 'socket hang up');
    const res = await charge(id);
    expect(res.status).toBe(500);
    expect(res.body.error).toEqual({ code: 'server_error', message: "We couldn't reach Stripe. Please try again." });
    expect(h.logs.at(-1)).toMatchObject({ level: 'error', message: 'Stripe find no-show fee failed' });
    expect(creates()).toHaveLength(1);
    expect((await feeRow(id)).no_show_fee_status).toBe('pending');
  });

  it('a lost answer is still looked up after the booking was reopened, but nothing new is sent then', async () => {
    const charged = await noShow();
    h.stripe.loseNextChargeAnswer = true;
    await charge(charged);
    expect((await setStatus(charged, 'booked')).status).toBe(200);
    // Stripe did charge it: that counts, whatever the status now.
    expect((await charge(charged)).body.appointment.noShowFee.status).toBe('charged');

    const other = (await protectedBooking({ start: '2026-11-03T19:00:00Z' })).id;
    h.setNow('2026-11-03T19:20:00Z');
    await markNoShow(other);
    h.stripe.nextError = stripeError('StripeConnectionError', {}, 'socket hang up');
    await charge(other);
    await setStatus(other, 'booked');
    // Nothing reached Stripe and it isn't a no-show any more: no new request.
    const res = await charge(other);
    expect(res.status).toBe(409);
    expect(res.body.error).toEqual({ code: 'not_chargeable', message: 'Mark the appointment as a no-show first.' });
    expect(creates().filter((c) => (c.params as { metadata: { appointment_id: string } }).metadata.appointment_id === other)).toHaveLength(1);
    expect((await feeRow(other)).no_show_fee_status).toBe('pending');
  });

  it('Stripe down before the charge: pending, and the next try (same key) charges', async () => {
    const id = await noShow();
    h.stripe.nextError = stripeError('StripeConnectionError', {}, 'socket hang up');
    expect((await charge(id)).status).toBe(500);
    expect((await charge(id)).body.appointment.noShowFee.status).toBe('charged');
    expect(new Set(creates().map((c) => (c.options as { idempotencyKey: string }).idempotencyKey))).toEqual(new Set([noShowFeeIdempotencyKey(id, 1)]));
  });

  it('taps at once (two phones, a double tap) charge once', async () => {
    const id = await noShow();
    const results = await Promise.all([charge(id), charge(id), charge(id), charge(id)]);
    for (const r of results) expect([200, 409]).toContain(r.status);
    expect(results.some((r) => r.status === 200 && r.body.appointment.noShowFee.status === 'charged')).toBe(true);
    expect([...h.stripe.intents.values()].filter((pi) => pi.metadata.kind === 'no_show_fee' && pi.status === 'succeeded')).toHaveLength(1);
  });

  it('only for a no-show that has started, with a card on file', async () => {
    const { id } = await protectedBooking();
    const early = await charge(id);
    expect(early.status).toBe(409);
    expect(early.body.error).toEqual({ code: 'not_chargeable', message: 'Mark the appointment as a no-show first.' });
    // A booking with a card on file can't be marked a no-show before it starts (the client may still cancel).
    const tooEarly = await markNoShow(id);
    expect(tooEarly.status).toBe(409);
    expect(tooEarly.body.error).toEqual({ code: 'not_started', message: 'You can mark a no-show once the appointment has started.' });
    expect((await feeRow(id)).status).toBe('booked');
    // One marked before it started anyway (from before that rule): still not chargeable until it starts.
    await h.database.pool.query(`UPDATE appointments SET status = 'no_show' WHERE id = $1`, [id]);
    const notStarted = await charge(id);
    expect(notStarted.body.error).toEqual({ code: 'not_chargeable', message: "The appointment hasn't started yet, so it can't be a no-show." });
    h.setNow('2026-11-03T18:00:00Z');
    expect((await markNoShow(id)).status).toBe(200);
    expect((await charge(id)).status).toBe(200);

    const walkIn = await h.call('POST', '/api/owner/appointments', { ...owner, body: { offeringId: FLOW45, start: '2026-11-03T19:00:00Z', customer: { name: 'Walk-in' } } });
    expect(walkIn.status, walkIn.text).toBe(201);
    // Without a card there's nothing to charge, so marking it early works as before.
    expect((await markNoShow(walkIn.body.appointment.id)).status).toBe(200);
    h.setNow('2026-11-03T19:30:00Z');
    const noCard = await charge(walkIn.body.appointment.id);
    expect(noCard.status).toBe(409);
    expect(noCard.body.error.message).toBe("This booking has no card on file, so there's no fee to charge.");
    expect(creates()).toHaveLength(1);
  });

  it('404 for an unknown appointment; 503 without Stripe; owner key needed', async () => {
    const id = await noShow();
    expect((await charge('00000000-0000-4000-8000-0000000000ff')).status).toBe(404);
    expect((await charge('nope')).status).toBe(404);
    expect((await h.call('POST', `/api/owner/appointments/${id}/no-show-fee`)).status).toBe(401);
    h.config.stripeSecretKey = undefined;
    const off = await charge(id);
    expect(off.status).toBe(503);
    expect(off.body.error.code).toBe('stripe_not_configured');
  });
});

describe('POST /api/stripe/webhook for no-show fees', () => {
  function event(type: string, intent: Record<string, unknown>) {
    return JSON.stringify({
      id: 'evt_fixture_fee',
      object: 'event',
      api_version: '2026-10-28.endive',
      created: Math.floor(Date.now() / 1000),
      type,
      livemode: false,
      pending_webhooks: 1,
      request: { id: null, idempotency_key: null },
      data: { object: { object: 'payment_intent', ...intent } },
    });
  }
  const send = (payload: string) =>
    h.call('POST', '/api/stripe/webhook', {
      rawBody: payload,
      headers: { 'content-type': 'application/json', 'stripe-signature': Stripe.webhooks.generateTestHeaderString({ payload, secret: WEBHOOK_SECRET }) },
    });
  const fee = async (id: string) => (await h.call('GET', '/api/owner/appointments?date=2026-11-03', owner)).body.appointments.find((a: { id: string }) => a.id === id).noShowFee;

  it('a processing fee becomes charged when Stripe says it succeeded, and declined when it failed', async () => {
    const id = await noShow();
    h.stripe.nextCharge = 'processing';
    await charge(id);
    const piId = (await feeRow(id)).no_show_fee_payment_intent_id;
    const metadata = { kind: 'no_show_fee', appointment_id: id, attempt: '1' };
    expect((await send(event('payment_intent.succeeded', { id: piId, status: 'succeeded', metadata }))).status).toBe(200);
    expect(await fee(id)).toMatchObject({ status: 'charged', chargedAt: '2026-11-03T18:20:00Z' });
    // A late failure can't undo it.
    await send(event('payment_intent.payment_failed', { id: piId, status: 'requires_payment_method', metadata }));
    expect((await fee(id)).status).toBe('charged');
    expect((await h.call('GET', '/api/owner/payments?date=2026-11-03', owner)).body.payments[0].status).toBe('succeeded');
  });

  it('failed: declined with the reason; a late "processing" for the same charge can’t make it pending again', async () => {
    const id = await noShow();
    h.stripe.nextCharge = 'processing';
    await charge(id);
    const piId = (await feeRow(id)).no_show_fee_payment_intent_id;
    const metadata = { kind: 'no_show_fee', appointment_id: id, attempt: '1' };
    await send(
      event('payment_intent.payment_failed', {
        id: piId,
        status: 'requires_payment_method',
        metadata,
        last_payment_error: { type: 'card_error', code: 'card_declined', decline_code: 'insufficient_funds' },
      }),
    );
    expect(await fee(id)).toMatchObject({ status: 'declined', message: "The card was declined: there isn't enough money on it." });
    await send(event('payment_intent.processing', { id: piId, status: 'processing', metadata }));
    expect((await fee(id)).status).toBe('declined');
    await send(event('payment_intent.canceled', { id: piId, status: 'canceled', metadata }));
    expect(await fee(id)).toMatchObject({ status: 'declined', message: 'The charge was cancelled in Stripe.' });
  });

  it('a charge the bank wants the client to approve stays "needs the client" when Stripe’s payment_failed comes', async () => {
    const id = await noShow();
    h.stripe.nextCharge = 'authentication_required';
    expect((await charge(id)).body.appointment.noShowFee.status).toBe('needsAction');
    const piId = (await feeRow(id)).no_show_fee_payment_intent_id;
    expect(piId).toMatch(/^pi_/);
    await send(
      event('payment_intent.payment_failed', {
        id: piId,
        status: 'requires_payment_method',
        metadata: { kind: 'no_show_fee', appointment_id: id, attempt: '1' },
        last_payment_error: { type: 'card_error', code: 'authentication_required', decline_code: 'authentication_required' },
      }),
    );
    expect(await fee(id)).toEqual({
      amountCents: 3500,
      fullPrice: true,
      status: 'needsAction',
      chargedAt: null,
      message: AUTHENTICATION_MESSAGE,
      customerCancelledAt: null,
      lateCancelWindowMinutes: 60,
      reason: 'noShow',
    });
  });

  it('a processing charge that then needs the client reads as needsAction, by webhook, by charging again and by …/complete', async () => {
    const authFailed = { status: 'requires_payment_method', last_payment_error: { type: 'card_error', code: 'card_declined', decline_code: 'authentication_required' } };
    // The webhook.
    const first = await noShow();
    h.stripe.nextCharge = 'processing';
    await charge(first);
    const firstPi = (await feeRow(first)).no_show_fee_payment_intent_id;
    await send(event('payment_intent.payment_failed', { id: firstPi, ...authFailed, metadata: { kind: 'no_show_fee', appointment_id: first, attempt: '1' } }));
    expect(await fee(first)).toMatchObject({ status: 'needsAction', message: AUTHENTICATION_MESSAGE });

    // Charging again asks Stripe (retrieve).
    const second = (await protectedBooking({ start: '2026-11-03T19:00:00Z' })).id;
    h.setNow('2026-11-03T19:20:00Z');
    await markNoShow(second);
    h.stripe.nextCharge = 'processing';
    await charge(second);
    const secondPi = (await feeRow(second)).no_show_fee_payment_intent_id;
    Object.assign(h.stripe.intents.get(secondPi)!, authFailed);
    expect((await charge(second)).body.appointment.noShowFee).toMatchObject({ status: 'needsAction', message: AUTHENTICATION_MESSAGE });

    // …/complete.
    const third = (await protectedBooking({ start: '2026-11-03T20:00:00Z' })).id;
    h.setNow('2026-11-03T20:20:00Z');
    await markNoShow(third);
    h.stripe.nextCharge = 'processing';
    await charge(third);
    const thirdPi = (await feeRow(third)).no_show_fee_payment_intent_id;
    Object.assign(h.stripe.intents.get(thirdPi)!, authFailed);
    expect((await h.call('POST', `/api/owner/payments/${thirdPi}/complete`, owner)).body.payment.status).toBe('requires_payment_method');
    expect(await fee(third)).toMatchObject({ status: 'needsAction', message: AUTHENTICATION_MESSAGE });
  });

  it('a charge the server never got to record is found by its metadata', async () => {
    const id = await noShow();
    // The server asked Stripe, Stripe charged, and the function stopped before writing anything.
    h.stripe.loseNextChargeAnswer = true;
    await charge(id);
    const [intent] = [...h.stripe.intents.values()].filter((pi) => pi.metadata.kind === 'no_show_fee');
    expect((await h.database.pool.query('SELECT count(*)::int AS n FROM payments')).rows[0].n).toBe(0);
    await send(event('payment_intent.succeeded', { id: intent!.id, status: 'succeeded', amount: 3500, metadata: intent!.metadata }));
    expect((await fee(id)).status).toBe('charged');
    const payments = (await h.call('GET', '/api/owner/payments?date=2026-11-03', owner)).body.payments;
    expect(payments).toEqual([expect.objectContaining({ id: intent!.id, kind: 'noShowFee', status: 'succeeded', amountCents: 3500, appointmentId: id })]);
    // And charging again now is just the same answer.
    expect((await charge(id)).body.appointment.noShowFee.status).toBe('charged');
  });

  it('an earlier attempt that succeeded after all still counts as charged; its other news doesn’t touch the current try', async () => {
    const id = await noShow();
    h.stripe.nextCharge = 'insufficient_funds';
    await charge(id);
    const first = (await feeRow(id)).no_show_fee_payment_intent_id;
    h.stripe.nextCharge = 'processing';
    await charge(id);
    const second = (await feeRow(id)).no_show_fee_payment_intent_id;
    expect(second).not.toBe(first);
    // Old news about attempt 1 (canceled) doesn't change attempt 2.
    await send(event('payment_intent.canceled', { id: first, status: 'canceled', metadata: { kind: 'no_show_fee', appointment_id: id, attempt: '1' } }));
    expect((await fee(id)).status).toBe('pending');
    await send(event('payment_intent.succeeded', { id: second, status: 'succeeded', metadata: { kind: 'no_show_fee', appointment_id: id, attempt: '2' } }));
    expect((await fee(id)).status).toBe('charged');
  });

  it('a late-cancellation fee the server never got to record is found by its metadata, and listed as one', async () => {
    const booking = await protectedBooking();
    h.setNow('2026-11-03T17:40:00Z');
    expect((await cancelInApp(booking)).body.appointment.noShowFee.reason).toBe('lateCancel');
    h.stripe.loseNextChargeAnswer = true;
    await charge(booking.id);
    const [intent] = [...h.stripe.intents.values()].filter((pi) => pi.metadata.kind === 'late_cancel_fee');
    expect(intent).toBeDefined();
    await send(event('payment_intent.succeeded', { id: intent!.id, status: 'succeeded', amount: 3500, metadata: intent!.metadata }));
    expect(await fee(booking.id)).toMatchObject({ status: 'charged', reason: 'lateCancel' });
    const payments = (await h.call('GET', '/api/owner/payments?date=2026-11-03', owner)).body.payments;
    expect(payments).toEqual([
      expect.objectContaining({
        id: intent!.id,
        kind: 'lateCancelFee',
        status: 'succeeded',
        description: 'Late cancellation fee: Haircut with Flowxbori, Tue, Nov 3 at 10:00 AM',
      }),
    ]);
    // …/complete on it keeps it a late-cancellation fee too.
    expect((await h.call('POST', `/api/owner/payments/${intent!.id}/complete`, owner)).body.payment).toMatchObject({ kind: 'lateCancelFee', status: 'succeeded' });
  });

  it('ignores fee events for appointments it doesn’t know, and in-person payments work as before', async () => {
    await protectedBooking();
    const unknown = event('payment_intent.succeeded', {
      id: 'pi_someone_else',
      status: 'succeeded',
      metadata: { kind: 'no_show_fee', appointment_id: '00000000-0000-4000-8000-0000000000ff', attempt: '1' },
    });
    expect((await send(unknown)).status).toBe(200);
    expect((await send(event('payment_intent.succeeded', { id: 'pi_x', status: 'succeeded', metadata: { kind: 'no_show_fee', appointment_id: 'nope' } }))).status).toBe(200);
    expect((await h.database.pool.query('SELECT count(*)::int AS n FROM payments')).rows[0].n).toBe(0);
  });
});
