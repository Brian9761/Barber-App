import { describe, expect, it } from 'vitest';
import feeCases from '../../../../test/fixtures/fee-cases.json';
import declinedFixture from '../../../../test/fixtures/contract/no-show-fee-declined.json';
import chargedFixture from '../../../../test/fixtures/contract/no-show-fee-charged.json';
import lateChargedFixture from '../../../../test/fixtures/contract/late-cancel-fee-charged.json';
import ownerAppointments from '../../../../test/fixtures/contract/owner-appointments-with-sale.json';
import type { OwnerAppointment } from '../types';
import {
  appointmentBadges,
  canMarkNoShow,
  chargeableFee,
  feeCase,
  feePanel,
  noShowHint,
  paidLabel,
  paymentSummary,
  reopenWarning,
  ruleFeeCase,
  shopCancelNote,
} from './fees';

// The owner app's fee rules (FeePanel.swift), checked against the server's own examples
// (fee-cases.json) and its contract fixtures.

const ZONE = 'America/Los_Angeles';
const charged = chargedFixture.appointment as unknown as OwnerAppointment;
const declined = declinedFixture.appointment as unknown as OwnerAppointment;
const lateCharged = lateChargedFixture.appointment as unknown as OwnerAppointment;
const checkedOut = ownerAppointments.appointments[0] as unknown as OwnerAppointment;

/** A booked appointment with a card on file and a fee not charged yet. */
function booked(overrides: Partial<OwnerAppointment> = {}): OwnerAppointment {
  return {
    ...charged,
    status: 'booked',
    noShowFee: { ...charged.noShowFee!, status: 'none', chargedAt: null, reason: null },
    ...overrides,
  };
}

describe('which fee can be charged', () => {
  it('matches the server for every one of its examples', () => {
    for (const c of feeCases.cases) {
      const found = ruleFeeCase(
        c.status as OwnerAppointment['status'],
        c.cancelledBy as OwnerAppointment['cancelledBy'],
        new Date(c.start),
        c.customerCancelledAt ? new Date(c.customerCancelledAt) : null,
        c.lateCancelWindowMinutes,
      );
      if (c.reason) expect(found, c.name).toEqual({ kind: 'chargeable', reason: c.reason });
      else expect(found, c.name).toEqual({ kind: 'refused', message: c.refusal });
    }
  });

  it('charges a no-show only once the appointment has started, and never without a card', () => {
    const noShow = booked({ status: 'noShow' });
    expect(feeCase(noShow, new Date('2026-11-03T17:59:00Z'))).toEqual({
      kind: 'refused',
      message: "The appointment hasn't started yet, so it can't be a no-show.",
    });
    expect(chargeableFee(noShow, new Date('2026-11-03T18:00:00Z'))).toBe('noShow');
    expect(chargeableFee({ ...noShow, card: null }, new Date('2026-11-03T19:00:00Z'))).toBeNull();
    // Charged already: nothing more to charge.
    expect(chargeableFee(charged, new Date('2026-11-03T19:00:00Z'))).toBeNull();
  });

  it('offers "Mark no-show" only once an appointment has started', () => {
    const appointment = booked({ card: null, noShowFee: null });
    expect(canMarkNoShow(appointment, new Date('2026-11-03T17:59:59Z'))).toBe(false);
    expect(canMarkNoShow(appointment, new Date('2026-11-03T18:00:00Z'))).toBe(true);
    expect(canMarkNoShow({ ...appointment, status: 'completed' }, new Date('2026-11-03T19:00:00Z'))).toBe(false);
    expect(noShowHint(appointment, new Date('2026-11-03T17:00:00Z'), ZONE)).toBe('You can mark a no-show once the appointment starts at 10 AM.');
    expect(noShowHint(booked(), new Date('2026-11-02T17:00:00Z'), ZONE)).toBe(
      'You can mark a no-show once the appointment starts on Tue, Nov 3 at 10 AM. Until then, the client can still cancel in the app.',
    );
  });
});

describe('the card on file in the details', () => {
  it('asks before charging, naming the card and the amount', () => {
    const panel = feePanel(booked({ status: 'noShow' }), new Date('2026-11-03T18:30:00Z'), ZONE)!;
    expect(panel.cardLabel).toBe('Visa •••• 4242');
    expect(panel.feeLabel).toBe('$35 (the full service price)');
    expect(panel.agreement).toBe('For not showing up, or cancelling less than 1 hour before.');
    expect(panel.action).toEqual({
      title: 'Charge no-show fee ($35)',
      confirmation: {
        title: "Charge $35 to Fixture Client's Visa •••• 4242?",
        message: 'No-show fee for Haircut with Flowxbori, Tue, Nov 3 at 10 AM. The client agreed to it when booking.',
        button: 'Charge $35',
      },
    });
    expect(panel.footer).toBe('Nothing is charged until you confirm, and a fee is only ever charged once.');
  });

  it('says a charged fee was charged, and that refunds are made in Stripe', () => {
    const panel = feePanel(charged, new Date('2026-11-03T19:00:00Z'), ZONE)!;
    expect(panel.status).toEqual({ kind: 'charged', title: 'No-show fee charged', detail: '$35 to Visa •••• 4242, Tue, Nov 3 at 10:20 AM.' });
    expect(panel.action).toBeNull();
    expect(panel.footer).toBe("Refunds are made in the Stripe Dashboard. Reopening the appointment doesn't refund the fee.");
  });

  it('offers to charge a declined fee again', () => {
    const panel = feePanel(declined, new Date('2026-11-03T20:00:00Z'), ZONE)!;
    expect(panel.status).toEqual({ kind: 'declined', detail: "The card was declined: there isn't enough money on it." });
    expect(panel.action?.title).toBe('Charge again ($25)');
  });

  it('words a late cancellation with when the client cancelled', () => {
    const late = { ...lateCharged, noShowFee: { ...lateCharged.noShowFee!, status: 'none' as const, chargedAt: null } };
    const panel = feePanel(late, new Date('2026-11-03T22:00:00Z'), ZONE)!;
    expect(panel.action?.title).toBe('Charge late cancellation fee ($25)');
    expect(panel.action?.confirmation?.message).toBe(
      'Late cancellation fee for Haircut with Flowxbori, Tue, Nov 3 at 1 PM: the client cancelled at 12:30 PM, less than 1 hour before. They agreed to it when booking.',
    );
  });

  it('has nothing to show without a card on file', () => {
    expect(feePanel(checkedOut, new Date(), ZONE)).toBeNull();
  });
});

describe('what Reopen and Cancel say first', () => {
  it('says a charged fee stays charged', () => {
    expect(reopenWarning(charged, new Date('2026-11-03T19:00:00Z'))).toBe(
      "The $35 no-show fee stays charged: reopening doesn't refund it. Refunds are made in the Stripe Dashboard.",
    );
    expect(shopCancelNote({ ...charged, status: 'booked' })).toBe(
      "The $35 no-show fee stays charged: cancelling doesn't refund it. Refunds are made in the Stripe Dashboard.",
    );
  });

  it("says a late cancellation can't be charged once it's reopened", () => {
    const late = { ...lateCharged, noShowFee: { ...lateCharged.noShowFee!, status: 'none' as const, chargedAt: null } };
    expect(reopenWarning(late, new Date('2026-11-03T22:00:00Z'))).toContain("the $25 late cancellation fee can't be charged any more");
  });

  it('says nothing when there is nothing to say', () => {
    expect(reopenWarning({ ...checkedOut, status: 'completed' }, new Date())).toBeNull();
    expect(shopCancelNote(booked())).toBe("There's no fee when the shop cancels.");
    expect(shopCancelNote(checkedOut)).toBeNull();
  });
});

describe('badges and the payment', () => {
  it('shows the status, the checkout and the card or its fee', () => {
    expect(appointmentBadges(checkedOut)).toEqual([
      { text: 'Completed', tone: 'completed' },
      { text: 'Paid $96 · Cash', tone: 'paid' },
    ]);
    expect(appointmentBadges(charged).map((b) => b.text)).toEqual(['No-show', 'No-show fee $35 charged']);
    expect(appointmentBadges(booked()).map((b) => b.text)).toEqual(['Booked', 'Card on file · Visa •••• 4242']);
    expect(appointmentBadges({ ...lateCharged, noShowFee: { ...lateCharged.noShowFee!, status: 'none', chargedAt: null } }).map((b) => b.text)).toEqual([
      'Cancelled late',
      'Card on file · Visa •••• 4242',
    ]);
  });

  it('says "Paid $60 · Cash" for a checkout, and keeps a charged fee apart from the service', () => {
    expect(paidLabel(checkedOut)).toBe('Paid $96 · Cash');
    expect(paymentSummary(checkedOut)).toEqual({ title: 'Paid', value: '$96 · Cash', feeNote: null });
    expect(paymentSummary(charged)).toEqual({ title: 'Service not paid', value: '$35', feeNote: 'The $35 no-show fee was charged to the card on file.' });
  });
});
