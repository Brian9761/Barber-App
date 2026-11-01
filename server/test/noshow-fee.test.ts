import Stripe from 'stripe';
import { describe, expect, it } from 'vitest';
import { newManageToken } from '../src/auth.js';
import { declineMessage, feeStatusFor, noShowFeeIdempotencyKey } from '../src/noshowfee.js';
import { RESPONSES } from './helpers/contract.js';
import { stripeError, useHarness } from './helpers/harness.js';

// Charging a no-show fee to the card on file, and keeping it right from
// Stripe's webhook. Only a PaymentIntent Stripe reports as succeeded is "charged".

// Monday Nov 2 2026, 9:00 AM PST.
const h = useHarness({ now: '2026-11-02T17:00:00Z' });

const FLOW45 = 'flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a';
const TUE10 = '2026-11-03T18:00:00Z';
const WEBHOOK_SECRET = 'whsec_fixture_fee';
const owner = { owner: true } as const;

/** A protected booking for Tuesday 10 AM with a saved Visa 4242. */
async function protectedBooking(options: { email?: string; start?: string } = {}) {
  h.config.stripeSecretKey = 'sk_test_fixture';
  h.config.stripeWebhookSecret = WEBHOOK_SECRET;
  const token = newManageToken();
  const checkout = await h.call('POST', '/api/cards/checkout', { headers: { 'x-card-token': token }, body: { offeringId: FLOW45 }, ip: '192.0.2.201' });
  h.stripe.completeSession(checkout.body.sessionId);
  await h.call('POST', '/api/cards', { headers: { 'x-card-token': token }, body: { sessionId: checkout.body.sessionId }, ip: '192.0.2.201' });
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
  return res.body.appointment as { id: string };
}

const charge = (id: string) => h.call('POST', `/api/owner/appointments/${id}/no-show-fee`, owner);
const markNoShow = (id: string) => h.call('PATCH', `/api/owner/appointments/${id}`, { ...owner, body: { status: 'noShow' } });

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
});

describe('POST /api/owner/appointments/:id/no-show-fee', () => {
  it('charges the agreed fee off-session to the card on file, once, with an idempotency key', async () => {
    const id = await noShow({ email: 'andre@example.com' });
    const res = await charge(id);
    expect(res.status).toBe(200);
    expect(RESPONSES['no-show-fee-charged'].safeParse(res.body).success).toBe(true);
    expect(res.body.appointment.noShowFee).toEqual({ amountCents: 1750, status: 'charged', chargedAt: '2026-11-03T18:20:00Z', message: null });
    // A no-show fee isn't a payment for the service.
    expect(res.body.appointment.payment).toEqual({ status: 'unpaid', amountCents: null, paidAt: null });

    const [call] = creates();
    const card = await h.database.pool.query('SELECT stripe_customer_id, stripe_payment_method_id FROM saved_cards');
    expect(call!.params).toEqual({
      amount: 1750,
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
        amountCents: 1750,
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
      amountCents: 1750,
      status: 'declined',
      chargedAt: null,
      message: "The card was declined: there isn't enough money on it.",
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
      amountCents: 1750,
      status: 'needsAction',
      chargedAt: null,
      message: "The client's bank wants them to approve this charge, so it can't go through from here. Ask them to pay at the shop.",
    });
    // A PaymentIntent left needing action (never with off_session in practice) reads the same.
    const other = await noShow({ start: '2026-11-03T19:00:00Z' });
    h.setNow('2026-11-03T19:20:00Z');
    await markNoShow(other);
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

  it('a lost answer leaves it pending; charging again uses the same key, so Stripe answers with the same charge', async () => {
    const id = await noShow();
    h.stripe.loseNextChargeAnswer = true;
    const lost = await charge(id);
    expect(lost.status).toBe(500);
    expect(lost.body.error).toEqual({ code: 'server_error', message: "We couldn't reach Stripe. Please try again." });
    expect((await feeRow(id)).no_show_fee_status).toBe('pending');
    const day = await h.call('GET', '/api/owner/appointments?date=2026-11-03', owner);
    expect(day.body.appointments[0].noShowFee.status).toBe('pending');

    const retry = await charge(id);
    expect(retry.body.appointment.noShowFee.status).toBe('charged');
    const keys = creates().map((c) => (c.options as { idempotencyKey: string }).idempotencyKey);
    expect(keys).toEqual([noShowFeeIdempotencyKey(id, 1), noShowFeeIdempotencyKey(id, 1)]);
    // One PaymentIntent at Stripe: the money moved once.
    expect([...h.stripe.intents.values()].filter((pi) => pi.metadata.kind === 'no_show_fee')).toHaveLength(1);
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
    // Marked a no-show before it started.
    await markNoShow(id);
    const notStarted = await charge(id);
    expect(notStarted.body.error).toEqual({ code: 'not_chargeable', message: "The appointment hasn't started yet, so it can't be a no-show." });
    h.setNow('2026-11-03T18:00:00Z');
    expect((await charge(id)).status).toBe(200);

    const walkIn = await h.call('POST', '/api/owner/appointments', { ...owner, body: { offeringId: FLOW45, start: '2026-11-03T19:00:00Z', customer: { name: 'Walk-in' } } });
    expect(walkIn.status, walkIn.text).toBe(201);
    h.setNow('2026-11-03T19:30:00Z');
    await markNoShow(walkIn.body.appointment.id);
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

  it('a charge the server never got to record is found by its metadata', async () => {
    const id = await noShow();
    // The server asked Stripe, Stripe charged, and the function stopped before writing anything.
    h.stripe.loseNextChargeAnswer = true;
    await charge(id);
    const [intent] = [...h.stripe.intents.values()].filter((pi) => pi.metadata.kind === 'no_show_fee');
    expect((await h.database.pool.query('SELECT count(*)::int AS n FROM payments')).rows[0].n).toBe(0);
    await send(event('payment_intent.succeeded', { id: intent!.id, status: 'succeeded', amount: 1750, metadata: intent!.metadata }));
    expect((await fee(id)).status).toBe('charged');
    const payments = (await h.call('GET', '/api/owner/payments?date=2026-11-03', owner)).body.payments;
    expect(payments).toEqual([expect.objectContaining({ id: intent!.id, kind: 'noShowFee', status: 'succeeded', amountCents: 1750, appointmentId: id })]);
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
