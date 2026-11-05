import { DateTime } from 'luxon';
import type Stripe from 'stripe';
import { requireOwner } from './auth.js';
import type { Queryable } from './db.js';
import type { Deps } from './deps.js';
import { FEE_KIND, feeCaseAt, isFeeKind, nothingCharged, reasonOfKind, type FeeKind, type FeeReason } from './feecase.js';
import { ApiError, json } from './http.js';
import type { Context } from './router.js';
import {
  accountMatch,
  requestOptions,
  shopStripe,
  stripeFailure,
  stripeSetup,
  succeededAt,
  type ShopStripe,
  type StripeErrorLike,
} from './stripeaccount.js';
import { appointmentJSON, type AppointmentRow, type NoShowFeeRowStatus } from './serialize.js';
import { UUID_RE } from './validation.js';

// Charging the fee to the card on file (POST /api/owner/appointments/:id/no-show-fee): for a
// no-show, or for a late cancellation (feecase.ts decides which, if either, applies).
//
// At most one fee per appointment: the appointment row is locked while the next
// step is decided, Stripe gets an idempotency key made from the appointment id
// and the attempt number, and only a PaymentIntent Stripe reports as succeeded
// ever makes the fee "charged". A try whose answer was lost keeps the same key,
// and before sending it again the server asks Stripe for that attempt's
// PaymentIntent (Stripe may forget a key after 24 hours, and then a reused key
// would charge again); only a definite "no" from Stripe (declined, or the bank
// wants the client to approve it) lets the next try make a new one. When Stripe
// has nothing for that try and the booking can't be charged any more (the shop
// reopened it, say), the fee is settled as not charged instead of staying
// pending for good; a later charge picks up that same try (same key) first.
//
// A client who cancelled in the app before the start (or asked to) is never
// charged a no-show fee, even if the shop reopened the booking since; only a
// cancellation inside the agreed late-cancellation window, which stayed
// cancelled by the client, can be charged (as a late cancellation). That's the
// policy they agreed to.
//
// With Stripe Connect, the fee is charged on the account the card was saved on
// (and looked up there), so a card saved before the shop connected another
// account can't be charged any more.

const notFound = () => new ApiError('not_found', "We couldn't find that appointment.");
const notChargeable = (message: string) => new ApiError('not_chargeable', message);
export const OLD_ACCOUNT_MESSAGE = "This card was saved with the shop's old Stripe account.";
/** The card was deleted (the client removed it, or it went unused): nothing can be charged to it. */
export const CARD_DELETED_MESSAGE = "The client's saved card was deleted, so it can't be charged.";
/** A fee whose answer was lost, on a card Stripe can't be asked about from here (see `chargeNoShowFee`). */
export const UNCHECKABLE_FEE_MESSAGE =
  "This card was saved with the shop's old Stripe account, so the app can't check whether its fee went through. Look for it in that Stripe account's Dashboard.";
/** A card saved while the shop's Stripe was in the other mode (test or live) is only there, in that mode. */
const otherModeMessage = (savedLive: boolean) =>
  savedLive
    ? "This card was saved while the shop's Stripe was live, so it can't be charged in test mode."
    : "This card was saved while the shop's Stripe was in test mode, so it can't be charged.";

/** Stripe's idempotency key for one attempt at one appointment's fee. */
export function noShowFeeIdempotencyKey(appointmentId: string, attempt: number): string {
  return `izzy-no-show-fee-${appointmentId}-${attempt}`;
}

/** What a PaymentIntent's status means for the fee. Only `succeeded` is "charged". */
export function feeStatusFor(status: string): NoShowFeeRowStatus {
  switch (status) {
    case 'succeeded':
      return 'charged';
    case 'requires_action':
      return 'needs_action';
    case 'requires_payment_method':
    case 'canceled':
      return 'declined';
    default:
      // processing, requires_confirmation, requires_capture: not money yet, maybe later.
      return 'pending';
  }
}

export const AUTHENTICATION_MESSAGE =
  "The client's bank wants them to approve this charge, so it can't go through from here. Ask them to pay at the shop.";
export const UNUSABLE_CARD_MESSAGE = "Stripe couldn't use the saved card. Ask the client to pay at the shop.";

/** Why a card was turned down, in plain words for the owner (never "lost" or "stolen": just declined). */
export function declineMessage(error: { code?: string | null; decline_code?: string | null } | null | undefined): string {
  const code = error?.decline_code ?? error?.code ?? '';
  switch (code) {
    case 'authentication_required':
      return AUTHENTICATION_MESSAGE;
    case 'insufficient_funds':
      return "The card was declined: there isn't enough money on it.";
    case 'expired_card':
      return 'The card has expired.';
    case 'incorrect_cvc':
    case 'invalid_cvc':
    case 'incorrect_number':
    case 'invalid_number':
    case 'invalid_expiry_month':
    case 'invalid_expiry_year':
    case 'incorrect_zip':
      return "The card's details didn't work.";
    case 'processing_error':
      return "The bank couldn't process the card. Try again in a while.";
    case 'card_decline_rate_limit_exceeded':
      return 'The card was declined too many times today. Try again tomorrow.';
    default:
      return error?.code === 'authentication_required' ? AUTHENTICATION_MESSAGE : 'The bank declined the card.';
  }
}

interface ChargeRow extends AppointmentRow {
  stripe_customer_id: string | null;
  stripe_payment_method_id: string | null;
  /** The connected account the card is saved on (null: saved with the server's own key). */
  card_stripe_account_id: string | null;
  /** Whether the card was saved in live mode (null without a card). */
  card_livemode: boolean | null;
}

type Claim =
  | { kind: 'done'; row: AppointmentRow }
  | { kind: 'retrieve'; row: ChargeRow; paymentIntentId: string }
  /**
   * A new attempt, or (`resumed`) the current one again after its answer was lost (or after it
   * was settled as not charged): then Stripe is asked for that attempt's PaymentIntent first,
   * and `refusal` (why it can't be charged now, if anything changed) stops a new request and
   * settles a pending try Stripe has nothing for. `reason` is what the attempt charges for.
   */
  | { kind: 'create'; row: ChargeRow; attempt: number; attemptAt: Date; resumed: boolean; refusal: ApiError | null; reason: FeeReason };

/** The parts of a PaymentIntent the fee follows. */
export interface FeeIntent {
  id: string;
  status: string;
  last_payment_error?: { code?: string | null; decline_code?: string | null } | null;
  /** When Stripe made it (Unix seconds), if known. */
  created?: number | null;
}

const FEE_TITLE: Record<FeeReason, string> = { no_show: 'No-show fee', late_cancel: 'Late cancellation fee' };

/** "No-show fee: Haircut with Flowxbori, Tue, Nov 3 at 10:00 AM" (shop time), or "Late cancellation fee: …". */
export function feeDescription(row: Pick<AppointmentRow, 'start_at' | 'service_name' | 'barber_name'>, zone: string, reason: FeeReason): string {
  const when = DateTime.fromJSDate(row.start_at, { zone }).setLocale('en-US').toFormat("ccc, LLL d 'at' h:mm a");
  return `${FEE_TITLE[reason]}: ${row.service_name} with ${row.barber_name}, ${when}`.slice(0, 200);
}

/** Whether Stripe's error says the bank wants the client to approve the charge (an off-session charge can't). */
export function needsTheClient(error: { code?: string | null; decline_code?: string | null } | null | undefined): boolean {
  return error?.code === 'authentication_required' || error?.decline_code === 'authentication_required';
}

/**
 * The fee's status and message for a PaymentIntent Stripe answered with. A failed
 * off-session charge leaves the PaymentIntent in requires_payment_method; when its
 * last_payment_error is authentication_required, that's "needs the client", not a decline.
 */
export function outcomeOf(intent: FeeIntent): { status: NoShowFeeRowStatus; message: string | null } {
  const status = feeStatusFor(intent.status);
  if (status === 'needs_action') return { status, message: AUTHENTICATION_MESSAGE };
  if (status === 'declined') {
    if (intent.status === 'canceled') return { status, message: 'The charge was cancelled in Stripe.' };
    if (needsTheClient(intent.last_payment_error)) return { status: 'needs_action', message: AUTHENTICATION_MESSAGE };
    return { status, message: declineMessage(intent.last_payment_error) };
  }
  return { status, message: null };
}

/** How far before the attempt's start the lookup reaches, in case this server's clock is ahead of Stripe's. */
const LOOKUP_SLACK_SECONDS = 3600;
/** Pages of 100 to look through; one saved card's Stripe Customer has a handful of PaymentIntents. */
const LOOKUP_MAX_PAGES = 20;

/**
 * This appointment's PaymentIntent for `attempt`, if Stripe has one: found among the
 * PaymentIntents of the card's own Stripe Customer created since the attempt began, by
 * the metadata the charge carries. Null when Stripe has none (the request never reached it).
 */
export async function findAttemptIntent(
  shop: ShopStripe,
  customerId: string,
  appointmentId: string,
  attempt: number,
  since: Date,
): Promise<Stripe.PaymentIntent | null> {
  const params: Stripe.PaymentIntentListParams = {
    customer: customerId,
    created: { gte: Math.floor(since.getTime() / 1000) - LOOKUP_SLACK_SECONDS },
    limit: 100,
  };
  for (let page = 0; page < LOOKUP_MAX_PAGES; page++) {
    const list = await shop.stripe.paymentIntents.list(params, requestOptions(shop));
    const match = list.data.find(
      (pi) => isFeeKind(pi.metadata?.kind) && pi.metadata?.appointment_id === appointmentId && pi.metadata?.attempt === String(attempt),
    );
    if (match) return match;
    const last = list.data.at(-1);
    if (!list.has_more || !last) return null;
    params.starting_after = last.id;
  }
  // Never guess "not there": sending the request again could charge twice.
  throw new Error(`More than ${LOOKUP_MAX_PAGES} pages of PaymentIntents for one saved card`);
}

/**
 * Records what Stripe said about one of an appointment's fee PaymentIntents, in
 * the caller's transaction: the payment (kind no_show_fee or late_cancel_fee, so
 * Payments today lists it as such, with the account it was charged on) and the appointment's fee. "Charged" is final; any fee
 * PaymentIntent of this appointment that succeeded makes it charged (money
 * moved, so it must never look chargeable again). Anything else only counts
 * for the current attempt, and "pending" never undoes a decline of the same
 * PaymentIntent (Stripe's events can arrive out of order).
 *
 * A fee that succeeded is charged at `succeeded` (when Stripe says it went through,
 * `succeededAt`; by default, when Stripe made it, since an off-session charge goes
 * through or not right away): the appointment's chargedAt, and the day it counts in the
 * analytics (payments.succeeded_at), even when Stripe finished it days after it was tried.
 */
export async function recordFeeIntent(
  tx: Queryable,
  row: Pick<AppointmentRow, 'id' | 'no_show_fee_cents'> & { description: string; kind: FeeKind; stripeAccountId: string | null },
  intent: FeeIntent,
  attempt: number | null,
  now: Date,
  options: { override?: { status: NoShowFeeRowStatus; message: string | null }; succeeded?: Date } = {},
): Promise<AppointmentRow | null> {
  const { status, message } = options.override ?? outcomeOf(intent);
  // Dated when Stripe made it, so a charge found after a lost answer lands on the day the money moved.
  const made = typeof intent.created === 'number' ? new Date(intent.created * 1000) : null;
  const createdAt = made && made < now ? made : now;
  const succeeded = options.succeeded ?? createdAt;
  const { rows } = await tx.query<AppointmentRow>(
    `UPDATE appointments
        SET no_show_fee_status = $3,
            no_show_fee_payment_intent_id = $2,
            no_show_fee_message = $4,
            no_show_fee_charged_at = CASE WHEN $3 = 'charged' THEN $7::timestamptz ELSE NULL END,
            updated_at = $5
      WHERE id = $1
        AND saved_card_id IS NOT NULL
        AND no_show_fee_status <> 'charged'
        AND ($3 = 'charged' OR no_show_fee_attempt = $6 OR no_show_fee_payment_intent_id = $2)
        AND NOT ($3 = 'pending' AND no_show_fee_status IN ('declined', 'needs_action') AND no_show_fee_payment_intent_id = $2)
      RETURNING *`,
    [row.id, intent.id, status, message, now, attempt, succeeded],
  );
  if (row.no_show_fee_cents !== null && /^pi_[A-Za-z0-9_]+$/.test(intent.id)) {
    // succeeded and canceled are final in Stripe, so a late or replayed event can't undo them.
    await tx.query(
      `INSERT INTO payments (id, amount_cents, description, appointment_id, status, receipt_email, created_at, updated_at, kind, stripe_account_id, succeeded_at)
       VALUES ($1, $2, $3, $4, $5, NULL, $8, $6, $7, $9, CASE WHEN $5 = 'succeeded' THEN $10::timestamptz END)
       ON CONFLICT (id) DO UPDATE SET status = EXCLUDED.status, updated_at = EXCLUDED.updated_at, succeeded_at = EXCLUDED.succeeded_at
         WHERE payments.status <> EXCLUDED.status AND payments.status NOT IN ('succeeded', 'canceled')`,
      [intent.id, row.no_show_fee_cents, row.description, row.id, intent.status, now, row.kind, createdAt, row.stripeAccountId, succeeded],
    );
  }
  if (rows[0]) return rows[0];
  const { rows: current } = await tx.query<AppointmentRow>('SELECT * FROM appointments WHERE id = $1', [row.id]);
  return current[0] ?? null;
}

/**
 * A Stripe error that is Stripe's definite "no" to the charge, with what it
 * means for the fee; null when the outcome isn't known (a timeout, an outage)
 * or the request never reached a charge (a bad key, a rate limit), so the same
 * attempt and key are used again.
 */
function definiteNo(error: unknown): { intent: FeeIntent | null; status: NoShowFeeRowStatus; message: string } | null {
  if (typeof error !== 'object' || error === null) return null;
  const e = error as StripeErrorLike & { decline_code?: string; payment_intent?: Stripe.PaymentIntent };
  const intent = e.payment_intent && typeof e.payment_intent.id === 'string' ? e.payment_intent : null;
  if (e.type === 'StripeCardError') {
    const needsClient = needsTheClient({ code: e.code ?? null, decline_code: e.decline_code ?? null });
    return {
      intent,
      status: needsClient ? 'needs_action' : 'declined',
      message: needsClient ? AUTHENTICATION_MESSAGE : declineMessage({ code: e.code ?? null, decline_code: e.decline_code ?? null }),
    };
  }
  if (e.type === 'StripeInvalidRequestError' && e.code !== 'idempotency_key_in_use') {
    // e.g. the card was removed from its Stripe customer: this card can't be charged.
    return { intent, status: 'declined', message: UNUSABLE_CARD_MESSAGE };
  }
  return null;
}

/**
 * A pending try Stripe has no PaymentIntent for, on a booking that can't be charged any more (the
 * shop reopened it, say): nothing was charged, so it's settled as that, status `none` again. Its
 * attempt is kept, so a later charge picks it up first (same key, looked up at Stripe). The answer
 * is a 409 saying so, or, if an answer from Stripe was recorded meanwhile (a webhook), the
 * appointment as it is now.
 */
async function settleUnsent(deps: Deps, id: string, attempt: number, refusal: ApiError): Promise<Response> {
  const { rows } = await deps.db.query<AppointmentRow>(
    `UPDATE appointments
        SET no_show_fee_status = 'none', no_show_fee_message = NULL, updated_at = $3
      WHERE id = $1 AND no_show_fee_status = 'pending' AND no_show_fee_attempt = $2 AND no_show_fee_payment_intent_id IS NULL
      RETURNING *`,
    [id, attempt, deps.now()],
  );
  if (rows[0]) {
    deps.log.warn('Settled a fee Stripe never got as not charged', { appointmentId: id, attempt });
    throw notChargeable(nothingCharged(refusal.message));
  }
  const { rows: current } = await deps.db.query<AppointmentRow>('SELECT * FROM appointments WHERE id = $1', [id]);
  const row = current[0];
  if (!row) throw notFound();
  if (row.no_show_fee_status === 'none') throw notChargeable(nothingCharged(refusal.message));
  return json({ appointment: appointmentJSON(row) });
}

/**
 * What this booking (it has a card on file) can be charged for now, or why it can't be
 * (`feeCaseAt`): a no-show only once the appointment has ended, and nothing more than 7 days
 * after its start. A try already pending is still looked up after that (see `chargeNoShowFee`):
 * only a new request to Stripe is refused.
 */
function chargeCase(row: AppointmentRow, now: Date): { reason: FeeReason; refusal: null } | { reason: null; refusal: ApiError } {
  const found = feeCaseAt(row, now);
  if (found.reason === null) return { reason: null, refusal: notChargeable(found.refusal) };
  return { reason: found.reason, refusal: null };
}

export async function chargeNoShowFee(ctx: Context): Promise<Response> {
  await requireOwner(ctx);
  const { deps } = ctx;
  // The shop's account now: 503 while Stripe is off (or, with Connect, not connected), as before.
  const current = await shopStripe(deps);
  const id = ctx.params.id ?? '';
  if (!UUID_RE.test(id)) throw notFound();
  const now = deps.now();

  const claim = await deps.db.transaction(async (tx): Promise<Claim> => {
    const { rows } = await tx.query<ChargeRow>(
      `SELECT a.*, c.stripe_customer_id, c.stripe_payment_method_id, c.stripe_account_id AS card_stripe_account_id, c.livemode AS card_livemode
         FROM appointments a LEFT JOIN saved_cards c ON c.id = a.saved_card_id
        WHERE a.id = $1
        FOR UPDATE OF a`,
      [id],
    );
    const row = rows[0];
    if (!row) throw notFound();
    // Already charged: the same answer again, nothing new at Stripe (a retry after a lost answer).
    if (row.no_show_fee_status === 'charged') return { kind: 'done', row };
    // A charge Stripe hasn't finished with: ask Stripe how it went, whatever happened since.
    if (row.no_show_fee_status === 'pending' && row.no_show_fee_payment_intent_id) {
      return { kind: 'retrieve', row, paymentIntentId: row.no_show_fee_payment_intent_id };
    }
    if (!row.saved_card_id || row.no_show_fee_cents === null) {
      throw notChargeable("This booking has no card on file, so there's no fee to charge.");
    }
    const chargeable = chargeCase(row, now);
    // The card was deleted at Stripe (retention.ts) once no booking needed it: why there's no fee, if
    // there's another reason, or else that the card is gone.
    if (!row.stripe_customer_id || !row.stripe_payment_method_id) throw chargeable.refusal ?? notChargeable(CARD_DELETED_MESSAGE);
    // The card can only be charged on the account it was saved on, in the mode it was saved in,
    // and those must be the shop's now.
    const savedLive = row.card_livemode === true;
    const match = accountMatch({ stripe_account_id: row.card_stripe_account_id, livemode: savedLive }, current);
    const unusable = match === 'otherAccount' ? notChargeable(OLD_ACCOUNT_MESSAGE) : match === 'otherMode' ? notChargeable(otherModeMessage(savedLive)) : null;
    const refusal = chargeable.refusal ?? unusable;
    // A try whose answer never came keeps its attempt (Stripe key and reason) and is looked up
    // first, whatever happened since; after a "no", a new attempt, only for a chargeable case.
    const pending = row.no_show_fee_status === 'pending';
    // A try settled as not charged (Stripe had nothing for it when the booking couldn't be charged
    // any more): charging again picks up that same attempt, looked up first, so a request of it that
    // reached Stripe late is found (or deduplicated by its key), never charged a second time.
    const settled = row.no_show_fee_status === 'none' && row.no_show_fee_attempt > 0;
    const resumed = pending || settled;
    // Only a pending try is looked up when the booking can't be charged now (to settle it).
    if (refusal && !pending) throw refusal;
    const attempt = resumed ? Math.max(row.no_show_fee_attempt, 1) : row.no_show_fee_attempt + 1;
    const attemptAt = resumed && row.no_show_fee_attempt_at ? row.no_show_fee_attempt_at : now;
    const reason: FeeReason = (resumed ? row.no_show_fee_reason : chargeable.reason) ?? chargeable.reason ?? 'no_show';
    if (!refusal) {
      await tx.query(
        `UPDATE appointments
            SET no_show_fee_status = 'pending', no_show_fee_attempt = $2, no_show_fee_attempt_at = $4, no_show_fee_reason = $5,
                no_show_fee_payment_intent_id = NULL, no_show_fee_message = NULL, updated_at = $3
          WHERE id = $1`,
        [id, attempt, now, attemptAt, reason],
      );
    }
    return { kind: 'create', row, attempt, attemptAt, resumed, refusal, reason };
  });

  if (claim.kind === 'done') return json({ appointment: appointmentJSON(claim.row) });
  // A pending PaymentIntent (retrieve) belongs to the attempt already on the row.
  const reason: FeeReason = claim.kind === 'create' ? claim.reason : (claim.row.no_show_fee_reason ?? 'no_show');
  const description = feeDescription(claim.row, deps.catalog.timeZone, reason);
  // Every call about this fee goes to the account the card is saved on. Only there can Stripe say
  // whether it went through: the connected account (connect mode), or the server key's own (a card
  // saved in direct mode). A card from the other setup can't be asked about from here, and its fee
  // is never taken for "nothing was charged".
  const cardAccount = claim.row.card_stripe_account_id ?? null;
  const checkable = (cardAccount !== null) === (stripeSetup(deps.config) === 'connect');
  if (!checkable && cardAccount === null) throw notChargeable(UNCHECKABLE_FEE_MESSAGE);
  const onCard = await shopStripe(deps, { account: cardAccount });
  const recordRow = { id, no_show_fee_cents: claim.row.no_show_fee_cents, description, kind: FEE_KIND[reason], stripeAccountId: cardAccount };

  if (claim.kind === 'retrieve') {
    let intent: Stripe.PaymentIntent;
    try {
      // With its charge, whose time is when the fee went through (it may have taken Stripe a while).
      intent = await onCard.stripe.paymentIntents.retrieve(claim.paymentIntentId, { expand: ['latest_charge'] }, requestOptions(onCard));
    } catch (error) {
      throw stripeFailure(deps, error, 'retrieve no-show fee');
    }
    const now = deps.now();
    const updated = await deps.db.transaction((tx) =>
      recordFeeIntent(tx, recordRow, intent, claim.row.no_show_fee_attempt, now, { succeeded: succeededAt(intent, now, intent.created) }),
    );
    return json({ appointment: appointmentJSON(updated ?? claim.row) });
  }

  const { row, attempt } = claim;
  if (claim.resumed) {
    // The answer to this attempt was lost. Stripe may have charged it, and may have forgotten its
    // idempotency key by now (after 24 hours), so ask for the PaymentIntent before sending it again.
    let found: Stripe.PaymentIntent | null;
    try {
      found = await findAttemptIntent(onCard, row.stripe_customer_id ?? '', id, attempt, claim.attemptAt);
    } catch (error) {
      throw stripeFailure(deps, error, 'find no-show fee');
    }
    if (found) {
      const updated = await deps.db.transaction((tx) => recordFeeIntent(tx, recordRow, found, attempt, deps.now()));
      return json({ appointment: appointmentJSON(updated ?? row) });
    }
    // Nothing reached Stripe: send it again (same key), unless it can't be charged any more. Then
    // nothing was charged, so the try is settled as that instead of staying pending for good; but
    // only when Stripe was asked on the card's own account, where "none" really means none.
    if (claim.refusal) {
      if (!checkable) throw notChargeable(UNCHECKABLE_FEE_MESSAGE);
      return settleUnsent(deps, id, attempt, claim.refusal);
    }
  }
  let intent: Stripe.PaymentIntent;
  try {
    intent = await onCard.stripe.paymentIntents.create(
      {
        amount: row.no_show_fee_cents ?? 0,
        currency: 'usd',
        customer: row.stripe_customer_id ?? undefined,
        payment_method: row.stripe_payment_method_id ?? undefined,
        // The client isn't here to approve anything; a bank that wants them to is a "needs the client" answer.
        off_session: true,
        confirm: true,
        // Not payment_method_types: that's a 400 since API version 2026-09-30.endive.
        allowed_payment_method_types: ['card'],
        description,
        // No receipt_email: an address Stripe turned down would fail the charge for a reason that isn't the card.
        metadata: { source: 'izzy-clipz-api', kind: FEE_KIND[reason], appointment_id: id, attempt: String(attempt) },
      },
      requestOptions(onCard, { idempotencyKey: noShowFeeIdempotencyKey(id, attempt) }),
    );
  } catch (error) {
    const no = definiteNo(error);
    if (!no) {
      if ((error as StripeErrorLike | null)?.type === 'StripeIdempotencyError' || (error as StripeErrorLike | null)?.code === 'idempotency_key_in_use') {
        stripeFailure(deps, error, 'charge no-show fee');
        throw notChargeable('This fee is being charged right now. Check the appointment again in a moment.');
      }
      // Unknown outcome: the fee stays pending, and charging again asks Stripe with the same key.
      throw stripeFailure(deps, error, 'charge no-show fee');
    }
    deps.log.warn('Stripe declined a no-show fee', {
      appointmentId: id,
      attempt,
      code: (error as StripeErrorLike).code,
      declineCode: (error as { decline_code?: string }).decline_code,
      requestId: (error as StripeErrorLike).requestId,
    });
    const updated = await deps.db.transaction(async (tx) => {
      if (no.intent) return recordFeeIntent(tx, recordRow, no.intent, attempt, deps.now(), { override: { status: no.status, message: no.message } });
      const { rows } = await tx.query<AppointmentRow>(
        `UPDATE appointments SET no_show_fee_status = $2, no_show_fee_message = $3, updated_at = $4
          WHERE id = $1 AND no_show_fee_status = 'pending' AND no_show_fee_attempt = $5
          RETURNING *`,
        [id, no.status, no.message, deps.now(), attempt],
      );
      return rows[0] ?? null;
    });
    return json({ appointment: appointmentJSON(updated ?? row) });
  }
  const updated = await deps.db.transaction((tx) => recordFeeIntent(tx, recordRow, intent, attempt, deps.now()));
  return json({ appointment: appointmentJSON(updated ?? row) });
}

/**
 * The webhook's part (POST /api/stripe/webhook, and …/complete): a fee PaymentIntent
 * (no-show or late cancellation) Stripe tells us about, found by our payments row
 * or, if the server stopped before writing it, by the PaymentIntent's metadata.
 * `paymentKind` is our payments row's kind, when there is one; `stripeAccountId`
 * the account the PaymentIntent is on (null: the server's own key); `succeeded`
 * when Stripe says it went through (the event's time, or its charge's).
 */
export async function syncNoShowFeeFromStripe(
  tx: Queryable,
  intent: FeeIntent & { metadata?: Record<string, string> | null },
  paymentAppointmentId: string | null,
  deps: Pick<Deps, 'catalog'>,
  now: Date,
  paymentKind: string | null,
  stripeAccountId: string | null,
  succeeded?: Date,
): Promise<void> {
  const appointmentId = paymentAppointmentId ?? intent.metadata?.appointment_id ?? '';
  if (!UUID_RE.test(appointmentId)) return;
  const { rows } = await tx.query<AppointmentRow>('SELECT * FROM appointments WHERE id = $1 FOR UPDATE', [appointmentId]);
  const row = rows[0];
  if (!row || !row.saved_card_id || row.no_show_fee_cents === null) return;
  const attemptText = intent.metadata?.attempt ?? '';
  const attempt = /^\d{1,6}$/.test(attemptText) ? Number(attemptText) : null;
  const metadataKind = intent.metadata?.kind;
  const kind: FeeKind = isFeeKind(paymentKind) ? paymentKind : isFeeKind(metadataKind) ? metadataKind : FEE_KIND[row.no_show_fee_reason ?? 'no_show'];
  await recordFeeIntent(
    tx,
    {
      id: row.id,
      no_show_fee_cents: row.no_show_fee_cents,
      description: feeDescription(row, deps.catalog.timeZone, reasonOfKind(kind)),
      kind,
      stripeAccountId,
    },
    intent,
    attempt,
    now,
    { succeeded },
  );
}
