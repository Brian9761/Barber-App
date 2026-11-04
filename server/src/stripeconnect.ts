import { randomBytes } from 'node:crypto';
import type Stripe from 'stripe';
import { z } from 'zod';
import { requireOwner, sha256Hex } from './auth.js';
import type { Config } from './config.js';
import type { Queryable } from './db.js';
import type { Deps } from './deps.js';
import { ApiError, baseOf, htmlPage, httpUrl, json, readOptionalJsonObject, redirect } from './http.js';
import { hit, ipKey } from './ratelimit.js';
import type { Context } from './router.js';
import {
  accessRevoked,
  ACCOUNT_ID_RE,
  CONNECT_SETTINGS_KEY,
  CONNECT_STRIPE_MESSAGE,
  connectionForKey,
  connectionMessage,
  connectionStatus,
  currentConnection,
  keyFingerprint,
  keyLivemode,
  loadConnections,
  OTHER_MODE_SETTINGS_KEY,
  parseConnection,
  platformStripe,
  requestOptions,
  shopStripe,
  stripeFailure,
  stripeSetup,
  type ConnectionStatus,
  type ShopStripe,
  type StripeConnection,
  type StripeErrorLike,
  type StripeSetup,
} from './stripeaccount.js';
import { formatInstant } from './time.js';
import { parse } from './validation.js';

// Connecting the shop's own Stripe account from Settings (connect mode, STRIPE_CONNECT=on),
// with Stripe Connect and Account Links onboarding:
//
// 1. POST /api/owner/stripe/connect { returnTo: "app" | "web" } makes the shop's account the
//    first time (Accounts v1 with controller properties, like a Standard account: the full
//    Stripe Dashboard, the shop pays Stripe's fees, Stripe covers losses and collects what it
//    needs), stores its id, and answers with a link to Stripe's own onboarding, where the owner
//    signs in or signs up and finishes setting up.
// 2. Stripe sends the browser back to GET /api/stripe/connect/return?state=… (or, when the link
//    has expired, …/refresh?state=…, which makes a new link). Each way back has a state of its
//    own, 32 random bytes kept as a SHA-256 for an hour: the return page's can be loaded again,
//    the refresh page's works once. The return page reads the account's status from Stripe and
//    sends the owner on to the app (izzyclipzbusiness://stripe-connected?status=…) or to the
//    website's Business settings.
// 3. GET /api/owner/stripe is what Settings shows, read live from Stripe; the account.updated
//    webhook keeps the cache fresh too.
//
// From then on Tap to Pay, saved cards and fees go to that account (stripeaccount.ts).

export const SHOP_NAME = 'Izzy Clipz Barbershop';
const SHOP_SUPPORT_PHONE = '+14423413053';
/** Stripe's merchant category for barber and beauty shops. */
const SHOP_MCC = '7241';
/**
 * The shop's address for its Terminal location: the Kit's ShopInfo
 * (IzzyClipzData.izzyClipz.address). Update both together.
 */
export const SHOP_ADDRESS: Stripe.Terminal.LocationCreateParams.Address = {
  line1: '1919 Mission Ave',
  line2: 'Ste 105',
  city: 'Oceanside',
  state: 'CA',
  postal_code: '92058',
  country: 'US',
};

/** The Business app's own URL scheme, which its sign-in sheet waits for. */
export const BUSINESS_APP_SCHEME = 'izzyclipzbusiness';
export const CONNECT_STATE_MINUTES = 60;
/** Stripe's pages back (return and refresh) per network per 10 minutes. */
export const CONNECT_PAGES_PER_IP = 20;
const DASHBOARD_URL = 'https://dashboard.stripe.com/';
/** One account, one Terminal location: making either is serialized with this lock. */
const CONNECT_LOCK = 'izzy-clipz-stripe-connect';
const STATE_RE = /^[A-Za-z0-9_-]{43}$/;

export const DISCONNECTED_MESSAGE =
  "Stripe is disconnected. Your Stripe account isn't closed: you can still sign in to Stripe to see its payments and payouts.";
const EXPIRED_MESSAGE = 'This link has expired. Go back to Izzy Clipz Business and tap Connect Stripe again.';
const NO_BASE_URL_MESSAGE =
  "Stripe can't send you back to the app until the server's PUBLIC_BASE_URL is set (its https address). Set it on the server, then try again.";

/** How many times the shop's account was forgotten (disconnected, or its access taken away): see `accountIdempotencyKey`. */
const HISTORY_SETTINGS_KEY = 'stripe_connect_history';

/** The connection as Settings shows it (GET /api/owner/stripe and the connect routes). */
export interface StripeConnectionJSON {
  mode: StripeSetup;
  status: ConnectionStatus;
  accountId: string | null;
  businessName: string | null;
  livemode: boolean | null;
  chargesEnabled: boolean;
  payoutsEnabled: boolean;
  detailsSubmitted: boolean;
  requirementsDue: number;
  message: string;
  dashboardUrl: string;
  checkedAt: string | null;
}

export function connectionJSON(setup: StripeSetup, stored: StripeConnection | null, config: Config): StripeConnectionJSON {
  const connection = setup === 'connect' ? stored : null;
  const status: ConnectionStatus = setup === 'connect' ? connectionStatus(connection) : setup;
  return {
    mode: setup,
    status,
    accountId: connection?.accountId ?? null,
    businessName: connection?.businessName ?? null,
    livemode: setup === 'connect' ? (connection?.livemode ?? null) : setup === 'direct' ? keyLivemode(config) : null,
    chargesEnabled: connection?.chargesEnabled ?? false,
    payoutsEnabled: connection?.payoutsEnabled ?? false,
    detailsSubmitted: connection?.detailsSubmitted ?? false,
    requirementsDue: connection?.requirementsDue ?? 0,
    message: connectionMessage(status, connection),
    dashboardUrl: DASHBOARD_URL,
    checkedAt: connection?.checkedAt ?? null,
  };
}

/** GET /api/owner/me's short version, from the cache: `{ mode, status, businessName }`. */
export function connectionSummary(setup: StripeSetup, connection: StripeConnection | null) {
  return {
    mode: setup,
    status: setup === 'connect' ? connectionStatus(connection) : setup,
    businessName: setup === 'connect' ? (connection?.businessName ?? null) : null,
  };
}

/** What the cache keeps of Stripe's Account. */
function accountStatus(account: Stripe.Account) {
  const due = new Set([...(account.requirements?.currently_due ?? []), ...(account.requirements?.past_due ?? [])]);
  const name = account.business_profile?.name ?? account.settings?.dashboard?.display_name ?? null;
  return {
    chargesEnabled: account.charges_enabled === true,
    payoutsEnabled: account.payouts_enabled === true,
    detailsSubmitted: account.details_submitted === true,
    requirementsDue: due.size,
    disabledReason: account.requirements?.disabled_reason ?? null,
    businessName: name ? name.slice(0, 200) : null,
  };
}

async function lockConnect(tx: Queryable): Promise<void> {
  await tx.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [CONNECT_LOCK]);
}

/**
 * Stores a new connection (made with the key's mode; the caller holds the lock). One of the other
 * mode (test or live) stored before is kept aside rather than replaced, so a tap on Connect Stripe
 * while the server briefly has a test key can never take the place of the live account.
 */
async function saveConnection(tx: Queryable, connection: StripeConnection, now: Date): Promise<void> {
  await tx.query(
    `INSERT INTO settings (key, value, updated_at)
     SELECT $2, value, $3 FROM settings WHERE key = $1 AND (value->>'livemode')::boolean IS DISTINCT FROM $4
     ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = EXCLUDED.updated_at`,
    [CONNECT_SETTINGS_KEY, OTHER_MODE_SETTINGS_KEY, now, connection.livemode],
  );
  await tx.query(
    `INSERT INTO settings (key, value, updated_at) VALUES ($1, $2::jsonb, $3)
     ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = EXCLUDED.updated_at`,
    [CONNECT_SETTINGS_KEY, JSON.stringify(connection), now],
  );
}

/**
 * Merges `fields` into the stored connection for `accountId`, only while it's still stored (a
 * disconnect, or a new account, that happened meanwhile wins). Null when it isn't.
 */
async function updateConnection(db: Queryable, accountId: string, fields: Partial<StripeConnection>, now: Date): Promise<StripeConnection | null> {
  const { rows } = await db.query<{ value: unknown }>(
    `UPDATE settings SET value = value || $3::jsonb, updated_at = $4
      WHERE key = ANY($1::text[]) AND value->>'accountId' = $2
      RETURNING value`,
    [[CONNECT_SETTINGS_KEY, OTHER_MODE_SETTINGS_KEY], accountId, JSON.stringify(fields), now],
  );
  return parseConnection(rows[0]?.value);
}

/**
 * Forgets the shop's account `accountId` (if it's still stored), and counts it, so the next
 * connection makes a new account. The account itself stays at Stripe.
 */
async function forgetConnection(tx: Queryable, now: Date, accountId: string): Promise<boolean> {
  const { rowCount } = await tx.query(`DELETE FROM settings WHERE key = ANY($1::text[]) AND value->>'accountId' = $2`, [
    [CONNECT_SETTINGS_KEY, OTHER_MODE_SETTINGS_KEY],
    accountId,
  ]);
  if (!rowCount) return false;
  await tx.query(
    `INSERT INTO settings (key, value, updated_at) VALUES ($1, '{"disconnects": 1}'::jsonb, $2)
     ON CONFLICT (key) DO UPDATE
       SET value = jsonb_build_object('disconnects', COALESCE((settings.value->>'disconnects')::int, 0) + 1), updated_at = EXCLUDED.updated_at`,
    [HISTORY_SETTINGS_KEY, now],
  );
  // A way back from Stripe that's still open would now lead nowhere.
  await tx.query('DELETE FROM stripe_connect_states');
  return true;
}

/**
 * Reads the connected account's status from Stripe and caches it (with the key that read it);
 * once it can take card payments, its Terminal location is made too (so Tap to Pay finds it in
 * GET /api/owner/me). Null when the shop disconnected it meanwhile, or when Stripe says the
 * platform can't use it any more (the shop took the access away): then it's forgotten, and
 * Settings asks to connect again. Any other Stripe failure is logged and thrown (stripeFailure).
 *
 * Stripe gives a key of some other Stripe account (pasted by mistake, say) the same "no access"
 * answer as a platform that lost its access, so that answer only counts from the key that made
 * the account or last read it. With any other key the account is kept: once the right key is
 * back, it works again, with every card saved on it.
 */
export async function refreshConnection(deps: Deps, connection: StripeConnection): Promise<StripeConnection | null> {
  let account: Stripe.Account;
  try {
    account = await platformStripe(deps).accounts.retrieve(connection.accountId);
  } catch (error) {
    if (!accessRevoked(error)) throw stripeFailure(deps, error, 'retrieve account');
    stripeFailure(deps, error, 'retrieve account');
    if (connection.keyFingerprint === null || connection.keyFingerprint !== keyFingerprint(deps.config)) {
      deps.log.warn("Stripe didn't let a different key read the shop's account; kept it", { accountId: connection.accountId });
      throw new ApiError('server_error', "Stripe didn't let this server's key use the shop's Stripe account. Check STRIPE_SECRET_KEY on the server.");
    }
    await accessLost(deps, connection.accountId);
    return null;
  }
  if (account.id !== connection.accountId) throw stripeFailure(deps, new Error('Stripe answered with another account'), 'retrieve account');
  const now = deps.now();
  const updated = await updateConnection(
    deps.db,
    connection.accountId,
    { ...accountStatus(account), keyFingerprint: keyFingerprint(deps.config), checkedAt: formatInstant(now) },
    now,
  );
  if (updated?.chargesEnabled && !updated.locationId) {
    try {
      updated.locationId = await terminalLocation(deps, await shopStripe(deps));
    } catch {
      // Logged by stripeFailure; the next refresh, or a connection token, makes it.
    }
  }
  return updated;
}

/** The platform can't use the shop's account any more: forget it, so Settings asks to connect again. */
async function accessLost(deps: Deps, accountId: string): Promise<void> {
  const forgot = await deps.db.transaction(async (tx) => {
    await lockConnect(tx);
    return forgetConnection(tx, deps.now(), accountId);
  });
  if (forgot) deps.log.warn("Stripe no longer lets the platform use the shop's account; forgot it", { accountId });
}

/** The connection, read live from Stripe when that works, from the cache when it doesn't (logged). */
async function freshConnection(deps: Deps): Promise<StripeConnection | null> {
  const connection = await currentConnection(deps);
  if (!connection) return null;
  try {
    return await refreshConnection(deps, connection);
  } catch {
    return connection;
  }
}

/**
 * The account.updated webhook for the shop's connected account: cache its new status (others are
 * ignored). Read from Stripe rather than from the event, since events can come out of order.
 */
export async function accountUpdated(deps: Deps, accountId: string): Promise<void> {
  const connection = await currentConnection(deps);
  if (!connection || connection.accountId !== accountId) return;
  // A Stripe failure answers 500, so Stripe sends the event again.
  await refreshConnection(deps, connection);
}

/** The account.application.deauthorized webhook: the shop took the platform's access away. Forget the account. */
export async function accountDeauthorized(deps: Deps, accountId: string): Promise<void> {
  if ((await loadConnections(deps.db)).some((connection) => connection.accountId === accountId)) await accessLost(deps, accountId);
}

/**
 * Stripe's idempotency key for making the shop's account: one per mode and per connection, so a
 * try whose answer was lost (a timeout, the function stopping) gets the same account when it's
 * tried again, and connecting again after a disconnect makes a new one.
 */
async function accountIdempotencyKey(tx: Queryable, livemode: boolean): Promise<string> {
  const { rows } = await tx.query<{ value: { disconnects?: unknown } }>('SELECT value FROM settings WHERE key = $1', [HISTORY_SETTINGS_KEY]);
  const disconnects = Number(rows[0]?.value.disconnects ?? 0);
  return `izzy-clipz-shop-account-${livemode ? 'live' : 'test'}-${Number.isSafeInteger(disconnects) ? disconnects : 0}`;
}

/**
 * The shop's account in connect mode, made the first time and never twice: two taps (or the
 * app and the website) at once wait for each other, and the id is stored before any link is
 * made. A key of the other mode (test or live) gets an account of its own; the one connected
 * with the first mode is kept aside for when its key is back (saveConnection).
 */
async function shopAccountForOnboarding(deps: Deps, base: string): Promise<StripeConnection> {
  return deps.db.transaction(async (tx) => {
    await lockConnect(tx);
    const existing = connectionForKey(await loadConnections(tx), deps.config);
    if (existing) return existing;
    const params: Stripe.AccountCreateParams = {
      controller: {
        stripe_dashboard: { type: 'full' },
        fees: { payer: 'account' },
        losses: { payments: 'stripe' },
        requirement_collection: 'stripe',
      },
      // Tap to Pay (Terminal) and direct charges need card_payments; Stripe asks for transfers with it.
      capabilities: { card_payments: { requested: true }, transfers: { requested: true } },
      country: 'US',
      business_profile: {
        name: SHOP_NAME,
        mcc: SHOP_MCC,
        // Stripe only takes a public https address as the business's website.
        ...(base.startsWith('https://') ? { url: base } : {}),
        support_phone: SHOP_SUPPORT_PHONE,
      },
      metadata: { izzy_clipz: 'shop' },
    };
    const idempotencyKey = await accountIdempotencyKey(tx, keyLivemode(deps.config) === true);
    let account: Stripe.Account;
    try {
      account = await platformStripe(deps).accounts.create(params, { idempotencyKey });
    } catch (error) {
      if ((error as StripeErrorLike | null)?.type !== 'StripeIdempotencyError') throw stripeFailure(deps, error, 'create account');
      // A lost try was made with other details (PUBLIC_BASE_URL changed since): make it afresh.
      stripeFailure(deps, error, 'create account');
      try {
        account = await platformStripe(deps).accounts.create(params, { idempotencyKey: `${idempotencyKey}-${deps.now().getTime()}` });
      } catch (retryError) {
        throw stripeFailure(deps, retryError, 'create account');
      }
    }
    if (!ACCOUNT_ID_RE.test(account.id)) throw stripeFailure(deps, new Error('Stripe answered with an account id we can’t use'), 'create account');
    const now = deps.now();
    const connection: StripeConnection = {
      accountId: account.id,
      livemode: keyLivemode(deps.config) === true,
      keyFingerprint: keyFingerprint(deps.config),
      connectedAt: formatInstant(now),
      locationId: null,
      ...accountStatus(account),
      checkedAt: formatInstant(now),
    };
    await saveConnection(tx, connection, now);
    return connection;
  });
}

/**
 * PUBLIC_BASE_URL without a trailing slash, for the pages Stripe sends the owner back to; null
 * when it isn't set or isn't an http(s) address (Stripe wants https with a live key).
 */
export function connectBase(config: Config): string | null {
  const url = httpUrl(config.publicBaseUrl);
  if (!url || (url.protocol === 'http:' && keyLivemode(config) === true)) return null;
  return baseOf(url);
}

type ReturnTo = 'app' | 'web';
/** Which of Stripe's two ways back a state is for (return_url or refresh_url). */
type StatePage = 'return' | 'refresh';

/**
 * A state's SHA-256, which also says which page it's for: the return page's state, which stays in
 * the browser's history after onboarding, never works on the refresh page (which makes links).
 */
const stateHash = (state: string, page: StatePage) => sha256Hex(page === 'return' ? state : `refresh:${state}`);

/**
 * New states for one onboarding link's two ways back, with the same `returnTo`; expired ones are
 * cleared out first. The return page's can be loaded again until it expires; the refresh page's
 * works once (it makes a new link to Stripe's onboarding).
 */
async function newStates(deps: Deps, returnTo: ReturnTo): Promise<Record<StatePage, string>> {
  const now = deps.now();
  const expires = new Date(now.getTime() + CONNECT_STATE_MINUTES * 60_000);
  const states = { return: randomBytes(32).toString('base64url'), refresh: randomBytes(32).toString('base64url') };
  await deps.db.query('DELETE FROM stripe_connect_states WHERE expires_at <= $1', [now]);
  await deps.db.query(
    `INSERT INTO stripe_connect_states (state_hash, return_to, created_at, expires_at)
     VALUES ($1, $3, $4, $5), ($2, $3, $4, $5)`,
    [stateHash(states.return, 'return'), stateHash(states.refresh, 'refresh'), returnTo, now, expires],
  );
  return states;
}

/**
 * Where a state for `page` sends the owner back to, while it hasn't expired. The return page's
 * state can be used more than once until then; the refresh page's is used up here.
 */
async function stateReturnTo(deps: Deps, state: string | null, page: StatePage): Promise<ReturnTo | null> {
  if (!state || !STATE_RE.test(state)) return null;
  const { rows } = await deps.db.query<{ return_to: ReturnTo }>(
    page === 'return'
      ? 'SELECT return_to FROM stripe_connect_states WHERE state_hash = $1 AND expires_at > $2'
      : 'DELETE FROM stripe_connect_states WHERE state_hash = $1 AND expires_at > $2 RETURNING return_to',
    [stateHash(state, page), deps.now()],
  );
  return rows[0]?.return_to ?? null;
}

/**
 * A link to Stripe's onboarding for the shop's account (made first when `create` is set), with
 * new states in the addresses Stripe sends the browser back to.
 */
async function onboardingLink(deps: Deps, returnTo: ReturnTo, create: boolean): Promise<{ url: string; expiresAt: string }> {
  const base = connectBase(deps.config);
  if (!base) throw new ApiError('stripe_not_configured', NO_BASE_URL_MESSAGE);
  const connection = create ? await shopAccountForOnboarding(deps, base) : await currentConnection(deps);
  if (!connection) throw new ApiError('not_found', EXPIRED_MESSAGE);
  const states = await newStates(deps, returnTo);
  let link: Stripe.AccountLink;
  try {
    link = await platformStripe(deps).accountLinks.create({
      account: connection.accountId,
      type: 'account_onboarding',
      refresh_url: `${base}/api/stripe/connect/refresh?state=${states.refresh}`,
      return_url: `${base}/api/stripe/connect/return?state=${states.return}`,
      collection_options: { fields: 'eventually_due' },
    });
  } catch (error) {
    throw stripeFailure(deps, error, 'create account link');
  }
  return { url: link.url, expiresAt: formatInstant(new Date(link.expires_at * 1000)) };
}

function connectOff(setup: StripeSetup, what: 'connect' | 'disconnect'): ApiError {
  return new ApiError(
    'stripe_connect_off',
    setup === 'off'
      ? `Stripe isn't set up on the server yet, so there's nothing to ${what}.`
      : `This server uses its own Stripe key, so there's nothing to ${what}.`,
  );
}

/**
 * The shop's Terminal location for Tap to Pay. Direct mode: STRIPE_TERMINAL_LOCATION_ID, as
 * before. Connect mode: a location on the connected account ("Izzy Clipz Barbershop" at the
 * shop's address), made the first time it's needed and cached, once even when several requests
 * need it at the same moment.
 */
export async function terminalLocation(deps: Deps, shop: ShopStripe): Promise<string | null> {
  const account = shop.stripeAccount;
  if (!account) return deps.config.stripeTerminalLocationId ?? null;
  const stored = async (db: Queryable) => (await loadConnections(db)).find((connection) => connection.accountId === account);
  const cached = await stored(deps.db);
  if (cached?.locationId) return cached.locationId;
  return deps.db.transaction(async (tx) => {
    await lockConnect(tx);
    const connection = await stored(tx);
    if (!connection) throw new ApiError('stripe_not_configured', CONNECT_STRIPE_MESSAGE);
    if (connection.locationId) return connection.locationId;
    let location: Stripe.Terminal.Location;
    try {
      location = await shop.stripe.terminal.locations.create({ display_name: SHOP_NAME, address: SHOP_ADDRESS }, requestOptions(shop));
    } catch (error) {
      throw stripeFailure(deps, error, 'create terminal location');
    }
    await updateConnection(tx, account, { locationId: location.id }, deps.now());
    return location.id;
  });
}

/** Forgets a cached location Stripe no longer has (the owner deleted it in the Dashboard), so the next request makes a new one. */
export async function forgetTerminalLocation(deps: Deps, account: string, locationId: string): Promise<void> {
  await deps.db.query(
    `UPDATE settings SET value = value || '{"locationId": null}'::jsonb, updated_at = $3
      WHERE key = ANY($1::text[]) AND value->>'accountId' = $2 AND value->>'locationId' = $4`,
    [[CONNECT_SETTINGS_KEY, OTHER_MODE_SETTINGS_KEY], account, deps.now(), locationId],
  );
}

// GET /api/owner/stripe

export async function getOwnerStripe(ctx: Context): Promise<Response> {
  await requireOwner(ctx);
  const { config } = ctx.deps;
  const setup = stripeSetup(config);
  if (setup !== 'connect') return json(connectionJSON(setup, null, config));
  return json(connectionJSON(setup, await freshConnection(ctx.deps), config));
}

// POST /api/owner/stripe/connect { returnTo: "app" | "web" } (no body: the app)

const connectBody = z.object({
  returnTo: z.enum(['app', 'web'], { error: 'returnTo must be "app" or "web".' }).optional(),
});

export async function postStripeConnect(ctx: Context): Promise<Response> {
  await requireOwner(ctx);
  const setup = stripeSetup(ctx.deps.config);
  if (setup !== 'connect') throw connectOff(setup, 'connect');
  const body = parse(connectBody, await readOptionalJsonObject(ctx.request));
  return json(await onboardingLink(ctx.deps, body.returnTo ?? 'app', true), 201);
}

// DELETE /api/owner/stripe/connect (the owner key only): forget the account. It stays open at Stripe.
// Only the account that works with the server's key now: one of the other mode (test or live), kept
// aside, stays for when its key is back.

export async function deleteStripeConnect(ctx: Context): Promise<Response> {
  await requireOwner(ctx, { keyOnly: true });
  const { deps } = ctx;
  const setup = stripeSetup(deps.config);
  if (setup !== 'connect') throw connectOff(setup, 'disconnect');
  await deps.db.transaction(async (tx) => {
    await lockConnect(tx);
    const connection = connectionForKey(await loadConnections(tx), deps.config);
    if (connection) await forgetConnection(tx, deps.now(), connection.accountId);
  });
  return json({ ...connectionJSON(setup, null, deps.config), message: DISCONNECTED_MESSAGE });
}

// GET /api/stripe/connect/return?state=… and GET /api/stripe/connect/refresh?state=… (a browser lands here)

/** Each network gets CONNECT_PAGES_PER_IP of Stripe's pages back per 10 minutes. */
async function pageLimit(ctx: Context): Promise<Response | null> {
  const { deps } = ctx;
  const hits = await hit(deps.db, ipKey('stripe-connect-page', deps.clientIp(ctx.request)), deps.now(), {
    max: CONNECT_PAGES_PER_IP,
    windowMinutes: 10,
  });
  if (hits <= CONNECT_PAGES_PER_IP) return null;
  return htmlPage(
    'Too many tries from this network. Wait 10 minutes, then go back to Izzy Clipz Business and tap Connect Stripe again.',
    429,
    { 'retry-after': '600' },
  );
}

const expiredPage = () => htmlPage(EXPIRED_MESSAGE, 400);

export async function stripeConnectReturn(ctx: Context): Promise<Response> {
  const limited = await pageLimit(ctx);
  if (limited) return limited;
  const { deps } = ctx;
  const returnTo = await stateReturnTo(deps, ctx.url.searchParams.get('state'), 'return');
  if (!returnTo) return expiredPage();
  const setup = stripeSetup(deps.config);
  const status: ConnectionStatus = setup === 'connect' ? connectionStatus(await freshConnection(deps)) : setup;
  if (returnTo === 'app') return redirect(`${BUSINESS_APP_SCHEME}://stripe-connected?status=${status}`);
  return redirect(`${connectBase(deps.config) ?? ctx.url.origin}/business/settings?stripe=${status}`);
}

/**
 * Stripe sends the browser here when an onboarding link expired or was already used: a new link
 * (with new states) and on to Stripe. Its state works once, and never the return page's, so an
 * address left in a browser's history can't hand anyone a way into the shop's Stripe account.
 */
export async function stripeConnectRefresh(ctx: Context): Promise<Response> {
  const limited = await pageLimit(ctx);
  if (limited) return limited;
  const { deps } = ctx;
  if (stripeSetup(deps.config) !== 'connect') return expiredPage();
  const returnTo = await stateReturnTo(deps, ctx.url.searchParams.get('state'), 'refresh');
  if (!returnTo) return expiredPage();
  try {
    return redirect((await onboardingLink(deps, returnTo, false)).url);
  } catch (error) {
    if (error instanceof ApiError && error.code === 'not_found') return expiredPage();
    const message = error instanceof ApiError && error.code === 'stripe_not_configured' ? error.message : "We couldn't reach Stripe. Go back to Izzy Clipz Business and tap Connect Stripe again.";
    return htmlPage(message, error instanceof ApiError ? error.status : 500);
  }
}
