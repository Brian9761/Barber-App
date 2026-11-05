// Analytics' periods on the shop's calendar (America/Los_Angeles): Today, Week (Monday
// to today), Month (the 1st to today), Year (January 1 to today) and a custom range of at
// most 366 days; their labels; and the change from the period before, in words.

import { MONTH_SHORT, addDays, daysBetween, parseDate, shortDateLabel, weekdayOf } from '../../lib/shopTime';

export type PeriodKind = 'today' | 'week' | 'month' | 'year' | 'custom';

export interface Range {
  from: string;
  to: string;
}

/** The longest range the server answers, in days. */
export const MAX_RANGE_DAYS = 366;
/** How far from today a custom range may reach, either way (the server's limit is about ten years). */
export const MAX_YEARS_AWAY = 10;

/** Monday of `date`'s week (the shop's weeks start on Monday). */
export function mondayOf(date: string): string {
  return addDays(date, -((weekdayOf(date) + 5) % 7));
}

/** The days a period covers, from `today` (the shop's today). */
export function periodRange(kind: Exclude<PeriodKind, 'custom'>, today: string): Range {
  switch (kind) {
    case 'today':
      return { from: today, to: today };
    case 'week':
      return { from: mondayOf(today), to: today };
    case 'month':
      return { from: `${today.slice(0, 7)}-01`, to: today };
    case 'year':
      return { from: `${today.slice(0, 4)}-01-01`, to: today };
  }
}

/** How many days a range covers, both ends included. */
export function rangeDays(range: Range): number {
  return daysBetween(range.from, range.to) + 1;
}

/** What's wrong with a custom range, or null: from on or before to, at most 366 days, within ten years of today. */
export function rangeProblem(range: Range, today: string): string | null {
  const datePattern = /^\d{4}-\d{2}-\d{2}$/;
  if (!datePattern.test(range.from) || !datePattern.test(range.to)) return 'Pick both dates.';
  if (range.to < range.from) return 'The end date is before the start date. Pick an end date on or after the start.';
  if (rangeDays(range) > MAX_RANGE_DAYS) return `Pick at most ${MAX_RANGE_DAYS} days (about a year).`;
  const limit = MAX_YEARS_AWAY * 366;
  if (Math.abs(daysBetween(today, range.from)) > limit || Math.abs(daysBetween(today, range.to)) > limit) return 'Pick dates within 10 years of today.';
  return null;
}

/** "Nov 2", or "Nov 2, 2025" when it isn't this year. */
function dayLabel(date: string, thisYear: number): string {
  const { year, month, day } = parseDate(date);
  return year === thisYear ? `${MONTH_SHORT[month - 1]} ${day}` : `${MONTH_SHORT[month - 1]} ${day}, ${year}`;
}

/** "Nov 2 – Nov 4", "Nov 4", "Dec 28, 2025 – Jan 3". */
export function rangeLabel(range: Range, today: string): string {
  const thisYear = parseDate(today).year;
  if (range.from === range.to) return shortDateLabel(range.from);
  return `${dayLabel(range.from, thisYear)} – ${dayLabel(range.to, thisYear)}`;
}

/** The period's name for the page: "Today", "This week", "This month", "This year", or the dates. */
export function periodTitle(kind: PeriodKind, range: Range, today: string): string {
  switch (kind) {
    case 'today':
      return 'Today';
    case 'week':
      return 'This week';
    case 'month':
      return 'This month';
    case 'year':
      return 'This year';
    default:
      return rangeLabel(range, today);
  }
}

/** What the change is measured from: "yesterday", "the week before", "the 3 days before". */
export function comparedWith(range: Range, today: string): string {
  const days = rangeDays(range);
  if (days === 1) return range.from === today ? 'yesterday' : 'the day before';
  if (days === 7) return 'the week before';
  return `the ${days} days before`;
}

/**
 * The change in sales from the same number of days just before (the server's `previous`,
 * docs/analytics.md): "Up 12% from yesterday", "Down 8% from the week before", "About the same
 * as the 3 days before", or "No sales yesterday" when there's nothing to compare with.
 */
export function changeText(currentCents: number, previousCents: number, range: Range, today: string): string {
  const before = comparedWith(range, today);
  if (previousCents <= 0) return before === 'yesterday' ? 'No sales yesterday' : `No sales ${before === 'the day before' ? 'the day before' : `in ${before}`}`;
  const change = Math.round(((currentCents - previousCents) / previousCents) * 100);
  if (change === 0) return `About the same as ${before}`;
  return `${change > 0 ? 'Up' : 'Down'} ${Math.abs(change)}% from ${before}`;
}

/** Whether the change is up, down, or neither, for its arrow. */
export function changeDirection(currentCents: number, previousCents: number): 'up' | 'down' | 'none' {
  if (previousCents <= 0) return 'none';
  const change = Math.round(((currentCents - previousCents) / previousCents) * 100);
  return change > 0 ? 'up' : change < 0 ? 'down' : 'none';
}

/** A series entry's label: "Tue 3" for a day (with the month on the 1st), "Nov" for a month. */
export function seriesTick(date: string): string {
  if (date.length === 7) return MONTH_SHORT[Number(date.slice(5, 7)) - 1]!;
  const { month, day } = parseDate(date);
  return day === 1 ? `${MONTH_SHORT[month - 1]} 1` : String(day);
}

/** A series entry in words, for its table row and its details: "Tue, Nov 3", or "November 2026". */
export function seriesLabel(date: string): string {
  if (date.length === 7) {
    const names = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return `${names[Number(date.slice(5, 7)) - 1]} ${date.slice(0, 4)}`;
  }
  return shortDateLabel(date);
}
