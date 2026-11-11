import { feeCase, isFullPrice, type FeeKind, type FeeReason } from './feecase.js';
import { formatInstant } from './time.js';

// Database rows → the API contract's JSON types (test/helpers/contract.ts has them as schemas).

export interface AppointmentRow {
  id: string;
  offering_id: string;
  service_id: string;
  barber_id: string;
  service_name: string;
  barber_name: string;
  price_label: string;
  price_cents: number;
  price_kind: string;
  start_at: Date;
  end_at: Date;
  status: 'booked' | 'cancelled' | 'completed' | 'no_show';
  cancelled_by: 'customer' | 'shop' | null;
  booked_by: 'customer' | 'shop';
  /** Booked for "any barber": the server picked `barber_id`. */
  any_barber: boolean;
  customer_name: string;
  customer_phone: string | null;
  customer_email: string | null;
  note: string | null;
  manage_token_hash: string | null;
  /** SHA-256 of the owner app's `Idempotency-Key` (migrations/003); shop bookings only. */
  idempotency_key_hash: string | null;
  payment_status: 'unpaid' | 'paid';
  paid_cents: number | null;
  paid_at: Date | null;
  payment_intent_id: string | null;
  created_at: Date;
  updated_at: Date;
  // No-show protection (migrations/004): all set when the booking has a card on file, else all null.
  saved_card_id: string | null;
  card_brand: string | null;
  card_last4: string | null;
  no_show_fee_cents: number | null;
  no_show_policy: string | null;
  no_show_consent_at: Date | null;
  /** The late-cancellation window in the agreed policy, in minutes; null when it had none. */
  late_cancel_window_minutes: number | null;
  no_show_fee_status: NoShowFeeRowStatus;
  no_show_fee_attempt: number;
  /** When the current attempt started (null before the first). */
  no_show_fee_attempt_at: Date | null;
  /** What the current attempt charges for (null before the first). */
  no_show_fee_reason: FeeReason | null;
  no_show_fee_payment_intent_id: string | null;
  no_show_fee_message: string | null;
  no_show_fee_charged_at: Date | null;
  /** When the client cancelled in the app, or asked to, before the start; never cleared. No fee then. */
  customer_cancelled_at: Date | null;
  /**
   * When the shop first marked it completed or checked it out (migrations/008); never cleared, so a
   * booking with a card on file that was completed can't become a no-show, even after it's reopened.
   */
  completed_at: Date | null;
  /** When the client's details were removed, 12 months on or on request (migrations/008, retention.ts). */
  anonymized_at: Date | null;
  /** The appointment's live sale (migrations/006), copied from `sales`: all three set, or all null. */
  sale_id: string | null;
  sale_total_cents: number | null;
  sale_method: SaleMethod | null;
}

/** How a sale was paid: Tap to Pay, cash, or another way the shop only records (Zelle, Cash App…). */
export type SaleMethod = 'card' | 'cash' | 'other';

export type NoShowFeeRowStatus = 'none' | 'pending' | 'charged' | 'declined' | 'needs_action';
export type NoShowFeeStatus = 'none' | 'pending' | 'charged' | 'declined' | 'needsAction';
export type NoShowFeeReason = 'noShow' | 'lateCancel';

const FEE_REASON_OUT: Record<FeeReason, NoShowFeeReason> = { no_show: 'noShow', late_cancel: 'lateCancel' };

const FEE_STATUS_OUT: Record<NoShowFeeRowStatus, NoShowFeeStatus> = {
  none: 'none',
  pending: 'pending',
  charged: 'charged',
  declined: 'declined',
  needs_action: 'needsAction',
};

export type AppointmentStatus = 'booked' | 'cancelled' | 'completed' | 'noShow';

export interface Appointment {
  id: string;
  offeringId: string;
  serviceId: string;
  serviceName: string;
  barberId: string;
  barberName: string;
  start: string;
  end: string;
  durationMinutes: number;
  priceLabel: string;
  status: AppointmentStatus;
  cancelledBy: 'customer' | 'shop' | null;
  payment: { status: 'unpaid' | 'paid'; amountCents: number | null; paidAt: string | null };
  customer: { name: string; phone: string | null; email: string | null };
  note: string | null;
  createdAt: string;
  /** The card on file for no-shows, or null when the booking has none. */
  card: { brand: string; last4: string } | null;
  /**
   * The fee agreed at booking (for a no-show or a late cancellation) and what happened to it,
   * or null without a card on file.
   */
  noShowFee: {
    amountCents: number;
    /** Whether the fee is the booked service's whole price (it is at 100%): "the full service price". */
    fullPrice: boolean;
    status: NoShowFeeStatus;
    chargedAt: string | null;
    message: string | null;
    /**
     * When the client cancelled in the app (or asked to) before the start. Then there's no
     * no-show fee; less than `lateCancelWindowMinutes` before the start, it's a late cancellation.
     */
    customerCancelledAt: string | null;
    /** The agreed policy's late-cancellation window in minutes, or null when it had none (cancelling was free). */
    lateCancelWindowMinutes: number | null;
    /**
     * What the fee is for: once the shop tried to charge it, what that charge was for;
     * before (or once a try that never reached Stripe was settled as not charged), the case
     * that applies now (a late cancellation by the client, or a no-show), or null when neither does.
     */
    reason: NoShowFeeReason | null;
  } | null;
  /** The appointment's checkout (its live sale), or null. Only the shop sees it. */
  sale: { id: string; totalCents: number; method: SaleMethod } | null;
  /**
   * When the shop first marked it completed or checked it out, or null; never cleared, so a booking
   * with a card on file that was completed can't become a no-show, even after it's reopened (see
   * `patchOwnerAppointment`). Only the shop sees it.
   */
  completedAt: string | null;
}

/** What a client sees of their own appointment: everything but the shop's checkout and when it was first completed. */
export type CustomerAppointment = Omit<Appointment, 'sale' | 'completedAt'>;

const STATUS_OUT: Record<AppointmentRow['status'], AppointmentStatus> = {
  booked: 'booked',
  cancelled: 'cancelled',
  completed: 'completed',
  no_show: 'noShow',
};

export const STATUS_IN: Record<AppointmentStatus, AppointmentRow['status']> = {
  booked: 'booked',
  cancelled: 'cancelled',
  completed: 'completed',
  noShow: 'no_show',
};

export function appointmentJSON(row: AppointmentRow): Appointment {
  return {
    id: row.id,
    offeringId: row.offering_id,
    serviceId: row.service_id,
    serviceName: row.service_name,
    barberId: row.barber_id,
    barberName: row.barber_name,
    start: formatInstant(row.start_at),
    end: formatInstant(row.end_at),
    durationMinutes: Math.round((row.end_at.getTime() - row.start_at.getTime()) / 60_000),
    priceLabel: row.price_label,
    status: STATUS_OUT[row.status],
    cancelledBy: row.cancelled_by,
    payment: {
      status: row.payment_status,
      amountCents: row.paid_cents,
      paidAt: row.paid_at ? formatInstant(row.paid_at) : null,
    },
    customer: { name: row.customer_name, phone: row.customer_phone, email: row.customer_email },
    note: row.note,
    createdAt: formatInstant(row.created_at),
    card: row.saved_card_id && row.card_brand && row.card_last4 ? { brand: row.card_brand, last4: row.card_last4 } : null,
    noShowFee:
      row.saved_card_id && row.no_show_fee_cents !== null
        ? {
            amountCents: row.no_show_fee_cents,
            fullPrice: isFullPrice(row),
            // Only a fee Stripe reported as succeeded is "charged" (see noshowfee.ts).
            status: FEE_STATUS_OUT[row.no_show_fee_status],
            chargedAt: row.no_show_fee_charged_at ? formatInstant(row.no_show_fee_charged_at) : null,
            message: row.no_show_fee_message,
            customerCancelledAt: row.customer_cancelled_at ? formatInstant(row.customer_cancelled_at) : null,
            lateCancelWindowMinutes: row.late_cancel_window_minutes,
            reason: feeReasonOf(row),
          }
        : null,
    sale:
      row.sale_id && row.sale_total_cents !== null && row.sale_method
        ? { id: row.sale_id, totalCents: row.sale_total_cents, method: row.sale_method }
        : null,
    completedAt: row.completed_at ? formatInstant(row.completed_at) : null,
  };
}

/** The appointment as its client sees it (the customer endpoints): without the shop's checkout, or when it was first completed. */
export function customerAppointmentJSON(row: AppointmentRow): CustomerAppointment {
  const { sale: _sale, completedAt: _completedAt, ...appointment } = appointmentJSON(row);
  return appointment;
}

/**
 * The fee's `reason` in the JSON (see `Appointment.noShowFee`): what the shop's try charges for while
 * it shows (pending, charged, declined, needs the client); otherwise, also once a try that never
 * reached Stripe was settled as not charged, the case that applies now.
 */
function feeReasonOf(row: AppointmentRow): NoShowFeeReason | null {
  if (row.no_show_fee_reason && row.no_show_fee_status !== 'none') return FEE_REASON_OUT[row.no_show_fee_reason];
  const now = feeCase(row);
  return now.reason ? FEE_REASON_OUT[now.reason] : null;
}

export interface TimeOffRow {
  id: string;
  barber_id: string | null;
  start_at: Date;
  end_at: Date;
  reason: string | null;
}

export function timeOffJSON(row: TimeOffRow) {
  return {
    id: row.id,
    barberId: row.barber_id,
    start: formatInstant(row.start_at),
    end: formatInstant(row.end_at),
    reason: row.reason,
  };
}

export interface ProductRow {
  id: string;
  name: string;
  description: string | null;
  price_cents: number | null;
  image_url: string | null;
  visible: boolean;
  sort: number;
}

export function productJSON(row: ProductRow) {
  return {
    id: row.id,
    name: row.name,
    description: row.description,
    priceCents: row.price_cents,
    imageUrl: row.image_url,
    visible: row.visible,
  };
}

export interface PaymentRow {
  id: string;
  amount_cents: number;
  description: string | null;
  appointment_id: string | null;
  status: string;
  receipt_email: string | null;
  created_at: Date;
  kind: 'in_person' | FeeKind;
  /** The card sale recorded for this payment (migrations/006), voided or not. */
  sale_id: string | null;
}

const PAYMENT_KIND_OUT: Record<PaymentRow['kind'], 'inPerson' | 'noShowFee' | 'lateCancelFee'> = {
  in_person: 'inPerson',
  no_show_fee: 'noShowFee',
  late_cancel_fee: 'lateCancelFee',
};

/** The columns of a PaymentRow, for `SELECT … FROM payments` (the sale's lookup names the table, so no alias). */
export const PAYMENT_COLUMNS =
  'id, amount_cents, description, appointment_id, status, receipt_email, created_at, kind, ' +
  '(SELECT s.id FROM sales s WHERE s.payment_intent_id = payments.id) AS sale_id';

export function paymentJSON(row: PaymentRow) {
  return {
    id: row.id,
    amountCents: row.amount_cents,
    description: row.description,
    appointmentId: row.appointment_id,
    status: row.status,
    createdAt: formatInstant(row.created_at),
    /** "inPerson" (Tap to Pay in the shop), or a fee charged to the card on file: "noShowFee" or "lateCancelFee". */
    kind: PAYMENT_KIND_OUT[row.kind] ?? ('inPerson' as const),
    /** The card sale (checkout) this payment recorded once it succeeded, or null. */
    saleId: row.sale_id ?? null,
  };
}
