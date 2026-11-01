import { DateTime } from 'luxon';
import type Stripe from 'stripe';
import { requireOwner } from './auth.js';
import type { Queryable } from './db.js';
import type { Deps } from './deps.js';
import { ApiError, json } from './http.js';
import { stripeClient, stripeFailure, type StripeErrorLike } from './payments.js';
import type { Context } from './router.js';
import { appointmentJSON, type AppointmentRow, type NoShowFeeRowStatus } from './serialize.js';
import { UUID_RE } from './validation.js';

// Charging a no-show fee to the card on file (POST /api/owner/appointments/:id/no-show-fee).
//
// At most one fee per appointment: the appointment row is locked while the next
// step is decided, Stripe gets an idempotency key made from the appointment id
// and the attempt number, and only a PaymentIntent Stripe reports as succeeded
// ever makes the fee "charged". A try whose answer was lost keeps the same key,
// so trying again can't charge twice; only a definite "no" from Stripe (declined,
// or the bank wants the client to approve it) lets the next try make a new one.

const notFound = () => new ApiError('not_found', "We couldn't find that appointment.");
const notChargeable = (message: string) => new ApiError('not_chargeable', message);

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
}

type Claim =
  | { kind: 'done'; row: AppointmentRow }
  | { kind: 'retrieve'; row: ChargeRow; paymentIntentId: string }
  | { kind: 'create'; row: ChargeRow; attempt: number };

/** The parts of a PaymentIntent the fee follows. */
export interface FeeIntent {
  id: string;
  status: string;
  last_payment_error?: { code?: string | null; decline_code?: string | null } | null;
}

/** "No-show fee: Haircut with Flowxbori, Tue, Nov 3 at 10:00 AM" (shop time). */
function feeDescription(row: AppointmentRow, zone: string): string {
  const when = DateTime.fromJSDate(row.start_at, { zone }).setLocale('en-US').toFormat("ccc, LLL d 'at' h:mm a");
  return `No-show fee: ${row.service_name} with ${row.barber_name}, ${when}`.slice(0, 200);
}

/** The fee's status and message for a PaymentIntent Stripe answered with. */
function outcomeOf(intent: FeeIntent): { status: NoShowFeeRowStatus; message: string | null } {
  const status = feeStatusFor(intent.status);
  if (status === 'needs_action') return { status, message: AUTHENTICATION_MESSAGE };
  if (status === 'declined') {
    return { status, message: intent.status === 'canceled' ? 'The charge was cancelled in Stripe.' : declineMessage(intent.last_payment_error) };
  }
  return { status, message: null };
}

/**
 * Records what Stripe said about one of an appointment's fee PaymentIntents, in
 * the caller's transaction: the payment (kind no_show_fee, so Payments today
 * lists it) and the appointment's fee. "Charged" is final; any fee
 * PaymentIntent of this appointment that succeeded makes it charged (money
 * moved, so it must never look chargeable again). Anything else only counts
 * for the current attempt, and "pending" never undoes a decline of the same
 * PaymentIntent (Stripe's events can arrive out of order).
 */
export async function recordFeeIntent(
  tx: Queryable,
  row: Pick<AppointmentRow, 'id' | 'no_show_fee_cents'> & { description: string },
  intent: FeeIntent,
  attempt: number | null,
  now: Date,
  override?: { status: NoShowFeeRowStatus; message: string | null },
): Promise<AppointmentRow | null> {
  const { status, message } = override ?? outcomeOf(intent);
  const { rows } = await tx.query<AppointmentRow>(
    `UPDATE appointments
        SET no_show_fee_status = $3,
            no_show_fee_payment_intent_id = $2,
            no_show_fee_message = $4,
            no_show_fee_charged_at = CASE WHEN $3 = 'charged' THEN $5::timestamptz ELSE NULL END,
            updated_at = $5
      WHERE id = $1
        AND saved_card_id IS NOT NULL
        AND no_show_fee_status <> 'charged'
        AND ($3 = 'charged' OR no_show_fee_attempt = $6 OR no_show_fee_payment_intent_id = $2)
        AND NOT ($3 = 'pending' AND no_show_fee_status IN ('declined', 'needs_action') AND no_show_fee_payment_intent_id = $2)
      RETURNING *`,
    [row.id, intent.id, status, message, now, attempt],
  );
  if (row.no_show_fee_cents !== null && /^pi_[A-Za-z0-9_]+$/.test(intent.id)) {
    // succeeded and canceled are final in Stripe, so a late or replayed event can't undo them.
    await tx.query(
      `INSERT INTO payments (id, amount_cents, description, appointment_id, status, receipt_email, created_at, updated_at, kind)
       VALUES ($1, $2, $3, $4, $5, NULL, $6, $6, 'no_show_fee')
       ON CONFLICT (id) DO UPDATE SET status = EXCLUDED.status, updated_at = EXCLUDED.updated_at
         WHERE payments.status <> EXCLUDED.status AND payments.status NOT IN ('succeeded', 'canceled')`,
      [intent.id, row.no_show_fee_cents, row.description, row.id, intent.status, now],
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
    const needsClient = e.code === 'authentication_required' || e.decline_code === 'authentication_required';
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

export async function chargeNoShowFee(ctx: Context): Promise<Response> {
  requireOwner(ctx.request, ctx.deps.config);
  const { deps } = ctx;
  const stripe = stripeClient(deps);
  const id = ctx.params.id ?? '';
  if (!UUID_RE.test(id)) throw notFound();
  const now = deps.now();

  const claim = await deps.db.transaction(async (tx): Promise<Claim> => {
    const { rows } = await tx.query<ChargeRow>(
      `SELECT a.*, c.stripe_customer_id, c.stripe_payment_method_id
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
    if (!row.saved_card_id || row.no_show_fee_cents === null || !row.stripe_customer_id || !row.stripe_payment_method_id) {
      throw notChargeable("This booking has no card on file, so there's no fee to charge.");
    }
    if (row.status !== 'no_show') throw notChargeable('Mark the appointment as a no-show first.');
    if (row.start_at > now) throw notChargeable("The appointment hasn't started yet, so it can't be a no-show.");
    // A try whose answer never came keeps its attempt (and Stripe key); after a "no", a new attempt.
    const attempt = row.no_show_fee_status === 'pending' ? Math.max(row.no_show_fee_attempt, 1) : row.no_show_fee_attempt + 1;
    await tx.query(
      `UPDATE appointments
          SET no_show_fee_status = 'pending', no_show_fee_attempt = $2, no_show_fee_payment_intent_id = NULL,
              no_show_fee_message = NULL, updated_at = $3
        WHERE id = $1`,
      [id, attempt, now],
    );
    return { kind: 'create', row, attempt };
  });

  if (claim.kind === 'done') return json({ appointment: appointmentJSON(claim.row) });
  const description = feeDescription(claim.row, deps.catalog.timeZone);
  const recordRow = { id, no_show_fee_cents: claim.row.no_show_fee_cents, description };

  if (claim.kind === 'retrieve') {
    let intent: Stripe.PaymentIntent;
    try {
      intent = await stripe.paymentIntents.retrieve(claim.paymentIntentId);
    } catch (error) {
      throw stripeFailure(deps, error, 'retrieve no-show fee');
    }
    const updated = await deps.db.transaction((tx) => recordFeeIntent(tx, recordRow, intent, claim.row.no_show_fee_attempt, deps.now()));
    return json({ appointment: appointmentJSON(updated ?? claim.row) });
  }

  const { row, attempt } = claim;
  let intent: Stripe.PaymentIntent;
  try {
    intent = await stripe.paymentIntents.create(
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
        metadata: { source: 'izzy-clipz-api', kind: 'no_show_fee', appointment_id: id, attempt: String(attempt) },
      },
      { idempotencyKey: noShowFeeIdempotencyKey(id, attempt) },
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
      if (no.intent) return recordFeeIntent(tx, recordRow, no.intent, attempt, deps.now(), { status: no.status, message: no.message });
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
 * The webhook's part (POST /api/stripe/webhook): a no-show fee PaymentIntent
 * Stripe tells us about, found by our payments row or, if the server stopped
 * before writing it, by the PaymentIntent's metadata.
 */
export async function syncNoShowFeeFromStripe(
  tx: Queryable,
  intent: FeeIntent & { metadata?: Record<string, string> | null },
  paymentAppointmentId: string | null,
  deps: Pick<Deps, 'catalog'>,
  now: Date,
): Promise<void> {
  const appointmentId = paymentAppointmentId ?? intent.metadata?.appointment_id ?? '';
  if (!UUID_RE.test(appointmentId)) return;
  const { rows } = await tx.query<AppointmentRow>('SELECT * FROM appointments WHERE id = $1 FOR UPDATE', [appointmentId]);
  const row = rows[0];
  if (!row || !row.saved_card_id || row.no_show_fee_cents === null) return;
  const attemptText = intent.metadata?.attempt ?? '';
  const attempt = /^\d{1,6}$/.test(attemptText) ? Number(attemptText) : null;
  await recordFeeIntent(
    tx,
    { id: row.id, no_show_fee_cents: row.no_show_fee_cents, description: feeDescription(row, deps.catalog.timeZone) },
    intent,
    attempt,
    now,
  );
}
