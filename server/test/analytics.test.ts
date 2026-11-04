import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { openMinutes, previousPeriod, rankLeaderboard, ratio, roundedRatio, seriesPeriods } from '../src/analytics.js';
import { Catalog, loadCatalog } from '../src/catalog.js';
import type { Db, Queryable } from '../src/db.js';
import { newManageToken } from '../src/auth.js';
import { RESPONSES } from './helpers/contract.js';
import { protectionOn, useHarness } from './helpers/harness.js';
import { OFFERING, seedWeek, sendWebhook, WEBHOOK_SECRET } from './helpers/week.js';

// GET /api/owner/analytics against the week in test/helpers/week.ts, with every expected
// number worked out by hand below. Times are the shop's (Pacific). "Now" is Saturday Nov 7,
// 3:00 PM. Opening hours: Sunday 10–6 (480 minutes), Monday to Saturday 10–7 (540).
//
// The week before (Oct 25–31), the `previous` period:
//   P1 Thu Oct 29  Carlos walk-in, cash: haircut $45
//   P2 Fri Oct 30  Julian's haircut marked done, never checked out: $35 (booked price)
//   A0 Sat Oct 31  Julian's 6 PM haircut done; checked out Sunday (S0), so it counts then
//   P3 Sat Oct 31  11 PM PDT (07:00 Nov 1 in UTC): Izzy walk-in, cash: haircut $40
//   → previous = $45 + $35 + $40 = $120.
//
// The week (Nov 1–7):
//   Sun Nov 1 (25 hours: clocks go back at 2 AM)
//     S0 Julian, cash, A0's haircut at its booked price          $35
//     S1 Izzy, cash, A1: haircut $40 + Matte pomade $18           $58
//     A2 Flowxbori's 12 PM haircut marked done, no checkout       $35 (service, counted at its price)
//     S2 11:30 PM (07:30 Nov 2 UTC): Carlos, walk-in "Late client": gift card $25 + 2 × Beard oil $15 = $55
//   Mon Nov 2
//     S3 Carlos, card (Tap to Pay, …/complete), A3: haircut $45 + Matte pomade $18 = $63
//     A4 Cristian's haircut & beard: no-show (shop booking, no card, no fee)
//     S4 Julian, other (Zelle), A5: haircut $35
//   Tue Nov 3 (Julian off 1–3 PM)
//     C1 Fay (online, card on file) no-show at Flowxbori's 10 AM: fee charged $35 (F1)
//     S5 Izzy, cash, A6: VIP $80 + Sea salt spray at $12 (no list price) = $92
//     A7 Julian's 3 PM haircut marked done, no checkout              $35
//   Wed Nov 4: the shop is closed all day (shop-wide time off; Cristian's own 2–5 PM block overlaps it)
//   Thu Nov 5 (Carlos off 8–11 AM: 10–11 counts)
//     C3 Jay cancels Julian's 3 PM at 11 AM: cancelled, not late
//     S6 Carlos, cash, A8: haircut & beard $60, voided 2 minutes later (doesn't count)
//     S7 Carlos, cash, A8: haircut & beard $60 + Old gel $10 = $70 (Old gel is deleted on Friday)
//     A9 Cristian's noon haircut marked done, no checkout             $35
//     C2 Ivy cancels Izzy's 2 PM at 1:30 PM: a late cancellation (window 1 hour)
//   Fri Nov 6 (Flowxbori off from 5 PM to Saturday noon)
//     F2 9:30 AM: Ivy's late-cancellation fee charged $40 (Izzy's; counts on Friday, the day it was charged)
//     S8 Flowxbori, card (Stripe's webhook only), A10: haircut $40 + 2 × Matte pomade = $76
//     A11 Julian's 4 PM haircut & beard: no-show
//     S9 9:45 PM (05:45 Nov 7 UTC): Izzy, walk-in: military haircut $25
//   Sat Nov 7 (today)
//     S10 Cristian, cash, A12: haircut $35
//     A13 Izzy 4 PM booked (upcoming), A14 Carlos noon still booked (never marked), A15 Julian 1 PM cancelled by the shop
//   Sun Nov 8: A16 Izzy 10 AM booked (after the range)
//
// Services: S0 35 + S1 40 + S3 45 + S4 35 + S5 80 + S7 60 + S8 40 + S9 25 + S10 35 + A2 35 + A7 35 + A9 35 = $500 (12)
// Products: S1 18 + S2 30 (2) + S3 18 + S5 12 + S7 10 + S8 36 (2) = $124 (8). Other: $25. Fees: 35 + 40 = $75.
// Sales: 500 + 124 + 25 + 75 = $724.
// Checkouts: 10 live sales + 3 completed without one = 13. Clients served: 10 completed + 2 walk-in sales = 12.
// Average ticket: round($649 / 13) = $49.92. Product attach rate: 6 of 10 sales.
// Open minutes, per barber: 480 + 6 × 540 = 3720, less Wednesday (540) for everyone, and
//   Izzy 3180; Carlos − 60 = 3120; Flowxbori − 120 − 120 = 2940; Cristian 3180 (his block is inside the closure);
//   Julian − 120 = 3060 → 15,480 for the shop.
// Booked minutes (booked or completed, starting today or before): A1 60, A2 45, A3 45, A5 45, A6 75, A7 45,
//   A8 60, A9 45, A10 60, A12 45, A13 60, A14 45 = 630.
// Sales per hour: round($649 × 60 / 15,480) = round(251.55¢) = 252¢.

const h = useHarness({ now: '2026-11-02T17:00:00Z' });
const owner = { owner: true } as const;
const analytics = (query = '') => h.call('GET', `/api/owner/analytics${query}`, owner);

const zeroDay = (date: string) => ({
  date,
  salesCents: 0,
  servicesCents: 0,
  productsCents: 0,
  otherCents: 0,
  feesCents: 0,
  servicesCount: 0,
  productsCount: 0,
});

const SHOP_LEADERBOARD = [
  {
    rank: 1,
    barberId: 'israel-flores',
    name: 'Izzy',
    salesCents: 21500,
    servicesCents: 14500,
    productsCents: 3000,
    servicesCount: 3,
    productsCount: 2,
    clientsServed: 3,
    averageTicketCents: 5833,
  },
  {
    rank: 2,
    barberId: 'carlos-rafael',
    name: 'Carlos',
    salesCents: 18800,
    servicesCents: 10500,
    productsCents: 5800,
    servicesCount: 2,
    productsCount: 4,
    clientsServed: 3,
    averageTicketCents: 6267,
  },
  {
    rank: 3,
    barberId: 'flowxbori',
    name: 'Flowxbori',
    salesCents: 14600,
    servicesCents: 7500,
    productsCents: 3600,
    servicesCount: 2,
    productsCount: 2,
    clientsServed: 2,
    averageTicketCents: 5550,
  },
  {
    rank: 4,
    barberId: 'julian-ramos',
    name: 'Julian',
    salesCents: 10500,
    servicesCents: 10500,
    productsCents: 0,
    servicesCount: 3,
    productsCount: 0,
    clientsServed: 2,
    averageTicketCents: 3500,
  },
  {
    rank: 5,
    barberId: 'cristian-ceja',
    name: 'Cristian',
    salesCents: 7000,
    servicesCents: 7000,
    productsCents: 0,
    servicesCount: 2,
    productsCount: 0,
    clientsServed: 2,
    averageTicketCents: 3500,
  },
];

const TEAM = [
  { barberId: 'israel-flores', name: 'Izzy' },
  { barberId: 'carlos-rafael', name: 'Carlos' },
  { barberId: 'flowxbori', name: 'Flowxbori' },
  { barberId: 'cristian-ceja', name: 'Cristian' },
  { barberId: 'julian-ramos', name: 'Julian' },
];

describe('the definitions, piece by piece', () => {
  it('series: a day each up to 62 days, then a month each, every one listed', () => {
    expect(seriesPeriods('2026-11-01', '2026-11-01')).toEqual({ granularity: 'day', periods: [{ label: '2026-11-01', from: '2026-11-01', to: '2026-11-01' }] });
    const sixtyTwo = seriesPeriods('2026-09-07', '2026-11-07');
    expect(sixtyTwo.granularity).toBe('day');
    expect(sixtyTwo.periods).toHaveLength(62);
    expect(sixtyTwo.periods.at(-1)).toEqual({ label: '2026-11-07', from: '2026-11-07', to: '2026-11-07' });
    expect(seriesPeriods('2026-09-06', '2026-11-07')).toEqual({
      granularity: 'month',
      periods: [
        { label: '2026-09', from: '2026-09-06', to: '2026-09-30' },
        { label: '2026-10', from: '2026-10-01', to: '2026-10-31' },
        { label: '2026-11', from: '2026-11-01', to: '2026-11-07' },
      ],
    });
    // Across a new year, a whole year and a day.
    const year = seriesPeriods('2025-11-08', '2026-11-08');
    expect(year.periods.map((p) => p.label)).toEqual([
      '2025-11', '2025-12', '2026-01', '2026-02', '2026-03', '2026-04', '2026-05', '2026-06', '2026-07', '2026-08', '2026-09', '2026-10', '2026-11',
    ]);
    expect(year.periods[1]).toEqual({ label: '2025-12', from: '2025-12-01', to: '2025-12-31' });
  });

  it('previous: as many days, right before from', () => {
    expect(previousPeriod('2026-11-01', '2026-11-07')).toEqual({ from: '2026-10-25', to: '2026-10-31' });
    expect(previousPeriod('2026-11-04', '2026-11-04')).toEqual({ from: '2026-11-03', to: '2026-11-03' });
    expect(previousPeriod('2026-03-01', '2026-03-31')).toEqual({ from: '2026-01-29', to: '2026-02-28' });
  });

  it('averages and per-hour figures round halves up, and dividing by nothing is 0', () => {
    expect(roundedRatio(5, 2)).toBe(3);
    expect(roundedRatio(7, 2)).toBe(4);
    expect(roundedRatio(64900, 13)).toBe(4992);
    expect(roundedRatio(17500, 3)).toBe(5833);
    expect(roundedRatio(18800, 3)).toBe(6267);
    expect(roundedRatio(1, 3)).toBe(0);
    expect(roundedRatio(500, 0)).toBe(0);
    expect(ratio(3, 4)).toBe(0.75);
    expect(ratio(3, 0)).toBe(0);
  });

  it('leaderboard: by sales, then services, then name; ties share a rank and the next one skips', () => {
    const entry = (name: string, salesCents: number, servicesCount: number) => ({ name, salesCents, servicesCount });
    expect(
      rankLeaderboard([entry('Julian', 0, 0), entry('Carlos', 3500, 1), entry('Izzy', 3500, 2), entry('Cristian', 3500, 1), entry('Flowxbori', 0, 0)]).map(
        (e) => [e.rank, e.name],
      ),
    ).toEqual([
      [1, 'Izzy'],
      [2, 'Carlos'],
      [2, 'Cristian'],
      [4, 'Flowxbori'],
      [4, 'Julian'],
    ]);
  });

  it('open minutes: the day’s hours less overlapping time off (counted once), nothing for closed or future days', () => {
    const catalog = loadCatalog();
    const off = (barberId: string | null, start: string, end: string) => ({ barberId, start: new Date(start), end: new Date(end) });
    const monday = ['2026-11-02'];
    expect(openMinutes(catalog, 'flowxbori', monday, '2026-11-02', [])).toBe(540);
    // 9–11 AM: only 10–11 is inside the hours.
    expect(openMinutes(catalog, 'flowxbori', monday, '2026-11-02', [off('flowxbori', '2026-11-02T17:00:00Z', '2026-11-02T19:00:00Z')])).toBe(480);
    // His noon–2 PM and the shop's 1–3 PM overlap: noon–3 PM is off, once.
    const both = [off('flowxbori', '2026-11-02T20:00:00Z', '2026-11-02T22:00:00Z'), off(null, '2026-11-02T21:00:00Z', '2026-11-02T23:00:00Z')];
    expect(openMinutes(catalog, 'flowxbori', monday, '2026-11-02', both)).toBe(360);
    // Someone else's time off doesn't count; the shop's does.
    expect(openMinutes(catalog, 'julian-ramos', monday, '2026-11-02', both)).toBe(420);
    // A block from Monday 6 PM to Tuesday 11 AM takes an hour from each day.
    const overnight = [off('flowxbori', '2026-11-03T02:00:00Z', '2026-11-03T19:00:00Z')];
    expect(openMinutes(catalog, 'flowxbori', ['2026-11-02', '2026-11-03'], '2026-11-03', overnight)).toBe(480 + 480);
    // Tuesday hasn't happened yet: 0. Today counts all of its hours.
    expect(openMinutes(catalog, 'flowxbori', ['2026-11-02', '2026-11-03'], '2026-11-02', [])).toBe(540);
    // Both 2026 clock changes fall on Sundays (open 10–6): still 8 hours.
    expect(openMinutes(catalog, 'flowxbori', ['2026-03-08'], '2026-03-08', [])).toBe(480);
    expect(openMinutes(catalog, 'flowxbori', ['2026-11-01'], '2026-11-01', [])).toBe(480);
    // A day off from midnight to midnight, and a weekday the shop doesn't open.
    expect(openMinutes(catalog, 'flowxbori', monday, '2026-11-02', [off(null, '2026-11-02T08:00:00Z', '2026-11-03T08:00:00Z')])).toBe(0);
    // (The shop opens every day; a catalog whose hours leave Sunday out has it closed.)
    const closedSundays = new Catalog(JSON.parse(readFileSync(new URL('../data/catalog.json', import.meta.url), 'utf8')));
    closedSundays.hours = (day: number) => (day === 1 ? undefined : catalog.hours(day));
    expect(openMinutes(closedSundays, 'flowxbori', ['2026-11-01', '2026-11-02'], '2026-11-02', [])).toBe(540);
  });
});

describe('GET /api/owner/analytics for a week at the shop', () => {
  it('the whole shop: every definition, worked out by hand', async () => {
    await seedWeek(h);
    const res = await analytics('?from=2026-11-01&to=2026-11-07');
    expect(res.status, res.text).toBe(200);
    expect(res.headers.get('cache-control')).toBe('no-store');
    expect(RESPONSES.analytics.safeParse(res.body).success).toBe(true);
    expect(res.body).toEqual({
      from: '2026-11-01',
      to: '2026-11-07',
      barberId: null,
      timeZone: 'America/Los_Angeles',
      generatedAt: '2026-11-07T23:00:00Z',
      granularity: 'day',
      totals: {
        salesCents: 72400,
        servicesCents: 50000,
        productsCents: 12400,
        otherCents: 2500,
        feesCents: 7500,
        servicesCount: 12,
        productsCount: 8,
        clientsServed: 12,
        checkouts: 13,
        averageTicketCents: 4992,
      },
      previous: { from: '2026-10-25', to: '2026-10-31', salesCents: 12000 },
      productivity: {
        openMinutes: 15480,
        bookedMinutes: 630,
        chairTimeBooked: 630 / 15480,
        appointments: { booked: 2, completed: 10, noShows: 3, cancelled: 3, lateCancellations: 1, upcoming: 1 },
        completionRate: 10 / 13,
        noShowRate: 3 / 13,
        salesPerHourCents: 252,
        productAttachRate: 0.6,
      },
      topBarber: { barberId: 'israel-flores', name: 'Izzy', salesCents: 21500, servicesCount: 3, productsCount: 2 },
      leaderboard: SHOP_LEADERBOARD,
      services: [
        { serviceId: 'haircut', name: 'Haircut', count: 9, salesCents: 33500 },
        { serviceId: 'vip', name: 'VIP', count: 1, salesCents: 8000 },
        { serviceId: 'haircut-and-beard', name: 'Haircut & Beard', count: 1, salesCents: 6000 },
        { serviceId: 'military-haircut', name: 'Military Haircut', count: 1, salesCents: 2500 },
      ],
      products: [
        { productId: expect.any(String), name: 'Matte pomade', quantity: 4, salesCents: 7200 },
        { productId: expect.any(String), name: 'Beard oil', quantity: 2, salesCents: 3000 },
        { productId: expect.any(String), name: 'Sea salt spray', quantity: 1, salesCents: 1200 },
        // Deleted on Friday: listed by the name it was sold under.
        { productId: null, name: 'Old gel', quantity: 1, salesCents: 1000 },
      ],
      series: [
        { date: '2026-11-01', salesCents: 18300, servicesCents: 11000, productsCents: 4800, otherCents: 2500, feesCents: 0, servicesCount: 3, productsCount: 3 },
        { date: '2026-11-02', salesCents: 9800, servicesCents: 8000, productsCents: 1800, otherCents: 0, feesCents: 0, servicesCount: 2, productsCount: 1 },
        { date: '2026-11-03', salesCents: 16200, servicesCents: 11500, productsCents: 1200, otherCents: 0, feesCents: 3500, servicesCount: 2, productsCount: 1 },
        zeroDay('2026-11-04'),
        { date: '2026-11-05', salesCents: 10500, servicesCents: 9500, productsCents: 1000, otherCents: 0, feesCents: 0, servicesCount: 2, productsCount: 1 },
        { date: '2026-11-06', salesCents: 14100, servicesCents: 6500, productsCents: 3600, otherCents: 0, feesCents: 4000, servicesCount: 2, productsCount: 2 },
        { date: '2026-11-07', salesCents: 3500, servicesCents: 3500, productsCents: 0, otherCents: 0, feesCents: 0, servicesCount: 1, productsCount: 0 },
      ],
      barbers: TEAM,
    });
    // The pieces add up.
    const body = res.body;
    expect(body.series.reduce((sum: number, d: { salesCents: number }) => sum + d.salesCents, 0)).toBe(body.totals.salesCents);
    expect(body.leaderboard.reduce((sum: number, b: { salesCents: number }) => sum + b.salesCents, 0)).toBe(body.totals.salesCents);
    expect(body.services.reduce((sum: number, s: { salesCents: number }) => sum + s.salesCents, 0)).toBe(body.totals.servicesCents);
    expect(body.products.reduce((sum: number, p: { salesCents: number }) => sum + p.salesCents, 0)).toBe(body.totals.productsCents);
  });

  it('one barber: his numbers; the leaderboard and the top barber stay the whole shop’s', async () => {
    await seedWeek(h);
    const flow = await analytics('?from=2026-11-01&to=2026-11-07&barberId=flowxbori');
    expect(flow.status, flow.text).toBe(200);
    expect(RESPONSES['analytics-barber'].safeParse(flow.body).success).toBe(true);
    expect(flow.body).toMatchObject({
      barberId: 'flowxbori',
      totals: {
        salesCents: 14600,
        servicesCents: 7500,
        productsCents: 3600,
        otherCents: 0,
        feesCents: 3500,
        servicesCount: 2,
        productsCount: 2,
        clientsServed: 2,
        checkouts: 2,
        averageTicketCents: 5550,
      },
      previous: { from: '2026-10-25', to: '2026-10-31', salesCents: 0 },
      productivity: {
        openMinutes: 2940,
        bookedMinutes: 105,
        chairTimeBooked: 105 / 2940,
        appointments: { booked: 0, completed: 2, noShows: 1, cancelled: 0, lateCancellations: 0, upcoming: 0 },
        completionRate: 2 / 3,
        noShowRate: 1 / 3,
        salesPerHourCents: 227,
        productAttachRate: 1,
      },
      topBarber: { barberId: 'israel-flores', name: 'Izzy', salesCents: 21500, servicesCount: 3, productsCount: 2 },
      services: [{ serviceId: 'haircut', name: 'Haircut', count: 2, salesCents: 7500 }],
      products: [{ productId: expect.any(String), name: 'Matte pomade', quantity: 2, salesCents: 3600 }],
      series: [
        { ...zeroDay('2026-11-01'), salesCents: 3500, servicesCents: 3500, servicesCount: 1 },
        zeroDay('2026-11-02'),
        { ...zeroDay('2026-11-03'), salesCents: 3500, feesCents: 3500 },
        zeroDay('2026-11-04'),
        zeroDay('2026-11-05'),
        { ...zeroDay('2026-11-06'), salesCents: 7600, servicesCents: 4000, productsCents: 3600, servicesCount: 1, productsCount: 2 },
        zeroDay('2026-11-07'),
      ],
      barbers: TEAM,
    });
    expect(flow.body.leaderboard).toEqual(SHOP_LEADERBOARD);

    const izzy = (await analytics('?from=2026-11-01&to=2026-11-07&barberId=israel-flores')).body;
    expect(izzy.totals).toEqual({
      salesCents: 21500,
      servicesCents: 14500,
      productsCents: 3000,
      otherCents: 0,
      feesCents: 4000,
      servicesCount: 3,
      productsCount: 2,
      clientsServed: 3,
      checkouts: 3,
      averageTicketCents: 5833,
    });
    // His 11 PM sale on Saturday Oct 31 is in the week before.
    expect(izzy.previous).toEqual({ from: '2026-10-25', to: '2026-10-31', salesCents: 4000 });
    expect(izzy.productivity).toEqual({
      openMinutes: 3180,
      bookedMinutes: 195,
      chairTimeBooked: 195 / 3180,
      appointments: { booked: 1, completed: 2, noShows: 0, cancelled: 1, lateCancellations: 1, upcoming: 1 },
      completionRate: 1,
      noShowRate: 0,
      salesPerHourCents: 330,
      productAttachRate: 2 / 3,
    });
    expect(izzy.services).toEqual([
      { serviceId: 'vip', name: 'VIP', count: 1, salesCents: 8000 },
      { serviceId: 'haircut', name: 'Haircut', count: 1, salesCents: 4000 },
      { serviceId: 'military-haircut', name: 'Military Haircut', count: 1, salesCents: 2500 },
    ]);
    expect(izzy.products.map((p: { name: string; quantity: number }) => [p.name, p.quantity])).toEqual([
      ['Matte pomade', 1],
      ['Sea salt spray', 1],
    ]);
    // The late-cancellation fee lands on Friday, when it was charged, not Thursday.
    expect(izzy.series.map((d: { salesCents: number }) => d.salesCents)).toEqual([5800, 0, 9200, 0, 0, 6500, 0]);
    expect(izzy.series[5]).toMatchObject({ servicesCents: 2500, feesCents: 4000 });
  });

  it('late-evening sales count on the shop’s own day, across the clock change', async () => {
    await seedWeek(h);
    // Sunday Nov 1 has 25 hours. Carlos's 11:30 PM sale (07:30 on Nov 2 in UTC) is Sunday's;
    // Izzy's 11 PM sale the night before (07:00 on Nov 1 in UTC, still daylight time) is Saturday's.
    const sunday = (await analytics('?from=2026-11-01&to=2026-11-01')).body;
    expect(sunday.totals).toMatchObject({ salesCents: 18300, otherCents: 2500, productsCents: 4800, servicesCents: 11000, clientsServed: 3, checkouts: 4 });
    expect(sunday.previous).toEqual({ from: '2026-10-31', to: '2026-10-31', salesCents: 4000 });
    expect(sunday.productivity).toMatchObject({ openMinutes: 2400, bookedMinutes: 105, appointments: { completed: 2 } });
    const monday = (await analytics('?from=2026-11-02&to=2026-11-02')).body;
    expect(monday.totals.salesCents).toBe(9800);
    expect(monday.totals.otherCents).toBe(0);
    // Friday's 9:45 PM walk-in (05:45 Saturday in UTC) is Friday's.
    const friday = (await analytics('?from=2026-11-06&to=2026-11-06&barberId=israel-flores')).body;
    expect(friday.totals).toMatchObject({ servicesCents: 2500, feesCents: 4000, clientsServed: 1 });
    // The day's sales list agrees.
    const day = (await h.call('GET', '/api/owner/sales?date=2026-11-01', owner)).body;
    expect(day.totals).toEqual({ totalCents: 3500 + 5800 + 5500, count: 3 });
  });

  it('a closed day and a day with one sale: ranks are shared, the top barber needs sales', async () => {
    await seedWeek(h);
    const closed = (await analytics('?from=2026-11-04&to=2026-11-04')).body;
    expect(closed.totals).toEqual({
      salesCents: 0,
      servicesCents: 0,
      productsCents: 0,
      otherCents: 0,
      feesCents: 0,
      servicesCount: 0,
      productsCount: 0,
      clientsServed: 0,
      checkouts: 0,
      averageTicketCents: 0,
    });
    expect(closed.productivity).toEqual({
      openMinutes: 0,
      bookedMinutes: 0,
      chairTimeBooked: 0,
      appointments: { booked: 0, completed: 0, noShows: 0, cancelled: 0, lateCancellations: 0, upcoming: 0 },
      completionRate: 0,
      noShowRate: 0,
      salesPerHourCents: 0,
      productAttachRate: 0,
    });
    expect(closed.topBarber).toBeNull();
    expect(closed.leaderboard.map((b: { rank: number; name: string }) => [b.rank, b.name])).toEqual([
      [1, 'Carlos'],
      [1, 'Cristian'],
      [1, 'Flowxbori'],
      [1, 'Izzy'],
      [1, 'Julian'],
    ]);
    expect(closed.series).toEqual([zeroDay('2026-11-04')]);
    expect(closed.services).toEqual([]);
    expect(closed.products).toEqual([]);

    // Today (Saturday) so far: Cristian's $35, and the day's hours count in full.
    const today = (await analytics()).body;
    expect(today.from).toBe('2026-11-07');
    expect(today.to).toBe('2026-11-07');
    expect(today.leaderboard.map((b: { rank: number; name: string }) => [b.rank, b.name])).toEqual([
      [1, 'Cristian'],
      [2, 'Carlos'],
      [2, 'Flowxbori'],
      [2, 'Izzy'],
      [2, 'Julian'],
    ]);
    expect(today.topBarber).toEqual({ barberId: 'cristian-ceja', name: 'Cristian', salesCents: 3500, servicesCount: 1, productsCount: 0 });
    // Everyone 540, less Flowxbori's 10–noon.
    expect(today.productivity).toMatchObject({
      openMinutes: 5 * 540 - 120,
      bookedMinutes: 45 + 60 + 45,
      appointments: { booked: 2, completed: 1, cancelled: 1, upcoming: 1, noShows: 0, lateCancellations: 0 },
    });
  });

  it('days after today count no open hours; their bookings are upcoming', async () => {
    await seedWeek(h);
    const res = (await analytics('?from=2026-11-01&to=2026-11-08')).body;
    expect(res.previous).toEqual({ from: '2026-10-24', to: '2026-10-31', salesCents: 12000 });
    expect(res.totals.salesCents).toBe(72400);
    expect(res.productivity).toMatchObject({
      openMinutes: 15480,
      bookedMinutes: 630,
      appointments: { booked: 3, upcoming: 2, completed: 10, noShows: 3, cancelled: 3, lateCancellations: 1 },
    });
    expect(res.series).toHaveLength(8);
    expect(res.series[7]).toEqual(zeroDay('2026-11-08'));
  });

  it('a range over 62 days is shown by month; previous is the same number of days before', async () => {
    await seedWeek(h);
    const res = (await analytics('?from=2026-09-01&to=2026-11-30')).body;
    expect(res.granularity).toBe('month');
    expect(res.series).toEqual([
      zeroDay('2026-09'),
      { date: '2026-10', salesCents: 12000, servicesCents: 12000, productsCents: 0, otherCents: 0, feesCents: 0, servicesCount: 3, productsCount: 0 },
      { date: '2026-11', salesCents: 72400, servicesCents: 50000, productsCents: 12400, otherCents: 2500, feesCents: 7500, servicesCount: 12, productsCount: 8 },
    ]);
    expect(res.previous).toEqual({ from: '2026-06-02', to: '2026-08-31', salesCents: 0 });
    // Sep 1 – Nov 7: 9 Sundays (480) and 59 other days (540) for each of the five, less the week's time off (3120).
    expect(res.productivity.openMinutes).toBe(5 * (9 * 480 + 59 * 540) - 3120);
    expect(res.totals).toMatchObject({ salesCents: 84400, checkouts: 16, clientsServed: 16 });
    expect(res.productivity.appointments).toEqual({ booked: 3, completed: 12, noShows: 3, cancelled: 3, lateCancellations: 1, upcoming: 2 });
    expect(res.productivity.bookedMinutes).toBe(630 + 45 + 45);
  });

  it('a barber who left: still in the shop’s totals and on his own page, not on the leaderboard or open hours', async () => {
    await seedWeek(h);
    // The barbers table isn't reset between tests: put him back however this ends.
    await h.database.pool.query(`UPDATE barbers SET active = false WHERE id = 'julian-ramos'`);
    try {
      const shop = (await analytics('?from=2026-11-01&to=2026-11-07')).body;
      expect(shop.totals.salesCents).toBe(72400);
      expect(shop.leaderboard.map((b: { barberId: string }) => b.barberId)).toEqual(['israel-flores', 'carlos-rafael', 'flowxbori', 'cristian-ceja']);
      expect(shop.barbers.map((b: { barberId: string }) => b.barberId)).toEqual(['israel-flores', 'carlos-rafael', 'flowxbori', 'cristian-ceja']);
      expect(shop.productivity).toMatchObject({ openMinutes: 15480 - 3060, bookedMinutes: 630 });
      const julian = (await analytics('?from=2026-11-01&to=2026-11-07&barberId=julian-ramos')).body;
      expect(julian.totals).toMatchObject({ salesCents: 10500, servicesCount: 3, checkouts: 3, clientsServed: 2 });
      expect(julian.productivity).toMatchObject({ openMinutes: 0, bookedMinutes: 45 + 45, chairTimeBooked: 0, salesPerHourCents: 0 });
    } finally {
      await h.database.pool.query(`UPDATE barbers SET active = true WHERE id = 'julian-ramos'`);
    }
  });

  it('ranges at their limits, and plain errors', async () => {
    h.setNow('2026-11-07T23:00:00Z');
    const year = await analytics('?from=2025-11-08&to=2026-11-08');
    expect(year.status, year.text).toBe(200);
    expect(year.body.granularity).toBe('month');
    expect(year.body.series).toHaveLength(13);
    expect(year.body.previous).toEqual({ from: '2024-11-07', to: '2025-11-07', salesCents: 0 });
    const days62 = await analytics('?from=2026-09-07&to=2026-11-07');
    expect(days62.body.granularity).toBe('day');
    expect(days62.body.series).toHaveLength(62);
    expect((await analytics('?from=2026-09-06&to=2026-11-07')).body.granularity).toBe('month');
    const errors: [string, string][] = [
      ['?from=2025-11-07&to=2026-11-08', 'Ask for at most 366 days at a time.'],
      ['?from=2026-11-07&to=2026-11-01', 'to must be on or after from.'],
      ['?to=2026-11-01', 'to must be on or after from.'],
      ['?from=2026-02-30', 'Dates must look like 2026-11-02.'],
      ['?from=11/01/2026', 'Dates must look like 2026-11-02.'],
      ['?from=2015-01-01&to=2015-01-31', 'Pick dates within 10 years of today.'],
      ['?barberId=nobody', "That barber isn't on the team."],
    ];
    for (const [query, message] of errors) {
      const res = await analytics(query);
      expect(res.status, query).toBe(400);
      expect(res.body.error).toEqual({ code: 'invalid_request', message });
    }
    // from alone runs to today.
    expect((await analytics('?from=2026-11-01')).body).toMatchObject({ from: '2026-11-01', to: '2026-11-07' });
  });

  it('owner only', async () => {
    const res = await h.call('GET', '/api/owner/analytics');
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe('unauthorized');
    h.config.ownerKey = undefined;
    expect((await analytics()).status).toBe(503);
  });

  it('reads with a handful of indexed queries, whatever the range', async () => {
    await seedWeek(h);
    const queries: string[] = [];
    const db = h.deps.db;
    const counted = (q: Queryable): Queryable['query'] =>
      ((text: string, values?: unknown[]) => {
        queries.push(text);
        return q.query(text, values);
      }) as Queryable['query'];
    const counting: Db = { query: counted(db), transaction: (fn) => db.transaction((tx) => fn({ query: counted(tx) })) };
    const { createApp } = await import('../src/app.js');
    const app = createApp({ ...h.deps, db: counting });
    for (const query of ['from=2026-11-01&to=2026-11-07', 'from=2025-11-08&to=2026-11-08&barberId=flowxbori']) {
      queries.length = 0;
      const res = await app.fetch(new Request(`https://x.test/api/owner/analytics?${query}`, { headers: { authorization: `Bearer ${h.config.ownerKey}` } }));
      expect(res.status).toBe(200);
      // The snapshot setting, the team, sale items, appointments without a sale, fees, sale counts,
      // appointment counts, late cancellations and time off.
      expect(queries).toHaveLength(9);
    }
  });
});

describe('fees in the analytics', () => {
  it('a fee Stripe finished days after it was tried counts on the day it went through, like its chargedAt', async () => {
    await protectionOn(h);
    h.config.stripeWebhookSecret = WEBHOOK_SECRET;
    // Fay books Flowxbori's Tuesday 10 AM online, with her card on file.
    const token = newManageToken();
    const checkout = await h.call('POST', '/api/cards/checkout', { headers: { 'x-card-token': token }, body: { offeringId: OFFERING.flowHaircut45 } });
    h.stripe.completeSession(checkout.body.sessionId);
    expect((await h.call('POST', '/api/cards', { headers: { 'x-card-token': token }, body: { sessionId: checkout.body.sessionId } })).status).toBe(201);
    const policy = (await h.call('GET', `/api/no-show-policy?offeringId=${encodeURIComponent(OFFERING.flowHaircut45)}`)).body.policyText;
    const booked = await h.call('POST', '/api/appointments', {
      headers: { 'x-card-token': token },
      body: { offeringId: OFFERING.flowHaircut45, start: '2026-11-03T18:00:00Z', customer: { name: 'Fay', phone: '4425550101' }, noShowPolicy: policy },
    });
    expect(booked.status, booked.text).toBe(201);
    const id = booked.body.appointment.id as string;
    // Tuesday 10:20 AM: a no-show. Charging the fee, her bank wants her to approve it first.
    h.setNow('2026-11-03T18:20:00Z');
    expect((await h.call('PATCH', `/api/owner/appointments/${id}`, { ...owner, body: { status: 'noShow' } })).status).toBe(200);
    h.stripe.nextCharge = 'requires_action';
    const tried = await h.call('POST', `/api/owner/appointments/${id}/no-show-fee`, owner);
    expect(tried.body.appointment.noShowFee.status).toBe('needsAction');
    const intent = [...h.stripe.intents.values()].find((pi) => pi.metadata.appointment_id === id)!;
    // Thursday 4 PM: Stripe says it went through.
    h.setNow('2026-11-06T00:00:00Z');
    expect((await sendWebhook(h, 'payment_intent.succeeded', { object: 'payment_intent', id: intent.id, status: 'succeeded', amount: 3500 })).status).toBe(200);
    const day = await h.call('GET', '/api/owner/appointments?date=2026-11-03', owner);
    expect(day.body.appointments.find((a: { id: string }) => a.id === id).noShowFee).toMatchObject({ status: 'charged', chargedAt: '2026-11-06T00:00:00Z' });

    const week = (await analytics('?from=2026-11-03&to=2026-11-05')).body;
    expect(week.series.map((d: { date: string; feesCents: number }) => [d.date, d.feesCents])).toEqual([
      ['2026-11-03', 0],
      ['2026-11-04', 0],
      ['2026-11-05', 3500],
    ]);
    expect(week.totals.feesCents).toBe(3500);
    expect((await analytics('?from=2026-11-03&to=2026-11-03')).body.totals.feesCents).toBe(0);
  });
});
