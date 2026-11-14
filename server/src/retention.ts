import { DateTime } from 'luxon';
import type { SavedCardRow } from './cards.js';
import type { Queryable } from './db.js';
import type { Deps } from './deps.js';
import { feeCase, pastFeeDeadline } from './feecase.js';
import type { AppointmentRow } from './serialize.js';
import { accessRevoked, requestOptions, shopStripe, stripeFailure, stripeSetup, type StripeErrorLike } from './stripeaccount.js';
import { localDate } from './time.js';

// How long the shop keeps clients' details, as its Privacy Policy says (docs/legal/privacy.md,
// "How long we keep it"; docs/legal/research.md §17; docs/legal/data-inventory.md G1 and G2):
//
// - An appointment's name, number, email and note: 12 months after the appointment, then they're
//   removed, except while a fee for it is still pending. The appointment stays, without them, so
//   the analytics (which never read them) don't change.
// - The client's name on a sale (and why it was voided), and a card payment's description, receipt
//   email and the client's name on its checkout ticket: 12 months.
// - A saved card: deleted at Stripe (detached, and its Customer deleted) once it has expired, gone
//   12 months without being used for a booking, or the client asked (Remove card, Forget my details,
//   or a booking made without Remember me), as soon as no booking still needs it.
//
// The daily job (cron.ts) does all of it in batches; the privacy tools (privacy.ts) do it for one
// person at once.

/** How long details are kept, in months. One place to change it. */
export const RETENTION_MONTHS = 12;
/** What an appointment's name becomes (the column can't be empty). */
export const NAME_REMOVED = 'Name removed';
/** Rows changed per statement, so no statement holds its locks for long. */
export const RETENTION_BATCH = 1_000;
/** How long the daily job may spend on all of it: the function itself may run 30 seconds. */
export const RETENTION_BUDGET_MS = 20_000;

/** The moment before which details are removed: `RETENTION_MONTHS` before `now`. */
export function retentionCutoff(now: Date): Date {
  return DateTime.fromJSDate(now, { zone: 'utc' }).minus({ months: RETENTION_MONTHS }).toJSDate();
}

/** When to stop starting new batches (`Date.now()` milliseconds); tests pass their own. */
export interface Budget {
  stopAt: number;
  clock?: () => number;
  batchSize?: number;
}

const timeLeft = (budget: Budget) => (budget.clock ?? Date.now)() < budget.stopAt;

// Removing the details. Each statement takes ids, so the daily job and the privacy tools share them.

async function anonymizeAppointments(db: Queryable, ids: string[], now: Date): Promise<number> {
  if (ids.length === 0) return 0;
  const result = await db.query(
    `UPDATE appointments
        SET customer_name = '${NAME_REMOVED}', customer_phone = NULL, customer_email = NULL, note = NULL,
            manage_token_hash = NULL, idempotency_key_hash = NULL, no_show_fee_message = NULL,
            anonymized_at = $2, updated_at = $2
      WHERE id = ANY($1::uuid[]) AND anonymized_at IS NULL`,
    [ids, now],
  );
  return result.rowCount ?? 0;
}

async function anonymizeSales(db: Queryable, ids: string[], now: Date): Promise<number> {
  if (ids.length === 0) return 0;
  const result = await db.query(
    `UPDATE sales SET customer_name = NULL, void_reason = NULL, anonymized_at = $2, updated_at = $2
      WHERE id = ANY($1::uuid[]) AND anonymized_at IS NULL`,
    [ids, now],
  );
  return result.rowCount ?? 0;
}

/**
 * A card payment taken at the shop loses its description too (it may name the client); a fee's names
 * only the service. Its checkout ticket loses the client's name and keeps the rest (the items, and
 * the appointment it was for, which `voidSale` still reads to give that appointment back to it).
 */
async function anonymizePayments(db: Queryable, ids: string[], now: Date): Promise<number> {
  if (ids.length === 0) return 0;
  // jsonb_set leaves a payment without a ticket (NULL) as it is.
  const result = await db.query(
    `UPDATE payments
        SET receipt_email = NULL, sale_draft = jsonb_set(sale_draft, '{customerName}', 'null'::jsonb),
            description = CASE WHEN kind = 'in_person' THEN NULL ELSE description END,
            anonymized_at = $2, updated_at = $2
      WHERE id = ANY($1::text[]) AND anonymized_at IS NULL`,
    [ids, now],
  );
  return result.rowCount ?? 0;
}

export interface Anonymized {
  appointments: number;
  sales: number;
  payments: number;
}

/**
 * The daily job's part: everything older than 12 months, in batches of 1,000, oldest first, until
 * nothing's left or the budget runs out (the next run carries on). Appointments count from their
 * end, and wait while a fee for them is pending; sales from when they were sold; payments from when
 * they were made.
 */
export async function anonymizeExpired(db: Queryable, now: Date, budget: Budget): Promise<Anonymized> {
  const cutoff = retentionCutoff(now);
  const size = budget.batchSize ?? RETENTION_BATCH;
  const done: Anonymized = { appointments: 0, sales: 0, payments: 0 };
  const steps: [keyof Anonymized, () => Promise<number>][] = [
    [
      'appointments',
      async () => {
        const { rows } = await db.query<{ id: string }>(
          `SELECT id FROM appointments
            WHERE anonymized_at IS NULL AND end_at < $1 AND no_show_fee_status <> 'pending'
            ORDER BY end_at LIMIT $2`,
          [cutoff, size],
        );
        await anonymizeAppointments(db, rows.map((r) => r.id), now);
        return rows.length;
      },
    ],
    [
      'sales',
      async () => {
        const { rows } = await db.query<{ id: string }>(
          'SELECT id FROM sales WHERE anonymized_at IS NULL AND sold_at < $1 ORDER BY sold_at LIMIT $2',
          [cutoff, size],
        );
        await anonymizeSales(db, rows.map((r) => r.id), now);
        return rows.length;
      },
    ],
    [
      'payments',
      async () => {
        const { rows } = await db.query<{ id: string }>(
          'SELECT id FROM payments WHERE anonymized_at IS NULL AND created_at < $1 ORDER BY created_at LIMIT $2',
          [cutoff, size],
        );
        await anonymizePayments(db, rows.map((r) => r.id), now);
        return rows.length;
      },
    ],
  ];
  for (const [key, step] of steps) {
    while (timeLeft(budget)) {
      const count = await step();
      done[key] += count;
      if (count < size) break;
    }
  }
  return done;
}

/** Receipt emails aren't kept at all (the address goes to Stripe only): any left from older code is cleared. */
export async function clearReceiptEmails(db: Queryable): Promise<number> {
  return (await db.query('UPDATE payments SET receipt_email = NULL WHERE receipt_email IS NOT NULL')).rowCount ?? 0;
}

// Which bookings still need their details, or their card.

type NeedRow = Pick<
  AppointmentRow,
  | 'id'
  | 'status'
  | 'cancelled_by'
  | 'start_at'
  | 'end_at'
  | 'created_at'
  | 'saved_card_id'
  | 'no_show_fee_cents'
  | 'late_cancel_window_minutes'
  | 'customer_cancelled_at'
  | 'no_show_fee_status'
>;

const NEED_COLUMNS =
  'id, status, cancelled_by, start_at, end_at, created_at, saved_card_id, no_show_fee_cents, late_cancel_window_minutes, customer_cancelled_at, no_show_fee_status';

/**
 * Whether a booking still needs its card on file: a fee for it is pending, or it can still be charged
 * one before the 7-day deadline (it's still booked, upcoming or not marked yet; it's a no-show; or the
 * client cancelled late). A fee already charged, or a booking that can't be charged any more, doesn't.
 */
export function bookingNeedsCard(row: NeedRow, now: Date): boolean {
  if (row.saved_card_id === null) return false;
  if (row.no_show_fee_status === 'pending') return true;
  if (row.no_show_fee_status === 'charged' || pastFeeDeadline(row.start_at, now)) return false;
  if (row.status === 'booked') return true;
  return feeCase(row).reason !== null;
}

/**
 * Why an appointment's details are still needed, or null when they can be removed now: it's upcoming
 * (the shop needs to know who's coming), a fee for it is pending, or its card can still be charged
 * a fee (the shop may need to tell the client).
 */
export function detailsStillNeeded(row: NeedRow, now: Date): 'upcoming' | 'fee' | null {
  if (row.status === 'booked' && row.start_at > now) return 'upcoming';
  return bookingNeedsCard(row, now) ? 'fee' : null;
}

/** Whether any booking still needs the card `cardId`. */
export async function cardNeeded(db: Queryable, cardId: string, now: Date): Promise<boolean> {
  const { rows } = await db.query<NeedRow>(`SELECT ${NEED_COLUMNS} FROM appointments WHERE saved_card_id = $1`, [cardId]);
  return rows.some((row) => bookingNeedsCard(row, now));
}

// Deleting a saved card.

const errorOf = (error: unknown) => (typeof error === 'object' && error !== null ? error : {}) as StripeErrorLike;
/** Stripe doesn't have it (any more). */
const missing = (error: unknown) => errorOf(error).code === 'resource_missing' || errorOf(error).statusCode === 404;

/**
 * Detaches the card and deletes its Stripe Customer (each saved card has its own), on the account it
 * was saved on. After that Stripe can't charge it. (The completed Checkout Session keeps the email
 * typed on Stripe's page: Stripe can't delete a Checkout Session, and the Privacy Policy says so.)
 *
 * - `deleted`: done, or Stripe had neither any more.
 * - `unreachable`: it's on an account this server can't use any more (saved with the shop's own key
 *   before Stripe was connected, or the other way round, or the shop took the platform's access
 *   away). It can't be charged from here either; it has to be deleted in that account's Dashboard.
 * - `failed`: Stripe is off on this server or didn't answer; try again later.
 */
export async function deleteAtStripe(
  deps: Pick<Deps, 'config' | 'db' | 'stripe' | 'log'>,
  card: Pick<SavedCardRow, 'id' | 'stripe_account_id' | 'stripe_customer_id' | 'stripe_payment_method_id'>,
): Promise<'deleted' | 'unreachable' | 'failed'> {
  const setup = stripeSetup(deps.config);
  if (setup === 'off') return 'failed';
  if ((card.stripe_account_id !== null) !== (setup === 'connect')) return 'unreachable';
  const shop = await shopStripe(deps, { account: card.stripe_account_id });
  if (card.stripe_payment_method_id) {
    try {
      await shop.stripe.paymentMethods.detach(card.stripe_payment_method_id, undefined, requestOptions(shop));
    } catch (error) {
      // Already detached or gone is fine: deleting the Customer below removes whatever is left.
      if (errorOf(error).type !== 'StripeInvalidRequestError') {
        if (accessRevoked(error)) return 'unreachable';
        stripeFailure(deps, error, 'detach card');
        return 'failed';
      }
    }
  }
  if (card.stripe_customer_id) {
    try {
      await shop.stripe.customers.del(card.stripe_customer_id, undefined, requestOptions(shop));
    } catch (error) {
      if (!missing(error)) {
        if (accessRevoked(error)) return 'unreachable';
        stripeFailure(deps, error, 'delete customer');
        return 'failed';
      }
    }
  }
  return 'deleted';
}

/** The card can't be used or charged any more: removed, without Stripe's ids. */
async function markRemoved(db: Queryable, cardId: string, now: Date): Promise<void> {
  await db.query(
    `UPDATE saved_cards
        SET removed_at = $2, checkout_session_id = NULL, stripe_customer_id = NULL, stripe_payment_method_id = NULL
      WHERE id = $1 AND removed_at IS NULL`,
    [cardId, now],
  );
}

/**
 * The card can't book again, and the daily job deletes it at Stripe once no booking needs it. For
 * DELETE /api/cards, the privacy tools, and a booking made without "Remember me" (booking.ts).
 */
export async function markRequested(db: Queryable, cardId: string, now: Date): Promise<void> {
  await db.query('UPDATE saved_cards SET delete_requested_at = COALESCE(delete_requested_at, $2) WHERE id = $1', [cardId, now]);
}

/**
 * Deletes a card at Stripe now, or marks it for the daily job when it can't be (a booking still needs
 * it, or Stripe didn't answer). Either way it can't book again. For DELETE /api/cards and the privacy tools.
 */
export async function removeCard(
  deps: Pick<Deps, 'config' | 'db' | 'stripe' | 'log'>,
  card: SavedCardRow,
  now: Date,
): Promise<'deleted' | 'scheduled'> {
  if (card.removed_at) return 'deleted';
  await markRequested(deps.db, card.id, now);
  if (await cardNeeded(deps.db, card.id, now)) return 'scheduled';
  const result = await deleteAtStripe(deps, card);
  if (result === 'failed') return 'scheduled';
  if (result === 'unreachable') logUnreachable(deps, card);
  await markRemoved(deps.db, card.id, now);
  return 'deleted';
}

function logUnreachable(deps: Pick<Deps, 'log'>, card: Pick<SavedCardRow, 'id' | 'stripe_account_id'>): void {
  deps.log.warn("A saved card is on a Stripe account this server can't use any more: removed here, delete it in that account's Dashboard", {
    cardId: card.id,
    stripeAccount: card.stripe_account_id,
  });
}

export interface CardPurge {
  /** Deleted at Stripe (or unreachable there, and removed here). */
  deleted: number;
  /** Due for deletion, but a booking still needs it. */
  stillNeeded: number;
  /** Stripe didn't answer (or is off): tried again tomorrow. */
  failed: number;
}

/**
 * The daily job's part: every card that has expired (after its expiry month, shop time), went 12
 * months without being used for a booking (counting from when it was saved), or that the client asked
 * to delete, is deleted at Stripe once no booking needs it; oldest first, until the budget runs out.
 */
export async function purgeSavedCards(deps: Pick<Deps, 'config' | 'db' | 'stripe' | 'log' | 'catalog'>, now: Date, budget: Budget): Promise<CardPurge> {
  const done: CardPurge = { deleted: 0, stillNeeded: 0, failed: 0 };
  const [year, month] = localDate(now, deps.catalog.timeZone).split('-').map(Number) as [number, number];
  // Where the next page starts (cards still needed are passed over, and found again tomorrow).
  const cursor: { createdAt: Date | null; id: string | null } = { createdAt: null, id: null };
  while (timeLeft(budget)) {
    const { rows }: { rows: SavedCardRow[] } = await deps.db.query<SavedCardRow>(
      `SELECT c.* FROM saved_cards c
        WHERE c.removed_at IS NULL
          AND ($4::timestamptz IS NULL OR (c.created_at, c.id) > ($4::timestamptz, $5::uuid))
          AND (c.delete_requested_at IS NOT NULL
               OR c.exp_year < $2 OR (c.exp_year = $2 AND c.exp_month < $3)
               OR GREATEST(c.created_at, (SELECT max(a.created_at) FROM appointments a WHERE a.saved_card_id = c.id)) < $1)
        ORDER BY c.created_at, c.id
        LIMIT 100`,
      [retentionCutoff(now), year, month, cursor.createdAt, cursor.id],
    );
    for (const card of rows) {
      if (!timeLeft(budget)) return done;
      cursor.createdAt = card.created_at;
      cursor.id = card.id;
      if (await cardNeeded(deps.db, card.id, now)) {
        done.stillNeeded += 1;
        continue;
      }
      const result = await deleteAtStripe(deps, card);
      if (result === 'failed') {
        done.failed += 1;
        continue;
      }
      if (result === 'unreachable') logUnreachable(deps, card);
      await markRemoved(deps.db, card.id, now);
      done.deleted += 1;
    }
    if (rows.length < 100) break;
  }
  return done;
}

export { anonymizeAppointments, anonymizePayments, anonymizeSales };
