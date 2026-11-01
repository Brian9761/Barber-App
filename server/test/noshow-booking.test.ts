import { describe, expect, it } from 'vitest';
import { newManageToken } from '../src/auth.js';
import { RESPONSES } from './helpers/contract.js';
import { useHarness, type FakeCard } from './helpers/harness.js';

// Booking with no-show protection: a card on file and the agreed policy when
// the booking needs them, and exactly today's behavior when it doesn't.

// Monday Nov 2 2026, 9:00 AM PST. Tuesday Nov 3 opens at 10:00 PST = 18:00Z.
const h = useHarness({ now: '2026-11-02T17:00:00Z' });

const FLOW45 = 'flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a';
const LINEUP = 'carlos-rafael/0b5b851e-ab05-44a1-8d42-dc9dbc5f02eb';
const TUE10 = '2026-11-03T18:00:00Z';
const customer = { name: 'Card Client', phone: '(442) 555-0140' };

async function policyFor(query: string): Promise<string | null> {
  return (await h.call('GET', `/api/no-show-policy?${query}`)).body.policyText;
}
const flowPolicy = () => policyFor(`offeringId=${encodeURIComponent(FLOW45)}`);

/** A card saved the way the app does it; returns its token. */
async function savedCard(card?: FakeCard): Promise<string> {
  const token = newManageToken();
  const checkout = await h.call('POST', '/api/cards/checkout', { headers: { 'x-card-token': token }, body: { offeringId: FLOW45 }, ip: '192.0.2.200' });
  expect(checkout.status, checkout.text).toBe(201);
  h.stripe.completeSession(checkout.body.sessionId, card);
  const saved = await h.call('POST', '/api/cards', { headers: { 'x-card-token': token }, body: { sessionId: checkout.body.sessionId }, ip: '192.0.2.200' });
  expect(saved.status, saved.text).toBe(201);
  return token;
}

function book(body: Record<string, unknown>, headers: Record<string, string> = {}, ip = '203.0.113.60') {
  return h.call('POST', '/api/appointments', { body: { offeringId: FLOW45, start: TUE10, customer, ...body }, headers, ip });
}

async function row(id: string) {
  return (await h.database.pool.query('SELECT * FROM appointments WHERE id = $1', [id])).rows[0];
}

describe('booking when no card is needed', () => {
  it('without Stripe: books as before, with no card and no fee, even if a card token is sent', async () => {
    const res = await book({}, { 'x-card-token': newManageToken() });
    expect(res.status).toBe(201);
    expect(res.body.appointment.card).toBeNull();
    expect(res.body.appointment.noShowFee).toBeNull();
    expect(RESPONSES['appointment-created'].safeParse(res.body).success).toBe(true);
    const stored = await row(res.body.appointment.id);
    expect(stored).toMatchObject({ saved_card_id: null, no_show_fee_cents: null, no_show_policy: null, no_show_consent_at: null, no_show_fee_status: 'none' });
  });

  it('with protection turned off, or for an item with no fee', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    const lineup = await book({ offeringId: LINEUP, start: '2026-11-03T18:00:00Z' });
    expect(lineup.status, lineup.text).toBe(201);
    expect(lineup.body.appointment.card).toBeNull();
    await h.call('PATCH', '/api/owner/no-show-settings', { owner: true, body: { enabled: false } });
    const off = await book({});
    expect(off.status).toBe(201);
    expect(off.body.appointment.noShowFee).toBeNull();
  });

  it('a fee under 50¢ means no card is needed', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    await h.call('PATCH', '/api/owner/no-show-settings', { owner: true, body: { percent: 1 } });
    // 1% of $35 is 35¢.
    expect((await h.call('GET', `/api/no-show-policy?offeringId=${encodeURIComponent(FLOW45)}`)).body.required).toBe(false);
    expect((await book({})).status).toBe(201);
  });

  it('the shop’s own bookings never need a card', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    const res = await h.call('POST', '/api/owner/appointments', { owner: true, body: { offeringId: FLOW45, start: TUE10, customer: { name: 'Walk-in' } } });
    expect(res.status).toBe(201);
    expect(res.body.appointment.card).toBeNull();
    expect(res.body.appointment.noShowFee).toBeNull();
  });
});

describe('booking when a card is needed', () => {
  it('no card: 400 card_required, and it isn’t counted as a booking attempt', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    const res = await book({ noShowPolicy: await flowPolicy() });
    expect(res.status).toBe(400);
    expect(res.body.error).toEqual({ code: 'card_required', message: "Add a card to book this time. You won't be charged now." });
    expect((await h.database.pool.query('SELECT count(*)::int AS n FROM rate_limits')).rows[0].n).toBe(0);
    expect((await h.database.pool.query('SELECT count(*)::int AS n FROM appointments')).rows[0].n).toBe(0);
  });

  it('a card token the server doesn’t know, or a malformed one', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    const unknown = await book({ noShowPolicy: await flowPolicy() }, { 'x-card-token': newManageToken() });
    expect(unknown.status).toBe(400);
    expect(unknown.body.error).toEqual({ code: 'card_required', message: "We couldn't find your saved card. Add it again." });
    const malformed = await book({ noShowPolicy: await flowPolicy() }, { 'x-card-token': 'not-a-token' });
    expect(malformed.status).toBe(400);
    expect(malformed.body.error.code).toBe('invalid_request');
  });

  it('a card that expires before the appointment’s month is no card; one good through that month works', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    const october = await savedCard({ brand: 'visa', last4: '0001', exp_month: 11, exp_year: 2026 });
    // Booked for December 1: the card ends November 30.
    const december = await book({ start: '2026-12-01T18:00:00Z', noShowPolicy: await flowPolicy() }, { 'x-card-token': october });
    expect(december.status).toBe(400);
    expect(december.body.error).toEqual({ code: 'card_required', message: 'That card expires before your appointment. Add another card.' });
    const november = await book({ noShowPolicy: await flowPolicy() }, { 'x-card-token': october });
    expect(november.status, november.text).toBe(201);
  });

  it('a card saved in test mode can’t book once the shop uses a live key', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    const token = await savedCard();
    h.config.stripeSecretKey = 'sk_live_fixture';
    const res = await book({ noShowPolicy: await flowPolicy() }, { 'x-card-token': token });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('card_required');
  });

  it('the policy must be the one the server gives for this booking right now', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    const token = await savedCard();
    const headers = { 'x-card-token': token };
    const missing = await book({}, headers);
    expect(missing.status).toBe(409);
    expect(missing.body.error).toEqual({ code: 'policy_changed', message: 'The no-show policy for this booking just changed. Check it and book again.' });
    const otherTarget = await book({ noShowPolicy: await policyFor('serviceId=haircut-and-beard&barberId=any') }, headers);
    expect(otherTarget.status).toBe(409);
    // The owner changes the fee between the client reading the policy and booking.
    const seen = await flowPolicy();
    await h.call('PATCH', '/api/owner/no-show-settings', { owner: true, body: { percent: 60 } });
    expect((await book({ noShowPolicy: seen }, headers)).status).toBe(409);
    const fresh = await book({ noShowPolicy: await flowPolicy() }, headers);
    expect(fresh.status).toBe(201);
    expect(fresh.body.appointment.noShowFee.amountCents).toBe(2100);
  });

  it('books with the card on file: the fee for this item, the exact policy and the consent time are kept', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    const token = await savedCard({ brand: 'amex', last4: '8431', exp_month: 1, exp_year: 2031 });
    const policy = await flowPolicy();
    h.advance(3);
    const res = await book({ noShowPolicy: policy }, { 'x-card-token': token });
    expect(res.status).toBe(201);
    expect(res.body.appointment.card).toEqual({ brand: 'amex', last4: '8431' });
    expect(res.body.appointment.noShowFee).toEqual({ amountCents: 1750, status: 'none', chargedAt: null, message: null });
    expect(res.body.appointment.payment).toEqual({ status: 'unpaid', amountCents: null, paidAt: null });
    const stored = await row(res.body.appointment.id);
    expect(stored.no_show_policy).toBe(policy);
    expect(stored.no_show_consent_at.toISOString()).toBe('2026-11-02T17:03:00.000Z');
    expect(stored.saved_card_id).toMatch(/^[0-9a-f-]{36}$/);
    // And the client sees it with their manage token.
    const read = await h.call('GET', `/api/appointments/${res.body.appointment.id}`, { headers: { 'x-manage-token': res.body.manageToken } });
    expect(read.body.appointment.card).toEqual({ brand: 'amex', last4: '8431' });
  });

  it('any barber: the fee of the barber the shop picks, within the range the client saw', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    const token = await savedCard();
    const policy = await policyFor('serviceId=haircut-and-beard&barberId=any');
    const prices: Record<string, number> = { 'israel-flores': 5500, 'carlos-rafael': 6000, flowxbori: 5500, 'cristian-ceja': 5500, 'julian-ramos': 5500 };
    const fees = new Set<number>();
    for (let i = 0; i < 5; i++) {
      const res = await book(
        { serviceId: 'haircut-and-beard', barberId: 'any', offeringId: undefined, start: TUE10, customer: { name: `Any ${i}`, phone: `44255501${50 + i}` }, noShowPolicy: policy },
        { 'x-card-token': token },
        `198.51.100.${i}`,
      );
      expect(res.status, res.text).toBe(201);
      const fee = res.body.appointment.noShowFee.amountCents;
      expect(fee).toBe(Math.floor((prices[res.body.appointment.barberId]! * 50 + 50) / 100));
      fees.add(fee);
      expect((await row(res.body.appointment.id)).no_show_policy).toBe(policy);
    }
    expect([...fees].sort()).toEqual([2750, 3000]);
  });

  it('one card books more than once; a retry with the manage token doesn’t look at the card again', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    const card = await savedCard();
    const manage = newManageToken();
    const policy = await flowPolicy();
    const first = await book({ noShowPolicy: policy }, { 'x-card-token': card, 'x-manage-token': manage });
    expect(first.status).toBe(201);
    // The retry after a lost answer: no card token, an old policy, Stripe off — still the same booking.
    h.config.stripeSecretKey = undefined;
    const retry = await book({ noShowPolicy: 'whatever' }, { 'x-manage-token': manage });
    expect(retry.status).toBe(200);
    expect(retry.body).toEqual(first.body);
    h.config.stripeSecretKey = 'sk_test_fixture';
    const second = await book({ start: '2026-11-03T19:00:00Z', noShowPolicy: policy }, { 'x-card-token': card }, '203.0.113.61');
    expect(second.status).toBe(201);
    expect(second.body.appointment.card).toEqual(first.body.appointment.card);
  });

  it('the schema keeps the card, fee, policy and consent together', async () => {
    const pool = h.database.pool;
    const res = await book({});
    const id = res.body.appointment.id;
    await expect(pool.query('UPDATE appointments SET no_show_fee_cents = 1000 WHERE id = $1', [id])).rejects.toThrow(/appointments_no_show_terms/);
    await expect(pool.query(`UPDATE appointments SET no_show_fee_status = 'pending' WHERE id = $1`, [id])).rejects.toThrow(
      /appointments_no_show_fee_needs_terms/,
    );
  });
});
