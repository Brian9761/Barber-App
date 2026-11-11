import { describe, expect, it } from 'vitest';
import feeCases from '../../../test/fixtures/fee-cases.json';
import noShowRule from '../../../test/fixtures/no-show-rule.json';
import lateCancelFee from '../../../test/fixtures/contract/errors/late_cancel_fee.json';
import { fixtureAppointment, policy35 } from '../test/api';
import type { Appointment } from '../api/types';
import {
  cancelledLate,
  feeLabel,
  isCancellable,
  LATE_CANCEL_GRACE_MINUTES,
  lateCancelNotice,
  lateCancelNoticeText,
  lateCancelWarning,
  lateCancelWarningText,
  wholeSecond,
} from './lateCancel';

// Flowxbori's haircut at 10 AM on Tuesday, November 3, 2026, $35 with a Visa on
// file and a 1-hour window.
const at = (iso: string) => new Date(iso);
const withFee = (fee: Partial<NonNullable<Appointment['noShowFee']>>, changes: Partial<Appointment> = {}): Appointment => ({
  ...fixtureAppointment,
  ...changes,
  noShowFee: { ...fixtureAppointment.noShowFee!, ...fee },
});

describe('a late cancellation, decided like the server', () => {
  it.each(feeCases.cases.map((c) => [c.name, c] as const))('%s', (_name, c) => {
    expect(
      cancelledLate(at(c.start), c.customerCancelledAt ? at(c.customerCancelledAt) : null, c.lateCancelWindowMinutes, at(c.createdAt)),
    ).toBe(c.cancelledLate);
  });

  it('is never late within 15 minutes of booking, as the server rules (no-show-rule.json)', () => {
    expect(LATE_CANCEL_GRACE_MINUTES).toBe(noShowRule.graceMinutes);
    expect(LATE_CANCEL_GRACE_MINUTES).toBe(feeCases.graceMinutes);
    for (const c of noShowRule.lateCancels) {
      expect(cancelledLate(at(c.start), at(c.cancelledAt), c.lateCancelWindowMinutes, at(c.createdAt)), JSON.stringify(c)).toBe(c.late);
    }
  });

  it('counts the grace period only for a booking it knows the time of', () => {
    // Booked at 9:30 for 10 AM, cancelled at 9:40: free, but not for a time that isn't booked yet.
    expect(cancelledLate(at('2026-11-03T18:00:00Z'), at('2026-11-03T17:40:00Z'), 60, at('2026-11-03T17:30:00Z'))).toBe(false);
    expect(cancelledLate(at('2026-11-03T18:00:00Z'), at('2026-11-03T17:40:00Z'), 60)).toBe(true);
    // A booking time that can't be read counts no grace period.
    expect(cancelledLate(at('2026-11-03T18:00:00Z'), at('2026-11-03T17:40:00Z'), 60, new Date('not a date'))).toBe(true);
  });
});

describe('the warning before cancelling', () => {
  it.each(feeCases.cancelWarnings.map((w) => [w.warning, w] as const))('reads "%s"', (warning, w) => {
    expect(lateCancelWarningText(w.lateCancelWindowMinutes, w.amountCents, w.fullPrice)).toBe(warning);
  });

  it('shows only inside the window the client agreed to, and only with a card on file', () => {
    expect(lateCancelWarning(fixtureAppointment, at('2026-11-03T16:59:00Z'))).toBeNull(); // 61 minutes before
    expect(lateCancelWarning(fixtureAppointment, at('2026-11-03T17:00:00Z'))).toBeNull(); // exactly 1 hour: still free
    expect(lateCancelWarning(fixtureAppointment, at('2026-11-03T17:01:00Z'))).toBe(lateCancelFee.error.message);
    expect(lateCancelWarning(fixtureAppointment, at('2026-11-03T17:59:00Z'))).toBe(lateCancelFee.error.message);
    // Started, not booked, no card, or no late cancellations in what was agreed: nothing to warn about.
    expect(lateCancelWarning(fixtureAppointment, at('2026-11-03T18:00:00Z'))).toBeNull();
    expect(lateCancelWarning({ ...fixtureAppointment, status: 'cancelled' }, at('2026-11-03T17:30:00Z'))).toBeNull();
    expect(lateCancelWarning({ ...fixtureAppointment, card: null }, at('2026-11-03T17:30:00Z'))).toBeNull();
    expect(lateCancelWarning({ ...fixtureAppointment, noShowFee: null }, at('2026-11-03T17:30:00Z'))).toBeNull();
    expect(lateCancelWarning(withFee({ lateCancelWindowMinutes: null }), at('2026-11-03T17:30:00Z'))).toBeNull();
  });

  it('says nothing within 15 minutes of booking, even inside the window', () => {
    // Booked at 9:30 for 10 AM (inside the 1-hour window).
    const late = { ...fixtureAppointment, createdAt: '2026-11-03T17:30:00Z' };
    expect(lateCancelWarning(late, at('2026-11-03T17:44:00Z'))).toBeNull();
    expect(lateCancelWarning(late, at('2026-11-03T17:45:00Z'))).toBeNull(); // exactly 15 minutes: still free
    expect(lateCancelWarning(late, at('2026-11-03T17:45:00.900Z'))).toBeNull(); // the server counts whole seconds
    expect(lateCancelWarning(late, at('2026-11-03T17:45:01Z'))).toBe(lateCancelFee.error.message);
    expect(lateCancelWarning(late, at('2026-11-03T17:46:00Z'))).toBe(lateCancelFee.error.message);
  });

  it('reads the time to the whole second, as the server keeps it', () => {
    // 400 ms after 9 AM is exactly 1 hour before 10 AM for the server: free.
    expect(lateCancelWarning(fixtureAppointment, at('2026-11-03T17:00:00.400Z'))).toBeNull();
    expect(lateCancelWarning(fixtureAppointment, at('2026-11-03T17:00:01Z'))).toBe(lateCancelFee.error.message);
    expect(wholeSecond(at('2026-11-03T17:00:00.999Z')).toISOString()).toBe('2026-11-03T17:00:00.000Z');
  });

  it('counts from the first time the client cancelled, when the shop reopened it', () => {
    // Cancelled early, reopened by the shop: cancelling again is still free.
    expect(lateCancelWarning(withFee({ customerCancelledAt: '2026-11-03T08:00:00Z' }), at('2026-11-03T17:30:00Z'))).toBeNull();
    // Cancelled late, reopened: cancelling again is late even long before.
    expect(lateCancelWarning(withFee({ customerCancelledAt: '2026-11-03T17:50:00Z' }), at('2026-11-03T12:00:00Z'))).not.toBeNull();
  });

  it('says "the full service price" only when the fee is the whole price', () => {
    const now = at('2026-11-03T17:30:00Z');
    expect(lateCancelWarning(withFee({ amountCents: 1750, fullPrice: false }), now)).toBe(
      'Cancelling now, less than 1 hour before your appointment, may be charged $17.50.',
    );
    // A server from before fullPrice: judged by the price label.
    expect(lateCancelWarning(withFee({ fullPrice: undefined }), now)).toBe(lateCancelFee.error.message);
    expect(lateCancelWarning(withFee({ fullPrice: undefined }, { priceLabel: 'From $35' }), now)).toBe(
      'Cancelling now, less than 1 hour before your appointment, may be charged $35.',
    );
  });

  it('lets a client cancel only what is booked and still ahead', () => {
    expect(isCancellable(fixtureAppointment, at('2026-11-03T17:59:59Z'))).toBe(true);
    expect(isCancellable(fixtureAppointment, at('2026-11-03T18:00:00Z'))).toBe(false);
    expect(isCancellable({ ...fixtureAppointment, status: 'completed' }, at('2026-11-02T18:00:00Z'))).toBe(false);
  });
});

describe('a time already inside the window', () => {
  it.each(noShowRule.notices.map((n) => [n.notice, n] as const))('reads "%s", as the server words it', (notice, n) => {
    expect(lateCancelNoticeText(n.lateCancelWindowMinutes, n.feeLabel)).toBe(notice);
  });

  it('is pointed out while picking it, with the fee for that booking', () => {
    const start = at('2026-11-03T18:00:00Z');
    expect(lateCancelNotice(policy35, start, at('2026-11-03T17:30:00Z'))).toBe(noShowRule.notices.find((n) => n.feeLabel === '$35')!.notice);
    expect(lateCancelNotice(policy35, start, at('2026-11-03T17:30:00Z'))).toBe(
      'This time is less than 1 hour away, so cancelling it more than 15 minutes after booking may be charged $35.',
    );
    expect(lateCancelNotice(policy35, start, at('2026-11-03T17:00:00Z'))).toBeNull();
    const anyBarber = { ...policy35, minFeeCents: 5500, maxFeeCents: 6000, lateCancelWindowMinutes: 120 };
    expect(lateCancelNotice(anyBarber, start, at('2026-11-03T16:30:00Z'))).toBe(
      'This time is less than 2 hours away, so cancelling it more than 15 minutes after booking may be charged $55–$60.',
    );
    expect(lateCancelNotice({ ...policy35, lateCancelWindowMinutes: null }, start, at('2026-11-03T17:30:00Z'))).toBeNull();
    expect(lateCancelNotice({ ...policy35, required: false }, start, at('2026-11-03T17:30:00Z'))).toBeNull();
  });

  it('names the fee, or the range when barbers differ', () => {
    expect(feeLabel(policy35)).toBe('$35');
    expect(feeLabel({ ...policy35, minFeeCents: 1750, maxFeeCents: 2250 })).toBe('$17.50–$22.50');
    expect(feeLabel({ ...policy35, required: false, minFeeCents: null, maxFeeCents: null })).toBeNull();
  });
});
