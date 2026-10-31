import { z } from 'zod';

// The API v1 contract's response types as strict schemas: every key present, no extra keys, exact types.
// Used to check what the real handlers return before it's written to
// test/fixtures/contract/*.json for the Swift Kit to decode.

const instant = z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/, 'ISO 8601 UTC, no fractional seconds');
const date = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);
const id = z.string().min(1);
const int = z.number().int();

export const Appointment = z.strictObject({
  id,
  offeringId: id,
  serviceId: id,
  serviceName: z.string(),
  barberId: id,
  barberName: z.string(),
  start: instant,
  end: instant,
  durationMinutes: int.positive(),
  priceLabel: z.string(),
  status: z.enum(['booked', 'cancelled', 'completed', 'noShow']),
  cancelledBy: z.enum(['customer', 'shop']).nullable(),
  payment: z.strictObject({ status: z.enum(['unpaid', 'paid']), amountCents: int.nullable(), paidAt: instant.nullable() }),
  customer: z.strictObject({ name: z.string(), phone: z.string().regex(/^\+1\d{10}$/).nullable(), email: z.string().nullable() }),
  note: z.string().nullable(),
  createdAt: instant,
});

export const Slot = z.strictObject({ start: instant, barberIds: z.array(id) });
export const DaySlots = z.strictObject({ date, slots: z.array(Slot) });
export const Product = z.strictObject({
  id,
  name: z.string(),
  description: z.string().nullable(),
  priceCents: int.nullable(),
  imageUrl: z.string().nullable(),
  visible: z.boolean(),
});
export const Review = z.strictObject({
  author: z.string(),
  authorPhotoUrl: z.string().nullable(),
  authorUrl: z.string().nullable(),
  rating: int.min(1).max(5),
  text: z.string(),
  relativeTime: z.string().nullable(),
  publishedAt: instant.nullable(),
  url: z.string().nullable(),
});
export const ReviewSource = z.strictObject({
  available: z.boolean(),
  rating: z.number().nullable(),
  count: int.nullable(),
  url: z.string(),
  reviews: z.array(Review),
  fetchedAt: instant.nullable(),
});
export const TimeOff = z.strictObject({ id, barberId: id.nullable(), start: instant, end: instant, reason: z.string().nullable() });
export const Payment = z.strictObject({
  id,
  amountCents: int,
  description: z.string().nullable(),
  appointmentId: id.nullable(),
  status: z.string(),
  createdAt: instant,
});
export const ErrorBody = z.strictObject({
  error: z.strictObject({
    code: z.enum([
      'invalid_request',
      'unauthorized',
      'not_found',
      'slot_taken',
      'not_cancellable',
      'outside_hours',
      'too_soon',
      'too_far',
      'rate_limited',
      'stripe_not_configured',
      'owner_not_configured',
      'server_error',
    ]),
    message: z.string().min(1),
  }),
});

/** Response bodies by fixture name. */
export const RESPONSES = {
  health: z.strictObject({ ok: z.literal(true), version: z.string() }),
  availability: z.strictObject({ timeZone: z.string(), days: z.array(DaySlots) }),
  'appointment-created': z.strictObject({ appointment: Appointment, manageToken: z.string().regex(/^[A-Za-z0-9_-]{43}$/) }),
  appointment: z.strictObject({ appointment: Appointment }),
  'appointment-cancelled': z.strictObject({ appointment: Appointment }),
  reviews: z.strictObject({ google: ReviewSource, yelp: ReviewSource }),
  'reviews-unavailable': z.strictObject({ google: ReviewSource, yelp: ReviewSource }),
  products: z.strictObject({ products: z.array(Product) }),
  'owner-me': z.strictObject({
    ok: z.literal(true),
    stripe: z.strictObject({ configured: z.boolean(), mode: z.enum(['test', 'live']).nullable(), locationId: z.string().nullable() }),
  }),
  'owner-appointments': z.strictObject({ appointments: z.array(Appointment) }),
  'owner-appointment-created': z.strictObject({ appointment: Appointment }),
  'owner-appointment-updated': z.strictObject({ appointment: Appointment }),
  'time-off-list': z.strictObject({ timeOff: z.array(TimeOff) }),
  'time-off-created': z.strictObject({ timeOff: TimeOff }),
  'owner-products': z.strictObject({ products: z.array(Product) }),
  'product-created': z.strictObject({ product: Product }),
  'product-updated': z.strictObject({ product: Product }),
  'product-photo': z.strictObject({ product: Product }),
  'connection-token': z.strictObject({ secret: z.string().min(1) }),
  'payment-created': z.strictObject({ paymentIntentId: z.string().regex(/^pi_/), clientSecret: z.string().min(1) }),
  'payment-completed': z.strictObject({ payment: Payment }),
  payments: z.strictObject({ payments: z.array(Payment) }),
} as const;

export type ResponseName = keyof typeof RESPONSES;
