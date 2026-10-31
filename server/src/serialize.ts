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
}

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
}

export function paymentJSON(row: PaymentRow) {
  return {
    id: row.id,
    amountCents: row.amount_cents,
    description: row.description,
    appointmentId: row.appointment_id,
    status: row.status,
    createdAt: formatInstant(row.created_at),
  };
}
