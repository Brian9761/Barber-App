// The owner API's JSON, field for field as the server writes it (server/src/sales.ts,
// analytics.ts, stripeconnect.ts, computers.ts, noshow.ts, products.ts, timeoff.ts and
// server/test/fixtures/contract/*.json). Times are ISO 8601 UTC strings, money is in
// cents, shop days are "YYYY-MM-DD".

import type { Appointment } from '../api/types';

/** How a sale was paid: Tap to Pay on the iPhone, cash, or another way the shop only records (Zelle, Cash App…). */
export type SaleMethod = 'card' | 'cash' | 'other';

/** An appointment as the shop sees it: with its checkout (its live sale), if any, and when it was first completed. */
export interface OwnerAppointment extends Appointment {
  sale: { id: string; totalCents: number; method: SaleMethod } | null;
  /**
   * When the shop first marked it completed or checked it out, or null. The server never clears it:
   * a booking with a card on file that was completed can't become a no-show, even after it's reopened
   * (`completed_at`). Missing from a server from before it.
   */
  completedAt: string | null;
}

export type SaleItemKind = 'service' | 'product' | 'custom';

export interface SaleItem {
  kind: SaleItemKind;
  serviceId: string | null;
  /** Null for a product deleted since; the name stays. */
  productId: string | null;
  name: string;
  quantity: number;
  unitCents: number;
  totalCents: number;
}

export interface Sale {
  id: string;
  barberId: string;
  barberName: string;
  appointmentId: string | null;
  customerName: string | null;
  method: SaleMethod;
  /** The Tap to Pay payment of a card sale, else null. */
  paymentIntentId: string | null;
  totalCents: number;
  items: SaleItem[];
  soldAt: string;
  voidedAt: string | null;
  voidReason: string | null;
}

/** GET /api/owner/sales?date= */
export interface SalesDay {
  date: string;
  /** Newest first, voided ones too. */
  sales: Sale[];
  /** Live sales only. */
  totals: { totalCents: number; count: number };
}

export type NewSaleItem =
  | { kind: 'service'; serviceId: string; unitCents?: number; quantity?: number }
  | { kind: 'product'; productId: string; unitCents?: number; quantity?: number }
  | { kind: 'custom'; name: string; unitCents: number; quantity?: number };

/** POST /api/owner/sales: cash or other (card sales are taken with Tap to Pay on the iPhone). */
export interface NewSale {
  barberId: string;
  appointmentId?: string | null;
  customerName?: string | null;
  method: 'cash' | 'other';
  items: NewSaleItem[];
}

/** POST /api/owner/sales/:id/void */
export interface VoidedSale {
  sale: Sale;
  message: string;
}

export interface Product {
  id: string;
  name: string;
  description: string | null;
  /** Null: no price (asked for at checkout). */
  priceCents: number | null;
  imageUrl: string | null;
  /** Shown to clients in the Izzy Clipz app. */
  visible: boolean;
}

export interface ProductInput {
  name: string;
  description: string | null;
  priceCents: number | null;
  visible: boolean;
}

export interface TimeOff {
  id: string;
  /** Null: the whole shop. */
  barberId: string | null;
  start: string;
  end: string;
  reason: string | null;
}

export type StripeMode = 'connect' | 'direct' | 'off';
export type StripeStatus = 'notConnected' | 'needsInfo' | 'pending' | 'active' | 'restricted' | 'direct' | 'off';

/** GET /api/owner/stripe */
export interface StripeConnection {
  mode: StripeMode;
  /** A status this version doesn't know is shown with the server's message. */
  status: StripeStatus | (string & {});
  accountId: string | null;
  businessName: string | null;
  livemode: boolean | null;
  chargesEnabled: boolean;
  payoutsEnabled: boolean;
  detailsSubmitted: boolean;
  requirementsDue: number;
  message: string;
  dashboardUrl: string;
  checkedAt: string | null;
}

/** POST /api/owner/stripe/connect */
export interface StripeConnectLink {
  url: string;
  expiresAt: string;
}

export interface NoShowSettings {
  enabled: boolean;
  feeMode: 'percent' | 'flat';
  percent: number;
  flatCents: number;
  lateCancelEnabled: boolean;
  lateCancelWindowMinutes: number;
}

export interface ComputerSession {
  id: string;
  name: string;
  createdAt: string;
  lastUsedAt: string;
  expiresAt: string;
  /** The computer asking. */
  current: boolean;
}

/** POST /api/computer-sessions */
export interface SignedIn {
  token: string;
  session: ComputerSession;
}

// --------------------------------------------------------------- Analytics

export type Granularity = 'day' | 'month';

export interface AnalyticsTotals {
  salesCents: number;
  servicesCents: number;
  productsCents: number;
  otherCents: number;
  feesCents: number;
  servicesCount: number;
  productsCount: number;
  clientsServed: number;
  checkouts: number;
  averageTicketCents: number;
}

export interface AnalyticsAppointments {
  booked: number;
  completed: number;
  noShows: number;
  cancelled: number;
  lateCancellations: number;
  upcoming: number;
}

export interface AnalyticsProductivity {
  openMinutes: number;
  bookedMinutes: number;
  /** A raw ratio, which can pass 1; shown capped at 100%. */
  chairTimeBooked: number;
  appointments: AnalyticsAppointments;
  completionRate: number;
  noShowRate: number;
  salesPerHourCents: number;
  productAttachRate: number;
}

export interface LeaderboardEntry {
  rank: number;
  barberId: string;
  name: string;
  salesCents: number;
  servicesCents: number;
  productsCents: number;
  servicesCount: number;
  productsCount: number;
  clientsServed: number;
  averageTicketCents: number;
}

export interface TopBarber {
  barberId: string;
  name: string;
  salesCents: number;
  servicesCount: number;
  productsCount: number;
}

export interface ServiceLine {
  serviceId: string;
  name: string;
  count: number;
  salesCents: number;
}

export interface ProductLine {
  productId: string | null;
  name: string;
  quantity: number;
  salesCents: number;
}

export interface SeriesEntry {
  /** "2026-11-01" by day, "2026-11" by month. */
  date: string;
  salesCents: number;
  servicesCents: number;
  productsCents: number;
  otherCents: number;
  feesCents: number;
  servicesCount: number;
  productsCount: number;
}

/** GET /api/owner/analytics */
export interface Analytics {
  from: string;
  to: string;
  barberId: string | null;
  timeZone: string;
  generatedAt: string;
  granularity: Granularity;
  totals: AnalyticsTotals;
  previous: { from: string; to: string; salesCents: number };
  productivity: AnalyticsProductivity;
  topBarber: TopBarber | null;
  leaderboard: LeaderboardEntry[];
  services: ServiceLine[];
  products: ProductLine[];
  series: SeriesEntry[];
  barbers: { barberId: string; name: string }[];
}

export interface AnalyticsQuery {
  from: string;
  to: string;
  barberId: string | null;
}
