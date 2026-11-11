import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { api, errorMessage } from '../api/client';
import type { BookingTarget, Catalog, Slot } from '../api/types';
import { addDays, daysBetween, localDate, weekdayOf, type MonthPage } from '../lib/shopTime';

// The open times for one booking choice, from the shop's live calendar, asked
// for two weeks at a time and kept by shop day (the app's AvailabilityLoader).
// Days before today, after the booking window and when the shop is closed are
// known without asking; every other day is "checking" until the server answers.

export type DayStatus = 'past' | 'tooFar' | 'closed' | 'notLoaded' | 'noOpenings' | 'open';

/** Days per request. */
const CHUNK_DAYS = 14;

export function useAvailability(catalog: Catalog, target: BookingTarget, now: Date) {
  const targetKey = JSON.stringify(target);
  const [slotsByDay, setSlotsByDay] = useState<Record<string, Slot[]>>({});
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const loaded = useRef<Record<string, Slot[]>>({});
  const queue = useRef<Promise<void>>(Promise.resolve());
  const generation = useRef(0);

  const today = localDate(now, catalog.timeZone);
  const lastDay = addDays(today, catalog.windowDays);

  // Another service or barber: start over.
  useEffect(() => {
    generation.current += 1;
    loaded.current = {};
    setSlotsByDay({});
    setError(null);
  }, [targetKey]);

  const statusOf = useCallback(
    (date: string): DayStatus => {
      if (date < today) return 'past';
      if (date > lastDay) return 'tooFar';
      if (!catalog.hours[String(weekdayOf(date))]) return 'closed';
      const slots = slotsByDay[date];
      if (!slots) return 'notLoaded';
      return slots.length === 0 ? 'noOpenings' : 'open';
    },
    [catalog.hours, lastDay, slotsByDay, today],
  );

  /** The bookable days of a month page: from today to the last day of the window. */
  const rangeOf = useCallback(
    (page: MonthPage): [string, string] | null => {
      const first = page.days[0];
      const last = page.days[page.days.length - 1];
      if (!first || !last) return null;
      const start = first < today ? today : first;
      const end = last > lastDay ? lastDay : last;
      return start <= end ? [start, end] : null;
    },
    [lastDay, today],
  );

  const fetchRange = useCallback(
    (from: string, to: string, skipLoaded: boolean): Promise<void> => {
      const run = generation.current;
      const parsedTarget = JSON.parse(targetKey) as BookingTarget;
      // One request at a time, so answers for the same days can't arrive out of order.
      queue.current = queue.current.then(async () => {
        if (run !== generation.current) return;
        setLoading(true);
        try {
          let day = from;
          while (day <= to) {
            if (skipLoaded && loaded.current[day]) {
              day = addDays(day, 1);
              continue;
            }
            const count = Math.min(CHUNK_DAYS, daysBetween(day, to) + 1);
            const response = await api.availability(parsedTarget, day, count);
            if (run !== generation.current) return;
            // Every day asked for is known now, even one the server left out.
            for (let i = 0; i < count; i += 1) loaded.current[addDays(day, i)] = [];
            for (const d of response.days) loaded.current[d.date] = [...d.slots].sort((a, b) => a.start.localeCompare(b.start));
            setSlotsByDay({ ...loaded.current });
            setError(null);
            day = addDays(day, count);
          }
        } catch (e) {
          if (run === generation.current) setError(errorMessage(e));
        } finally {
          if (run === generation.current) setLoading(false);
        }
      });
      return queue.current;
    },
    [targetKey],
  );

  /** Loads the month's bookable days that haven't been loaded. */
  const load = useCallback(
    (page: MonthPage) => {
      const range = rangeOf(page);
      return range ? fetchRange(range[0], range[1], true) : Promise.resolve();
    },
    [fetchRange, rangeOf],
  );

  /** Asks again for the whole month (after a time was taken, say), replacing what's there as answers arrive. */
  const reload = useCallback(
    (page: MonthPage) => {
      const range = rangeOf(page);
      return range ? fetchRange(range[0], range[1], false) : Promise.resolve();
    },
    [fetchRange, rangeOf],
  );

  /** The first day from `start` on with open times, among the days loaded. */
  const firstOpenDay = useCallback(
    (start: string, end: string): string | null => {
      const days = Object.keys(slotsByDay)
        .filter((d) => d >= start && d <= end && statusOf(d) === 'open')
        .sort();
      return days[0] ?? null;
    },
    [slotsByDay, statusOf],
  );

  /** Whether every bookable day of the month has an answer. */
  const isLoaded = useCallback(
    (page: MonthPage) => {
      const range = rangeOf(page);
      if (!range) return true;
      for (let day = range[0]; day <= range[1]; day = addDays(day, 1)) {
        if (statusOf(day) === 'notLoaded') return false;
      }
      return true;
    },
    [rangeOf, statusOf],
  );

  return useMemo(
    () => ({ slotsByDay, loading, error, statusOf, load, reload, firstOpenDay, isLoaded, rangeOf, today, lastDay }),
    [slotsByDay, loading, error, statusOf, load, reload, firstOpenDay, isLoaded, rangeOf, today, lastDay],
  );
}
