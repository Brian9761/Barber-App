// Late cancellations, worded and decided like the server (server/src/feecase.ts)
// and the app (IzzyClipzKit's NoShowRule), and checked against the server's own
// examples (server/test/fixtures/fee-cases.json).

import type { Appointment, NoShowPolicy } from '../api/types';
import { money, windowLabel } from './format';

/**
 * Whether cancelling at `cancelledAt` is less than the agreed window before the
 * start (exactly that long before is still free).
 */
export function cancelledLate(start: Date, cancelledAt: Date | null, windowMinutes: number | null): boolean {
  if (cancelledAt === null || windowMinutes === null) return false;
  return start.getTime() - cancelledAt.getTime() < windowMinutes * 60_000;
}

/** What a client may cancel: still booked and not started. */
export function isCancellable(appointment: Pick<Appointment, 'status' | 'start'>, now: Date): boolean {
  return appointment.status === 'booked' && new Date(appointment.start).getTime() > now.getTime();
}

/**
 * "Cancelling now, less than 1 hour before your appointment, may be charged $35, the
 * full service price." The server's own words (its 409 `late_cancel_fee` says the same).
 */
export function lateCancelWarningText(windowMinutes: number, feeCents: number, fullPrice: boolean): string {
  const amount = fullPrice ? `${money(feeCents)}, the full service price` : money(feeCents);
  return `Cancelling now, less than ${windowLabel(windowMinutes)} before your appointment, may be charged ${amount}.`;
}

/** Whether the agreed fee is the whole price: the server says so; an older server is judged by the label. */
function isFullPrice(appointment: Appointment): boolean {
  const fee = appointment.noShowFee;
  if (!fee) return false;
  return fee.fullPrice ?? money(fee.amountCents) === appointment.priceLabel;
}

/**
 * The warning before cancelling, when cancelling now would be a late cancellation
 * under the policy the client agreed to; null when it's free. Like the server, the
 * first time the client cancelled (or asked to) counts, if there was one.
 */
export function lateCancelWarning(appointment: Appointment, now: Date): string | null {
  const fee = appointment.noShowFee;
  if (!isCancellable(appointment, now) || !appointment.card || !fee || fee.lateCancelWindowMinutes === null) return null;
  const firstAsked = fee.customerCancelledAt ? new Date(fee.customerCancelledAt) : now;
  if (!cancelledLate(new Date(appointment.start), firstAsked, fee.lateCancelWindowMinutes)) return null;
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
 * For a picked time that starts less than the window from now (bookings open 30 minutes
 * ahead, the window is often an hour): "This time is less than 1 hour away, so cancelling
 * it may be charged $35." It can't be cancelled for free once it's booked. Null otherwise.
 */
export function lateCancelNotice(policy: NoShowPolicy, start: Date, now: Date): string | null {
  const fee = feeLabel(policy);
  if (!fee || policy.lateCancelWindowMinutes === null) return null;
  if (!cancelledLate(start, now, policy.lateCancelWindowMinutes)) return null;
  return `This time is less than ${windowLabel(policy.lateCancelWindowMinutes)} away, so cancelling it may be charged ${fee}.`;
}
