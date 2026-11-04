import Stripe from 'stripe';
import { describe, expect, it } from 'vitest';
import { newManageToken } from '../src/auth.js';
import { RESPONSES } from './helpers/contract.js';
import { connectedShop, connectMode, useHarness, type CallOptions } from './helpers/harness.js';

// Sales and analytics together with the shop's own Stripe account and computer sign-in:
// a computer signed in with a code checks clients out and reads the analytics like the
// Business app (but never takes a card), and a card checkout on the shop's connected account
// is recorded as a sale whether Stripe's Connect webhook or …/complete sees it succeed first.

// Monday Nov 2 2026, 11:10 AM PST.
const h = useHarness({ now: '2026-11-02T19:10:00Z' });
const owner = { owner: true } as const;
const FLOW45 = 'flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a';
const CONNECT_SECRET = 'whsec_fixture_connect';
const FORBIDDEN = { code: 'forbidden', message: 'This can only be done in the Izzy Clipz Business app on your iPhone.' };

/** A computer signed in with a code from the Business app (the website's Business area). */
async function computer(): Promise<Pick<CallOptions, 'headers'>> {
  const code = await h.call('POST', '/api/owner/computer-codes', owner);
  expect(code.status, code.text).toBe(201);
  const signedIn = await h.call('POST', '/api/computer-sessions', { body: { code: code.body.code, name: 'Chrome on Mac' } });
  expect(signedIn.status, signedIn.text).toBe(201);
  return { headers: { authorization: `Bearer ${signedIn.body.token}` } };
}

async function walkIn(auth: CallOptions, start = '2026-11-02T20:00:00Z', name = 'Ben'): Promise<string> {
  const res = await h.call('POST', '/api/owner/appointments', { ...auth, body: { offeringId: FLOW45, start, customer: { name } } });
  expect(res.status, res.text).toBe(201);
  return res.body.appointment.id;
}

async function pomade(auth: CallOptions): Promise<string> {
  const res = await h.call('POST', '/api/owner/products', { ...auth, body: { name: 'Matte pomade', priceCents: 1800 } });
  expect(res.status, res.text).toBe(201);
  return res.body.product.id;
}

const ownerAppointment = async (id: string) =>
  (await h.call('GET', '/api/owner/appointments?date=2026-11-02', owner)).body.appointments.find((a: { id: string }) => a.id === id);
const salesFor = async (paymentId: string) =>
  (await h.database.pool.query('SELECT id, appointment_id, method, total_cents FROM sales WHERE payment_intent_id = $1', [paymentId])).rows;

/** A Stripe event, signed for the platform's Connect endpoint; `account` is the connected account it happened on. */
function connectEvent(type: string, object: Record<string, unknown>, account: string): CallOptions {
  const payload = JSON.stringify({
    id: `evt_fixture_${type.replace(/\W/g, '_')}_${account}`,
    object: 'event',
    api_version: '2026-10-28.endive',
    created: Math.floor(h.now.getTime() / 1000),
    type,
    livemode: false,
    pending_webhooks: 1,
    request: { id: null, idempotency_key: null },
    data: { object },
    account,
  });
  const signature = Stripe.webhooks.generateTestHeaderString({ payload, secret: CONNECT_SECRET });
  return { rawBody: payload, headers: { 'content-type': 'application/json', 'stripe-signature': signature } };
}
const succeededOn = (account: string, id: string) =>
  h.call('POST', '/api/stripe/webhook', connectEvent('payment_intent.succeeded', { object: 'payment_intent', id, status: 'succeeded' }, account));

describe('a computer signed in with a code (the website’s Business area)', () => {
  it('checks a client out with cash, sees it in the day’s sales, the schedule and the analytics, and voids it', async () => {
    const pc = await computer();
    const appointment = await walkIn(pc);
    const product = await pomade(pc);
    expect((await h.call('PATCH', `/api/owner/products/${product}`, { ...pc, body: { visible: false } })).status).toBe(200);
    expect((await h.call('GET', '/api/owner/products', pc)).body.products).toHaveLength(1);

    // The website keeps the checkout's key and sends it again after a lost answer, like the app.
    const key = newManageToken();
    const ticket = { method: 'cash', appointmentId: appointment, items: [{ kind: 'service', serviceId: 'haircut' }, { kind: 'product', productId: product }] };
    const sold = await h.call('POST', '/api/owner/sales', { ...pc, headers: { ...pc.headers, 'idempotency-key': key }, body: ticket });
    expect(sold.status, sold.text).toBe(201);
    expect(RESPONSES['sale-created'].safeParse(sold.body).success).toBe(true);
    expect(sold.body.sale).toMatchObject({ barberId: 'flowxbori', appointmentId: appointment, customerName: 'Ben', method: 'cash', totalCents: 5300 });
    const again = await h.call('POST', '/api/owner/sales', { ...pc, headers: { ...pc.headers, 'idempotency-key': key }, body: ticket });
    expect(again.status, again.text).toBe(200);
    expect(again.body).toEqual(sold.body);

    const day = await h.call('GET', '/api/owner/sales?date=2026-11-02', pc);
    expect(day.status, day.text).toBe(200);
    expect(day.body.totals).toEqual({ totalCents: 5300, count: 1 });
    expect((await h.call('GET', '/api/owner/appointments?date=2026-11-02', pc)).body.appointments[0]).toMatchObject({
      id: appointment,
      status: 'completed',
      payment: { status: 'paid', amountCents: 5300 },
      sale: { id: sold.body.sale.id, totalCents: 5300, method: 'cash' },
    });

    const analytics = await h.call('GET', '/api/owner/analytics?from=2026-11-02&to=2026-11-02', pc);
    expect(analytics.status, analytics.text).toBe(200);
    expect(RESPONSES.analytics.safeParse(analytics.body).success).toBe(true);
    expect(analytics.body.totals).toMatchObject({ salesCents: 5300, servicesCents: 3500, productsCents: 1800, checkouts: 1, clientsServed: 1 });
    expect(analytics.body.topBarber).toMatchObject({ barberId: 'flowxbori', salesCents: 5300 });
    const barber = await h.call('GET', '/api/owner/analytics?from=2026-11-02&to=2026-11-02&barberId=flowxbori', pc);
    expect(barber.status, barber.text).toBe(200);
    expect(barber.body.products).toEqual([{ productId: product, name: 'Matte pomade', quantity: 1, salesCents: 1800 }]);

    const voided = await h.call('POST', `/api/owner/sales/${sold.body.sale.id}/void`, { ...pc, body: { reason: 'Rang up twice' } });
    expect(voided.status, voided.text).toBe(200);
    expect(voided.body.sale).toMatchObject({ voidReason: 'Rang up twice', voidedAt: '2026-11-02T19:10:00Z' });
    expect((await h.call('GET', '/api/owner/sales?date=2026-11-02', pc)).body.totals).toEqual({ totalCents: 0, count: 0 });
    // Voided: the appointment stays done, and is unpaid again until it's checked out again.
    expect(await ownerAppointment(appointment)).toMatchObject({ status: 'completed', payment: { status: 'unpaid' }, sale: null });
  });

  it('manages no-show protection and Stripe from the website, but can’t disconnect it', async () => {
    connectMode(h);
    const pc = await computer();
    expect((await h.call('GET', '/api/owner/no-show-settings', pc)).status).toBe(200);
    const settings = await h.call('PATCH', '/api/owner/no-show-settings', { ...pc, body: { feeMode: 'flat', flatCents: 2500 } });
    expect(settings.status, settings.text).toBe(200);
    expect(settings.body.noShowSettings).toMatchObject({ feeMode: 'flat', flatCents: 2500 });

    const status = await h.call('GET', '/api/owner/stripe', pc);
    expect(status.status, status.text).toBe(200);
    expect(status.body).toMatchObject({ mode: 'connect', status: 'notConnected' });
    const link = await h.call('POST', '/api/owner/stripe/connect', { ...pc, body: { returnTo: 'web' } });
    expect(link.status, link.text).toBe(201);
    expect(RESPONSES['stripe-connect-link'].safeParse(link.body).success).toBe(true);
    const account = [...h.stripe.connectedAccounts.keys()][0]!;

    const disconnect = await h.call('DELETE', '/api/owner/stripe/connect', pc);
    expect(disconnect.status).toBe(403);
    expect(disconnect.body.error).toEqual(FORBIDDEN);
    expect((await h.call('GET', '/api/owner/stripe', pc)).body.accountId).toBe(account);
  });

  it('can’t take a card: Tap to Pay, card checkouts and codes for another computer stay with the owner key', async () => {
    await connectedShop(h);
    const pc = await computer();
    const appointment = await walkIn(pc);
    const sale = { appointmentId: appointment, items: [{ kind: 'service', serviceId: 'haircut' }] };
    const before = h.stripe.calls.length;
    for (const [path, body] of [
      ['/api/owner/payments', { amountCents: 3500, sale }],
      ['/api/owner/terminal/connection-token', undefined],
      ['/api/owner/computer-codes', undefined],
    ] as const) {
      const res = await h.call('POST', path, { ...pc, ...(body ? { body } : {}) });
      expect(res.status, path).toBe(403);
      expect(res.body.error).toEqual(FORBIDDEN);
    }
    expect(h.stripe.calls.slice(before)).toEqual([]);
    expect((await h.database.pool.query('SELECT count(*)::int AS n FROM payments')).rows[0].n).toBe(0);
    expect((await ownerAppointment(appointment)).status).toBe('booked');
  });
});

describe('card sales on the shop’s own Stripe account (Connect)', () => {
  it('Stripe’s Connect webhook from the shop’s account records the card sale once; …/complete then finds it', async () => {
    const account = await connectedShop(h);
    h.config.stripeConnectWebhookSecret = CONNECT_SECRET;
    const appointment = await walkIn(owner);
    const product = await pomade(owner);
    const created = await h.call('POST', '/api/owner/payments', {
      ...owner,
      body: { amountCents: 5300, sale: { appointmentId: appointment, items: [{ kind: 'service', serviceId: 'haircut' }, { kind: 'product', productId: product }] } },
    });
    expect(created.status, created.text).toBe(201);
    const id = created.body.paymentIntentId;
    expect(h.stripe.calls.at(-1)).toMatchObject({ method: 'paymentIntents.create', params: { amount: 5300 }, options: { stripeAccount: account } });
    const stored = (await h.database.pool.query('SELECT stripe_account_id, sale_draft FROM payments WHERE id = $1', [id])).rows[0];
    expect(stored).toMatchObject({ stripe_account_id: account, sale_draft: { barberId: 'flowxbori', appointmentId: appointment, totalCents: 5300 } });

    h.stripe.succeed(id);
    h.advance(1);
    // The same payment reported by another of the platform's connected accounts isn't the shop's: ignored.
    expect((await succeededOn('acct_SomeoneElse01', id)).status).toBe(200);
    expect(await salesFor(id)).toEqual([]);
    expect((await ownerAppointment(appointment)).payment.status).toBe('unpaid');

    const res = await succeededOn(account, id);
    expect(res.status, res.text).toBe(200);
    const [sale] = await salesFor(id);
    expect(sale).toMatchObject({ appointment_id: appointment, method: 'card', total_cents: 5300 });
    expect(await ownerAppointment(appointment)).toMatchObject({
      status: 'completed',
      payment: { status: 'paid', amountCents: 5300 },
      sale: { id: sale.id, totalCents: 5300, method: 'card' },
    });
    // Stripe sends it again, and the app confirms: still one sale, looked up on the shop's account.
    expect((await succeededOn(account, id)).status).toBe(200);
    const done = await h.call('POST', `/api/owner/payments/${id}/complete`, owner);
    expect(done.status, done.text).toBe(200);
    expect(done.body.payment).toMatchObject({ status: 'succeeded', saleId: sale.id });
    expect(h.stripe.calls.at(-1)).toEqual({ method: 'paymentIntents.retrieve', params: id, options: { stripeAccount: account } });
    expect(await salesFor(id)).toHaveLength(1);

    // The website's analytics count it like any other sale.
    const analytics = await h.call('GET', '/api/owner/analytics?from=2026-11-02&to=2026-11-02', await computer());
    expect(analytics.body.totals).toMatchObject({ salesCents: 5300, servicesCents: 3500, productsCents: 1800, checkouts: 1 });
  });

  it('…/complete asks Stripe on the account the payment was made on, even after the shop connected another, and records the sale', async () => {
    const first = await connectedShop(h);
    h.config.stripeConnectWebhookSecret = CONNECT_SECRET;
    const appointment = await walkIn(owner);
    const created = await h.call('POST', '/api/owner/payments', {
      ...owner,
      body: { amountCents: 3500, sale: { appointmentId: appointment, items: [{ kind: 'service', serviceId: 'haircut' }] } },
    });
    expect(created.status, created.text).toBe(201);
    const id = created.body.paymentIntentId;

    expect((await h.call('DELETE', '/api/owner/stripe/connect', owner)).status).toBe(200);
    const second = await connectedShop(h);
    expect(second).not.toBe(first);

    h.stripe.succeed(id);
    h.advance(2);
    const done = await h.call('POST', `/api/owner/payments/${id}/complete`, owner);
    expect(done.status, done.text).toBe(200);
    expect(h.stripe.calls.at(-1)).toEqual({ method: 'paymentIntents.retrieve', params: id, options: { stripeAccount: first } });
    const saleId = done.body.payment.saleId;
    expect(saleId).toMatch(/^[0-9a-f-]{36}$/);
    const day = await h.call('GET', '/api/owner/sales?date=2026-11-02', owner);
    expect(day.body.sales).toEqual([
      // Sold when the card went through, two minutes before the app confirmed it.
      expect.objectContaining({ id: saleId, method: 'card', paymentIntentId: id, appointmentId: appointment, totalCents: 3500, soldAt: '2026-11-02T19:10:00Z' }),
    ]);
    // The earlier account's webhook arrives late: nothing more is recorded.
    expect((await succeededOn(first, id)).status).toBe(200);
    expect(await salesFor(id)).toHaveLength(1);
  });

  it('until the shop’s account can take cards, a card checkout is turned down like Stripe being off, and cash still works', async () => {
    connectMode(h);
    const appointment = await walkIn(owner);
    const card = await h.call('POST', '/api/owner/payments', {
      ...owner,
      body: { amountCents: 3500, sale: { appointmentId: appointment, items: [{ kind: 'service', serviceId: 'haircut' }] } },
    });
    expect(card.status).toBe(503);
    expect(card.body.error.code).toBe('stripe_not_configured');
    expect(h.stripe.calls.filter((c) => c.method.startsWith('paymentIntents'))).toEqual([]);
    const cash = await h.call('POST', '/api/owner/sales', { ...owner, body: { method: 'cash', appointmentId: appointment, items: [{ kind: 'service', serviceId: 'haircut' }] } });
    expect(cash.status, cash.text).toBe(201);
  });
});
