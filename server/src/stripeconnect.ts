import { createHash, randomBytes } from 'node:crypto';
import type Stripe from 'stripe';
import { z } from 'zod';
import { requireOwner } from './auth.js';
import type { Config } from './config.js';
import type { Queryable } from './db.js';
import type { Deps } from './deps.js';
import { ApiError, htmlPage, json, readJsonObject, redirect } from './http.js';
import { hit, ipKey } from './ratelimit.js';
import type { Context } from './router.js';
import {
  ACCOUNT_ID_RE,
  CONNECT_SETTINGS_KEY,
  CONNECT_STRIPE_MESSAGE,
  connectionForKey,
  connectionMessage,
  connectionStatus,
  currentConnection,
  keyLivemode,
  loadConnection,
  parseConnection,
  platformStripe,
  requestOptions,
  stripeFailure,
  stripeSetup,
  type ConnectionStatus,
  type ShopStripe,
  type StripeConnection,
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
//    has expired, …/refresh?state=…, which makes a new link). The state is 32 random bytes, kept
//    as a SHA-256 for an hour. The return page reads the account's status from Stripe and sends
//    the owner on to the app (izzyclipzbusiness://stripe-connected?status=…) or to the
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

const sha256 = (text: string): string => createHash('sha256').update(text, 'utf8').digest('hex');

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

async function saveConnection(db: Queryable, connection: StripeConnection, now: Date): Promise<void> {
  await db.query(
    `INSERT INTO settings (key, value, updated_at) VALUES ($1, $2::jsonb, $3)
     ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = EXCLUDED.updated_at`,
    [CONNECT_SETTINGS_KEY, JSON.stringify(connection), now],
  );
}

/**
 * Merges `fields` into the stored connection, only while it's still the one for `accountId`
 * (a disconnect, or a new account, that happened meanwhile wins). Null when it isn't.
 */
async function updateConnection(db: Queryable, accountId: string, fields: Partial<StripeConnection>, now: Date): Promise<StripeConnection | null> {
  const { rows } = await db.query<{ value: unknown }>(
    `UPDATE settings SET value = value || $3::jsonb, updated_at = $4
      WHERE key = $1 AND value->>'accountId' = $2
      RETURNING value`,
    [CONNECT_SETTINGS_KEY, accountId, JSON.stringify(fields), now],
  );
  return parseConnection(rows[0]?.value);
}

/**
 * Reads the connected account's status from Stripe and caches it. Null when the shop
 * disconnected it meanwhile. A Stripe failure is logged and thrown (stripeFailure).
 */
export async function refreshConnection(deps: Deps, connection: StripeConnection): Promise<StripeConnection | null> {
  let account: Stripe.Account;
  try {
    account = await platformStripe(deps).accounts.retrieve(connection.accountId);
  } catch (error) {
    throw stripeFailure(deps, error, 'retrieve account');
  }
  if (account.id !== connection.accountId) throw stripeFailure(deps, new Error('Stripe answered with another account'), 'retrieve account');
  const now = deps.now();
  return updateConnection(deps.db, connection.accountId, { ...accountStatus(account), checkedAt: formatInstant(now) }, now);
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

/** The account.updated webhook for the shop's connected account: cache its new status (others are ignored). */
export async function accountUpdated(deps: Deps, accountId: string): Promise<void> {
  const connection = await currentConnection(deps);
  if (!connection || connection.accountId !== accountId) return;
  // A Stripe failure answers 500, so Stripe sends the event again.
  await refreshConnection(deps, connection);
}

/**
 * The shop's account in connect mode, made the first time and never twice: two taps (or the
 * app and the website) at once wait for each other, and the id is stored before any link is
 * made. An account kept from a key of the other mode (test or live) is replaced.
 */
async function shopAccountForOnboarding(deps: Deps, base: string): Promise<StripeConnection> {
  return deps.db.transaction(async (tx) => {
    await lockConnect(tx);
    const existing = connectionForKey(await loadConnection(tx), deps.config);
    if (existing) return existing;
    let account: Stripe.Account;
    try {
      account = await platformStripe(deps).accounts.create({
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
      });
    } catch (error) {
      throw stripeFailure(deps, error, 'create account');
    }
    if (!ACCOUNT_ID_RE.test(account.id)) throw stripeFailure(deps, new Error('Stripe answered with an account id we can’t use'), 'create account');
    const now = deps.now();
    const connection: StripeConnection = {
      accountId: account.id,
      livemode: keyLivemode(deps.config) === true,
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
  if (!config.publicBaseUrl) return null;
  let url: URL;
  try {
    url = new URL(config.publicBaseUrl);
  } catch {
    return null;
  }
  if (url.protocol !== 'https:' && !(url.protocol === 'http:' && keyLivemode(config) !== true)) return null;
  return `${url.origin}${url.pathname.replace(/\/+$/, '')}`;
}

type ReturnTo = 'app' | 'web';

/** A new one-time state for Stripe's way back; expired ones are cleared out first. */
async function newState(deps: Deps, returnTo: ReturnTo): Promise<string> {
  const now = deps.now();
  const state = randomBytes(32).toString('base64url');
  await deps.db.query('DELETE FROM stripe_connect_states WHERE expires_at <= $1', [now]);
  await deps.db.query('INSERT INTO stripe_connect_states (state_hash, return_to, created_at, expires_at) VALUES ($1, $2, $3, $4)', [
    sha256(state),
    returnTo,
    now,
    new Date(now.getTime() + CONNECT_STATE_MINUTES * 60_000),
  ]);
  return state;
}

/** Where a state sends the owner back to, while it hasn't expired (it can be used more than once until then). */
async function stateReturnTo(deps: Deps, state: string | null): Promise<ReturnTo | null> {
  if (!state || !STATE_RE.test(state)) return null;
  const { rows } = await deps.db.query<{ return_to: ReturnTo }>(
    'SELECT return_to FROM stripe_connect_states WHERE state_hash = $1 AND expires_at > $2',
    [sha256(state), deps.now()],
  );
  return rows[0]?.return_to ?? null;
}

/**
 * A link to Stripe's onboarding for the shop's account (made first when `create` is set), with
 * a new state in the addresses Stripe sends the browser back to.
 */
async function onboardingLink(deps: Deps, returnTo: ReturnTo, create: boolean): Promise<{ url: string; expiresAt: string }> {
  const base = connectBase(deps.config);
  if (!base) throw new ApiError('stripe_not_configured', NO_BASE_URL_MESSAGE);
  const connection = create ? await shopAccountForOnboarding(deps, base) : await currentConnection(deps);
  if (!connection) throw new ApiError('not_found', EXPIRED_MESSAGE);
  const state = await newState(deps, returnTo);
  let link: Stripe.AccountLink;
  try {
    link = await platformStripe(deps).accountLinks.create({
      account: connection.accountId,
      type: 'account_onboarding',
      refresh_url: `${base}/api/stripe/connect/refresh?state=${state}`,
      return_url: `${base}/api/stripe/connect/return?state=${state}`,
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
  const cached = await loadConnection(deps.db);
  if (cached?.accountId === account && cached.locationId) return cached.locationId;
  return deps.db.transaction(async (tx) => {
    await lockConnect(tx);
    const connection = await loadConnection(tx);
    if (connection?.accountId !== account) throw new ApiError('stripe_not_configured', CONNECT_STRIPE_MESSAGE);
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
      WHERE key = $1 AND value->>'accountId' = $2 AND value->>'locationId' = $4`,
    [CONNECT_SETTINGS_KEY, account, deps.now(), locationId],
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

// POST /api/owner/stripe/connect { returnTo: "app" | "web" }

const connectBody = z.object({
  returnTo: z.enum(['app', 'web'], { error: 'returnTo must be "app" or "web".' }).optional(),
});

export async function postStripeConnect(ctx: Context): Promise<Response> {
  await requireOwner(ctx);
  const setup = stripeSetup(ctx.deps.config);
  if (setup !== 'connect') throw connectOff(setup, 'connect');
  const body = parse(connectBody, await readJsonObject(ctx.request));
  return json(await onboardingLink(ctx.deps, body.returnTo ?? 'app', true), 201);
}

// DELETE /api/owner/stripe/connect (the owner key only): forget the account. It stays open at Stripe.

export async function deleteStripeConnect(ctx: Context): Promise<Response> {
  await requireOwner(ctx, { keyOnly: true });
  const { deps } = ctx;
  const setup = stripeSetup(deps.config);
  if (setup !== 'connect') throw connectOff(setup, 'disconnect');
  await deps.db.transaction(async (tx) => {
    await lockConnect(tx);
    await tx.query('DELETE FROM settings WHERE key = $1', [CONNECT_SETTINGS_KEY]);
    // A way back from Stripe that's still open would now lead nowhere.
    await tx.query('DELETE FROM stripe_connect_states');
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
  const returnTo = await stateReturnTo(deps, ctx.url.searchParams.get('state'));
  if (!returnTo) return expiredPage();
  const setup = stripeSetup(deps.config);
  const status: ConnectionStatus = setup === 'connect' ? connectionStatus(await freshConnection(deps)) : setup;
  if (returnTo === 'app') return redirect(`${BUSINESS_APP_SCHEME}://stripe-connected?status=${status}`);
  return redirect(`${connectBase(deps.config) ?? ctx.url.origin}/business/settings?stripe=${status}`);
}

export async function stripeConnectRefresh(ctx: Context): Promise<Response> {
  const limited = await pageLimit(ctx);
  if (limited) return limited;
  const { deps } = ctx;
  const returnTo = await stateReturnTo(deps, ctx.url.searchParams.get('state'));
  if (!returnTo || stripeSetup(deps.config) !== 'connect') return expiredPage();
  try {
    return redirect((await onboardingLink(deps, returnTo, false)).url);
  } catch (error) {
    if (error instanceof ApiError && error.code === 'not_found') return expiredPage();
    const message = error instanceof ApiError && error.code === 'stripe_not_configured' ? error.message : "We couldn't reach Stripe. Go back to Izzy Clipz Business and tap Connect Stripe again.";
    return htmlPage(message, error instanceof ApiError ? error.status : 500);
  }
}
