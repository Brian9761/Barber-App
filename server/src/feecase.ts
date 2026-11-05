import type { AppointmentRow } from './serialize.js';

// Which fee a protected booking can be charged, in one place: a no-show, or a
// late cancellation (the client cancelled less than the agreed window before the
// start). Both use the fee agreed at booking, and the owner decides each time.
// The rules only read the booking's own terms (what the client agreed to), never
// today's settings. No imports at run time, so serialize.ts can use it too.

/** What a fee is for. */
export type FeeReason = 'no_show' | 'late_cancel';

/** The payments.kind of a fee charged to the card on file. */
export type FeeKind = 'no_show_fee' | 'late_cancel_fee';

export const FEE_KIND: Record<FeeReason, FeeKind> = { no_show: 'no_show_fee', late_cancel: 'late_cancel_fee' };

/** Whether `kind` (payments.kind, or a PaymentIntent's metadata.kind) is a fee charged to a card on file. */
export function isFeeKind(kind: string | null | undefined): kind is FeeKind {
  return kind === 'no_show_fee' || kind === 'late_cancel_fee';
}

/** The fee's reason for a fee kind. */
export function reasonOfKind(kind: FeeKind): FeeReason {
  return kind === 'late_cancel_fee' ? 'late_cancel' : 'no_show';
}

export const MIN_LATE_CANCEL_WINDOW_MINUTES = 30;
export const MAX_LATE_CANCEL_WINDOW_MINUTES = 48 * 60;

/** "$20", "$17.50": like the Kit's `Price.currencyString`. */
export function money(cents: number): string {
  const dollars = Math.floor(cents / 100);
  const rest = cents % 100;
  return rest === 0 ? `$${dollars}` : `$${dollars}.${String(rest).padStart(2, '0')}`;
}

/** "30 minutes", "1 hour", "90 minutes", "2 hours", "48 hours": as the policy and warning say it. */
export function windowLabel(minutes: number): string {
  if (minutes % 60 !== 0) return `${minutes} minutes`;
  const hours = minutes / 60;
  return hours === 1 ? '1 hour' : `${hours} hours`;
}

/**
 * Cancelling within this many minutes of booking is always free: the grace period. It matters for a
 * time booked when its free-cancellation cutoff had already passed (bookings open 30 minutes ahead,
 * the window can be up to 48 hours): the time was free a minute earlier, so the shop lost nothing.
 */
export const LATE_CANCEL_GRACE_MINUTES = 15;

/** A fee can be charged until 7 days after the appointment's start, never later (the agreement ends then). */
export const FEE_DEADLINE_DAYS = 7;
const FEE_DEADLINE_MS = FEE_DEADLINE_DAYS * 24 * 60 * 60 * 1000;

/** The owner's answer once the 7 days are over (the Kit and the website say the same). */
export const FEE_DEADLINE_MESSAGE = `It's more than ${FEE_DEADLINE_DAYS} days after the appointment, so the fee can't be charged.`;
/** A no-show fee before the appointment's end: a client who comes before the end isn't a no-show. */
export const NOT_ENDED_MESSAGE = "The appointment hasn't ended yet, so it can't be a no-show.";

/** The last moment a fee for an appointment starting at `start` can be charged: 7 days (of 24 hours) later. */
export function feeDeadline(start: Date): Date {
  return new Date(start.getTime() + FEE_DEADLINE_MS);
}

/** Whether it's too late to charge a fee for an appointment that started at `start` (exactly 7 days later still isn't). */
export function pastFeeDeadline(start: Date, now: Date): boolean {
  return now.getTime() > start.getTime() + FEE_DEADLINE_MS;
}

type FeeTerms = Pick<
  AppointmentRow,
  | 'status'
  | 'cancelled_by'
  | 'start_at'
  | 'created_at'
  | 'saved_card_id'
  | 'no_show_fee_cents'
  | 'late_cancel_window_minutes'
  | 'customer_cancelled_at'
>;

/**
 * Whether the client cancelled in the app less than the agreed window before the
 * start (cancelling exactly that long before is still free), and more than 15
 * minutes after booking (the grace period: exactly 15 minutes after is still free).
 * Only for a booking whose agreed policy had late cancellations in it.
 */
export function cancelledLate(row: FeeTerms): boolean {
  if (row.saved_card_id === null || row.no_show_fee_cents === null) return false;
  return cancelledInsideWindow(row) && !withinGrace(row);
}

/** Whether the client's (first) cancel time was less than the agreed window before the start, the grace period aside. */
function cancelledInsideWindow(row: Pick<FeeTerms, 'start_at' | 'late_cancel_window_minutes' | 'customer_cancelled_at'>): boolean {
  if (row.late_cancel_window_minutes === null || row.customer_cancelled_at === null) return false;
  return row.start_at.getTime() - row.customer_cancelled_at.getTime() < row.late_cancel_window_minutes * 60_000;
}

/** Whether the client cancelled (first) at most 15 minutes after booking. */
function withinGrace(row: Pick<FeeTerms, 'created_at' | 'customer_cancelled_at'>): boolean {
  return row.customer_cancelled_at !== null && row.customer_cancelled_at.getTime() - row.created_at.getTime() <= LATE_CANCEL_GRACE_MINUTES * 60_000;
}

/**
 * Whether the client cancelling at `now` would be a late cancellation. The time that
 * counts is the first one the client cancelled (or asked to) before the start, if
 * there was one: a booking cancelled early and reopened by the shop stays free.
 */
export function cancellingIsLate(row: FeeTerms, now: Date): boolean {
  return cancelledLate({ ...row, customer_cancelled_at: row.customer_cancelled_at ?? now });
}

/** Whether the agreed fee is the booked service's whole price (it is at 100%). */
export function isFullPrice(row: Pick<AppointmentRow, 'no_show_fee_cents' | 'price_cents'>): boolean {
  return row.no_show_fee_cents !== null && row.no_show_fee_cents === row.price_cents;
}

/**
 * What the client is told before cancelling inside the agreed window, in the customer
 * app's confirmation and in the server's 409 `late_cancel_fee`: "Cancelling now, less
 * than 1 hour before your appointment, may be charged $35, the full service price."
 */
export function lateCancelWarning(windowMinutes: number, feeCents: number, fullPrice: boolean): string {
  const amount = fullPrice ? `${money(feeCents)}, the full service price` : money(feeCents);
  return `Cancelling now, less than ${windowLabel(windowMinutes)} before your appointment, may be charged ${amount}.`;
}

/**
 * The owner's answer when a try whose answer was lost turns out never to have reached Stripe and
 * the booking can't be charged any more: "Nothing was charged. Mark the appointment as a no-show first."
 */
export function nothingCharged(refusal: string): string {
  return `Nothing was charged. ${refusal}`;
}

/** The case a fee applies to now, or why there's none (in plain words for the owner). */
export type FeeCase = { reason: FeeReason; refusal: null } | { reason: null; refusal: string };

const refuse = (refusal: string): FeeCase => ({ reason: null, refusal });

export const MARK_NO_SHOW_MESSAGE = 'Mark the appointment as a no-show first.';
export const COMPLETED_MESSAGE = "The appointment is marked completed, so there's no fee to charge.";

/**
 * Which fee this booking (with a card on file) can be charged, ignoring the clock:
 * - a late cancellation: it ended cancelled by the client, who cancelled inside the agreed
 *   window, more than 15 minutes after booking;
 * - a no-show: it's marked a no-show and the client never cancelled (nor asked to).
 * Cancelling earlier than the window (or within 15 minutes of booking) is free, so is any
 * booking the shop cancelled, and a booking the client cancelled that the shop reopened is
 * never charged. The clock decides the rest (`feeCaseAt`): a no-show also needs its end to
 * have passed, and nothing can be charged more than 7 days after the start.
 */
export function feeCase(row: FeeTerms): FeeCase {
  if (row.status === 'cancelled') {
    if (row.cancelled_by !== 'customer') return refuse("The shop cancelled this booking, so there's no fee.");
    if (cancelledLate(row)) return { reason: 'late_cancel', refusal: null };
    if (row.late_cancel_window_minutes !== null && row.customer_cancelled_at !== null) {
      if (cancelledInsideWindow(row)) {
        return refuse(`The client cancelled within ${LATE_CANCEL_GRACE_MINUTES} minutes of booking, so there's no fee.`);
      }
      return refuse(`The client cancelled at least ${windowLabel(row.late_cancel_window_minutes)} before, so there's no fee.`);
    }
    return refuse("The client cancelled this booking in the app, so there's no fee.");
  }
  if (row.customer_cancelled_at !== null) return refuse("The client cancelled this booking in the app, so there's no fee.");
  // The client came: a completed booking with a card on file can't become a no-show (appointments.ts).
  if (row.status === 'completed') return refuse(COMPLETED_MESSAGE);
  if (row.status !== 'no_show') return refuse(MARK_NO_SHOW_MESSAGE);
  return { reason: 'no_show', refusal: null };
}

/**
 * Which fee this booking (with a card on file) can be charged at `now`, or why not: `feeCase`,
 * then the clock. Nothing more than 7 days after the start (a booking still marked booked then
 * hears that too, rather than to mark a no-show first), and a no-show only once the appointment
 * has ended (a client who comes before the end isn't a no-show).
 */
export function feeCaseAt(row: FeeTerms & Pick<AppointmentRow, 'end_at'>, now: Date): FeeCase {
  const found = feeCase(row);
  const tooLate = pastFeeDeadline(row.start_at, now);
  if (found.reason === null) return found.refusal === MARK_NO_SHOW_MESSAGE && tooLate ? refuse(FEE_DEADLINE_MESSAGE) : found;
  if (tooLate) return refuse(FEE_DEADLINE_MESSAGE);
  if (found.reason === 'no_show' && row.end_at.getTime() > now.getTime()) return refuse(NOT_ENDED_MESSAGE);
  return found;
}
