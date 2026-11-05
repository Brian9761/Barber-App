import { createHash } from 'node:crypto';
import type Stripe from 'stripe';
import type { Config } from './config.js';
import type { Queryable } from './db.js';
import type { Deps, StripeClient } from './deps.js';
import { ApiError } from './http.js';

// Which Stripe account the shop's card payments go to, decided from the environment:
//
// - off: no STRIPE_SECRET_KEY. Card payments, saved cards and no-show protection are off.
// - direct: STRIPE_SECRET_KEY is the shop's own Stripe account (STRIPE_CONNECT isn't on), as in v4.
// - connect: STRIPE_CONNECT=on. The key is the app developer's Connect platform, and the owner
//   connects the shop's own Stripe account from Settings (stripeconnect.ts). Every call for the
//   shop is then a direct charge on that account (the Stripe-Account header), so the money, the
//   fees and the Dashboard are the shop's. Until that account can take card payments,
//   everything behaves exactly like off.
//
// `shopStripe` is the one way to get a Stripe client for the shop, and `requestOptions` the one
// way to send its account with a call: nothing can forget the header.

export type StripeSetup = 'off' | 'direct' | 'connect';

export function stripeSetup(config: Config): StripeSetup {
  if (!config.stripeSecretKey) return 'off';
  return config.stripeConnect ? 'connect' : 'direct';
}

export type StripeMode = 'test' | 'live' | null;

export function stripeMode(config: Config): StripeMode {
  const key = config.stripeSecretKey;
  if (!key) return null;
  if (/^(sk|rk)_test_/.test(key)) return 'test';
  if (/^(sk|rk)_live_/.test(key)) return 'live';
  return null;
}

/** Live (true) or test (false), from the key; null when the key doesn't say. */
export function keyLivemode(config: Config): boolean | null {
  const mode = stripeMode(config);
  return mode === null ? null : mode === 'live';
}

/**
 * A short fingerprint of the server's Stripe key (the start of its SHA-256), never the key: which
 * key last read the shop's account (`StripeConnection.keyFingerprint`). Null without a key.
 */
export function keyFingerprint(config: Config): string | null {
  const key = config.stripeSecretKey;
  return key ? createHash('sha256').update(key).digest('hex').slice(0, 16) : null;
}

// The connected account, cached in settings under 'stripe_connect' (stripeconnect.ts keeps it fresh).

export const CONNECT_SETTINGS_KEY = 'stripe_connect';
/**
 * The connection made with a key of the other mode (test or live) than the one under
 * 'stripe_connect', kept aside when the shop connected while the server had a key of the other
 * mode. When that mode's key comes back, its connection is the shop's again: switching the key
 * between test and live never loses (or replaces) an account.
 */
export const OTHER_MODE_SETTINGS_KEY = 'stripe_connect_other_mode';
const CONNECTION_KEYS = [CONNECT_SETTINGS_KEY, OTHER_MODE_SETTINGS_KEY];
export const ACCOUNT_ID_RE = /^acct_[A-Za-z0-9]+$/;
const LOCATION_ID_RE = /^tml_[A-Za-z0-9]+$/;
const FINGERPRINT_RE = /^[0-9a-f]{16}$/;

export interface StripeConnection {
  accountId: string;
  /** Made with a live key (true) or a test key (false): it only works with a key of the same mode. */
  livemode: boolean;
  /** `keyFingerprint` of the key that made the account or last read it from Stripe (null when unknown). */
  keyFingerprint: string | null;
  connectedAt: string;
  /** The shop's Terminal location on this account, made the first time Tap to Pay needs it. */
  locationId: string | null;
  chargesEnabled: boolean;
  payoutsEnabled: boolean;
  detailsSubmitted: boolean;
  /** How many of Stripe's requirements are currently due. */
  requirementsDue: number;
  /** Stripe's `requirements.disabled_reason`, when it has paused the account. */
  disabledReason: string | null;
  businessName: string | null;
  /** When the status was last read from Stripe. */
  checkedAt: string | null;
}

const text = (v: unknown, max = 200): string | null => (typeof v === 'string' && v.length > 0 && v.length <= max ? v : null);
const flag = (v: unknown): boolean => v === true;

/** The stored connection, or null when there's none (or what's stored can't be read). */
export function parseConnection(value: unknown): StripeConnection | null {
  if (typeof value !== 'object' || value === null) return null;
  const v = value as Record<string, unknown>;
  const accountId = text(v.accountId, 255);
  if (!accountId || !ACCOUNT_ID_RE.test(accountId) || typeof v.livemode !== 'boolean') return null;
  const locationId = text(v.locationId, 255);
  const fingerprint = text(v.keyFingerprint);
  const due = v.requirementsDue;
  return {
    accountId,
    livemode: v.livemode,
    keyFingerprint: fingerprint && FINGERPRINT_RE.test(fingerprint) ? fingerprint : null,
    connectedAt: text(v.connectedAt) ?? '',
    locationId: locationId && LOCATION_ID_RE.test(locationId) ? locationId : null,
    chargesEnabled: flag(v.chargesEnabled),
    payoutsEnabled: flag(v.payoutsEnabled),
    detailsSubmitted: flag(v.detailsSubmitted),
    requirementsDue: typeof due === 'number' && Number.isSafeInteger(due) && due >= 0 ? due : 0,
    disabledReason: text(v.disabledReason),
    businessName: text(v.businessName),
    checkedAt: text(v.checkedAt),
  };
}

/** The stored connections: the latest one first, then the other mode's kept aside (if any). At most one per mode. */
export async function loadConnections(db: Queryable): Promise<StripeConnection[]> {
  const { rows } = await db.query<{ key: string; value: unknown }>('SELECT key, value FROM settings WHERE key = ANY($1::text[])', [
    CONNECTION_KEYS,
  ]);
  return CONNECTION_KEYS.flatMap((key) => {
    const connection = parseConnection(rows.find((row) => row.key === key)?.value);
    return connection ? [connection] : [];
  });
}

/**
 * The stored connection that works with this key: an account connected while the platform used
 * a test key can't take live payments (and the other way round), so a key of the other mode
 * needs an account of its own (and the first one works again once its mode's key is back).
 */
export function connectionForKey(stored: readonly StripeConnection[], config: Config): StripeConnection | null {
  const live = keyLivemode(config);
  return stored.find((connection) => live === null || connection.livemode === live) ?? null;
}

/** The shop's connected account in connect mode, if it works with this key (null in the other modes). */
export async function currentConnection(deps: Pick<Deps, 'config' | 'db'>, db: Queryable = deps.db): Promise<StripeConnection | null> {
  if (stripeSetup(deps.config) !== 'connect') return null;
  return connectionForKey(await loadConnections(db), deps.config);
}

export type ConnectionStatus = 'notConnected' | 'needsInfo' | 'pending' | 'active' | 'restricted' | 'direct' | 'off';

/**
 * A connect-mode connection's status, in this order:
 * - active: Stripe lets it take card payments (charges_enabled);
 * - needsInfo: details not submitted yet, requirements currently due, or paused for being past due;
 * - pending: details submitted and nothing due, while Stripe verifies them;
 * - restricted: Stripe paused it for any other reason (rejected, under review, …).
 */
export function connectionStatus(connection: StripeConnection | null): 'notConnected' | 'needsInfo' | 'pending' | 'active' | 'restricted' {
  if (!connection) return 'notConnected';
  if (connection.chargesEnabled) return 'active';
  if (!connection.detailsSubmitted) return 'needsInfo';
  const reason = connection.disabledReason;
  if (reason === null || reason === 'requirements.pending_verification') return connection.requirementsDue > 0 ? 'needsInfo' : 'pending';
  if (reason === 'requirements.past_due') return 'needsInfo';
  return 'restricted';
}

/** What Settings says about the connection, in plain words. */
export function connectionMessage(status: ConnectionStatus, connection: StripeConnection | null): string {
  switch (status) {
    case 'off':
      return "Stripe isn't set up on the server.";
    case 'direct':
      return "Card payments use this server's own Stripe key.";
    case 'notConnected':
      return 'Connect your Stripe account to take card payments in the app.';
    case 'needsInfo':
      return 'Finish setting up Stripe to take card payments.';
    case 'pending':
      return 'Stripe is checking your details. This usually takes a few minutes.';
    case 'restricted':
      return 'Stripe paused card payments: open Stripe to fix it.';
    case 'active':
      return `Connected. Card payments are on.${connection?.payoutsEnabled ? ' Payouts to your bank are on.' : ' Add your bank in Stripe to get paid out.'}`;
  }
}

// Getting a client for the shop.

/** The account a call for the shop goes to: the connected account in connect mode (none in direct mode). */
export interface ShopAccount {
  /** Sent as the Stripe-Account header on every call for the shop (connect mode only). */
  stripeAccount?: string;
  /** Live or test: from the key (and the connected account's own, in connect mode); null when the key doesn't say. */
  livemode: boolean | null;
}

export interface ShopStripe extends ShopAccount {
  stripe: StripeClient;
}

const STRIPE_OFF_MESSAGE = "Card payments aren't set up yet. Add the shop's Stripe key on the server.";
export const CONNECT_STRIPE_MESSAGE = 'Connect Stripe in Settings to take card payments.';
/** Something made with the shop's own Stripe key before Stripe was connected, which connect mode can't look up. */
export const SERVER_KEY_OBJECT_MESSAGE =
  "This was made with the shop's own Stripe key, before Stripe was connected in Settings, so the app can't look it up. Check it in that Stripe account's Dashboard.";

/** 503 stripe_not_configured: no Stripe key at all (always checked first, as before connect mode). */
export function stripeOff(): ApiError {
  return new ApiError('stripe_not_configured', STRIPE_OFF_MESSAGE);
}

/** 503 stripe_not_configured in connect mode while the shop's account can't take card payments, saying why. */
function notConnected(connection: StripeConnection | null): ApiError {
  const status = connectionStatus(connection);
  return new ApiError('stripe_not_configured', status === 'notConnected' ? CONNECT_STRIPE_MESSAGE : connectionMessage(status, connection));
}

/**
 * The shop's current account, or null while card features are off: no key, or (connect mode)
 * no connected account that can take card payments yet. Reads the cache, never Stripe.
 */
export async function shopAccount(deps: Pick<Deps, 'config' | 'db'>, db: Queryable = deps.db): Promise<ShopAccount | null> {
  const setup = stripeSetup(deps.config);
  if (setup === 'off') return null;
  if (setup === 'direct') return { livemode: keyLivemode(deps.config) };
  const connection = await currentConnection(deps, db);
  if (!connection?.chargesEnabled) return null;
  return { stripeAccount: connection.accountId, livemode: connection.livemode };
}

/**
 * The Stripe client for a call made for the shop, with the account it goes to. Every Stripe call
 * for the shop gets its client here and passes `requestOptions(shop)`.
 *
 * - Without `account`: the shop's current account. 503 stripe_not_configured while there's no
 *   key, or (connect mode) until the connected account can take card payments: for the owner,
 *   with what to do in Settings; for clients (`forClients`), exactly as when Stripe is off.
 * - With `account`: an object stored with the account it lives on (a payment's or a saved
 *   card's `stripe_account_id`; null for one made with a server key). That's where Stripe has
 *   it, even after the shop connected another account, so it can still be looked up. Only the
 *   key is needed (in direct mode no Stripe-Account header is ever sent). In connect mode, one
 *   made with the server's own key in direct mode (null) is on the shop's own Stripe account,
 *   which the platform's key can't see: it's a 404 saying so, never a lookup on the platform's
 *   account, where "not found" would mean nothing.
 */
export async function shopStripe(
  deps: Pick<Deps, 'config' | 'db' | 'stripe'>,
  options: { account?: string | null; db?: Queryable; forClients?: boolean } = {},
): Promise<ShopStripe> {
  const key = deps.config.stripeSecretKey;
  const setup = stripeSetup(deps.config);
  if (setup === 'off' || !key) throw stripeOff();
  const livemode = keyLivemode(deps.config);
  if (setup === 'direct') return { stripe: deps.stripe(key), livemode };
  if (options.account !== undefined) {
    if (!options.account) throw new ApiError('not_found', SERVER_KEY_OBJECT_MESSAGE);
    return { stripe: deps.stripe(key), stripeAccount: options.account, livemode };
  }
  const connection = await currentConnection(deps, options.db ?? deps.db);
  if (!connection?.chargesEnabled) throw options.forClients ? stripeOff() : notConnected(connection);
  return { stripe: deps.stripe(key), stripeAccount: connection.accountId, livemode: connection.livemode };
}

/** The platform's own client (connect mode), for its calls about the connected account. */
export function platformStripe(deps: Pick<Deps, 'config' | 'stripe'>): StripeClient {
  const key = deps.config.stripeSecretKey;
  if (!key) throw stripeOff();
  return deps.stripe(key);
}

/**
 * The request options for a call on `shop`'s account: the Stripe-Account header in connect mode
 * (stripe-node's `stripeAccount`), plus `extra` such as an idempotency key. Undefined when
 * there's nothing to send.
 */
export function requestOptions(shop: Pick<ShopAccount, 'stripeAccount'>, extra?: Stripe.RequestOptions): Stripe.RequestOptions | undefined {
  if (!shop.stripeAccount) return extra;
  return { ...extra, stripeAccount: shop.stripeAccount };
}

/**
 * Whether something saved on Stripe (a saved card) works with the shop's account now: the same
 * account (none, in direct mode) and the same mode (unless the key doesn't say).
 */
export function accountMatch(saved: { stripe_account_id: string | null; livemode: boolean }, shop: ShopAccount): 'same' | 'otherAccount' | 'otherMode' {
  if ((saved.stripe_account_id ?? null) !== (shop.stripeAccount ?? null)) return 'otherAccount';
  if (shop.livemode !== null && saved.livemode !== shop.livemode) return 'otherMode';
  return 'same';
}

/**
 * When Stripe says a PaymentIntent went through, as near as the server can tell, never after
 * `now`: its latest charge's time when it was read with `latest_charge` expanded, else
 * `fallbackSeconds` (a webhook event's time, or when Stripe made the PaymentIntent), else `now`.
 * It can be well before the server hears of it: a webhook Stripe sent again later, or an app
 * that confirms a payment the next morning.
 */
export function succeededAt(
  intent: { latest_charge?: string | { created?: number } | null },
  now: Date,
  fallbackSeconds?: number | null,
): Date {
  const charge = intent.latest_charge;
  const seconds = typeof charge === 'object' && charge !== null && typeof charge.created === 'number' ? charge.created : fallbackSeconds;
  const at = typeof seconds === 'number' && Number.isFinite(seconds) ? new Date(seconds * 1000) : null;
  return at && at < now ? at : now;
}

// Stripe's errors.

export type StripeCall =
  | 'connection token'
  | 'create payment'
  | 'retrieve payment'
  | 'create customer'
  | 'create card checkout'
  | 'retrieve card checkout'
  | 'charge no-show fee'
  | 'retrieve no-show fee'
  | 'find no-show fee'
  | 'create account'
  | 'retrieve account'
  | 'create account link'
  | 'create terminal location'
  | 'detach card'
  | 'delete customer'
  | 'send receipt';

/** The parts of a stripe-node error worth logging. */
export interface StripeErrorLike {
  type?: string;
  code?: string;
  param?: string;
  statusCode?: number;
  requestId?: string;
  message?: string;
}

/** Keys and client secrets never reach the logs, even if Stripe quotes one in a message. */
function redactSecrets(text: string | undefined): string | undefined {
  return text?.replace(/\b((?:sk|rk)_(?:test|live)_)[A-Za-z0-9]+/g, '$1…').replace(/(_secret_)[A-Za-z0-9]+/g, '$1…');
}

/**
 * Whether Stripe says the platform can't use a connected account any more: the shop took its
 * access away (or the account is gone, or belongs to the other mode).
 */
export function accessRevoked(error: unknown): boolean {
  const e = (typeof error === 'object' && error !== null ? error : {}) as StripeErrorLike;
  return e.type === 'StripePermissionError' && /does not have access to account|access may have been revoked/i.test(e.message ?? '');
}

/**
 * Stripe's own errors, logged (what failed and why, never a key) and answered
 * with what to fix: a payment Stripe doesn't have is a 404; a Terminal location
 * or key Stripe turns down is a 500 that names the server setting; anything
 * else is a 500 asking to try again.
 */
export function stripeFailure(deps: Pick<Deps, 'log'>, error: unknown, what: StripeCall): ApiError {
  if (error instanceof ApiError) return error;
  const e = (typeof error === 'object' && error !== null ? error : {}) as StripeErrorLike;
  deps.log.error(`Stripe ${what} failed`, {
    type: e.type,
    code: e.code,
    param: e.param,
    status: e.statusCode,
    requestId: e.requestId,
    message: redactSecrets(e.message),
  });
  const missing = e.code === 'resource_missing' || e.statusCode === 404;
  if ((what === 'retrieve payment' || what === 'retrieve no-show fee') && missing) {
    return new ApiError('not_found', "Stripe doesn't know that payment.");
  }
  if (what === 'retrieve card checkout' && missing) {
    return new ApiError('not_found', "We couldn't find that card. Add it again.");
  }
  if (what === 'connection token' && (missing || e.param === 'location')) {
    // Usually a test-mode location with a live key (or the other way round), or a typo.
    return new ApiError(
      'server_error',
      "Stripe didn't accept the Terminal location set on the server. Check STRIPE_TERMINAL_LOCATION_ID: it must be a location from the same Stripe account and mode (test or live) as the key.",
    );
  }
  if (accessRevoked(error)) {
    // Connect mode: the platform can't use the shop's connected account any more (access revoked, or the other mode).
    return new ApiError('server_error', "Stripe didn't let the app use the shop's Stripe account. Connect Stripe again in Settings.");
  }
  if (e.type === 'StripeAuthenticationError' || e.type === 'StripePermissionError') {
    return new ApiError('server_error', "Stripe didn't accept the server's Stripe key. Check STRIPE_SECRET_KEY on the server.");
  }
  return new ApiError('server_error', "We couldn't reach Stripe. Please try again.");
}
