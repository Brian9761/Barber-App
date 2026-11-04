import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import type { z } from 'zod';
import { createApp } from '../src/app.js';
import { ErrorBody, RESPONSES, type ResponseName } from './helpers/contract.js';
import { protectionOn, useHarness, type CallResult } from './helpers/harness.js';

// Writes one example per §5 response type to test/fixtures/contract/, produced
// by the real handlers, after checking it against strict schemas. The Swift Kit
// decodes these same files. Run with UPDATE_CONTRACT_FIXTURES=1 to rewrite them;
// otherwise the test fails if a handler's output drifts from the committed files.

const DIR = new URL('./fixtures/contract/', import.meta.url);
const UPDATE = process.env.UPDATE_CONTRACT_FIXTURES === '1';

function record(path: string, body: unknown): void {
  const file = new URL(path, DIR);
  const text = `${JSON.stringify(body, null, 2)}\n`;
  if (UPDATE || !existsSync(file)) {
    mkdirSync(new URL('.', file), { recursive: true });
    writeFileSync(file, text);
    return;
  }
  expect(JSON.parse(readFileSync(file, 'utf8')), `${path} is out of date: run UPDATE_CONTRACT_FIXTURES=1 npm test`).toEqual(body);
}

function check<N extends ResponseName>(name: N, res: CallResult, status = 200): z.output<(typeof RESPONSES)[N]> {
  expect(res.status, `${name}: ${res.text}`).toBe(status);
  const parsed = RESPONSES[name].safeParse(res.body);
  if (!parsed.success) throw new Error(`${name} doesn't match the contract: ${JSON.stringify(parsed.error.issues, null, 2)}`);
  record(`${name}.json`, res.body);
  return parsed.data as z.output<(typeof RESPONSES)[N]>;
}

const fixture = (path: string) => JSON.parse(readFileSync(new URL(`./fixtures/${path}`, import.meta.url), 'utf8'));
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });

const FLOW45 = 'flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a';
const JULIAN45 = 'julian-ramos/bbb0c294-87a6-465d-9f55-6f579dcb399a';
/** Included with a cut: no fee, so no card needed. */
const CARLOS_LINEUP = 'carlos-rafael/0b5b851e-ab05-44a1-8d42-dc9dbc5f02eb';
/** A card token the app made (32 bytes of 0x01, base64url). */
const CARD_TOKEN = Buffer.alloc(32, 1).toString('base64url');
const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0xff, 0xd9]);

const h = useHarness({ now: '2026-11-02T17:00:00Z' });

describe('contract fixtures (API v1)', () => {
  it('the website’s catalog (GET /api/catalog)', async () => {
    check('catalog', await h.call('GET', '/api/catalog'));
  });

  it('every response type, from the real handlers', async () => {
    const owner = { owner: true } as const;
    h.config.stripeSecretKey = 'sk_test_fixture';

    check('health', await h.call('GET', '/api/health'));

    // Reviews
    h.config.googlePlacesApiKey = 'AIzaFixtureKey';
    h.config.yelpApiKey = 'yelp-fixture-key';
    h.fetch.on('https://places.googleapis.com/v1/places/', () => json(fixture('google/place-details.json')));
    h.fetch.on('https://api.yelp.com/v3/businesses/', (url) =>
      json(fixture(url.pathname.endsWith('/reviews') ? 'yelp/reviews.json' : 'yelp/business.json')),
    );
    check('reviews', await h.call('GET', '/api/reviews'));
    h.config.googlePlacesApiKey = undefined;
    h.config.yelpApiKey = undefined;
    check('reviews-unavailable', await h.call('GET', '/api/reviews'));

    check('owner-me', await h.call('GET', '/api/owner/me', owner));
    check('no-show-settings', await h.call('GET', '/api/owner/no-show-settings', owner));
    // Off until the owner turns it on.
    await protectionOn(h);

    // Products
    const pomade = check(
      'product-created',
      await h.call('POST', '/api/owner/products', { ...owner, body: { name: 'Matte pomade', description: 'Medium hold, low shine.', priceCents: 1800 } }),
      201,
    ).product;
    check(
      'product-photo',
      await h.call('POST', `/api/owner/products/${pomade.id}/photo`, { ...owner, rawBody: JPEG, headers: { 'content-type': 'image/jpeg' } }),
    );
    const oil = (await h.call('POST', '/api/owner/products', { ...owner, body: { name: 'Beard oil', visible: false } })).body.product;
    await h.call('POST', '/api/owner/products', { ...owner, body: { name: 'Hair tonic', visible: false } });
    check('product-updated', await h.call('PATCH', `/api/owner/products/${oil.id}`, { ...owner, body: { visible: true, priceCents: 1500 } }));
    check('products', await h.call('GET', '/api/products'));
    check('owner-products', await h.call('GET', '/api/owner/products', owner));

    // No-show protection: the policy, then a card saved with Stripe Checkout (setup mode).
    check('no-show-policy', await h.call('GET', '/api/no-show-policy?serviceId=haircut-and-beard&barberId=any'));
    check('no-show-policy-not-required', await h.call('GET', `/api/no-show-policy?offeringId=${encodeURIComponent(CARLOS_LINEUP)}`));
    const flowPolicy = (await h.call('GET', `/api/no-show-policy?offeringId=${encodeURIComponent(FLOW45)}`)).body.policyText;
    const anyPolicy = (await h.call('GET', '/api/no-show-policy?serviceId=haircut&barberId=any')).body.policyText;
    const cardHeaders = { 'x-card-token': CARD_TOKEN };
    const checkout = check(
      'card-checkout',
      await h.call('POST', '/api/cards/checkout', { headers: cardHeaders, body: { offeringId: FLOW45 } }),
      201,
    );
    h.stripe.completeSession(checkout.sessionId);
    check('card-saved', await h.call('POST', '/api/cards', { headers: cardHeaders, body: { sessionId: checkout.sessionId } }), 201);

    // Customer bookings (with the card on file)
    const created = check(
      'appointment-created',
      await h.call('POST', '/api/appointments', {
        headers: cardHeaders,
        body: {
          offeringId: FLOW45,
          start: '2026-11-03T18:00:00Z',
          customer: { name: 'Fixture Client', phone: '(442) 555-0123', email: 'client@example.com' },
          note: 'Low skin fade, please.',
          noShowPolicy: flowPolicy,
        },
      }),
      201,
    );
    const token = { headers: { 'x-manage-token': created.manageToken } };
    check('appointment', await h.call('GET', `/api/appointments/${created.appointment.id}`, token));

    const anyBooking = await h.call('POST', '/api/appointments', {
      headers: cardHeaders,
      body: {
        serviceId: 'haircut',
        barberId: 'any',
        start: '2026-11-03T18:00:00Z',
        customer: { name: 'Second Client', phone: '4425550124' },
        noShowPolicy: anyPolicy,
      },
    });
    check(
      'appointment-cancelled',
      await h.call('POST', `/api/appointments/${anyBooking.body.appointment.id}/cancel`, { headers: { 'x-manage-token': anyBooking.body.manageToken } }),
    );

    // Owner bookings and payments (10:20 AM PST)
    h.setNow('2026-11-02T18:20:00Z');
    const walkIn = check(
      'owner-appointment-created',
      await h.call('POST', '/api/owner/appointments', { ...owner, body: { offeringId: JULIAN45, start: '2026-11-02T18:20:00Z', customer: { name: 'Walk-in' } } }),
      201,
    ).appointment;
    h.setNow('2026-11-02T19:05:00Z');
    check('owner-appointment-updated', await h.call('PATCH', `/api/owner/appointments/${walkIn.id}`, { ...owner, body: { status: 'completed' } }));
    check('connection-token', await h.call('POST', '/api/owner/terminal/connection-token', owner));
    const intent = check(
      'payment-created',
      await h.call('POST', '/api/owner/payments', { ...owner, body: { amountCents: 3500, description: 'Haircut', appointmentId: walkIn.id } }),
      201,
    );
    h.stripe.succeed(intent.paymentIntentId);
    h.advance(1);
    check('payment-completed', await h.call('POST', `/api/owner/payments/${intent.paymentIntentId}/complete`, owner));
    await h.call('POST', '/api/owner/payments', { ...owner, body: { amountCents: 500 } });
    check('payments', await h.call('GET', '/api/owner/payments?date=2026-11-02', owner));

    const noShow = await h.call('POST', '/api/owner/appointments', {
      ...owner,
      body: { offeringId: JULIAN45, start: '2026-11-03T19:00:00Z', customer: { name: 'Phone booking', phone: '760-555-0142' } },
    });
    await h.call('PATCH', `/api/owner/appointments/${noShow.body.appointment.id}`, { ...owner, body: { status: 'noShow' } });

    // Time off
    check(
      'time-off-created',
      await h.call('POST', '/api/owner/time-off', {
        ...owner,
        body: { barberId: 'cristian-ceja', start: '2026-11-03T20:00:00Z', end: '2026-11-03T22:00:00Z', reason: 'Dentist' },
      }),
      201,
    );
    await h.call('POST', '/api/owner/time-off', {
      ...owner,
      body: { barberId: null, start: '2026-11-26T18:00:00Z', end: '2026-11-27T03:00:00Z', reason: 'Thanksgiving' },
    });
    check('time-off-list', await h.call('GET', '/api/owner/time-off?from=2026-11-01&to=2026-11-30', owner));

    check('owner-appointments', await h.call('GET', '/api/owner/appointments?from=2026-11-02&to=2026-11-03', owner));

    // Availability last, so it shows a mix of free barbers.
    check('availability', await h.call('GET', '/api/availability?serviceId=haircut&barberId=any&from=2026-11-03&days=2'));

    // The shop changes the fee; then a client who booked with a card doesn't come (Tuesday 10:20 AM).
    check('no-show-settings-updated', await h.call('PATCH', '/api/owner/no-show-settings', { ...owner, body: { feeMode: 'flat', flatCents: 2500 } }));
    h.setNow('2026-11-03T18:20:00Z');
    await h.call('PATCH', `/api/owner/appointments/${created.appointment.id}`, { ...owner, body: { status: 'noShow' } });
    check('no-show-fee-charged', await h.call('POST', `/api/owner/appointments/${created.appointment.id}/no-show-fee`, owner));
    // Another one, whose card is declined.
    const later = await h.call('POST', '/api/appointments', {
      headers: cardHeaders,
      body: {
        offeringId: JULIAN45,
        start: '2026-11-03T19:00:00Z',
        customer: { name: 'Third Client', phone: '4425550125' },
        noShowPolicy: (await h.call('GET', `/api/no-show-policy?offeringId=${encodeURIComponent(JULIAN45)}`)).body.policyText,
      },
    });
    h.setNow('2026-11-03T19:25:00Z');
    await h.call('PATCH', `/api/owner/appointments/${later.body.appointment.id}`, { ...owner, body: { status: 'noShow' } });
    h.stripe.nextCharge = 'insufficient_funds';
    check('no-show-fee-declined', await h.call('POST', `/api/owner/appointments/${later.body.appointment.id}/no-show-fee`, owner));
    // And one who cancels in the app 30 minutes before their 1 PM: a late cancellation the owner charges.
    const lateBooking = await h.call('POST', '/api/appointments', {
      headers: cardHeaders,
      body: {
        offeringId: FLOW45,
        start: '2026-11-03T21:00:00Z',
        customer: { name: 'Fourth Client', phone: '4425550127' },
        noShowPolicy: (await h.call('GET', `/api/no-show-policy?offeringId=${encodeURIComponent(FLOW45)}`)).body.policyText,
      },
    });
    expect(lateBooking.status, lateBooking.text).toBe(201);
    h.setNow('2026-11-03T20:30:00Z');
    // Inside the window: the client confirmed the warning (the server asks first: errors/late_cancel_fee.json).
    check(
      'appointment-cancelled-late',
      await h.call('POST', `/api/appointments/${lateBooking.body.appointment.id}/cancel`, {
        headers: { 'x-manage-token': lateBooking.body.manageToken },
        body: { acceptLateCancelFee: true },
      }),
    );
    h.advance(2);
    check('late-cancel-fee-charged', await h.call('POST', `/api/owner/appointments/${lateBooking.body.appointment.id}/no-show-fee`, owner));
    check('payments-with-fees', await h.call('GET', '/api/owner/payments?date=2026-11-03', owner));
  });

  it('the shop’s own Stripe account (connect mode) and signing in on a computer', async () => {
    const owner = { owner: true } as const;
    // Settings before Stripe is set up, and with the server's own key.
    check('stripe-connection-off', await h.call('GET', '/api/owner/stripe', owner));
    h.config.stripeSecretKey = 'sk_test_fixture';
    check('stripe-connection-direct', await h.call('GET', '/api/owner/stripe', owner));

    // The app developer's platform key: the owner connects the shop's own account.
    h.config.stripeConnect = true;
    h.config.publicBaseUrl = 'https://izzy-clipz-api.test';
    check('stripe-connection-not-connected', await h.call('GET', '/api/owner/stripe', owner));
    const link = check('stripe-connect-link', await h.call('POST', '/api/owner/stripe/connect', { ...owner, body: { returnTo: 'app' } }), 201);
    const account = [...h.stripe.connectedAccounts.keys()][0]!;
    expect(link.url).toContain(account);
    h.advance(2);
    check('stripe-connection-needs-info', await h.call('GET', '/api/owner/stripe', owner));
    h.stripe.setAccount(account, { details_submitted: true, currently_due: [], disabled_reason: 'requirements.pending_verification', name: 'Izzy Clipz Barbershop' });
    h.advance(3);
    check('stripe-connection-pending', await h.call('GET', '/api/owner/stripe', owner));
    h.stripe.activateAccount(account);
    h.advance(5);
    check('stripe-connection-active', await h.call('GET', '/api/owner/stripe', owner));
    check('owner-me-connected', await h.call('GET', '/api/owner/me', owner));
    h.stripe.setAccount(account, { charges_enabled: false, payouts_enabled: false, disabled_reason: 'under_review' });
    h.advance(60);
    check('stripe-connection-restricted', await h.call('GET', '/api/owner/stripe', owner));
    check('stripe-connection-disconnected', await h.call('DELETE', '/api/owner/stripe/connect', owner));

    // A code from the Business app, typed on two computers in turn.
    h.setNow('2026-11-02T18:00:00Z');
    const code = check('computer-code', await h.call('POST', '/api/owner/computer-codes', owner), 201);
    const mac = check(
      'computer-session-created',
      await h.call('POST', '/api/computer-sessions', { body: { code: code.code, name: 'Chrome on Mac' } }),
      201,
    );
    h.advance(30);
    const second = (await h.call('POST', '/api/owner/computer-codes', owner)).body.code;
    const pc = await h.call('POST', '/api/computer-sessions', { body: { code: second, name: 'Edge on Windows' }, ip: '198.51.100.20' });
    expect(pc.status, pc.text).toBe(201);
    h.advance(15);
    check('computer-sessions', await h.call('GET', '/api/owner/computer-sessions', { headers: { authorization: `Bearer ${mac.token}` } }));
  });

  it('one example error for every error code', async () => {
    const examples: Record<string, CallResult> = {};
    const book = (body: Record<string, unknown>, ip = '203.0.113.1') =>
      h.call('POST', '/api/appointments', { body: { customer: { name: 'Fixture Client', phone: '4425550123' }, ...body }, ip });

    examples.invalid_request = await book({ offeringId: FLOW45, start: '2026-11-03T18:00:00Z', customer: { name: 'Fixture Client', phone: '555-0123' } });
    examples.unauthorized = await h.call('GET', '/api/owner/me');
    examples.not_found = await h.call('GET', '/api/appointments/00000000-0000-4000-8000-0000000000ff', {
      headers: { 'x-manage-token': 'fixture-manage-token-0000xxxxxxxxxxxxxxxxxx' },
    });
    const first = await book({ offeringId: FLOW45, start: '2026-11-03T18:00:00Z' });
    examples.slot_taken = await book({ offeringId: FLOW45, start: '2026-11-03T18:00:00Z' }, '203.0.113.2');
    const headers = { 'x-manage-token': first.body.manageToken };
    await h.call('POST', `/api/appointments/${first.body.appointment.id}/cancel`, { headers });
    examples.not_cancellable = await h.call('POST', `/api/appointments/${first.body.appointment.id}/cancel`, { headers });
    examples.outside_hours = await book({ offeringId: FLOW45, start: '2026-11-03T18:15:00Z' }, '203.0.113.3');
    examples.too_soon = await book({ offeringId: FLOW45, start: '2026-11-02T16:00:00Z' }, '203.0.113.3');
    examples.too_far = await book({ offeringId: FLOW45, start: '2027-01-04T18:00:00Z' }, '203.0.113.3');
    // Three upcoming bookings for one number, then a fourth.
    for (const [i, day] of ['04', '05', '06'].entries()) {
      await book({ offeringId: FLOW45, start: `2026-11-${day}T18:00:00Z` }, `203.0.113.${4 + i}`);
    }
    examples.rate_limited = await book({ offeringId: FLOW45, start: '2026-11-09T18:00:00Z' }, '203.0.113.7');
    // No-show protection's own errors, with Stripe set up and protection on.
    await protectionOn(h);
    examples.card_required = await book({ offeringId: FLOW45, start: '2026-11-10T18:00:00Z' }, '203.0.113.8');
    const checkout = await h.call('POST', '/api/cards/checkout', { headers: { 'x-card-token': CARD_TOKEN }, body: { offeringId: FLOW45 } });
    h.stripe.completeSession(checkout.body.sessionId);
    await h.call('POST', '/api/cards', { headers: { 'x-card-token': CARD_TOKEN }, body: { sessionId: checkout.body.sessionId } });
    examples.policy_changed = await h.call('POST', '/api/appointments', {
      headers: { 'x-card-token': CARD_TOKEN },
      body: { offeringId: FLOW45, start: '2026-11-10T18:00:00Z', customer: { name: 'Fixture Client', phone: '4425550126' }, noShowPolicy: 'An old policy.' },
      ip: '203.0.113.8',
    });
    examples.not_chargeable = await h.call('POST', `/api/owner/appointments/${first.body.appointment.id}/no-show-fee`, { owner: true });
    const protectedBooking = await h.call('POST', '/api/appointments', {
      headers: { 'x-card-token': CARD_TOKEN },
      body: {
        offeringId: FLOW45,
        start: '2026-11-10T18:00:00Z',
        customer: { name: 'Fixture Client', phone: '4425550126' },
        noShowPolicy: (await h.call('GET', `/api/no-show-policy?offeringId=${encodeURIComponent(FLOW45)}`)).body.policyText,
      },
      ip: '203.0.113.9',
    });
    examples.not_started = await h.call('PATCH', `/api/owner/appointments/${protectedBooking.body.appointment.id}`, {
      owner: true,
      body: { status: 'noShow' },
    });
    // The client cancels that booking 30 minutes before, without having seen the warning yet.
    h.setNow('2026-11-10T17:30:00Z');
    examples.late_cancel_fee = await h.call('POST', `/api/appointments/${protectedBooking.body.appointment.id}/cancel`, {
      headers: { 'x-manage-token': protectedBooking.body.manageToken },
    });
    // The shop's own Stripe account and computer sign-in.
    examples.stripe_connect_off = await h.call('POST', '/api/owner/stripe/connect', { owner: true, body: { returnTo: 'app' } });
    await h.call('POST', '/api/owner/computer-codes', { owner: true });
    examples.wrong_code = await h.call('POST', '/api/computer-sessions', { body: { code: '000000', name: 'Chrome on Mac' } });
    const code = (await h.call('POST', '/api/owner/computer-codes', { owner: true })).body.code;
    const computer = await h.call('POST', '/api/computer-sessions', { body: { code, name: 'Chrome on Mac' } });
    examples.forbidden = await h.call('POST', '/api/owner/computer-codes', { headers: { authorization: `Bearer ${computer.body.token}` } });
    h.config.stripeSecretKey = undefined;
    examples.stripe_not_configured = await h.call('POST', '/api/owner/terminal/connection-token', { owner: true });
    h.config.ownerKey = undefined;
    examples.owner_not_configured = await h.call('GET', '/api/owner/me', { owner: true });
    const broken = createApp({
      ...h.deps,
      db: {
        query: async () => {
          throw new Error('connection refused');
        },
        transaction: async () => {
          throw new Error('connection refused');
        },
      },
    });
    const res = await broken.fetch(new Request('https://x.test/api/products'));
    const text = await res.text();
    examples.server_error = { status: res.status, headers: res.headers, body: JSON.parse(text), text };

    const status: Record<string, number> = {
      invalid_request: 400,
      unauthorized: 401,
      not_found: 404,
      slot_taken: 409,
      not_cancellable: 409,
      outside_hours: 422,
      too_soon: 422,
      too_far: 422,
      rate_limited: 429,
      card_required: 400,
      policy_changed: 409,
      not_chargeable: 409,
      not_started: 409,
      late_cancel_fee: 409,
      stripe_not_configured: 503,
      owner_not_configured: 503,
      stripe_connect_off: 409,
      wrong_code: 400,
      forbidden: 403,
      server_error: 500,
    };
    expect(Object.keys(examples).sort()).toEqual(Object.keys(status).sort());
    for (const [code, result] of Object.entries(examples)) {
      expect(result.status, code).toBe(status[code]);
      expect(ErrorBody.parse(result.body).error.code).toBe(code);
      record(`errors/${code}.json`, result.body);
    }
  });
});
