import type { Catalog, Offering } from './catalog.js';
import type { Queryable } from './db.js';
import { addDays, addMinutes, dayBounds, formatInstant, localDate, weekday, wallClock } from './time.js';

// The Kit's BookingCalendar rules, on the server:
//  - start times every `slotIntervalMinutes` from opening, on the shop's wall clock;
//  - the appointment must end by closing;
//  - it must start at least `leadTimeMinutes` after now;
//  - only today through today + `windowDays` (shop-local days);
// minus each barber's booked/completed appointments and time off (theirs or the whole shop's).

export interface GridOptions {
  /** Defaults to the catalog's lead time. Owner bookings pass 0. */
  leadTimeMinutes?: number;
}

/** Start times on `date` for an appointment of `durationMinutes`, before any bookings. Mirrors BookingCalendar.slots. */
export function gridStarts(catalog: Catalog, date: string, durationMinutes: number, now: Date, options: GridOptions = {}): Date[] {
  const zone = catalog.timeZone;
  const today = localDate(now, zone);
  if (date < today || date > addDays(today, catalog.windowDays)) return [];
  const hours = catalog.hours(weekday(date));
  if (!hours) return [];
  const closes = wallClock(date, hours.closes, zone);
  if (!closes) return [];
  const earliest = addMinutes(now, options.leadTimeMinutes ?? catalog.leadTimeMinutes);
  const starts: Date[] = [];
  for (let minutes = hours.opens; minutes < hours.closes; minutes += catalog.slotIntervalMinutes) {
    const start = wallClock(date, minutes, zone);
    if (!start) continue;
    if (addMinutes(start, durationMinutes) > closes) break;
    if (start >= earliest) starts.push(start);
  }
  return starts;
}

export interface Busy {
  /** null = the whole shop. */
  barberId: string | null;
  start: Date;
  end: Date;
}

/** Live appointments and time off that touch [from, to) for these barbers (and shop-wide blocks). */
export async function busyIntervals(db: Queryable, barberIds: readonly string[], from: Date, to: Date): Promise<Busy[]> {
  const { rows } = await db.query<{ barber_id: string | null; start_at: Date; end_at: Date }>(
    `SELECT barber_id, start_at, end_at FROM appointments
      WHERE barber_id = ANY($1::text[])
        AND (status = 'booked' OR status = 'completed')
        AND start_at < $3 AND end_at > $2
     UNION ALL
     SELECT barber_id, start_at, end_at FROM time_off
      WHERE (barber_id IS NULL OR barber_id = ANY($1::text[]))
        AND start_at < $3 AND end_at > $2`,
    [barberIds, from, to],
  );
  return rows.map((r) => ({ barberId: r.barber_id, start: r.start_at, end: r.end_at }));
}

export function isFree(busy: readonly Busy[], barberId: string, start: Date, end: Date): boolean {
  return !busy.some(
    (b) => (b.barberId === null || b.barberId === barberId) && b.start < end && b.end > start,
  );
}

export interface Slot {
  start: string;
  barberIds: string[];
}

export interface DaySlots {
  date: string;
  slots: Slot[];
}

/**
 * Open start times for each day. A start is listed when at least one of the
 * offerings' barbers is free for that offering's own length; `barberIds` are the
 * free ones, in team order.
 */
export async function availability(
  db: Queryable,
  catalog: Catalog,
  offerings: readonly Offering[],
  from: string,
  days: number,
  now: Date,
): Promise<DaySlots[]> {
  const zone = catalog.timeZone;
  const dates = Array.from({ length: days }, (_, i) => addDays(from, i));
  const first = dates[0];
  const last = dates[dates.length - 1];
  if (first === undefined || last === undefined) return [];
  const rangeStart = dayBounds(first, zone).start;
  const rangeEnd = dayBounds(last, zone).end;

  // Grid first, so days with nothing to offer cost no query.
  const grids = dates.map((date) => offerings.map((o) => gridStarts(catalog, date, o.durationMinutes, now)));
  const anyCandidates = grids.some((perOffering) => perOffering.some((starts) => starts.length > 0));
  const busy = anyCandidates
    ? await busyIntervals(db, [...new Set(offerings.map((o) => o.barberId))], rangeStart, rangeEnd)
    : [];

  return dates.map((date, dayIndex) => {
    const free = new Map<number, Set<string>>();
    offerings.forEach((offering, i) => {
      for (const start of grids[dayIndex]?.[i] ?? []) {
        const end = addMinutes(start, offering.durationMinutes);
        if (!isFree(busy, offering.barberId, start, end)) continue;
        const key = start.getTime();
        let set = free.get(key);
        if (!set) free.set(key, (set = new Set()));
        set.add(offering.barberId);
      }
    });
    const slots = [...free.entries()]
      .sort(([a], [b]) => a - b)
      .map(([time, ids]) => ({
        start: formatInstant(new Date(time)),
        barberIds: [...ids].sort((a, b) => catalog.barberRank(a) - catalog.barberRank(b)),
      }));
    return { date, slots };
  });
}
