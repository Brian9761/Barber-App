// An appointment's card on file and its fee (for a no-show or a late cancellation), with
// the owner app's rules and words (IzzyClipzBusiness/Stores/FeePanel.swift and the Kit's
// NoShow.swift), which mirror the server's (server/src/feecase.ts): which fee can be
// charged now, what the details say about it, the badges on a schedule row, and what
// Reopen and Cancel say first. Checked against the server's own examples
// (server/test/fixtures/fee-cases.json).

import type { NoShowFee } from '../../api/types';
import { cardLabel, money, windowLabel } from '../../lib/format';
import { cancelledLate } from '../../lib/lateCancel';
import { dateTimeLabel, localDate, timeLabel } from '../../lib/shopTime';
import type { OwnerAppointment } from '../types';

export type FeeReason = 'noShow' | 'lateCancel';

export type FeeCase = { kind: 'chargeable'; reason: FeeReason } | { kind: 'refused'; message: string };

export const NO_CARD_MESSAGE = "This booking has no card on file, so there's no fee to charge.";
export const NOT_STARTED_MESSAGE = "The appointment hasn't started yet, so it can't be a no-show.";
const CANCELLED_IN_APP = "The client cancelled this booking in the app, so there's no fee.";
const SHOP_CANCELLED = "The shop cancelled this booking, so there's no fee.";
const MARK_NO_SHOW = 'Mark the appointment as a no-show first.';

/** "No-show fee", "Late cancellation fee". */
export function reasonTitle(reason: FeeReason | null | undefined): string {
  return reason === 'lateCancel' ? 'Late cancellation fee' : 'No-show fee';
}

/** The fee's title: what it's for, or "No-show fee" while that isn't known. */
export function feeTitle(fee: NoShowFee): string {
  return reasonTitle(fee.reason);
}

/** What these rules read of an appointment. */
type Booking = Pick<OwnerAppointment, 'status' | 'cancelledBy' | 'start' | 'card' | 'noShowFee'>;

/**
 * The server's rule, ignoring the clock (the Kit's `NoShowRule.feeCase`): a late cancellation
 * (cancelled by the client inside the agreed window, still cancelled), or a no-show (marked, and
 * the client never cancelled nor asked to).
 */
export function ruleFeeCase(
  status: OwnerAppointment['status'],
  cancelledBy: OwnerAppointment['cancelledBy'],
  start: Date,
  customerCancelledAt: Date | null,
  lateCancelWindowMinutes: number | null,
): FeeCase {
  if (status === 'cancelled') {
    if (cancelledBy !== 'customer') return { kind: 'refused', message: SHOP_CANCELLED };
    if (cancelledLate(start, customerCancelledAt, lateCancelWindowMinutes)) return { kind: 'chargeable', reason: 'lateCancel' };
    if (lateCancelWindowMinutes !== null && customerCancelledAt !== null) {
      return { kind: 'refused', message: `The client cancelled at least ${windowLabel(lateCancelWindowMinutes)} before, so there's no fee.` };
    }
    return { kind: 'refused', message: CANCELLED_IN_APP };
  }
  if (customerCancelledAt !== null) return { kind: 'refused', message: CANCELLED_IN_APP };
  if (status !== 'noShow') return { kind: 'refused', message: MARK_NO_SHOW };
  return { kind: 'chargeable', reason: 'noShow' };
}

/** Which fee the server lets the owner charge now, or why not (the Kit's `Appointment.feeCase(at:)`). */
export function feeCase(appointment: Booking, now: Date): FeeCase {
  const fee = appointment.noShowFee;
  if (!appointment.card || !fee) return { kind: 'refused', message: NO_CARD_MESSAGE };
  const start = new Date(appointment.start);
  const found = ruleFeeCase(
    appointment.status,
    appointment.cancelledBy,
    start,
    fee.customerCancelledAt ? new Date(fee.customerCancelledAt) : null,
    fee.lateCancelWindowMinutes,
  );
  if (found.kind === 'chargeable' && found.reason === 'noShow' && start.getTime() > now.getTime()) {
    return { kind: 'refused', message: NOT_STARTED_MESSAGE };
  }
  return found;
}

/**
 * The fee the owner can act on now, or null (the Kit's `chargeableFee(at:)`): a chargeable case
 * with a fee that isn't charged yet (a declined one can be tried again), or a pending one, always,
 * as "Check again" (the server only asks Stripe how that try went, and never charges twice).
 */
export function chargeableFee(appointment: Booking, now: Date): FeeReason | null {
  const fee = appointment.noShowFee;
  if (!appointment.card || !fee || fee.status === 'charged') return null;
  const found = feeCase(appointment, now);
  if (fee.status === 'pending') return fee.reason ?? (found.kind === 'chargeable' ? found.reason : 'noShow');
  return found.kind === 'chargeable' ? found.reason : null;
}

/** An earlier try at the fee has no final answer from Stripe yet: the button reads "Check again". */
export function isFeePending(appointment: Booking): boolean {
  return Boolean(appointment.card) && appointment.noShowFee?.status === 'pending';
}

/**
 * Whether "Mark no-show" is offered: once the appointment has started, whatever the card (on the
 * website a no-show is only ever marked after the start, which the server also needs for a
 * booking with a card on file, so the client can still cancel until then).
 */
export function canMarkNoShow(appointment: Pick<OwnerAppointment, 'status' | 'start'>, now: Date): boolean {
  return appointment.status === 'booked' && new Date(appointment.start).getTime() <= now.getTime();
}

/** The client cancelled in the app less than the agreed window before the start: a late cancellation. */
export function isCancelledLate(appointment: Booking): boolean {
  const fee = appointment.noShowFee;
  if (appointment.status !== 'cancelled' || appointment.cancelledBy !== 'customer' || !appointment.card || !fee) return false;
  return cancelledLate(new Date(appointment.start), fee.customerCancelledAt ? new Date(fee.customerCancelledAt) : null, fee.lateCancelWindowMinutes);
}

/** "$40", or "$40 (the full service price)". */
export function feeAmountLabel(fee: NoShowFee): string {
  return fee.fullPrice ? `${money(fee.amountCents)} (the full service price)` : money(fee.amountCents);
}

// ------------------------------------------------------------------ The panel

export type FeeStatusView =
  | { kind: 'notCharged'; note: string | null }
  | { kind: 'charged'; title: string; detail: string }
  | { kind: 'declined'; detail: string }
  | { kind: 'needsClient'; detail: string }
  | { kind: 'pending'; detail: string };

export interface FeeConfirmation {
  /** "Charge $35 to Kim Sample's Visa •••• 4242?" */
  title: string;
  message: string;
  /** "Charge $35". */
  button: string;
}

export interface FeeAction {
  /** "Charge no-show fee ($35)", "Charge late cancellation fee ($35)", "Charge again ($35)" or "Check again". */
  title: string;
  /** Asked before every new charge; null for Check again (it only finishes the try already confirmed). */
  confirmation: FeeConfirmation | null;
}

export interface FeePanel {
  /** "Visa •••• 4242". */
  cardLabel: string;
  /** "$35", or "$35 (the full service price)". */
  feeLabel: string;
  /** "For not showing up, or cancelling less than 1 hour before." */
  agreement: string;
  status: FeeStatusView;
  action: FeeAction | null;
  footer: string | null;
}

const PENDING =
  "Stripe hasn't confirmed this charge yet. Check again finishes it: if it went through, it shows as charged, and if Stripe never got it, it's sent now. To not charge it, reopen the appointment first.";
const PENDING_CHECK_ONLY =
  "Stripe hasn't confirmed this charge yet. Check again asks Stripe how it went: if it went through, it shows as charged, and if not, nothing is charged.";

function text(message: string | null | undefined, fallback: string): string {
  const trimmed = message?.trim() ?? '';
  return trimmed === '' ? fallback : trimmed;
}

/** Why a fee that wasn't charged can't be, or how it could be, in plain words. */
function feeNote(appointment: OwnerAppointment, now: Date): string | null {
  const found = feeCase(appointment, now);
  if (found.kind !== 'refused') return null;
  // A client who cancelled in the app (or asked to) is never charged a no-show fee: said first.
  if (appointment.noShowFee?.customerCancelledAt) return found.message;
  switch (appointment.status) {
    case 'booked':
      return new Date(appointment.start).getTime() > now.getTime()
        ? "If the client doesn't come, you can mark a no-show once the appointment has started. Then you can charge the fee."
        : "If the client didn't come, mark a no-show. Then you can charge the fee.";
    case 'completed':
      return null;
    default:
      return found.message;
  }
}

function whyNotAgain(appointment: OwnerAppointment, now: Date): string | null {
  const note = feeNote(appointment, now);
  if (note) return note;
  return appointment.status === 'completed' ? "The appointment is marked completed, so there's no fee to charge." : null;
}

function confirmationMessage(appointment: OwnerAppointment, fee: NoShowFee, reason: FeeReason, zone: string): string {
  const what = `${appointment.serviceName} with ${appointment.barberName}, ${dateTimeLabel(new Date(appointment.start), zone)}`;
  if (reason === 'noShow') return `No-show fee for ${what}. The client agreed to it when booking.`;
  let message = `Late cancellation fee for ${what}`;
  if (fee.customerCancelledAt) {
    const cancelled = new Date(fee.customerCancelledAt);
    const sameDay = localDate(cancelled, zone) === localDate(new Date(appointment.start), zone);
    message += sameDay ? `: the client cancelled at ${timeLabel(cancelled, zone)}` : `: the client cancelled on ${dateTimeLabel(cancelled, zone)}`;
    if (fee.lateCancelWindowMinutes !== null) message += `, less than ${windowLabel(fee.lateCancelWindowMinutes)} before`;
  }
  return `${message}. They agreed to it when booking.`;
}

/** The "Card on file" part of an appointment's details, or null without a card on file. */
export function feePanel(appointment: OwnerAppointment, now: Date, zone: string): FeePanel | null {
  const fee = appointment.noShowFee;
  if (!fee) return null;
  const card = appointment.card ? cardLabel(appointment.card) : 'the card on file';
  const chargeable = chargeableFee(appointment, now);
  const agreement =
    fee.lateCancelWindowMinutes !== null
      ? `For not showing up, or cancelling less than ${windowLabel(fee.lateCancelWindowMinutes)} before.`
      : 'For not showing up. Cancelling in the app before the start is free.';

  let status: FeeStatusView;
  let footer: string | null;
  switch (fee.status) {
    case 'charged': {
      const when = fee.chargedAt ? `, ${dateTimeLabel(new Date(fee.chargedAt), zone)}` : '';
      status = { kind: 'charged', title: `${feeTitle(fee)} charged`, detail: `${money(fee.amountCents)} to ${card}${when}.` };
      footer = "Refunds are made in the Stripe Dashboard. Reopening the appointment doesn't refund the fee.";
      break;
    }
    case 'declined':
      status = { kind: 'declined', detail: text(fee.message, 'The bank declined the card.') };
      footer = chargeable ? 'You can try the card again later, or ask the client to pay at the shop.' : whyNotAgain(appointment, now);
      break;
    case 'needsAction':
      status = { kind: 'needsClient', detail: text(fee.message, "The client's bank wants them to approve this charge. Ask them to pay at the shop.") };
      footer = chargeable ? null : whyNotAgain(appointment, now);
      break;
    case 'pending':
      status = { kind: 'pending', detail: feeCase(appointment, now).kind === 'chargeable' ? PENDING : PENDING_CHECK_ONLY };
      footer = null;
      break;
    default:
      status = { kind: 'notCharged', note: feeNote(appointment, now) };
      footer = chargeable ? 'Nothing is charged until you confirm, and a fee is only ever charged once.' : null;
  }

  let action: FeeAction | null = null;
  if (isFeePending(appointment)) {
    action = { title: 'Check again', confirmation: null };
  } else if (chargeable) {
    const amount = money(fee.amountCents);
    const title =
      fee.status === 'declined' || fee.status === 'needsAction' ? `Charge again (${amount})` : `Charge ${reasonTitle(chargeable).toLowerCase()} (${amount})`;
    action = {
      title,
      confirmation: {
        title: `Charge ${amount} to ${appointment.customer.name}'s ${card}?`,
        message: confirmationMessage(appointment, fee, chargeable, zone),
        button: `Charge ${amount}`,
      },
    };
  }

  return {
    cardLabel: appointment.card ? cardLabel(appointment.card) : 'Card on file',
    feeLabel: feeAmountLabel(fee),
    agreement,
    status,
    action,
    footer,
  };
}

// --------------------------------------------------------- Status changes

/**
 * What Reopen says first, when reopening changes something about the fee: a charged fee isn't
 * refunded, one Stripe hasn't confirmed may have gone through, a late cancellation that's reopened
 * can't be charged any more, and a booking the client cancelled in the app can't be charged a
 * no-show fee once it's reopened. Null when there's nothing to say.
 */
export function reopenWarning(appointment: OwnerAppointment, now: Date): string | null {
  const fee = appointment.noShowFee;
  if (!fee) return null;
  const what = `${money(fee.amountCents)} ${feeTitle(fee).toLowerCase()}`;
  switch (fee.status) {
    case 'charged':
      return `The ${what} stays charged: reopening doesn't refund it. Refunds are made in the Stripe Dashboard.`;
    case 'pending':
      return `Stripe hasn't confirmed the ${what} yet. If it went through, reopening doesn't refund it. Refunds are made in the Stripe Dashboard.`;
    default:
      if (chargeableFee(appointment, now) === 'lateCancel') {
        return `Once it's reopened, the ${money(fee.amountCents)} late cancellation fee can't be charged any more. The client cancelled in the app, so a no-show fee can't be charged either.`;
      }
      if (appointment.status === 'cancelled' && appointment.card && fee.customerCancelledAt) {
        return "The client cancelled this booking in the app, so once it's reopened, it can't be charged a no-show fee. To keep a no-show fee, ask them to book again in the app instead.";
      }
      return null;
  }
}

/** Under the status buttons of a booked appointment that hasn't started: when "Mark no-show" shows. */
export function noShowHint(appointment: OwnerAppointment, now: Date, zone: string): string | null {
  if (appointment.status !== 'booked' || canMarkNoShow(appointment, now)) return null;
  const start = new Date(appointment.start);
  const today = localDate(now, zone) === localDate(start, zone);
  const when = today ? `at ${timeLabel(start, zone)}` : `on ${dateTimeLabel(start, zone)}`;
  const tail = appointment.card ? ' Until then, the client can still cancel in the app.' : '';
  return `You can mark a no-show once the appointment starts ${when}.${tail}`;
}

/** Added to "Cancel appointment"'s question for a booking with a card on file. */
export function shopCancelNote(appointment: OwnerAppointment): string | null {
  if (!appointment.card) return null;
  const fee = appointment.noShowFee;
  const none = "There's no fee when the shop cancels.";
  if (!fee) return none;
  const what = `${money(fee.amountCents)} ${feeTitle(fee).toLowerCase()}`;
  switch (fee.status) {
    case 'charged':
      return `The ${what} stays charged: cancelling doesn't refund it. Refunds are made in the Stripe Dashboard.`;
    case 'pending':
      return `Stripe hasn't confirmed the ${what} yet. If it went through, cancelling doesn't refund it. Refunds are made in the Stripe Dashboard.`;
    default:
      return none;
  }
}

// ------------------------------------------------------------------ Badges

export type BadgeTone = 'booked' | 'completed' | 'noShow' | 'cancelled' | 'paid' | 'card' | 'feeCharged' | 'feeDeclined' | 'feeWaiting';

export interface Badge {
  text: string;
  tone: BadgeTone;
}

const STATUS_TITLE: Record<OwnerAppointment['status'], string> = {
  booked: 'Booked',
  completed: 'Completed',
  noShow: 'No-show',
  cancelled: 'Cancelled',
};

const METHOD_TITLE = { cash: 'Cash', other: 'Other', card: 'Card' } as const;

/** "Cash", "Other", "Card". */
export function methodTitle(method: keyof typeof METHOD_TITLE): string {
  return METHOD_TITLE[method];
}

/** "Paid $60 · Cash", "Paid $40": what an appointment's checkout (or payment) says. */
export function paidLabel(appointment: Pick<OwnerAppointment, 'sale' | 'payment'>): string | null {
  if (appointment.sale) return `Paid ${money(appointment.sale.totalCents)} · ${methodTitle(appointment.sale.method)}`;
  if (appointment.payment.status === 'paid') return appointment.payment.amountCents !== null ? `Paid ${money(appointment.payment.amountCents)}` : 'Paid';
  return null;
}

/**
 * The short labels on a schedule card and at the top of an appointment's details: the status
 * ("Cancelled late" for a late cancellation), what was paid, and the card on file or what
 * happened to its fee.
 */
export function appointmentBadges(appointment: OwnerAppointment): Badge[] {
  const badges: Badge[] = [{ text: isCancelledLate(appointment) ? 'Cancelled late' : STATUS_TITLE[appointment.status], tone: appointment.status }];
  const paid = paidLabel(appointment);
  if (paid) badges.push({ text: paid, tone: 'paid' });
  const fee = appointment.noShowFee;
  const onFile = appointment.card ? `Card on file · ${cardLabel(appointment.card)}` : 'Card on file';
  if (fee) {
    switch (fee.status) {
      case 'charged':
        badges.push({ text: `${feeTitle(fee)} ${money(fee.amountCents)} charged`, tone: 'feeCharged' });
        break;
      case 'declined':
        badges.push({ text: 'Fee declined', tone: 'feeDeclined' });
        break;
      case 'needsAction':
        badges.push({ text: 'Fee needs the client', tone: 'feeWaiting' });
        break;
      case 'pending':
        badges.push({ text: 'Fee not confirmed', tone: 'feeWaiting' });
        break;
      default:
        badges.push({ text: onFile, tone: 'card' });
    }
  } else if (appointment.card) {
    badges.push({ text: onFile, tone: 'card' });
  }
  return badges;
}

export function statusTitle(status: OwnerAppointment['status']): string {
  return STATUS_TITLE[status];
}

/**
 * The Payment part of the details: the service's payment, with a fee charged to the card on
 * file said apart from it.
 */
export function paymentSummary(appointment: OwnerAppointment): { title: string; value: string; feeNote: string | null } {
  const fee = appointment.noShowFee;
  const feeCharged = fee?.status === 'charged';
  let title: string;
  let value: string;
  if (appointment.sale) {
    title = 'Paid';
    value = `${money(appointment.sale.totalCents)} · ${methodTitle(appointment.sale.method)}`;
  } else if (appointment.payment.status === 'paid') {
    title = 'Paid';
    value = appointment.payment.amountCents !== null ? money(appointment.payment.amountCents) : 'Yes';
  } else {
    title = feeCharged ? 'Service not paid' : 'Not paid yet';
    value = appointment.priceLabel;
  }
  const feeNote = fee && feeCharged ? `The ${money(fee.amountCents)} ${feeTitle(fee).toLowerCase()} was charged to the card on file.` : null;
  return { title, value, feeNote };
}
