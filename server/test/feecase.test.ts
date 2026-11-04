import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { cancelledLate, FEE_KIND, feeCase, isFeeKind, reasonOfKind, windowLabel } from '../src/feecase.js';
import type { AppointmentRow } from '../src/serialize.js';

// Which fee a booking with a card on file can be charged: a no-show, a late
// cancellation, or none (and why). The cases are also written to
// test/fixtures/fee-cases.json, which the Kit's tests read to check its mirror
// (used by the apps to show the charge button, and by the fakes to answer like
// the server).

const START = new Date('2026-11-03T18:00:00Z');
const minutesBefore = (m: number) => new Date(START.getTime() - m * 60_000);

type Terms = Parameters<typeof feeCase>[0];
const booking = (changes: Partial<Terms> = {}): Terms => ({
  status: 'booked',
  cancelled_by: null,
  start_at: START,
  saved_card_id: '00000000-0000-4000-8000-0000000000c1',
  no_show_fee_cents: 3500,
  late_cancel_window_minutes: 60,
  customer_cancelled_at: null,
  ...changes,
});
const byClient = (minutes: number, changes: Partial<Terms> = {}) =>
  booking({ status: 'cancelled', cancelled_by: 'customer', customer_cancelled_at: minutesBefore(minutes), ...changes });

const CASES: { name: string; row: Terms; reason: AppointmentRow['no_show_fee_reason']; refusal: string | null }[] = [
  { name: 'booked', row: booking(), reason: null, refusal: 'Mark the appointment as a no-show first.' },
  { name: 'completed', row: booking({ status: 'completed' }), reason: null, refusal: 'Mark the appointment as a no-show first.' },
  { name: 'a no-show', row: booking({ status: 'no_show' }), reason: 'no_show', refusal: null },
  { name: 'a no-show, booked without late cancellations', row: booking({ status: 'no_show', late_cancel_window_minutes: null }), reason: 'no_show', refusal: null },
  { name: 'cancelled 30 minutes before', row: byClient(30), reason: 'late_cancel', refusal: null },
  { name: 'cancelled 1 minute before', row: byClient(1), reason: 'late_cancel', refusal: null },
  { name: 'cancelled 59 minutes before', row: byClient(59), reason: 'late_cancel', refusal: null },
  { name: 'cancelled exactly 1 hour before', row: byClient(60), reason: null, refusal: "The client cancelled at least 1 hour before, so there's no fee." },
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
        customerCancelledAt: iso(c.row.customer_cancelled_at),
        lateCancelWindowMinutes: c.row.late_cancel_window_minutes,
        reason: c.reason ? REASON[c.reason] : null,
        refusal: c.refusal,
      })),
      notStarted: "The appointment hasn't started yet, so it can't be a no-show.",
    };
    const file = new URL('./fixtures/fee-cases.json', import.meta.url);
    const text = `${JSON.stringify(document, null, 2)}\n`;
    if (process.env.UPDATE_CONTRACT_FIXTURES === '1' || !existsSync(file)) writeFileSync(file, text);
    expect(JSON.parse(readFileSync(file, 'utf8')), 'fee-cases.json is out of date: run UPDATE_CONTRACT_FIXTURES=1 npm test').toEqual(document);
  });
});
