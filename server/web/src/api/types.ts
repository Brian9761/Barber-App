// The API's JSON, field for field as the server writes it (server/src/*.ts and
// server/test/fixtures/contract/*.json). Times are ISO 8601 UTC strings, money
// is in cents, shop days are "YYYY-MM-DD".

import type { PriceKind } from '../lib/format';
import type { WeeklyHours } from '../lib/shopTime';

export interface CatalogService {
  id: string;
  name: string;
  description?: string;
  /** The menu category's title, "Haircuts". */
  category: string;
  popular: boolean;
}

export interface CatalogBarber {
  id: string;
  name: string;
  /** "Owner · Barber". */
  title: string;
  bio: string;
  specialties: string[];
  /** The two letters on their tile, "IZ". */
  monogram: string;
  instagram?: { handle: string; url: string };
}

export interface Offering {
  /** "<barber id>/<menu item id>": what a booking for this barber sends as `offeringId`. */
  id: string;
  serviceId: string;
  barberId: string;
  durationMinutes: number;
  priceCents: number;
  priceKind: PriceKind;
  priceLabel: string;
  /** What this barber's version includes, when it says more than the service does. */
  note?: string;
}

export interface Shop {
  name: string;
  fullName: string;
  tagline: string;
  phone: { e164: string; display: string };
  address: { street: string; unit?: string; city: string; state: string; postalCode: string; lines: string[] };
  coordinate: { latitude: number; longitude: number };
  instagram: { handle: string; url: string };
  appleMapsUrl: string;
  appleMapsDirectionsUrl: string;
  googleMapsUrl: string;
  googleMapsDirectionsUrl: string;
  googleReviewUrl: string;
  websiteUrl: string;
  about: string[];
  highlights: string[];
  paymentMethods: string[];
  accessibility: string[];
}

/** GET /api/catalog */
export interface Catalog {
  timeZone: string;
  slotIntervalMinutes: number;
  leadTimeMinutes: number;
  windowDays: number;
  hours: WeeklyHours;
  services: CatalogService[];
  barbers: CatalogBarber[];
  offerings: Offering[];
  /** For each service at least two barbers share: the offerings "Any barber" picks from, in team order. */
  firstAvailable: { serviceId: string; offeringIds: string[] }[];
  shop: Shop;
}

export interface Slot {
  start: string;
  /** The barbers free at that time, in team order. */
  barberIds: string[];
}

export interface DaySlots {
  date: string;
  slots: Slot[];
}

/** GET /api/availability */
export interface Availability {
  timeZone: string;
  days: DaySlots[];
}

export interface FeeWarning {
  title: string;
  message: string;
}

/** GET /api/no-show-policy */
export interface NoShowPolicy {
  required: boolean;
  minFeeCents: number | null;
  maxFeeCents: number | null;
  /** What the client agrees to; the booking sends it back exactly. */
  policyText: string | null;
  lateCancelWindowMinutes: number | null;
  warning: FeeWarning | null;
}

export type AppointmentStatus = 'booked' | 'cancelled' | 'completed' | 'noShow';

export interface NoShowFee {
  amountCents: number;
  /** The fee is the booked service's whole price. Missing on a server from before it. */
  fullPrice?: boolean;
  status: 'none' | 'pending' | 'charged' | 'declined' | 'needsAction';
  chargedAt: string | null;
  message: string | null;
  customerCancelledAt: string | null;
  lateCancelWindowMinutes: number | null;
  reason: 'noShow' | 'lateCancel' | null;
}

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
  card: { brand: string; last4: string } | null;
  noShowFee: NoShowFee | null;
}

/** POST /api/appointments */
export interface BookingConfirmation {
  appointment: Appointment;
  manageToken: string;
}

export interface Review {
  author: string;
  authorPhotoUrl: string | null;
  authorUrl: string | null;
  rating: number;
  text: string;
  relativeTime: string | null;
  publishedAt: string | null;
  url: string | null;
}

export interface ReviewSource {
  available: boolean;
  rating: number | null;
  count: number | null;
  url: string;
  reviews: Review[];
  fetchedAt: string | null;
}

/** GET /api/reviews */
export interface Reviews {
  google: ReviewSource;
  yelp: ReviewSource;
}

/** POST /api/cards/checkout */
export interface CardCheckout {
  url: string;
  sessionId: string;
}

export interface SavedCard {
  brand: string;
  last4: string;
  expMonth: number;
  expYear: number;
}

/** Who a booking is for: one barber's offering, or a service with whoever is free first. */
export type BookingTarget = { offeringId: string } | { serviceId: string; barberId: 'any' };

export interface NewAppointment {
  target: BookingTarget;
  start: string;
  customer: { name: string; phone: string; email?: string };
  note?: string;
  /** The policy text the client was shown, exactly, when a card is required. */
  noShowPolicy?: string;
}
