import { DateTime } from 'luxon';
import type Stripe from 'stripe';
import { CHECKOUT_MINUTES, type CardCheckoutRow, type SavedCardRow } from './cards.js';
import type { Queryable } from './db.js';
import type { Deps } from './deps.js';
import { feeCase, feeDeadline, pastFeeDeadline } from './feecase.js';
import type { AppointmentRow } from './serialize.js';
import { accessRevoked, keyLivemode, requestOptions, shopStripe, stripeFailure, stripeSetup, type StripeErrorLike } from './stripeaccount.js';
import { localDate } from './time.js';

// How long the shop keeps clients' details, as its Privacy Policy says (docs/legal/privacy.md,
// "How long we keep it"; docs/legal/research.md §17; docs/legal/data-inventory.md G1 and G2):
//
// - An appointment's name, number, email and note: 12 months after the appointment, then they're
//   removed. The appointment stays, without them, so the analytics (which never read them) don't
//   change. (A fee try still waiting for Stripe's answer only holds them for a couple of weeks:
//   `PENDING_FEE_HOLD_DAYS`.)
// - The client's name on a sale (and why it was voided), and a card payment's description, receipt
//   email and the client's name on its checkout ticket: 12 months.
// - A saved card: deleted at Stripe (detached, and its Customer deleted) once it has expired, gone
//   12 months without being used for a booking, or the client asked (Remove card, Forget my details,
//   or a booking made without Remember me), as soon as no booking still needs it.
// - A card page whose card was never saved here (the page, the tab or the app closed right after
//   Stripe saved it): its card (if one was added) and its Customer deleted at Stripe within 2 days.
// - Either one on a Stripe account this server can't use any more: removed here, and listed for
//   the shop (GET /api/owner/stripe, `cardsToDelete`) to delete in that account's Dashboard.
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

/**
 * How long after the 7-day fee deadline a fee try still marked pending keeps the card and the
 * client's details. Stripe answers an off-session card charge at once, so a try still pending then
 * is one whose answer was lost and that nobody checked again (Check again still settles it any
 * time). After that it holds nothing: the Privacy Policy keeps them only while a fee "is still
 * being processed".
 */
export const PENDING_FEE_HOLD_DAYS = 7;
const DAY_MS = 24 * 60 * 60 * 1000;

/** Whether a fee try for an appointment starting at `start` that's still pending still holds its card and details at `now`. */
export function pendingFeeHolds(start: Date, now: Date): boolean {
  return now.getTime() <= feeDeadline(start).getTime() + PENDING_FEE_HOLD_DAYS * DAY_MS;
}

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
        // A fee try still pending holds them only until a couple of weeks after the start
        // (pendingFeeHolds), long before the 12 months are up.
        const { rows } = await db.query<{ id: string }>(
          `SELECT id FROM appointments
            WHERE anonymized_at IS NULL AND end_at < $1 AND (no_show_fee_status <> 'pending' OR start_at < $3)
            ORDER BY end_at LIMIT $2`,
          [cutoff, size, new Date(now.getTime() - (7 + PENDING_FEE_HOLD_DAYS) * DAY_MS)],
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
 * Whether a booking still needs its card on file: a fee try for it is pending (for a couple of
 * weeks at most: `pendingFeeHolds`), or it can still be charged one before the 7-day deadline (it's
 * still booked, upcoming or not marked yet; it's a no-show; or the client cancelled late). A fee
 * already charged, one the bank turned down (the card isn't charged again), or a booking that can't
 * be charged any more, doesn't.
 */
export function bookingNeedsCard(row: NeedRow, now: Date): boolean {
  if (row.saved_card_id === null) return false;
  if (row.no_show_fee_status === 'pending') return pendingFeeHolds(row.start_at, now);
  if (row.no_show_fee_status === 'charged' || row.no_show_fee_status === 'declined' || row.no_show_fee_status === 'needs_action') return false;
  if (pastFeeDeadline(row.start_at, now)) return false;
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

/** What deleting a card at Stripe needs: its ids, and the account and mode it was saved on. */
export interface StripeCardIds {
  /** The connected account it's on; null when saved with the shop's own key. */
  stripe_account_id: string | null;
  /** Saved in live mode (true) or test mode (false). */
  livemode: boolean;
  stripe_customer_id: string | null;
  stripe_payment_method_id: string | null;
}

/**
 * Detaches the card and deletes its Stripe Customer (each saved card has its own), on the account it
 * was saved on. After that Stripe can't charge it. (The completed Checkout Session keeps the email
 * typed on Stripe's page: Stripe can't delete a Checkout Session, and the Privacy Policy says so.)
 *
 * - `deleted`: done, or Stripe had neither any more.
 * - `unreachable`: it's on an account this server can't use any more (saved with the shop's own key
 *   before Stripe was connected, or the other way round, or with a key of the other mode, test or
 *   live, or the shop took the platform's access away). It can't be charged from here either; it
 *   has to be deleted in that account's Dashboard. (Asked with a key of the other mode, Stripe would
 *   answer "no such customer", which isn't "deleted".)
 * - `failed`: Stripe is off on this server or didn't answer; try again later.
 */
export async function deleteAtStripe(deps: Pick<Deps, 'config' | 'db' | 'stripe' | 'log'>, card: StripeCardIds): Promise<'deleted' | 'unreachable' | 'failed'> {
  const setup = stripeSetup(deps.config);
  if (setup === 'off') return 'failed';
  if ((card.stripe_account_id !== null) !== (setup === 'connect')) return 'unreachable';
  const live = keyLivemode(deps.config);
  if (live !== null && card.livemode !== live) return 'unreachable';
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
 * The card is on a Stripe account this server can't use any more: it can't be used or charged any
 * more (removed), but it keeps Stripe's ids, so the shop can find it and delete it in that account's
 * Dashboard (`cardsToDelete`), until the shop says it did (`deletedInStripe`).
 */
async function markUnreachable(db: Queryable, cardId: string, now: Date): Promise<void> {
  await db.query('UPDATE saved_cards SET removed_at = $2, stripe_unreachable_at = $2 WHERE id = $1 AND removed_at IS NULL', [cardId, now]);
}

/**
 * The card can't book again, and the daily job deletes it at Stripe once no booking needs it. For
 * DELETE /api/cards, the privacy tools, and a booking made without "Remember me" (booking.ts).
 */
export async function markRequested(db: Queryable, cardId: string, now: Date): Promise<void> {
  await db.query('UPDATE saved_cards SET delete_requested_at = COALESCE(delete_requested_at, $2) WHERE id = $1', [cardId, now]);
}

/** After `deleteAtStripe`: removed here, and kept for the shop when Stripe can't be reached from here. */
async function settleCard(deps: Pick<Deps, 'db' | 'log'>, card: SavedCardRow, result: 'deleted' | 'unreachable', now: Date): Promise<void> {
  if (result === 'deleted') return markRemoved(deps.db, card.id, now);
  logUnreachable(deps, card);
  return markUnreachable(deps.db, card.id, now);
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
  await settleCard(deps, card, result, now);
  return 'deleted';
}

function logUnreachable(deps: Pick<Deps, 'log'>, card: Pick<SavedCardRow, 'id' | 'stripe_account_id' | 'stripe_customer_id' | 'livemode'>): void {
  deps.log.warn("A saved card is on a Stripe account this server can't use any more: removed here, delete it in that account's Dashboard", {
    cardId: card.id,
    customerId: card.stripe_customer_id,
    stripeAccount: card.stripe_account_id,
    livemode: card.livemode,
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
      await settleCard(deps, card, result, now);
      done.deleted += 1;
    }
    if (rows.length < 100) break;
  }
  return done;
}

// Card pages whose card was never saved here (migrations/011, cards.ts).

/**
 * How long after a card page closes (CHECKOUT_MINUTES after it was made) its card may still be
 * saved: the apps and the website try again when an answer is lost, and the website's page can be
 * reloaded. A little under a day, so that the daily job, which runs once a day and up to an hour
 * late, still deletes an unfinished page at Stripe within 2 days of it being made, as the Privacy
 * Policy says.
 */
export const UNFINISHED_CHECKOUT_MARGIN_HOURS = 21;

/** Card pages made before this moment, and still not saved, are deleted at Stripe. */
export function unfinishedCheckoutCutoff(now: Date): Date {
  return new Date(now.getTime() - CHECKOUT_MINUTES * 60_000 - UNFINISHED_CHECKOUT_MARGIN_HOURS * 60 * 60_000);
}

/** The id of an expanded Stripe object, or the id itself. */
function idOf(value: string | { id: string } | null | undefined): string | null {
  if (!value) return null;
  return typeof value === 'string' ? value : value.id;
}

/**
 * Deletes an unfinished card page's card, if Stripe saved one, and its Customer, on the account it
 * was made on: the page is read first, for the card its SetupIntent saved. Then as `deleteAtStripe`.
 */
async function deletePageAtStripe(
  deps: Pick<Deps, 'config' | 'db' | 'stripe' | 'log'>,
  page: CardCheckoutRow,
): Promise<'deleted' | 'unreachable' | 'failed'> {
  const setup = stripeSetup(deps.config);
  if (setup === 'off') return 'failed';
  const live = keyLivemode(deps.config);
  const reachable = (page.stripe_account_id !== null) === (setup === 'connect') && (live === null || page.livemode === live);
  if (!reachable) return 'unreachable';
  const shop = await shopStripe(deps, { account: page.stripe_account_id });
  let paymentMethod: string | null = null;
  try {
    const session: Stripe.Checkout.Session = await shop.stripe.checkout.sessions.retrieve(page.checkout_session_id, { expand: ['setup_intent'] }, requestOptions(shop));
    const setupIntent = typeof session.setup_intent === 'object' && session.setup_intent !== null ? session.setup_intent : null;
    paymentMethod = idOf(setupIntent?.payment_method);
  } catch (error) {
    // A page Stripe doesn't have (any more) has no card to detach; its Customer is still deleted.
    if (!missing(error)) {
      if (accessRevoked(error)) return 'unreachable';
      stripeFailure(deps, error, 'retrieve card checkout');
      return 'failed';
    }
  }
  return deleteAtStripe(deps, {
    stripe_account_id: page.stripe_account_id,
    livemode: page.livemode,
    stripe_customer_id: page.stripe_customer_id,
    stripe_payment_method_id: paymentMethod,
  });
}

export interface CheckoutPurge {
  /** Deleted at Stripe: the card, if one was added, and the Customer. */
  deleted: number;
  /** On a Stripe account this server can't use any more: listed for the shop to delete there. */
  unreachable: number;
  /** Stripe didn't answer (or is off): tried again tomorrow. Its card can't be saved meanwhile. */
  failed: number;
}

/**
 * The daily job's part, after the saved cards: every card page made more than its 60 minutes and
 * `UNFINISHED_CHECKOUT_MARGIN_HOURS` ago whose card was never saved here is taken up (from then on
 * its card can't be saved: POST /api/cards answers that the page has expired) and deleted at Stripe,
 * its card (if Stripe saved one) and its Customer; oldest first, until the budget runs out. One
 * Stripe didn't answer is tried again the next day; one on an account this server can't use any
 * more waits for the shop (`cardsToDelete`). A page deleted at Stripe stays marked, so nothing is
 * asked twice.
 */
export async function purgeUnfinishedCheckouts(deps: Pick<Deps, 'config' | 'db' | 'stripe' | 'log'>, now: Date, budget: Budget): Promise<CheckoutPurge> {
  const done: CheckoutPurge = { deleted: 0, unreachable: 0, failed: 0 };
  // A page whose card was saved by code from before migrations/011 (a rollback, say) was never
  // closed: it's closed now, and saved_cards deletes its card.
  await deps.db.query(
    `UPDATE card_checkouts c SET closed_at = s.created_at, stripe_customer_id = NULL
       FROM saved_cards s
      WHERE s.checkout_session_id = c.checkout_session_id AND c.closed_at IS NULL AND c.abandoned_at IS NULL`,
  );
  const cutoff = unfinishedCheckoutCutoff(now);
  // Where the next page of rows starts (pages Stripe didn't answer for are passed over, and found again tomorrow).
  const cursor: { createdAt: Date | null; id: string | null } = { createdAt: null, id: null };
  while (timeLeft(budget)) {
    const { rows } = await deps.db.query<{ checkout_session_id: string; created_at: Date }>(
      `SELECT checkout_session_id, created_at FROM card_checkouts
        WHERE closed_at IS NULL AND deleted_at IS NULL AND stripe_unreachable_at IS NULL
          AND (abandoned_at IS NOT NULL OR created_at < $1)
          AND ($2::timestamptz IS NULL OR (created_at, checkout_session_id) > ($2::timestamptz, $3::text))
        ORDER BY created_at, checkout_session_id
        LIMIT 100`,
      [cutoff, cursor.createdAt, cursor.id],
    );
    for (const { checkout_session_id: id, created_at: createdAt } of rows) {
      if (!timeLeft(budget)) return done;
      cursor.createdAt = createdAt;
      cursor.id = id;
      // Taken up under the row's lock, which POST /api/cards takes too: a card being saved right now
      // is left alone (and closed by then), and one taken up here can't be saved any more.
      const page = await deps.db.transaction(async (tx) => {
        const { rows: locked } = await tx.query<CardCheckoutRow>(
          `SELECT * FROM card_checkouts c
            WHERE c.checkout_session_id = $1 AND c.closed_at IS NULL AND c.deleted_at IS NULL AND c.stripe_unreachable_at IS NULL
              AND NOT EXISTS (SELECT 1 FROM saved_cards s WHERE s.checkout_session_id = c.checkout_session_id)
            FOR UPDATE SKIP LOCKED`,
          [id],
        );
        const found = locked[0];
        if (found && !found.abandoned_at) await tx.query('UPDATE card_checkouts SET abandoned_at = $2 WHERE checkout_session_id = $1', [id, now]);
        return found ?? null;
      });
      if (!page) continue;
      const result = await deletePageAtStripe(deps, page);
      if (result === 'failed') {
        done.failed += 1;
        continue;
      }
      if (result === 'unreachable') {
        deps.log.warn("A card page that wasn't finished is on a Stripe account this server can't use any more: delete its customer in that account's Dashboard", {
          customerId: page.stripe_customer_id,
          stripeAccount: page.stripe_account_id,
          livemode: page.livemode,
        });
        await deps.db.query('UPDATE card_checkouts SET stripe_unreachable_at = $2 WHERE checkout_session_id = $1', [id, now]);
        done.unreachable += 1;
        continue;
      }
      await deps.db.query('UPDATE card_checkouts SET deleted_at = $2, stripe_customer_id = NULL WHERE checkout_session_id = $1', [id, now]);
      done.deleted += 1;
    }
    if (rows.length < 100) break;
  }
  return done;
}

// What the shop deletes in an old Stripe account itself (Settings → Stripe).

/** A saved card, or an unfinished card page, on a Stripe account this server can't use any more. */
export interface CardToDeleteJSON {
  /** The saved card's id, or the card page's Checkout Session id. */
  id: string;
  kind: 'savedCard' | 'cardPage';
  /** The connected account it's on; null when it was saved with the shop's own Stripe key. */
  stripeAccountId: string | null;
  /** Live (true) or test mode (false), in which to look for it. */
  livemode: boolean;
  /** What to search for in that account's Customers. */
  customerId: string;
  /** The saved card's type, last 4 and expiry; null for a card page (its card, if any, was never read). */
  card: { brand: string; last4: string; expMonth: number; expYear: number } | null;
}

/** At most this many are listed at once (the oldest first); the next ones show once those are done. */
export const CARDS_TO_DELETE_LIMIT = 100;

/** What the shop has to delete in an old Stripe account, oldest first. */
export async function cardsToDelete(db: Queryable): Promise<CardToDeleteJSON[]> {
  const { rows } = await db.query<{
    id: string;
    kind: 'savedCard' | 'cardPage';
    stripe_account_id: string | null;
    livemode: boolean;
    stripe_customer_id: string;
    brand: string | null;
    last4: string | null;
    exp_month: number | null;
    exp_year: number | null;
  }>(
    `SELECT id::text AS id, 'savedCard' AS kind, stripe_account_id, livemode, stripe_customer_id, brand, last4, exp_month, exp_year, stripe_unreachable_at
       FROM saved_cards WHERE stripe_unreachable_at IS NOT NULL
     UNION ALL
     SELECT checkout_session_id, 'cardPage', stripe_account_id, livemode, stripe_customer_id, NULL, NULL, NULL, NULL, stripe_unreachable_at
       FROM card_checkouts WHERE stripe_unreachable_at IS NOT NULL AND deleted_at IS NULL
     ORDER BY stripe_unreachable_at, id
     LIMIT ${CARDS_TO_DELETE_LIMIT}`,
  );
  return rows.map((row) => ({
    id: row.id,
    kind: row.kind,
    stripeAccountId: row.stripe_account_id,
    livemode: row.livemode,
    customerId: row.stripe_customer_id,
    card:
      row.brand !== null && row.last4 !== null && row.exp_month !== null && row.exp_year !== null
        ? { brand: row.brand, last4: row.last4, expMonth: row.exp_month, expYear: row.exp_year }
        : null,
  }));
}

/**
 * The shop deleted it in that Stripe account's Dashboard ("Deleted in Stripe"): its Stripe ids are
 * forgotten, and it's off the list. `found` is false when no saved card or card page has that id;
 * one already off the list is left as it is.
 */
export async function deletedInStripe(db: Queryable, id: string, now: Date): Promise<{ found: boolean }> {
  if (id.startsWith('cs_')) {
    const { rows } = await db.query<{ found: boolean }>(
      `WITH done AS (
         UPDATE card_checkouts SET deleted_at = $2, stripe_customer_id = NULL, stripe_unreachable_at = NULL
          WHERE checkout_session_id = $1 AND stripe_unreachable_at IS NOT NULL AND deleted_at IS NULL
          RETURNING 1)
       SELECT EXISTS (SELECT 1 FROM done) OR EXISTS (SELECT 1 FROM card_checkouts WHERE checkout_session_id = $1) AS found`,
      [id, now],
    );
    return { found: rows[0]?.found === true };
  }
  const { rows } = await db.query<{ found: boolean }>(
    `WITH done AS (
       UPDATE saved_cards SET checkout_session_id = NULL, stripe_customer_id = NULL, stripe_payment_method_id = NULL, stripe_unreachable_at = NULL
        WHERE id = $1::uuid AND stripe_unreachable_at IS NOT NULL
        RETURNING 1)
     SELECT EXISTS (SELECT 1 FROM done) OR EXISTS (SELECT 1 FROM saved_cards WHERE id = $1::uuid) AS found`,
    [id],
  );
  return { found: rows[0]?.found === true };
}

export { anonymizeAppointments, anonymizePayments, anonymizeSales };
