import { describe, expect, it } from 'vitest';
import { changeDirection, changeText, comparedWith, mondayOf, periodRange, periodTitle, rangeDays, rangeLabel, rangeProblem, seriesLabel, seriesTick } from './periods';

// Analytics' periods on the shop's calendar: weeks start on Monday, months on the 1st,
// years on January 1, all up to today; a custom range is at most 366 days.

describe('periods', () => {
  it('starts weeks on Monday, whatever the day', () => {
    expect(mondayOf('2026-11-02')).toBe('2026-11-02'); // a Monday
    expect(mondayOf('2026-11-04')).toBe('2026-11-02'); // Wednesday
    expect(mondayOf('2026-11-08')).toBe('2026-11-02'); // Sunday: the end of Monday's week
    expect(mondayOf('2026-01-01')).toBe('2025-12-29'); // across the new year
  });

  it('runs Today, Week, Month and Year up to today', () => {
    expect(periodRange('today', '2026-11-04')).toEqual({ from: '2026-11-04', to: '2026-11-04' });
    expect(periodRange('week', '2026-11-04')).toEqual({ from: '2026-11-02', to: '2026-11-04' });
    expect(periodRange('month', '2026-11-04')).toEqual({ from: '2026-11-01', to: '2026-11-04' });
    expect(periodRange('year', '2026-11-04')).toEqual({ from: '2026-01-01', to: '2026-11-04' });
    // The week the clocks fall back (Sunday, November 1) is still seven days from Monday.
    expect(rangeDays(periodRange('week', '2026-11-01'))).toBe(7);
    expect(periodRange('week', '2026-03-08')).toEqual({ from: '2026-03-02', to: '2026-03-08' }); // the spring change
    // December 31 of a leap year: 366 days, the most the server takes.
    expect(rangeDays(periodRange('year', '2028-12-31'))).toBe(366);
  });

  it('takes a custom range of at most 366 days, in order, within ten years', () => {
    const today = '2026-11-04';
    expect(rangeProblem({ from: '2026-10-01', to: '2026-10-31' }, today)).toBeNull();
    expect(rangeProblem({ from: '2025-11-05', to: '2026-11-05' }, today)).toBeNull(); // 366 days
    expect(rangeProblem({ from: '2025-11-04', to: '2026-11-05' }, today)).toBe('Pick at most 366 days (about a year).');
    expect(rangeProblem({ from: '2026-11-05', to: '2026-11-01' }, today)).toBe('The end date is before the start date. Pick an end date on or after the start.');
    expect(rangeProblem({ from: '', to: '2026-11-01' }, today)).toBe('Pick both dates.');
    expect(rangeProblem({ from: '2010-01-01', to: '2010-01-02' }, today)).toBe('Pick dates within 10 years of today.');
  });

  it('labels a period plainly', () => {
    const today = '2026-11-04';
    expect(periodTitle('week', { from: '2026-11-02', to: today }, today)).toBe('This week');
    expect(rangeLabel({ from: '2026-11-02', to: '2026-11-04' }, today)).toBe('Nov 2 – Nov 4');
    expect(rangeLabel({ from: '2025-12-28', to: '2026-01-03' }, today)).toBe('Dec 28, 2025 – Jan 3');
    expect(rangeLabel({ from: today, to: today }, today)).toBe('Wed, Nov 4');
    expect(periodTitle('custom', { from: '2026-10-01', to: '2026-10-31' }, today)).toBe('Oct 1 – Oct 31');
    expect(seriesTick('2026-11-01')).toBe('Nov 1');
    expect(seriesTick('2026-11-02')).toBe('2');
    expect(seriesTick('2026-11')).toBe('Nov');
    expect(seriesLabel('2026-11')).toBe('November 2026');
    expect(seriesLabel('2026-11-03')).toBe('Tue, Nov 3');
  });
});

describe('the change from before', () => {
  const today = '2026-11-04';

  it('is measured from the same number of days just before (docs/analytics.md)', () => {
    expect(comparedWith({ from: today, to: today }, today)).toBe('yesterday');
    expect(comparedWith({ from: '2026-11-03', to: '2026-11-03' }, today)).toBe('the day before');
    expect(comparedWith({ from: '2026-10-26', to: '2026-11-01' }, today)).toBe('the week before');
    expect(comparedWith({ from: '2026-11-02', to: today }, today)).toBe('the 3 days before');
  });

  it('says up or down in whole percents, or that there was nothing before', () => {
    const day = { from: today, to: today };
    expect(changeText(11200, 10000, day, today)).toBe('Up 12% from yesterday');
    expect(changeText(5000, 10000, day, today)).toBe('Down 50% from yesterday');
    expect(changeText(10040, 10000, day, today)).toBe('About the same as yesterday');
    expect(changeText(5000, 0, day, today)).toBe('No sales yesterday');
    expect(changeText(5000, 0, { from: '2026-10-26', to: '2026-11-01' }, today)).toBe('No sales in the week before');
    expect(changeDirection(11200, 10000)).toBe('up');
    expect(changeDirection(5000, 10000)).toBe('down');
    expect(changeDirection(5000, 0)).toBe('none');
  });
});
