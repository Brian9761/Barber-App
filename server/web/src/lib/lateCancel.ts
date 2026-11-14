// Late cancellations, worded and decided like the server (server/src/feecase.ts and
// noshow.ts) and the app (IzzyClipzKit's NoShowRule), and checked against the server's
// own examples (server/test/fixtures/fee-cases.json and no-show-rule.json).

import type { Appointment, NoShowPolicy } from '../api/types';
import { money, windowLabel } from './format';

/**
 * Cancelling within this many minutes of booking is always free: the grace period. It matters
 * for a time booked when its free-cancellation cutoff had already passed (bookings open 30
 * minutes ahead, and the window can be up to 48 hours).
 */
export const LATE_CANCEL_GRACE_MINUTES = 15;

/**
 * Whether cancelling at `cancelledAt` is less than the agreed window before the start (exactly
 * that long before is still free) and, given `bookedAt` (when it was booked), more than 15
 * minutes after booking (exactly 15 minutes after is still free). Without `bookedAt`, the grace
 * period isn't counted: that's for a time that isn't booked yet.
 */
export function cancelledLate(start: Date, cancelledAt: Date | null, windowMinutes: number | null, bookedAt?: Date | null): boolean {
  if (cancelledAt === null || windowMinutes === null) return false;
  if (bookedAt && !Number.isNaN(bookedAt.getTime()) && cancelledAt.getTime() - bookedAt.getTime() <= LATE_CANCEL_GRACE_MINUTES * 60_000) return false;
  return start.getTime() - cancelledAt.getTime() < windowMinutes * 60_000;
}

/** What a client may cancel: still booked and not started. */
export function isCancellable(appointment: Pick<Appointment, 'status' | 'start'>, now: Date): boolean {
  return appointment.status === 'booked' && new Date(appointment.start).getTime() > now.getTime();
}

/**
 * The instant rounded down to the whole second. The server takes a client's cancel time this
 * way (and writes it so), so a cancel 400 ms inside the window is exactly the window before:
 * free for the server, and so here too.
 */
export function wholeSecond(date: Date): Date {
  return new Date(Math.floor(date.getTime() / 1000) * 1000);
}

/**
 * "Cancelling now, less than 1 hour before your appointment, may be charged $35, the
 * full service price." The server's own words (its 409 `late_cancel_fee` says the same).
 */
export function lateCancelWarningText(windowMinutes: number, feeCents: number, fullPrice: boolean): string {
  const amount = fullPrice ? `${money(feeCents)}, the full service price` : money(feeCents);
  return `Cancelling now, less than ${windowLabel(windowMinutes)} before your appointment, may be charged ${amount}.`;
}

/** What these rules read: never the client's own details. */
type Booked = Omit<Appointment, 'customer' | 'note'>;

/** Whether the agreed fee is the whole price: the server says so; an older server is judged by the label. */
function isFullPrice(appointment: Booked): boolean {
  const fee = appointment.noShowFee;
  if (!fee) return false;
  return fee.fullPrice ?? money(fee.amountCents) === appointment.priceLabel;
}

/**
 * The warning before cancelling, when cancelling now would be a late cancellation under the
 * policy the client agreed to; null when it's free. Like the server, the first time the client
 * cancelled (or asked to) counts, if there was one, and cancelling within 15 minutes of booking
 * is free (so there's no warning then).
 */
export function lateCancelWarning(appointment: Booked, now: Date): string | null {
  const fee = appointment.noShowFee;
  if (!isCancellable(appointment, now) || !appointment.card || !fee || fee.lateCancelWindowMinutes === null) return null;
  const firstAsked = fee.customerCancelledAt ? new Date(fee.customerCancelledAt) : wholeSecond(now);
  if (!cancelledLate(new Date(appointment.start), firstAsked, fee.lateCancelWindowMinutes, new Date(appointment.createdAt))) return null;
  return lateCancelWarningText(fee.lateCancelWindowMinutes, fee.amountCents, isFullPrice(appointment));
}

/** "$20", or "$17.50–$22.50" for any barber when their fees differ. */
export function feeLabel(policy: NoShowPolicy): string | null {
  if (!policy.required || policy.minFeeCents === null || policy.maxFeeCents === null) return null;
  return policy.minFeeCents === policy.maxFeeCents
    ? money(policy.minFeeCents)
    : `${money(policy.minFeeCents)}–${money(policy.maxFeeCents)}`;
}

/**
 * "This time is less than 1 hour away, so cancelling it more than 15 minutes after booking may
 * be charged $35." The server words it (`lateCancelNotice` in server/src/noshow.ts, written to
 * no-show-rule.json), and the app says the same.
 */
export function lateCancelNoticeText(windowMinutes: number, fee: string): string {
  return `This time is less than ${windowLabel(windowMinutes)} away, so cancelling it more than ${LATE_CANCEL_GRACE_MINUTES} minutes after booking may be charged ${fee}.`;
}

/**
 * When cancelling a time starting at `start` stops being free under `policy` (ms): the window
 * before it. Null when it never does (no card needed, or late cancellations off).
 */
export function cutoffOf(policy: NoShowPolicy, start: string): number | null {
  if (!policy.required || policy.lateCancelWindowMinutes === null) return null;
  const at = new Date(start).getTime() - policy.lateCancelWindowMinutes * 60_000;
  return Number.isFinite(at) ? at : null;
}

/**
 * For a picked time that starts less than the window from now (bookings open 30 minutes ahead,
 * the window is often an hour): the policy's "Cancelling in the app more than 1 hour before is
 * free" can't apply to it, and once it's booked, cancelling it is free only for 15 minutes.
 * Null otherwise.
 */
export function lateCancelNotice(policy: NoShowPolicy, start: Date, now: Date): string | null {
  const fee = feeLabel(policy);
  if (!fee || policy.lateCancelWindowMinutes === null) return null;
  if (!cancelledLate(start, now, policy.lateCancelWindowMinutes)) return null;
  return lateCancelNoticeText(policy.lateCancelWindowMinutes, fee);
}
