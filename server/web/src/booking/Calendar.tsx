import { useEffect, useId, useRef, useState, type KeyboardEvent } from 'react';
import { Icon } from '../components/Icon';
import { addDays, longDateLabel, parseDate, WEEKDAY_NAMES, WEEKDAY_SHORT, type MonthPage } from '../lib/shopTime';
import type { DayStatus } from './useAvailability';

/**
 * One month, Sunday first. A day with open times is dark with a blue dot under it
 * and can be picked; days without openings, closed days, past days and days not
 * checked yet are gray and can't be. Today has a ring; the picked day is blue.
 *
 * Keyboard: the month is one tab stop; the arrow keys move between days that can
 * be picked (a week up or down with ↑ ↓), Home and End to the first and last,
 * and Enter or Space picks.
 */
export function Calendar({
  page,
  today,
  selectedDay,
  statusOf,
  slotCount,
  canShowPrevious,
  canShowNext,
  onPrevious,
  onNext,
  onSelect,
  note,
}: {
  /** A line under the legend: how far ahead, and how soon before a time, it can be booked. */
  note?: string;
  page: MonthPage;
  today: string;
  selectedDay: string | null;
  statusOf: (date: string) => DayStatus;
  slotCount: (date: string) => number;
  canShowPrevious: boolean;
  canShowNext: boolean;
  onPrevious: () => void;
  onNext: () => void;
  onSelect: (date: string) => void;
}) {
  const titleId = useId();
  const buttons = useRef(new Map<string, HTMLButtonElement>());
  const bookable = page.days.filter((d) => statusOf(d) === 'open');
  const [focusDay, setFocusDay] = useState<string | null>(null);
  const [moveFocus, setMoveFocus] = useState(false);

  // The one day in the tab order: the one the arrows moved to, the picked day, or the first open one.
  const tabDay =
    (focusDay && bookable.includes(focusDay) && focusDay) || (selectedDay && bookable.includes(selectedDay) && selectedDay) || bookable[0] || null;

  useEffect(() => {
    if (moveFocus && tabDay) {
      buttons.current.get(tabDay)?.focus();
      setMoveFocus(false);
    }
  }, [moveFocus, tabDay]);

  const onKeyDown = (event: KeyboardEvent<HTMLTableElement>) => {
    if (!tabDay) return;
    const step: Record<string, number> = { ArrowRight: 1, ArrowLeft: -1, ArrowDown: 7, ArrowUp: -7 };
    let next: string | null = null;
    if (event.key in step) {
      const delta = step[event.key]!;
      // The nearest open day that way: a week down lands on the next open day on or after it.
      let day = addDays(tabDay, delta);
      while (day >= page.days[0]! && day <= page.days[page.days.length - 1]!) {
        if (bookable.includes(day)) {
          next = day;
          break;
        }
        day = addDays(day, delta > 0 ? 1 : -1);
      }
    } else if (event.key === 'Home') {
      next = bookable[0] ?? null;
    } else if (event.key === 'End') {
      next = bookable[bookable.length - 1] ?? null;
    } else {
      return;
    }
    event.preventDefault();
    if (next) {
      setFocusDay(next);
      setMoveFocus(true);
    }
  };

  const cells: (string | null)[] = [...Array<null>(page.leadingBlanks).fill(null), ...page.days];
  while (cells.length % 7 !== 0) cells.push(null);
  const weeks: (string | null)[][] = [];
  for (let i = 0; i < cells.length; i += 7) weeks.push(cells.slice(i, i + 7));

  return (
    <div className="calendar">
      <div className="calendar__header">
        <h2 id={titleId} className="calendar__title" data-testid="calendar-month">
          {page.title}
        </h2>
        <button type="button" className="calendar__nav" onClick={onPrevious} disabled={!canShowPrevious} aria-label="Previous month">
          <Icon name="chevronLeft" />
        </button>
        <button type="button" className="calendar__nav" onClick={onNext} disabled={!canShowNext} aria-label="Next month">
          <Icon name="chevronRight" />
        </button>
      </div>
      <table className="calendar__grid" aria-labelledby={titleId} onKeyDown={onKeyDown}>
        <thead>
          <tr>
            {WEEKDAY_SHORT.map((short, i) => (
              <th key={short} scope="col">
                <abbr title={WEEKDAY_NAMES[i]}>{short}</abbr>
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {weeks.map((week, w) => (
            <tr key={w}>
              {week.map((day, d) =>
                day ? (
                  <td key={day}>
                    <DayButton
                      day={day}
                      status={statusOf(day)}
                      slots={slotCount(day)}
                      isToday={day === today}
                      isSelected={day === selectedDay}
                      inTabOrder={day === tabDay}
                      onSelect={() => {
                        setFocusDay(day);
                        onSelect(day);
                      }}
                      register={(el) => {
                        if (el) buttons.current.set(day, el);
                        else buttons.current.delete(day);
                      }}
                    />
                  </td>
                ) : (
                  <td key={`blank-${w}-${d}`} aria-hidden="true" />
                ),
              )}
            </tr>
          ))}
        </tbody>
      </table>
      <p className="calendar__legend">
        <span>
          <span className="calendar__legend-dot" aria-hidden="true" />
          Days with open times
        </span>
        <span>Gray days can't be booked</span>
      </p>
      {note ? (
        <p className="calendar__note" data-testid="booking-window">
          {note}
        </p>
      ) : null}
    </div>
  );
}

const STATUS_TEXT: Record<DayStatus, string> = {
  open: '',
  noOpenings: 'no openings',
  closed: 'closed',
  past: 'past',
  tooFar: 'not open for booking yet',
  notLoaded: 'checking',
};

function DayButton({
  day,
  status,
  slots,
  isToday,
  isSelected,
  inTabOrder,
  onSelect,
  register,
}: {
  day: string;
  status: DayStatus;
  slots: number;
  isToday: boolean;
  isSelected: boolean;
  inTabOrder: boolean;
  onSelect: () => void;
  register: (el: HTMLButtonElement | null) => void;
}) {
  const open = status === 'open';
  const parts = [longDateLabel(day)];
  if (isToday) parts.push('today');
  parts.push(open ? (slots === 1 ? '1 open time' : `${slots} open times`) : STATUS_TEXT[status]);
  const classes = ['calendar__day', open ? 'is-open' : '', isToday ? 'is-today' : ''].filter(Boolean).join(' ');
  return (
    <button
      ref={register}
      type="button"
      className={classes}
      disabled={!open}
      aria-pressed={open ? isSelected : undefined}
      aria-label={parts.join(', ')}
      tabIndex={inTabOrder ? 0 : -1}
      onClick={onSelect}
      data-testid={`day-${day}`}
    >
      {parseDate(day).day}
    </button>
  );
}
