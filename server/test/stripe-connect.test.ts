import { createHash } from 'node:crypto';
import Stripe from 'stripe';
import { describe, expect, it } from 'vitest';
import { configFromEnv, connectSwitch } from '../src/config.js';
import { connectionStatus, type StripeConnection } from '../src/stripeaccount.js';
import { CONNECT_PAGES_PER_IP, DISCONNECTED_MESSAGE } from '../src/stripeconnect.js';
import { RESPONSES } from './helpers/contract.js';
import { connectedShop, connectMode, PLATFORM_KEY, PUBLIC_BASE_URL, stripeError, useHarness } from './helpers/harness.js';

// Connecting the shop's own Stripe account from Settings (STRIPE_CONNECT=on): the three modes,
// the account (made once), Stripe's onboarding link and its way back, the status Settings
// shows, disconnecting, and the webhook for connected accounts.

// Monday Nov 2 2026, 9:00 AM PST.
const h = useHarness({ now: '2026-11-02T17:00:00Z' });
const owner = { owner: true } as const;
const sha256 = (text: string) => createHash('sha256').update(text).digest('hex');

const status = () => h.call('GET', '/api/owner/stripe', owner);
const connect = (body: unknown = { returnTo: 'app' }, auth: { owner?: boolean; headers?: Record<string, string> } = owner) =>
  h.call('POST', '/api/owner/stripe/connect', { ...auth, body });
const accountCreates = () => h.stripe.calls.filter((c) => c.method === 'accounts.create');
const links = () => h.stripe.calls.filter((c) => c.method === 'accountLinks.create').map((c) => c.params as Stripe.AccountLinkCreateParams);
/** The state in the last onboarding link's addresses. */
const lastState = () => new URL(links().at(-1)!.return_url!).searchParams.get('state')!;
const back = (page: 'return' | 'refresh', state: string | null, ip?: string) =>
  h.call('GET', `/api/stripe/connect/${page}${state === null ? '' : `?state=${encodeURIComponent(state)}`}`, ip ? { ip } : {});
/** The shop's account, made by the first POST /api/owner/stripe/connect. */
const onlyAccount = () => {
  expect(h.stripe.connectedAccounts.size).toBe(1);
  return [...h.stripe.connectedAccounts.keys()][0]!;
};
const stored = async () => (await h.database.pool.query(`SELECT value FROM settings WHERE key = 'stripe_connect'`)).rows[0]?.value;

/** A computer signed in with a code, for routes a computer may (or may not) use. */
async function computer(): Promise<Record<string, string>> {
  const code = (await h.call('POST', '/api/owner/computer-codes', owner)).body.code;
  const res = await h.call('POST', '/api/computer-sessions', { body: { code, name: 'Chrome on Mac' } });
  expect(res.status, res.text).toBe(201);
  return { authorization: `Bearer ${res.body.token}` };
}

describe('STRIPE_CONNECT', () => {
  it('"on" turns connect mode on; unset or off-words leave it off; anything else counts as on', () => {
    expect(configFromEnv({}).stripeConnect).toBe(false);
    expect(configFromEnv({ STRIPE_CONNECT: '' }).stripeConnect).toBe(false);
    expect(configFromEnv({ STRIPE_CONNECT: 'on' }).stripeConnect).toBe(true);
    expect(configFromEnv({ STRIPE_CONNECT: ' ON ' }).stripeConnect).toBe(true);
    for (const off of ['off', 'false', '0', 'no', 'OFF', 'none', 'disabled', 'direct']) expect(connectSwitch(off), off).toBe(false);
    // A typo must never send the shop's payments to the developer's own account.
    for (const on of ['true', '1', 'yes', 'onn']) expect(connectSwitch(on), on).toBe(true);
    expect(configFromEnv({ STRIPE_CONNECT_WEBHOOK_SECRET: 'whsec_x' }).stripeConnectWebhookSecret).toBe('whsec_x');
  });
});

describe('the three modes', () => {
  it('off: no Stripe key. Settings says so, and there is nothing to connect', async () => {
    const res = await status();
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ mode: 'off', status: 'off', accountId: null, livemode: null, message: "Stripe isn't set up on the server." });
    expect(RESPONSES['stripe-connection-off'].safeParse(res.body).success).toBe(true);
    const post = await connect();
    expect(post.status).toBe(409);
    expect(post.body.error).toEqual({ code: 'stripe_connect_off', message: "Stripe isn't set up on the server yet, so there's nothing to connect." });
    // Even with STRIPE_CONNECT on: without a key Stripe is off.
    h.config.stripeConnect = true;
    expect((await status()).body.mode).toBe('off');
    expect((await h.call('DELETE', '/api/owner/stripe/connect', owner)).status).toBe(409);
    expect(h.stripe.calls).toEqual([]);
    expect(h.stripe.keys).toEqual([]);
  });

  it('direct: the server’s own key, as before. Nothing to connect, and nothing is asked of Stripe', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    const res = await status();
    expect(res.body).toEqual({
      mode: 'direct',
      status: 'direct',
      accountId: null,
      businessName: null,
      livemode: false,
      chargesEnabled: false,
      payoutsEnabled: false,
      detailsSubmitted: false,
      requirementsDue: 0,
      message: "Card payments use this server's own Stripe key.",
      dashboardUrl: 'https://dashboard.stripe.com/',
      checkedAt: null,
    });
    h.config.stripeSecretKey = 'sk_live_fixture';
    expect((await status()).body.livemode).toBe(true);
    const post = await connect();
    expect(post.status).toBe(409);
    expect(post.body.error).toEqual({ code: 'stripe_connect_off', message: "This server uses its own Stripe key, so there's nothing to connect." });
    const del = await h.call('DELETE', '/api/owner/stripe/connect', owner);
    expect(del.body.error).toEqual({ code: 'stripe_connect_off', message: "This server uses its own Stripe key, so there's nothing to disconnect." });
    expect(h.stripe.calls).toEqual([]);
    expect((await h.call('GET', '/api/owner/me', owner)).body.connection).toEqual({ mode: 'direct', status: 'direct', businessName: null });
  });

  it('connect, before the shop connects: card payments, saving cards and no-show protection behave like off', async () => {
    connectMode(h);
    await h.call('PATCH', '/api/owner/no-show-settings', { ...owner, body: { enabled: true } });
    const res = await status();
    expect(res.body).toMatchObject({
      mode: 'connect',
      status: 'notConnected',
      accountId: null,
      message: 'Connect your Stripe account to take card payments in the app.',
    });
    expect((await h.call('GET', '/api/owner/me', owner)).body).toEqual({
      ok: true,
      stripe: { configured: false, mode: null, locationId: null },
      connection: { mode: 'connect', status: 'notConnected', businessName: null },
    });
    const off = { code: 'stripe_not_configured', message: 'Connect Stripe in Settings to take card payments.' };
    expect((await h.call('POST', '/api/owner/terminal/connection-token', owner)).body.error).toEqual(off);
    expect((await h.call('POST', '/api/owner/payments', { ...owner, body: { amountCents: 3500 } })).body.error).toEqual(off);
    // Clients get exactly the answer they get when Stripe is off.
    const checkout = await h.call('POST', '/api/cards/checkout', {
      headers: { 'x-card-token': Buffer.alloc(32, 7).toString('base64url') },
      body: { offeringId: 'flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a' },
    });
    const clientsOff = { code: 'stripe_not_configured', message: "Card payments aren't set up yet. Add the shop's Stripe key on the server." };
    expect(checkout.status).toBe(503);
    expect(checkout.body.error).toEqual(clientsOff);
    const save = await h.call('POST', '/api/cards', {
      headers: { 'x-card-token': Buffer.alloc(32, 7).toString('base64url') },
      body: { sessionId: 'cs_test_abc' },
    });
    expect(save.body.error).toEqual(clientsOff);
    // The policy needs no card, and booking works without one.
    const policy = await h.call('GET', '/api/no-show-policy?serviceId=haircut&barberId=any');
    expect(policy.body).toMatchObject({ required: false, policyText: null, warning: null });
    const booking = await h.call('POST', '/api/appointments', {
      body: { serviceId: 'haircut', barberId: 'any', start: '2026-11-03T18:00:00Z', customer: { name: 'Walk Up', phone: '4425550160' } },
    });
    expect(booking.status, booking.text).toBe(201);
    expect(booking.body.appointment.card).toBeNull();
    expect(h.stripe.calls).toEqual([]);
  });
});

describe('POST /api/owner/stripe/connect', () => {
  it('makes the shop’s own account (controller properties, card payments) and an onboarding link', async () => {
    connectMode(h);
    const res = await connect();
    expect(res.status, res.text).toBe(201);
    expect(RESPONSES['stripe-connect-link'].safeParse(res.body).success).toBe(true);
    const account = onlyAccount();
    expect(res.body).toEqual({ url: `https://connect.stripe.com/setup/s/${account}/fixture000002`, expiresAt: '2026-11-02T17:05:00Z' });
    expect(accountCreates()).toEqual([
      {
        method: 'accounts.create',
        params: {
          controller: {
            stripe_dashboard: { type: 'full' },
            fees: { payer: 'account' },
            losses: { payments: 'stripe' },
            requirement_collection: 'stripe',
          },
          capabilities: { card_payments: { requested: true }, transfers: { requested: true } },
          country: 'US',
          business_profile: { name: 'Izzy Clipz Barbershop', mcc: '7241', url: PUBLIC_BASE_URL, support_phone: '+14423413053' },
          metadata: { izzy_clipz: 'shop' },
        },
        // One key per mode and per connection: a lost answer, tried again, gets the same account.
        options: { idempotencyKey: 'izzy-clipz-shop-account-test-0' },
      },
    ]);
    // The platform's own calls: no Stripe-Account header.
    const call = h.stripe.calls.find((c) => c.method === 'accountLinks.create')!;
    expect(call.options).toBeUndefined();
    const state = lastState();
    expect(state).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(call.params).toEqual({
      account,
      type: 'account_onboarding',
      refresh_url: `${PUBLIC_BASE_URL}/api/stripe/connect/refresh?state=${state}`,
      return_url: `${PUBLIC_BASE_URL}/api/stripe/connect/return?state=${state}`,
      collection_options: { fields: 'eventually_due' },
    });
    // Only the state's SHA-256 is kept, for an hour.
    const { rows } = await h.database.pool.query('SELECT * FROM stripe_connect_states');
    expect(rows).toEqual([
      { state_hash: sha256(state), return_to: 'app', created_at: new Date('2026-11-02T17:00:00Z'), expires_at: new Date('2026-11-02T18:00:00Z') },
    ]);
    expect(JSON.stringify(rows)).not.toContain(state);
    // The id is stored with what the new account says.
    expect(await stored()).toEqual({
      accountId: account,
      livemode: false,
      connectedAt: '2026-11-02T17:00:00Z',
      locationId: null,
      chargesEnabled: false,
      payoutsEnabled: false,
      detailsSubmitted: false,
      requirementsDue: 3,
      disabledReason: 'requirements.past_due',
      businessName: 'Izzy Clipz Barbershop',
      checkedAt: '2026-11-02T17:00:00Z',
    });
  });

  it('never makes a second account: again later, or many at once from the app and the website', async () => {
    connectMode(h);
    expect((await connect()).status).toBe(201);
    const account = onlyAccount();
    h.advance(10);
    const again = await connect({ returnTo: 'web' });
    expect(again.status).toBe(201);
    expect(accountCreates()).toHaveLength(1);
    expect(links().map((l) => l.account)).toEqual([account, account]);
    // Each link has a state of its own, with its own way back.
    const states = (await h.database.pool.query('SELECT return_to FROM stripe_connect_states ORDER BY created_at')).rows;
    expect(states).toEqual([{ return_to: 'app' }, { return_to: 'web' }]);

    // A fresh start, with several taps landing together.
    await h.database.pool.query(`DELETE FROM settings WHERE key = 'stripe_connect'`);
    h.stripe.calls.length = 0;
    const session = await computer();
    const results = await Promise.all([
      connect(),
      connect({ returnTo: 'web' }, { headers: session }),
      connect(),
      connect({ returnTo: 'web' }),
      connect(),
    ]);
    expect(results.map((r) => r.status)).toEqual([201, 201, 201, 201, 201]);
    expect(accountCreates()).toHaveLength(1);
    const second = (await stored()).accountId;
    expect(new Set(links().map((l) => l.account))).toEqual(new Set([second]));
  });

  it('a computer signed in with a code may connect (from the website’s settings)', async () => {
    connectMode(h);
    const res = await connect({ returnTo: 'web' }, { headers: await computer() });
    expect(res.status, res.text).toBe(201);
  });

  it('needs PUBLIC_BASE_URL (https with a live key), and a JSON body with a known returnTo', async () => {
    connectMode(h);
    h.config.publicBaseUrl = undefined;
    const missing = await connect();
    expect(missing.status).toBe(503);
    expect(missing.body.error.code).toBe('stripe_not_configured');
    expect(missing.body.error.message).toContain('PUBLIC_BASE_URL');
    h.config.publicBaseUrl = 'not a url';
    expect((await connect()).status).toBe(503);
    h.config.stripeSecretKey = 'sk_live_platform';
    h.config.publicBaseUrl = 'http://izzy-clipz-api.test';
    expect((await connect()).status).toBe(503);
    expect(h.stripe.calls).toEqual([]);
    // With a test key, http (a local server) works; Stripe only gets an https address as the website.
    h.config.stripeSecretKey = PLATFORM_KEY;
    h.config.publicBaseUrl = 'http://localhost:3000/';
    const local = await connect();
    expect(local.status, local.text).toBe(201);
    expect((accountCreates()[0]!.params as Stripe.AccountCreateParams).business_profile).not.toHaveProperty('url');
    expect(links()[0]!.return_url).toMatch(/^http:\/\/localhost:3000\/api\/stripe\/connect\/return\?state=/);

    expect((await connect({ returnTo: 'phone' })).status).toBe(400);
    expect((await connect([])).status).toBe(400);
    const noJson = await h.call('POST', '/api/owner/stripe/connect', { ...owner, rawBody: 'returnTo=app', headers: { 'content-type': 'application/x-www-form-urlencoded' } });
    expect(noJson.status).toBe(415);
    // returnTo is optional, and so is the body: the app's way back.
    expect((await connect({})).status).toBe(201);
    expect((await h.call('POST', '/api/owner/stripe/connect', owner)).status).toBe(201);
    const ways = (await h.database.pool.query('SELECT return_to FROM stripe_connect_states')).rows.map((r) => r.return_to);
    expect(ways).toEqual(['app', 'app', 'app']);
  });

  it('a Stripe failure is a plain 500, nothing is stored, and the next try makes the account', async () => {
    connectMode(h);
    h.stripe.nextError = stripeError('StripeConnectionError', {}, 'socket hang up');
    const res = await connect();
    expect(res.status).toBe(500);
    expect(res.body.error).toEqual({ code: 'server_error', message: "We couldn't reach Stripe. Please try again." });
    expect(h.logs[0]).toMatchObject({ level: 'error', message: 'Stripe create account failed' });
    expect(await stored()).toBeUndefined();
    expect((await connect()).status).toBe(201);
    expect(h.stripe.connectedAccounts.size).toBe(1);
  });

  it('a try whose answer was lost gets the same account when tried again; after a disconnect, a new one', async () => {
    connectMode(h);
    h.stripe.loseNextAccountAnswer = true;
    const lost = await connect();
    expect(lost.status).toBe(500);
    expect(await stored()).toBeUndefined();
    // Stripe made it; the same key gets it back instead of a second one.
    expect(h.stripe.connectedAccounts.size).toBe(1);
    const again = await connect();
    expect(again.status, again.text).toBe(201);
    const account = onlyAccount();
    expect((await stored()).accountId).toBe(account);
    expect(accountCreates().map((c) => c.options)).toEqual([
      { idempotencyKey: 'izzy-clipz-shop-account-test-0' },
      { idempotencyKey: 'izzy-clipz-shop-account-test-0' },
    ]);
    await h.call('DELETE', '/api/owner/stripe/connect', owner);
    await connect();
    expect(accountCreates().at(-1)!.options).toEqual({ idempotencyKey: 'izzy-clipz-shop-account-test-1' });
    expect(h.stripe.connectedAccounts.size).toBe(2);
  });

  it('a lost try with other details (PUBLIC_BASE_URL changed since) is made afresh rather than stuck', async () => {
    connectMode(h);
    h.stripe.loseNextAccountAnswer = true;
    expect((await connect()).status).toBe(500);
    h.config.publicBaseUrl = 'https://izzyclipz.example';
    const res = await connect();
    expect(res.status, res.text).toBe(201);
    expect(h.stripe.connectedAccounts.size).toBe(2);
    expect(accountCreates().at(-1)!.options).toEqual({ idempotencyKey: `izzy-clipz-shop-account-test-0-${Date.parse('2026-11-02T17:00:00Z')}` });
    expect(h.logs.some((l) => l.message === 'Stripe create account failed' && l.details?.type === 'StripeIdempotencyError')).toBe(true);
  });

  it('a key of the other mode needs an account of its own: a test-mode connection doesn’t count with a live key', async () => {
    const testAccount = await connectedShop(h);
    h.config.stripeSecretKey = 'sk_live_platform';
    expect((await status()).body).toMatchObject({ status: 'notConnected', accountId: null });
    expect((await h.call('POST', '/api/owner/terminal/connection-token', owner)).status).toBe(503);
    expect((await connect()).status).toBe(201);
    expect(accountCreates()).toHaveLength(2);
    expect(await stored()).toMatchObject({ livemode: true });
    expect((await stored()).accountId).not.toBe(testAccount);
  });
});

describe('the status Settings shows (GET /api/owner/stripe)', () => {
  it('is read live from Stripe and cached: needsInfo, pending, active, restricted', async () => {
    connectMode(h);
    await connect();
    const account = onlyAccount();
    h.stripe.calls.length = 0;
    h.advance(1);
    const fresh = await status();
    expect(fresh.body).toMatchObject({ status: 'needsInfo', requirementsDue: 3, message: 'Finish setting up Stripe to take card payments.', checkedAt: '2026-11-02T17:01:00Z' });
    expect(h.stripe.calls).toEqual([{ method: 'accounts.retrieve', params: { id: account }, options: undefined }]);

    // Details sent, something still due.
    h.stripe.setAccount(account, { details_submitted: true, currently_due: ['external_account'], disabled_reason: null });
    expect((await status()).body).toMatchObject({ status: 'needsInfo', detailsSubmitted: true, requirementsDue: 1 });
    // Nothing due: Stripe is checking.
    h.stripe.setAccount(account, { currently_due: [], disabled_reason: 'requirements.pending_verification' });
    expect((await status()).body).toMatchObject({ status: 'pending', message: 'Stripe is checking your details. This usually takes a few minutes.' });
    // Charges on, payouts not yet.
    h.stripe.setAccount(account, { charges_enabled: true, disabled_reason: null, name: 'Izzy Clipz' });
    expect((await status()).body).toMatchObject({
      status: 'active',
      chargesEnabled: true,
      payoutsEnabled: false,
      businessName: 'Izzy Clipz',
      message: 'Connected. Card payments are on. Add your bank in Stripe to get paid out.',
    });
    h.stripe.setAccount(account, { payouts_enabled: true });
    expect((await status()).body.message).toBe('Connected. Card payments are on. Payouts to your bank are on.');
    // Paused by Stripe.
    h.stripe.setAccount(account, { charges_enabled: false, disabled_reason: 'rejected.other' });
    expect((await status()).body).toMatchObject({ status: 'restricted', message: 'Stripe paused card payments: open Stripe to fix it.' });
    // /api/owner/me reads the cache, without asking Stripe.
    h.stripe.calls.length = 0;
    expect((await h.call('GET', '/api/owner/me', owner)).body.connection).toEqual({ mode: 'connect', status: 'restricted', businessName: 'Izzy Clipz' });
    expect(h.stripe.calls).toEqual([]);
  });

  it('when the shop took the platform’s access away, the account is forgotten and Settings asks to connect again', async () => {
    const account = await connectedShop(h);
    const revoked = () =>
      stripeError(
        'StripePermissionError',
        { statusCode: 403 },
        `The provided key 'sk_test_…' does not have access to account '${account}' (or that account does not exist). Application access may have been revoked.`,
      );
    h.stripe.nextError = revoked();
    const res = await status();
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ status: 'notConnected', accountId: null, message: 'Connect your Stripe account to take card payments in the app.' });
    expect(await stored()).toBeUndefined();
    expect(h.logs.some((l) => l.level === 'warn' && l.details?.accountId === account)).toBe(true);
    expect((await h.call('POST', '/api/owner/payments', { ...owner, body: { amountCents: 3500 } })).status).toBe(503);
    // Connecting again makes a new account (not the old one, whose access is gone).
    expect((await connect()).status).toBe(201);
    expect(accountCreates().at(-1)!.options).toEqual({ idempotencyKey: 'izzy-clipz-shop-account-test-1' });
    expect((await stored()).accountId).not.toBe(account);
  });

  it('when Stripe can’t be reached, answers from the cache (and logs it)', async () => {
    const account = await connectedShop(h);
    h.advance(30);
    h.stripe.nextError = stripeError('StripeConnectionError', {}, 'socket hang up');
    const res = await status();
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ status: 'active', accountId: account, checkedAt: '2026-11-02T17:00:00Z' });
    expect(h.logs.at(-1)).toMatchObject({ level: 'error', message: 'Stripe retrieve account failed' });
  });

  it('the status rules, in order', () => {
    const base: StripeConnection = {
      accountId: 'acct_x',
      livemode: false,
      connectedAt: '',
      locationId: null,
      chargesEnabled: false,
      payoutsEnabled: false,
      detailsSubmitted: true,
      requirementsDue: 0,
      disabledReason: null,
      businessName: null,
      checkedAt: null,
    };
    expect(connectionStatus(null)).toBe('notConnected');
    expect(connectionStatus({ ...base, detailsSubmitted: false })).toBe('needsInfo');
    expect(connectionStatus({ ...base, detailsSubmitted: false, disabledReason: 'rejected.other' })).toBe('needsInfo');
    expect(connectionStatus({ ...base, requirementsDue: 2 })).toBe('needsInfo');
    expect(connectionStatus({ ...base, disabledReason: 'requirements.past_due' })).toBe('needsInfo');
    expect(connectionStatus(base)).toBe('pending');
    expect(connectionStatus({ ...base, disabledReason: 'requirements.pending_verification' })).toBe('pending');
    expect(connectionStatus({ ...base, disabledReason: 'under_review' })).toBe('restricted');
    expect(connectionStatus({ ...base, disabledReason: 'rejected.fraud', requirementsDue: 1 })).toBe('restricted');
    expect(connectionStatus({ ...base, chargesEnabled: true, disabledReason: 'other', requirementsDue: 4 })).toBe('active');
  });
});

describe('GET /api/stripe/connect/return and /refresh (Stripe sends the browser back)', () => {
  it('return: checks the account with Stripe, then back to the app with its status (the link works more than once)', async () => {
    connectMode(h);
    await connect();
    const account = onlyAccount();
    const state = lastState();
    h.stripe.activateAccount(account);
    h.advance(4);
    const res = await back('return', state);
    expect(res.status).toBe(302);
    expect(res.headers.get('location')).toBe('izzyclipzbusiness://stripe-connected?status=active');
    expect(res.headers.get('cache-control')).toBe('no-store');
    expect(res.headers.get('referrer-policy')).toBe('no-referrer');
    // Read from Stripe, and now that it takes card payments, its Terminal location is made.
    expect(h.stripe.calls.slice(-2).map((c) => c.method)).toEqual(['accounts.retrieve', 'terminal.locations.create']);
    expect(await stored()).toMatchObject({ chargesEnabled: true, checkedAt: '2026-11-02T17:04:00Z', locationId: [...h.stripe.locations.keys()][0] });
    // Loaded again (the browser went back): the same answer until the state expires.
    h.advance(50);
    expect((await back('return', state)).headers.get('location')).toBe('izzyclipzbusiness://stripe-connected?status=active');
  });

  it('return to the website: its Business settings, with the status', async () => {
    connectMode(h);
    await connect({ returnTo: 'web' });
    const res = await back('return', lastState());
    expect(res.status).toBe(302);
    expect(res.headers.get('location')).toBe(`${PUBLIC_BASE_URL}/business/settings?stripe=needsInfo`);
    expect(res.text).toContain(`href="${PUBLIC_BASE_URL}/business/settings?stripe=needsInfo"`);
  });

  it('when Stripe can’t be reached, still goes back, with the status from the cache', async () => {
    connectMode(h);
    await connect();
    h.stripe.nextError = stripeError('StripeAPIError', { statusCode: 500 }, 'Stripe had a problem');
    const res = await back('return', lastState());
    expect(res.headers.get('location')).toBe('izzyclipzbusiness://stripe-connected?status=needsInfo');
    expect(h.logs.at(-1)).toMatchObject({ level: 'error', message: 'Stripe retrieve account failed' });
  });

  it('an expired, unknown, malformed or missing state shows a friendly page (400, never cached)', async () => {
    connectMode(h);
    await connect();
    const state = lastState();
    h.advance(61);
    for (const [page, s] of [
      ['return', state],
      ['refresh', state],
      ['return', Buffer.alloc(32, 9).toString('base64url')],
      ['return', 'short'],
      ['refresh', `${state}x`],
      ['return', null],
      ['refresh', null],
    ] as const) {
      const res = await back(page, s);
      expect(res.status, `${page} ${s}`).toBe(400);
      expect(res.headers.get('content-type')).toBe('text/html; charset=utf-8');
      expect(res.headers.get('cache-control')).toBe('no-store');
      expect(res.text).toContain('This link has expired. Go back to Izzy Clipz Business and tap Connect Stripe again.');
    }
    // Nothing went to Stripe for any of them.
    expect(h.stripe.calls.filter((c) => c.method !== 'accounts.create' && c.method !== 'accountLinks.create')).toEqual([]);
  });

  it('refresh: a new link and a new state with the same way back, then on to Stripe', async () => {
    connectMode(h);
    await connect({ returnTo: 'web' });
    const first = lastState();
    h.advance(6);
    const res = await back('refresh', first);
    expect(res.status).toBe(302);
    const second = lastState();
    expect(second).not.toBe(first);
    expect(res.headers.get('location')).toBe(`https://connect.stripe.com/setup/s/${onlyAccount()}/fixture000003`);
    const rows = (await h.database.pool.query('SELECT state_hash, return_to FROM stripe_connect_states ORDER BY created_at')).rows;
    expect(rows).toEqual([
      { state_hash: sha256(first), return_to: 'web' },
      { state_hash: sha256(second), return_to: 'web' },
    ]);
    expect(accountCreates()).toHaveLength(1);
    // Disconnected meanwhile: nothing to link to.
    await h.call('DELETE', '/api/owner/stripe/connect', owner);
    expect((await back('refresh', second)).status).toBe(400);
  });

  it('refresh when Stripe can’t make the link: a friendly page saying to try again', async () => {
    connectMode(h);
    await connect();
    h.stripe.nextError = stripeError('StripeConnectionError', {}, 'socket hang up');
    const res = await back('refresh', lastState());
    expect(res.status).toBe(500);
    expect(res.text).toContain("We couldn't reach Stripe. Go back to Izzy Clipz Business and tap Connect Stripe again.");
  });

  it('both pages allow 20 visits per network per 10 minutes, then a friendly 429', async () => {
    connectMode(h);
    await connect();
    const state = lastState();
    for (let i = 0; i < CONNECT_PAGES_PER_IP; i++) {
      expect((await back(i % 2 === 0 ? 'return' : 'refresh', state)).status, `visit ${i + 1}`).toBe(302);
    }
    const limited = await back('return', state);
    expect(limited.status).toBe(429);
    expect(limited.headers.get('retry-after')).toBe('600');
    expect(limited.headers.get('content-type')).toBe('text/html; charset=utf-8');
    expect(limited.text).toContain('Too many tries from this network.');
    expect((await back('refresh', 'guess')).status).toBe(429);
    expect((await back('return', state, '198.51.100.30')).status).toBe(302);
    h.advance(11);
    expect((await back('return', state)).status).toBe(302);
  });
});

describe('DELETE /api/owner/stripe/connect', () => {
  it('forgets the account (it stays open at Stripe), with the owner key only', async () => {
    const account = await connectedShop(h);
    const session = await computer();
    const refused = await h.call('DELETE', '/api/owner/stripe/connect', { headers: session });
    expect(refused.status).toBe(403);
    expect(refused.body.error.code).toBe('forbidden');
    expect(await stored()).toMatchObject({ accountId: account });

    const res = await h.call('DELETE', '/api/owner/stripe/connect', owner);
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ mode: 'connect', status: 'notConnected', accountId: null, message: DISCONNECTED_MESSAGE });
    expect(RESPONSES['stripe-connection-disconnected'].safeParse(res.body).success).toBe(true);
    expect(await stored()).toBeUndefined();
    expect((await h.database.pool.query('SELECT count(*)::int AS n FROM stripe_connect_states')).rows[0].n).toBe(0);
    // Nothing was deleted at Stripe.
    expect(h.stripe.connectedAccounts.has(account)).toBe(true);
    expect((await status()).body.status).toBe('notConnected');
    // Again: still nothing connected, no error.
    expect((await h.call('DELETE', '/api/owner/stripe/connect', owner)).status).toBe(200);
    // Connecting again makes a new account.
    expect((await connect()).status).toBe(201);
    expect(h.stripe.connectedAccounts.size).toBe(2);
  });
});

describe('POST /api/stripe/webhook with Stripe Connect', () => {
  const WEBHOOK_SECRET = 'whsec_fixture_account';
  const CONNECT_SECRET = 'whsec_fixture_connect';
  function event(type: string, object: Record<string, unknown>, account?: string) {
    return JSON.stringify({
      id: 'evt_fixture_connect',
      object: 'event',
      api_version: '2026-10-28.endive',
      created: Math.floor(Date.now() / 1000),
      type,
      livemode: false,
      pending_webhooks: 1,
      request: { id: null, idempotency_key: null },
      data: { object },
      ...(account ? { account } : {}),
    });
  }
  const sign = (payload: string, secret: string) => Stripe.webhooks.generateTestHeaderString({ payload, secret });
  const send = (payload: string, secret: string) =>
    h.call('POST', '/api/stripe/webhook', { rawBody: payload, headers: { 'content-type': 'application/json', 'stripe-signature': sign(payload, secret) } });

  async function walkInPayment() {
    const appointment = (
      await h.call('POST', '/api/owner/appointments', {
        ...owner,
        body: { offeringId: 'flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a', start: '2026-11-02T18:00:00Z', customer: { name: 'Walk-in' } },
      })
    ).body.appointment;
    const payment = await h.call('POST', '/api/owner/payments', { ...owner, body: { amountCents: 3500, appointmentId: appointment.id } });
    expect(payment.status, payment.text).toBe(201);
    return { appointment, paymentIntentId: payment.body.paymentIntentId as string };
  }
  const paymentOf = async () => (await h.call('GET', '/api/owner/appointments?date=2026-11-02', owner)).body.appointments[0].payment;

  it('takes either secret: the shop’s own endpoint’s, or the platform’s Connect endpoint’s', async () => {
    const account = await connectedShop(h);
    const { paymentIntentId } = await walkInPayment();
    h.config.stripeConnectWebhookSecret = CONNECT_SECRET;
    const processing = event('payment_intent.processing', { object: 'payment_intent', id: paymentIntentId, status: 'processing' }, account);
    expect((await send(processing, CONNECT_SECRET)).status).toBe(200);
    expect((await send(processing, 'whsec_someone_else')).status).toBe(400);
    h.config.stripeWebhookSecret = WEBHOOK_SECRET;
    h.stripe.succeed(paymentIntentId);
    const succeeded = event('payment_intent.succeeded', { object: 'payment_intent', id: paymentIntentId, status: 'succeeded' }, account);
    const res = await send(succeeded, WEBHOOK_SECRET);
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ received: true });
    expect(await paymentOf()).toMatchObject({ status: 'paid', amountCents: 3500 });
    // Neither secret set: the webhook isn't set up.
    h.config.stripeWebhookSecret = undefined;
    h.config.stripeConnectWebhookSecret = undefined;
    expect((await send(succeeded, CONNECT_SECRET)).status).toBe(503);
  });

  it('ignores events from a connected account that isn’t the shop’s (200, nothing changes)', async () => {
    await connectedShop(h);
    const { paymentIntentId } = await walkInPayment();
    h.config.stripeConnectWebhookSecret = CONNECT_SECRET;
    h.stripe.succeed(paymentIntentId);
    const foreign = event('payment_intent.succeeded', { object: 'payment_intent', id: paymentIntentId, status: 'succeeded' }, 'acct_SomeoneElse01');
    const res = await send(foreign, CONNECT_SECRET);
    expect(res.status).toBe(200);
    expect(await paymentOf()).toMatchObject({ status: 'unpaid' });
    expect((await h.call('GET', '/api/owner/payments?date=2026-11-02', owner)).body.payments[0].status).toBe('requires_payment_method');
  });

  it('a payment made on the shop’s earlier account is still followed after it connected another', async () => {
    const first = await connectedShop(h);
    const { paymentIntentId } = await walkInPayment();
    await h.call('DELETE', '/api/owner/stripe/connect', owner);
    await connectedShop(h);
    h.config.stripeConnectWebhookSecret = CONNECT_SECRET;
    h.stripe.succeed(paymentIntentId);
    await send(event('payment_intent.succeeded', { object: 'payment_intent', id: paymentIntentId, status: 'succeeded' }, first), CONNECT_SECRET);
    expect(await paymentOf()).toMatchObject({ status: 'paid' });
  });

  it('account.updated for the shop’s account refreshes the cache; for any other account it’s ignored', async () => {
    connectMode(h);
    await connect();
    const account = onlyAccount();
    h.config.stripeConnectWebhookSecret = CONNECT_SECRET;
    h.stripe.activateAccount(account);
    h.stripe.calls.length = 0;
    h.advance(7);
    const updated = event('account.updated', { object: 'account', id: account, charges_enabled: true }, account);
    expect((await send(updated, CONNECT_SECRET)).status).toBe(200);
    expect(h.stripe.calls.map((c) => c.method)).toEqual(['accounts.retrieve', 'terminal.locations.create']);
    expect(h.stripe.calls[0]).toEqual({ method: 'accounts.retrieve', params: { id: account }, options: undefined });
    expect(await stored()).toMatchObject({ chargesEnabled: true, payoutsEnabled: true, checkedAt: '2026-11-02T17:07:00Z' });
    expect((await h.call('GET', '/api/owner/me', owner)).body.connection).toEqual({ mode: 'connect', status: 'active', businessName: 'Izzy Clipz Barbershop' });

    h.stripe.calls.length = 0;
    const other = event('account.updated', { object: 'account', id: 'acct_SomeoneElse01' }, 'acct_SomeoneElse01');
    expect((await send(other, CONNECT_SECRET)).status).toBe(200);
    // The platform's own account (no `account` on the event).
    h.config.stripeWebhookSecret = WEBHOOK_SECRET;
    expect((await send(event('account.updated', { object: 'account', id: 'acct_ThePlatform01' }), WEBHOOK_SECRET)).status).toBe(200);
    expect(h.stripe.calls).toEqual([]);
  });

  it('account.application.deauthorized for the shop’s account forgets it; for another account it’s ignored', async () => {
    const account = await connectedShop(h);
    h.config.stripeConnectWebhookSecret = CONNECT_SECRET;
    const other = event('account.application.deauthorized', { object: 'application', id: 'ca_fixture' }, 'acct_SomeoneElse01');
    expect((await send(other, CONNECT_SECRET)).status).toBe(200);
    expect(await stored()).toMatchObject({ accountId: account });
    const gone = event('account.application.deauthorized', { object: 'application', id: 'ca_fixture' }, account);
    expect((await send(gone, CONNECT_SECRET)).status).toBe(200);
    expect(await stored()).toBeUndefined();
    expect((await status()).body.status).toBe('notConnected');
  });

  it('account.updated for an account the platform lost access to: forgotten, and 200 (Stripe needn’t send it again)', async () => {
    const account = await connectedShop(h);
    h.config.stripeConnectWebhookSecret = CONNECT_SECRET;
    h.stripe.nextError = stripeError('StripePermissionError', { statusCode: 403 }, `The provided key does not have access to account '${account}'.`);
    const res = await send(event('account.updated', { object: 'account', id: account }, account), CONNECT_SECRET);
    expect(res.status).toBe(200);
    expect(await stored()).toBeUndefined();
  });

  it('account.updated when Stripe can’t be reached: 500, so Stripe sends it again', async () => {
    connectMode(h);
    await connect();
    const account = onlyAccount();
    h.config.stripeConnectWebhookSecret = CONNECT_SECRET;
    h.stripe.nextError = stripeError('StripeConnectionError', {}, 'socket hang up');
    const res = await send(event('account.updated', { object: 'account', id: account }, account), CONNECT_SECRET);
    expect(res.status).toBe(500);
  });

  it('account.updated in direct mode is ignored', async () => {
    h.config.stripeSecretKey = 'sk_test_fixture';
    h.config.stripeWebhookSecret = WEBHOOK_SECRET;
    expect((await send(event('account.updated', { object: 'account', id: 'acct_TheShop00001' }), WEBHOOK_SECRET)).status).toBe(200);
    expect(h.stripe.calls).toEqual([]);
  });
});
