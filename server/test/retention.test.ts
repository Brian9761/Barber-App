import { describe, expect, it } from 'vitest';
import { newManageToken } from '../src/auth.js';
import { anonymizeExpired, bookingNeedsCard, NAME_REMOVED, retentionCutoff, RETENTION_MONTHS } from '../src/retention.js';
import { RESPONSES } from './helpers/contract.js';
import { CRON_SECRET, connectedShop, protectionOn, stripeError, useHarness } from './helpers/harness.js';
import { seedWeek } from './helpers/week.js';

// What the Privacy Policy promises about how long things are kept (src/retention.ts): clients'
// details removed 12 months after the appointment (not while a fee is pending), names on sales and
// card payments' descriptions after 12 months, receipt emails not kept, and saved cards deleted at
// Stripe once they're due and no booking needs them, by the daily job or when the client removes one.

// Monday Nov 2 2026, 9:00 AM PST.
const h = useHarness({ now: '2026-11-02T17:00:00Z' });
const owner = { owner: true } as const;
const FLOW45 = 'flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a';
const TUE10 = '2026-11-03T18:00:00Z';
const cron = () => h.call('GET', '/api/cron/daily', { headers: { authorization: `Bearer ${CRON_SECRET}` } });
const row = async (table: string, id: string) => (await h.database.pool.query(`SELECT * FROM ${table} WHERE id = $1`, [id])).rows[0];

/** A card saved the way the app does it (Visa 4242); returns its token. */
async function saveCard(ip = '192.0.2.70'): Promise<string> {
  await protectionOn(h);
  const token = newManageToken();
  const checkout = await h.call('POST', '/api/cards/checkout', { headers: { 'x-card-token': token }, body: { offeringId: FLOW45 }, ip });
  expect(checkout.status, checkout.text).toBe(201);
  h.stripe.completeSession(checkout.body.sessionId);
  const saved = await h.call('POST', '/api/cards', { headers: { 'x-card-token': token }, body: { sessionId: checkout.body.sessionId }, ip });
  expect(saved.status, saved.text).toBe(201);
  return token;
}

/** A booking with the card saved under `token`, for Flowxbori's 45-minute haircut at `start`. */
async function book(token: string, start = TUE10, customer: Record<string, string> = { name: 'Andre Sample', phone: '4425550170' }) {
  const policy = (await h.call('GET', `/api/no-show-policy?offeringId=${encodeURIComponent(FLOW45)}`)).body.policyText;
  const res = await h.call('POST', '/api/appointments', {
    headers: { 'x-card-token': token },
    body: { offeringId: FLOW45, start, customer, note: 'Low fade, please.', noShowPolicy: policy },
    ip: '203.0.113.71',
  });
  expect(res.status, res.text).toBe(201);
  return { id: res.body.appointment.id as string, manageToken: res.body.manageToken as string };
}

const removeCard = (token: string) => h.call('DELETE', '/api/cards', { headers: { 'x-card-token': token } });
const setStatus = (id: string, status: string) => h.call('PATCH', `/api/owner/appointments/${id}`, { ...owner, body: { status } });
const cardRow = async () => (await h.database.pool.query('SELECT * FROM saved_cards ORDER BY created_at')).rows[0];
const stripeDeletes = () => h.stripe.calls.filter((c) => c.method === 'paymentMethods.detach' || c.method === 'customers.del');

describe('clients’ details are removed 12 months after the appointment', () => {
  it('the cut-off is 12 months before now', () => {
    expect(RETENTION_MONTHS).toBe(12);
    expect(retentionCutoff(new Date('2027-11-03T18:45:00Z'))).toEqual(new Date('2026-11-03T18:45:00Z'));
  });

  it('a minute past 12 months after the end: name, number, email, note and keys removed; the rest stays', async () => {
    const token = await saveCard();
    const booking = await book(token, TUE10, { name: 'Andre Sample', phone: '4425550170', email: 'andre@example.com' });
    h.setNow('2026-11-03T18:30:00Z');
    expect((await setStatus(booking.id, 'completed')).status).toBe(200);
    const before = await row('appointments', booking.id);
    // 12 months after the 10:45 AM end, less a minute: nothing yet.
    h.setNow('2027-11-03T18:44:00Z');
    expect((await cron()).body.anonymized).toMatchObject({ appointments: 0 });
    expect((await row('appointments', booking.id)).customer_name).toBe('Andre Sample');
    // A minute after.
    h.setNow('2027-11-03T18:46:00Z');
    const run = await cron();
    expect(run.status).toBe(200);
    expect(run.body.anonymized).toMatchObject({ appointments: 1 });
    const after = await row('appointments', booking.id);
    expect(after).toMatchObject({
      customer_name: NAME_REMOVED,
      customer_phone: null,
      customer_email: null,
      note: null,
      manage_token_hash: null,
      idempotency_key_hash: null,
      no_show_fee_message: null,
      anonymized_at: new Date('2027-11-03T18:46:00Z'),
    });
    // What was booked, when, the price, what happened and the agreed terms (evidence for a dispute) stay.
    for (const column of ['service_name', 'barber_name', 'price_cents', 'start_at', 'end_at', 'status', 'card_brand', 'card_last4', 'no_show_fee_cents', 'no_show_policy', 'no_show_consent_at', 'created_at']) {
      expect(after[column], column).toEqual(before[column]);
    }
    // The client's key no longer finds it.
    expect((await h.call('GET', `/api/appointments/${booking.id}`, { headers: { 'x-manage-token': booking.manageToken } })).status).toBe(404);
    // The shop's list shows it without the details.
    const day = await h.call('GET', '/api/owner/appointments?date=2026-11-03', owner);
    expect(day.body.appointments[0].customer).toEqual({ name: 'Name removed', phone: null, email: null });
    expect(RESPONSES['owner-appointments'].safeParse(day.body).success).toBe(true);
    // Doing it again changes nothing.
    expect((await cron()).body.anonymized).toEqual({ appointments: 0, sales: 0, payments: 0, receiptEmails: 0 });
  });

  it('waits while a fee for the appointment is pending, then removes them', async () => {
    const token = await saveCard();
    const booking = await book(token);
    h.setNow('2026-11-03T18:50:00Z');
    expect((await setStatus(booking.id, 'noShow')).status).toBe(200);
    h.stripe.nextCharge = 'processing';
    expect((await h.call('POST', `/api/owner/appointments/${booking.id}/no-show-fee`, owner)).body.appointment.noShowFee.status).toBe('pending');
    h.setNow('2027-12-01T19:00:00Z');
    expect((await cron()).body.anonymized.appointments).toBe(0);
    expect((await row('appointments', booking.id)).customer_name).toBe('Andre Sample');
    await h.database.pool.query(`UPDATE appointments SET no_show_fee_status = 'declined' WHERE id = $1`, [booking.id]);
    expect((await cron()).body.anonymized.appointments).toBe(1);
    expect((await row('appointments', booking.id)).customer_name).toBe(NAME_REMOVED);
  });

  it('names on sales and void reasons, and card payments’ descriptions, names on tickets and receipt emails, after 12 months', async () => {
    // Monday 10:20 AM: a walk-in checked out in cash by name, then voided; a card payment with a note.
    h.setNow('2026-11-02T18:20:00Z');
    const sale = await h.call('POST', '/api/owner/sales', {
      ...owner,
      body: { method: 'cash', barberId: 'carlos-rafael', customerName: 'Walk-in Wanda', items: [{ kind: 'service', serviceId: 'haircut' }] },
    });
    expect(sale.status, sale.text).toBe(201);
    await h.call('POST', `/api/owner/sales/${sale.body.sale.id}/void`, { ...owner, body: { reason: 'Rang up Wanda twice' } });
    h.config.stripeSecretKey = 'sk_test_fixture';
    const pay = await h.call('POST', '/api/owner/payments', {
      ...owner,
      body: { amountCents: 4500, description: 'Haircut for Wanda', sale: { barberId: 'carlos-rafael', customerName: 'Walk-in Wanda', items: [{ kind: 'service', serviceId: 'haircut' }] } },
    });
    expect(pay.status, pay.text).toBe(201);
    const paymentId = pay.body.paymentIntentId as string;
    // A receipt email left by older code, as it used to be kept.
    await h.database.pool.query(`UPDATE payments SET receipt_email = 'wanda@example.com' WHERE id = $1`, [paymentId]);
    // The next day the job clears that one (receipt emails aren't kept at all), and nothing else yet.
    h.setNow('2026-11-03T19:00:00Z');
    expect((await cron()).body.anonymized).toEqual({ appointments: 0, sales: 0, payments: 0, receiptEmails: 1 });
    expect(await row('payments', paymentId)).toMatchObject({ receipt_email: null, description: 'Haircut for Wanda' });
    // 12 months later.
    h.setNow('2027-11-02T18:21:00Z');
    expect((await cron()).body.anonymized).toEqual({ appointments: 0, sales: 1, payments: 1, receiptEmails: 0 });
    expect(await row('sales', sale.body.sale.id)).toMatchObject({ customer_name: null, void_reason: null, total_cents: 4500, method: 'cash' });
    expect((await row('sales', sale.body.sale.id)).voided_at).not.toBeNull();
    // The ticket keeps its items (and the appointment it was for, if any), without the name.
    const payment = await row('payments', paymentId);
    expect(payment).toMatchObject({ description: null, receipt_email: null, amount_cents: 4500 });
    expect(payment.sale_draft).toMatchObject({ barberId: 'carlos-rafael', appointmentId: null, customerName: null, totalCents: 4500, items: [{ serviceId: 'haircut' }] });
  });

  it('a card checkout’s ticket still names its appointment, so voiding the other sale a year later gives the visit to the card', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    // Monday 10 AM, a walk-in: paid by card, and checked out in cash by mistake while the card went through.
    const walkIn = await h.call('POST', '/api/owner/appointments', { ...owner, body: { offeringId: FLOW45, start: '2026-11-02T18:00:00Z', customer: { name: 'Ben Walkin' } } });
    expect(walkIn.status, walkIn.text).toBe(201);
    const appointment = walkIn.body.appointment.id as string;
    const haircut = [{ kind: 'service', serviceId: 'haircut' }];
    const card = await h.call('POST', '/api/owner/payments', { ...owner, body: { amountCents: 3500, sale: { appointmentId: appointment, items: haircut } } });
    expect(card.status, card.text).toBe(201);
    const cash = await h.call('POST', '/api/owner/sales', { ...owner, body: { method: 'cash', appointmentId: appointment, items: haircut } });
    expect(cash.status, cash.text).toBe(201);
    h.stripe.succeed(card.body.paymentIntentId);
    const cardSale = (await h.call('POST', `/api/owner/payments/${card.body.paymentIntentId}/complete`, owner)).body.payment.saleId as string;
    expect((await row('sales', cardSale)).appointment_id).toBeNull();
    // A year and a day later the details are gone.
    h.setNow('2027-11-03T19:00:00Z');
    expect((await cron()).body.anonymized).toEqual({ appointments: 1, sales: 2, payments: 1, receiptEmails: 0 });
    // Voiding the cash sale now still gives the visit to the card sale, and the reason typed isn't kept.
    const voided = await h.call('POST', `/api/owner/sales/${cash.body.sale.id}/void`, { ...owner, body: { reason: 'Ben paid by card' } });
    expect(voided.status, voided.text).toBe(200);
    expect(voided.body.message).toBe('The sale was voided, so it no longer counts in your sales. The card payment taken for this appointment is its checkout now.');
    expect(voided.body.sale.voidReason).toBeNull();
    expect(await row('sales', cardSale)).toMatchObject({ appointment_id: appointment, customer_name: null });
    expect(await row('appointments', appointment)).toMatchObject({ sale_id: cardSale, customer_name: NAME_REMOVED });
  });

  it('a fee’s description (the service and the time) stays; the payment row does too', async () => {
    const token = await saveCard();
    const booking = await book(token);
    h.setNow('2026-11-03T18:50:00Z');
    await setStatus(booking.id, 'noShow');
    await h.call('POST', `/api/owner/appointments/${booking.id}/no-show-fee`, owner);
    h.setNow('2027-11-04T19:00:00Z');
    expect((await cron()).body.anonymized).toMatchObject({ appointments: 1, payments: 1 });
    const fee = (await h.database.pool.query(`SELECT description, amount_cents, status FROM payments WHERE kind = 'no_show_fee'`)).rows[0];
    expect(fee).toEqual({ description: 'No-show fee: Haircut with Flowxbori, Tue, Nov 3 at 10:00 AM', amount_cents: 3500, status: 'succeeded' });
  });

  it('in batches, oldest first, carrying on where the budget ran out', async () => {
    // Five walk-ins in November 2026 (no phone needed).
    for (const [i, start] of ['2026-11-03T18:00:00Z', '2026-11-03T19:00:00Z', '2026-11-03T20:00:00Z', '2026-11-03T21:00:00Z', '2026-11-03T22:00:00Z'].entries()) {
      h.setNow(start);
      const res = await h.call('POST', '/api/owner/appointments', { ...owner, body: { offeringId: FLOW45, start, customer: { name: `Walk-in ${i}` } } });
      expect(res.status, res.text).toBe(201);
    }
    const now = new Date('2027-12-01T00:00:00Z');
    // A budget that runs out after the first batch of two.
    let ticks = 0;
    const once = { stopAt: 1, clock: () => (ticks++ === 0 ? 0 : 2), batchSize: 2 };
    expect(await anonymizeExpired(h.deps.db, now, once)).toEqual({ appointments: 2, sales: 0, payments: 0 });
    const names = async () => (await h.database.pool.query('SELECT customer_name FROM appointments ORDER BY end_at')).rows.map((r) => r.customer_name);
    expect(await names()).toEqual([NAME_REMOVED, NAME_REMOVED, 'Walk-in 2', 'Walk-in 3', 'Walk-in 4']);
    // The next run, in batches of two, finishes the rest.
    expect(await anonymizeExpired(h.deps.db, now, { stopAt: Number.MAX_SAFE_INTEGER, batchSize: 2 })).toEqual({ appointments: 3, sales: 0, payments: 0 });
    expect(await names()).toEqual(Array(5).fill(NAME_REMOVED));
  });

  it('the analytics stay exactly the same', async () => {
    await seedWeek(h);
    const week = async () => {
      const res = await h.call('GET', '/api/owner/analytics?from=2026-10-26&to=2026-11-08', owner);
      expect(res.status, res.text).toBe(200);
      const { generatedAt: _generatedAt, ...rest } = res.body;
      return rest;
    };
    // Read at the same moment before and after (the numbers depend on what's past by then).
    h.setNow('2028-01-01T08:00:00Z');
    const before = await week();
    const run = await cron();
    expect(run.body.anonymized.appointments).toBeGreaterThan(10);
    expect(run.body.anonymized.sales).toBeGreaterThan(5);
    expect(await week()).toEqual(before);
  });
});

describe('a booking still needs its card…', () => {
  const base = {
    id: '00000000-0000-4000-8000-000000000001',
    status: 'booked' as const,
    cancelled_by: null,
    start_at: new Date('2026-11-03T18:00:00Z'),
    end_at: new Date('2026-11-03T18:45:00Z'),
    created_at: new Date('2026-11-01T18:00:00Z'),
    saved_card_id: '00000000-0000-4000-8000-0000000000c1',
    no_show_fee_cents: 3500,
    late_cancel_window_minutes: 60,
    customer_cancelled_at: null,
    no_show_fee_status: 'none' as const,
  };
  const at = (iso: string) => new Date(iso);

  it('while it’s upcoming, or could still be charged a fee before the 7-day deadline', () => {
    expect(bookingNeedsCard(base, at('2026-11-02T17:00:00Z')), 'upcoming').toBe(true);
    expect(bookingNeedsCard(base, at('2026-11-05T17:00:00Z')), 'not marked yet').toBe(true);
    expect(bookingNeedsCard({ ...base, status: 'no_show' }, at('2026-11-10T17:59:00Z')), 'a no-show, 7 days less a minute').toBe(true);
    expect(bookingNeedsCard({ ...base, status: 'no_show' }, at('2026-11-10T18:01:00Z')), 'a no-show, past the deadline').toBe(false);
    const late = { ...base, status: 'cancelled' as const, cancelled_by: 'customer' as const, customer_cancelled_at: at('2026-11-03T17:30:00Z') };
    expect(bookingNeedsCard(late, at('2026-11-04T17:00:00Z')), 'a late cancellation').toBe(true);
    expect(bookingNeedsCard({ ...late, customer_cancelled_at: at('2026-11-03T16:00:00Z') }, at('2026-11-04T17:00:00Z')), 'cancelled in time').toBe(false);
  });

  it('while a fee is pending, whenever; never once it’s charged, completed or cancelled by the shop', () => {
    expect(bookingNeedsCard({ ...base, status: 'no_show', no_show_fee_status: 'pending' }, at('2027-01-01T00:00:00Z'))).toBe(true);
    expect(bookingNeedsCard({ ...base, status: 'no_show', no_show_fee_status: 'charged' }, at('2026-11-04T00:00:00Z'))).toBe(false);
    expect(bookingNeedsCard({ ...base, status: 'no_show', no_show_fee_status: 'declined' }, at('2026-11-04T00:00:00Z')), 'tried again').toBe(true);
    expect(bookingNeedsCard({ ...base, status: 'completed' }, at('2026-11-04T00:00:00Z'))).toBe(false);
    expect(bookingNeedsCard({ ...base, status: 'cancelled', cancelled_by: 'shop' }, at('2026-11-02T18:00:00Z'))).toBe(false);
    expect(bookingNeedsCard({ ...base, saved_card_id: null, no_show_fee_cents: null }, at('2026-11-02T17:00:00Z'))).toBe(false);
  });
});

describe('DELETE /api/cards: the client removes their saved card', () => {
  it('no booking needs it: detached and its Customer deleted at Stripe, and it can’t book again', async () => {
    const token = await saveCard();
    const card = await cardRow();
    const res = await removeCard(token);
    expect(res.status, res.text).toBe(200);
    expect(res.body).toEqual({ cardDeletion: { status: 'deleted', message: "Your saved card is deleted. It can't be charged any more." } });
    expect(stripeDeletes().map((c) => [c.method, c.params, c.options])).toEqual([
      ['paymentMethods.detach', { id: card.stripe_payment_method_id }, undefined],
      ['customers.del', { id: card.stripe_customer_id }, undefined],
    ]);
    expect(await cardRow()).toMatchObject({
      removed_at: new Date('2026-11-02T17:00:00Z'),
      checkout_session_id: null,
      stripe_customer_id: null,
      stripe_payment_method_id: null,
      brand: 'visa',
      last4: '4242',
    });
    // It can't book, or be saved again with the same token.
    const policy = (await h.call('GET', `/api/no-show-policy?offeringId=${encodeURIComponent(FLOW45)}`)).body.policyText;
    const booked = await h.call('POST', '/api/appointments', {
      headers: { 'x-card-token': token },
      body: { offeringId: FLOW45, start: TUE10, customer: { name: 'Andre Sample', phone: '4425550170' }, noShowPolicy: policy },
    });
    expect(booked.status).toBe(400);
    expect(booked.body.error).toEqual({ code: 'card_required', message: "We couldn't find your saved card. Add it again." });
    expect((await h.call('POST', '/api/cards', { headers: { 'x-card-token': token }, body: { sessionId: card.checkout_session_id } })).status).toBe(404);
    // Removing it again answers the same, without asking Stripe.
    expect((await removeCard(token)).body.cardDeletion.status).toBe('deleted');
    expect(stripeDeletes()).toHaveLength(2);
    expect(RESPONSES['card-deletion'].safeParse(res.body).success).toBe(true);
  });

  it('a booking still needs it: kept for that booking, deleted by the daily job once it doesn’t', async () => {
    const token = await saveCard();
    const booking = await book(token);
    // Right after booking without Remember me, as the app and website do.
    const res = await removeCard(token);
    expect(res.body).toEqual({ cardDeletion: { status: 'scheduled', message: 'Your card will be deleted as soon as your appointments no longer need it.' } });
    expect(stripeDeletes()).toEqual([]);
    expect(await cardRow()).toMatchObject({ removed_at: null, delete_requested_at: new Date('2026-11-02T17:00:00Z') });
    // It can't book anything else.
    const policy = (await h.call('GET', `/api/no-show-policy?offeringId=${encodeURIComponent(FLOW45)}`)).body.policyText;
    const again = await h.call('POST', '/api/appointments', {
      headers: { 'x-card-token': token },
      body: { offeringId: FLOW45, start: '2026-11-04T18:00:00Z', customer: { name: 'Andre Sample', phone: '4425550170' }, noShowPolicy: policy },
      ip: '203.0.113.72',
    });
    expect(again.body.error).toEqual({ code: 'card_required', message: "We couldn't find your saved card. Add it again." });
    // The client doesn't come: the no-show can still be charged to it within 7 days, so the job keeps it…
    h.setNow('2026-11-03T18:50:00Z');
    await setStatus(booking.id, 'noShow');
    h.setNow('2026-11-04T19:17:00Z');
    expect((await cron()).body.savedCards).toEqual({ deleted: 0, stillNeeded: 1, failed: 0 });
    expect((await h.call('POST', `/api/owner/appointments/${booking.id}/no-show-fee`, owner)).body.appointment.noShowFee.status).toBe('charged');
    // …and once it's charged, nothing needs it any more.
    h.setNow('2026-11-05T19:17:00Z');
    expect((await cron()).body.savedCards).toEqual({ deleted: 1, stillNeeded: 0, failed: 0 });
    expect(stripeDeletes().map((c) => c.method)).toEqual(['paymentMethods.detach', 'customers.del']);
    expect((await cardRow()).removed_at).toEqual(new Date('2026-11-05T19:17:00Z'));
    // The appointment keeps the card's brand and last 4, and its fee.
    const day = await h.call('GET', '/api/owner/appointments?date=2026-11-03', owner);
    expect(day.body.appointments[0]).toMatchObject({ card: { brand: 'visa', last4: '4242' }, noShowFee: { status: 'charged' } });
    expect((await removeCard(token)).body.cardDeletion.status).toBe('deleted');
  });

  it('a no-show that’s never charged keeps it only until 7 days after the start', async () => {
    const token = await saveCard();
    const booking = await book(token);
    await removeCard(token);
    h.setNow('2026-11-03T18:50:00Z');
    await setStatus(booking.id, 'noShow');
    h.setNow('2026-11-10T17:59:00Z');
    expect((await cron()).body.savedCards.stillNeeded).toBe(1);
    h.setNow('2026-11-10T18:01:00Z');
    expect((await cron()).body.savedCards.deleted).toBe(1);
    // Charging it now: too late anyway.
    expect((await h.call('POST', `/api/owner/appointments/${booking.id}/no-show-fee`, owner)).body.error).toEqual({
      code: 'not_chargeable',
      message: "It's more than 7 days after the appointment, so the fee can't be charged.",
    });
  });

  it('a completed visit, a cancellation in time or by the shop don’t need it', async () => {
    const token = await saveCard();
    const done = await book(token);
    const cancelled = await book(token, '2026-11-04T18:00:00Z');
    const shop = await book(token, '2026-11-05T18:00:00Z');
    expect((await removeCard(token)).body.cardDeletion.status).toBe('scheduled');
    h.setNow('2026-11-03T18:30:00Z');
    await setStatus(done.id, 'completed');
    expect((await h.call('POST', `/api/appointments/${cancelled.id}/cancel`, { headers: { 'x-manage-token': cancelled.manageToken } })).status).toBe(200);
    await setStatus(shop.id, 'cancelled');
    expect((await cron()).body.savedCards).toEqual({ deleted: 1, stillNeeded: 0, failed: 0 });
  });

  it('a pending fee keeps it, even after the 7 days, until Stripe answers', async () => {
    const token = await saveCard();
    const booking = await book(token);
    h.setNow('2026-11-03T18:50:00Z');
    await setStatus(booking.id, 'noShow');
    h.stripe.nextCharge = 'processing';
    await h.call('POST', `/api/owner/appointments/${booking.id}/no-show-fee`, owner);
    expect((await removeCard(token)).body.cardDeletion.status).toBe('scheduled');
    h.setNow('2026-11-20T19:17:00Z');
    expect((await cron()).body.savedCards).toEqual({ deleted: 0, stillNeeded: 1, failed: 0 });
  });

  it('Stripe doesn’t answer: marked for the daily job, which deletes it the next day', async () => {
    const token = await saveCard();
    h.stripe.nextError = stripeError('StripeConnectionError', {}, 'socket hang up');
    expect((await removeCard(token)).body.cardDeletion.status).toBe('scheduled');
    expect(h.logs.at(-1)).toMatchObject({ level: 'error', message: 'Stripe detach card failed' });
    expect((await cardRow()).removed_at).toBeNull();
    h.setNow('2026-11-03T19:17:00Z');
    h.stripe.nextError = stripeError('StripeAPIError', { statusCode: 500 }, 'Server error');
    expect((await cron()).body.savedCards).toEqual({ deleted: 0, stillNeeded: 0, failed: 1 });
    h.setNow('2026-11-04T19:17:00Z');
    expect((await cron()).body.savedCards).toEqual({ deleted: 1, stillNeeded: 0, failed: 0 });
  });

  it('a card Stripe already forgot is just removed here', async () => {
    const token = await saveCard();
    const card = await cardRow();
    await h.stripe.customers.del(card.stripe_customer_id);
    expect((await removeCard(token)).body.cardDeletion.status).toBe('deleted');
    expect((await cardRow()).removed_at).not.toBeNull();
  });

  it('with Stripe Connect, deleted on the account it was saved on', async () => {
    const account = await connectedShop(h);
    const token = await saveCard();
    expect((await removeCard(token)).body.cardDeletion.status).toBe('deleted');
    expect(stripeDeletes().map((c) => [c.method, c.options])).toEqual([
      ['paymentMethods.detach', { stripeAccount: account }],
      ['customers.del', { stripeAccount: account }],
    ]);
  });

  it('a card saved with the shop’s own key, before Stripe was connected: removed here, logged, nothing asked of the platform', async () => {
    const token = await saveCard();
    await connectedShop(h);
    expect((await removeCard(token)).body.cardDeletion.status).toBe('deleted');
    expect(stripeDeletes()).toEqual([]);
    expect(h.logs.at(-1)).toMatchObject({ level: 'warn', message: expect.stringContaining("delete it in that account's Dashboard") });
    expect((await cardRow()).removed_at).not.toBeNull();
  });

  it('a fee whose card was deleted says so (when nothing else stops it)', async () => {
    const token = await saveCard();
    const booking = await book(token);
    h.setNow('2026-11-03T18:50:00Z');
    await setStatus(booking.id, 'noShow');
    // Removed here while the no-show could still be charged (say it was on another Stripe account).
    await h.database.pool.query(
      `UPDATE saved_cards SET removed_at = now(), checkout_session_id = NULL, stripe_customer_id = NULL, stripe_payment_method_id = NULL`,
    );
    const res = await h.call('POST', `/api/owner/appointments/${booking.id}/no-show-fee`, owner);
    expect(res.status).toBe(409);
    expect(res.body.error).toEqual({ code: 'not_chargeable', message: "The client's saved card was deleted, so it can't be charged." });
    expect(h.stripe.calls.filter((c) => c.method === 'paymentIntents.create')).toEqual([]);
  });

  it('the token: required, well formed, and a card that was saved', async () => {
    expect((await h.call('DELETE', '/api/cards')).body.error).toEqual({ code: 'invalid_request', message: 'Send the card token as X-Card-Token.' });
    expect((await h.call('DELETE', '/api/cards', { headers: { 'x-card-token': 'short' } })).status).toBe(400);
    const unknown = await removeCard(newManageToken());
    expect(unknown.status).toBe(404);
    expect(unknown.body.error).toEqual({ code: 'not_found', message: "We couldn't find that card." });
  });
});

describe('the daily job deletes saved cards that are due', () => {
  it('expired: after its expiry month, once nothing needs it', async () => {
    await protectionOn(h);
    const token = newManageToken();
    const checkout = await h.call('POST', '/api/cards/checkout', { headers: { 'x-card-token': token }, body: { offeringId: FLOW45 } });
    h.stripe.completeSession(checkout.body.sessionId, { brand: 'visa', last4: '1881', exp_month: 11, exp_year: 2026 });
    expect((await h.call('POST', '/api/cards', { headers: { 'x-card-token': token }, body: { sessionId: checkout.body.sessionId } })).status).toBe(201);
    h.setNow('2026-11-30T19:17:00Z');
    expect((await cron()).body.savedCards.deleted).toBe(0);
    h.setNow('2026-12-01T19:17:00Z');
    expect((await cron()).body.savedCards.deleted).toBe(1);
  });

  it('12 months without being used for a booking (counting from when it was saved, or its last booking)', async () => {
    const token = await saveCard();
    // Used for a booking on Nov 2 2026, then never again.
    const booking = await book(token);
    h.setNow('2026-11-03T18:30:00Z');
    await setStatus(booking.id, 'completed');
    h.setNow('2027-11-02T16:59:00Z');
    expect((await cron()).body.savedCards.deleted).toBe(0);
    h.setNow('2027-11-02T17:01:00Z');
    expect((await cron()).body.savedCards.deleted).toBe(1);
    // A card kept with Remember me and used meanwhile stays.
  });

  it('a card used within 12 months stays', async () => {
    const token = await saveCard();
    h.setNow('2027-05-01T17:00:00Z');
    const later = await book(token, '2027-05-04T17:00:00Z');
    h.setNow('2027-05-04T17:30:00Z');
    await setStatus(later.id, 'completed');
    h.setNow('2027-11-03T19:17:00Z');
    expect((await cron()).body.savedCards).toEqual({ deleted: 0, stillNeeded: 0, failed: 0 });
    expect((await cardRow()).removed_at).toBeNull();
  });
});
