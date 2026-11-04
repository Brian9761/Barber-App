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

type FeeTerms = Pick<
  AppointmentRow,
  'status' | 'cancelled_by' | 'start_at' | 'saved_card_id' | 'no_show_fee_cents' | 'late_cancel_window_minutes' | 'customer_cancelled_at'
>;

/**
 * Whether the client cancelled in the app less than the agreed window before the
 * start (cancelling exactly that long before is still free). Only for a booking
 * whose agreed policy had late cancellations in it.
 */
export function cancelledLate(row: FeeTerms): boolean {
  if (row.saved_card_id === null || row.no_show_fee_cents === null) return false;
  if (row.late_cancel_window_minutes === null || row.customer_cancelled_at === null) return false;
  return row.start_at.getTime() - row.customer_cancelled_at.getTime() < row.late_cancel_window_minutes * 60_000;
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

/**
 * Which fee this booking (with a card on file) can be charged, ignoring the clock:
 * - a late cancellation: it ended cancelled by the client, who cancelled inside the agreed window;
 * - a no-show: it's marked a no-show and the client never cancelled (nor asked to).
 * Cancelling earlier than the window is free, so is any booking the shop cancelled, and
 * a booking the client cancelled that the shop reopened is never charged. A no-show
 * also needs its start to have passed; the caller checks that against its clock.
 */
export function feeCase(row: FeeTerms): FeeCase {
  if (row.status === 'cancelled') {
    if (row.cancelled_by !== 'customer') return refuse("The shop cancelled this booking, so there's no fee.");
    if (cancelledLate(row)) return { reason: 'late_cancel', refusal: null };
    if (row.late_cancel_window_minutes !== null && row.customer_cancelled_at !== null) {
      return refuse(`The client cancelled at least ${windowLabel(row.late_cancel_window_minutes)} before, so there's no fee.`);
    }
    return refuse("The client cancelled this booking in the app, so there's no fee.");
  }
  if (row.customer_cancelled_at !== null) return refuse("The client cancelled this booking in the app, so there's no fee.");
  if (row.status !== 'no_show') return refuse('Mark the appointment as a no-show first.');
  return { reason: 'no_show', refusal: null };
}
