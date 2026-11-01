import { createHash } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { newManageToken } from '../src/auth.js';
import { publicBase } from '../src/cards.js';
import { stripeError, useHarness } from './helpers/harness.js';

// Saving a card for no-show protection: Stripe Checkout in setup mode, the https
// page Stripe returns to, and saving the completed session under the app's token.

// Monday Nov 2 2026, 9:00 AM PST.
const h = useHarness({ now: '2026-11-02T17:00:00Z' });

const FLOW45 = 'flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a';
const LINEUP = 'carlos-rafael/0b5b851e-ab05-44a1-8d42-dc9dbc5f02eb';
const sha256 = (text: string) => createHash('sha256').update(text).digest('hex');

const checkout = (token: string | undefined, body: unknown = { offeringId: FLOW45 }, ip?: string) =>
  h.call('POST', '/api/cards/checkout', { body, headers: token === undefined ? {} : { 'x-card-token': token }, ...(ip ? { ip } : {}) });
const save = (token: string | undefined, sessionId: string, ip?: string) =>
  h.call('POST', '/api/cards', { body: { sessionId }, headers: token === undefined ? {} : { 'x-card-token': token }, ...(ip ? { ip } : {}) });

/** Checkout made and completed on Stripe's page, ready to save. */
async function completedSession(token: string, card?: Parameters<typeof h.stripe.completeSession>[1]): Promise<string> {
  const res = await checkout(token);
  expect(res.status, res.text).toBe(201);
  h.stripe.completeSession(res.body.sessionId, card);
  return res.body.sessionId;
}

describe('POST /api/cards/checkout', () => {
  it('503 stripe_not_configured without a Stripe key, before anything else', async () => {
    const res = await checkout(newManageToken());
    expect(res.status).toBe(503);
    expect(res.body.error.code).toBe('stripe_not_configured');
    expect(h.stripe.calls).toEqual([]);
  });

  it('makes a Customer and a setup-mode Checkout Session with the policy, cards only, returning over https', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    const token = newManageToken();
    const res = await checkout(token);
    expect(res.status).toBe(201);
    expect(res.body).toEqual({ url: 'https://checkout.stripe.com/c/pay/cs_test_Fixture000002#fixture', sessionId: 'cs_test_Fixture000002' });

    expect(h.stripe.calls.map((c) => c.method)).toEqual(['customers.create', 'checkout.sessions.create']);
    expect(h.stripe.calls[0]!.params).toEqual({
      description: 'Izzy Clipz client (card for no-show protection)',
      metadata: { source: 'izzy-clipz-api', purpose: 'izzy_no_show_card' },
    });
    const params = h.stripe.calls[1]!.params as Record<string, unknown>;
    expect(params).toEqual({
      mode: 'setup',
      currency: 'usd',
      allowed_payment_method_types: ['card'],
      customer: 'cus_TestFixture000001',
      success_url: 'https://izzy-clipz-api.test/api/cards/return?session_id={CHECKOUT_SESSION_ID}',
      cancel_url: 'https://izzy-clipz-api.test/api/cards/cancel',
      custom_text: {
        submit: {
          message:
            "No payment now. If you don't come and haven't cancelled, Izzy Clipz may charge $17.50 (50% of the service) to this card. Cancelling in the app before your appointment is free.",
        },
      },
      setup_intent_data: {
        description: 'Izzy Clipz no-show protection',
        metadata: { source: 'izzy-clipz-api', purpose: 'izzy_no_show_card' },
      },
      metadata: { source: 'izzy-clipz-api', purpose: 'izzy_no_show_card', card_token_sha256: sha256(token) },
      expires_at: Date.parse('2026-11-02T18:00:00Z') / 1000,
    });
    // API 2026-10-28.endive has no payment_method_types on Checkout Sessions.
    expect(params).not.toHaveProperty('payment_method_types');
    // The token itself never goes to Stripe.
    expect(JSON.stringify(h.stripe.calls)).not.toContain(token);
  });

  it('uses PUBLIC_BASE_URL for the way back when it is set', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    h.config.publicBaseUrl = 'https://api.izzyclipz.example/';
    await checkout(newManageToken());
    const params = h.stripe.calls[1]!.params as Record<string, unknown>;
    expect(params.success_url).toBe('https://api.izzyclipz.example/api/cards/return?session_id={CHECKOUT_SESSION_ID}');
    expect(params.cancel_url).toBe('https://api.izzyclipz.example/api/cards/cancel');
  });

  it('the way back: PUBLIC_BASE_URL (with or without a path), or the request’s own address', () => {
    expect(publicBase(undefined, 'https://izzy-clipz-api.vercel.app')).toBe('https://izzy-clipz-api.vercel.app');
    expect(publicBase('https://api.example.com/', 'https://x.test')).toBe('https://api.example.com');
    expect(publicBase('https://example.com/izzy/', 'https://x.test')).toBe('https://example.com/izzy');
    expect(publicBase('not a url', 'https://x.test')).toBe('https://x.test');
    expect(publicBase('ftp://example.com', 'https://x.test')).toBe('https://x.test');
  });

  it('needs the app’s card token, in the manage token format', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    for (const token of [undefined, '', 'short', 'x'.repeat(43) + 'y', `${newManageToken().slice(0, 42)}B`]) {
      const res = await checkout(token);
      expect(res.status, String(token)).toBe(400);
      expect(res.body.error.code).toBe('invalid_request');
    }
    expect(h.stripe.calls).toEqual([]);
  });

  it('turns down a booking that needs no card, and a target that isn’t on the menu', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    const lineup = await checkout(newManageToken(), { offeringId: LINEUP });
    expect(lineup.status).toBe(400);
    expect(lineup.body.error.message).toBe("This booking doesn't need a card. Go ahead and book.");
    await h.call('PATCH', '/api/owner/no-show-settings', { owner: true, body: { enabled: false } });
    expect((await checkout(newManageToken())).status).toBe(400);
    await h.call('PATCH', '/api/owner/no-show-settings', { owner: true, body: { enabled: true } });
    expect((await checkout(newManageToken(), { offeringId: 'nope' })).status).toBe(400);
    expect((await checkout(newManageToken(), { serviceId: 'haircut' })).status).toBe(400);
    expect(h.stripe.calls).toEqual([]);
    // Any barber works.
    expect((await checkout(newManageToken(), { serviceId: 'haircut-and-beard', barberId: 'any' })).status).toBe(201);
  });

  it('allows 10 a hour from one network, then 429', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    for (let i = 0; i < 10; i++) expect((await checkout(newManageToken())).status).toBe(201);
    const eleventh = await checkout(newManageToken());
    expect(eleventh.status).toBe(429);
    expect(eleventh.body.error).toEqual({
      code: 'rate_limited',
      message: 'Too many tries to add a card from this network. Try again in an hour, or call the shop.',
    });
    expect(eleventh.headers.get('retry-after')).toBe('3600');
    expect((await checkout(newManageToken(), undefined, '198.51.100.4')).status).toBe(201);
    h.advance(61);
    expect((await checkout(newManageToken())).status).toBe(201);
  });

  it('a Stripe failure is a plain 500, logged without the key', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    h.stripe.nextError = stripeError('StripeConnectionError', {}, 'socket hang up');
    const res = await checkout(newManageToken());
    expect(res.status).toBe(500);
    expect(res.body.error).toEqual({ code: 'server_error', message: "We couldn't reach Stripe. Please try again." });
    expect(h.logs[0]).toMatchObject({ level: 'error', message: 'Stripe create customer failed' });
  });
});

describe('GET /api/cards/return and /api/cards/cancel', () => {
  it('sends the phone back to the app with the session id', async () => {
    const res = await h.call('GET', '/api/cards/return?session_id=cs_test_a1B2c3');
    expect(res.status).toBe(302);
    expect(res.headers.get('location')).toBe('izzyclipz://card-saved?session_id=cs_test_a1B2c3');
    expect(res.headers.get('cache-control')).toBe('no-store');
    expect(res.headers.get('content-type')).toBe('text/html; charset=utf-8');
    expect(res.text).toContain('<a href="izzyclipz://card-saved?session_id=cs_test_a1B2c3">Back to Izzy Clipz</a>');
  });

  it('cancelled on Stripe’s page, or a session id that isn’t one, goes back without a card', async () => {
    const cancel = await h.call('GET', '/api/cards/cancel');
    expect(cancel.status).toBe(302);
    expect(cancel.headers.get('location')).toBe('izzyclipz://card-cancelled');
    for (const query of ['', '?session_id=', '?session_id={CHECKOUT_SESSION_ID}', '?session_id=cs_test_x%22%3E%3Cscript%3E', '?session_id=pi_123']) {
      const res = await h.call('GET', `/api/cards/return${query}`);
      expect(res.status, query).toBe(302);
      expect(res.headers.get('location')).toBe('izzyclipz://card-failed');
    }
  });
});

describe('POST /api/cards', () => {
  it('saves the card from a completed session: brand, last 4 and expiry only, under the token’s hash', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    const token = newManageToken();
    const sessionId = await completedSession(token, { brand: 'mastercard', last4: '4444', exp_month: 3, exp_year: 2029 });
    const res = await save(token, sessionId);
    expect(res.status).toBe(201);
    expect(res.body).toEqual({ card: { brand: 'mastercard', last4: '4444', expMonth: 3, expYear: 2029 } });
    expect(h.stripe.calls.at(-1)).toEqual({
      method: 'checkout.sessions.retrieve',
      params: { id: sessionId, expand: ['setup_intent.payment_method'] },
    });
    const { rows } = await h.database.pool.query('SELECT * FROM saved_cards');
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      token_hash: sha256(token),
      checkout_session_id: sessionId,
      stripe_customer_id: 'cus_TestFixture000001',
      brand: 'mastercard',
      last4: '4444',
      exp_month: 3,
      exp_year: 2029,
      livemode: false,
    });
    expect(rows[0].stripe_payment_method_id).toMatch(/^pm_TestFixture/);
    expect(JSON.stringify(rows)).not.toContain(token);
  });

  it('saving again with the same token and session answers 200 with the same card (a lost answer)', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    const token = newManageToken();
    const sessionId = await completedSession(token);
    const first = await save(token, sessionId);
    const again = await save(token, sessionId);
    expect(again.status).toBe(200);
    expect(again.body).toEqual(first.body);
    expect((await h.database.pool.query('SELECT count(*)::int AS n FROM saved_cards')).rows[0].n).toBe(1);
  });

  it('one token, one card: the same token for another session is a 400', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    const token = newManageToken();
    const first = await completedSession(token);
    const second = await completedSession(token);
    expect((await save(token, first)).status).toBe(201);
    const res = await save(token, second);
    expect(res.status).toBe(400);
    expect(res.body.error.message).toBe('That card token was already used for another card.');
  });

  it('someone who only knows the session id gets nothing', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    const sessionId = await completedSession(newManageToken());
    const res = await save(newManageToken(), sessionId);
    expect(res.status).toBe(404);
    expect(res.body.error).toEqual({ code: 'not_found', message: "We couldn't find that card. Add it again." });
    expect((await h.database.pool.query('SELECT count(*)::int AS n FROM saved_cards')).rows[0].n).toBe(0);
  });

  it('a session that isn’t finished is a 400 that says to add it again', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    const token = newManageToken();
    const open = (await checkout(token)).body.sessionId;
    const res = await save(token, open);
    expect(res.status).toBe(400);
    expect(res.body.error.message).toBe("The card wasn't added. Add it again.");
    // A completed session whose SetupIntent didn't succeed, likewise.
    const session = h.stripe.completeSession(open);
    (session.setup_intent as { status: string }).status = 'requires_payment_method';
    expect((await save(token, open)).status).toBe(400);
  });

  it('a session Stripe doesn’t know, one this server didn’t make, or one not in setup mode is a 404', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    const token = newManageToken();
    expect((await save(token, 'cs_test_Unknown')).status).toBe(404);
    const foreign = await completedSession(token);
    h.stripe.sessions.get(foreign)!.metadata = { card_token_sha256: sha256(token) };
    expect((await save(token, foreign)).status).toBe(404);
    const payment = await completedSession(token);
    (h.stripe.sessions.get(payment) as { mode: string }).mode = 'payment';
    expect((await save(token, payment)).status).toBe(404);
  });

  it('turns down an expired card, and anything that isn’t a card', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    const token = newManageToken();
    const expired = await completedSession(token, { brand: 'visa', last4: '0069', exp_month: 10, exp_year: 2026 });
    const res = await save(token, expired);
    expect(res.status).toBe(400);
    expect(res.body.error.message).toBe('That card has expired. Add another card.');
    // Good through the end of its month.
    const tokenB = newManageToken();
    const thisMonth = await completedSession(tokenB, { brand: 'visa', last4: '1111', exp_month: 11, exp_year: 2026 });
    expect((await save(tokenB, thisMonth)).status).toBe(201);

    const other = newManageToken();
    const link = await completedSession(other);
    const pm = (h.stripe.sessions.get(link)!.setup_intent as { payment_method: { type: string; card: unknown } }).payment_method;
    pm.type = 'link';
    pm.card = null;
    const notCard = await save(other, link);
    expect(notCard.status).toBe(400);
    expect(notCard.body.error.message).toBe('Only a card can be saved for no-show protection. Add a card.');
  });

  it('validates the token and the session id before calling Stripe', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    expect((await save(undefined, 'cs_test_abc')).status).toBe(400);
    expect((await save('bad', 'cs_test_abc')).status).toBe(400);
    for (const sessionId of ['', 'pi_123', 'cs_test_', 'cs_test_a/b', 'cs_prod_abc']) {
      const res = await save(newManageToken(), sessionId);
      expect(res.status, sessionId).toBe(400);
    }
    const wrongType = await h.call('POST', '/api/cards', { body: { sessionId: 5 }, headers: { 'x-card-token': newManageToken() } });
    expect(wrongType.status).toBe(400);
    expect(h.stripe.calls).toEqual([]);
  });

  it('allows 10 saves a hour from one network; a repeat of one that went through isn’t counted', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    const token = newManageToken();
    const sessionId = await completedSession(token);
    for (let i = 0; i < 10; i++) expect((await save(newManageToken(), 'cs_test_Unknown', '192.0.2.9')).status).toBe(404);
    expect((await save(token, sessionId, '192.0.2.9')).status).toBe(429);
    expect((await save(token, sessionId, '192.0.2.10')).status).toBe(201);
    // Saved now: a repeat answers even from the limited network.
    expect((await save(token, sessionId, '192.0.2.9')).status).toBe(200);
  });

  it('503 without Stripe', async () => {
    expect((await save(newManageToken(), 'cs_test_abc')).status).toBe(503);
  });
});
