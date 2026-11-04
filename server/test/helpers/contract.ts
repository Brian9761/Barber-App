import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { expect } from 'vitest';
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
  card: z.strictObject({ brand: z.string().regex(/^[a-z0-9_]+$/), last4: z.string().regex(/^\d{4}$/) }).nullable(),
  noShowFee: z
    .strictObject({
      amountCents: int.min(50),
      status: z.enum(['none', 'pending', 'charged', 'declined', 'needsAction']),
      chargedAt: instant.nullable(),
      message: z.string().min(1).nullable(),
      customerCancelledAt: instant.nullable(),
      lateCancelWindowMinutes: int.min(30).max(2880).nullable(),
      reason: z.enum(['noShow', 'lateCancel']).nullable(),
    })
    .nullable(),
});

/** The owner's view of an appointment: the client's view plus its checkout (live sale). */
export const OwnerAppointment = Appointment.extend({
  sale: z.strictObject({ id, totalCents: int.min(0).max(1_000_000), method: z.enum(['card', 'cash', 'other']) }).nullable(),
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
  kind: z.enum(['inPerson', 'noShowFee', 'lateCancelFee']),
  saleId: id.nullable(),
});
export const SavedCard = z.strictObject({
  brand: z.string().regex(/^[a-z0-9_]+$/),
  last4: z.string().regex(/^\d{4}$/),
  expMonth: int.min(1).max(12),
  expYear: int.min(2000),
});
export const NoShowSettings = z.strictObject({
  enabled: z.boolean(),
  feeMode: z.enum(['percent', 'flat']),
  percent: int.min(1).max(100),
  flatCents: int.min(50).max(50_000),
  lateCancelEnabled: z.boolean(),
  lateCancelWindowMinutes: int.min(30).max(2880),
});
export const NoShowPolicy = z.strictObject({
  required: z.boolean(),
  minFeeCents: int.min(50).nullable(),
  maxFeeCents: int.min(50).nullable(),
  policyText: z.string().min(1).nullable(),
  lateCancelWindowMinutes: int.min(30).max(2880).nullable(),
  warning: z.strictObject({ title: z.string().min(1), message: z.string().min(1) }).nullable(),
});
export const SaleItem = z.strictObject({
  kind: z.enum(['service', 'product', 'custom']),
  serviceId: id.nullable(),
  productId: id.nullable(),
  name: z.string().min(1).max(80),
  quantity: int.min(1).max(99),
  unitCents: int.min(0).max(1_000_000),
  totalCents: int.min(0),
});
export const Sale = z.strictObject({
  id,
  barberId: id,
  barberName: z.string().min(1),
  appointmentId: id.nullable(),
  customerName: z.string().min(1).max(60).nullable(),
  method: z.enum(['card', 'cash', 'other']),
  paymentIntentId: z.string().regex(/^pi_/).nullable(),
  totalCents: int.min(0).max(1_000_000),
  items: z.array(SaleItem).min(1).max(20),
  soldAt: instant,
  voidedAt: instant.nullable(),
  voidReason: z.string().nullable(),
});
const month = z.string().regex(/^\d{4}-\d{2}$/);
const cents = int.min(0);
const rate = z.number().min(0);
export const Analytics = z.strictObject({
  from: date,
  to: date,
  barberId: id.nullable(),
  timeZone: z.string().min(1),
  generatedAt: instant,
  granularity: z.enum(['day', 'month']),
  totals: z.strictObject({
    salesCents: cents,
    servicesCents: cents,
    productsCents: cents,
    otherCents: cents,
    feesCents: cents,
    servicesCount: int.min(0),
    productsCount: int.min(0),
    clientsServed: int.min(0),
    checkouts: int.min(0),
    averageTicketCents: cents,
  }),
  previous: z.strictObject({ from: date, to: date, salesCents: cents }),
  productivity: z.strictObject({
    openMinutes: int.min(0),
    bookedMinutes: int.min(0),
    chairTimeBooked: rate,
    appointments: z.strictObject({
      booked: int.min(0),
      completed: int.min(0),
      noShows: int.min(0),
      cancelled: int.min(0),
      lateCancellations: int.min(0),
      upcoming: int.min(0),
    }),
    completionRate: rate.max(1),
    noShowRate: rate.max(1),
    salesPerHourCents: cents,
    productAttachRate: rate.max(1),
  }),
  topBarber: z
    .strictObject({ barberId: id, name: z.string().min(1), salesCents: cents, servicesCount: int.min(0), productsCount: int.min(0) })
    .nullable(),
  leaderboard: z.array(
    z.strictObject({
      rank: int.min(1),
      barberId: id,
      name: z.string().min(1),
      salesCents: cents,
      servicesCents: cents,
      productsCents: cents,
      servicesCount: int.min(0),
      productsCount: int.min(0),
      clientsServed: int.min(0),
      averageTicketCents: cents,
    }),
  ),
  services: z.array(z.strictObject({ serviceId: id, name: z.string().min(1), count: int.min(0), salesCents: cents })),
  products: z.array(z.strictObject({ productId: id.nullable(), name: z.string().min(1), quantity: int.min(0), salesCents: cents })),
  series: z.array(
    z.strictObject({
      date: z.union([date, month]),
      salesCents: cents,
      servicesCents: cents,
      productsCents: cents,
      otherCents: cents,
      feesCents: cents,
      servicesCount: int.min(0),
      productsCount: int.min(0),
    }),
  ),
  barbers: z.array(z.strictObject({ barberId: id, name: z.string().min(1) })),
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
      'card_required',
      'policy_changed',
      'not_chargeable',
      'not_started',
      'not_checkoutable',
      'already_checked_out',
      'amount_mismatch',
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
  'owner-appointments': z.strictObject({ appointments: z.array(OwnerAppointment) }),
  'owner-appointment-created': z.strictObject({ appointment: OwnerAppointment }),
  'owner-appointment-updated': z.strictObject({ appointment: OwnerAppointment }),
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
  // No-show protection
  'no-show-policy': NoShowPolicy,
  'no-show-policy-not-required': NoShowPolicy,
  'card-checkout': z.strictObject({ url: z.string().regex(/^https:\/\//), sessionId: z.string().regex(/^cs_(test|live)_/) }),
  'card-saved': z.strictObject({ card: SavedCard }),
  'no-show-settings': z.strictObject({ noShowSettings: NoShowSettings }),
  'no-show-settings-updated': z.strictObject({ noShowSettings: NoShowSettings }),
  'payments-with-fees': z.strictObject({ payments: z.array(Payment) }),
  'no-show-fee-charged': z.strictObject({ appointment: OwnerAppointment }),
  'no-show-fee-declined': z.strictObject({ appointment: OwnerAppointment }),
  'appointment-cancelled-late': z.strictObject({ appointment: Appointment }),
  'late-cancel-fee-charged': z.strictObject({ appointment: OwnerAppointment }),
  // Sales and analytics
  'sale-created': z.strictObject({ sale: Sale }),
  'sales-day': z.strictObject({ date, sales: z.array(Sale), totals: z.strictObject({ totalCents: int.min(0), count: int.min(0) }) }),
  'sale-voided': z.strictObject({ sale: Sale, message: z.string().min(1) }),
  'payment-created-with-sale': z.strictObject({ paymentIntentId: z.string().regex(/^pi_/), clientSecret: z.string().min(1) }),
  'payment-completed-with-sale': z.strictObject({ payment: Payment }),
  'owner-appointments-with-sale': z.strictObject({ appointments: z.array(OwnerAppointment) }),
  analytics: Analytics,
  'analytics-barber': Analytics,
} as const;

export type ResponseName = keyof typeof RESPONSES;

// Writing the fixtures (test/contract.test.ts has its own copy of these two; they work the same way).

const FIXTURES = new URL('../fixtures/contract/', import.meta.url);
const UPDATE = process.env.UPDATE_CONTRACT_FIXTURES === '1';

/** Writes `body` to test/fixtures/contract/`path` (with UPDATE_CONTRACT_FIXTURES=1, or when it's new); otherwise checks it's unchanged. */
export function recordFixture(path: string, body: unknown): void {
  const file = new URL(path, FIXTURES);
  const text = `${JSON.stringify(body, null, 2)}\n`;
  if (UPDATE || !existsSync(file)) {
    mkdirSync(new URL('.', file), { recursive: true });
    writeFileSync(file, text);
    return;
  }
  expect(JSON.parse(readFileSync(file, 'utf8')), `${path} is out of date: run UPDATE_CONTRACT_FIXTURES=1 npm test`).toEqual(body);
}

/** Checks a response against the contract's strict schema for `name` and records it as `name`.json. */
export function checkFixture<N extends ResponseName>(
  name: N,
  res: { status: number; body: unknown; text: string },
  status = 200,
): z.output<(typeof RESPONSES)[N]> {
  expect(res.status, `${name}: ${res.text}`).toBe(status);
  const parsed = RESPONSES[name].safeParse(res.body);
  if (!parsed.success) throw new Error(`${name} doesn't match the contract: ${JSON.stringify(parsed.error.issues, null, 2)}`);
  recordFixture(`${name}.json`, res.body);
  return parsed.data as z.output<(typeof RESPONSES)[N]>;
}
