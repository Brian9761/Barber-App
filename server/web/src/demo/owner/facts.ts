// The facts the demo's analytics are built from, gathered from its own appointments and
// sales the way the shop's server gathers them from its database (server/src/analytics.ts
// loadMoney, loadSaleCounts, loadAppointments and openMinutes), then turned into the API's
// JSON by the same definitions (./analytics.ts, docs/analytics.md):
//
// - live sales count the day they were sold (the shop's day), for the sale's barber; their
//   service, product and custom items are services, products and other;
// - a completed appointment with no live sale counts as its service, at its booked price,
//   the day it started;
// - a fee counts the day it was charged, for the appointment's barber;
// - appointments count the day they start; open hours are each barber's opening hours on
//   days up to today (the demo has no time off).

import type { Catalog } from '../../api/types';
import { cancelledLate } from '../../lib/lateCancel';
import { addDays, clockMinutes, localDate, weekdayOf, zonedInstant } from '../../lib/shopTime';
import type { Analytics, AnalyticsQuery, Product } from '../../business/types';
import {
  computeAnalytics,
  previousPeriod,
  seriesPeriods,
  type AnalyticsInput,
  type AppointmentFact,
  type MoneyFact,
  type SaleCountFact,
} from './analytics';
import type { DayData } from './samples';

/** How many days before the range a fee's appointment may have been (fees are charged after the visit). */
const FEE_LOOKBACK_DAYS = 14;

/**
 * Each barber's open minutes over `dates`: the shop's hours on each day up to and including
 * today (today counts all of its hours), nothing for days after today or days it's closed.
 */
export function openMinutes(catalog: Catalog, dates: readonly string[], today: string): number {
  let total = 0;
  for (const date of dates) {
    if (date > today) continue;
    const hours = catalog.hours[String(weekdayOf(date))];
    if (!hours) continue;
    const opens = zonedInstant(date, clockMinutes(hours.opens), catalog.timeZone)?.getTime();
    const closes = zonedInstant(date, clockMinutes(hours.closes), catalog.timeZone)?.getTime();
    if (opens === undefined || closes === undefined || closes <= opens) continue;
    total += closes - opens;
  }
  return Math.round(total / 60_000);
}

export interface FactsSource {
  catalog: Catalog;
  /** A shop day's appointments and sales. */
  day(date: string): DayData;
  /** The products as they are now (a product sold under another name shows its name now). */
  products: readonly Product[];
  now: Date;
}

/** The analytics JSON for `query`, from the demo's own data. */
export function demoAnalytics(source: FactsSource, query: AnalyticsQuery): Analytics {
  const { catalog, now } = source;
  const zone = catalog.timeZone;
  const today = localDate(now, zone);
  const { granularity, periods } = seriesPeriods(query.from, query.to);
  const previous = previousPeriod(query.from, query.to);

  /** The series period a shop day belongs to: -1 for the previous period, null outside both. */
  const periodOf = (date: string): number | null => {
    if (date < previous.from || date > query.to) return null;
    if (date < query.from) return -1;
    const index = periods.findIndex((p) => date >= p.from && date <= p.to);
    return index === -1 ? null : index;
  };

  const productNames = new Map(source.products.map((p) => [p.id, p.name]));
  const money: MoneyFact[] = [];
  const saleCounts = new Map<string, SaleCountFact>();
  const appointmentFacts = new Map<string, AppointmentFact>();
  const appointmentFact = (barberId: string): AppointmentFact => {
    let fact = appointmentFacts.get(barberId);
    if (!fact) {
      fact = { barberId, booked: 0, completed: 0, noShows: 0, cancelled: 0, lateCancellations: 0, upcoming: 0, bookedMinutes: 0 };
      appointmentFacts.set(barberId, fact);
    }
    return fact;
  };
  const todayEnd = zonedInstant(addDays(today, 1), 0, zone)?.getTime() ?? Number.POSITIVE_INFINITY;

  for (let date = addDays(previous.from, -FEE_LOOKBACK_DAYS); date <= query.to; date = addDays(date, 1)) {
    const { appointments, sales } = source.day(date);
    const period = periodOf(date);

    for (const sale of sales) {
      if (sale.voidedAt !== null) continue;
      const soldOn = localDate(new Date(sale.soldAt), zone);
      const salePeriod = periodOf(soldOn);
      if (salePeriod === null) continue;
      for (const item of sale.items) {
        // A product that still exists shows its name now; a deleted one keeps the name it was sold under.
        const exists = item.productId !== null && productNames.has(item.productId);
        money.push({
          period: salePeriod,
          barberId: sale.barberId,
          kind: item.kind,
          visit: false,
          itemId: item.kind === 'service' ? item.serviceId : item.kind === 'product' ? (exists ? item.productId : null) : null,
          name: item.kind === 'product' && exists ? (productNames.get(item.productId!) ?? item.name) : item.name,
          count: item.quantity,
          cents: item.totalCents,
        });
      }
      if (salePeriod >= 0) {
        const counts = saleCounts.get(sale.barberId) ?? { barberId: sale.barberId, sales: 0, withoutAppointment: 0, withProduct: 0 };
        counts.sales += 1;
        if (sale.appointmentId === null) counts.withoutAppointment += 1;
        if (sale.items.some((i) => i.kind === 'product')) counts.withProduct += 1;
        saleCounts.set(sale.barberId, counts);
      }
    }

    for (const appointment of appointments) {
      // Fees count the day Stripe charged them.
      const fee = appointment.noShowFee;
      if (fee?.status === 'charged') {
        const chargedOn = localDate(new Date(fee.chargedAt ?? appointment.start), zone);
        const feePeriod = periodOf(chargedOn);
        if (feePeriod !== null) {
          money.push({ period: feePeriod, barberId: appointment.barberId, kind: 'fee', visit: false, itemId: null, name: '', count: 1, cents: fee.amountCents });
        }
      }
      if (period === null) continue;
      // Marked Done without a checkout: the booked service at its booked price.
      if (appointment.status === 'completed' && appointment.sale === null) {
        money.push({
          period,
          barberId: appointment.barberId,
          kind: 'service',
          visit: true,
          itemId: appointment.serviceId,
          name: appointment.serviceName,
          count: 1,
          cents: appointment.priceCents,
        });
      }
      if (period < 0) continue;
      const fact = appointmentFact(appointment.barberId);
      const start = Date.parse(appointment.start);
      if (appointment.status === 'booked') fact.booked += 1;
      if (appointment.status === 'completed') fact.completed += 1;
      if (appointment.status === 'noShow') fact.noShows += 1;
      if (appointment.status === 'cancelled') fact.cancelled += 1;
      if (appointment.status === 'booked' && start > now.getTime()) fact.upcoming += 1;
      if ((appointment.status === 'booked' || appointment.status === 'completed') && start < todayEnd) {
        fact.bookedMinutes += Math.round((Date.parse(appointment.end) - start) / 60_000);
      }
      if (
        appointment.status === 'cancelled' &&
        appointment.cancelledBy === 'customer' &&
        fee &&
        fee.lateCancelWindowMinutes !== null &&
        fee.customerCancelledAt !== null &&
        cancelledLate(new Date(start), new Date(fee.customerCancelledAt), fee.lateCancelWindowMinutes)
      ) {
        fact.lateCancellations += 1;
      }
    }
  }

  const dates: string[] = [];
  for (let date = query.from; date <= query.to; date = addDays(date, 1)) dates.push(date);
  const open = openMinutes(catalog, dates, today);

  const input: AnalyticsInput = {
    from: query.from,
    to: query.to,
    barberId: query.barberId,
    timeZone: zone,
    generatedAt: now,
    granularity,
    periods,
    previous,
    barbers: catalog.barbers.map((b) => ({ id: b.id, name: b.name, active: true })),
    serviceName: (id) => catalog.services.find((s) => s.id === id)?.name,
    money,
    sales: [...saleCounts.values()],
    appointments: [...appointmentFacts.values()],
    openMinutes: new Map(catalog.barbers.map((b) => [b.id, open])),
  };
  return computeAnalytics(input);
}
