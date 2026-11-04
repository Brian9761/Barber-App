import { afterEach, describe, expect, it } from 'vitest';
import { catalog } from '../test/api';
import {
  addDays,
  dateTimeLabel,
  hoursSummary,
  localDate,
  longDateLabel,
  monthPage,
  monthsBetween,
  openStatus,
  timeLabel,
  wallClock,
  weekdayOf,
  weekRows,
  zoneOffsetMinutes,
} from './shopTime';

const LA = 'America/Los_Angeles';
const open = (iso: string) => openStatus(catalog.hours, LA, new Date(iso)).text;

describe('open today, on the shop’s clock', () => {
  const originalTZ = process.env.TZ;
  afterEach(() => {
    process.env.TZ = originalTZ;
  });

  it('says until when it’s open, or when it opens', () => {
    // Tuesday, November 3, 2026 (PST, UTC−8): 10 AM to 7 PM.
    expect(open('2026-11-03T17:30:00Z')).toBe('Open today from 10 AM until 7 PM'); // 9:30 AM
    expect(open('2026-11-03T18:00:00Z')).toBe('Open today until 7 PM'); // 10 AM
    expect(open('2026-11-04T02:59:00Z')).toBe('Open today until 7 PM'); // 6:59 PM, already Wednesday in UTC
    expect(open('2026-11-04T03:00:00Z')).toBe('Closed now. Opens tomorrow at 10 AM'); // 7 PM
    // Saturday night: Sunday opens at 10.
    expect(open('2026-11-08T04:30:00Z')).toBe('Closed now. Opens tomorrow at 10 AM');
    expect(openStatus(catalog.hours, LA, new Date('2026-11-03T18:00:00Z')).isOpen).toBe(true);
  });

  it('gets the day right on the day clocks fall back (Sunday, November 1, 2026)', () => {
    // Sunday hours are 10 AM to 6 PM. 1:30 AM happens twice, first in PDT then in PST.
    expect(open('2026-11-01T08:30:00Z')).toBe('Open today from 10 AM until 6 PM');
    expect(open('2026-11-01T09:30:00Z')).toBe('Open today from 10 AM until 6 PM');
    expect(open('2026-11-01T17:59:00Z')).toBe('Open today from 10 AM until 6 PM'); // 9:59 AM PST
    expect(open('2026-11-01T18:00:00Z')).toBe('Open today until 6 PM'); // 10:00 AM PST
    expect(open('2026-11-02T01:59:00Z')).toBe('Open today until 6 PM'); // 5:59 PM PST
    expect(open('2026-11-02T02:00:00Z')).toBe('Closed now. Opens tomorrow at 10 AM'); // 6 PM PST
  });

  it('gets the hour right on the day clocks spring forward (Sunday, March 8, 2026)', () => {
    // After 2 AM it's PDT (UTC−7): 10 AM is 17:00 UTC, not 18:00.
    expect(open('2026-03-08T16:59:00Z')).toBe('Open today from 10 AM until 6 PM');
    expect(open('2026-03-08T17:00:00Z')).toBe('Open today until 6 PM');
    expect(open('2026-03-09T00:59:00Z')).toBe('Open today until 6 PM'); // 5:59 PM PDT
    expect(open('2026-03-09T01:00:00Z')).toBe('Closed now. Opens tomorrow at 10 AM');
  });

  it("doesn't depend on the computer's own time zone", () => {
    process.env.TZ = 'Asia/Tokyo';
    expect(new Date('2026-11-03T18:00:00Z').getHours()).toBe(3);
    expect(open('2026-11-03T18:00:00Z')).toBe('Open today until 7 PM');
    process.env.TZ = 'Pacific/Honolulu';
    expect(open('2026-11-04T03:00:00Z')).toBe('Closed now. Opens tomorrow at 10 AM');
  });

  it('says so on a day the shop is closed', () => {
    const noMondays = { ...catalog.hours, '2': undefined };
    expect(openStatus(noMondays, LA, new Date('2026-11-02T20:00:00Z')).text).toBe('Closed today. Opens tomorrow at 10 AM');
    expect(openStatus({}, LA, new Date('2026-11-02T20:00:00Z')).text).toBe('Closed today');
  });
});

describe('the shop’s calendar and labels', () => {
  it('reads the wall clock in the shop’s zone', () => {
    expect(wallClock(new Date('2026-11-03T18:30:00Z'), LA)).toEqual({ date: '2026-11-03', hour: 10, minute: 30, weekday: 3 });
    expect(localDate(new Date('2026-11-04T07:59:00Z'), LA)).toBe('2026-11-03');
    expect(localDate(new Date('2026-11-04T08:00:00Z'), LA)).toBe('2026-11-04');
    expect(wallClock(new Date('2026-11-04T07:00:00Z'), LA).hour).toBe(23);
    expect(zoneOffsetMinutes(new Date('2026-11-03T18:00:00Z'), LA)).toBe(-480);
    expect(zoneOffsetMinutes(new Date('2026-07-03T18:00:00Z'), LA)).toBe(-420);
  });

  it('labels times and days like the Kit', () => {
    expect(timeLabel(new Date('2026-11-03T18:00:00Z'), LA)).toBe('10 AM');
    expect(timeLabel(new Date('2026-11-03T22:30:00Z'), LA)).toBe('2:30 PM');
    expect(timeLabel(new Date('2026-11-03T20:00:00Z'), LA)).toBe('12 PM');
    expect(dateTimeLabel(new Date('2026-11-03T22:30:00Z'), LA)).toBe('Tue, Nov 3 at 2:30 PM');
    expect(longDateLabel('2026-10-29')).toBe('Thursday, October 29');
    expect(weekdayOf('2026-11-01')).toBe(1);
    expect(addDays('2026-12-31', 1)).toBe('2027-01-01');
  });

  it('lists the week Monday first, today marked, and sums it up', () => {
    const rows = weekRows(catalog.hours, 3);
    expect(rows.map((r) => r.name)).toEqual(['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']);
    expect(rows.find((r) => r.isToday)?.name).toBe('Tuesday');
    expect(rows[6]!.label).toBe('10 AM – 6 PM');
    expect(hoursSummary(catalog.hours)).toEqual(['Monday–Saturday: 10 AM – 7 PM', 'Sunday: 10 AM – 6 PM']);
  });

  it('lays out months Sunday first, from this month to the end of the booking window', () => {
    const november = monthPage(2026, 11);
    expect(november).toMatchObject({ id: '2026-11', title: 'November 2026', leadingBlanks: 0 });
    expect(november.days).toHaveLength(30);
    expect(monthPage(2026, 12).leadingBlanks).toBe(2);
    expect(monthPage(2028, 2).days).toHaveLength(29);
    expect(monthsBetween('2026-11-03', addDays('2026-11-03', 60)).map((p) => p.id)).toEqual(['2026-11', '2026-12', '2027-01']);
  });
});
