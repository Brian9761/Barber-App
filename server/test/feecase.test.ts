import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import {
  cancelledLate,
  cancellingIsLate,
  COMPLETED_MESSAGE,
  FEE_DEADLINE_DAYS,
  FEE_DEADLINE_MESSAGE,
  FEE_KIND,
  feeCase,
  feeCaseAt,
  feeDeadline,
  isFeeKind,
  isFullPrice,
  LATE_CANCEL_GRACE_MINUTES,
  lateCancelWarning,
  MARK_NO_SHOW_MESSAGE,
  money,
  NOT_ENDED_MESSAGE,
  nothingCharged,
  pastFeeDeadline,
  reasonOfKind,
  windowLabel,
} from '../src/feecase.js';
import type { AppointmentRow } from '../src/serialize.js';
import { wholeSecond } from '../src/time.js';

// Which fee a booking with a card on file can be charged: a no-show, a late
// cancellation, or none (and why). The cases are also written to
// test/fixtures/fee-cases.json, which the Kit's tests read to check its mirror
// (used by the apps to show the charge button, and by the fakes to answer like
// the server).

const START = new Date('2026-11-03T18:00:00Z');
/** A 45-minute appointment. */
const END = new Date('2026-11-03T18:45:00Z');
/** Booked two days ahead, unless a case says otherwise. */
const BOOKED = new Date('2026-11-01T18:00:00Z');
const minutesBefore = (m: number) => new Date(START.getTime() - m * 60_000);
const minutesAfter = (at: Date, m: number) => new Date(at.getTime() + m * 60_000);
const DAY_MINUTES = 24 * 60;

type Terms = Parameters<typeof feeCaseAt>[0];
const booking = (changes: Partial<Terms> = {}): Terms => ({
  status: 'booked',
  cancelled_by: null,
  start_at: START,
  end_at: END,
  created_at: BOOKED,
  saved_card_id: '00000000-0000-4000-8000-0000000000c1',
  no_show_fee_cents: 3500,
  late_cancel_window_minutes: 60,
  customer_cancelled_at: null,
  ...changes,
});
/** Booked `bookedBefore` minutes before the start (inside the window when that's less than 60), cancelled `after` minutes later. */
const bookedLate = (bookedBefore: number, after: number, changes: Partial<Terms> = {}) =>
  booking({
    status: 'cancelled',
    cancelled_by: 'customer',
    created_at: minutesBefore(bookedBefore),
    customer_cancelled_at: minutesBefore(bookedBefore - after),
    ...changes,
  });
const byClient = (minutes: number, changes: Partial<Terms> = {}) =>
  booking({ status: 'cancelled', cancelled_by: 'customer', customer_cancelled_at: minutesBefore(minutes), ...changes });
/** Cancelled by the client `ms` milliseconds before the start, kept as the server keeps it: to the whole second. */
const byClientMsBefore = (ms: number) =>
  booking({ status: 'cancelled', cancelled_by: 'customer', customer_cancelled_at: wholeSecond(new Date(START.getTime() - ms)) });

const CASES: { name: string; row: Terms; reason: AppointmentRow['no_show_fee_reason']; refusal: string | null }[] = [
  { name: 'booked', row: booking(), reason: null, refusal: 'Mark the appointment as a no-show first.' },
  // The client came: a completed booking with a card on file can't become a no-show.
  { name: 'completed', row: booking({ status: 'completed' }), reason: null, refusal: "The appointment is marked completed, so there's no fee to charge." },
  { name: 'a no-show', row: booking({ status: 'no_show' }), reason: 'no_show', refusal: null },
  { name: 'a no-show, booked without late cancellations', row: booking({ status: 'no_show', late_cancel_window_minutes: null }), reason: 'no_show', refusal: null },
  { name: 'cancelled 30 minutes before', row: byClient(30), reason: 'late_cancel', refusal: null },
  { name: 'cancelled 1 minute before', row: byClient(1), reason: 'late_cancel', refusal: null },
  { name: 'cancelled 59 minutes before', row: byClient(59), reason: 'late_cancel', refusal: null },
  { name: 'cancelled exactly 1 hour before', row: byClient(60), reason: null, refusal: "The client cancelled at least 1 hour before, so there's no fee." },
  {
    name: 'cancelled 400 ms inside the window, kept to the second: exactly 1 hour before',
    row: byClientMsBefore(60 * 60_000 - 400),
    reason: null,
    refusal: "The client cancelled at least 1 hour before, so there's no fee.",
  },
  { name: 'cancelled 1 second inside the window', row: byClientMsBefore(60 * 60_000 - 1_000), reason: 'late_cancel', refusal: null },
  { name: 'cancelled 2 hours before', row: byClient(120), reason: null, refusal: "The client cancelled at least 1 hour before, so there's no fee." },
  {
    name: 'cancelled 2 hours before, with a 3-hour window',
    row: byClient(120, { late_cancel_window_minutes: 180 }),
    reason: 'late_cancel',
    refusal: null,
  },
  {
    name: 'cancelled 45 minutes before, with a 30-minute window',
    row: byClient(45, { late_cancel_window_minutes: 30 }),
    reason: null,
    refusal: "The client cancelled at least 30 minutes before, so there's no fee.",
  },
  {
    name: 'cancelled 90 minutes before, with a 90-minute window',
    row: byClient(90, { late_cancel_window_minutes: 90 }),
    reason: null,
    refusal: "The client cancelled at least 90 minutes before, so there's no fee.",
  },
  {
    name: 'cancelled 5 minutes before, booked without late cancellations',
    row: byClient(5, { late_cancel_window_minutes: null }),
    reason: null,
    refusal: "The client cancelled this booking in the app, so there's no fee.",
  },
  {
    name: 'cancelled late, then reopened by the shop',
    row: booking({ customer_cancelled_at: minutesBefore(10) }),
    reason: null,
    refusal: "The client cancelled this booking in the app, so there's no fee.",
  },
  {
    name: 'cancelled late, reopened, then marked a no-show',
    row: booking({ status: 'no_show', customer_cancelled_at: minutesBefore(10) }),
    reason: null,
    refusal: "The client cancelled this booking in the app, so there's no fee.",
  },
  {
    name: 'cancelled early, reopened, then marked a no-show',
    row: booking({ status: 'no_show', customer_cancelled_at: minutesBefore(600) }),
    reason: null,
    refusal: "The client cancelled this booking in the app, so there's no fee.",
  },
  { name: 'cancelled by the shop', row: booking({ status: 'cancelled', cancelled_by: 'shop' }), reason: null, refusal: "The shop cancelled this booking, so there's no fee." },
  {
    name: 'cancelled late by the client, then again by the shop',
    row: booking({ status: 'cancelled', cancelled_by: 'shop', customer_cancelled_at: minutesBefore(10) }),
    reason: null,
    refusal: "The shop cancelled this booking, so there's no fee.",
  },
  {
    name: 'cancelled by the client with no time kept',
    row: booking({ status: 'cancelled', cancelled_by: 'customer' }),
    reason: null,
    refusal: "The client cancelled this booking in the app, so there's no fee.",
  },
  {
    name: 'completed after the client asked to cancel',
    row: booking({ status: 'completed', customer_cancelled_at: minutesBefore(5) }),
    reason: null,
    refusal: "The client cancelled this booking in the app, so there's no fee.",
  },
  // The 15-minute grace period: a time booked inside the window (30 minutes before, with a 1-hour
  // window) is free to cancel for 15 minutes after booking, and late after that.
  {
    name: 'booked inside the window, cancelled 14 minutes after booking',
    row: bookedLate(30, 14),
    reason: null,
    refusal: "The client cancelled within 15 minutes of booking, so there's no fee.",
  },
  {
    name: 'booked inside the window, cancelled exactly 15 minutes after booking',
    row: bookedLate(30, 15),
    reason: null,
    refusal: "The client cancelled within 15 minutes of booking, so there's no fee.",
  },
  { name: 'booked inside the window, cancelled 16 minutes after booking', row: bookedLate(30, 16), reason: 'late_cancel', refusal: null },
  {
    name: 'booked inside a 48-hour window, cancelled 16 minutes after booking',
    row: bookedLate(24 * 60, 16, { late_cancel_window_minutes: 2880 }),
    reason: 'late_cancel',
    refusal: null,
  },
  {
    name: 'booked just before the window, cancelled 10 minutes later, inside it',
    row: bookedLate(65, 10),
    reason: null,
    refusal: "The client cancelled within 15 minutes of booking, so there's no fee.",
  },
  {
    name: 'booked inside the window, cancelled 5 minutes later, then reopened and marked a no-show',
    row: bookedLate(30, 5, { status: 'no_show', cancelled_by: null }),
    reason: null,
    refusal: "The client cancelled this booking in the app, so there's no fee.",
  },
];

/** Which fee can be charged at a given moment: the end of the appointment and the 7-day deadline. */
const DEADLINE_MINUTES = FEE_DEADLINE_DAYS * DAY_MINUTES;
const CLOCK_CASES: { name: string; row: Terms; now: Date; reason: AppointmentRow['no_show_fee_reason']; refusal: string | null }[] = [
  { name: 'a no-show, 1 minute before the end', row: booking({ status: 'no_show' }), now: minutesAfter(END, -1), reason: null, refusal: NOT_ENDED_MESSAGE },
  { name: 'a no-show, right at the start', row: booking({ status: 'no_show' }), now: START, reason: null, refusal: NOT_ENDED_MESSAGE },
  { name: 'a no-show, at the end', row: booking({ status: 'no_show' }), now: END, reason: 'no_show', refusal: null },
  { name: 'a no-show, 1 minute after the end', row: booking({ status: 'no_show' }), now: minutesAfter(END, 1), reason: 'no_show', refusal: null },
  {
    name: 'a no-show, 7 days after the start less 1 minute',
    row: booking({ status: 'no_show' }),
    now: minutesAfter(START, DEADLINE_MINUTES - 1),
    reason: 'no_show',
    refusal: null,
  },
  { name: 'a no-show, exactly 7 days after the start', row: booking({ status: 'no_show' }), now: minutesAfter(START, DEADLINE_MINUTES), reason: 'no_show', refusal: null },
  {
    name: 'a no-show, 7 days and 1 minute after the start',
    row: booking({ status: 'no_show' }),
    now: minutesAfter(START, DEADLINE_MINUTES + 1),
    reason: null,
    refusal: FEE_DEADLINE_MESSAGE,
  },
  { name: 'a late cancellation, before the start', row: byClient(30), now: minutesBefore(29), reason: 'late_cancel', refusal: null },
  {
    name: 'a late cancellation, 7 days after the start less 1 minute',
    row: byClient(30),
    now: minutesAfter(START, DEADLINE_MINUTES - 1),
    reason: 'late_cancel',
    refusal: null,
  },
  {
    name: 'a late cancellation, 7 days and 1 minute after the start',
    row: byClient(30),
    now: minutesAfter(START, DEADLINE_MINUTES + 1),
    reason: null,
    refusal: FEE_DEADLINE_MESSAGE,
  },
  { name: 'still booked, after the end', row: booking(), now: minutesAfter(END, 1), reason: null, refusal: MARK_NO_SHOW_MESSAGE },
  {
    name: 'still booked, 7 days and 1 minute after the start',
    row: booking(),
    now: minutesAfter(START, DEADLINE_MINUTES + 1),
    reason: null,
    refusal: FEE_DEADLINE_MESSAGE,
  },
  {
    name: 'cancelled by the shop, after the deadline',
    row: booking({ status: 'cancelled', cancelled_by: 'shop' }),
    now: minutesAfter(START, DEADLINE_MINUTES + 1),
    reason: null,
    refusal: "The shop cancelled this booking, so there's no fee.",
  },
  {
    name: 'completed, after the deadline',
    row: booking({ status: 'completed' }),
    now: minutesAfter(START, DEADLINE_MINUTES + 1),
    reason: null,
    refusal: COMPLETED_MESSAGE,
  },
  {
    name: 'booked inside the window, cancelled 16 minutes later, after the start',
    row: bookedLate(30, 16),
    now: minutesAfter(END, 5),
    reason: 'late_cancel',
    refusal: null,
  },
];

describe('which fee a booking can be charged', () => {
  for (const c of CASES) {
    it(c.name, () => {
      expect(feeCase(c.row)).toEqual({ reason: c.reason, refusal: c.refusal });
      // A late-cancellation fee always means the client cancelled inside the window.
      if (c.reason === 'late_cancel') expect(cancelledLate(c.row)).toBe(true);
    });
  }

  it('cancelledLate is only about when the client cancelled, whatever happened since', () => {
    expect(cancelledLate(booking({ customer_cancelled_at: minutesBefore(10) }))).toBe(true);
    expect(cancelledLate(booking({ status: 'cancelled', cancelled_by: 'shop', customer_cancelled_at: minutesBefore(10) }))).toBe(true);
    expect(cancelledLate(byClient(60))).toBe(false);
    expect(cancelledLate(byClient(59))).toBe(true);
    expect(cancelledLate(byClient(10, { late_cancel_window_minutes: null }))).toBe(false);
    expect(cancelledLate(booking())).toBe(false);
  });

  it('a cancel time is decided as it is kept and written, to the second', () => {
    // 59 min 59.6 s before is late by the millisecond, but the JSON (which the apps decide from)
    // says exactly 1 hour before: the server keeps it to the whole second, so it's free for everyone.
    const exact = new Date(START.getTime() - (60 * 60_000 - 400));
    expect(cancelledLate(booking({ status: 'cancelled', cancelled_by: 'customer', customer_cancelled_at: exact }))).toBe(true);
    expect(cancelledLate(byClientMsBefore(60 * 60_000 - 400))).toBe(false);
    expect(cancelledLate(byClientMsBefore(60 * 60_000 - 1_000))).toBe(true);
  });

  it('cancelling within 15 minutes of booking is free: the grace period', () => {
    expect(LATE_CANCEL_GRACE_MINUTES).toBe(15);
    expect(cancelledLate(bookedLate(30, 14))).toBe(false);
    expect(cancelledLate(bookedLate(30, 15))).toBe(false);
    expect(cancelledLate(bookedLate(30, 16))).toBe(true);
    // To the second: 15 minutes and 1 second after booking is late.
    expect(cancelledLate({ ...bookedLate(30, 15), customer_cancelled_at: new Date(minutesBefore(15).getTime() + 1_000) })).toBe(true);
    // Booked well before the window: the grace period is long over when the window starts.
    expect(cancelledLate(byClient(59))).toBe(true);
  });

  it('a booking without a card on file is never a late cancellation', () => {
    expect(cancelledLate(byClient(10, { saved_card_id: null, no_show_fee_cents: null, late_cancel_window_minutes: null }))).toBe(false);
    expect(cancelledLate(byClient(10, { no_show_fee_cents: null }))).toBe(false);
  });

  it('names the payment kinds', () => {
    expect(FEE_KIND).toEqual({ no_show: 'no_show_fee', late_cancel: 'late_cancel_fee' });
    expect(['no_show_fee', 'late_cancel_fee'].every(isFeeKind)).toBe(true);
    expect([null, undefined, '', 'in_person', 'no_show', 'NO_SHOW_FEE'].some(isFeeKind)).toBe(false);
    expect(reasonOfKind('late_cancel_fee')).toBe('late_cancel');
    expect(reasonOfKind('no_show_fee')).toBe('no_show');
    expect(windowLabel(60)).toBe('1 hour');
  });
});

describe('which fee can be charged now: the end of the appointment and the 7-day deadline', () => {
  for (const c of CLOCK_CASES) {
    it(c.name, () => {
      expect(feeCaseAt(c.row, c.now)).toEqual({ reason: c.reason, refusal: c.refusal });
    });
  }

  it('the deadline is 7 days of 24 hours after the start, and exactly then still counts', () => {
    expect(feeDeadline(START)).toEqual(new Date('2026-11-10T18:00:00Z'));
    expect(pastFeeDeadline(START, new Date('2026-11-10T18:00:00Z'))).toBe(false);
    expect(pastFeeDeadline(START, new Date('2026-11-10T18:00:01Z'))).toBe(true);
    expect(FEE_DEADLINE_MESSAGE).toBe("It's more than 7 days after the appointment, so the fee can't be charged.");
  });
});

describe('cancelling now', () => {
  it('is free within 15 minutes of booking, even inside the window', () => {
    // Booked 30 minutes before a 1-hour window's start: inside it already.
    const inside = booking({ created_at: minutesBefore(30) });
    expect(cancellingIsLate(inside, minutesBefore(29))).toBe(false);
    expect(cancellingIsLate(inside, minutesBefore(16))).toBe(false); // 14 minutes after booking
    expect(cancellingIsLate(inside, minutesBefore(15))).toBe(false); // exactly 15
    expect(cancellingIsLate(inside, minutesBefore(14))).toBe(true); // 16 minutes after booking
  });

  it('is late inside the agreed window, counting from the first time the client cancelled or asked to', () => {
    const free = booking();
    expect(cancellingIsLate(free, minutesBefore(61))).toBe(false);
    expect(cancellingIsLate(free, minutesBefore(60))).toBe(false);
    expect(cancellingIsLate(free, minutesBefore(59))).toBe(true);
    expect(cancellingIsLate(free, minutesBefore(1))).toBe(true);
    // Cancelled early before (then reopened by the shop): that time counts, so it stays free.
    expect(cancellingIsLate(booking({ customer_cancelled_at: minutesBefore(600) }), minutesBefore(5))).toBe(false);
    // Asked inside the window before (the shop had marked it), so it's late whenever it goes through.
    expect(cancellingIsLate(booking({ customer_cancelled_at: minutesBefore(30) }), minutesBefore(20))).toBe(true);
    // No late cancellations in the agreed policy, or no card on file: always free.
    expect(cancellingIsLate(booking({ late_cancel_window_minutes: null }), minutesBefore(5))).toBe(false);
    expect(cancellingIsLate(booking({ saved_card_id: null, no_show_fee_cents: null, late_cancel_window_minutes: null }), minutesBefore(5))).toBe(false);
    // A longer window agreed at booking.
    expect(cancellingIsLate(booking({ late_cancel_window_minutes: 180 }), minutesBefore(120))).toBe(true);
  });

  it('warns with the agreed fee, and says when it is the full service price', () => {
    expect(isFullPrice({ no_show_fee_cents: 3500, price_cents: 3500 })).toBe(true);
    expect(isFullPrice({ no_show_fee_cents: 1750, price_cents: 3500 })).toBe(false);
    expect(isFullPrice({ no_show_fee_cents: 2500, price_cents: 1600 })).toBe(false);
    expect(isFullPrice({ no_show_fee_cents: null, price_cents: 3500 })).toBe(false);
    expect(isFullPrice({ no_show_fee_cents: null, price_cents: 0 })).toBe(false);
    expect(lateCancelWarning(60, 3500, true)).toBe('Cancelling now, less than 1 hour before your appointment, may be charged $35, the full service price.');
    expect(lateCancelWarning(60, 1750, false)).toBe('Cancelling now, less than 1 hour before your appointment, may be charged $17.50.');
    expect(lateCancelWarning(90, 2500, false)).toBe('Cancelling now, less than 90 minutes before your appointment, may be charged $25.');
    expect(lateCancelWarning(2880, 8000, true)).toBe('Cancelling now, less than 48 hours before your appointment, may be charged $80, the full service price.');
    expect([money(2000), money(1750), money(5)]).toEqual(['$20', '$17.50', '$0.05']);
  });

  it('a lost try settled as not charged says so, then why there is no fee now', () => {
    expect(nothingCharged('Mark the appointment as a no-show first.')).toBe('Nothing was charged. Mark the appointment as a no-show first.');
  });
});

/** The warnings the Kit's mirror is checked against (window, fee, full price). */
const WARNINGS: [number, number, boolean][] = [
  [30, 3500, true],
  [60, 3500, true],
  [60, 1750, false],
  [60, 2005, false],
  [90, 2500, false],
  [120, 4000, true],
  [180, 50, false],
  [2880, 8000, true],
];

describe('test/fixtures/fee-cases.json (read by the Kit)', () => {
  it('lists every case, as the apps see a booking, and is up to date', () => {
    const iso = (d: Date | null) => (d ? d.toISOString().replace(/\.\d{3}Z$/, 'Z') : null);
    const STATUS = { booked: 'booked', cancelled: 'cancelled', completed: 'completed', no_show: 'noShow' } as const;
    const REASON = { no_show: 'noShow', late_cancel: 'lateCancel' } as const;
    const document = {
      cases: CASES.map((c) => ({
        name: c.name,
        status: STATUS[c.row.status],
        cancelledBy: c.row.cancelled_by,
        start: iso(c.row.start_at),
        end: iso(c.row.end_at),
        createdAt: iso(c.row.created_at),
        customerCancelledAt: iso(c.row.customer_cancelled_at),
        lateCancelWindowMinutes: c.row.late_cancel_window_minutes,
        reason: c.reason ? REASON[c.reason] : null,
        refusal: c.refusal,
        // Whether the client's cancel time (if any) was inside the agreed window and after the grace period, whatever happened since.
        cancelledLate: cancelledLate(c.row),
      })),
      // The same rule at a given moment (`feeCaseAt`): what the server answers a charge then.
      clock: CLOCK_CASES.map((c) => ({
        name: c.name,
        status: STATUS[c.row.status],
        cancelledBy: c.row.cancelled_by,
        start: iso(c.row.start_at),
        end: iso(c.row.end_at),
        createdAt: iso(c.row.created_at),
        customerCancelledAt: iso(c.row.customer_cancelled_at),
        lateCancelWindowMinutes: c.row.late_cancel_window_minutes,
        now: iso(c.now),
        reason: c.reason ? REASON[c.reason] : null,
        refusal: c.refusal,
      })),
      notEnded: NOT_ENDED_MESSAGE,
      deadline: { days: FEE_DEADLINE_DAYS, message: FEE_DEADLINE_MESSAGE },
      graceMinutes: LATE_CANCEL_GRACE_MINUTES,
      nothingCharged: { refusal: CASES[0]!.refusal, message: nothingCharged(CASES[0]!.refusal ?? '') },
      cancelWarnings: WARNINGS.map(([lateCancelWindowMinutes, amountCents, fullPrice]) => ({
        lateCancelWindowMinutes,
        amountCents,
        fullPrice,
        warning: lateCancelWarning(lateCancelWindowMinutes, amountCents, fullPrice),
      })),
    };
    const file = new URL('./fixtures/fee-cases.json', import.meta.url);
    const text = `${JSON.stringify(document, null, 2)}\n`;
    if (process.env.UPDATE_CONTRACT_FIXTURES === '1' || !existsSync(file)) writeFileSync(file, text);
    expect(JSON.parse(readFileSync(file, 'utf8')), 'fee-cases.json is out of date: run UPDATE_CONTRACT_FIXTURES=1 npm test').toEqual(document);
  });
});
