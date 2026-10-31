import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { gridStarts } from '../src/availability.js';
import { loadCatalog } from '../src/catalog.js';
import { formatInstant } from '../src/time.js';
import { useHarness } from './helpers/harness.js';

// Fixtures exported from IzzyClipzKit's BookingCalendar (see README, "Kit fixtures").
interface KitCase {
  now: string;
  date: string;
  durationMinutes: number;
  availability: 'open' | 'closed' | 'past' | 'noTimesLeft' | 'outsideWindow';
  starts: string[];
}
const kit = JSON.parse(readFileSync(new URL('./fixtures/kit-slots.json', import.meta.url), 'utf8')) as {
  timeZone: string;
  cases: KitCase[];
};

const catalog = loadCatalog();

describe("availability math matches the Kit's BookingCalendar", () => {
  it('uses the same time zone', () => {
    expect(kit.timeZone).toBe(catalog.timeZone);
    expect(catalog.timeZone).toBe('America/Los_Angeles');
  });

  it('covers both 2026 DST changes, a Sunday, the window edge, past days and a late "today"', () => {
    const dates = new Set(kit.cases.map((c) => c.date));
    for (const d of ['2026-03-08', '2026-11-01', '2026-11-08', '2026-12-30', '2026-12-31', '2026-10-30']) expect(dates).toContain(d);
    const kinds = new Set(kit.cases.map((c) => c.availability));
    for (const k of ['open', 'past', 'noTimesLeft', 'outsideWindow']) expect(kinds).toContain(k);
    expect(new Set(kit.cases.map((c) => c.durationMinutes))).toEqual(new Set([45, 75]));
  });

  for (const c of kit.cases) {
    it(`${c.date} for ${c.durationMinutes} min at ${c.now} (${c.availability})`, () => {
      const starts = gridStarts(catalog, c.date, c.durationMinutes, new Date(c.now)).map(formatInstant);
      expect(starts).toEqual(c.starts);
    });
  }

  it('spring forward: Mar 8 2026 opens at 10 AM PDT (17:00Z), the Saturday before at 10 AM PST (18:00Z)', () => {
    const sunday = kit.cases.find((c) => c.date === '2026-03-08' && c.durationMinutes === 45);
    const saturday = gridStarts(catalog, '2026-03-14', 45, new Date('2026-03-07T18:00:00Z'));
    expect(sunday?.starts[0]).toBe('2026-03-08T17:00:00Z');
    expect(formatInstant(saturday[0]!)).toBe('2026-03-14T17:00:00Z');
    expect(formatInstant(gridStarts(catalog, '2026-03-07', 45, new Date('2026-03-06T00:00:00Z'))[0]!)).toBe('2026-03-07T18:00:00Z');
  });

  it('fall back: Nov 1 2026 opens at 10 AM PST (18:00Z), Oct 31 at 10 AM PDT (17:00Z)', () => {
    const now = new Date('2026-10-30T12:00:00Z');
    expect(formatInstant(gridStarts(catalog, '2026-10-31', 45, now)[0]!)).toBe('2026-10-31T17:00:00Z');
    expect(formatInstant(gridStarts(catalog, '2026-11-01', 45, now)[0]!)).toBe('2026-11-01T18:00:00Z');
  });
});

describe('GET /api/availability with no bookings', () => {
  const h = useHarness({ now: '2026-10-31T17:05:00Z' });

  it('returns exactly the Kit start times for each day', async () => {
    const offering = catalog.data.offerings.find((o) => o.durationMinutes === 45 && o.barberId === 'flowxbori')!;
    const vip = catalog.data.offerings.find((o) => o.durationMinutes === 75)!;
    for (const o of [offering, vip]) {
      const res = await h.call('GET', `/api/availability?offeringId=${encodeURIComponent(o.id)}&from=2026-10-30&days=3`);
      expect(res.status).toBe(200);
      expect(res.body.timeZone).toBe('America/Los_Angeles');
      for (const day of res.body.days) {
        const expected = kit.cases.find((c) => c.now === '2026-10-31T17:05:00Z' && c.date === day.date && c.durationMinutes === o.durationMinutes);
        expect(expected, day.date).toBeDefined();
        expect(day.slots.map((s: { start: string }) => s.start)).toEqual(expected!.starts);
        for (const s of day.slots) expect(s.barberIds).toEqual([o.barberId]);
      }
    }
  });

  it('lists every requested day, including closed, past and out-of-window ones', async () => {
    const o = catalog.data.offerings[0]!;
    const res = await h.call('GET', `/api/availability?offeringId=${encodeURIComponent(o.id)}&from=2026-12-28&days=5`);
    expect(res.body.days.map((d: { date: string }) => d.date)).toEqual(['2026-12-28', '2026-12-29', '2026-12-30', '2026-12-31', '2027-01-01']);
    expect(res.body.days[2].slots.length).toBeGreaterThan(0);
    expect(res.body.days[3].slots).toEqual([]);
    expect(res.body.days[4].slots).toEqual([]);
  });

  it('validates the query', async () => {
    const o = encodeURIComponent(catalog.data.offerings[0]!.id);
    for (const q of [`offeringId=${o}&days=0`, `offeringId=${o}&days=32`, `offeringId=${o}&days=two`, `offeringId=${o}&from=2026-02-30`, `offeringId=${o}&from=9999-12-31&days=2`, `offeringId=${o}&from=2020-01-01`, 'days=3', 'serviceId=haircut', 'serviceId=haircut&barberId=flowxbori', 'offeringId=nobody%2F1']) {
      const res = await h.call('GET', `/api/availability?${q}`);
      expect(res.status, q).toBe(400);
      expect(res.body.error.code).toBe('invalid_request');
    }
    expect((await h.call('GET', `/api/availability?offeringId=${o}&days=31`)).body.days).toHaveLength(31);
  });

  it('defaults to today, one day', async () => {
    const o = catalog.data.offerings[0]!;
    const res = await h.call('GET', `/api/availability?offeringId=${encodeURIComponent(o.id)}`);
    expect(res.body.days).toHaveLength(1);
    expect(res.body.days[0].date).toBe('2026-10-31');
  });

  it('any barber: a start lists every free first-available barber, in team order', async () => {
    const res = await h.call('GET', '/api/availability?serviceId=haircut&barberId=any&from=2026-11-02&days=1');
    expect(res.status).toBe(200);
    const ids = catalog.firstAvailable('haircut')!.map((o) => o.barberId);
    expect(ids).toEqual(['flowxbori', 'cristian-ceja', 'julian-ramos']);
    expect(res.body.days[0].slots[0]).toEqual({ start: '2026-11-02T18:00:00Z', barberIds: ids });
    const kitDay = kit.cases.find((c) => c.date === '2026-11-02' && c.durationMinutes === 45)!;
    expect(res.body.days[0].slots.map((s: { start: string }) => s.start)).toEqual(kitDay.starts);
  });
});

describe('GET /api/owner/availability', () => {
  // Saturday Oct 31 2026, 10:05 AM PDT: the 10:30 start is inside the 30-minute lead time.
  const h = useHarness({ now: '2026-10-31T17:05:00Z' });
  const flow45 = () => catalog.data.offerings.find((o) => o.durationMinutes === 45 && o.barberId === 'flowxbori')!;

  it('needs the owner key', async () => {
    const res = await h.call('GET', `/api/owner/availability?offeringId=${encodeURIComponent(flow45().id)}&from=2026-10-31`);
    expect(res.status).toBe(401);
  });

  it('skips the lead time, so a walk-in can take the next slot that hasn\'t started', async () => {
    const path = `availability?offeringId=${encodeURIComponent(flow45().id)}&from=2026-10-31`;
    const publicStarts = (await h.call('GET', `/api/${path}`)).body.days[0].slots.map((s: { start: string }) => s.start);
    const owner = await h.call('GET', `/api/owner/${path}`, { owner: true });
    expect(owner.status).toBe(200);
    const ownerStarts = owner.body.days[0].slots.map((s: { start: string }) => s.start);
    expect(publicStarts[0]).toBe('2026-10-31T18:00:00Z');
    expect(ownerStarts[0]).toBe('2026-10-31T17:30:00Z');
    expect(ownerStarts).not.toContain('2026-10-31T17:00:00Z');
    expect(ownerStarts.slice(1)).toEqual(publicStarts);
  });
});
