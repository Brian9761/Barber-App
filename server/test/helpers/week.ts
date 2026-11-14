import Stripe from 'stripe';
import { expect } from 'vitest';
import { newManageToken } from '../../src/auth.js';
import { protectionOn, type CallResult, type Harness } from './harness.js';

// A realistic week at the shop, Sunday Nov 1 – Saturday Nov 7, 2026 (plus the week before),
// made through the real endpoints so every time the server records is the one it would in
// the shop. The analytics tests check their numbers against it by hand
// (test/analytics.test.ts lists every event and what it adds up to). All times below are the
// shop's (Pacific): daylight saving time ends on Sunday Nov 1 at 2 AM, so that day is 25
// hours long, and late-evening sales fall on the next day in UTC.
//
// Prices: Izzy's haircut $40 (60 min), VIP $80 (75 min), military haircut $25; Carlos's haircut
// $45 (45 min), haircut & beard $60; Flowxbori's haircut $35 (45 min) or $40 (60 min);
// Cristian's and Julian's haircut $35 (45 min), haircut & beard $55 (60 min).
// No-show protection is on: the fee is the full price.

export const OFFERING = {
  izzyHaircut: 'israel-flores/0d069a9e-c5ea-4cca-ae34-3f38bf668940',
  izzyVip: 'israel-flores/9a33be59-43eb-445c-9c18-6435125b1f75',
  carlosHaircut: 'carlos-rafael/9343fc67-b196-4604-987e-a4a9b6b4cc41',
  carlosBeard: 'carlos-rafael/23936782-15f7-4ed5-9cde-ece8cc1d730c',
  flowHaircut45: 'flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a',
  flowHaircut60: 'flowxbori/0d069a9e-c5ea-4cca-ae34-3f38bf668940',
  cristianHaircut: 'cristian-ceja/bbb0c294-87a6-465d-9f55-6f579dcb399a',
  cristianBeard: 'cristian-ceja/23936782-15f7-4ed5-9cde-ece8cc1d730c',
  julianHaircut: 'julian-ramos/bbb0c294-87a6-465d-9f55-6f579dcb399a',
  julianBeard: 'julian-ramos/23936782-15f7-4ed5-9cde-ece8cc1d730c',
} as const;

export const WEBHOOK_SECRET = 'whsec_fixture_week';
/** Saturday Nov 7, 3:00 PM: when the week's analytics are read. */
export const WEEK_NOW = '2026-11-07T23:00:00Z';

const owner = { owner: true } as const;

function ok<T = any>(res: CallResult<T>, status = 200): T {
  expect(res.status, res.text).toBe(status);
  return res.body;
}

/** A signed Stripe webhook delivery: an event Stripe made at `created` (Unix seconds; now by default). */
export async function sendWebhook(
  h: Harness,
  type: string,
  object: Record<string, unknown>,
  created = Math.floor(h.now.getTime() / 1000),
): Promise<CallResult> {
  const payload = JSON.stringify({
    id: `evt_fixture_${Math.random().toString(36).slice(2, 10)}`,
    object: 'event',
    api_version: '2026-10-28.endive',
    created,
    type,
    livemode: false,
    pending_webhooks: 1,
    request: { id: null, idempotency_key: null },
    data: { object },
  });
  const signature = Stripe.webhooks.generateTestHeaderString({ payload, secret: h.config.stripeWebhookSecret ?? WEBHOOK_SECRET });
  return h.call('POST', '/api/stripe/webhook', { rawBody: payload, headers: { 'content-type': 'application/json', 'stripe-signature': signature } });
}

export interface Week {
  /** Appointments by their name in test/analytics.test.ts (A0–A16, C1–C3). */
  appointments: Record<string, string>;
  /** Products: pomade, beardOil, seaSalt, oldGel (deleted on Friday). */
  products: Record<string, string>;
  /** Sales by name (S0–S10; S6 was voided). */
  sales: Record<string, string>;
}

export async function seedWeek(h: Harness): Promise<Week> {
  const week: Week = { appointments: {}, products: {}, sales: {} };
  const at = (iso: string) => h.setNow(iso);
  const book = async (name: string, offeringId: string, start: string, client: string) => {
    const res = ok(await h.call('POST', '/api/owner/appointments', { ...owner, body: { offeringId, start, customer: { name: client } } }), 201);
    week.appointments[name] = res.appointment.id;
  };
  const mark = async (name: string, status: string) => {
    ok(await h.call('PATCH', `/api/owner/appointments/${week.appointments[name]}`, { ...owner, body: { status } }));
  };
  const sell = async (name: string, body: Record<string, unknown>) => {
    week.sales[name] = ok(await h.call('POST', '/api/owner/sales', { ...owner, body: { method: 'cash', ...body } }), 201).sale.id;
  };
  const cardPayment = async (amountCents: number, sale: Record<string, unknown>) =>
    ok(await h.call('POST', '/api/owner/payments', { ...owner, body: { amountCents, sale } }), 201).paymentIntentId as string;

  // Saturday Oct 24, 9 AM: the shop sets things up.
  at('2026-10-24T16:00:00Z');
  await protectionOn(h);
  h.config.stripeTerminalLocationId = 'tml_FixtureLocation';
  h.config.stripeWebhookSecret = WEBHOOK_SECRET;
  const product = async (key: string, name: string, priceCents?: number) => {
    const body = ok(await h.call('POST', '/api/owner/products', { ...owner, body: { name, ...(priceCents ? { priceCents } : {}) } }), 201);
    week.products[key] = body.product.id;
  };
  await product('pomade', 'Matte pomade', 1800);
  await product('beardOil', 'Beard oil', 1500);
  await product('seaSalt', 'Sea salt spray');
  await product('oldGel', 'Old gel', 1000);
  const timeOff = async (barberId: string | null, start: string, end: string, reason: string) => {
    ok(await h.call('POST', '/api/owner/time-off', { ...owner, body: { barberId, start, end, reason } }), 201);
  };
  await timeOff(null, '2026-11-04T08:00:00Z', '2026-11-05T08:00:00Z', 'Staff training: shop closed'); // all of Wed Nov 4
  await timeOff('julian-ramos', '2026-11-03T21:00:00Z', '2026-11-03T23:00:00Z', 'Dentist'); // Tue 1–3 PM
  await timeOff('carlos-rafael', '2026-11-05T16:00:00Z', '2026-11-05T19:00:00Z', 'School run'); // Thu 8–11 AM (10–11 counts)
  await timeOff('cristian-ceja', '2026-11-04T22:00:00Z', '2026-11-05T01:00:00Z', 'Errands'); // Wed 2–5 PM, inside the closure
  await timeOff('flowxbori', '2026-11-07T01:00:00Z', '2026-11-07T20:00:00Z', 'Trip'); // Fri 5 PM – Sat noon

  // Thursday Oct 29, 2 PM: a walk-in pays Carlos cash for a haircut ($45).
  at('2026-10-29T21:00:00Z');
  await sell('P1', { barberId: 'carlos-rafael', items: [{ kind: 'service', serviceId: 'haircut' }] });
  // Friday Oct 30: Julian's 11 AM haircut is marked done, never checked out ($35).
  at('2026-10-30T16:00:00Z');
  await book('P2', OFFERING.julianHaircut, '2026-10-30T18:00:00Z', 'Tom');
  at('2026-10-30T18:50:00Z');
  await mark('P2', 'completed');

  // Saturday Oct 31, 10 AM: three clients book online with a card on file.
  at('2026-10-31T17:00:00Z');
  const cardToken = newManageToken();
  const checkout = ok(
    await h.call('POST', '/api/cards/checkout', { headers: { 'x-card-token': cardToken }, body: { offeringId: OFFERING.flowHaircut45 } }),
    201,
  );
  h.stripe.completeSession(checkout.sessionId);
  ok(await h.call('POST', '/api/cards', { headers: { 'x-card-token': cardToken }, body: { sessionId: checkout.sessionId } }), 201);
  const online = async (name: string, offeringId: string, start: string, client: string, phone: string) => {
    const policy = ok(await h.call('GET', `/api/no-show-policy?offeringId=${encodeURIComponent(offeringId)}`)).policyText;
    const res = ok(
      await h.call('POST', '/api/appointments', {
        headers: { 'x-card-token': cardToken },
        body: { offeringId, start, customer: { name: client, phone }, noShowPolicy: policy },
      }),
      201,
    );
    week.appointments[name] = res.appointment.id;
    return res.manageToken as string;
  };
  await online('C1', OFFERING.flowHaircut45, '2026-11-03T18:00:00Z', 'Fay', '4425550101'); // Tue 10 AM
  const ivy = await online('C2', OFFERING.izzyHaircut, '2026-11-05T22:00:00Z', 'Ivy', '4425550102'); // Thu 2 PM
  const jay = await online('C3', OFFERING.julianHaircut, '2026-11-05T23:00:00Z', 'Jay', '4425550103'); // Thu 3 PM
  // 4 PM: Julian's 6 PM haircut (A0) is done, but not checked out until Sunday.
  at('2026-10-31T23:00:00Z');
  await book('A0', OFFERING.julianHaircut, '2026-11-01T01:00:00Z', 'Una');
  at('2026-11-01T01:50:00Z');
  await mark('A0', 'completed');
  // 11 PM (PDT): Izzy rings up a walk-in's haircut, cash ($40). Still Saturday Oct 31.
  at('2026-11-01T06:00:00Z');
  await sell('P3', { barberId: 'israel-flores', customerName: 'Night owl', items: [{ kind: 'service', serviceId: 'haircut' }] });

  // Sunday Nov 1 (clocks went back at 2 AM; now PST).
  at('2026-11-01T17:00:00Z'); // 9 AM
  await book('A1', OFFERING.izzyHaircut, '2026-11-01T18:00:00Z', 'Andre'); // 10 AM
  await book('A2', OFFERING.flowHaircut45, '2026-11-01T20:00:00Z', 'Ben'); // noon
  at('2026-11-01T18:15:00Z'); // 10:15 AM: Saturday's A0 checked out at its booked price ($35)
  await sell('S0', { appointmentId: week.appointments.A0, items: [{ kind: 'service', serviceId: 'haircut' }] });
  at('2026-11-01T19:05:00Z'); // 11:05 AM: Andre pays a haircut and a pomade
  await sell('S1', {
    appointmentId: week.appointments.A1,
    items: [
      { kind: 'service', serviceId: 'haircut' },
      { kind: 'product', productId: week.products.pomade },
    ],
  });
  at('2026-11-01T20:50:00Z'); // 12:50 PM: Ben's haircut marked done, no checkout
  await mark('A2', 'completed');
  at('2026-11-02T07:30:00Z'); // 11:30 PM PST, still Sunday: a gift card and two beard oils
  await sell('S2', {
    barberId: 'carlos-rafael',
    customerName: 'Late client',
    items: [
      { kind: 'custom', name: 'Gift card', unitCents: 2500 },
      { kind: 'product', productId: week.products.beardOil, quantity: 2 },
    ],
  });

  // Monday Nov 2
  at('2026-11-02T17:00:00Z');
  await book('A3', OFFERING.carlosHaircut, '2026-11-02T18:00:00Z', 'Chris'); // 10 AM
  await book('A4', OFFERING.cristianBeard, '2026-11-02T19:00:00Z', 'Dan'); // 11 AM
  await book('A5', OFFERING.julianHaircut, '2026-11-02T21:00:00Z', 'Eli'); // 1 PM
  at('2026-11-02T18:48:00Z'); // Chris taps his card for a haircut and a pomade ($63)
  const chris = await cardPayment(6300, {
    appointmentId: week.appointments.A3,
    items: [
      { kind: 'service', serviceId: 'haircut' },
      { kind: 'product', productId: week.products.pomade },
    ],
  });
  h.stripe.succeed(chris);
  at('2026-11-02T18:50:00Z'); // 10:50 AM: the app confirms it
  week.sales.S3 = ok(await h.call('POST', `/api/owner/payments/${chris}/complete`, owner)).payment.saleId;
  at('2026-11-02T19:20:00Z');
  await mark('A4', 'noShow');
  at('2026-11-02T21:50:00Z'); // Eli pays by Zelle
  await sell('S4', { appointmentId: week.appointments.A5, method: 'other', items: [{ kind: 'service', serviceId: 'haircut' }] });

  // Tuesday Nov 3
  at('2026-11-03T17:00:00Z');
  await book('A6', OFFERING.izzyVip, '2026-11-03T19:00:00Z', 'Gus'); // 11 AM
  await book('A7', OFFERING.julianHaircut, '2026-11-03T23:00:00Z', 'Hal'); // 3 PM, right after Julian's time off
  at('2026-11-03T18:50:00Z'); // 10:50 AM, after her 10–10:45: Fay never came: no-show, fee charged ($35)
  await mark('C1', 'noShow');
  expect(ok(await h.call('POST', `/api/owner/appointments/${week.appointments.C1}/no-show-fee`, owner)).appointment.noShowFee.status).toBe('charged');
  at('2026-11-03T20:20:00Z'); // Gus: VIP and a sea salt spray (no list price: $12)
  await sell('S5', {
    appointmentId: week.appointments.A6,
    items: [
      { kind: 'service', serviceId: 'vip' },
      { kind: 'product', productId: week.products.seaSalt, unitCents: 1200 },
    ],
  });
  at('2026-11-03T23:50:00Z');
  await mark('A7', 'completed');

  // Wednesday Nov 4: closed.

  // Thursday Nov 5
  at('2026-11-05T17:00:00Z');
  await book('A8', OFFERING.carlosBeard, '2026-11-05T19:00:00Z', 'Kai'); // 11 AM, right after Carlos's time off
  await book('A9', OFFERING.cristianHaircut, '2026-11-05T20:00:00Z', 'Leo'); // noon
  at('2026-11-05T19:00:00Z'); // 11 AM: Jay cancels his 3 PM in the app, in time
  ok(await h.call('POST', `/api/appointments/${week.appointments.C3}/cancel`, { headers: { 'x-manage-token': jay } }));
  at('2026-11-05T20:05:00Z'); // Kai checked out without the gel he bought…
  await sell('S6', { appointmentId: week.appointments.A8, items: [{ kind: 'service', serviceId: 'haircut-and-beard' }] });
  at('2026-11-05T20:07:00Z'); // …so that sale is voided and rung up again
  ok(await h.call('POST', `/api/owner/sales/${week.sales.S6}/void`, { ...owner, body: { reason: 'Forgot the gel' } }));
  at('2026-11-05T20:08:00Z');
  await sell('S7', {
    appointmentId: week.appointments.A8,
    items: [
      { kind: 'service', serviceId: 'haircut-and-beard' },
      { kind: 'product', productId: week.products.oldGel },
    ],
  });
  at('2026-11-05T20:50:00Z');
  await mark('A9', 'completed');
  at('2026-11-05T21:30:00Z'); // 1:30 PM: Ivy cancels her 2 PM in the app, is warned it's late, and confirms
  const cancelIvy = (body?: Record<string, unknown>) =>
    h.call('POST', `/api/appointments/${week.appointments.C2}/cancel`, { headers: { 'x-manage-token': ivy }, ...(body ? { body } : {}) });
  expect((await cancelIvy()).body.error.code).toBe('late_cancel_fee');
  ok(await cancelIvy({ acceptLateCancelFee: true }));

  // Friday Nov 6
  at('2026-11-06T17:00:00Z');
  await book('A10', OFFERING.flowHaircut60, '2026-11-06T18:00:00Z', 'Max'); // 10 AM
  await book('A11', OFFERING.julianBeard, '2026-11-07T00:00:00Z', 'Ned'); // 4 PM
  at('2026-11-06T17:30:00Z'); // 9:30 AM: the owner charges Ivy's late cancellation ($40)
  expect(ok(await h.call('POST', `/api/owner/appointments/${week.appointments.C2}/no-show-fee`, owner)).appointment.noShowFee.status).toBe('charged');
  at('2026-11-06T19:00:00Z'); // Max taps his card: haircut and two pomades ($76)…
  const max = await cardPayment(7600, {
    appointmentId: week.appointments.A10,
    items: [
      { kind: 'service', serviceId: 'haircut' },
      { kind: 'product', productId: week.products.pomade, quantity: 2 },
    ],
  });
  h.stripe.succeed(max);
  at('2026-11-06T19:05:00Z'); // …and only Stripe's webhook says it went through
  ok(await sendWebhook(h, 'payment_intent.succeeded', { object: 'payment_intent', id: max, status: 'succeeded', amount: 7600 }));
  week.sales.S8 = (await h.database.pool.query('SELECT id FROM sales WHERE payment_intent_id = $1', [max])).rows[0]?.id;
  at('2026-11-06T20:00:00Z');
  expect((await h.call('DELETE', `/api/owner/products/${week.products.oldGel}`, owner)).status).toBe(204);
  at('2026-11-07T00:20:00Z');
  await mark('A11', 'noShow');
  at('2026-11-07T05:45:00Z'); // 9:45 PM PST, still Friday: a walk-in's military cut with Izzy
  await sell('S9', { barberId: 'israel-flores', items: [{ kind: 'service', serviceId: 'military-haircut' }] });

  // Saturday Nov 7
  at('2026-11-07T17:00:00Z');
  await book('A12', OFFERING.cristianHaircut, '2026-11-07T18:00:00Z', 'Oz'); // 10 AM
  await book('A13', OFFERING.izzyHaircut, '2026-11-08T00:00:00Z', 'Pat'); // 4 PM
  await book('A14', OFFERING.carlosHaircut, '2026-11-07T20:00:00Z', 'Quinn'); // noon, never marked
  await book('A15', OFFERING.julianHaircut, '2026-11-07T21:00:00Z', 'Ray'); // 1 PM
  await book('A16', OFFERING.izzyHaircut, '2026-11-08T18:00:00Z', 'Sam'); // Sunday Nov 8, 10 AM
  at('2026-11-07T18:50:00Z');
  await sell('S10', { appointmentId: week.appointments.A12, items: [{ kind: 'service', serviceId: 'haircut' }] });
  at('2026-11-07T19:00:00Z');
  await mark('A15', 'cancelled');

  at(WEEK_NOW);
  return week;
}
