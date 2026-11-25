import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { newManageToken } from '../src/auth.js';
import { CARD_PAGE_EXPIRED_MESSAGE, CARD_SHOP_MESSAGE, CHECKOUT_MINUTES } from '../src/cards.js';
import {
  anonymizeExpired,
  bookingNeedsCard,
  NAME_REMOVED,
  retentionCutoff,
  RETENTION_MONTHS,
  UNFINISHED_CHECKOUT_MARGIN_HOURS,
  unfinishedCheckoutCutoff,
} from '../src/retention.js';
import { RESPONSES } from './helpers/contract.js';
import { CRON_SECRET, connectedShop, FakeStripe, protectionOn, stripeError, useHarness } from './helpers/harness.js';
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

  it('a fee try nobody checked again, still pending a year on, doesn’t keep them', async () => {
    const token = await saveCard();
    const booking = await book(token);
    h.setNow('2026-11-03T18:50:00Z');
    expect((await setStatus(booking.id, 'noShow')).status).toBe(200);
    h.stripe.nextCharge = 'processing';
    expect((await h.call('POST', `/api/owner/appointments/${booking.id}/no-show-fee`, owner)).body.appointment.noShowFee.status).toBe('pending');
    h.setNow('2027-12-01T19:00:00Z');
    expect((await cron()).body.anonymized.appointments).toBe(1);
    expect((await row('appointments', booking.id)).customer_name).toBe(NAME_REMOVED);
    // The try itself is still there, for Check again.
    expect((await row('appointments', booking.id)).no_show_fee_status).toBe('pending');
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

  it('while a fee is pending, for two weeks after the start at most; never once it’s charged, turned down, completed or cancelled by the shop', () => {
    const pending = { ...base, status: 'no_show' as const, no_show_fee_status: 'pending' as const };
    expect(bookingNeedsCard(pending, at('2026-11-10T18:01:00Z')), 'past the 7 days, still waiting for Stripe').toBe(true);
    expect(bookingNeedsCard(pending, at('2026-11-17T18:00:00Z')), '14 days after the start').toBe(true);
    expect(bookingNeedsCard(pending, at('2026-11-17T18:01:00Z')), 'nobody checked it again').toBe(false);
    expect(bookingNeedsCard(pending, at('2027-01-01T00:00:00Z'))).toBe(false);
    expect(bookingNeedsCard({ ...base, status: 'no_show', no_show_fee_status: 'charged' }, at('2026-11-04T00:00:00Z'))).toBe(false);
    expect(bookingNeedsCard({ ...base, status: 'no_show', no_show_fee_status: 'declined' }, at('2026-11-04T00:00:00Z')), 'not charged again').toBe(false);
    expect(bookingNeedsCard({ ...base, status: 'no_show', no_show_fee_status: 'needs_action' }, at('2026-11-04T00:00:00Z'))).toBe(false);
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
    expect((await cron()).body.savedCards).toEqual({ deleted: 0, stillNeeded: 1, unreachable: 0, failed: 0 });
    expect((await h.call('POST', `/api/owner/appointments/${booking.id}/no-show-fee`, owner)).body.appointment.noShowFee.status).toBe('charged');
    // …and once it's charged, nothing needs it any more.
    h.setNow('2026-11-05T19:17:00Z');
    expect((await cron()).body.savedCards).toEqual({ deleted: 1, stillNeeded: 0, unreachable: 0, failed: 0 });
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
    expect((await cron()).body.savedCards).toEqual({ deleted: 1, stillNeeded: 0, unreachable: 0, failed: 0 });
  });

  it('a pending fee keeps it past the 7 days while Stripe may still answer, but not for good', async () => {
    const token = await saveCard();
    const booking = await book(token);
    h.setNow('2026-11-03T18:50:00Z');
    await setStatus(booking.id, 'noShow');
    h.stripe.nextCharge = 'processing';
    await h.call('POST', `/api/owner/appointments/${booking.id}/no-show-fee`, owner);
    expect((await removeCard(token)).body.cardDeletion.status).toBe('scheduled');
    h.setNow('2026-11-12T19:17:00Z');
    expect((await cron()).body.savedCards).toEqual({ deleted: 0, stillNeeded: 1, unreachable: 0, failed: 0 });
    // Two weeks after the appointment, nobody has checked it again: the card goes.
    h.setNow('2026-11-18T19:17:00Z');
    expect((await cron()).body.savedCards).toEqual({ deleted: 1, stillNeeded: 0, unreachable: 0, failed: 0 });
  });

  it('a fee the bank turned down doesn’t keep it: the card isn’t charged again', async () => {
    const token = await saveCard();
    const booking = await book(token);
    h.setNow('2026-11-03T18:50:00Z');
    await setStatus(booking.id, 'noShow');
    h.stripe.nextCharge = 'insufficient_funds';
    expect((await h.call('POST', `/api/owner/appointments/${booking.id}/no-show-fee`, owner)).body.appointment.noShowFee.status).toBe('declined');
    expect((await removeCard(token)).body.cardDeletion.status).toBe('deleted');
  });

  it('Stripe doesn’t answer: marked for the daily job, which deletes it the next day', async () => {
    const token = await saveCard();
    h.stripe.nextError = stripeError('StripeConnectionError', {}, 'socket hang up');
    expect((await removeCard(token)).body.cardDeletion.status).toBe('scheduled');
    expect(h.logs.at(-1)).toMatchObject({ level: 'error', message: 'Stripe detach card failed' });
    expect((await cardRow()).removed_at).toBeNull();
    h.setNow('2026-11-03T19:17:00Z');
    h.stripe.nextError = stripeError('StripeAPIError', { statusCode: 500 }, 'Server error');
    expect((await cron()).body.savedCards).toEqual({ deleted: 0, stillNeeded: 0, unreachable: 0, failed: 1 });
    h.setNow('2026-11-04T19:17:00Z');
    expect((await cron()).body.savedCards).toEqual({ deleted: 1, stillNeeded: 0, unreachable: 0, failed: 0 });
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
    // Never called deleted: it's still in the shop's own Stripe account, for the shop to delete there.
    expect((await removeCard(token)).body.cardDeletion).toEqual({ status: 'shop', message: CARD_SHOP_MESSAGE });
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

describe('a booking made without “Remember me” (keepCard: false) is the only one its card is for', () => {
  /** Books Flowxbori's haircut with the card saved under `token`, saying whether to keep the card. */
  async function bookWith(token: string, keepCard: unknown, options: { start?: string; manageToken?: string; phone?: string } = {}) {
    const policy = (await h.call('GET', `/api/no-show-policy?offeringId=${encodeURIComponent(FLOW45)}`)).body.policyText;
    return h.call('POST', '/api/appointments', {
      headers: { 'x-card-token': token, ...(options.manageToken ? { 'x-manage-token': options.manageToken } : {}) },
      body: {
        offeringId: FLOW45,
        start: options.start ?? TUE10,
        customer: { name: 'Andre Sample', phone: options.phone ?? '4425550170' },
        ...(typeof policy === 'string' ? { noShowPolicy: policy } : {}),
        ...(keepCard === undefined ? {} : { keepCard }),
      },
      ip: '203.0.113.73',
    });
  }

  it('marks the card for deletion in the booking itself, so a connection lost right after can’t leave it saved', async () => {
    const token = await saveCard();
    const manageToken = newManageToken();
    const booked = await bookWith(token, false, { manageToken });
    expect(booked.status, booked.text).toBe(201);
    // No DELETE /api/cards was needed: the card is kept only while this booking needs it.
    expect(await cardRow()).toMatchObject({ removed_at: null, delete_requested_at: new Date('2026-11-02T17:00:00Z') });
    expect(stripeDeletes()).toEqual([]);
    // The booking keeps its card and its terms, as any booking with a card on file.
    expect(booked.body.appointment).toMatchObject({ card: { brand: 'visa', last4: '4242' }, noShowFee: { status: 'none' } });
    // The answer was lost: the retry with the same manage token is the same booking.
    const retry = await bookWith(token, false, { manageToken });
    expect(retry.status).toBe(200);
    expect(retry.body).toEqual(booked.body);
    // It books nothing else.
    const again = await bookWith(token, false, { start: '2026-11-04T18:00:00Z' });
    expect(again.body.error).toEqual({ code: 'card_required', message: "We couldn't find your saved card. Add it again." });
    // It can still be charged for this booking within the 7 days: the client didn't come…
    h.setNow('2026-11-03T18:50:00Z');
    expect((await setStatus(booked.body.appointment.id, 'noShow')).status).toBe(200);
    h.setNow('2026-11-04T19:17:00Z');
    expect((await cron()).body.savedCards).toEqual({ deleted: 0, stillNeeded: 1, unreachable: 0, failed: 0 });
    expect((await h.call('POST', `/api/owner/appointments/${booked.body.appointment.id}/no-show-fee`, owner)).body.appointment.noShowFee.status).toBe('charged');
    // …and then nothing needs it: the daily job deletes it at Stripe.
    h.setNow('2026-11-05T19:17:00Z');
    expect((await cron()).body.savedCards).toEqual({ deleted: 1, stillNeeded: 0, unreachable: 0, failed: 0 });
    expect(stripeDeletes().map((c) => c.method)).toEqual(['paymentMethods.detach', 'customers.del']);
  });

  it('with “Remember me” (keepCard true, or left out as before), the card stays for later bookings', async () => {
    const token = await saveCard();
    expect((await bookWith(token, true)).status).toBe(201);
    expect((await bookWith(token, undefined, { start: '2026-11-04T18:00:00Z' })).status).toBe(201);
    expect((await cardRow()).delete_requested_at).toBeNull();
    expect((await bookWith(token, false, { start: '2026-11-05T18:00:00Z' })).status).toBe(201);
    expect((await cardRow()).delete_requested_at).toEqual(new Date('2026-11-02T17:00:00Z'));
  });

  it('a booking that doesn’t go through leaves the card as it was', async () => {
    const taken = await saveCard();
    expect((await bookWith(taken, undefined)).status).toBe(201);
    const token = await saveCard('192.0.2.71');
    const refused = await bookWith(token, false, { phone: '4425550171' });
    expect(refused.status).toBe(409);
    expect(refused.body.error.code).toBe('slot_taken');
    const rows = (await h.database.pool.query('SELECT delete_requested_at FROM saved_cards ORDER BY created_at')).rows;
    expect(rows.map((r) => r.delete_requested_at)).toEqual([null, null]);
  });

  it('keepCard is true or false', async () => {
    const token = await saveCard();
    const res = await bookWith(token, 'no');
    expect(res.status).toBe(400);
    expect(res.body.error).toEqual({ code: 'invalid_request', message: 'keepCard must be true or false.' });
  });

  it('a booking that needs no card ignores it, as it ignores the card', async () => {
    const token = await saveCard();
    await h.call('PATCH', '/api/owner/no-show-settings', { ...owner, body: { enabled: false } });
    const res = await bookWith(token, false);
    expect(res.status, res.text).toBe(201);
    expect(res.body.appointment.card).toBeNull();
    expect((await cardRow()).delete_requested_at).toBeNull();
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
    expect((await cron()).body.savedCards).toEqual({ deleted: 0, stillNeeded: 0, unreachable: 0, failed: 0 });
    expect((await cardRow()).removed_at).toBeNull();
  });
});

/** A card page made the way the app does (POST /api/cards/checkout); `finished`: the client added a card on Stripe's page. */
async function cardPage(finished: boolean, ip = '192.0.2.80'): Promise<{ token: string; sessionId: string }> {
  const token = newManageToken();
  const res = await h.call('POST', '/api/cards/checkout', { headers: { 'x-card-token': token }, body: { offeringId: FLOW45 }, ip });
  expect(res.status, res.text).toBe(201);
  if (finished) h.stripe.completeSession(res.body.sessionId);
  return { token, sessionId: res.body.sessionId };
}
const page = async (id: string) => (await h.database.pool.query('SELECT * FROM card_checkouts WHERE checkout_session_id = $1', [id])).rows[0];
const pageCalls = () => h.stripe.calls.filter((c) => ['checkout.sessions.retrieve', 'paymentMethods.detach', 'customers.del', 'customers.retrieve'].includes(c.method));
const saveIt = (p: { token: string; sessionId: string }) =>
  h.call('POST', '/api/cards', { headers: { 'x-card-token': p.token }, body: { sessionId: p.sessionId }, ip: '192.0.2.81' });
const listed = async () => (await h.call('GET', '/api/owner/stripe', owner)).body.cardsToDelete;
/** Each key its own Stripe account, as in real life (the shared fake stands for the shop's own); returns the other one's fake. */
function anotherAccountsKey(): { other: FakeStripe; shopsKey: string } {
  const shopsKey = h.config.stripeSecretKey!;
  const other = new FakeStripe(() => h.now);
  h.deps.stripe = (key: string) => (key === shopsKey ? h.stripe : other);
  // Of the same mode: nothing in the key says it's another account's.
  h.config.stripeSecretKey = 'sk_test_AnotherStripeAccount';
  return { other, shopsKey };
}

describe('card pages whose card was never saved here are deleted at Stripe within 2 days', () => {
  const pagesCron = () => h.call('GET', '/api/cron/card-pages', { headers: { authorization: `Bearer ${CRON_SECRET}` } });

  it('within 2 days, even when a run misses it: the page’s hour, 21 hours more for the apps’ and the website’s tries, and two runs a day, each anywhere within its hour', () => {
    expect(CHECKOUT_MINUTES).toBe(60);
    expect(UNFINISHED_CHECKOUT_MARGIN_HOURS).toBe(21);
    expect(unfinishedCheckoutCutoff(new Date('2026-11-03T19:17:00Z'))).toEqual(new Date('2026-11-02T21:17:00Z'));
    // Taken up twice a day: by the daily job, and by the card pages' own run 12 hours later (each
    // once a day: Vercel's Hobby plan fails a deployment whose cron runs more often, and fires each
    // one anywhere within its scheduled hour, "17 11 * * *" from 11:00 to 11:59 UTC).
    const { crons } = JSON.parse(readFileSync(new URL('../vercel.json', import.meta.url), 'utf8')) as { crons: { path: string; schedule: string }[] };
    expect(crons).toEqual([
      { path: '/api/cron/daily', schedule: '17 11 * * *' },
      { path: '/api/cron/card-pages', schedule: '17 23 * * *' },
    ]);
    // The latest a page is deleted: it's due a moment after one run came at the start of its hour, so
    // by the next, which may come at the end of its hour, 12 hours 59 minutes later (within 35 hours of
    // the page being made); and when that run misses it (it fails, runs out of time, or Stripe doesn't
    // answer), by the one after it, 24 hours 59 minutes later (within 47 hours).
    expect(CHECKOUT_MINUTES / 60 + UNFINISHED_CHECKOUT_MARGIN_HOURS + 12 + 59 / 60).toBeLessThan(36);
    expect(CHECKOUT_MINUTES / 60 + UNFINISHED_CHECKOUT_MARGIN_HOURS + 24 + 59 / 60).toBeLessThan(48);
  });

  it('a finished page nobody saved: its card detached and its Customer deleted 22 hours after it was made, not a minute before', async () => {
    await protectionOn(h);
    const p = await cardPage(true);
    const session = h.stripe.sessions.get(p.sessionId)!;
    const pm = (session.setup_intent as unknown as { payment_method: { id: string } }).payment_method.id;
    h.setNow('2026-11-03T14:59:00Z');
    expect((await cron()).body.unfinishedCardPages).toEqual({ deleted: 0, unreachable: 0, failed: 0 });
    expect(pageCalls()).toEqual([]);
    expect(await page(p.sessionId)).toMatchObject({ abandoned_at: null, deleted_at: null });
    h.setNow('2026-11-03T15:01:00Z');
    expect((await cron()).body.unfinishedCardPages).toEqual({ deleted: 1, unreachable: 0, failed: 0 });
    expect(pageCalls().map((c) => [c.method, c.params, c.options])).toEqual([
      ['checkout.sessions.retrieve', { id: p.sessionId, expand: ['setup_intent'] }, undefined],
      ['paymentMethods.detach', { id: pm }, undefined],
      ['customers.del', { id: 'cus_TestFixture000001' }, undefined],
    ]);
    expect(h.stripe.deletedCustomers).toEqual(new Set(['cus_TestFixture000001']));
    // Marked, without the Customer's id, so nothing is asked again.
    expect(await page(p.sessionId)).toMatchObject({
      stripe_customer_id: null,
      abandoned_at: new Date('2026-11-03T15:01:00Z'),
      deleted_at: new Date('2026-11-03T15:01:00Z'),
      stripe_unreachable_at: null,
      stripe_unreachable_setup: null,
    });
    h.setNow('2026-11-04T19:17:00Z');
    expect((await cron()).body.unfinishedCardPages).toEqual({ deleted: 0, unreachable: 0, failed: 0 });
    expect(pageCalls()).toHaveLength(3);
    // A retry from the app that comes this late can't save the card that was deleted.
    const late = await saveIt(p);
    expect(late.status).toBe(404);
    expect(late.body.error).toEqual({ code: 'not_found', message: CARD_PAGE_EXPIRED_MESSAGE });
    expect((await h.database.pool.query('SELECT count(*)::int AS n FROM saved_cards')).rows[0].n).toBe(0);
  });

  it('the card pages’ own run, 12 hours after the daily job, deletes them the same way', async () => {
    await protectionOn(h);
    const p = await cardPage(true);
    h.setNow('2026-11-03T14:59:00Z');
    expect((await pagesCron()).body).toEqual({ ok: true, unfinishedCardPages: { deleted: 0, unreachable: 0, failed: 0 } });
    expect(pageCalls()).toEqual([]);
    h.setNow('2026-11-03T23:17:00Z');
    expect((await pagesCron()).body).toEqual({ ok: true, unfinishedCardPages: { deleted: 1, unreachable: 0, failed: 0 } });
    expect(pageCalls().map((c) => c.method)).toEqual(['checkout.sessions.retrieve', 'paymentMethods.detach', 'customers.del']);
    expect(h.stripe.deletedCustomers).toEqual(new Set(['cus_TestFixture000001']));
    expect(await page(p.sessionId)).toMatchObject({ deleted_at: new Date('2026-11-03T23:17:00Z'), stripe_customer_id: null });
    expect((await saveIt(p)).body.error).toEqual({ code: 'not_found', message: CARD_PAGE_EXPIRED_MESSAGE });
    // The daily job the next morning has nothing left to do with it: nothing more is asked of Stripe.
    const asked = pageCalls().length;
    h.setNow('2026-11-04T11:17:00Z');
    expect((await cron()).body.unfinishedCardPages).toEqual({ deleted: 0, unreachable: 0, failed: 0 });
    expect(pageCalls()).toHaveLength(asked);
  });

  it('a page that closed with no card on it: its empty Customer is deleted', async () => {
    await protectionOn(h);
    const p = await cardPage(false);
    h.setNow('2026-11-03T19:17:00Z');
    expect((await cron()).body.unfinishedCardPages).toEqual({ deleted: 1, unreachable: 0, failed: 0 });
    expect(pageCalls().map((c) => c.method)).toEqual(['checkout.sessions.retrieve', 'customers.del']);
    expect(await page(p.sessionId)).toMatchObject({ deleted_at: new Date('2026-11-03T19:17:00Z'), stripe_customer_id: null });
  });

  it('a page Stripe has never heard of (the key is another Stripe account’s now): listed for the shop with its Customer, never taken for deleted; deleted once the shop’s key is back', async () => {
    await protectionOn(h);
    const p = await cardPage(true);
    const { other, shopsKey } = anotherAccountsKey();
    h.setNow('2026-11-03T19:17:00Z');
    const run = await cron();
    expect(run.body.unfinishedCardPages).toEqual({ deleted: 0, unreachable: 1, failed: 0 });
    // Stripe keeps every Checkout Session: one it doesn't have is another account's. Nothing more is asked.
    expect(other.calls.map((c) => c.method)).toEqual(['checkout.sessions.retrieve']);
    expect(pageCalls()).toEqual([]);
    expect(h.stripe.deletedCustomers.size).toBe(0);
    expect(h.logs.at(-1)).toEqual({
      level: 'warn',
      message: "A card page that wasn't finished is on a Stripe account this server can't use any more: delete its customer in that account's Dashboard",
      details: { customerId: 'cus_TestFixture000001', stripeAccount: null, livemode: false },
    });
    expect(await page(p.sessionId)).toMatchObject({
      stripe_customer_id: 'cus_TestFixture000001',
      stripe_unreachable_at: new Date('2026-11-03T19:17:00Z'),
      stripe_unreachable_setup: expect.stringMatching(/^direct:[0-9a-f]{16}$/),
      deleted_at: null,
    });
    expect(await listed()).toEqual([
      { id: p.sessionId, kind: 'cardPage', stripeAccountId: null, livemode: false, customerId: 'cus_TestFixture000001', card: null },
    ]);
    // Not asked about again while the server reaches Stripe the same way.
    h.setNow('2026-11-04T19:17:00Z');
    const quiet = await cron();
    expect(quiet.body.unfinishedCardPages).toEqual({ deleted: 0, unreachable: 0, failed: 0 });
    expect(quiet.body.cardsToDelete).toEqual({ deleted: 0, unreachable: 0, failed: 0 });
    expect(other.calls).toHaveLength(1);
    // The shop's own key is back: the next run deletes the card and its Customer, and it's off the list.
    h.config.stripeSecretKey = shopsKey;
    h.setNow('2026-11-05T19:17:00Z');
    expect((await cron()).body.cardsToDelete).toEqual({ deleted: 1, unreachable: 0, failed: 0 });
    expect(pageCalls().map((c) => c.method)).toEqual(['checkout.sessions.retrieve', 'paymentMethods.detach', 'customers.del']);
    expect(h.stripe.deletedCustomers).toEqual(new Set(['cus_TestFixture000001']));
    expect(await page(p.sessionId)).toMatchObject({
      stripe_customer_id: null,
      stripe_unreachable_at: null,
      stripe_unreachable_setup: null,
      deleted_at: new Date('2026-11-05T19:17:00Z'),
    });
    expect(await listed()).toEqual([]);
    expect((await saveIt(p)).body.error).toEqual({ code: 'not_found', message: CARD_PAGE_EXPIRED_MESSAGE });
  });

  it('a page whose card was saved isn’t kept: the saved card is deleted from saved_cards, when it’s due', async () => {
    const token = await saveCard();
    const sessionId = (await cardRow()).checkout_session_id as string;
    const saving = pageCalls().length;
    expect(await page(sessionId)).toBeUndefined();
    h.setNow('2026-11-04T19:17:00Z');
    expect((await cron()).body.unfinishedCardPages).toEqual({ deleted: 0, unreachable: 0, failed: 0 });
    expect(pageCalls().slice(saving)).toEqual([]);
    expect((await cardRow()).removed_at).toBeNull();
    // Still the client's to book with.
    expect((await book(token, '2026-11-05T18:00:00Z')).id).toBeTruthy();
  });

  it('a card saved by older code (a rollback, say) whose page is still here: the page goes, and nothing is deleted at Stripe', async () => {
    await saveCard();
    const card = await cardRow();
    // As code from before migrations/011 leaves it: the page's row stays when its card is saved (here,
    // one the job had already taken up while Stripe didn't answer, too).
    await h.database.pool.query('INSERT INTO card_checkouts (checkout_session_id, stripe_customer_id, livemode, created_at, abandoned_at) VALUES ($1, $2, false, $3, $4)', [
      card.checkout_session_id,
      card.stripe_customer_id,
      new Date('2026-11-02T17:00:00Z'),
      new Date('2026-11-03T19:17:00Z'),
    ]);
    const saving = pageCalls().length;
    h.setNow('2026-11-04T19:17:00Z');
    expect((await cron()).body.unfinishedCardPages).toEqual({ deleted: 0, unreachable: 0, failed: 0 });
    expect(pageCalls().slice(saving)).toEqual([]);
    expect(await page(card.checkout_session_id)).toBeUndefined();
    expect(await cardRow()).toMatchObject({ removed_at: null, stripe_customer_id: card.stripe_customer_id });
  });

  it('Stripe doesn’t answer: tried again the next day, and the card can’t be saved meanwhile', async () => {
    await protectionOn(h);
    const p = await cardPage(true);
    h.setNow('2026-11-03T19:17:00Z');
    h.stripe.nextError = stripeError('StripeConnectionError', {}, 'socket hang up');
    expect((await cron()).body.unfinishedCardPages).toEqual({ deleted: 0, unreachable: 0, failed: 1 });
    expect(h.logs.at(-1)).toMatchObject({ level: 'error', message: 'Stripe retrieve card checkout failed', details: { message: 'socket hang up' } });
    expect(await page(p.sessionId)).toMatchObject({ abandoned_at: new Date('2026-11-03T19:17:00Z'), deleted_at: null });
    expect((await saveIt(p)).body.error).toEqual({ code: 'not_found', message: CARD_PAGE_EXPIRED_MESSAGE });
    // The Customer can't be deleted either, the next day: tried again the day after.
    h.setNow('2026-11-04T19:17:00Z');
    const realDel = h.stripe.customers.del;
    h.stripe.customers.del = async () => {
      h.stripe.customers.del = realDel;
      throw stripeError('StripeAPIError', { statusCode: 500 }, 'Server error');
    };
    expect((await cron()).body.unfinishedCardPages).toEqual({ deleted: 0, unreachable: 0, failed: 1 });
    h.setNow('2026-11-05T19:17:00Z');
    expect((await cron()).body.unfinishedCardPages).toEqual({ deleted: 1, unreachable: 0, failed: 0 });
    expect(await page(p.sessionId)).toMatchObject({ abandoned_at: new Date('2026-11-03T19:17:00Z'), deleted_at: new Date('2026-11-05T19:17:00Z') });
    expect(h.stripe.deletedCustomers.size).toBe(1);
  });

  it('with Stripe Connect, deleted on the account the page was made on', async () => {
    const account = await connectedShop(h);
    await protectionOn(h, h.config.stripeSecretKey);
    await cardPage(true);
    h.setNow('2026-11-03T19:17:00Z');
    expect((await cron()).body.unfinishedCardPages).toEqual({ deleted: 1, unreachable: 0, failed: 0 });
    expect(pageCalls().map((c) => [c.method, c.options])).toEqual([
      ['checkout.sessions.retrieve', { stripeAccount: account }],
      ['paymentMethods.detach', { stripeAccount: account }],
      ['customers.del', { stripeAccount: account }],
    ]);
  });

  it('with Stripe Connect, on an account the shop took the platform’s access away from: listed with that account', async () => {
    const account = await connectedShop(h);
    await protectionOn(h, h.config.stripeSecretKey);
    const p = await cardPage(true);
    const customerId = (await page(p.sessionId)).stripe_customer_id as string;
    h.setNow('2026-11-03T19:17:00Z');
    h.stripe.nextError = stripeError('StripePermissionError', { statusCode: 403 }, `The provided key does not have access to account '${account}' (or that account does not exist).`);
    expect((await cron()).body.unfinishedCardPages).toEqual({ deleted: 0, unreachable: 1, failed: 0 });
    expect(pageCalls().map((c) => [c.method, c.options])).toEqual([['checkout.sessions.retrieve', { stripeAccount: account }]]);
    expect(h.stripe.deletedCustomers.size).toBe(0);
    expect(h.logs.at(-1)).toMatchObject({ level: 'warn', details: { customerId, stripeAccount: account, livemode: false } });
    expect(await page(p.sessionId)).toMatchObject({
      stripe_account_id: account,
      stripe_customer_id: customerId,
      stripe_unreachable_at: new Date('2026-11-03T19:17:00Z'),
      stripe_unreachable_setup: expect.stringMatching(/^connect:[0-9a-f]{16}$/),
      deleted_at: null,
    });
    expect(await listed()).toEqual([{ id: p.sessionId, kind: 'cardPage', stripeAccountId: account, livemode: false, customerId, card: null }]);
  });

  it('on a Stripe account this server can’t use any more: nothing asked of Stripe, listed for the shop, which says when it’s deleted', async () => {
    await protectionOn(h);
    const p = await cardPage(true);
    // The shop connects its own Stripe account the next morning.
    h.setNow('2026-11-03T16:00:00Z');
    await connectedShop(h);
    const calls = h.stripe.calls.length;
    h.setNow('2026-11-03T19:17:00Z');
    expect((await cron()).body.unfinishedCardPages).toEqual({ deleted: 0, unreachable: 1, failed: 0 });
    expect(h.stripe.calls.slice(calls).filter((c) => c.method !== 'accounts.retrieve')).toEqual([]);
    expect(h.logs.at(-1)).toEqual({
      level: 'warn',
      message: "A card page that wasn't finished is on a Stripe account this server can't use any more: delete its customer in that account's Dashboard",
      details: { customerId: 'cus_TestFixture000001', stripeAccount: null, livemode: false },
    });
    expect(await page(p.sessionId)).toMatchObject({
      stripe_customer_id: 'cus_TestFixture000001',
      stripe_unreachable_at: new Date('2026-11-03T19:17:00Z'),
      stripe_unreachable_setup: expect.stringMatching(/^connect:[0-9a-f]{16}$/),
      deleted_at: null,
    });
    const settings = await h.call('GET', '/api/owner/stripe', owner);
    expect(settings.body.cardsToDelete).toEqual([
      { id: p.sessionId, kind: 'cardPage', stripeAccountId: null, livemode: false, customerId: 'cus_TestFixture000001', card: null },
    ]);
    // It isn't asked about again while it waits for the shop.
    h.setNow('2026-11-04T19:17:00Z');
    const again = await cron();
    expect(again.body.unfinishedCardPages).toEqual({ deleted: 0, unreachable: 0, failed: 0 });
    expect(again.body.cardsToDelete).toEqual({ deleted: 0, unreachable: 0, failed: 0 });
    // The shop deleted it in its old Stripe account.
    const done = await h.call('POST', `/api/owner/stripe/cards-to-delete/${p.sessionId}/deleted`, owner);
    expect(done.status, done.text).toBe(200);
    expect(done.body).toMatchObject({ mode: 'connect', status: 'active', cardsToDelete: [] });
    expect(await page(p.sessionId)).toMatchObject({
      stripe_customer_id: null,
      stripe_unreachable_at: null,
      stripe_unreachable_setup: null,
      deleted_at: new Date('2026-11-04T19:17:00Z'),
    });
    // Again (a lost answer): the same, nothing changes.
    expect((await h.call('POST', `/api/owner/stripe/cards-to-delete/${p.sessionId}/deleted`, owner)).body.cardsToDelete).toEqual([]);
    expect(await page(p.sessionId)).toMatchObject({ deleted_at: new Date('2026-11-04T19:17:00Z') });
  });
});

describe('a card on a Stripe account this server can’t use any more is the shop’s to delete there', () => {
  const policyFor = async () => (await h.call('GET', `/api/no-show-policy?offeringId=${encodeURIComponent(FLOW45)}`)).body.policyText;

  it('removed here (it can’t book or be charged), its Stripe ids kept and its customer in the log, until the shop says it deleted it', async () => {
    const token = await saveCard();
    const saved = await cardRow();
    await connectedShop(h);
    const removal = await removeCard(token);
    // Never told it's deleted: it's still in that Stripe account, and the shop deletes it there.
    expect(removal.body).toEqual({ cardDeletion: { status: 'shop', message: CARD_SHOP_MESSAGE } });
    expect(CARD_SHOP_MESSAGE).toBe("Your saved card can't be used or charged any more. The shop will delete it in its Stripe account.");
    expect(RESPONSES['card-deletion-shop'].safeParse(removal.body).success).toBe(true);
    expect(stripeDeletes()).toEqual([]);
    expect(h.logs.at(-1)).toEqual({
      level: 'warn',
      message: "A saved card is on a Stripe account this server can't use any more: removed here, delete it in that account's Dashboard",
      details: { cardId: saved.id, customerId: saved.stripe_customer_id, stripeAccount: null, livemode: false },
    });
    expect(await cardRow()).toMatchObject({
      removed_at: new Date('2026-11-02T17:00:00Z'),
      stripe_unreachable_at: new Date('2026-11-02T17:00:00Z'),
      stripe_unreachable_setup: expect.stringMatching(/^connect:[0-9a-f]{16}$/),
      checkout_session_id: saved.checkout_session_id,
      stripe_customer_id: saved.stripe_customer_id,
      stripe_payment_method_id: saved.stripe_payment_method_id,
    });
    // It can't book.
    const booked = await h.call('POST', '/api/appointments', {
      headers: { 'x-card-token': token },
      body: { offeringId: FLOW45, start: TUE10, customer: { name: 'Andre Sample', phone: '4425550170' }, noShowPolicy: await policyFor() },
    });
    expect(booked.body.error.code).toBe('card_required');
    // Settings lists it: where, what card, and the customer to search for.
    const settings = await h.call('GET', '/api/owner/stripe', owner);
    expect(settings.body.cardsToDelete).toEqual([
      {
        id: saved.id,
        kind: 'savedCard',
        stripeAccountId: null,
        livemode: false,
        customerId: saved.stripe_customer_id,
        card: { brand: 'visa', last4: '4242', expMonth: 12, expYear: 2030 },
      },
    ]);
    expect(RESPONSES['stripe-connection-cards-to-delete'].safeParse(settings.body).success).toBe(true);
    // Removing it again: still nothing asked of Stripe, still the shop's to delete, still on the list.
    expect((await removeCard(token)).body.cardDeletion.status).toBe('shop');
    expect(stripeDeletes()).toEqual([]);
    expect((await h.call('GET', '/api/owner/stripe', owner)).body.cardsToDelete).toHaveLength(1);
    // "Deleted in Stripe": its ids are forgotten, and it's off the list (a computer can say so too).
    const computer = await h.call('POST', '/api/owner/computer-codes', owner);
    const signedIn = await h.call('POST', '/api/computer-sessions', { body: { code: computer.body.code, name: 'Chrome on Mac' } });
    const done = await h.call('POST', `/api/owner/stripe/cards-to-delete/${saved.id}/deleted`, { headers: { authorization: `Bearer ${signedIn.body.token}` } });
    expect(done.status, done.text).toBe(200);
    expect(done.body.cardsToDelete).toEqual([]);
    expect(RESPONSES['stripe-connection-card-deleted'].safeParse(done.body).success).toBe(true);
    expect(await cardRow()).toMatchObject({
      removed_at: new Date('2026-11-02T17:00:00Z'),
      stripe_unreachable_at: null,
      stripe_unreachable_setup: null,
      checkout_session_id: null,
      stripe_customer_id: null,
      stripe_payment_method_id: null,
      brand: 'visa',
      last4: '4242',
    });
    // Now it is deleted, and the client is told so.
    expect((await removeCard(token)).body.cardDeletion).toEqual({ status: 'deleted', message: "Your saved card is deleted. It can't be charged any more." });
    // Again: the same answer. An id that's nothing here, or isn't an id: a 404.
    expect((await h.call('POST', `/api/owner/stripe/cards-to-delete/${saved.id}/deleted`, owner)).status).toBe(200);
    for (const id of ['00000000-0000-4000-8000-0000000000ff', 'cs_test_Unknown', 'nope', 'pm_123']) {
      const res = await h.call('POST', `/api/owner/stripe/cards-to-delete/${id}/deleted`, owner);
      expect(res.status, id).toBe(404);
      expect(res.body.error).toEqual({ code: 'not_found', message: "We couldn't find that card." });
    }
  });

  it('the daily job, likewise: an expired card saved with the shop’s own key, once Stripe is connected', async () => {
    await protectionOn(h);
    const token = newManageToken();
    const checkout = await h.call('POST', '/api/cards/checkout', { headers: { 'x-card-token': token }, body: { offeringId: FLOW45 } });
    h.stripe.completeSession(checkout.body.sessionId, { brand: 'amex', last4: '0005', exp_month: 11, exp_year: 2026 });
    expect((await h.call('POST', '/api/cards', { headers: { 'x-card-token': token }, body: { sessionId: checkout.body.sessionId } })).status).toBe(201);
    await connectedShop(h);
    h.setNow('2026-12-01T19:17:00Z');
    expect((await cron()).body.savedCards).toEqual({ deleted: 0, stillNeeded: 0, unreachable: 1, failed: 0 });
    expect(stripeDeletes()).toEqual([]);
    expect((await h.call('GET', '/api/owner/stripe', owner)).body.cardsToDelete).toMatchObject([
      { kind: 'savedCard', stripeAccountId: null, customerId: 'cus_TestFixture000001', card: { brand: 'amex', last4: '0005', expMonth: 11, expYear: 2026 } },
    ]);
    // It isn't picked up again.
    h.setNow('2026-12-02T19:17:00Z');
    const next = await cron();
    expect(next.body.savedCards).toEqual({ deleted: 0, stillNeeded: 0, unreachable: 0, failed: 0 });
    expect(next.body.cardsToDelete).toEqual({ deleted: 0, unreachable: 0, failed: 0 });
    expect(stripeDeletes()).toEqual([]);
  });

  it('saved with a test key, deleted once the key is live: listed, never taken for deleted (Stripe would say “no such customer”)', async () => {
    const token = await saveCard();
    h.config.stripeSecretKey = 'sk_live_fixture';
    expect((await removeCard(token)).body.cardDeletion.status).toBe('shop');
    expect(stripeDeletes()).toEqual([]);
    expect(await cardRow()).toMatchObject({ stripe_unreachable_at: new Date('2026-11-02T17:00:00Z'), stripe_customer_id: 'cus_TestFixture000001' });
    expect((await h.call('GET', '/api/owner/stripe', owner)).body.cardsToDelete).toMatchObject([{ kind: 'savedCard', livemode: false, stripeAccountId: null }]);
  });

  it('the key switched to live for a day and back: what waited for the shop meanwhile is deleted at Stripe by the next run, and off the list', async () => {
    // A saved card, and a page nobody finished, both in test mode.
    const token = await saveCard();
    const saved = await cardRow();
    const p = await cardPage(true, '192.0.2.82');
    // (Saving the card read its page from Stripe.) With the live key, nothing at all is asked of Stripe.
    const before = pageCalls().length;
    const testKey = h.config.stripeSecretKey!;
    h.config.stripeSecretKey = 'sk_live_fixture';
    expect((await removeCard(token)).body.cardDeletion.status).toBe('shop');
    h.setNow('2026-11-03T19:17:00Z');
    const live = await cron();
    expect(live.body.unfinishedCardPages).toEqual({ deleted: 0, unreachable: 1, failed: 0 });
    expect(live.body.cardsToDelete).toEqual({ deleted: 0, unreachable: 0, failed: 0 });
    expect(await listed()).toMatchObject([
      { id: saved.id, kind: 'savedCard', livemode: false },
      { id: p.sessionId, kind: 'cardPage', livemode: false },
    ]);
    expect(pageCalls().slice(before)).toEqual([]);
    // Back to the test key. The next run deletes both at Stripe; Stripe doesn't answer for the card the first time.
    h.config.stripeSecretKey = testKey;
    h.setNow('2026-11-04T19:17:00Z');
    h.stripe.nextError = stripeError('StripeConnectionError', {}, 'socket hang up');
    const back = await cron();
    expect(back.body.savedCards).toEqual({ deleted: 0, stillNeeded: 0, unreachable: 0, failed: 0 });
    expect(back.body.unfinishedCardPages).toEqual({ deleted: 0, unreachable: 0, failed: 0 });
    expect(back.body.cardsToDelete).toEqual({ deleted: 1, unreachable: 0, failed: 1 });
    expect(await page(p.sessionId)).toMatchObject({ deleted_at: new Date('2026-11-04T19:17:00Z'), stripe_customer_id: null, stripe_unreachable_at: null });
    expect(await listed()).toMatchObject([{ id: saved.id, kind: 'savedCard' }]);
    // …and the day after, the card too.
    h.setNow('2026-11-05T19:17:00Z');
    expect((await cron()).body.cardsToDelete).toEqual({ deleted: 1, unreachable: 0, failed: 0 });
    expect(h.stripe.deletedCustomers).toEqual(new Set([saved.stripe_customer_id, (await h.stripe.sessions.get(p.sessionId)!.customer) as string]));
    expect(await cardRow()).toMatchObject({
      removed_at: new Date('2026-11-02T17:00:00Z'),
      stripe_unreachable_at: null,
      stripe_unreachable_setup: null,
      checkout_session_id: null,
      stripe_customer_id: null,
      stripe_payment_method_id: null,
    });
    expect(await listed()).toEqual([]);
    expect((await removeCard(token)).body.cardDeletion.status).toBe('deleted');
    // Nothing more is asked.
    const asked = pageCalls().length;
    h.setNow('2026-11-06T19:17:00Z');
    expect((await cron()).body.cardsToDelete).toEqual({ deleted: 0, unreachable: 0, failed: 0 });
    expect(pageCalls()).toHaveLength(asked);
  });

  it('saved with the shop’s own key, removed once the key is another Stripe account’s: Stripe has never heard of its Customer, so it’s the shop’s, never taken for deleted', async () => {
    const token = await saveCard();
    const saved = await cardRow();
    const { other, shopsKey } = anotherAccountsKey();
    expect((await removeCard(token)).body.cardDeletion).toEqual({ status: 'shop', message: CARD_SHOP_MESSAGE });
    // Asked whether its Customer was deleted: Stripe keeps deleted ones, and has never heard of this one.
    expect(other.calls.map((c) => [c.method, c.params])).toEqual([
      ['paymentMethods.detach', { id: saved.stripe_payment_method_id }],
      ['customers.del', { id: saved.stripe_customer_id }],
      ['customers.retrieve', { id: saved.stripe_customer_id }],
    ]);
    expect(await cardRow()).toMatchObject({
      removed_at: new Date('2026-11-02T17:00:00Z'),
      stripe_unreachable_at: new Date('2026-11-02T17:00:00Z'),
      stripe_customer_id: saved.stripe_customer_id,
      stripe_payment_method_id: saved.stripe_payment_method_id,
    });
    expect(await listed()).toMatchObject([{ id: saved.id, kind: 'savedCard', stripeAccountId: null, customerId: saved.stripe_customer_id }]);
    // Not asked about again while that key stays.
    h.setNow('2026-11-03T19:17:00Z');
    expect((await cron()).body.cardsToDelete).toEqual({ deleted: 0, unreachable: 0, failed: 0 });
    expect(other.calls).toHaveLength(3);
    // The shop's own key back: deleted at Stripe by the next run, and off the list.
    h.config.stripeSecretKey = shopsKey;
    h.setNow('2026-11-04T19:17:00Z');
    expect((await cron()).body.cardsToDelete).toEqual({ deleted: 1, unreachable: 0, failed: 0 });
    expect(stripeDeletes().map((c) => c.method)).toEqual(['paymentMethods.detach', 'customers.del']);
    expect(h.stripe.deletedCustomers).toEqual(new Set([saved.stripe_customer_id]));
    expect(await listed()).toEqual([]);
  });

  it('a Customer the shop already deleted in its Dashboard is deleted, not the shop’s', async () => {
    const token = await saveCard();
    const saved = await cardRow();
    await h.stripe.customers.del(saved.stripe_customer_id);
    expect((await removeCard(token)).body.cardDeletion.status).toBe('deleted');
    expect(h.stripe.calls.filter((c) => c.method === 'customers.retrieve').map((c) => c.params)).toEqual([{ id: saved.stripe_customer_id }]);
    expect(await cardRow()).toMatchObject({ stripe_unreachable_at: null, stripe_customer_id: null });
    expect(await listed()).toEqual([]);
  });

  it('Stripe has no such customer to delete, then finds it after all, or can’t say: tried again, never taken for deleted or for the shop’s', async () => {
    const token = await saveCard();
    const saved = await cardRow();
    const realDel = h.stripe.customers.del;
    const realRetrieve = h.stripe.customers.retrieve;
    // Stripe's two answers crossed: "no such customer" to delete it, then there it is, not deleted.
    h.stripe.customers.del = async (id: string) => {
      throw stripeError('StripeInvalidRequestError', { code: 'resource_missing', param: 'id', statusCode: 404 }, `No such customer: '${id}'`);
    };
    expect((await removeCard(token)).body.cardDeletion.status).toBe('scheduled');
    expect(h.logs.at(-1)).toMatchObject({ level: 'error', message: 'Stripe delete customer failed' });
    // Or Stripe doesn't answer whether it was deleted.
    h.stripe.customers.retrieve = async () => {
      throw stripeError('StripeConnectionError', {}, 'socket hang up');
    };
    h.setNow('2026-11-03T19:17:00Z');
    expect((await cron()).body.savedCards).toEqual({ deleted: 0, stillNeeded: 0, unreachable: 0, failed: 1 });
    expect(h.logs.at(-1)).toMatchObject({ level: 'error', message: 'Stripe retrieve customer failed', details: { type: 'StripeConnectionError' } });
    // Either way it isn't removed, isn't the shop's, and keeps its ids: the next run deletes it.
    expect(await cardRow()).toMatchObject({ removed_at: null, stripe_unreachable_at: null, stripe_customer_id: saved.stripe_customer_id });
    expect(await listed()).toEqual([]);
    h.stripe.customers.del = realDel;
    h.stripe.customers.retrieve = realRetrieve;
    h.setNow('2026-11-04T19:17:00Z');
    expect((await cron()).body.savedCards).toEqual({ deleted: 1, stillNeeded: 0, unreachable: 0, failed: 0 });
    expect(h.stripe.deletedCustomers).toEqual(new Set([saved.stripe_customer_id]));
    expect(await cardRow()).toMatchObject({ stripe_unreachable_at: null, stripe_customer_id: null });
  });

  it('on a connected account the shop took the platform’s access away from: listed with that account', async () => {
    const account = await connectedShop(h);
    const token = await saveCard();
    const saved = await cardRow();
    h.stripe.nextError = stripeError('StripePermissionError', { statusCode: 403 }, `The provided key does not have access to account '${account}' (or that account does not exist).`);
    expect((await removeCard(token)).body.cardDeletion.status).toBe('shop');
    expect(h.stripe.deletedCustomers.size).toBe(0);
    expect(await cardRow()).toMatchObject({ stripe_account_id: account, stripe_customer_id: saved.stripe_customer_id, stripe_unreachable_at: new Date('2026-11-02T17:00:00Z') });
    expect((await h.call('GET', '/api/owner/stripe', owner)).body.cardsToDelete).toMatchObject([
      { kind: 'savedCard', stripeAccountId: account, livemode: false, customerId: saved.stripe_customer_id },
    ]);
  });

  it('one the platform has no access to isn’t asked about every day: only again once the server’s Stripe setup changes', async () => {
    const account = await connectedShop(h);
    const token = await saveCard();
    const revoked = () =>
      stripeError('StripePermissionError', { statusCode: 403 }, `The provided key does not have access to account '${account}' (or that account does not exist).`);
    h.stripe.nextError = revoked();
    expect((await removeCard(token)).body.cardDeletion.status).toBe('shop');
    const asked = () => stripeDeletes().length;
    expect(asked()).toBe(1);
    h.setNow('2026-11-03T19:17:00Z');
    expect((await cron()).body.cardsToDelete).toEqual({ deleted: 0, unreachable: 0, failed: 0 });
    expect(asked()).toBe(1);
    // The platform's key changes (rotated, say): asked once more, still no access, still listed.
    h.config.stripeSecretKey = 'sk_test_PlatformRotated';
    h.setNow('2026-11-04T19:17:00Z');
    h.stripe.nextError = revoked();
    expect((await cron()).body.cardsToDelete).toEqual({ deleted: 0, unreachable: 1, failed: 0 });
    expect(asked()).toBe(2);
    h.setNow('2026-11-05T19:17:00Z');
    expect((await cron()).body.cardsToDelete).toEqual({ deleted: 0, unreachable: 0, failed: 0 });
    expect(asked()).toBe(2);
    expect(await listed()).toMatchObject([{ kind: 'savedCard', stripeAccountId: account }]);
  });

  it('a card kept for the shop can’t be charged a fee', async () => {
    const token = await saveCard();
    const booking = await book(token);
    h.setNow('2026-11-03T18:50:00Z');
    await setStatus(booking.id, 'noShow');
    // Removed here with its ids kept (say the shop changed how it connects to Stripe).
    await h.database.pool.query(`UPDATE saved_cards SET removed_at = now(), stripe_unreachable_at = now(), stripe_unreachable_setup = 'connect:0123456789abcdef'`);
    const res = await h.call('POST', `/api/owner/appointments/${booking.id}/no-show-fee`, owner);
    expect(res.status).toBe(409);
    expect(res.body.error).toEqual({ code: 'not_chargeable', message: "The client's saved card was deleted, so it can't be charged." });
    expect(h.stripe.calls.filter((c) => c.method === 'paymentIntents.create')).toEqual([]);
  });
});
