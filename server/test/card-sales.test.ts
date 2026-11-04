import { describe, expect, it } from 'vitest';
import { RESPONSES } from './helpers/contract.js';
import { useHarness } from './helpers/harness.js';
import { sendWebhook, WEBHOOK_SECRET } from './helpers/week.js';

// Card sales: a checkout's ticket sent with POST /api/owner/payments (`sale`), kept with the
// payment, and recorded as a sale exactly once when the payment succeeds, whichever of
// …/complete and Stripe's webhook says so first (or both at once).

// Monday Nov 2 2026, 11:10 AM PST.
const h = useHarness({ now: '2026-11-02T19:10:00Z' });
const owner = { owner: true } as const;
const FLOW45 = 'flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a';

function configureStripe() {
  h.config.stripeSecretKey = 'sk_test_fixture';
  h.config.stripeTerminalLocationId = 'tml_FixtureLocation';
  h.config.stripeWebhookSecret = WEBHOOK_SECRET;
}

async function walkIn(start = '2026-11-02T20:00:00Z', name = 'Ben') {
  const res = await h.call('POST', '/api/owner/appointments', { ...owner, body: { offeringId: FLOW45, start, customer: { name } } });
  expect(res.status, res.text).toBe(201);
  return res.body.appointment.id as string;
}

async function pomade() {
  return (await h.call('POST', '/api/owner/products', { ...owner, body: { name: 'Matte pomade', priceCents: 1800 } })).body.product.id as string;
}

const pay = (body: Record<string, unknown>) => h.call('POST', '/api/owner/payments', { ...owner, body });
const complete = (id: string) => h.call('POST', `/api/owner/payments/${id}/complete`, owner);
const succeeded = (id: string) => sendWebhook(h, 'payment_intent.succeeded', { object: 'payment_intent', id, status: 'succeeded', amount: 5300 });
const salesFor = async (paymentId: string) =>
  (await h.database.pool.query('SELECT id, appointment_id, sold_at, method, total_cents FROM sales WHERE payment_intent_id = $1', [paymentId])).rows;
const ownerAppointment = async (id: string) =>
  (await h.call('GET', '/api/owner/appointments?date=2026-11-02', owner)).body.appointments.find((a: { id: string }) => a.id === id);

/** A $53 ticket for Ben's noon haircut: the haircut at its booked $35 and a pomade. */
async function ticket() {
  const appointment = await walkIn();
  const product = await pomade();
  return {
    appointment,
    product,
    sale: { appointmentId: appointment, items: [{ kind: 'service', serviceId: 'haircut' }, { kind: 'product', productId: product }] },
  };
}

describe('a card checkout', () => {
  it('keeps the ticket with the payment, and records the sale once …/complete sees it succeeded', async () => {
    configureStripe();
    const { appointment, product, sale } = await ticket();
    const created = await pay({ amountCents: 5300, sale });
    expect(created.status, created.text).toBe(201);
    expect(RESPONSES['payment-created-with-sale'].safeParse(created.body).success).toBe(true);
    const id = created.body.paymentIntentId;
    // The PaymentIntent is the same as without a ticket, and knows its appointment.
    const params = h.stripe.calls.find((c) => c.method === 'paymentIntents.create')?.params;
    expect(params).toEqual({
      amount: 5300,
      currency: 'usd',
      allowed_payment_method_types: ['card_present'],
      capture_method: 'automatic',
      metadata: { source: 'izzy-clipz-business', appointment_id: appointment },
    });
    const stored = (await h.database.pool.query('SELECT appointment_id, sale_draft FROM payments WHERE id = $1', [id])).rows[0];
    expect(stored).toEqual({
      appointment_id: appointment,
      sale_draft: {
        barberId: 'flowxbori',
        appointmentId: appointment,
        customerName: 'Ben',
        items: [
          { kind: 'service', serviceId: 'haircut', productId: null, name: 'Haircut', quantity: 1, unitCents: 3500, totalCents: 3500 },
          { kind: 'product', serviceId: null, productId: product, name: 'Matte pomade', quantity: 1, unitCents: 1800, totalCents: 1800 },
        ],
        totalCents: 5300,
      },
    });

    // Not paid yet: no sale.
    const early = await complete(id);
    expect(early.body.payment).toMatchObject({ status: 'requires_payment_method', saleId: null });
    expect(await salesFor(id)).toEqual([]);
    expect((await ownerAppointment(appointment)).sale).toBeNull();

    h.stripe.succeed(id);
    h.advance(2);
    const done = await complete(id);
    expect(done.status).toBe(200);
    expect(RESPONSES['payment-completed-with-sale'].safeParse(done.body).success).toBe(true);
    const saleId = done.body.payment.saleId;
    expect(saleId).toMatch(/^[0-9a-f-]{36}$/);
    const day = await h.call('GET', '/api/owner/sales?date=2026-11-02', owner);
    expect(day.body.sales).toEqual([
      {
        id: saleId,
        barberId: 'flowxbori',
        barberName: 'Flowxbori',
        appointmentId: appointment,
        customerName: 'Ben',
        method: 'card',
        paymentIntentId: id,
        totalCents: 5300,
        items: [
          { kind: 'service', serviceId: 'haircut', productId: null, name: 'Haircut', quantity: 1, unitCents: 3500, totalCents: 3500 },
          { kind: 'product', serviceId: null, productId: product, name: 'Matte pomade', quantity: 1, unitCents: 1800, totalCents: 1800 },
        ],
        soldAt: '2026-11-02T19:12:00Z',
        voidedAt: null,
        voidReason: null,
      },
    ]);
    // The appointment is completed and paid by the card, with its sale.
    expect(await ownerAppointment(appointment)).toMatchObject({
      status: 'completed',
      payment: { status: 'paid', amountCents: 5300, paidAt: '2026-11-02T19:12:00Z' },
      sale: { id: saleId, totalCents: 5300, method: 'card' },
    });
    // Asking again, and Stripe's webhook later, record nothing more.
    h.advance(1);
    expect((await complete(id)).body.payment.saleId).toBe(saleId);
    expect((await succeeded(id)).status).toBe(200);
    expect(await salesFor(id)).toHaveLength(1);
    // Payments today shows which sale it recorded.
    const payments = await h.call('GET', '/api/owner/payments?date=2026-11-02', owner);
    expect(payments.body.payments).toEqual([expect.objectContaining({ id, status: 'succeeded', saleId })]);
  });

  it('records it from Stripe’s webhook when the app never confirms, once, and …/complete then finds it', async () => {
    configureStripe();
    const { appointment, sale } = await ticket();
    const id = (await pay({ amountCents: 5300, sale })).body.paymentIntentId;
    h.stripe.succeed(id);
    h.advance(1);
    expect((await succeeded(id)).status).toBe(200);
    const [recorded] = await salesFor(id);
    expect(recorded).toMatchObject({ appointment_id: appointment, method: 'card', total_cents: 5300, sold_at: new Date('2026-11-02T19:11:00Z') });
    // Stripe may deliver the event again.
    h.advance(5);
    await succeeded(id);
    const later = await complete(id);
    expect(later.body.payment).toMatchObject({ status: 'succeeded', saleId: recorded.id });
    expect(await salesFor(id)).toHaveLength(1);
  });

  it('…/complete and the webhook at the same moment record one sale', async () => {
    configureStripe();
    const { sale } = await ticket();
    const id = (await pay({ amountCents: 5300, sale })).body.paymentIntentId;
    h.stripe.succeed(id);
    const [completed, hook, again] = await Promise.all([complete(id), succeeded(id), complete(id)]);
    expect([completed.status, hook.status, again.status]).toEqual([200, 200, 200]);
    const rows = await salesFor(id);
    expect(rows).toHaveLength(1);
    expect(completed.body.payment.saleId).toBe(rows[0].id);
    expect(again.body.payment.saleId).toBe(rows[0].id);
  });

  it('the amount must be the ticket’s total, and nothing reaches Stripe otherwise', async () => {
    configureStripe();
    const { sale } = await ticket();
    const res = await pay({ amountCents: 5000, sale });
    expect(res.status).toBe(400);
    expect(res.body.error).toEqual({ code: 'amount_mismatch', message: "The amount doesn't match the items." });
    expect(h.stripe.calls.filter((c) => c.method === 'paymentIntents.create')).toEqual([]);
    // The card limits still apply to the amount.
    const free = await pay({ amountCents: 0, sale: { barberId: 'carlos-rafael', items: [{ kind: 'service', serviceId: 'eyebrows' }] } });
    expect(free.status).toBe(400);
    expect(free.body.error.code).toBe('invalid_request');
  });

  it('checks the ticket like a cash sale: the appointment, the barber, the items', async () => {
    configureStripe();
    const { appointment, sale } = await ticket();
    expect((await pay({ amountCents: 5300, appointmentId: appointment, sale })).status).toBe(201);
    // A top-level appointmentId stands for the ticket's when it names none, and must agree when it does.
    const other = await walkIn('2026-11-02T22:00:00Z', 'Cy');
    const inherited = await pay({ amountCents: 3500, appointmentId: other, sale: { items: [{ kind: 'service', serviceId: 'haircut' }] } });
    expect(inherited.status, inherited.text).toBe(201);
    const draft = (await h.database.pool.query('SELECT appointment_id, sale_draft FROM payments WHERE id = $1', [inherited.body.paymentIntentId])).rows[0];
    expect(draft).toMatchObject({ appointment_id: other, sale_draft: { appointmentId: other, barberId: 'flowxbori', customerName: 'Cy' } });
    const disagree = await pay({ amountCents: 5300, appointmentId: other, sale });
    expect(disagree.body.error).toEqual({ code: 'invalid_request', message: "The appointment doesn't match the sale's appointment." });
    expect((await pay({ amountCents: 5300, appointmentId: other, sale: { ...sale, appointmentId: null } })).status).toBe(400);
    // The same rules as cash.
    const cancelled = await walkIn('2026-11-02T23:00:00Z', 'Dee');
    await h.call('PATCH', `/api/owner/appointments/${cancelled}`, { ...owner, body: { status: 'cancelled' } });
    expect((await pay({ amountCents: 3500, sale: { appointmentId: cancelled, items: [{ kind: 'service', serviceId: 'haircut' }] } })).body.error.code).toBe(
      'not_checkoutable',
    );
    await h.call('POST', '/api/owner/sales', { ...owner, body: { method: 'cash', appointmentId: other, items: [{ kind: 'service', serviceId: 'haircut' }] } });
    const taken = await pay({ amountCents: 3500, sale: { appointmentId: other, items: [{ kind: 'service', serviceId: 'haircut' }] } });
    expect(taken.status).toBe(409);
    expect(taken.body.error).toEqual({ code: 'already_checked_out', message: 'This appointment was already checked out.' });
    expect((await pay({ amountCents: 3500, sale: { items: [{ kind: 'service', serviceId: 'haircut' }] } })).body.error.message).toBe(
      'Pick the barber who gets credit for this sale.',
    );
    expect((await pay({ amountCents: 3500, sale: { barberId: 'flowxbori', items: [] } })).body.error.message).toBe('Add at least one item.');
    expect((await pay({ amountCents: 3500, sale: 'haircut' })).body.error.message).toBe('sale must be the ticket: the barber and the items.');
    // Without Stripe set up, it's the usual 503 before anything else.
    h.config.stripeSecretKey = undefined;
    expect((await pay({ amountCents: 5300, sale })).body.error.code).toBe('stripe_not_configured');
  });

  it('an appointment checked out meanwhile: the card sale is recorded without it (the money still counts), and logged', async () => {
    configureStripe();
    const { appointment, sale } = await ticket();
    const id = (await pay({ amountCents: 5300, sale })).body.paymentIntentId;
    // While the card is being tapped, someone records a cash sale for the same appointment.
    const cash = await h.call('POST', '/api/owner/sales', { ...owner, body: { method: 'cash', appointmentId: appointment, items: [{ kind: 'service', serviceId: 'haircut' }] } });
    expect(cash.status).toBe(201);
    h.stripe.succeed(id);
    const done = await complete(id);
    const [card] = await salesFor(id);
    expect(card).toMatchObject({ id: done.body.payment.saleId, appointment_id: null, method: 'card', total_cents: 5300 });
    expect(h.logs).toContainEqual({
      level: 'warn',
      message: 'A card sale was recorded without its appointment, which was already checked out, cancelled or a no-show',
      details: { paymentId: id, appointmentId: appointment, status: 'completed', liveSaleId: cash.body.sale.id },
    });
    // The appointment keeps its cash checkout and what it paid; the card payment lets go of it,
    // now and when Stripe's webhook comes in.
    expect(done.body.payment.appointmentId).toBeNull();
    await succeeded(id);
    expect(await ownerAppointment(appointment)).toMatchObject({
      sale: { id: cash.body.sale.id, method: 'cash', totalCents: 3500 },
      payment: { status: 'paid', amountCents: 3500 },
    });
    // Both count in the day's sales, and voiding the cash one leaves the appointment unpaid.
    expect((await h.call('GET', '/api/owner/sales?date=2026-11-02', owner)).body.totals).toEqual({ totalCents: 3500 + 5300, count: 2 });
    await h.call('POST', `/api/owner/sales/${cash.body.sale.id}/void`, { ...owner, body: {} });
    expect((await ownerAppointment(appointment)).payment).toEqual({ status: 'unpaid', amountCents: null, paidAt: null });
  });

  it('an appointment cancelled meanwhile: recorded without it too', async () => {
    configureStripe();
    const { appointment, sale } = await ticket();
    const id = (await pay({ amountCents: 5300, sale })).body.paymentIntentId;
    await h.call('PATCH', `/api/owner/appointments/${appointment}`, { ...owner, body: { status: 'cancelled' } });
    h.stripe.succeed(id);
    await complete(id);
    expect(await salesFor(id)).toEqual([expect.objectContaining({ appointment_id: null, total_cents: 5300 })]);
    expect(await ownerAppointment(appointment)).toMatchObject({ status: 'cancelled', payment: { status: 'unpaid' }, sale: null });
  });

  it('a client’s name counts in characters, as at checkout: 60 emoji are fine all the way through', async () => {
    configureStripe();
    const name = '💈'.repeat(60);
    const { sale } = await ticket();
    const created = await pay({ amountCents: 5300, sale: { ...sale, customerName: name } });
    expect(created.status, created.text).toBe(201);
    h.stripe.succeed(created.body.paymentIntentId);
    expect((await complete(created.body.paymentIntentId)).body.payment.saleId).not.toBeNull();
    const day = await h.call('GET', '/api/owner/sales?date=2026-11-02', owner);
    expect(day.body.sales[0].customerName).toBe(name);
    expect((await pay({ amountCents: 5300, sale: { ...sale, appointmentId: null, barberId: 'flowxbori', customerName: `${name}💈` } })).status).toBe(400);
  });

  it('voiding a card sale doesn’t refund it: the message says where refunds are made', async () => {
    configureStripe();
    const { appointment, sale } = await ticket();
    const id = (await pay({ amountCents: 5300, sale })).body.paymentIntentId;
    h.stripe.succeed(id);
    const saleId = (await complete(id)).body.payment.saleId;
    const voided = await h.call('POST', `/api/owner/sales/${saleId}/void`, { ...owner, body: { reason: 'Wrong client' } });
    expect(voided.status).toBe(200);
    expect(voided.body.message).toBe(
      "The sale was voided, so it no longer counts in your sales. Voiding doesn't refund the card: refunds are made in the Stripe Dashboard.",
    );
    expect(h.stripe.calls.map((c) => c.method)).toEqual(['paymentIntents.create', 'paymentIntents.retrieve']);
    // The card still paid the appointment, which can be checked out again (the card's numbers stay).
    expect(await ownerAppointment(appointment)).toMatchObject({ status: 'completed', payment: { status: 'paid', amountCents: 5300 }, sale: null });
    const redo = await h.call('POST', '/api/owner/sales', { ...owner, body: { method: 'cash', appointmentId: appointment, items: [{ kind: 'service', serviceId: 'haircut' }] } });
    expect(redo.status).toBe(201);
    expect((await ownerAppointment(appointment)).payment).toMatchObject({ status: 'paid', amountCents: 5300 });
    // The payment still points at its (voided) sale.
    expect((await complete(id)).body.payment.saleId).toBe(saleId);
  });

  it('a product deleted before the card goes through is recorded by name', async () => {
    configureStripe();
    const { product, sale } = await ticket();
    const id = (await pay({ amountCents: 5300, sale })).body.paymentIntentId;
    await h.call('DELETE', `/api/owner/products/${product}`, owner);
    h.stripe.succeed(id);
    const saleId = (await complete(id)).body.payment.saleId;
    const day = await h.call('GET', '/api/owner/sales?date=2026-11-02', owner);
    expect(day.body.sales.find((s: { id: string }) => s.id === saleId).items[1]).toEqual({
      kind: 'product',
      serviceId: null,
      productId: null,
      name: 'Matte pomade',
      quantity: 1,
      unitCents: 1800,
      totalCents: 1800,
    });
  });

  it('a ticket the server can’t read is logged, and the payment is still recorded as paid', async () => {
    configureStripe();
    const { sale } = await ticket();
    const id = (await pay({ amountCents: 5300, sale })).body.paymentIntentId;
    await h.database.pool.query(`UPDATE payments SET sale_draft = '{"items": "haircut"}' WHERE id = $1`, [id]);
    h.stripe.succeed(id);
    const done = await complete(id);
    expect(done.body.payment).toMatchObject({ status: 'succeeded', saleId: null });
    expect(h.logs).toContainEqual(expect.objectContaining({ level: 'error', message: "A card sale couldn't be recorded: its ticket is unreadable" }));
    expect(await salesFor(id)).toEqual([]);
  });

  it('a payment without a ticket works as before and records no sale', async () => {
    configureStripe();
    const appointment = await walkIn();
    const id = (await pay({ amountCents: 3500, appointmentId: appointment })).body.paymentIntentId;
    h.stripe.succeed(id);
    const done = await complete(id);
    expect(done.body.payment).toMatchObject({ status: 'succeeded', saleId: null });
    expect(await ownerAppointment(appointment)).toMatchObject({ status: 'booked', payment: { status: 'paid', amountCents: 3500 }, sale: null });
    expect((await h.database.pool.query('SELECT count(*)::int AS n FROM sales')).rows[0].n).toBe(0);
  });
});
