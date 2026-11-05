// The analytics numbers, worked out in the browser for the demo exactly as the shop's
// server works them out: a line-for-line port of the pure part of
// server/src/analytics.ts (seriesPeriods, previousPeriod, roundedRatio, ratio,
// rankLeaderboard, computeAnalytics), with the definitions of docs/analytics.md. The
// demo gathers the facts from its own appointments and sales (./facts.ts) and this
// file turns them into the API's JSON. tools/analytics-parity.test.ts checks that it
// answers exactly like the server's own code for the same facts.
//
// No imports at run time, so that test can load it next to the server's code.

/** The longest range, in shop-local days (from and to included). */
export const MAX_ANALYTICS_DAYS = 366;
/** Ranges up to this many days get one series entry per day; longer ones, one per month. */
export const MAX_DAILY_SERIES_DAYS = 62;

export type Granularity = 'day' | 'month';

/** One series entry's days: a single day, or the part of a month inside the range. */
export interface Period {
  /** "2026-11-01" for a day, "2026-11" for a month. */
  label: string;
  from: string;
  to: string;
}

function utcDay(date: string): number {
  const [y, m, d] = date.split('-').map(Number) as [number, number, number];
  return Date.UTC(y, m - 1, d);
}

function formatDay(ms: number): string {
  const day = new Date(ms);
  return `${String(day.getUTCFullYear()).padStart(4, '0')}-${String(day.getUTCMonth() + 1).padStart(2, '0')}-${String(day.getUTCDate()).padStart(2, '0')}`;
}

/** The day `days` after `date` (calendar math, no time zones). */
export function addDays(date: string, days: number): string {
  return formatDay(utcDay(date) + days * 86_400_000);
}

/** Whole days from `from` to `to`. */
export function daysBetween(from: string, to: string): number {
  return Math.round((utcDay(to) - utcDay(from)) / 86_400_000);
}

/** "2026-11-02T18:00:00Z": the contract's form, without fractions of a second. */
export function formatInstant(instant: Date): string {
  return new Date(Math.floor(instant.getTime() / 1000) * 1000).toISOString().replace(/\.\d{3}Z$/, 'Z');
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
