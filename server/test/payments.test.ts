import Stripe from 'stripe';
import { describe, expect, it } from 'vitest';
import { useHarness } from './helpers/harness.js';

const h = useHarness({ now: '2026-11-02T19:10:00Z' });

const STRIPE_KEY = 'sk_test_fixture';
const WEBHOOK_SECRET = 'whsec_fixture_webhook_secret';
const FLOW45 = 'flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a';

function configureStripe() {
  h.config.stripeSecretKey = STRIPE_KEY;
  h.config.stripeTerminalLocationId = 'tml_FixtureLocation';
  h.config.stripeWebhookSecret = WEBHOOK_SECRET;
}

async function walkIn(start = '2026-11-02T20:00:00Z') {
  const res = await h.call('POST', '/api/owner/appointments', {
    owner: true,
    body: { offeringId: FLOW45, start, customer: { name: 'Walk-in' } },
  });
  return res.body.appointment;
}

const pay = (body: unknown) => h.call('POST', '/api/owner/payments', { owner: true, body });

describe('without Stripe configured', () => {
  it('payment endpoints answer 503 stripe_not_configured and never build a client', async () => {
    for (const [method, path, body] of [
      ['POST', '/api/owner/terminal/connection-token', undefined],
      ['POST', '/api/owner/payments', { amountCents: 3500 }],
      ['POST', '/api/owner/payments/pi_123/complete', undefined],
    ] as const) {
      const res = await h.call(method, path, { owner: true, ...(body ? { body } : {}) });
      expect(res.status, path).toBe(503);
      expect(res.body.error).toEqual({
        code: 'stripe_not_configured',
        message: "Card payments aren't set up yet. Add the shop's Stripe key on the server.",
      });
    }
    expect(h.stripe.keys).toEqual([]);
    // The day's list still works (empty).
    expect((await h.call('GET', '/api/owner/payments?date=2026-11-02', { owner: true })).body).toEqual({ payments: [] });
  });
});

describe('with Stripe configured', () => {
  it('creates a connection token for the Terminal SDK', async () => {
    configureStripe();
    const res = await h.call('POST', '/api/owner/terminal/connection-token', { owner: true });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ secret: 'pst_test_YWNjdF8xRml4dHVyZUNvbm5lY3Rpb25Ub2tlbg' });
    expect(h.stripe.keys).toEqual([STRIPE_KEY]);
    expect(h.stripe.calls[0]).toEqual({ method: 'terminal.connectionTokens.create', params: { location: 'tml_FixtureLocation' } });
  });

  it('creates a card_present PaymentIntent with allowed_payment_method_types and automatic capture', async () => {
    configureStripe();
    const appointment = await walkIn();
    const res = await pay({ amountCents: 3500, description: ' Haircut ', appointmentId: appointment.id, receiptEmail: 'client@example.com' });
    expect(res.status).toBe(201);
    expect(res.body).toEqual({ paymentIntentId: 'pi_3TestFixture000001', clientSecret: 'pi_3TestFixture000001_secret_FixtureClientSecret' });
    const params = h.stripe.calls.find((c) => c.method === 'paymentIntents.create')!.params as Record<string, unknown>;
    expect(params).toEqual({
      amount: 3500,
      currency: 'usd',
      allowed_payment_method_types: ['card_present'],
      capture_method: 'automatic',
      description: 'Haircut',
      receipt_email: 'client@example.com',
      metadata: { source: 'izzy-clipz-business', appointment_id: appointment.id },
    });
    expect(params).not.toHaveProperty('payment_method_types');
    const list = await h.call('GET', '/api/owner/payments?date=2026-11-02', { owner: true });
    expect(list.body.payments).toEqual([
      {
        id: 'pi_3TestFixture000001',
        amountCents: 3500,
        description: 'Haircut',
        appointmentId: appointment.id,
        status: 'requires_payment_method',
        createdAt: '2026-11-02T19:10:00Z',
      },
    ]);
  });

  it('validates the amount and the appointment', async () => {
    configureStripe();
    for (const amountCents of [49, 100_001, 12.5, '3500', null, undefined]) {
      const res = await pay({ amountCents });
      expect(res.status, String(amountCents)).toBe(400);
    }
    expect((await pay({ amountCents: 50 })).status).toBe(201);
    expect((await pay({ amountCents: 100_000 })).status).toBe(201);
    expect((await pay({ amountCents: 500, receiptEmail: 'nope' })).status).toBe(400);
    expect((await pay({ amountCents: 500, description: 'd'.repeat(201) })).status).toBe(400);
    expect((await pay({ amountCents: 500, appointmentId: '00000000-0000-4000-8000-0000000000aa' })).status).toBe(404);
    expect((await pay({ amountCents: 500, appointmentId: 'nope' })).status).toBe(404);
  });

  it('complete: reports Stripe’s status, and marks the appointment paid only once it succeeded', async () => {
    configureStripe();
    const appointment = await walkIn();
    const { paymentIntentId } = (await pay({ amountCents: 3500, appointmentId: appointment.id })).body;
    const complete = () => h.call('POST', `/api/owner/payments/${paymentIntentId}/complete`, { owner: true });

    const early = await complete();
    expect(early.status).toBe(200);
    expect(early.body.payment.status).toBe('requires_payment_method');
    const unpaid = await h.call('GET', '/api/owner/appointments?date=2026-11-02', { owner: true });
    expect(unpaid.body.appointments[0].payment).toEqual({ status: 'unpaid', amountCents: null, paidAt: null });

    h.stripe.succeed(paymentIntentId);
    h.advance(3);
    const done = await complete();
    expect(done.body).toEqual({
      payment: {
        id: paymentIntentId,
        amountCents: 3500,
        description: null,
        appointmentId: appointment.id,
        status: 'succeeded',
        createdAt: '2026-11-02T19:10:00Z',
      },
    });
    const paid = await h.call('GET', '/api/owner/appointments?date=2026-11-02', { owner: true });
    expect(paid.body.appointments[0].payment).toEqual({ status: 'paid', amountCents: 3500, paidAt: '2026-11-02T19:13:00Z' });

    // Calling again changes nothing.
    h.advance(10);
    await complete();
    const again = await h.call('GET', '/api/owner/appointments?date=2026-11-02', { owner: true });
    expect(again.body.appointments[0].payment).toEqual({ status: 'paid', amountCents: 3500, paidAt: '2026-11-02T19:13:00Z' });
  });

  it('adds up two payments for one appointment', async () => {
    configureStripe();
    const appointment = await walkIn();
    for (const amountCents of [3500, 700]) {
      const { paymentIntentId } = (await pay({ amountCents, appointmentId: appointment.id })).body;
      h.stripe.succeed(paymentIntentId);
      await h.call('POST', `/api/owner/payments/${paymentIntentId}/complete`, { owner: true });
    }
    const list = await h.call('GET', '/api/owner/appointments?date=2026-11-02', { owner: true });
    expect(list.body.appointments[0].payment.amountCents).toBe(4200);
  });

  it('complete: 404 for unknown or foreign payments; a Stripe outage is a plain 500', async () => {
    configureStripe();
    expect((await h.call('POST', '/api/owner/payments/pi_unknown/complete', { owner: true })).status).toBe(404);
    expect((await h.call('POST', '/api/owner/payments/not-a-pi/complete', { owner: true })).status).toBe(404);
    const { paymentIntentId } = (await pay({ amountCents: 900 })).body;
    h.stripe.nextError = Object.assign(new Error('socket hang up'), { type: 'StripeConnectionError' });
    const outage = await h.call('POST', `/api/owner/payments/${paymentIntentId}/complete`, { owner: true });
    expect(outage.status).toBe(500);
    expect(outage.body.error).toEqual({ code: 'server_error', message: "We couldn't reach Stripe. Please try again." });
    h.stripe.intents.delete(paymentIntentId);
    expect((await h.call('POST', `/api/owner/payments/${paymentIntentId}/complete`, { owner: true })).status).toBe(404);
    h.stripe.nextError = Object.assign(new Error('Invalid API Key provided'), { type: 'StripeAuthenticationError', statusCode: 401 });
    const badKey = await pay({ amountCents: 900 });
    expect(badKey.status).toBe(500);
    expect(badKey.body.error).toEqual({
      code: 'server_error',
      message: "Stripe didn't accept the server's Stripe key. Check STRIPE_SECRET_KEY on the server.",
    });
    expect(h.logs.some((l) => l.level === 'error' && l.message.startsWith('Stripe'))).toBe(true);
  });

  it('a payment Stripe doesn’t have is a 404, and is logged', async () => {
    configureStripe();
    const { paymentIntentId } = (await pay({ amountCents: 900 })).body;
    h.stripe.intents.delete(paymentIntentId);
    const res = await h.call('POST', `/api/owner/payments/${paymentIntentId}/complete`, { owner: true });
    expect(res.status).toBe(404);
    expect(res.body.error).toEqual({ code: 'not_found', message: "Stripe doesn't know that payment." });
    expect(h.logs).toEqual([
      {
        level: 'error',
        message: 'Stripe retrieve payment failed',
        details: {
          type: 'StripeInvalidRequestError',
          code: 'resource_missing',
          param: undefined,
          status: 404,
          requestId: undefined,
          message: `No such payment_intent: '${paymentIntentId}'`,
        },
      },
    ]);
  });

  it('a Terminal location Stripe turns down says so, and is logged without the key', async () => {
    // Going live with the test-mode location still set: Stripe answers the token with a 400.
    configureStripe();
    h.config.stripeSecretKey = 'sk_live_fixture';
    h.config.stripeTerminalLocationId = 'tml_TestModeLocation';
    const locationMessage =
      "Stripe didn't accept the Terminal location set on the server. Check STRIPE_TERMINAL_LOCATION_ID: it must be a location from the same Stripe account and mode (test or live) as the key.";
    const failures = [
      { type: 'StripeInvalidRequestError', code: 'resource_missing', param: 'location', statusCode: 400, requestId: 'req_fixture' },
      { type: 'StripeInvalidRequestError', code: 'resource_missing', statusCode: 404 },
      { type: 'StripeInvalidRequestError', code: 'parameter_invalid_string', param: 'location', statusCode: 400 },
    ];
    for (const failure of failures) {
      h.stripe.nextError = Object.assign(new Error("No such location: 'tml_TestModeLocation' (key sk_live_fixture)"), failure);
      const res = await h.call('POST', '/api/owner/terminal/connection-token', { owner: true });
      expect(res.status, JSON.stringify(failure)).toBe(500);
      expect(res.body.error).toEqual({ code: 'server_error', message: locationMessage });
    }
    expect(h.logs).toHaveLength(3);
    expect(h.logs[0]).toEqual({
      level: 'error',
      message: 'Stripe connection token failed',
      details: {
        type: 'StripeInvalidRequestError',
        code: 'resource_missing',
        param: 'location',
        status: 400,
        requestId: 'req_fixture',
        message: "No such location: 'tml_TestModeLocation' (key sk_live_…)",
      },
    });
    expect(JSON.stringify(h.logs)).not.toContain('sk_live_fixture');
    // Not "Stripe doesn't know that payment": nothing here is about a payment.
    expect(JSON.stringify(h.logs)).not.toContain('payment');

    // A Stripe outage while making the token still says to try again.
    h.stripe.nextError = Object.assign(new Error('socket hang up'), { type: 'StripeConnectionError' });
    const outage = await h.call('POST', '/api/owner/terminal/connection-token', { owner: true });
    expect(outage.body.error).toEqual({ code: 'server_error', message: "We couldn't reach Stripe. Please try again." });
  });

  it('lists payments for a shop-local day, newest first', async () => {
    configureStripe();
    await pay({ amountCents: 1000 });
    h.advance(60);
    await pay({ amountCents: 2000 });
    h.setNow('2026-11-03T07:59:00Z'); // still Nov 2, 11:59 PM PST
    await pay({ amountCents: 3000 });
    h.setNow('2026-11-03T08:00:00Z'); // Nov 3
    await pay({ amountCents: 4000 });
    const nov2 = await h.call('GET', '/api/owner/payments?date=2026-11-02', { owner: true });
    expect(nov2.body.payments.map((p: { amountCents: number }) => p.amountCents)).toEqual([3000, 2000, 1000]);
    const today = await h.call('GET', '/api/owner/payments', { owner: true });
    expect(today.body.payments.map((p: { amountCents: number }) => p.amountCents)).toEqual([4000]);
  });
});

describe('POST /api/stripe/webhook', () => {
  function event(type: string, intent: Record<string, unknown>) {
    return JSON.stringify({
      id: 'evt_fixture_1',
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
  const send = (payload: string, signature?: string) =>
    h.call('POST', '/api/stripe/webhook', {
      rawBody: payload,
      headers: { 'content-type': 'application/json', ...(signature ? { 'stripe-signature': signature } : {}) },
    });
  const sign = (payload: string, secret = WEBHOOK_SECRET) => Stripe.webhooks.generateTestHeaderString({ payload, secret });

  it('503 without STRIPE_WEBHOOK_SECRET; 400 without or with a bad signature', async () => {
    const payload = event('payment_intent.succeeded', { id: 'pi_x', status: 'succeeded' });
    expect((await send(payload, sign(payload))).status).toBe(503);
    configureStripe();
    expect((await send(payload)).status).toBe(400);
    const bad = await send(payload, sign(payload, 'whsec_someone_else'));
    expect(bad.status).toBe(400);
    expect(bad.body.error.message).toBe("The webhook signature doesn't match.");
    const tampered = await send(payload.replace('succeeded', 'canceled'), sign(payload));
    expect(tampered.status).toBe(400);
    const stale = Stripe.webhooks.generateTestHeaderString({ payload, secret: WEBHOOK_SECRET, timestamp: Math.floor(Date.now() / 1000) - 3600 });
    expect((await send(payload, stale)).status).toBe(400);
  });

  it('a signed payment_intent.succeeded marks the payment and appointment paid, and later events cannot undo it', async () => {
    configureStripe();
    const appointment = await walkIn();
    const { paymentIntentId } = (await pay({ amountCents: 3500, appointmentId: appointment.id })).body;
    const succeeded = event('payment_intent.succeeded', { id: paymentIntentId, status: 'succeeded', amount: 3500 });
    const res = await send(succeeded, sign(succeeded));
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ received: true });
    const list = await h.call('GET', '/api/owner/appointments?date=2026-11-02', { owner: true });
    expect(list.body.appointments[0].payment).toMatchObject({ status: 'paid', amountCents: 3500 });

    const late = event('payment_intent.processing', { id: paymentIntentId, status: 'processing' });
    expect((await send(late, sign(late))).status).toBe(200);
    const payments = await h.call('GET', '/api/owner/payments?date=2026-11-02', { owner: true });
    expect(payments.body.payments[0].status).toBe('succeeded');
  });

  it('records failures and ignores events it does not handle or payments it does not know', async () => {
    configureStripe();
    const { paymentIntentId } = (await pay({ amountCents: 1200 })).body;
    const failed = event('payment_intent.payment_failed', { id: paymentIntentId, status: 'requires_payment_method' });
    expect((await send(failed, sign(failed))).status).toBe(200);
    const canceled = event('payment_intent.canceled', { id: paymentIntentId, status: 'canceled' });
    await send(canceled, sign(canceled));
    expect((await h.call('GET', '/api/owner/payments', { owner: true })).body.payments[0].status).toBe('canceled');
    for (const payload of [
      event('charge.refunded', { id: paymentIntentId, status: 'succeeded' }),
      event('payment_intent.succeeded', { id: 'pi_not_ours', status: 'succeeded' }),
    ]) {
      expect((await send(payload, sign(payload))).status).toBe(200);
    }
    expect((await h.call('GET', '/api/owner/payments', { owner: true })).body.payments[0].status).toBe('canceled');
  });
});

describe('GET /api/owner/me', () => {
  it('reports Stripe as not configured, with no location', async () => {
    const res = await h.call('GET', '/api/owner/me', { owner: true });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ ok: true, stripe: { configured: false, mode: null, locationId: null } });
  });

  it('gives the app the Terminal location it needs to connect Tap to Pay', async () => {
    configureStripe();
    const res = await h.call('GET', '/api/owner/me', { owner: true });
    expect(res.status).toBe(200);
    expect(res.body.stripe).toEqual({ configured: true, mode: 'test', locationId: 'tml_FixtureLocation' });
  });
});
