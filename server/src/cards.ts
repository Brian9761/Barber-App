import { timingSafeEqual } from 'node:crypto';
import type Stripe from 'stripe';
import { z } from 'zod';
import { hashManageToken, isNewManageToken } from './auth.js';
import { resolveTarget, type Target } from './booking.js';
import type { Queryable } from './db.js';
import type { Deps } from './deps.js';
import { ApiError, baseOf, httpUrl, json, readJsonObject, redirect } from './http.js';
import { loadNoShowSettings, protectionFor } from './noshow.js';
import { hit, ipKey } from './ratelimit.js';
import { removeCard } from './retention.js';
import type { Context } from './router.js';
import { accountMatch, requestOptions, shopAccount, shopStripe, stripeFailure } from './stripeaccount.js';
import { localDate } from './time.js';
import { parse, shortId } from './validation.js';

// Saving a card for no-show protection, with Stripe Checkout in setup mode: the
// card is typed on Stripe's own page, so card numbers never reach this server or
// the apps, and nothing is charged.
//
// 1. POST /api/cards/checkout (X-Card-Token: a token the app made) → a Checkout
//    URL. The token's SHA-256 goes into the Checkout Session's metadata, so only
//    the phone that holds the token can save that session's card.
// 2. The app opens the URL in ASWebAuthenticationSession; Stripe returns to
//    GET /api/cards/return (https, as Checkout needs), which redirects to
//    izzyclipz://card-saved?session_id=… (or izzyclipz://card-cancelled). For the
//    website (returnTo "web") it's the website's own page instead:
//    /book/card-return?status=saved&session_id=… (or status=cancelled).
// 3. POST /api/cards { sessionId } with the same X-Card-Token → the card's brand,
//    last 4 and expiry, stored under that token. Doing it again answers the same.
//
// With Stripe Connect, the Customer, the Checkout Session and so the card live on the
// shop's connected account (stripe_account_id), and only work while the shop keeps it.

export const CARD_CHECKOUTS_PER_IP_PER_HOUR = 10;
export const CARD_SAVES_PER_IP_PER_HOUR = 10;
/** How long Stripe keeps the card page open (Stripe allows 30 minutes to 24 hours). */
export const CHECKOUT_MINUTES = 60;

/** The app's URL scheme, as `ASWebAuthenticationSession` waits for it. */
export const APP_SCHEME = 'izzyclipz';
export const CARD_SAVED_URL = `${APP_SCHEME}://card-saved`;
export const CARD_CANCELLED_URL = `${APP_SCHEME}://card-cancelled`;
export const CARD_FAILED_URL = `${APP_SCHEME}://card-failed`;

/** Marks the Checkout Sessions this server made (metadata.purpose). */
export const CHECKOUT_PURPOSE = 'izzy_no_show_card';
const SESSION_ID_RE = /^cs_(test|live)_[A-Za-z0-9]{1,200}$/;

/**
 * The app's card token from `X-Card-Token`: 32 random bytes in base64url, like a
 * manage token. Anything else, an empty header included, is a 400.
 */
export function cardTokenFrom(request: Request): string | undefined {
  const value = request.headers.get('x-card-token');
  if (value === null) return undefined;
  const token = value.trim();
  if (!isNewManageToken(token)) {
    throw new ApiError('invalid_request', 'X-Card-Token must be 32 random bytes in base64url (43 characters).');
  }
  return token;
}

function requiredCardToken(request: Request): string {
  const token = cardTokenFrom(request);
  if (!token) throw new ApiError('invalid_request', 'Send the card token as X-Card-Token.');
  return token;
}

export interface SavedCardRow {
  id: string;
  token_hash: string;
  /** Stripe's ids: null once the card is removed (migrations/008). */
  checkout_session_id: string | null;
  stripe_customer_id: string | null;
  stripe_payment_method_id: string | null;
  brand: string;
  last4: string;
  exp_month: number;
  exp_year: number;
  livemode: boolean;
  created_at: Date;
  /** The connected account the card is saved on (migrations/005); null when saved with the server's own key. */
  stripe_account_id: string | null;
  /** When it was deleted at Stripe (retention.ts); it can't book or be charged since. */
  removed_at: Date | null;
  /** When the client asked to delete it (DELETE /api/cards) while a booking still needed it. It can't book again. */
  delete_requested_at: Date | null;
}

/** Whether a saved card can still be used for a new booking: not removed, and the client hasn't asked to delete it. */
export function cardKept(card: Pick<SavedCardRow, 'removed_at' | 'delete_requested_at'>): boolean {
  return card.removed_at === null && card.delete_requested_at === null;
}

export function savedCardJSON(row: Pick<SavedCardRow, 'brand' | 'last4' | 'exp_month' | 'exp_year'>) {
  return { brand: row.brand, last4: row.last4, expMonth: row.exp_month, expYear: row.exp_year };
}

/**
 * Whether the card still works in the month of `at` (shop time): cards are good
 * through the last day of their expiry month.
 */
export function cardValidAt(card: Pick<SavedCardRow, 'exp_month' | 'exp_year'>, at: Date, zone: string): boolean {
  const [year, month] = localDate(at, zone).split('-').map(Number) as [number, number];
  return card.exp_year > year || (card.exp_year === year && card.exp_month >= month);
}

export async function findCardByToken(db: Queryable, token: string): Promise<SavedCardRow | null> {
  const { rows } = await db.query<SavedCardRow>('SELECT * FROM saved_cards WHERE token_hash = $1', [hashManageToken(token)]);
  return rows[0] ?? null;
}

async function limit(deps: Deps, request: Request, scope: string, max: number): Promise<void> {
  const hits = await hit(deps.db, ipKey(scope, deps.clientIp(request)), deps.now(), { max, windowMinutes: 60 });
  if (hits > max) {
    throw new ApiError('rate_limited', 'Too many tries to add a card from this network. Try again in an hour, or call the shop.', {
      headers: { 'retry-after': '3600' },
    });
  }
}

/**
 * The API's public address for Stripe to send the client back to:
 * PUBLIC_BASE_URL when it's a usable https (or http) address, otherwise the
 * address this request came in on.
 */
export function publicBase(configured: string | undefined, requestOrigin: string): string {
  return baseOf(httpUrl(configured) ?? new URL(requestOrigin));
}

// POST /api/cards/checkout { offeringId? | serviceId + barberId: "any", returnTo?: "app" | "web" } (X-Card-Token)

const checkoutBody = z.object({
  offeringId: shortId.optional(),
  serviceId: shortId.optional(),
  barberId: shortId.optional(),
  /** Where Stripe's page sends the client back to: the app (the default) or the website. */
  returnTo: z.enum(['app', 'web'], { error: 'returnTo must be "app" or "web".' }).optional(),
});

export async function createCardCheckout(ctx: Context): Promise<Response> {
  const { request, deps } = ctx;
  const shop = await shopStripe(deps, { forClients: true });
  const token = requiredCardToken(request);
  const body = parse(checkoutBody, await readJsonObject(request));
  const target = resolveTarget(deps.catalog, body);
  const { policy } = protectionFor(target, await loadNoShowSettings(deps.db), true);
  if (!policy.required || !policy.policyText) {
    throw new ApiError('invalid_request', "This booking doesn't need a card. Go ahead and book.");
  }
  await limit(deps, request, 'card-checkout', CARD_CHECKOUTS_PER_IP_PER_HOUR);

  const base = publicBase(deps.config.publicBaseUrl, ctx.url.origin);
  const toWeb = body.returnTo === 'web' ? '&to=web' : '';
  let customer: Stripe.Customer;
  try {
    // The card is saved to a Customer of its own: Checkout attaches it there, so it can be charged later.
    customer = await shop.stripe.customers.create(
      {
        description: 'Izzy Clipz client (card for no-show protection)',
        metadata: { source: 'izzy-clipz-api', purpose: CHECKOUT_PURPOSE },
      },
      requestOptions(shop),
    );
  } catch (error) {
    throw stripeFailure(deps, error, 'create customer');
  }
  let session: Stripe.Checkout.Session;
  try {
    session = await shop.stripe.checkout.sessions.create(
      {
        mode: 'setup',
        currency: 'usd',
        // Cards only (Apple Pay counts as a card); not payment_method_types, which API 2026-10-28.endive doesn't have.
        allowed_payment_method_types: ['card'],
        customer: customer.id,
        success_url: `${base}/api/cards/return?session_id={CHECKOUT_SESSION_ID}${toWeb}`,
        cancel_url: `${base}/api/cards/cancel${toWeb ? '?to=web' : ''}`,
        custom_text: { submit: { message: policy.policyText } },
        setup_intent_data: {
          description: 'Izzy Clipz no-show protection',
          metadata: { source: 'izzy-clipz-api', purpose: CHECKOUT_PURPOSE },
        },
        metadata: { source: 'izzy-clipz-api', purpose: CHECKOUT_PURPOSE, card_token_sha256: hashManageToken(token) },
        expires_at: Math.floor(deps.now().getTime() / 1000) + CHECKOUT_MINUTES * 60,
      },
      requestOptions(shop),
    );
  } catch (error) {
    throw stripeFailure(deps, error, 'create card checkout');
  }
  if (!session.url) throw stripeFailure(deps, new Error('Checkout Session has no url'), 'create card checkout');
  return json({ url: session.url, sessionId: session.id }, 201);
}

// GET /api/cards/return?session_id=cs_…[&to=web] and GET /api/cards/cancel[?to=web]: Stripe's way
// back to the app, or (to=web) to the website's own page, which then saves the card.

/** The website's page that takes the client back to their booking: /book/card-return?status=… */
function webCardReturn(ctx: Context, query: string): string {
  return `${publicBase(ctx.deps.config.publicBaseUrl, ctx.url.origin)}/book/card-return?${query}`;
}

const toWebsite = (ctx: Context) => ctx.url.searchParams.get('to') === 'web';

export async function cardCheckoutReturn(ctx: Context): Promise<Response> {
  const sessionId = ctx.url.searchParams.get('session_id') ?? '';
  const valid = SESSION_ID_RE.test(sessionId);
  if (toWebsite(ctx)) return redirect(webCardReturn(ctx, valid ? `status=saved&session_id=${sessionId}` : 'status=failed'));
  if (!valid) return redirect(CARD_FAILED_URL);
  return redirect(`${CARD_SAVED_URL}?session_id=${sessionId}`);
}

export async function cardCheckoutCancel(ctx: Context): Promise<Response> {
  if (toWebsite(ctx)) return redirect(webCardReturn(ctx, 'status=cancelled'));
  return redirect(CARD_CANCELLED_URL);
}

// POST /api/cards { sessionId } (X-Card-Token)

const saveBody = z.object({
  sessionId: z.string({ error: 'sessionId is missing.' }).regex(SESSION_ID_RE, { error: "That isn't a Stripe Checkout session id." }),
});

const tokenUsed = () => new ApiError('invalid_request', 'That card token was already used for another card.');
const unknownSession = () => new ApiError('not_found', "We couldn't find that card. Add it again.");
const notFinished = () => new ApiError('invalid_request', "The card wasn't added. Add it again.");

function idOf(value: string | { id: string } | null | undefined): string | null {
  if (!value) return null;
  return typeof value === 'string' ? value : value.id;
}

function sameDigest(hexA: string, hexB: string): boolean {
  if (!/^[0-9a-f]{64}$/.test(hexA) || !/^[0-9a-f]{64}$/.test(hexB)) return false;
  return timingSafeEqual(Buffer.from(hexA, 'hex'), Buffer.from(hexB, 'hex'));
}

/**
 * Saving it again with the same token and session (a lost answer): the same card; anything else with
 * that token: a 400. A card the client removed (or asked to) isn't saved again: a 404, add it again.
 */
function repeat(existing: SavedCardRow, sessionId: string): Response {
  if (!cardKept(existing)) throw unknownSession();
  if (existing.checkout_session_id !== sessionId) throw tokenUsed();
  return json({ card: savedCardJSON(existing) });
}

export async function saveCard(ctx: Context): Promise<Response> {
  const { request, deps } = ctx;
  const shop = await shopStripe(deps, { forClients: true });
  const token = requiredCardToken(request);
  const { sessionId } = parse(saveBody, await readJsonObject(request));
  const tokenHash = hashManageToken(token);

  // Answered before the rate limit: it saves nothing new. A card the client removed stays removed.
  const existing = await findCardByToken(deps.db, token);
  if (existing) return repeat(existing, sessionId);

  await limit(deps, request, 'card-save', CARD_SAVES_PER_IP_PER_HOUR);

  let session: Stripe.Checkout.Session;
  try {
    session = await shop.stripe.checkout.sessions.retrieve(sessionId, { expand: ['setup_intent.payment_method'] }, requestOptions(shop));
  } catch (error) {
    throw stripeFailure(deps, error, 'retrieve card checkout');
  }
  // Only sessions this server made for this very token: anyone else who learns the session id gets nothing.
  if (session.id !== sessionId || session.metadata?.purpose !== CHECKOUT_PURPOSE) throw unknownSession();
  if (!sameDigest(session.metadata?.card_token_sha256 ?? '', tokenHash)) throw unknownSession();
  if (session.mode !== 'setup') throw unknownSession();
  if (session.status !== 'complete') throw notFinished();

  const setupIntent = typeof session.setup_intent === 'object' ? session.setup_intent : null;
  if (!setupIntent || setupIntent.status !== 'succeeded') throw notFinished();
  const paymentMethod = typeof setupIntent.payment_method === 'object' ? setupIntent.payment_method : null;
  const card = paymentMethod?.type === 'card' ? paymentMethod.card : null;
  if (!paymentMethod || !card) throw new ApiError('invalid_request', 'Only a card can be saved for no-show protection. Add a card.');
  const customerId = idOf(setupIntent.customer) ?? idOf(session.customer);
  if (!customerId) throw stripeFailure(deps, new Error('Completed setup session has no customer'), 'retrieve card checkout');
  if (!cardValidAt({ exp_month: card.exp_month, exp_year: card.exp_year }, deps.now(), deps.catalog.timeZone)) {
    throw new ApiError('invalid_request', 'That card has expired. Add another card.');
  }

  const { rows } = await deps.db.query<SavedCardRow>(
    `INSERT INTO saved_cards (id, token_hash, checkout_session_id, stripe_customer_id, stripe_payment_method_id,
                              brand, last4, exp_month, exp_year, livemode, created_at, stripe_account_id)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
     ON CONFLICT DO NOTHING
     RETURNING *`,
    [
      deps.uuid(),
      tokenHash,
      session.id,
      customerId,
      paymentMethod.id,
      normalizedBrand(card.brand),
      card.last4,
      card.exp_month,
      card.exp_year,
      session.livemode,
      deps.now(),
      shop.stripeAccount ?? null,
    ],
  );
  const saved = rows[0];
  if (saved) return json({ card: savedCardJSON(saved) }, 201);
  // Another copy of this request saved it a moment ago (or the session is already saved): answer like a repeat.
  const now = await findCardByToken(deps.db, token);
  if (now) return repeat(now, sessionId);
  throw unknownSession();
}

/** Stripe's brand ("visa", "amex", "cartes_bancaires"), kept to what the database accepts. */
function normalizedBrand(brand: string | null | undefined): string {
  const b = (brand ?? '').toLowerCase();
  return /^[a-z0-9_]{1,40}$/.test(b) ? b : 'unknown';
}

// DELETE /api/cards (X-Card-Token): the client removes their saved card ("Remove card", "Forget my
// details", "Forget me", or right after a booking made without Remember me).

export const CARD_DELETED_MESSAGE = "Your saved card is deleted. It can't be charged any more.";
export const CARD_SCHEDULED_MESSAGE = 'Your card will be deleted as soon as your appointments no longer need it.';

/**
 * Deletes the card at Stripe now (`deleted`), or, while a booking still needs it (upcoming, still
 * chargeable before the 7-day deadline, or a fee pending), marks it so the daily job deletes it once
 * none does (`scheduled`). Either way it can't book again. Doing it again answers the same; a token
 * with no card is a 404.
 */
export async function deleteCard(ctx: Context): Promise<Response> {
  const { request, deps } = ctx;
  const token = requiredCardToken(request);
  const card = await findCardByToken(deps.db, token);
  if (!card) throw new ApiError('not_found', "We couldn't find that card.");
  const status = await removeCard(deps, card, deps.now());
  return json({ cardDeletion: { status, message: status === 'deleted' ? CARD_DELETED_MESSAGE : CARD_SCHEDULED_MESSAGE } });
}

// Booking with a card on file (POST /api/appointments with X-Card-Token).

/** What a protected booking stores: the card, the policy the client agreed to, and each possible offering's fee. */
export interface NoShowTerms {
  card: SavedCardRow;
  policyText: string;
  /** The late-cancellation window that policy states, or null when it has none. */
  lateCancelWindowMinutes: number | null;
  fees: Map<string, number | null>;
}

/**
 * The no-show terms for a customer booking, or null when it isn't protected
 * (Stripe not set up, or in connect mode no account that can take card payments;
 * protection off; or no fee for this booking): then no card is needed and any
 * card token is ignored. When it is protected, the booking needs a saved card
 * that's on the shop's current Stripe account, in the same mode (test or live),
 * and good through the appointment's month, and the policy text the client
 * agreed to must be today's policy for this booking.
 */
export async function noShowTermsForBooking(
  deps: Deps,
  target: Target,
  start: Date,
  cardToken: string | undefined,
  agreedPolicy: string | undefined,
): Promise<NoShowTerms | null> {
  const shop = await shopAccount(deps);
  if (!shop) return null;
  const { policy, fees } = protectionFor(target, await loadNoShowSettings(deps.db), true);
  if (!policy.required || !policy.policyText) return null;
  if (!cardToken) throw new ApiError('card_required', "Add a card to book this time. You won't be charged now.");
  // A card the client removed (or asked to, or saved without Remember me) doesn't book again.
  const found = await findCardByToken(deps.db, cardToken);
  const card = found && cardKept(found) ? found : null;
  const match = card ? accountMatch(card, shop) : null;
  // A card saved with the shop's earlier Stripe account can't be charged with this one.
  if (match === 'otherAccount') throw new ApiError('card_required', 'Add your card again: the shop changed its payment account.');
  // A card saved while the shop was in test mode can't be charged with a live key (or the other way round).
  if (!card || match !== 'same') {
    throw new ApiError('card_required', "We couldn't find your saved card. Add it again.");
  }
  if (!cardValidAt(card, start, deps.catalog.timeZone)) {
    throw new ApiError('card_required', 'That card expires before your appointment. Add another card.');
  }
  if (agreedPolicy !== policy.policyText) {
    throw new ApiError('policy_changed', 'The no-show policy for this booking just changed. Check it and book again.');
  }
  return { card, policyText: policy.policyText, lateCancelWindowMinutes: policy.lateCancelWindowMinutes, fees };
}
