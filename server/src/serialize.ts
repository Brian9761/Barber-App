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
  no_show_fee_status: NoShowFeeRowStatus;
  no_show_fee_attempt: number;
  no_show_fee_payment_intent_id: string | null;
  no_show_fee_message: string | null;
  no_show_fee_charged_at: Date | null;
}

export type NoShowFeeRowStatus = 'none' | 'pending' | 'charged' | 'declined' | 'needs_action';
export type NoShowFeeStatus = 'none' | 'pending' | 'charged' | 'declined' | 'needsAction';

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
  /** The no-show fee agreed at booking and what happened to it, or null without a card on file. */
  noShowFee: { amountCents: number; status: NoShowFeeStatus; chargedAt: string | null; message: string | null } | null;
}

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
            // Only a fee Stripe reported as succeeded is "charged" (see noshowfee.ts).
            status: FEE_STATUS_OUT[row.no_show_fee_status],
            chargedAt: row.no_show_fee_charged_at ? formatInstant(row.no_show_fee_charged_at) : null,
            message: row.no_show_fee_message,
          }
        : null,
  };
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
  kind: 'in_person' | 'no_show_fee';
}

export const PAYMENT_COLUMNS = 'id, amount_cents, description, appointment_id, status, receipt_email, created_at, kind';

export function paymentJSON(row: PaymentRow) {
  return {
    id: row.id,
    amountCents: row.amount_cents,
    description: row.description,
    appointmentId: row.appointment_id,
    status: row.status,
    createdAt: formatInstant(row.created_at),
    /** "inPerson" (Tap to Pay in the shop) or "noShowFee" (charged to the card on file). */
    kind: row.kind === 'no_show_fee' ? ('noShowFee' as const) : ('inPerson' as const),
  };
}
