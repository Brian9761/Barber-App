// @vitest-environment node
import { describe, expect, it } from 'vitest';
import * as server from '../../src/analytics.js';
import * as demo from '../src/demo/owner/analytics.js';

// The demo works its analytics out with a copy of the server's own definitions
// (src/demo/owner/analytics.ts, ported from server/src/analytics.ts). This runs both on
// the same facts, many times over, and they must answer exactly the same.

/** The same random numbers for the same seed, so a failure can be run again. */
function random(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4_294_967_296;
  };
}

const BARBERS = [
  { id: 'israel-flores', name: 'Izzy', active: true },
  { id: 'carlos-rafael', name: 'Carlos', active: true },
  { id: 'flowxbori', name: 'Flowxbori', active: true },
  { id: 'cristian-ceja', name: 'Cristian', active: true },
  { id: 'julian-ramos', name: 'Julian', active: true },
  { id: 'former-barber', name: 'Former', active: false },
];
const SERVICES: Record<string, string> = { haircut: 'Haircut', vip: 'VIP', 'military-haircut': 'Military Haircut' };

function facts(seed: number, from: string, to: string, barberId: string | null): demo.AnalyticsInput {
  const r = random(seed);
  const pick = <T>(items: readonly T[]): T => items[Math.floor(r() * items.length)]!;
  const { granularity, periods } = demo.seriesPeriods(from, to);
  const money: demo.MoneyFact[] = Array.from({ length: Math.floor(r() * 60) }, () => {
    const kind = pick(['service', 'service', 'product', 'custom', 'fee'] as const);
    const visit = kind === 'service' && r() < 0.3;
    const count = 1 + Math.floor(r() * 3);
    return {
      period: Math.floor(r() * (periods.length + 1)) - 1,
      barberId: kind === 'fee' && r() < 0.1 ? null : pick(BARBERS).id,
      kind,
      visit,
      itemId: kind === 'service' ? pick(Object.keys(SERVICES)) : kind === 'product' ? (r() < 0.2 ? null : pick(['p1', 'p2', 'p3'])) : null,
      name: kind === 'product' ? pick(['Pomade', 'Oil', 'Old gel']) : kind === 'service' ? 'Old name' : '',
      count,
      cents: count * (500 + Math.floor(r() * 8000)),
    };
  });
  const sales: demo.SaleCountFact[] = BARBERS.filter(() => r() < 0.8).map((b) => {
    const count = Math.floor(r() * 10);
    return { barberId: b.id, sales: count, withoutAppointment: Math.floor(r() * (count + 1)), withProduct: Math.floor(r() * (count + 1)) };
  });
  const appointments: demo.AppointmentFact[] = BARBERS.filter(() => r() < 0.8).map((b) => ({
    barberId: b.id,
    booked: Math.floor(r() * 5),
    completed: Math.floor(r() * 10),
    noShows: Math.floor(r() * 3),
    cancelled: Math.floor(r() * 3),
    lateCancellations: Math.floor(r() * 2),
    upcoming: Math.floor(r() * 4),
    bookedMinutes: Math.floor(r() * 2000),
  }));
  return {
    from,
    to,
    barberId,
    timeZone: 'America/Los_Angeles',
    generatedAt: new Date('2026-11-04T23:00:00.456Z'),
    granularity,
    periods,
    previous: demo.previousPeriod(from, to),
    barbers: BARBERS,
    serviceName: (id) => SERVICES[id],
    money,
    sales,
    appointments,
    openMinutes: new Map(BARBERS.filter((b) => b.active && r() < 0.9).map((b) => [b.id, Math.floor(r() * 5000)])),
  };
}

describe('the demo’s analytics', () => {
  it('splits a range into the same days or months as the server, with the same period before', () => {
    for (const [from, to] of [
      ['2026-11-04', '2026-11-04'],
      ['2026-11-02', '2026-11-08'],
      ['2026-10-01', '2026-12-01'],
      ['2026-09-04', '2026-11-04'],
      ['2026-01-01', '2026-12-31'],
      ['2027-12-20', '2028-02-29'],
    ] as const) {
      expect(demo.seriesPeriods(from, to), `${from}…${to}`).toEqual(server.seriesPeriods(from, to));
      expect(demo.previousPeriod(from, to)).toEqual(server.previousPeriod(from, to));
    }
  });

  it('rounds and ranks like the server', () => {
    for (const [n, d] of [
      [0, 0],
      [5, 2],
      [7, 2],
      [1, 3],
      [2, 3],
      [12345, 678],
    ] as const) {
      expect(demo.roundedRatio(n, d)).toBe(server.roundedRatio(n, d));
      expect(demo.ratio(n, d)).toBe(server.ratio(n, d));
    }
    const entries = [
      { name: 'Carlos', salesCents: 100, servicesCount: 2 },
      { name: 'Izzy', salesCents: 100, servicesCount: 2 },
      { name: 'Julian', salesCents: 100, servicesCount: 3 },
      { name: 'Cristian', salesCents: 0, servicesCount: 0 },
    ];
    expect(demo.rankLeaderboard(entries)).toEqual(server.rankLeaderboard(entries));
  });

  it('answers exactly like the server for the same facts, for the whole shop and each barber', () => {
    const ranges = [
      ['2026-11-04', '2026-11-04'],
      ['2026-11-02', '2026-11-04'],
      ['2026-10-01', '2026-11-04'],
      ['2026-01-01', '2026-11-04'],
    ] as const;
    let compared = 0;
    for (let seed = 1; seed <= 60; seed += 1) {
      const [from, to] = ranges[seed % ranges.length]!;
      for (const barberId of [null, 'flowxbori', 'former-barber']) {
        const input = facts(seed, from, to, barberId);
        // The server's own input type, field for field the same.
        expect(demo.computeAnalytics(input)).toEqual(server.computeAnalytics(input as unknown as server.AnalyticsInput));
        compared += 1;
      }
    }
    expect(compared).toBe(180);
  });
});
