import { useEffect, useMemo, useState } from 'react';
import type { BookingTarget, Catalog, NoShowPolicy, Slot } from '../api/types';
import { useNow } from '../components/hooks';
import { CallLink, Loading, NewTabLink, Notice } from '../components/ui';
import { plural, windowLabel } from '../lib/format';
import { lateCancelNotice } from '../lib/lateCancel';
import { dateTimeLabel, dayPart, localDate, longDateLabel, monthsBetween, timeLabel, wallClock, WEEKDAY_NAMES, weekdayOf, zoneOffsetMinutes } from '../lib/shopTime';
import { useBooking, useStepNavigation } from './BookingContext';
import { Calendar } from './Calendar';
import { summarize } from './describe';
import { targetOf } from './flow';
import { BookingLayout, StepHeader } from './StepChrome';
import { useAvailability } from './useAvailability';
import { useNoShowPolicy } from './usePolicy';

/**
 * Step 3: a day and a time from the shop's live calendar. The first day with
 * openings is picked to start with. If someone else books the picked time first,
 * the client comes back here with the times checked again and a note saying so.
 */
export function TimeStep({ catalog }: { catalog: Catalog }) {
  const { draft } = useBooking();
  const target = targetOf(draft);
  if (!target) return null;
  return <TimePicker catalog={catalog} target={target} />;
}

function TimePicker({ catalog, target }: { catalog: Catalog; target: BookingTarget }) {
  const { draft, dispatch } = useBooking();
  const { goTo } = useStepNavigation('time');
  const zone = catalog.timeZone;
  const now = useNow();
  const availability = useAvailability(catalog, target, now);
  const policy = useNoShowPolicy(target);
  const summary = summarize(catalog, draft);

  const pages = useMemo(() => monthsBetween(availability.today, availability.lastDay), [availability.today, availability.lastDay]);
  const startDay = draft.start ? localDate(new Date(draft.start), zone) : null;
  const [monthId, setMonthId] = useState(() => (startDay ?? availability.today).slice(0, 7));
  const pageIndex = Math.max(0, pages.findIndex((p) => p.id === monthId));
  const page = pages[pageIndex]!;
  const [selectedDay, setSelectedDay] = useState<string | null>(startDay);
  const [pickedDay, setPickedDay] = useState(startDay !== null);
  const [lookedAhead, setLookedAhead] = useState(false);
  // Times changed while away (a time was taken): ask again for the month.
  const [reloadOnArrival] = useState(() => draft.notice !== null);

  useEffect(() => {
    if (reloadOnArrival) void availability.reload(page);
    else void availability.load(page);
    // Only when the month or the booking changes (not on every answer).
  }, [page.id, JSON.stringify(target)]);

  // Start on the first day with openings; on the first look, a month with nothing left moves on to the next.
  useEffect(() => {
    const range = availability.rangeOf(page);
    if (selectedDay && availability.statusOf(selectedDay) === 'open') {
      if (pickedDay || (range && selectedDay >= range[0] && selectedDay <= range[1])) return;
    }
    if (range) {
      const first = availability.firstOpenDay(range[0], range[1]);
      if (first) {
        setSelectedDay(first);
        return;
      }
    }
    if (!availability.isLoaded(page) || availability.error) return;
    if (selectedDay && availability.statusOf(selectedDay) !== 'notLoaded' && availability.statusOf(selectedDay) !== 'open') {
      // The picked day filled up: move on.
      setPickedDay(false);
      setSelectedDay(null);
    }
    if (!lookedAhead && !pickedDay && pageIndex < pages.length - 1) {
      setLookedAhead(true);
      setMonthId(pages[pageIndex + 1]!.id);
    }
  }, [availability, page, pageIndex, pages, pickedDay, lookedAhead, selectedDay]);

  // A picked time that isn't open any more (after checking again): drop it, and say so.
  useEffect(() => {
    if (!draft.start) return;
    const day = localDate(new Date(draft.start), zone);
    const status = availability.statusOf(day);
    if (status === 'notLoaded' || (status !== 'open' && status !== 'noOpenings')) return;
    const open = (availability.slotsByDay[day] ?? []).some((slot) => slot.start === draft.start);
    if (!open) dispatch({ type: 'timeGone', message: `${timeLabel(new Date(draft.start), zone)} is no longer available. Pick another time.` });
  }, [availability, dispatch, draft.start, zone]);

  const selectDay = (day: string) => {
    if (day === selectedDay) return;
    setPickedDay(true);
    setSelectedDay(day);
  };

  const slots = selectedDay ? (availability.slotsByDay[selectedDay] ?? []) : [];
  const groups = groupByPart(slots, zone);
  // The picked time stays picked while the client looks at other days and months; it's
  // dropped (above) only once its own day has been checked and it isn't open any more.
  const isStillOpen = (start: string): boolean => {
    const day = localDate(new Date(start), zone);
    const status = availability.statusOf(day);
    if (status === 'notLoaded') return true;
    return status === 'open' && (availability.slotsByDay[day] ?? []).some((slot) => slot.start === start);
  };
  const picked = draft.start && isStillOpen(draft.start) ? draft.start : null;
  const zoneNote = zoneOffsetMinutes(new Date(picked ?? now), zone) !== -new Date(picked ?? now).getTimezoneOffset();

  return (
    <BookingLayout catalog={catalog}>
      <StepHeader
        step="time"
        title="Pick a day and time"
        subtitle={`${summary.serviceName ?? ''} ${summary.isAnyBarber ? 'with any barber' : `with ${summary.barberName ?? ''}`} · ${summary.priceLabel ?? ''} · ${summary.durationLabel ?? ''}`}
      />

      {policy.state.status === 'ready' ? <FeeWarning policy={policy.state.policy} start={picked} now={now} /> : null}

      {draft.notice ? (
        <Notice tone="info" role="alert" testId="time-notice">
          <p>{draft.notice}</p>
        </Notice>
      ) : null}

      <Calendar
        page={page}
        today={availability.today}
        selectedDay={selectedDay}
        statusOf={availability.statusOf}
        slotCount={(day) => availability.slotsByDay[day]?.length ?? 0}
        canShowPrevious={pageIndex > 0}
        canShowNext={pageIndex < pages.length - 1}
        onPrevious={() => setMonthId(pages[pageIndex - 1]!.id)}
        onNext={() => setMonthId(pages[pageIndex + 1]!.id)}
        onSelect={selectDay}
        note={bookingWindowNote(catalog)}
      />

      {/* One short line for screen readers when the day changes, not every time read out. */}
      <p className="visually-hidden" role="status" data-testid="times-status">
        {selectedDay && availability.statusOf(selectedDay) === 'open' ? `${plural(slots.length, 'open time')} on ${longDateLabel(selectedDay)}.` : ''}
      </p>
      <section className="times" aria-labelledby="times-title">
        {selectedDay && availability.statusOf(selectedDay) === 'open' ? (
          <>
            <h2 id="times-title" className="times__day">
              {longDateLabel(selectedDay)}
            </h2>
            {groups.map((group) => (
              <div key={group.part} className="time-group">
                <h3 className="time-group__title">{group.part}</h3>
                <ul className="time-chips">
                  {group.slots.map((slot) => (
                    <li key={slot.start}>
                      <button
                        type="button"
                        className="time-chip"
                        aria-pressed={slot.start === picked}
                        onClick={() => dispatch({ type: 'chooseTime', start: slot.start })}
                        data-testid={`time-${slot.start}`}
                      >
                        {timeLabel(new Date(slot.start), zone)}
                      </button>
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </>
        ) : (
          <>
            <h2 id="times-title" className="visually-hidden">
              Times
            </h2>
            <NoTimes
              loading={availability.loading || !availability.isLoaded(page)}
              error={availability.error}
              onRetry={() => void availability.reload(page)}
              selectedDay={selectedDay}
              status={selectedDay ? availability.statusOf(selectedDay) : null}
              monthTitle={page.title}
              hasNextMonth={pageIndex < pages.length - 1}
              windowDays={catalog.windowDays}
              onNextMonth={() => setMonthId(pages[pageIndex + 1]!.id)}
            />
          </>
        )}
      </section>

      {zoneNote ? <p className="secondary">Times are in Oceanside time (Pacific), where the shop is.</p> : null}

      <div className="step-actions">
        <button type="button" className="button button--primary button--large step-actions__continue" disabled={!picked} onClick={() => goTo('details')}>
          Continue
        </button>
        <p className="step-actions__note" aria-live="polite">
          {picked ? dateTimeLabel(new Date(picked), zone) : 'Pick a time first.'}
        </p>
      </div>
    </BookingLayout>
  );
}

/**
 * How far ahead, and how soon before a time, the shop takes bookings online (the Terms: "The
 * booking screens tell you when a limit applies"), from the catalog the server applies them with:
 * "We take bookings up to 60 days ahead, for times at least 30 minutes away. For anything sooner,
 * call the shop."
 */
export function bookingWindowNote(catalog: Pick<Catalog, 'windowDays' | 'leadTimeMinutes'>): string {
  const soonest = catalog.leadTimeMinutes > 0 ? `, for times at least ${windowLabel(catalog.leadTimeMinutes)} away. For anything sooner, call the shop.` : '.';
  return `We take bookings up to ${catalog.windowDays} days ahead${soonest}`;
}

/** The no-show notice from the shop's policy, when this booking needs a card: hard to miss. */
export function FeeWarning({ policy, start, now }: { policy: NoShowPolicy; start: string | null; now: Date }) {
  if (!policy.required || !policy.warning) return null;
  const inside = start ? lateCancelNotice(policy, new Date(start), now) : null;
  return (
    <Notice tone="warning" title={policy.warning.title} testId="fee-warning">
      <p>{policy.warning.message}</p>
      {/* The shop's words are written for the app too; the website's own cancelling is the same thing. */}
      <p>Cancelling on this website, under My appointments, works the same as cancelling in the app.</p>
      {inside ? <p className="notice__strong">{inside}</p> : null}
      {/* The whole policy, in a new tab: the booking stays where it is. */}
      <p>
        <NewTabLink href="/cancellation-policy" testId="fee-policy-link">
          Read the Cancellation & No-Show Policy
        </NewTabLink>
      </p>
    </Notice>
  );
}

function groupByPart(slots: Slot[], zone: string) {
  const groups: { part: ReturnType<typeof dayPart>; slots: Slot[] }[] = [];
  for (const slot of slots) {
    const part = dayPart(wallClock(new Date(slot.start), zone).hour);
    let group = groups.find((g) => g.part === part);
    if (!group) groups.push((group = { part, slots: [] }));
    group.slots.push(slot);
  }
  return groups;
}

function NoTimes({
  loading,
  error,
  onRetry,
  selectedDay,
  status,
  monthTitle,
  hasNextMonth,
  windowDays,
  onNextMonth,
}: {
  loading: boolean;
  error: string | null;
  onRetry: () => void;
  selectedDay: string | null;
  status: string | null;
  monthTitle: string;
  hasNextMonth: boolean;
  windowDays: number;
  onNextMonth: () => void;
}) {
  if (error) {
    return (
      <Notice
        tone="error"
        title="Couldn't load the times"
        role="alert"
        actions={
          <>
            <button type="button" className="button button--primary" onClick={onRetry}>
              Try again
            </button>
            <CallLink className="button button--secondary">Call the shop</CallLink>
          </>
        }
      >
        <p>{error}</p>
      </Notice>
    );
  }
  if (loading) return <Loading text="Checking open times…" />;
  let text: string;
  if (selectedDay && status === 'noOpenings') text = 'No openings left on this day. Pick another day.';
  else if (selectedDay && status === 'closed') text = `The shop is closed on ${WEEKDAY_NAMES[weekdayOf(selectedDay) - 1]}s. Pick another day.`;
  else if (hasNextMonth) text = `No openings left in ${monthTitle}. Try next month.`;
  else text = `No openings left in the next ${windowDays} days. Give the shop a call and they'll find you a time.`;
  return (
    <div className="no-times card card--gray">
      <p>{text}</p>
      <div className="actions">
        {hasNextMonth && !selectedDay ? (
          <button type="button" className="button button--secondary" onClick={onNextMonth}>
            Show next month
          </button>
        ) : null}
        <CallLink className="button button--secondary">Call the shop</CallLink>
      </div>
    </div>
  );
}
