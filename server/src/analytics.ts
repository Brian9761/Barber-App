import { z } from 'zod';
import { requireOwner } from './auth.js';
import type { Busy } from './availability.js';
import type { Catalog } from './catalog.js';
import type { Queryable } from './db.js';
import { cancelledLate } from './feecase.js';
import { ApiError, json } from './http.js';
import type { Context } from './router.js';
import type { AppointmentRow } from './serialize.js';
import { addDays, dayBounds, daysBetween, formatInstant, localDate, wallClock, weekday } from './time.js';
import { calendarDate, parse, shortId } from './validation.js';

// Analytics for the whole shop and for each barber (GET /api/owner/analytics): the
// top sales barber, products sold, services sold, how productive the shop was, the
// leaderboard, sales by service, and sales day by day. Every number is defined in
// this file, once, in the same words as docs/analytics.md.
//
// A day is a shop-local calendar day (America/Los_Angeles, from the catalog). The
// database adds things up per day (or month) and barber, using day boundaries
// worked out here with Luxon, never the database's own time zone, all in one
// read-only snapshot; `computeAnalytics` then applies the definitions. Nothing here
// calls Stripe: fees count once Stripe told the server they succeeded.

/** The longest range, in shop-local days (from and to included). */
export const MAX_ANALYTICS_DAYS = 366;
/** Ranges up to this many days get one series entry per day; longer ones, one per month. */
export const MAX_DAILY_SERIES_DAYS = 62;
/** How far from today `from` and `to` may be, either way (about ten years). */
export const MAX_DAYS_FROM_TODAY = 3660;

export type Granularity = 'day' | 'month';

/** One series entry's days: a single day, or the part of a month inside the range. */
export interface Period {
  /** "2026-11-01" for a day, "2026-11" for a month. */
  label: string;
  from: string;
  to: string;
}

/** The first day of the month after `month` ("2026-11" → "2026-12-01"). */
function nextMonth(month: string): string {
  const year = Number(month.slice(0, 4));
  const m = Number(month.slice(5, 7));
  return m === 12 ? `${String(year + 1).padStart(4, '0')}-01-01` : `${month.slice(0, 4)}-${String(m + 1).padStart(2, '0')}-01`;
}

/**
 * `series`: one entry per day when the range is 62 days or fewer (`granularity: "day"`),
 * otherwise one per calendar month (`"month"`, dated "2026-11"). Every day or month in the
 * range is there, zeros included; the first and last months hold only the range's days.
 */
export function seriesPeriods(from: string, to: string): { granularity: Granularity; periods: Period[] } {
  const days = daysBetween(from, to) + 1;
  if (days <= MAX_DAILY_SERIES_DAYS) {
    const periods = Array.from({ length: days }, (_, i) => {
      const date = addDays(from, i);
      return { label: date, from: date, to: date };
    });
    return { granularity: 'day', periods };
  }
  const periods: Period[] = [];
  for (let start = from; start <= to; ) {
    const month = start.slice(0, 7);
    const next = nextMonth(month);
    const last = addDays(next, -1);
    periods.push({ label: month, from: start, to: last < to ? last : to });
    start = next;
  }
  return { granularity: 'month', periods };
}

/** `previous`: the same number of days right before `from`. */
export function previousPeriod(from: string, to: string): { from: string; to: string } {
  const days = daysBetween(from, to) + 1;
  return { from: addDays(from, -days), to: addDays(from, -1) };
}

/** round(numerator / denominator), halves up, or 0 when the denominator is 0. Whole cents in, whole cents out. */
export function roundedRatio(numerator: number, denominator: number): number {
  return denominator > 0 ? Math.floor((2 * numerator + denominator) / (2 * denominator)) : 0;
}

/** numerator / denominator, or 0 when the denominator is 0. */
export function ratio(numerator: number, denominator: number): number {
  return denominator > 0 ? numerator / denominator : 0;
}

/**
 * `openMinutes` for one barber: for each day of `dates` up to and including `today`, the
 * shop's opening hours that day minus the time off that overlaps them (the barber's own or the
 * whole shop's; where blocks overlap each other, that time counts once). Days after today count
 * 0, and so does a day the shop is closed. Today counts all of its hours.
 */
export function openMinutes(catalog: Catalog, barberId: string, dates: readonly string[], today: string, timeOff: readonly Busy[]): number {
  let total = 0;
  for (const date of dates) {
    if (date > today) continue;
    const hours = catalog.hours(weekday(date));
    if (!hours) continue;
    const opens = wallClock(date, hours.opens, catalog.timeZone)?.getTime();
    const closes = wallClock(date, hours.closes, catalog.timeZone)?.getTime();
    if (opens === undefined || closes === undefined || closes <= opens) continue;
    const blocks = timeOff
      .filter((b) => (b.barberId === null || b.barberId === barberId) && b.start.getTime() < closes && b.end.getTime() > opens)
      .map((b) => [Math.max(b.start.getTime(), opens), Math.min(b.end.getTime(), closes)] as const)
      .sort((a, b) => a[0] - b[0]);
    let off = 0;
    let covered = opens;
    for (const [start, end] of blocks) {
      const from = Math.max(start, covered);
      if (end > from) {
        off += end - from;
        covered = end;
      }
    }
    total += closes - opens - off;
  }
  return Math.round(total / 60_000);
}

// What the database adds up (see `loadFacts`).

/** Money of one kind, added up per period and barber (and per service or product). */
export interface MoneyFact {
  /** The series period's index, or -1 for the previous period. */
  period: number;
  /** Who gets credit; null only for a fee whose appointment is gone. */
  barberId: string | null;
  /**
   * - service: a service item of a live sale, or (`visit`) a completed appointment with no live sale;
   * - product, custom: items of live sales;
   * - fee: a no-show or late-cancellation fee Stripe charged.
   */
  kind: 'service' | 'product' | 'custom' | 'fee';
  /** A completed appointment without a live sale, counted at its booked price. */
  visit: boolean;
  /** Services: the catalog's service id. Products: the product id, or null once deleted. Otherwise null. */
  itemId: string | null;
  /** The name when sold; for a product that still exists, its current name. */
  name: string;
  /** Services and products: how many (quantities added up; an appointment is 1). Custom items and fees: how many lines. */
  count: number;
  cents: number;
}

/** Live sales in the range (by when they were sold), per barber. */
export interface SaleCountFact {
  barberId: string;
  sales: number;
  withoutAppointment: number;
  /** Sales with at least one product item. */
  withProduct: number;
}

/** Appointments in the range (by their start's day), per barber. */
export interface AppointmentFact {
  barberId: string;
  booked: number;
  completed: number;
  noShows: number;
  cancelled: number;
  lateCancellations: number;
  upcoming: number;
  bookedMinutes: number;
}

export interface AnalyticsInput {
  from: string;
  to: string;
  barberId: string | null;
  timeZone: string;
  generatedAt: Date;
  granularity: Granularity;
  periods: Period[];
  previous: { from: string; to: string };
  /** Every barber, in team order; `active` ones are on the team now. */
  barbers: { id: string; name: string; active: boolean }[];
  /** The menu's name for a service id, if it's still on the menu. */
  serviceName(id: string): string | undefined;
  money: MoneyFact[];
  sales: SaleCountFact[];
  appointments: AppointmentFact[];
  /** Each active barber's open minutes over the range (`openMinutes`). */
  openMinutes: Map<string, number>;
}

/** What one barber, or the whole selection, sold and did. */
interface Tally {
  servicesCents: number;
  servicesCount: number;
  productsCents: number;
  productsCount: number;
  otherCents: number;
  feesCents: number;
  /** Live sales; those without an appointment; those with a product. */
  sales: number;
  salesWithoutAppointment: number;
  salesWithProduct: number;
  /** Completed appointments without a live sale. */
  visits: number;
  /** All completed appointments. */
  completed: number;
}

const emptyTally = (): Tally => ({
  servicesCents: 0,
  servicesCount: 0,
  productsCents: 0,
  productsCount: 0,
  otherCents: 0,
  feesCents: 0,
  sales: 0,
  salesWithoutAppointment: 0,
  salesWithProduct: 0,
  visits: 0,
  completed: 0,
});

/**
 * Service sales: the service items of live sales (the day they were sold, for the sale's
 * barber) plus every completed appointment with no live sale (the day it started, for its
 * barber, at its booked price, counting 1). Product sales: product items of live sales,
 * quantities and totals added up. Other: custom items. Fees: no-show and late-cancellation
 * fees Stripe charged (the day they were charged, for the appointment's barber).
 */
function addMoney(tally: Tally, fact: MoneyFact): void {
  switch (fact.kind) {
    case 'service':
      tally.servicesCents += fact.cents;
      tally.servicesCount += fact.count;
      if (fact.visit) tally.visits += fact.count;
      break;
    case 'product':
      tally.productsCents += fact.cents;
      tally.productsCount += fact.count;
      break;
    case 'custom':
      tally.otherCents += fact.cents;
      break;
    case 'fee':
      tally.feesCents += fact.cents;
      break;
  }
}

function addSales(tally: Tally, fact: SaleCountFact): void {
  tally.sales += fact.sales;
  tally.salesWithoutAppointment += fact.withoutAppointment;
  tally.salesWithProduct += fact.withProduct;
}

/** `salesCents` = services + products + other + fees. */
const salesCents = (t: Tally) => t.servicesCents + t.productsCents + t.otherCents + t.feesCents;
/** What was sold without the fees: services + products + other. */
const soldCents = (t: Tally) => t.servicesCents + t.productsCents + t.otherCents;
/** `checkouts` = live sales + completed appointments without a sale. */
const checkouts = (t: Tally) => t.sales + t.visits;
/** `clientsServed` = completed appointments + live sales without an appointment. */
const clientsServed = (t: Tally) => t.completed + t.salesWithoutAppointment;
/** `averageTicketCents` = round((services + products + other) / checkouts), or 0. */
const averageTicketCents = (t: Tally) => roundedRatio(soldCents(t), checkouts(t));

function totalsJSON(t: Tally) {
  return {
    salesCents: salesCents(t),
    servicesCents: t.servicesCents,
    productsCents: t.productsCents,
    otherCents: t.otherCents,
    feesCents: t.feesCents,
    servicesCount: t.servicesCount,
    productsCount: t.productsCount,
    clientsServed: clientsServed(t),
    checkouts: checkouts(t),
    averageTicketCents: averageTicketCents(t),
  };
}

function seriesJSON(label: string, t: Tally) {
  return {
    date: label,
    salesCents: salesCents(t),
    servicesCents: t.servicesCents,
    productsCents: t.productsCents,
    otherCents: t.otherCents,
    feesCents: t.feesCents,
    servicesCount: t.servicesCount,
    productsCount: t.productsCount,
  };
}

const byName = (a: string, b: string) => a.localeCompare(b, 'en');

/**
 * `leaderboard` order: `salesCents` high to low, then `servicesCount` high to low, then
 * name A to Z. `rank` starts at 1; barbers with the same sales and the same number of
 * services share a rank, and the next rank skips (1, 1, 3).
 */
export function rankLeaderboard<T extends { name: string; salesCents: number; servicesCount: number }>(entries: readonly T[]): (T & { rank: number })[] {
  const sorted = [...entries].sort((a, b) => b.salesCents - a.salesCents || b.servicesCount - a.servicesCount || byName(a.name, b.name));
  let rank = 0;
  return sorted.map((entry, i) => {
    const before = sorted[i - 1];
    if (!before || before.salesCents !== entry.salesCents || before.servicesCount !== entry.servicesCount) rank = i + 1;
    return { rank, ...entry };
  });
}

/**
 * The analytics JSON. `totals`, `services`, `products`, `series`, `productivity` and
 * `previous` cover the selection: the whole shop, or the one barber `barberId` names. The
 * leaderboard and the top barber are always the whole shop's, so a barber's page still
 * shows his rank.
 */
export function computeAnalytics(input: AnalyticsInput) {
  const selected = (barberId: string | null) => input.barberId === null || barberId === input.barberId;
  const team = input.barbers.filter((b) => b.active);
  const scope = emptyTally();
  const perBarber = new Map(team.map((b) => [b.id, emptyTally()]));
  const perPeriod = input.periods.map(() => emptyTally());
  let previousCents = 0;
  const services = new Map<string, { serviceId: string; name: string; count: number; salesCents: number }>();
  const products = new Map<string, { productId: string | null; name: string; quantity: number; salesCents: number }>();

  for (const fact of input.money) {
    if (fact.period < 0) {
      if (selected(fact.barberId)) previousCents += fact.cents;
      continue;
    }
    const barber = fact.barberId === null ? undefined : perBarber.get(fact.barberId);
    if (barber) addMoney(barber, fact);
    if (!selected(fact.barberId)) continue;
    addMoney(scope, fact);
    const period = perPeriod[fact.period];
    if (period) addMoney(period, fact);
    if (fact.kind === 'service' && fact.itemId !== null) {
      const line = services.get(fact.itemId) ?? { serviceId: fact.itemId, name: input.serviceName(fact.itemId) ?? fact.name, count: 0, salesCents: 0 };
      line.count += fact.count;
      line.salesCents += fact.cents;
      services.set(fact.itemId, line);
    } else if (fact.kind === 'product') {
      // A deleted product has no id any more: it's listed by the name it was sold under.
      const key = fact.itemId ?? `deleted:${fact.name}`;
      const line = products.get(key) ?? { productId: fact.itemId, name: fact.name, quantity: 0, salesCents: 0 };
      line.quantity += fact.count;
      line.salesCents += fact.cents;
      products.set(key, line);
    }
  }
  for (const fact of input.sales) {
    const barber = perBarber.get(fact.barberId);
    if (barber) addSales(barber, fact);
    if (selected(fact.barberId)) addSales(scope, fact);
  }
  const appointments = { booked: 0, completed: 0, noShows: 0, cancelled: 0, lateCancellations: 0, upcoming: 0 };
  let bookedMinutes = 0;
  for (const fact of input.appointments) {
    const barber = perBarber.get(fact.barberId);
    if (barber) barber.completed += fact.completed;
    if (!selected(fact.barberId)) continue;
    scope.completed += fact.completed;
    appointments.booked += fact.booked;
    appointments.completed += fact.completed;
    appointments.noShows += fact.noShows;
    appointments.cancelled += fact.cancelled;
    appointments.lateCancellations += fact.lateCancellations;
    appointments.upcoming += fact.upcoming;
    bookedMinutes += fact.bookedMinutes;
  }
  // openMinutes: each selected barber who's on the team (see `openMinutes`).
  const open = team.filter((b) => selected(b.id)).reduce((sum, b) => sum + (input.openMinutes.get(b.id) ?? 0), 0);
  const visitsWithOutcome = appointments.completed + appointments.noShows;

  const leaderboard = rankLeaderboard(
    team.map((b) => {
      const t = perBarber.get(b.id) ?? emptyTally();
      return {
        barberId: b.id,
        name: b.name,
        salesCents: salesCents(t),
        servicesCents: t.servicesCents,
        productsCents: t.productsCents,
        servicesCount: t.servicesCount,
        productsCount: t.productsCount,
        clientsServed: clientsServed(t),
        averageTicketCents: averageTicketCents(t),
      };
    }),
  );
  const first = leaderboard[0];

  return {
    from: input.from,
    to: input.to,
    barberId: input.barberId,
    timeZone: input.timeZone,
    generatedAt: formatInstant(input.generatedAt),
    granularity: input.granularity,
    totals: totalsJSON(scope),
    previous: { from: input.previous.from, to: input.previous.to, salesCents: previousCents },
    productivity: {
      openMinutes: open,
      bookedMinutes,
      /** bookedMinutes / openMinutes, or 0: a raw ratio, which can pass 1 (the apps show at most 100%). */
      chairTimeBooked: ratio(bookedMinutes, open),
      appointments,
      /** completed / (completed + no-shows), or 0. */
      completionRate: ratio(appointments.completed, visitsWithOutcome),
      /** no-shows / (completed + no-shows), or 0. */
      noShowRate: ratio(appointments.noShows, visitsWithOutcome),
      /** round((services + products + other) / (openMinutes / 60)), or 0. */
      salesPerHourCents: roundedRatio(soldCents(scope) * 60, open),
      /** Live sales with at least one product / live sales, or 0. */
      productAttachRate: ratio(scope.salesWithProduct, scope.sales),
    },
    /** leaderboard[0] when its sales are above $0, else null; always the whole shop's. */
    topBarber:
      first && first.salesCents > 0
        ? { barberId: first.barberId, name: first.name, salesCents: first.salesCents, servicesCount: first.servicesCount, productsCount: first.productsCount }
        : null,
    leaderboard,
    services: [...services.values()].sort((a, b) => b.salesCents - a.salesCents || b.count - a.count || byName(a.name, b.name)),
    products: [...products.values()].sort((a, b) => b.salesCents - a.salesCents || b.quantity - a.quantity || byName(a.name, b.name)),
    series: input.periods.map((period, i) => seriesJSON(period.label, perPeriod[i] ?? emptyTally())),
    barbers: team.map((b) => ({ barberId: b.id, name: b.name })),
  };
}

export type Analytics = ReturnType<typeof computeAnalytics>;

// The database's part: everything added up in one snapshot, with indexed range scans.

interface Range {
  /** The instants each period starts at, with the previous period's start first. */
  edges: string[];
  previousStart: Date;
  start: Date;
  end: Date;
  /** Where today ends: appointments starting before it count towards bookedMinutes. */
  todayEnd: Date;
  now: Date;
}

interface MoneyRow {
  bucket: number;
  barber_id: string | null;
  item_id: string | null;
  name: string | null;
  count: number;
  cents: number;
}

/**
 * Money facts for the previous period and each series period, in one scan per kind:
 * `width_bucket` puts each row in its period by the shop-local day boundaries in `edges`
 * (bucket 1 is the previous period, bucket 2 the first series period, and so on).
 */
async function loadMoney(db: Queryable, range: Range): Promise<MoneyFact[]> {
  const values = [range.edges, range.previousStart, range.end];
  const items = await db.query<MoneyRow & { kind: 'service' | 'product' | 'custom' }>(
    `SELECT width_bucket(s.sold_at, $1::timestamptz[]) AS bucket, s.barber_id, i.kind,
            COALESCE(i.service_id, i.product_id::text) AS item_id,
            COALESCE(max(p.name), min(i.name)) AS name,
            sum(i.quantity)::int AS count, sum(i.total_cents)::int AS cents
       FROM sales s
       JOIN sale_items i ON i.sale_id = s.id
       LEFT JOIN products p ON p.id = i.product_id
      WHERE s.voided_at IS NULL AND s.sold_at >= $2 AND s.sold_at < $3
      GROUP BY 1, 2, 3, 4, CASE WHEN i.kind = 'product' AND i.product_id IS NULL THEN i.name END`,
    values,
  );
  // Whether an appointment has a live sale is read from `sales` itself (its unique index on live
  // sales per appointment), not from the copy on the appointment row.
  const visits = await db.query<MoneyRow>(
    `SELECT width_bucket(a.start_at, $1::timestamptz[]) AS bucket, a.barber_id, a.service_id AS item_id,
            min(a.service_name) AS name, count(*)::int AS count, sum(a.price_cents)::int AS cents
       FROM appointments a
      WHERE a.status = 'completed' AND a.start_at >= $2 AND a.start_at < $3
        AND NOT EXISTS (SELECT 1 FROM sales s WHERE s.appointment_id = a.id AND s.voided_at IS NULL)
      GROUP BY 1, 2, 3`,
    values,
  );
  // A fee counts the day Stripe charged it: off-session charges succeed or fail as they're made,
  // and payments.created_at is when Stripe made the charge (the day Payments lists it), even when
  // the server only found out later.
  const fees = await db.query<MoneyRow>(
    `SELECT width_bucket(p.created_at, $1::timestamptz[]) AS bucket, a.barber_id, NULL AS item_id, NULL AS name,
            count(*)::int AS count, sum(p.amount_cents)::int AS cents
       FROM payments p
       LEFT JOIN appointments a ON a.id = p.appointment_id
      WHERE p.kind IN ('no_show_fee', 'late_cancel_fee') AND p.status = 'succeeded'
        AND p.created_at >= $2 AND p.created_at < $3
      GROUP BY 1, 2`,
    values,
  );
  const fact = (row: MoneyRow, kind: MoneyFact['kind'], visit: boolean): MoneyFact => ({
    period: row.bucket - 2,
    barberId: row.barber_id,
    kind,
    visit,
    itemId: row.item_id,
    name: row.name ?? '',
    count: row.count,
    cents: row.cents,
  });
  return [
    ...items.rows.map((row) => fact(row, row.kind, false)),
    ...visits.rows.map((row) => fact(row, 'service', true)),
    ...fees.rows.map((row) => fact(row, 'fee', false)),
  ];
}

async function loadSaleCounts(db: Queryable, range: Range): Promise<SaleCountFact[]> {
  const { rows } = await db.query<{ barber_id: string; sales: number; without_appointment: number; with_product: number }>(
    `SELECT s.barber_id,
            count(*)::int AS sales,
            count(*) FILTER (WHERE s.appointment_id IS NULL)::int AS without_appointment,
            count(*) FILTER (WHERE EXISTS (SELECT 1 FROM sale_items i WHERE i.sale_id = s.id AND i.kind = 'product'))::int AS with_product
       FROM sales s
      WHERE s.voided_at IS NULL AND s.sold_at >= $1 AND s.sold_at < $2
      GROUP BY s.barber_id`,
    [range.start, range.end],
  );
  return rows.map((r) => ({ barberId: r.barber_id, sales: r.sales, withoutAppointment: r.without_appointment, withProduct: r.with_product }));
}

type LateCancelRow = Pick<
  AppointmentRow,
  'barber_id' | 'status' | 'cancelled_by' | 'start_at' | 'saved_card_id' | 'no_show_fee_cents' | 'late_cancel_window_minutes' | 'customer_cancelled_at'
>;

/**
 * Appointments by the day they start: `booked` (still booked), `completed`, `noShows`,
 * `cancelled` (by anyone), `lateCancellations` (cancelled by the client in the app less than
 * that booking's agreed late-cancellation window before the start: the same rule as the fee,
 * feecase.ts `cancelledLate`; a booking whose policy had no window is never late) and
 * `upcoming` (booked, starting after now). `bookedMinutes`: the length of booked and completed
 * appointments that start on days up to today.
 */
async function loadAppointments(db: Queryable, range: Range): Promise<AppointmentFact[]> {
  const { rows } = await db.query<{
    barber_id: string;
    booked: number;
    completed: number;
    no_shows: number;
    cancelled: number;
    upcoming: number;
    booked_minutes: number;
  }>(
    `SELECT a.barber_id,
            count(*) FILTER (WHERE a.status = 'booked')::int AS booked,
            count(*) FILTER (WHERE a.status = 'completed')::int AS completed,
            count(*) FILTER (WHERE a.status = 'no_show')::int AS no_shows,
            count(*) FILTER (WHERE a.status = 'cancelled')::int AS cancelled,
            count(*) FILTER (WHERE a.status = 'booked' AND a.start_at > $3)::int AS upcoming,
            COALESCE(sum(round(extract(epoch FROM a.end_at - a.start_at) / 60))
                       FILTER (WHERE a.status IN ('booked', 'completed') AND a.start_at < $4), 0)::int AS booked_minutes
       FROM appointments a
      WHERE a.start_at >= $1 AND a.start_at < $2
      GROUP BY a.barber_id`,
    [range.start, range.end, range.now, range.todayEnd],
  );
  const { rows: cancelled } = await db.query<LateCancelRow>(
    `SELECT a.barber_id, a.status, a.cancelled_by, a.start_at, a.saved_card_id, a.no_show_fee_cents,
            a.late_cancel_window_minutes, a.customer_cancelled_at
       FROM appointments a
      WHERE a.start_at >= $1 AND a.start_at < $2
        AND a.status = 'cancelled' AND a.cancelled_by = 'customer'
        AND a.late_cancel_window_minutes IS NOT NULL AND a.customer_cancelled_at IS NOT NULL`,
    [range.start, range.end],
  );
  const late = new Map<string, number>();
  for (const row of cancelled) if (cancelledLate(row)) late.set(row.barber_id, (late.get(row.barber_id) ?? 0) + 1);
  return rows.map((r) => ({
    barberId: r.barber_id,
    booked: r.booked,
    completed: r.completed,
    noShows: r.no_shows,
    cancelled: r.cancelled,
    lateCancellations: late.get(r.barber_id) ?? 0,
    upcoming: r.upcoming,
    bookedMinutes: r.booked_minutes,
  }));
}

async function loadTimeOff(db: Queryable, range: Range): Promise<Busy[]> {
  const { rows } = await db.query<{ barber_id: string | null; start_at: Date; end_at: Date }>(
    `SELECT barber_id, start_at, end_at FROM time_off
      WHERE tstzrange(start_at, end_at, '[)') && tstzrange($1, $2, '[)')`,
    [range.start, range.end],
  );
  return rows.map((r) => ({ barberId: r.barber_id, start: r.start_at, end: r.end_at }));
}

// GET /api/owner/analytics?from=YYYY-MM-DD&to=YYYY-MM-DD[&barberId=…]

const analyticsQuery = z.object({
  from: calendarDate.optional(),
  to: calendarDate.optional(),
  barberId: shortId.optional(),
});

export async function getAnalytics(ctx: Context): Promise<Response> {
  await requireOwner(ctx);
  const { catalog } = ctx.deps;
  const zone = catalog.timeZone;
  const now = ctx.deps.now();
  const today = localDate(now, zone);
  const query = parse(analyticsQuery, Object.fromEntries(ctx.url.searchParams));
  const from = query.from ?? today;
  const to = query.to ?? today;
  if (Math.abs(daysBetween(today, from)) > MAX_DAYS_FROM_TODAY || Math.abs(daysBetween(today, to)) > MAX_DAYS_FROM_TODAY) {
    throw new ApiError('invalid_request', 'Pick dates within 10 years of today.');
  }
  const span = daysBetween(from, to);
  if (span < 0) throw new ApiError('invalid_request', 'to must be on or after from.');
  if (span >= MAX_ANALYTICS_DAYS) throw new ApiError('invalid_request', `Ask for at most ${MAX_ANALYTICS_DAYS} days at a time.`);

  const { granularity, periods } = seriesPeriods(from, to);
  const previous = previousPeriod(from, to);
  const range: Range = {
    edges: [previous.from, ...periods.map((p) => p.from)].map((date) => formatInstant(dayBounds(date, zone).start)),
    previousStart: dayBounds(previous.from, zone).start,
    start: dayBounds(from, zone).start,
    end: dayBounds(to, zone).end,
    todayEnd: dayBounds(today, zone).end,
    now,
  };
  const dates = Array.from({ length: span + 1 }, (_, i) => addDays(from, i));

  const input = await ctx.deps.db.transaction(async (tx): Promise<AnalyticsInput> => {
    // Every number from the same moment, even while checkouts are coming in.
    await tx.query('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY');
    const { rows: barbers } = await tx.query<{ id: string; name: string; active: boolean }>('SELECT id, name, active FROM barbers ORDER BY sort, id');
    const barberId = query.barberId ?? null;
    if (barberId !== null && !barbers.some((b) => b.id === barberId)) throw new ApiError('invalid_request', "That barber isn't on the team.");
    const money = await loadMoney(tx, range);
    const sales = await loadSaleCounts(tx, range);
    const appointments = await loadAppointments(tx, range);
    const timeOff = await loadTimeOff(tx, range);
    const open = new Map(barbers.filter((b) => b.active).map((b) => [b.id, openMinutes(catalog, b.id, dates, today, timeOff)]));
    return {
      from,
      to,
      barberId,
      timeZone: zone,
      generatedAt: now,
      granularity,
      periods,
      previous,
      barbers,
      serviceName: (id) => catalog.service(id)?.name,
      money,
      sales,
      appointments,
      openMinutes: open,
    };
  });
  return json(computeAnalytics(input));
}
