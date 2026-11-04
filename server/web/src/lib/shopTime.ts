// Times on the shop's wall clock, in the catalog's time zone (America/Los_Angeles),
// whatever zone the visitor's computer is set to. Instants are Dates; shop days
// are "YYYY-MM-DD" strings, done with plain calendar math (no time zones), so
// daylight saving changes never move a day. Labels are formatted by hand, like
// the Kit's, so they read the same in every browser.

export interface OpeningHours {
  /** "10:00", 24-hour. */
  opens: string;
  closes: string;
}

/** Keyed by the Kit's weekday numbers: "1" = Sunday … "7" = Saturday. Missing days are closed. */
export type WeeklyHours = Partial<Record<string, OpeningHours>>;

export const WEEKDAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'] as const;
export const WEEKDAY_SHORT = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'] as const;
export const MONTH_NAMES = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
] as const;
export const MONTH_SHORT = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'] as const;

export interface WallClock {
  /** "2026-11-04" */
  date: string;
  hour: number;
  minute: number;
  /** 1 = Sunday … 7 = Saturday. */
  weekday: number;
}

const formatters = new Map<string, Intl.DateTimeFormat>();

function formatter(zone: string): Intl.DateTimeFormat {
  let f = formatters.get(zone);
  if (!f) {
    f = new Intl.DateTimeFormat('en-US', {
      timeZone: zone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      hourCycle: 'h23',
    });
    formatters.set(zone, f);
  }
  return f;
}

/** The shop's wall clock at `instant`. */
export function wallClock(instant: Date, zone: string): WallClock {
  const parts: Record<string, string> = {};
  for (const part of formatter(zone).formatToParts(instant)) parts[part.type] = part.value;
  const date = `${parts.year}-${parts.month}-${parts.day}`;
  return { date, hour: Number(parts.hour) % 24, minute: Number(parts.minute), weekday: weekdayOf(date) };
}

/** The zone's offset from UTC at `instant`, in minutes (-480 for Pacific Standard Time). */
export function zoneOffsetMinutes(instant: Date, zone: string): number {
  const clock = wallClock(instant, zone);
  const { year, month, day } = parseDate(clock.date);
  const asUTC = Date.UTC(year, month - 1, day, clock.hour, clock.minute);
  return Math.round((asUTC - Math.floor(instant.getTime() / 60_000) * 60_000) / 60_000);
}

/** The shop day that contains `instant`. */
export function localDate(instant: Date, zone: string): string {
  return wallClock(instant, zone).date;
}

function utcDay(date: string): Date {
  const [y, m, d] = date.split('-').map(Number) as [number, number, number];
  return new Date(Date.UTC(y, m - 1, d));
}

function formatDay(day: Date): string {
  return `${day.getUTCFullYear()}-${String(day.getUTCMonth() + 1).padStart(2, '0')}-${String(day.getUTCDate()).padStart(2, '0')}`;
}

/** The day `days` after `date`. */
export function addDays(date: string, days: number): string {
  const day = utcDay(date);
  day.setUTCDate(day.getUTCDate() + days);
  return formatDay(day);
}

/** Whole days from `from` to `to`. */
export function daysBetween(from: string, to: string): number {
  return Math.round((utcDay(to).getTime() - utcDay(from).getTime()) / 86_400_000);
}

/** 1 = Sunday … 7 = Saturday, like the Kit's `Weekday`. */
export function weekdayOf(date: string): number {
  return utcDay(date).getUTCDay() + 1;
}

export function parseDate(date: string): { year: number; month: number; day: number } {
  const [year, month, day] = date.split('-').map(Number) as [number, number, number];
  return { year, month, day };
}

/** "10:00" → 600. */
export function clockMinutes(clock: string): number {
  const [h, m] = clock.split(':').map(Number) as [number, number];
  return h * 60 + m;
}

/** "10 AM", "7 PM", "10:30 AM", "12 PM" (the Kit's `TimeOfDay.label`). */
export function timeOfDayLabel(hour: number, minute: number): string {
  const suffix = hour < 12 ? 'AM' : 'PM';
  const twelve = hour % 12 === 0 ? 12 : hour % 12;
  return minute === 0 ? `${twelve} ${suffix}` : `${twelve}:${String(minute).padStart(2, '0')} ${suffix}`;
}

/** "19:00" → "7 PM". */
export function clockLabel(clock: string): string {
  const minutes = clockMinutes(clock);
  return timeOfDayLabel(Math.floor(minutes / 60), minutes % 60);
}

/** "10 AM – 7 PM". */
export function hoursLabel(hours: OpeningHours): string {
  return `${clockLabel(hours.opens)} – ${clockLabel(hours.closes)}`;
}

/** "2:30 PM" on the shop's clock. */
export function timeLabel(instant: Date, zone: string): string {
  const clock = wallClock(instant, zone);
  return timeOfDayLabel(clock.hour, clock.minute);
}

/** "Thu, Oct 29". */
export function shortDateLabel(date: string): string {
  const { month, day } = parseDate(date);
  return `${WEEKDAY_SHORT[weekdayOf(date) - 1]}, ${MONTH_SHORT[month - 1]} ${day}`;
}

/** "Thursday, October 29". */
export function longDateLabel(date: string): string {
  const { month, day } = parseDate(date);
  return `${WEEKDAY_NAMES[weekdayOf(date) - 1]}, ${MONTH_NAMES[month - 1]} ${day}`;
}

/** "Thursday, October 29, 2026". */
export function fullDateLabel(date: string): string {
  return `${longDateLabel(date)}, ${parseDate(date).year}`;
}

/** "Thu, Oct 29 at 2:30 PM" on the shop's clock (the Kit's `dateTimeLabel`). */
export function dateTimeLabel(instant: Date, zone: string): string {
  return `${shortDateLabel(localDate(instant, zone))} at ${timeLabel(instant, zone)}`;
}

/** "Thursday, October 29 at 2:30 PM". */
export function longDateTimeLabel(instant: Date, zone: string): string {
  return `${longDateLabel(localDate(instant, zone))} at ${timeLabel(instant, zone)}`;
}

/** "November 2026". */
export function monthTitle(year: number, month: number): string {
  return `${MONTH_NAMES[month - 1]} ${year}`;
}

/** "Morning" before noon, "Afternoon" until 5 PM, then "Evening" (the Kit's `DayPart`). */
export function dayPart(hour: number): 'Morning' | 'Afternoon' | 'Evening' {
  if (hour < 12) return 'Morning';
  if (hour < 17) return 'Afternoon';
  return 'Evening';
}

export interface OpenStatus {
  text: string;
  isOpen: boolean;
}

/**
 * Whether the shop is open today, on its own clock: "Open today until 7 PM",
 * "Open today from 10 AM until 7 PM" (before opening), "Closed now. Opens
 * tomorrow at 10 AM" (after closing) or "Closed today".
 */
export function openStatus(hours: WeeklyHours, zone: string, now: Date): OpenStatus {
  const clock = wallClock(now, zone);
  const minutes = clock.hour * 60 + clock.minute;
  const today = hours[String(clock.weekday)];
  if (today) {
    if (minutes < clockMinutes(today.opens)) {
      return { text: `Open today from ${clockLabel(today.opens)} until ${clockLabel(today.closes)}`, isOpen: false };
    }
    if (minutes < clockMinutes(today.closes)) {
      return { text: `Open today until ${clockLabel(today.closes)}`, isOpen: true };
    }
  }
  const next = nextOpening(hours, clock.date);
  const prefix = today ? 'Closed now' : 'Closed today';
  return { text: next ? `${prefix}. Opens ${next}` : 'Closed today', isOpen: false };
}

/** "tomorrow at 10 AM" or "Monday at 10 AM": the next day after `date` the shop opens. */
function nextOpening(hours: WeeklyHours, date: string): string | null {
  for (let offset = 1; offset <= 7; offset += 1) {
    const day = addDays(date, offset);
    const open = hours[String(weekdayOf(day))];
    if (!open) continue;
    const when = offset === 1 ? 'tomorrow' : WEEKDAY_NAMES[weekdayOf(day) - 1];
    return `${when} at ${clockLabel(open.opens)}`;
  }
  return null;
}

export interface HoursRow {
  weekday: number;
  name: string;
  /** "10 AM – 7 PM" or "Closed". */
  label: string;
  isToday: boolean;
}

/** The week's hours, Monday first, the way the shop lists them. */
export function weekRows(hours: WeeklyHours, todayWeekday: number): HoursRow[] {
  return [2, 3, 4, 5, 6, 7, 1].map((weekday) => {
    const open = hours[String(weekday)];
    return {
      weekday,
      name: WEEKDAY_NAMES[weekday - 1]!,
      label: open ? hoursLabel(open) : 'Closed',
      isToday: weekday === todayWeekday,
    };
  });
}

/**
 * The week in as few lines as it takes, Monday first: "Monday–Saturday: 10 AM – 7 PM",
 * "Sunday: 10 AM – 6 PM".
 */
export function hoursSummary(hours: WeeklyHours): string[] {
  const groups: { first: number; last: number; label: string }[] = [];
  for (const weekday of [2, 3, 4, 5, 6, 7, 1]) {
    const open = hours[String(weekday)];
    const label = open ? hoursLabel(open) : 'Closed';
    const last = groups[groups.length - 1];
    if (last && last.label === label) last.last = weekday;
    else groups.push({ first: weekday, last: weekday, label });
  }
  return groups.map((g) => {
    const days = g.first === g.last ? WEEKDAY_NAMES[g.first - 1] : `${WEEKDAY_NAMES[g.first - 1]}–${WEEKDAY_NAMES[g.last - 1]}`;
    return `${days}: ${g.label}`;
  });
}

export interface MonthPage {
  year: number;
  month: number;
  /** "2026-11" */
  id: string;
  title: string;
  /** Empty cells before the 1st, Sunday first. */
  leadingBlanks: number;
  days: string[];
}

export function monthPage(year: number, month: number): MonthPage {
  const first = `${year}-${String(month).padStart(2, '0')}-01`;
  const count = new Date(Date.UTC(year, month, 0)).getUTCDate();
  return {
    year,
    month,
    id: first.slice(0, 7),
    title: monthTitle(year, month),
    leadingBlanks: weekdayOf(first) - 1,
    days: Array.from({ length: count }, (_, i) => addDays(first, i)),
  };
}

/** This month through the month of `lastDay`. */
export function monthsBetween(firstDay: string, lastDay: string): MonthPage[] {
  const pages: MonthPage[] = [];
  let { year, month } = parseDate(firstDay);
  const last = parseDate(lastDay);
  while (year < last.year || (year === last.year && month <= last.month)) {
    pages.push(monthPage(year, month));
    month += 1;
    if (month > 12) {
      month = 1;
      year += 1;
    }
  }
  return pages;
}
