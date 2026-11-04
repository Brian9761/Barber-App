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
      fullPrice: z.boolean(),
      status: z.enum(['none', 'pending', 'charged', 'declined', 'needsAction']),
      chargedAt: instant.nullable(),
      message: z.string().min(1).nullable(),
      customerCancelledAt: instant.nullable(),
      lateCancelWindowMinutes: int.min(30).max(2880).nullable(),
      reason: z.enum(['noShow', 'lateCancel']).nullable(),
    })
    .nullable(),
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
      'late_cancel_fee',
      'stripe_not_configured',
      'owner_not_configured',
      'server_error',
    ]),
    message: z.string().min(1),
  }),
});

const httpsUrl = z.string().regex(/^https:\/\/\S+$/);
const Instagram = z.strictObject({ handle: z.string().min(1), url: httpsUrl });
const clock = z.string().regex(/^\d{2}:\d{2}$/);

/** GET /api/catalog: data/catalog.json as the Kit exports it, for the website. */
export const WebsiteCatalog = z.strictObject({
  timeZone: z.string().min(1),
  slotIntervalMinutes: int.positive(),
  leadTimeMinutes: int.min(0),
  windowDays: int.min(0),
  hours: z.record(z.enum(['1', '2', '3', '4', '5', '6', '7']), z.strictObject({ opens: clock, closes: clock })),
  services: z.array(
    z.strictObject({ id, name: z.string().min(1), description: z.string().min(1).optional(), category: z.string().min(1), popular: z.boolean() }),
  ),
  barbers: z.array(
    z.strictObject({
      id,
      name: z.string().min(1),
      title: z.string().min(1),
      bio: z.string().min(1),
      specialties: z.array(z.string().min(1)),
      monogram: z.string().regex(/^[A-Z0-9]{1,2}$/),
      instagram: Instagram.optional(),
    }),
  ),
  offerings: z.array(
    z.strictObject({
      id,
      serviceId: id,
      barberId: id,
      durationMinutes: int.positive(),
      priceCents: int.min(0),
      priceKind: z.enum(['fixed', 'startingAt', 'includedWithCut']),
      priceLabel: z.string().min(1),
      name: z.string().min(1).optional(),
    }),
  ),
  firstAvailable: z.array(z.strictObject({ serviceId: id, offeringIds: z.array(id).min(2) })),
  shop: z.strictObject({
    name: z.string().min(1),
    fullName: z.string().min(1),
    tagline: z.string().min(1),
    phone: z.strictObject({ e164: z.string().regex(/^\+1\d{10}$/), display: z.string().regex(/^\(\d{3}\) \d{3}-\d{4}$/) }),
    address: z.strictObject({
      street: z.string().min(1),
      unit: z.string().min(1).optional(),
      city: z.string().min(1),
      state: z.string().regex(/^[A-Z]{2}$/),
      postalCode: z.string().regex(/^\d{5}$/),
      lines: z.array(z.string().min(1)).min(1),
    }),
    coordinate: z.strictObject({ latitude: z.number().min(-90).max(90), longitude: z.number().min(-180).max(180) }),
    instagram: Instagram,
    appleMapsUrl: httpsUrl,
    appleMapsDirectionsUrl: httpsUrl,
    googleMapsUrl: httpsUrl,
    googleMapsDirectionsUrl: httpsUrl,
    googleReviewUrl: httpsUrl,
    websiteUrl: httpsUrl,
    about: z.array(z.string().min(1)),
    highlights: z.array(z.string().min(1)),
    paymentMethods: z.array(z.string().min(1)),
    accessibility: z.array(z.string().min(1)),
  }),
});

/** Response bodies by fixture name. */
export const RESPONSES = {
  health: z.strictObject({ ok: z.literal(true), version: z.string() }),
  catalog: WebsiteCatalog,
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
  // No-show protection
  'no-show-policy': NoShowPolicy,
  'no-show-policy-not-required': NoShowPolicy,
  'card-checkout': z.strictObject({ url: z.string().regex(/^https:\/\//), sessionId: z.string().regex(/^cs_(test|live)_/) }),
  'card-saved': z.strictObject({ card: SavedCard }),
  'no-show-settings': z.strictObject({ noShowSettings: NoShowSettings }),
  'no-show-settings-updated': z.strictObject({ noShowSettings: NoShowSettings }),
  'payments-with-fees': z.strictObject({ payments: z.array(Payment) }),
  'no-show-fee-charged': z.strictObject({ appointment: Appointment }),
  'no-show-fee-declined': z.strictObject({ appointment: Appointment }),
  'appointment-cancelled-late': z.strictObject({ appointment: Appointment }),
  'late-cancel-fee-charged': z.strictObject({ appointment: Appointment }),
} as const;

export type ResponseName = keyof typeof RESPONSES;
