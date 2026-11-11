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
/** The client taps Cancel in the app; with `acceptLateCancelFee`, after confirming the late-cancellation warning. */
const cancelInApp = (booking: { id: string; manageToken: string }, options: { acceptLateCancelFee?: unknown } = {}) =>
  h.call('POST', `/api/appointments/${booking.id}/cancel`, {
    headers: { 'x-manage-token': booking.manageToken },
    ...('acceptLateCancelFee' in options ? { body: { acceptLateCancelFee: options.acceptLateCancelFee } } : {}),
  });
const ACCEPT = { acceptLateCancelFee: true } as const;

/** Tuesday 10:50 AM, after the 10–10:45 appointment: the client never came. */
async function noShow(options?: Parameters<typeof protectedBooking>[0]) {
  const appointment = await protectedBooking(options);
  h.setNow('2026-11-03T18:50:00Z');
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
    h.setNow('2026-11-03T18:50:00Z');
    expect((await markNoShow(booking.id)).status).toBe(200);
    const res = await charge(booking.id);
    expect(res.status).toBe(409);
    expect(res.body.error).toEqual(NOT_CHARGEABLE);
    expect(creates()).toHaveLength(0);
    expect((await feeRow(booking.id)).no_show_fee_status).toBe('none');
  });

  it('the shop can’t mark a booking with a card a no-show before it ends, so the client can still cancel or come', async () => {
    const booking = await protectedBooking();
    // 9:50 AM: too early to call it a no-show.
    h.setNow('2026-11-03T17:50:00Z');
    const early = await markNoShow(booking.id);
    expect(early.status).toBe(409);
    expect(early.body.error).toEqual({ code: 'not_started', message: 'You can mark a no-show once the appointment has ended.' });
    // 9:55 AM: the client cancels (after the late-cancellation warning).
    h.setNow('2026-11-03T17:55:00Z');
    expect((await cancelInApp(booking, ACCEPT)).status).toBe(200);
    // 10:50 AM: marked a no-show anyway, but there's nothing to charge.
    h.setNow('2026-11-03T18:50:00Z');
    expect((await markNoShow(booking.id)).status).toBe(200);
    expect((await charge(booking.id)).body.error).toEqual(NOT_CHARGEABLE);
    expect(creates()).toHaveLength(0);
  });

  it('asking to cancel in time counts even when the shop had already marked the booking', async () => {
    const booking = await protectedBooking();
    // 9:50 AM: cancelled by the shop by mistake; 9:55 AM: the client tries to cancel.
    h.setNow('2026-11-03T17:50:00Z');
    expect((await setStatus(booking.id, 'cancelled')).status).toBe(200);
    h.setNow('2026-11-03T17:55:00Z');
    const refused = await cancelInApp(booking);
    expect(refused.status).toBe(409);
    expect(refused.body.error).toEqual({ code: 'not_cancellable', message: 'This appointment is already cancelled.' });
    expect((await feeRow(booking.id)).customer_cancelled_at.toISOString()).toBe('2026-11-03T17:55:00.000Z');
    // Trying again later doesn't move the time.
    h.setNow('2026-11-03T17:58:00Z');
    await cancelInApp(booking);
    expect((await feeRow(booking.id)).customer_cancelled_at.toISOString()).toBe('2026-11-03T17:55:00.000Z');
    // 10:50 AM: reopened, then marked a no-show.
    h.setNow('2026-11-03T18:50:00Z');
    await setStatus(booking.id, 'booked');
    expect((await markNoShow(booking.id)).status).toBe(200);
    expect((await charge(booking.id)).body.error).toEqual(NOT_CHARGEABLE);
    // And on the shop's list, so the app can say why.
    const day = await h.call('GET', '/api/owner/appointments?date=2026-11-03', owner);
    expect(day.body.appointments[0].noShowFee.customerCancelledAt).toBe('2026-11-03T17:55:00Z');
  });

  it('marked completed by mistake: the client’s request still counts, and it can’t become a no-show', async () => {
    const booking = await protectedBooking();
    // 9:50 AM: marked completed by mistake; 9:55 AM: the client tries to cancel.
    h.setNow('2026-11-03T17:50:00Z');
    expect((await setStatus(booking.id, 'completed')).status).toBe(200);
    h.setNow('2026-11-03T17:55:00Z');
    const refused = await cancelInApp(booking);
    expect(refused.status).toBe(409);
    expect(refused.body.error).toEqual({ code: 'not_cancellable', message: "This appointment can't be cancelled any more." });
    expect((await feeRow(booking.id)).customer_cancelled_at.toISOString()).toBe('2026-11-03T17:55:00.000Z');
    // 10:50 AM: reopened, then marked a no-show: once completed, never a no-show.
    h.setNow('2026-11-03T18:50:00Z');
    await setStatus(booking.id, 'booked');
    const mark = await markNoShow(booking.id);
    expect(mark.status).toBe(409);
    expect(mark.body.error).toEqual({ code: 'already_completed', message: "This appointment was marked completed, so it can't become a no-show." });
    expect((await charge(booking.id)).body.error).toEqual({ code: 'not_chargeable', message: "The client cancelled this booking in the app, so there's no fee." });
  });

  it('asking to cancel after the start doesn’t count: the no-show can be charged', async () => {
    const booking = await protectedBooking();
    h.setNow('2026-11-03T18:05:00Z');
    const late = await cancelInApp(booking);
    expect(late.status).toBe(409);
    expect(late.body.error).toEqual({ code: 'not_cancellable', message: 'This appointment has already started. Call the shop if you need help.' });
    expect((await feeRow(booking.id)).customer_cancelled_at).toBeNull();
    h.setNow('2026-11-03T18:50:00Z');
    await markNoShow(booking.id);
    expect((await charge(booking.id)).body.appointment.noShowFee).toMatchObject({ status: 'charged', customerCancelledAt: null });
  });

  it('a client cancelling and the shop marking at the same moment: one wins, and a cancelled booking is never charged', async () => {
    const booking = await protectedBooking();
    h.setNow('2026-11-03T17:59:00Z');
    const [cancel, mark] = await Promise.all([cancelInApp(booking, ACCEPT), setStatus(booking.id, 'completed')]);
    expect(mark.status).toBe(200);
    expect([200, 409]).toContain(cancel.status);
    // Either way the client asked in time.
    expect((await feeRow(booking.id)).customer_cancelled_at).not.toBeNull();
    h.setNow('2026-11-03T18:10:00Z');
    await markNoShow(booking.id);
    expect((await charge(booking.id)).body.error).toEqual(NOT_CHARGEABLE);
  });
});

describe('inside the window the server asks the client to confirm first, by its own clock', () => {
  const LATE_FEE = {
    code: 'late_cancel_fee',
    message: 'Cancelling now, less than 1 hour before your appointment, may be charged $35, the full service price.',
  };

  describe('a time booked inside the window (Tuesday 9:25 AM for 10 AM): the 15-minute grace period', () => {
    const GRACE = { code: 'not_chargeable', message: "The client cancelled within 15 minutes of booking, so there's no fee." };
    async function bookedAt925() {
      h.setNow('2026-11-03T17:25:00Z');
      return protectedBooking();
    }

    it('14 minutes after booking: free, and nothing is asked', async () => {
      const booking = await bookedAt925();
      h.setNow('2026-11-03T17:39:00Z');
      const res = await cancelInApp(booking);
      expect(res.status, res.text).toBe(200);
      expect(res.body.appointment).toMatchObject({ status: 'cancelled', cancelledBy: 'customer' });
      expect(res.body.appointment.noShowFee).toMatchObject({ customerCancelledAt: '2026-11-03T17:39:00Z', reason: null });
      expect((await charge(booking.id)).body.error).toEqual(GRACE);
      expect(creates()).toHaveLength(0);
    });

    it('exactly 15 minutes after booking: still free', async () => {
      const booking = await bookedAt925();
      h.setNow('2026-11-03T17:40:00Z');
      expect((await cancelInApp(booking)).body.appointment.noShowFee.reason).toBeNull();
      expect((await charge(booking.id)).body.error).toEqual(GRACE);
    });

    it('16 minutes after booking: a late cancellation, confirmed first, and it can be charged', async () => {
      const booking = await bookedAt925();
      h.setNow('2026-11-03T17:41:00Z');
      const asked = await cancelInApp(booking);
      expect(asked.status).toBe(409);
      expect(asked.body.error).toEqual(LATE_FEE);
      const res = await cancelInApp(booking, ACCEPT);
      expect(res.body.appointment.noShowFee).toMatchObject({ customerCancelledAt: '2026-11-03T17:41:00Z', reason: 'lateCancel' });
      expect((await charge(booking.id)).body.appointment.noShowFee).toMatchObject({ status: 'charged', reason: 'lateCancel' });
    });
  });

  it('answers 409 late_cancel_fee with the warning and changes nothing; confirmed, it cancels', async () => {
    const booking = await protectedBooking();
    // Tuesday 9:30 AM, for the 10 AM.
    h.setNow('2026-11-03T17:30:00Z');
    const asked = await cancelInApp(booking);
    expect(asked.status).toBe(409);
    expect(asked.body.error).toEqual(LATE_FEE);
    expect(await feeRow(booking.id)).toMatchObject({ status: 'booked', cancelled_by: null, customer_cancelled_at: null });
    // Saying no is the same as not saying.
    expect((await cancelInApp(booking, { acceptLateCancelFee: false })).body.error).toEqual(LATE_FEE);
    const mine = await h.call('GET', `/api/appointments/${booking.id}`, { headers: { 'x-manage-token': booking.manageToken } });
    expect(mine.body.appointment).toMatchObject({ status: 'booked', noShowFee: { customerCancelledAt: null, reason: null } });
    // The client read it and cancels anyway, a minute later: that time counts.
    h.advance(1);
    const cancelled = await cancelInApp(booking, ACCEPT);
    expect(cancelled.status, cancelled.text).toBe(200);
    expect(cancelled.body.appointment).toMatchObject({ status: 'cancelled', cancelledBy: 'customer' });
    expect(cancelled.body.appointment.noShowFee).toMatchObject({ customerCancelledAt: '2026-11-03T17:31:00Z', reason: 'lateCancel' });
    // The owner may charge it, and nothing was charged before.
    expect(creates()).toHaveLength(0);
    expect((await charge(booking.id)).body.appointment.noShowFee.status).toBe('charged');
  });

  it('the server’s clock decides: a dialog opened at 8:59:40 and tapped at 9:00:05 still gets the warning', async () => {
    const tapped = await protectedBooking();
    h.setNow('2026-11-03T17:00:05Z');
    expect((await cancelInApp(tapped)).body.error).toEqual(LATE_FEE);
    expect((await feeRow(tapped.id)).status).toBe('booked');
    // Exactly an hour before is still free, and asks nothing.
    h.setNow('2026-11-02T17:00:00Z');
    const onTime = await protectedBooking({ start: '2026-11-03T19:00:00Z' });
    h.setNow('2026-11-03T18:00:00Z');
    const free = await cancelInApp(onTime);
    expect(free.status, free.text).toBe(200);
    expect(free.body.appointment.noShowFee).toMatchObject({ customerCancelledAt: '2026-11-03T18:00:00Z', reason: null });
  });

  it('asks nothing outside the window, for a policy without late cancellations, or for a booking without a card', async () => {
    const early = await protectedBooking();
    h.setNow('2026-11-03T16:00:00Z'); // 2 hours before
    expect((await cancelInApp(early)).status).toBe(200);

    h.setNow('2026-11-02T17:00:00Z');
    await h.call('PATCH', '/api/owner/no-show-settings', { ...owner, body: { lateCancelEnabled: false } });
    const noLateFee = await protectedBooking({ start: '2026-11-03T19:00:00Z' });
    h.setNow('2026-11-03T18:55:00Z');
    const free = await cancelInApp(noLateFee);
    expect(free.status, free.text).toBe(200);
    expect(free.body.appointment.noShowFee).toMatchObject({ lateCancelWindowMinutes: null, reason: null });

    h.setNow('2026-11-02T17:00:00Z');
    await h.call('PATCH', '/api/owner/no-show-settings', { ...owner, body: { enabled: false } });
    const plain = await h.call('POST', '/api/appointments', {
      body: { offeringId: FLOW45, start: '2026-11-03T20:00:00Z', customer: { name: 'No Card', phone: '4425550171' } },
    });
    expect(plain.status, plain.text).toBe(201);
    h.setNow('2026-11-03T19:55:00Z');
    expect((await cancelInApp({ id: plain.body.appointment.id, manageToken: plain.body.manageToken })).status).toBe(200);
  });

  it('a request inside the window the status turned down still counts; once reopened, cancelling asks first', async () => {
    const booking = await protectedBooking();
    // 9:20 AM: marked completed by mistake; 9:30 AM: the client taps Cancel.
    h.setNow('2026-11-03T17:20:00Z');
    await setStatus(booking.id, 'completed');
    h.setNow('2026-11-03T17:30:00Z');
    const refused = await cancelInApp(booking);
    expect(refused.status).toBe(409);
    expect(refused.body.error).toEqual({ code: 'not_cancellable', message: "This appointment can't be cancelled any more." });
    expect((await feeRow(booking.id)).customer_cancelled_at.toISOString()).toBe('2026-11-03T17:30:00.000Z');
    // 9:35 AM: reopened; 9:40 AM: the client cancels again. The 9:30 request counts, so it's late.
    h.setNow('2026-11-03T17:35:00Z');
    await setStatus(booking.id, 'booked');
    h.setNow('2026-11-03T17:40:00Z');
    expect((await cancelInApp(booking)).body.error).toEqual(LATE_FEE);
    const cancelled = await cancelInApp(booking, ACCEPT);
    expect(cancelled.body.appointment.noShowFee).toMatchObject({ customerCancelledAt: '2026-11-03T17:30:00Z', reason: 'lateCancel' });
  });

  it('acceptLateCancelFee must be true or false; the body stays optional', async () => {
    const booking = await protectedBooking();
    h.setNow('2026-11-03T17:30:00Z');
    const wrong = await cancelInApp(booking, { acceptLateCancelFee: 'yes' });
    expect(wrong.status).toBe(400);
    expect(wrong.body.error).toEqual({ code: 'invalid_request', message: 'acceptLateCancelFee must be true or false.' });
    const notJson = await h.call('POST', `/api/appointments/${booking.id}/cancel`, {
      headers: { 'x-manage-token': booking.manageToken, 'content-type': 'text/plain' },
      rawBody: 'acceptLateCancelFee=true',
    });
    expect(notJson.status).toBe(415);
    // `{}` (what the apps send without the flag) is like no body at all; other fields are ignored.
    const empty = await h.call('POST', `/api/appointments/${booking.id}/cancel`, { headers: { 'x-manage-token': booking.manageToken }, body: {} });
    expect(empty.body.error).toEqual(LATE_FEE);
    const extra = await h.call('POST', `/api/appointments/${booking.id}/cancel`, {
      headers: { 'x-manage-token': booking.manageToken },
      body: { reason: 'running late', acceptLateCancelFee: true },
    });
    expect(extra.status, extra.text).toBe(200);
    // A wrong token is still a 404 first.
    expect((await cancelInApp({ id: booking.id, manageToken: newManageToken() }, { acceptLateCancelFee: 'yes' })).status).toBe(404);
  });

  it('a fee less than the full price is warned as the amount alone', async () => {
    await protectionOn(h);
    await h.call('PATCH', '/api/owner/no-show-settings', { ...owner, body: { percent: 50 } });
    const booking = await protectedBooking();
    h.setNow('2026-11-03T17:30:00Z');
    expect((await cancelInApp(booking)).body.error).toEqual({
      code: 'late_cancel_fee',
      message: 'Cancelling now, less than 1 hour before your appointment, may be charged $17.50.',
    });
  });
});

describe('late cancellations: the client cancels less than the agreed window before the start', () => {
  /** A protected booking for `start`, cancelled in the app at `cancelAt` (the client confirmed the warning, if there was one). */
  async function cancelledAt(cancelAt: string, start = TUE10) {
    const booking = await protectedBooking({ start });
    h.setNow(cancelAt);
    const res = await cancelInApp(booking, ACCEPT);
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

  it('the cancel time is kept to the second, as the apps read it: 400 ms inside the window is still exactly 1 hour before', async () => {
    // 9:00:00.400 AM for the 10 AM booking, 59 min 59.6 s before. The JSON says 9:00:00, so the
    // owner app reads exactly 1 hour before (free), and the server decides the same: no warning, no fee.
    const booking = await protectedBooking();
    h.setNow('2026-11-03T17:00:00.400Z');
    const free = await cancelInApp(booking);
    expect(free.status, free.text).toBe(200);
    expect(free.body.appointment.noShowFee).toMatchObject({ customerCancelledAt: '2026-11-03T17:00:00Z', reason: null });
    expect((await feeRow(booking.id)).customer_cancelled_at.toISOString()).toBe('2026-11-03T17:00:00.000Z');
    const refused = await charge(booking.id);
    expect(refused.status).toBe(409);
    expect(refused.body.error).toEqual({ code: 'not_chargeable', message: "The client cancelled at least 1 hour before, so there's no fee." });

    // One whole second inside is late, for the server and as the apps read it.
    h.setNow('2026-11-02T17:00:00Z');
    const later = await protectedBooking({ start: '2026-11-03T19:00:00Z' });
    h.setNow('2026-11-03T18:00:01.400Z');
    expect((await cancelInApp(later)).body.error.code).toBe('late_cancel_fee');
    const late = await cancelInApp(later, ACCEPT);
    expect(late.status, late.text).toBe(200);
    expect(late.body.appointment.noShowFee).toMatchObject({ customerCancelledAt: '2026-11-03T18:00:01Z', reason: 'lateCancel' });
    expect((await feeRow(later.id)).customer_cancelled_at.toISOString()).toBe('2026-11-03T18:00:01.000Z');
    expect((await charge(later.id)).body.appointment.noShowFee.status).toBe('charged');

    // A request the status turned down keeps its time the same way.
    h.setNow('2026-11-02T17:00:00Z');
    const marked = await protectedBooking({ start: '2026-11-03T20:00:00Z' });
    expect((await setStatus(marked.id, 'completed')).status).toBe(200);
    h.setNow('2026-11-03T19:00:00.700Z');
    expect((await cancelInApp(marked)).status).toBe(409);
    expect((await feeRow(marked.id)).customer_cancelled_at.toISOString()).toBe('2026-11-03T19:00:00.000Z');
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
    h.setNow('2026-11-03T18:50:00Z');
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
    // …nor once the shop cancels it again, or marks it a no-show after the end.
    expect((await setStatus(late.id, 'cancelled')).body.appointment.cancelledBy).toBe('shop');
    expect((await charge(late.id)).body.error).toEqual(SHOP);
    h.setNow('2026-11-03T19:50:00Z');
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
      chargedAt: '2026-11-03T18:50:00Z',
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
        createdAt: '2026-11-03T18:50:00Z',
        kind: 'noShowFee',
        saleId: null,
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
    const other = (await protectedBooking({ start: '2026-11-03T20:00:00Z' })).id;
    h.setNow('2026-11-03T20:50:00Z');
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
    // Charged when Stripe's charge went through, not when the owner checked two minutes later.
    expect(done.body.appointment.noShowFee).toMatchObject({ status: 'charged', chargedAt: '2026-11-03T18:50:00Z' });
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
    expect((await feeRow(id)).no_show_fee_attempt_at.toISOString()).toBe('2026-11-03T18:50:00.000Z');
    const day = await h.call('GET', '/api/owner/appointments?date=2026-11-03', owner);
    expect(day.body.appointments[0].noShowFee.status).toBe('pending');

    h.advance(3);
    const retry = await charge(id);
    // Charged when the money moved (the lost try), not when the server found out.
    expect(retry.body.appointment.noShowFee).toMatchObject({ status: 'charged', chargedAt: '2026-11-03T18:50:00Z' });
    // Asked Stripe for this attempt's PaymentIntent: the card's own Customer, since the attempt began.
    const card = await h.database.pool.query('SELECT stripe_customer_id FROM saved_cards');
    const lists = h.stripe.calls.filter((c) => c.method === 'paymentIntents.list');
    expect(lists.map((c) => c.params)).toEqual([
      { customer: card.rows[0].stripe_customer_id, created: { gte: Date.parse('2026-11-03T18:50:00Z') / 1000 - 3600 }, limit: 100 },
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
    h.setNow('2026-11-03T18:50:00Z');
    await markNoShow(first);
    expect((await charge(first)).body.appointment.noShowFee.status).toBe('charged');
    h.setNow('2026-11-03T19:50:00Z');
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

  it('a lost answer is still looked up after the booking was reopened; nothing new is sent then, and nothing was charged', async () => {
    const charged = await noShow();
    h.stripe.loseNextChargeAnswer = true;
    await charge(charged);
    expect((await setStatus(charged, 'booked')).status).toBe(200);
    // Stripe did charge it: that counts, whatever the status now.
    expect((await charge(charged)).body.appointment.noShowFee.status).toBe('charged');

    const other = (await protectedBooking({ start: '2026-11-03T20:00:00Z' })).id;
    h.setNow('2026-11-03T20:50:00Z');
    await markNoShow(other);
    h.stripe.nextError = stripeError('StripeConnectionError', {}, 'socket hang up');
    await charge(other);
    await setStatus(other, 'booked');
    // Nothing reached Stripe and it isn't a no-show any more: no new request, and the try is settled as not charged.
    const res = await charge(other);
    expect(res.status).toBe(409);
    expect(res.body.error).toEqual({ code: 'not_chargeable', message: 'Nothing was charged. Mark the appointment as a no-show first.' });
    expect(creates().filter((c) => (c.params as { metadata: { appointment_id: string } }).metadata.appointment_id === other)).toHaveLength(1);
    expect((await feeRow(other)).no_show_fee_status).toBe('none');
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

  it('only for a no-show that has ended, with a card on file', async () => {
    const { id } = await protectedBooking();
    const early = await charge(id);
    expect(early.status).toBe(409);
    expect(early.body.error).toEqual({ code: 'not_chargeable', message: 'Mark the appointment as a no-show first.' });
    // A booking with a card on file can't be marked a no-show before it ends (the client may still cancel, or come).
    const NOT_ENDED = { code: 'not_started', message: 'You can mark a no-show once the appointment has ended.' };
    const tooEarly = await markNoShow(id);
    expect(tooEarly.status).toBe(409);
    expect(tooEarly.body.error).toEqual(NOT_ENDED);
    // 10:44 AM, a minute before its 10:45 end: it has started, but it's still too early.
    h.setNow('2026-11-03T18:44:00Z');
    const minuteBefore = await markNoShow(id);
    expect(minuteBefore.status).toBe(409);
    expect(minuteBefore.body.error).toEqual(NOT_ENDED);
    expect((await feeRow(id)).status).toBe('booked');
    // One marked before it ended anyway (from before that rule): still not chargeable until it ends.
    await h.database.pool.query(`UPDATE appointments SET status = 'no_show' WHERE id = $1`, [id]);
    const notEnded = await charge(id);
    expect(notEnded.status).toBe(409);
    expect(notEnded.body.error).toEqual({ code: 'not_chargeable', message: "The appointment hasn't ended yet, so it can't be a no-show." });
    expect(creates()).toHaveLength(0);
    // 10:46 AM, a minute after the end: marked, and charged.
    h.setNow('2026-11-03T18:46:00Z');
    await h.database.pool.query(`UPDATE appointments SET status = 'booked' WHERE id = $1`, [id]);
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

  it('a completed booking with a card on file stays completed: never a no-show, even after it’s reopened', async () => {
    const DONE = { code: 'already_completed', message: "This appointment was marked completed, so it can't become a no-show." };
    const booking = await protectedBooking();
    const { id } = booking;
    // The shop's view says when it was first completed (the client's never does): nothing yet.
    const ownerView = async (appointmentId: string) =>
      ((await h.call('GET', '/api/owner/appointments?date=2026-11-03', owner)).body.appointments as { id: string; completedAt: string | null }[]).find(
        (a) => a.id === appointmentId,
      )!;
    expect((await ownerView(id)).completedAt).toBeNull();
    // 10:30 AM: the client came, and the visit is marked completed.
    h.setNow('2026-11-03T18:30:00Z');
    const completed = await setStatus(id, 'completed');
    expect(completed.status).toBe(200);
    expect(completed.body.appointment.completedAt).toBe('2026-11-03T18:30:00Z');
    // 10:50 AM, after the end: marking it a no-show (by mistake) is refused.
    h.setNow('2026-11-03T18:50:00Z');
    const mark = await markNoShow(id);
    expect(mark.status).toBe(409);
    expect(mark.body.error).toEqual(DONE);
    expect((await feeRow(id)).status).toBe('completed');
    // Reopened first, it still can't become one: the client came. The shop's view still says so,
    // so the website and the apps can tell before trying.
    const reopened = await setStatus(id, 'booked');
    expect(reopened.status).toBe(200);
    expect(reopened.body.appointment).toMatchObject({ status: 'booked', completedAt: '2026-11-03T18:30:00Z' });
    expect((await ownerView(id)).completedAt).toBe('2026-11-03T18:30:00Z');
    const clientView = await h.call('GET', `/api/appointments/${id}`, { headers: { 'x-manage-token': booking.manageToken } });
    expect(clientView.status, clientView.text).toBe(200);
    expect(clientView.body.appointment).not.toHaveProperty('completedAt');
    expect(clientView.body.appointment).not.toHaveProperty('sale');
    expect((await markNoShow(id)).body.error).toEqual(DONE);
    const res = await charge(id);
    expect(res.status).toBe(409);
    expect(res.body.error).toEqual({ code: 'not_chargeable', message: 'Mark the appointment as a no-show first.' });
    // Completed again (it keeps the first time), and the fee can't be charged either.
    h.setNow('2026-11-03T18:55:00Z');
    expect((await setStatus(id, 'completed')).body.appointment.completedAt).toBe('2026-11-03T18:30:00Z');
    expect((await charge(id)).body.error).toEqual({ code: 'not_chargeable', message: "The appointment is marked completed, so there's no fee to charge." });
    expect(creates()).toHaveLength(0);
    // A checkout counts as completed too, and is remembered after its sale is voided and it's reopened.
    const other = (await protectedBooking({ start: '2026-11-03T20:00:00Z' })).id;
    h.setNow('2026-11-03T20:30:00Z');
    const sale = await h.call('POST', '/api/owner/sales', { ...owner, body: { method: 'cash', appointmentId: other, items: [{ kind: 'service', serviceId: 'haircut' }] } });
    expect(sale.status, sale.text).toBe(201);
    await h.call('POST', `/api/owner/sales/${sale.body.sale.id}/void`, { ...owner, body: {} });
    expect((await setStatus(other, 'booked')).body.appointment).toMatchObject({ status: 'booked', sale: null, completedAt: '2026-11-03T20:30:00Z' });
    h.setNow('2026-11-03T20:50:00Z');
    expect((await markNoShow(other)).body.error).toEqual(DONE);
    // Without a card there's no fee, so the shop can change it as before.
    const walkIn = await h.call('POST', '/api/owner/appointments', { ...owner, body: { offeringId: FLOW45, start: '2026-11-03T22:00:00Z', customer: { name: 'Walk-in' } } });
    expect((await setStatus(walkIn.body.appointment.id, 'completed')).status).toBe(200);
    expect((await markNoShow(walkIn.body.appointment.id)).status).toBe(200);
  });

  it('no new try more than 7 days after the start', async () => {
    const DEADLINE = { code: 'not_chargeable', message: "It's more than 7 days after the appointment, so the fee can't be charged." };
    const id = await noShow();
    // Tuesday Nov 10, 9:59 AM: 7 days after the 10 AM start, less a minute: it can still be charged.
    const late = await protectedBooking({ start: '2026-11-03T20:00:00Z' });
    h.setNow('2026-11-03T20:50:00Z');
    expect((await markNoShow(late.id)).status).toBe(200);
    h.setNow('2026-11-10T17:59:00Z');
    expect((await charge(id)).body.appointment.noShowFee).toMatchObject({ status: 'charged', chargedAt: '2026-11-10T17:59:00Z' });
    // The 12 PM one at 12:01 PM a week later: too late, and nothing goes to Stripe.
    h.setNow('2026-11-10T20:01:00Z');
    const refused = await charge(late.id);
    expect(refused.status).toBe(409);
    expect(refused.body.error).toEqual(DEADLINE);
    expect(creates()).toHaveLength(1);
    expect((await feeRow(late.id)).no_show_fee_status).toBe('none');
    // Late cancellations too (Wednesday's 10 AM and noon, each cancelled half an hour before), and a
    // booking still marked booked hears the same, rather than to mark a no-show first.
    h.setNow('2026-11-02T17:00:00Z');
    const tenAm = await protectedBooking({ start: '2026-11-04T18:00:00Z' });
    const noon = await protectedBooking({ start: '2026-11-04T20:00:00Z' });
    const unmarked = await protectedBooking({ start: '2026-11-04T19:00:00Z' });
    h.setNow('2026-11-04T17:30:00Z');
    expect((await cancelInApp(tenAm, ACCEPT)).body.appointment.noShowFee.reason).toBe('lateCancel');
    h.setNow('2026-11-04T19:30:00Z');
    expect((await cancelInApp(noon, ACCEPT)).body.appointment.noShowFee.reason).toBe('lateCancel');
    h.setNow('2026-11-11T18:01:00Z');
    expect((await charge(tenAm.id)).body.error).toEqual(DEADLINE);
    h.setNow('2026-11-11T19:01:00Z');
    expect((await charge(unmarked.id)).body.error).toEqual(DEADLINE);
    h.setNow('2026-11-11T19:59:00Z');
    expect((await charge(noon.id)).body.appointment.noShowFee).toMatchObject({ status: 'charged', reason: 'lateCancel' });
  });

  it('a try whose answer was lost is still looked up after the 7 days, and settled as not charged when Stripe never got it', async () => {
    const id = await noShow();
    h.stripe.nextError = stripeError('StripeConnectionError', {}, 'socket hang up');
    expect((await charge(id)).status).toBe(500);
    expect((await feeRow(id)).no_show_fee_status).toBe('pending');
    // Eight days later, Check again: Stripe is asked, has nothing, and nothing new is sent.
    h.setNow('2026-11-11T19:00:00Z');
    const res = await charge(id);
    expect(res.status).toBe(409);
    expect(res.body.error).toEqual({
      code: 'not_chargeable',
      message: "Nothing was charged. It's more than 7 days after the appointment, so the fee can't be charged.",
    });
    expect(creates()).toHaveLength(1);
    expect(h.stripe.calls.filter((c) => c.method === 'paymentIntents.list')).toHaveLength(1);
    expect((await feeRow(id)).no_show_fee_status).toBe('none');
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
    expect(await fee(id)).toMatchObject({ status: 'charged', chargedAt: '2026-11-03T18:50:00Z' });
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
    // Three no-shows on Tuesday: at 10 AM, noon and 1 PM.
    const second = (await protectedBooking({ start: '2026-11-03T20:00:00Z' })).id;
    const third = (await protectedBooking({ start: '2026-11-03T21:00:00Z' })).id;
    // The webhook.
    const first = await noShow();
    h.stripe.nextCharge = 'processing';
    await charge(first);
    const firstPi = (await feeRow(first)).no_show_fee_payment_intent_id;
    await send(event('payment_intent.payment_failed', { id: firstPi, ...authFailed, metadata: { kind: 'no_show_fee', appointment_id: first, attempt: '1' } }));
    expect(await fee(first)).toMatchObject({ status: 'needsAction', message: AUTHENTICATION_MESSAGE });

    // Charging again asks Stripe (retrieve).
    h.setNow('2026-11-03T20:50:00Z');
    await markNoShow(second);
    h.stripe.nextCharge = 'processing';
    await charge(second);
    const secondPi = (await feeRow(second)).no_show_fee_payment_intent_id;
    Object.assign(h.stripe.intents.get(secondPi)!, authFailed);
    expect((await charge(second)).body.appointment.noShowFee).toMatchObject({ status: 'needsAction', message: AUTHENTICATION_MESSAGE });

    // …/complete.
    h.setNow('2026-11-03T21:50:00Z');
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
    expect((await cancelInApp(booking, ACCEPT)).body.appointment.noShowFee.reason).toBe('lateCancel');
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

describe('a try Stripe never got, on a booking that can’t be charged any more, is settled as not charged', () => {
  const NOTHING = { code: 'not_chargeable', message: 'Nothing was charged. Mark the appointment as a no-show first.' };
  const NOTHING_COMPLETED = { code: 'not_chargeable', message: "Nothing was charged. The appointment is marked completed, so there's no fee to charge." };
  const lookups = () => h.stripe.calls.filter((c) => c.method === 'paymentIntents.list').length;
  const feeIntents = (id: string) => [...h.stripe.intents.values()].filter((pi) => pi.metadata.appointment_id === id);
  /** The Stripe Customer of the card this appointment was booked with. */
  const customerOf = async (id: string): Promise<string> =>
    (
      await h.database.pool.query(
        'SELECT c.stripe_customer_id FROM saved_cards c JOIN appointments a ON a.saved_card_id = c.id WHERE a.id = $1',
        [id],
      )
    ).rows[0].stripe_customer_id;
  function succeededEvent(intent: { id: string; metadata: Record<string, string> }) {
    const payload = JSON.stringify({
      id: 'evt_fixture_settle',
      object: 'event',
      api_version: '2026-10-28.endive',
      created: Math.floor(h.now.getTime() / 1000),
      type: 'payment_intent.succeeded',
      livemode: false,
      pending_webhooks: 1,
      request: { id: null, idempotency_key: null },
      data: { object: { object: 'payment_intent', id: intent.id, status: 'succeeded', amount: 3500, metadata: intent.metadata } },
    });
    return h.call('POST', '/api/stripe/webhook', {
      rawBody: payload,
      headers: { 'content-type': 'application/json', 'stripe-signature': Stripe.webhooks.generateTestHeaderString({ payload, secret: WEBHOOK_SECRET }) },
    });
  }

  /**
   * Kim didn't come by the end; Charge fails before reaching Stripe (the fee stays pending); then
   * the shop reopens the booking (she called: she's on her way) and, with `then: 'completed'`, fits
   * her in after all.
   */
  async function lostThenCame(start = TUE10, then: 'booked' | 'completed' = 'booked') {
    h.setNow('2026-11-02T17:00:00Z');
    const { id } = await protectedBooking({ start });
    h.setNow(new Date(new Date(start).getTime() + 50 * 60_000).toISOString());
    expect((await markNoShow(id)).status).toBe(200);
    h.stripe.nextError = stripeError('StripeConnectionError', {}, 'socket hang up');
    expect((await charge(id)).status).toBe(500);
    expect((await feeRow(id)).no_show_fee_status).toBe('pending');
    h.advance(5);
    const reopened = await setStatus(id, 'booked');
    expect(reopened.body.appointment.noShowFee).toMatchObject({ status: 'pending', reason: 'noShow' });
    if (then === 'completed') {
      const done = await setStatus(id, 'completed');
      expect(done.body.appointment.noShowFee).toMatchObject({ status: 'pending', reason: 'noShow' });
    }
    return id;
  }

  it('Check again asks Stripe, finds nothing, and settles it: no fee pending on a completed visit', async () => {
    const id = await lostThenCame(TUE10, 'completed');
    const res = await charge(id);
    expect(res.status).toBe(409);
    expect(res.body.error).toEqual(NOTHING_COMPLETED);
    expect(lookups()).toBe(1);
    expect(creates()).toHaveLength(1);
    // Both apps now see no fee pending, and why there's none today.
    const day = await h.call('GET', '/api/owner/appointments?date=2026-11-03', owner);
    expect(day.body.appointments[0].noShowFee).toEqual({
      amountCents: 3500,
      fullPrice: true,
      status: 'none',
      chargedAt: null,
      message: null,
      customerCancelledAt: null,
      lateCancelWindowMinutes: 60,
      reason: null,
    });
    expect((await h.call('GET', '/api/owner/payments?date=2026-11-03', owner)).body.payments).toEqual([]);
    expect(h.logs.at(-1)).toMatchObject({ level: 'warn', message: 'Settled a fee Stripe never got as not charged' });
    // The attempt stays on the row (its key may still be used), and asking again needs no Stripe call.
    expect(await feeRow(id)).toMatchObject({ no_show_fee_attempt: 1, no_show_fee_reason: 'no_show', no_show_fee_payment_intent_id: null });
    const again = await charge(id);
    expect(again.body.error).toEqual({ code: 'not_chargeable', message: "The appointment is marked completed, so there's no fee to charge." });
    expect(lookups()).toBe(1);
    // And a completed visit never becomes a no-show, so that try is never picked up again.
    expect((await setStatus(id, 'noShow')).body.error.code).toBe('already_completed');
  });

  it('Check again on a reopened booking settles it the same way, saying to mark a no-show first', async () => {
    const id = await lostThenCame();
    const res = await charge(id);
    expect(res.status).toBe(409);
    expect(res.body.error).toEqual(NOTHING);
    expect(lookups()).toBe(1);
    expect(creates()).toHaveLength(1);
    expect((await feeRow(id)).no_show_fee_status).toBe('none');
  });

  it('marked a no-show again later, the charge picks up that same try: looked up first, sent with the same key, charged once', async () => {
    const id = await lostThenCame();
    await charge(id);
    expect((await setStatus(id, 'noShow')).status).toBe(200);
    const res = await charge(id);
    expect(res.status, res.text).toBe(200);
    expect(res.body.appointment.noShowFee).toMatchObject({ status: 'charged', reason: 'noShow' });
    expect(lookups()).toBe(2);
    expect(creates().map((c) => (c.options as { idempotencyKey: string }).idempotencyKey)).toEqual([
      noShowFeeIdempotencyKey(id, 1),
      noShowFeeIdempotencyKey(id, 1),
    ]);
    expect(feeIntents(id).map((pi) => [pi.metadata.attempt, pi.status])).toEqual([['1', 'succeeded']]);
  });

  it('a request of that try that reached Stripe after all is found, or recorded from the webhook, never charged again', async () => {
    const id = await lostThenCame();
    await charge(id);
    // Stripe got the lost request after all, and charged it.
    const late = await h.stripe.paymentIntents.create({
      amount: 3500,
      currency: 'usd',
      customer: await customerOf(id),
      metadata: { source: 'izzy-clipz-api', kind: 'no_show_fee', appointment_id: id, attempt: '1' },
    });
    h.stripe.succeed(late.id);
    // The webhook says so: charged, whatever the booking's status.
    expect((await succeededEvent(late)).status).toBe(200);
    expect((await feeRow(id)).no_show_fee_status).toBe('charged');

    // The same, found by the look-up when the owner charges a later no-show for it instead.
    const other = await lostThenCame('2026-11-03T19:00:00Z');
    await charge(other);
    const found = await h.stripe.paymentIntents.create({
      amount: 3500,
      currency: 'usd',
      customer: await customerOf(other),
      metadata: { source: 'izzy-clipz-api', kind: 'no_show_fee', appointment_id: other, attempt: '1' },
    });
    h.stripe.succeed(found.id);
    await setStatus(other, 'noShow');
    const res = await charge(other);
    expect(res.body.appointment.noShowFee).toMatchObject({ status: 'charged', reason: 'noShow' });
    expect(creates().filter((c) => (c.params as { metadata: { appointment_id: string } }).metadata.appointment_id === other)).toHaveLength(1);
  });

  it('an answer that arrives while it settles wins: the appointment as it is now', async () => {
    const id = await lostThenCame();
    const card = await customerOf(id);
    const realList = h.stripe.paymentIntents.list;
    h.stripe.paymentIntents.list = async (params) => {
      const page = await realList(params);
      // Right after Stripe answered "nothing", the lost request lands and its webhook comes in.
      h.stripe.paymentIntents.list = realList;
      const late = await h.stripe.paymentIntents.create({
        amount: 3500,
        currency: 'usd',
        customer: card,
        metadata: { source: 'izzy-clipz-api', kind: 'no_show_fee', appointment_id: id, attempt: '1' },
      });
      h.stripe.succeed(late.id);
      expect((await succeededEvent(late)).status).toBe(200);
      return page;
    };
    const res = await charge(id);
    expect(res.status, res.text).toBe(200);
    expect(res.body.appointment.noShowFee).toMatchObject({ status: 'charged', reason: 'noShow' });
  });

  it('a late cancellation’s lost try, once the shop reopened the booking, says why there’s no fee now', async () => {
    const booking = await protectedBooking();
    h.setNow('2026-11-03T17:40:00Z');
    expect((await cancelInApp(booking, ACCEPT)).body.appointment.noShowFee.reason).toBe('lateCancel');
    h.stripe.nextError = stripeError('StripeConnectionError', {}, 'socket hang up');
    expect((await charge(booking.id)).status).toBe(500);
    await setStatus(booking.id, 'booked');
    const res = await charge(booking.id);
    expect(res.body.error).toEqual({
      code: 'not_chargeable',
      message: "Nothing was charged. The client cancelled this booking in the app, so there's no fee.",
    });
    expect((await feeRow(booking.id)).no_show_fee_status).toBe('none');
    // The client cancels again (still late, the first time counts): the fee picks up that try.
    h.advance(5);
    expect((await cancelInApp(booking)).body.error.code).toBe('late_cancel_fee');
    expect((await cancelInApp(booking, ACCEPT)).body.appointment.noShowFee).toMatchObject({ status: 'none', reason: 'lateCancel' });
    const charged = await charge(booking.id);
    expect(charged.body.appointment.noShowFee).toMatchObject({ status: 'charged', reason: 'lateCancel' });
    expect(creates().map((c) => (c.options as { idempotencyKey: string }).idempotencyKey)).toEqual([
      noShowFeeIdempotencyKey(booking.id, 1),
      noShowFeeIdempotencyKey(booking.id, 1),
    ]);
  });

  it('a pending charge Stripe is still working on is only asked about, never settled', async () => {
    const id = await noShow();
    h.stripe.nextCharge = 'processing';
    expect((await charge(id)).body.appointment.noShowFee.status).toBe('pending');
    await setStatus(id, 'booked');
    await setStatus(id, 'completed');
    // Check again: Stripe still says processing, so it stays pending (the webhook settles it).
    const res = await charge(id);
    expect(res.status).toBe(200);
    expect(res.body.appointment.noShowFee.status).toBe('pending');
    expect(h.stripe.calls.filter((c) => c.method === 'paymentIntents.retrieve')).toHaveLength(1);
    expect(lookups()).toBe(0);
  });
});
