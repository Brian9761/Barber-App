import { DateTime } from 'luxon';

// Time helpers. Instants are JS Dates (UTC). Shop-local calendar days are plain
// "YYYY-MM-DD" strings, and wall-clock times are minutes since midnight. All
// zone math goes through Luxon with an explicit IANA zone, so the server's own
// time zone never matters and daylight saving changes are handled by tzdata.

const DATE_RE = /^(\d{4})-(\d{2})-(\d{2})$/;
const INSTANT_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d{1,9})?)?(?:Z|[+-]\d{2}:\d{2})$/;

/** "2026-11-02T18:00:00Z": UTC, no fractional seconds (the contract's format). */
export function formatInstant(date: Date): string {
  return date.toISOString().replace(/\.\d{3}Z$/, 'Z');
}

/** Parses an ISO 8601 date-time with a zone designator ("Z" or "+hh:mm"). */
export function parseInstant(text: string): Date | null {
  if (!INSTANT_RE.test(text)) return null;
  const dt = DateTime.fromISO(text, { setZone: true });
  return dt.isValid ? dt.toJSDate() : null;
}

/** Whether `text` is a real calendar date in "YYYY-MM-DD" form. */
export function isDate(text: string): boolean {
  const m = DATE_RE.exec(text);
  if (!m) return false;
  return DateTime.fromObject({ year: Number(m[1]), month: Number(m[2]), day: Number(m[3]) }, { zone: 'UTC' }).isValid;
}

function utcDay(date: string): DateTime {
  const m = DATE_RE.exec(date);
  if (!m) throw new RangeError(`Not a date: ${date}`);
  const dt = DateTime.fromObject({ year: Number(m[1]), month: Number(m[2]), day: Number(m[3]) }, { zone: 'UTC' });
  if (!dt.isValid) throw new RangeError(`Not a date: ${date}`);
  return dt;
}

/** The day `days` after `date` (pure calendar math, no time zones). */
export function addDays(date: string, days: number): string {
  return utcDay(date).plus({ days }).toFormat('yyyy-MM-dd');
}

/** Whole days from `from` to `to`. */
export function daysBetween(from: string, to: string): number {
  return Math.round(utcDay(to).diff(utcDay(from), 'days').days);
}

/** Day of the week like the Kit's `Weekday`: 1 = Sunday … 7 = Saturday. */
export function weekday(date: string): number {
  // Luxon: 1 = Monday … 7 = Sunday.
  return (utcDay(date).weekday % 7) + 1;
}

/** The shop-local calendar day that contains `instant`. */
export function localDate(instant: Date, zone: string): string {
  return DateTime.fromJSDate(instant, { zone }).toFormat('yyyy-MM-dd');
}

/** Minutes since local midnight shown on the shop's wall clock at `instant`. */
export function localMinutes(instant: Date, zone: string): number {
  const dt = DateTime.fromJSDate(instant, { zone });
  return dt.hour * 60 + dt.minute;
}

/**
 * The instant the shop's wall clock shows `minutes` past midnight on `date`, or
 * null when that time doesn't exist that day (skipped when clocks spring
 * forward). Times that happen twice (fall back) resolve to the first one, like
 * Foundation's Calendar.
 */
export function wallClock(date: string, minutes: number, zone: string): Date | null {
  const day = utcDay(date);
  const hour = Math.floor(minutes / 60);
  const minute = minutes % 60;
  if (hour > 23) return null;
  const dt = DateTime.fromObject({ year: day.year, month: day.month, day: day.day, hour, minute }, { zone });
  if (!dt.isValid) return null;
  if (dt.year !== day.year || dt.month !== day.month || dt.day !== day.day || dt.hour !== hour || dt.minute !== minute) {
    return null;
  }
  return dt.toJSDate();
}

/** Local midnight at the start of `date` until local midnight after it: 23, 24 or 25 hours. */
export function dayBounds(date: string, zone: string): { start: Date; end: Date } {
  const day = utcDay(date);
  const start = DateTime.fromObject({ year: day.year, month: day.month, day: day.day }, { zone }).startOf('day');
  return { start: start.toJSDate(), end: start.plus({ days: 1 }).startOf('day').toJSDate() };
}

/** "HH:mm" → minutes since midnight. */
export function parseClock(text: string): number {
  const m = /^(\d{2}):(\d{2})$/.exec(text);
  if (!m) throw new RangeError(`Not a time: ${text}`);
  const hours = Number(m[1]);
  const minutes = Number(m[2]);
  if (hours > 23 || minutes > 59) throw new RangeError(`Not a time: ${text}`);
  return hours * 60 + minutes;
}

export function addMinutes(instant: Date, minutes: number): Date {
  return new Date(instant.getTime() + minutes * 60_000);
}

/** Drops seconds and milliseconds. */
export function floorToMinute(instant: Date): Date {
  return new Date(Math.floor(instant.getTime() / 60_000) * 60_000);
}
