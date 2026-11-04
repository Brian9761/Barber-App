import { readdirSync, readFileSync } from 'node:fs';
import type Stripe from 'stripe';
import { describe, expect, it } from 'vitest';
import { newManageToken } from '../src/auth.js';
import { SHOP_ADDRESS } from '../src/stripeconnect.js';
import { RESPONSES } from './helpers/contract.js';
import { connectedShop, FakeStripe, PLATFORM_KEY, stripeError, useHarness } from './helpers/harness.js';

// With Stripe Connect every Stripe call for the shop goes to its connected account (the
// Stripe-Account header): Tap to Pay and its Terminal location, payments, saved cards and
// fees. A card or payment keeps the account it was made on.

// Monday Nov 2 2026, 9:00 AM PST. Tuesday Nov 3 opens at 10:00 PST = 18:00Z.
const h = useHarness({ now: '2026-11-02T17:00:00Z' });
const owner = { owner: true } as const;
const FLOW45 = 'flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a';
const TUE10 = '2026-11-03T18:00:00Z';

/** The calls made while `fn` runs. */
async function callsDuring(fn: () => Promise<unknown>) {
  const before = h.stripe.calls.length;
  await fn();
  return h.stripe.calls.slice(before);
}

const methods = (calls: { method: string }[]) => calls.map((c) => c.method);
const protectionOn = () => h.call('PATCH', '/api/owner/no-show-settings', { ...owner, body: { enabled: true } });

async function saveCard(ip = '192.0.2.50'): Promise<string> {
  const token = newManageToken();
  const checkout = await h.call('POST', '/api/cards/checkout', { headers: { 'x-card-token': token }, body: { offeringId: FLOW45 }, ip });
  expect(checkout.status, checkout.text).toBe(201);
  h.stripe.completeSession(checkout.body.sessionId);
  const saved = await h.call('POST', '/api/cards', { headers: { 'x-card-token': token }, body: { sessionId: checkout.body.sessionId }, ip });
  expect(saved.status, saved.text).toBe(201);
  return token;
}

async function book(cardToken: string, start = TUE10, phone = '4425550150') {
  const policy = (await h.call('GET', `/api/no-show-policy?offeringId=${encodeURIComponent(FLOW45)}`)).body.policyText;
  return h.call('POST', '/api/appointments', {
    headers: { 'x-card-token': cardToken },
    body: { offeringId: FLOW45, start, customer: { name: 'Card Client', phone }, noShowPolicy: policy },
    ip: '203.0.113.90',
  });
}

/** A booking with a card on file whose client didn't come, marked as a no-show after the start. */
async function noShow(cardToken: string, start = TUE10, phone?: string): Promise<string> {
  const booked = await book(cardToken, start, phone);
  expect(booked.status, booked.text).toBe(201);
  h.setNow(new Date(Date.parse(start) + 20 * 60_000).toISOString());
  expect((await h.call('PATCH', `/api/owner/appointments/${booked.body.appointment.id}`, { ...owner, body: { status: 'noShow' } })).status).toBe(200);
  return booked.body.appointment.id;
}
const charge = (id: string) => h.call('POST', `/api/owner/appointments/${id}/no-show-fee`, owner);

/** Every method of the fake Stripe client, as "terminal.locations.create". */
function clientMethods(client: FakeStripe): string[] {
  const found: string[] = [];
  const walk = (value: unknown, path: string) => {
    if (typeof value === 'function') return void found.push(path);
    if (typeof value !== 'object' || value === null || value instanceof Map || Array.isArray(value)) return;
    for (const [key, inner] of Object.entries(value)) walk(inner, `${path}.${key}`);
  };
  for (const [key, value] of Object.entries(client)) if (typeof value === 'object') walk(value, key);
  return found.sort();
}

describe('every Stripe call for the shop goes to its connected account', () => {
  it('walks every call site with a connected account: each sends it as stripeAccount, except the platform’s own calls', async () => {
    // accounts.create, accountLinks.create, accounts.retrieve: the platform's own calls.
    const account = await connectedShop(h);
    await protectionOn();
    const sites: { site: string; calls: Awaited<ReturnType<typeof callsDuring>> }[] = [];
    const site = async (name: string, fn: () => Promise<unknown>) => sites.push({ site: name, calls: await callsDuring(fn) });

    await site('Terminal location (GET /api/owner/me)', () => h.call('GET', '/api/owner/me', owner));
    await site('connection token', () => h.call('POST', '/api/owner/terminal/connection-token', owner));
    let intentId = '';
    await site('Tap to Pay payment', async () => {
      intentId = (await h.call('POST', '/api/owner/payments', { ...owner, body: { amountCents: 3500 } })).body.paymentIntentId;
    });
    h.stripe.succeed(intentId);
    await site('complete a payment', () => h.call('POST', `/api/owner/payments/${intentId}/complete`, owner));
    let token = '';
    await site('card checkout and save', async () => {
      token = await saveCard();
    });
    const missed = await noShow(token);
    h.stripe.nextCharge = 'processing';
    await site('no-show fee', () => charge(missed));
    await site('a fee Stripe is processing, checked again', () => charge(missed));
    const lost = await noShow(token, '2026-11-04T18:00:00Z', '4425550151');
    h.stripe.loseNextChargeAnswer = true;
    await site('a fee whose answer was lost', () => charge(lost));
    await site('…looked up at Stripe before charging again', () => charge(lost));
    await site('Settings (GET /api/owner/stripe)', () => h.call('GET', '/api/owner/stripe', owner));
    await site('another onboarding link', () => h.call('POST', '/api/owner/stripe/connect', { ...owner, body: { returnTo: 'web' } }));

    expect(sites.map((s) => [s.site, methods(s.calls)])).toEqual([
      ['Terminal location (GET /api/owner/me)', ['terminal.locations.create']],
      ['connection token', ['terminal.connectionTokens.create']],
      ['Tap to Pay payment', ['paymentIntents.create']],
      ['complete a payment', ['paymentIntents.retrieve']],
      ['card checkout and save', ['customers.create', 'checkout.sessions.create', 'checkout.sessions.retrieve']],
      ['no-show fee', ['paymentIntents.create']],
      ['a fee Stripe is processing, checked again', ['paymentIntents.retrieve']],
      ['a fee whose answer was lost', ['paymentIntents.create']],
      ['…looked up at Stripe before charging again', ['paymentIntents.list']],
      ['Settings (GET /api/owner/stripe)', ['accounts.retrieve']],
      ['another onboarding link', ['accountLinks.create']],
    ]);
    const platformCalls = new Set(['accounts.create', 'accounts.retrieve', 'accountLinks.create']);
    for (const call of h.stripe.calls) {
      if (platformCalls.has(call.method)) expect(call.options?.stripeAccount, call.method).toBeUndefined();
      else expect(call.options?.stripeAccount, call.method).toBe(account);
    }
    // Every method the server can call was called here, so a new one can't slip by untested.
    expect([...new Set(methods(h.stripe.calls))].sort()).toEqual(clientMethods(h.stripe));
    // Every client is the platform's key.
    expect(new Set(h.stripe.keys)).toEqual(new Set([PLATFORM_KEY]));
  });

  it('only stripeaccount.ts makes Stripe clients (shopStripe and platformStripe), so none can skip the account', () => {
    const dir = new URL('../src/', import.meta.url);
    const makers = readdirSync(dir)
      .filter((f) => f.endsWith('.ts'))
      .filter((f) => /\bdeps\.stripe\(|\.stripe\(key\)|stripeSecretKey\)/.test(readFileSync(new URL(f, dir), 'utf8')));
    expect(makers.sort()).toEqual(['stripeaccount.ts']);
  });
});

describe('Tap to Pay with a connected account', () => {
  it('makes the shop’s Terminal location on its account once, even when several requests need it at once', async () => {
    const account = await connectedShop(h);
    h.config.stripeTerminalLocationId = 'tml_IgnoredInConnectMode';
    const results = await Promise.all([
      h.call('GET', '/api/owner/me', owner),
      h.call('POST', '/api/owner/terminal/connection-token', owner),
      h.call('POST', '/api/owner/terminal/connection-token', owner),
      h.call('GET', '/api/owner/me', owner),
    ]);
    expect(results.map((r) => r.status)).toEqual([200, 200, 200, 200]);
    const creates = h.stripe.calls.filter((c) => c.method === 'terminal.locations.create');
    expect(creates).toEqual([
      {
        method: 'terminal.locations.create',
        params: { display_name: 'Izzy Clipz Barbershop', address: SHOP_ADDRESS },
        options: { stripeAccount: account },
      },
    ]);
    expect(SHOP_ADDRESS).toEqual({ line1: '1919 Mission Ave', line2: 'Ste 105', city: 'Oceanside', state: 'CA', postal_code: '92058', country: 'US' });
    const location = [...h.stripe.locations.keys()][0];
    expect(results[0]!.body).toEqual({
      ok: true,
      stripe: { configured: true, mode: 'test', locationId: location },
      connection: { mode: 'connect', status: 'active', businessName: 'Izzy Clipz Barbershop' },
    });
    expect(RESPONSES['owner-me-connected'].safeParse(results[0]!.body).success).toBe(true);
    for (const token of h.stripe.calls.filter((c) => c.method === 'terminal.connectionTokens.create')) {
      expect(token).toEqual({ method: 'terminal.connectionTokens.create', params: { location }, options: { stripeAccount: account } });
    }
    // Cached: later requests don't ask for another.
    await h.call('POST', '/api/owner/terminal/connection-token', owner);
    expect(h.stripe.calls.filter((c) => c.method === 'terminal.locations.create')).toHaveLength(1);
  });

  it('when Stripe can’t make the location, /api/owner/me answers without one, and asks again next time', async () => {
    await connectedShop(h);
    h.stripe.nextError = stripeError('StripeConnectionError', {}, 'socket hang up');
    const first = await h.call('GET', '/api/owner/me', owner);
    expect(first.status).toBe(200);
    expect(first.body.stripe).toEqual({ configured: true, mode: 'test', locationId: null });
    expect(h.logs.at(-1)).toMatchObject({ level: 'error', message: 'Stripe create terminal location failed' });
    const second = await h.call('GET', '/api/owner/me', owner);
    expect(second.body.stripe.locationId).toMatch(/^tml_/);
  });

  it('a location the owner deleted in the Dashboard: the token fails with what to do, and the next try makes a new one', async () => {
    const account = await connectedShop(h);
    await h.call('POST', '/api/owner/terminal/connection-token', owner);
    const gone = [...h.stripe.locations.keys()][0]!;
    h.stripe.nextError = stripeError('StripeInvalidRequestError', { code: 'resource_missing', param: 'location', statusCode: 400 }, `No such location: '${gone}'`);
    const failed = await h.call('POST', '/api/owner/terminal/connection-token', owner);
    expect(failed.status).toBe(500);
    expect(failed.body.error.message).toBe("Stripe couldn't find the shop's Tap to Pay location. Try again, and a new one is set up.");
    const again = await h.call('POST', '/api/owner/terminal/connection-token', owner);
    expect(again.status).toBe(200);
    const locations = h.stripe.calls.filter((c) => c.method === 'terminal.locations.create');
    expect(locations).toHaveLength(2);
    expect(h.stripe.calls.at(-1)).toMatchObject({ params: { location: [...h.stripe.locations.keys()][1] }, options: { stripeAccount: account } });
  });

  it('a payment is made on the connected account, kept with it, and checked there even after the shop connects another', async () => {
    const first = await connectedShop(h);
    const made = await h.call('POST', '/api/owner/payments', { ...owner, body: { amountCents: 4200, description: 'Haircut' } });
    expect(made.status, made.text).toBe(201);
    const id = made.body.paymentIntentId;
    expect(h.stripe.calls.at(-1)).toMatchObject({ method: 'paymentIntents.create', options: { stripeAccount: first } });
    expect((await h.database.pool.query('SELECT stripe_account_id FROM payments WHERE id = $1', [id])).rows[0].stripe_account_id).toBe(first);

    await h.call('DELETE', '/api/owner/stripe/connect', owner);
    // Not connected now: no new payments, but the one made can still be checked.
    expect((await h.call('POST', '/api/owner/payments', { ...owner, body: { amountCents: 500 } })).status).toBe(503);
    h.stripe.succeed(id);
    const done = await h.call('POST', `/api/owner/payments/${id}/complete`, owner);
    expect(done.status, done.text).toBe(200);
    expect(done.body.payment.status).toBe('succeeded');
    expect(h.stripe.calls.at(-1)).toEqual({ method: 'paymentIntents.retrieve', params: id, options: { stripeAccount: first } });
    const second = await connectedShop(h);
    expect(second).not.toBe(first);
    await h.call('POST', `/api/owner/payments/${id}/complete`, owner);
    expect(h.stripe.calls.at(-1)).toMatchObject({ method: 'paymentIntents.retrieve', options: { stripeAccount: first } });
  });

  it('when the platform can’t use the shop’s account any more, the owner is told to connect again', async () => {
    const account = await connectedShop(h);
    h.stripe.nextError = stripeError(
      'StripePermissionError',
      { statusCode: 403, requestId: 'req_fixture_access' },
      `The provided key 'sk_test_…' does not have access to account '${account}' (or that account does not exist). Application access may have been revoked.`,
    );
    const res = await h.call('POST', '/api/owner/payments', { ...owner, body: { amountCents: 3500 } });
    expect(res.status).toBe(500);
    expect(res.body.error).toEqual({ code: 'server_error', message: "Stripe didn't let the app use the shop's Stripe account. Connect Stripe again in Settings." });
    // A key Stripe turns down is still about the key.
    h.stripe.nextError = stripeError('StripeAuthenticationError', { statusCode: 401 }, 'Invalid API Key provided');
    const badKey = await h.call('POST', '/api/owner/payments', { ...owner, body: { amountCents: 3500 } });
    expect(badKey.body.error.message).toBe("Stripe didn't accept the server's Stripe key. Check STRIPE_SECRET_KEY on the server.");
  });

  it('Tap to Pay is for the Business app on the iPhone: a computer can’t get a token or start a payment', async () => {
    await connectedShop(h);
    const code = (await h.call('POST', '/api/owner/computer-codes', owner)).body.code;
    const signedIn = await h.call('POST', '/api/computer-sessions', { body: { code, name: 'Safari on Mac' } });
    const headers = { authorization: `Bearer ${signedIn.body.token}` };
    for (const [path, body] of [
      ['/api/owner/terminal/connection-token', undefined],
      ['/api/owner/payments', { amountCents: 3500 }],
    ] as const) {
      const res = await h.call('POST', path, { headers, ...(body ? { body } : {}) });
      expect(res.status, path).toBe(403);
      expect(res.body.error).toEqual({ code: 'forbidden', message: 'This can only be done in the Izzy Clipz Business app on your iPhone.' });
    }
    expect(h.stripe.calls.filter((c) => c.method.startsWith('terminal') || c.method.startsWith('paymentIntents'))).toEqual([]);
  });
});

describe('saved cards and fees with a connected account', () => {
  it('the card is saved on the connected account, and kept with it', async () => {
    const account = await connectedShop(h);
    await protectionOn();
    const calls = await callsDuring(() => saveCard());
    for (const call of calls) expect(call.options, call.method).toEqual({ stripeAccount: account });
    const { rows } = await h.database.pool.query('SELECT stripe_account_id, livemode FROM saved_cards');
    expect(rows).toEqual([{ stripe_account_id: account, livemode: false }]);
  });

  it('the policy needs a card only once the account can take card payments', async () => {
    const account = await connectedShop(h);
    await protectionOn();
    const policy = () => h.call('GET', `/api/no-show-policy?offeringId=${encodeURIComponent(FLOW45)}`);
    expect((await policy()).body.required).toBe(true);
    h.stripe.setAccount(account, { charges_enabled: false, disabled_reason: 'under_review' });
    await h.call('GET', '/api/owner/stripe', owner);
    expect((await policy()).body).toMatchObject({ required: false, policyText: null });
    const checkout = await h.call('POST', '/api/cards/checkout', { headers: { 'x-card-token': newManageToken() }, body: { offeringId: FLOW45 } });
    expect(checkout.status).toBe(503);
    expect(checkout.body.error.message).toBe('Stripe paused card payments: open Stripe to fix it.');
  });

  it('a fee is charged to the card on the account it was saved on, and recorded with it', async () => {
    const account = await connectedShop(h);
    await protectionOn();
    const id = await noShow(await saveCard());
    const res = await charge(id);
    expect(res.status, res.text).toBe(200);
    expect(res.body.appointment.noShowFee.status).toBe('charged');
    const create = h.stripe.calls.filter((c) => c.method === 'paymentIntents.create').at(-1)!;
    expect(create.options).toEqual({ idempotencyKey: `izzy-no-show-fee-${id}-1`, stripeAccount: account });
    expect((create.params as Stripe.PaymentIntentCreateParams).off_session).toBe(true);
    const { rows } = await h.database.pool.query('SELECT kind, stripe_account_id FROM payments');
    expect(rows).toEqual([{ kind: 'no_show_fee', stripe_account_id: account }]);
  });

  it('after the shop connects another account, cards saved on the old one can’t book or be charged', async () => {
    const first = await connectedShop(h);
    await protectionOn();
    const oldCard = await saveCard();
    const booked = await book(oldCard, '2026-11-05T18:00:00Z', '4425550152');
    expect(booked.status, booked.text).toBe(201);
    await h.call('DELETE', '/api/owner/stripe/connect', owner);
    const second = await connectedShop(h);
    expect(second).not.toBe(first);

    const again = await book(oldCard, '2026-11-06T18:00:00Z', '4425550153');
    expect(again.status).toBe(400);
    expect(again.body.error).toEqual({ code: 'card_required', message: 'Add your card again: the shop changed its payment account.' });
    // The booking made with it is kept, but its fee can't be charged with the new account.
    h.setNow('2026-11-05T18:20:00Z');
    await h.call('PATCH', `/api/owner/appointments/${booked.body.appointment.id}`, { ...owner, body: { status: 'noShow' } });
    h.stripe.calls.length = 0;
    const refused = await charge(booked.body.appointment.id);
    expect(refused.status).toBe(409);
    expect(refused.body.error).toEqual({ code: 'not_chargeable', message: "This card was saved with the shop's old Stripe account." });
    expect(h.stripe.calls).toEqual([]);
    // A card saved now (on the new account) books as before.
    h.setNow('2026-11-02T17:00:00Z');
    const fresh = await book(await saveCard('192.0.2.51'), '2026-11-06T18:00:00Z', '4425550154');
    expect(fresh.status, fresh.text).toBe(201);
    expect((await h.database.pool.query('SELECT stripe_account_id FROM saved_cards ORDER BY created_at')).rows.map((r) => r.stripe_account_id)).toEqual([first, second]);
  });

  it('a fee whose answer was lost before the shop switched accounts is still looked up on the card’s account', async () => {
    const first = await connectedShop(h);
    await protectionOn();
    const id = await noShow(await saveCard());
    h.stripe.loseNextChargeAnswer = true;
    expect((await charge(id)).status).toBe(500);
    await h.call('DELETE', '/api/owner/stripe/connect', owner);
    await connectedShop(h);
    const res = await charge(id);
    expect(res.status, res.text).toBe(200);
    expect(res.body.appointment.noShowFee.status).toBe('charged');
    const list = h.stripe.calls.filter((c) => c.method === 'paymentIntents.list').at(-1)!;
    expect(list.options).toEqual({ stripeAccount: first });
    // Found, not charged again.
    expect(h.stripe.calls.filter((c) => c.method === 'paymentIntents.create' && (c.params as { confirm?: boolean }).confirm)).toHaveLength(1);
  });

  it('a card saved with the server’s own key (before connect mode) is from another account too', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    await protectionOn();
    const directCard = await saveCard();
    expect((await h.database.pool.query('SELECT stripe_account_id FROM saved_cards')).rows).toEqual([{ stripe_account_id: null }]);
    await connectedShop(h);
    const res = await book(directCard);
    expect(res.status).toBe(400);
    expect(res.body.error.message).toBe('Add your card again: the shop changed its payment account.');
  });
});
