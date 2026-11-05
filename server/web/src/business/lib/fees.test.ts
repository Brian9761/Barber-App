import { describe, expect, it } from 'vitest';
import feeCases from '../../../../test/fixtures/fee-cases.json';
import declinedFixture from '../../../../test/fixtures/contract/no-show-fee-declined.json';
import chargedFixture from '../../../../test/fixtures/contract/no-show-fee-charged.json';
import lateChargedFixture from '../../../../test/fixtures/contract/late-cancel-fee-charged.json';
import ownerAppointments from '../../../../test/fixtures/contract/owner-appointments-with-sale.json';
import alreadyCompleted from '../../../../test/fixtures/contract/errors/already_completed.json';
import notStarted from '../../../../test/fixtures/contract/errors/not_started.json';
import { times } from '../../test/text';
import type { OwnerAppointment } from '../types';
import {
  appointmentBadges,
  canMarkNoShow,
  chargeableFee,
  COMPLETED_NO_SHOW_MESSAGE,
  FEE_DEADLINE_DAYS,
  FEE_DEADLINE_MESSAGE,
  feeCase,
  feeDeadline,
  feePanel,
  NO_SHOW_BEFORE_END_MESSAGE,
  noShowHint,
  NOT_ENDED_MESSAGE,
  paidLabel,
  pastFeeDeadline,
  paymentSummary,
  reopenWarning,
  ruleFeeCase,
  ruleFeeCaseAt,
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

type FeeCaseFixture = (typeof feeCases.cases)[number];

/** A fixture case as the rule reads it, with its booking time. */
const ruleOf = (c: FeeCaseFixture) =>
  [
    c.status as OwnerAppointment['status'],
    c.cancelledBy as OwnerAppointment['cancelledBy'],
    new Date(c.start),
    c.customerCancelledAt ? new Date(c.customerCancelledAt) : null,
    c.lateCancelWindowMinutes,
    new Date(c.createdAt),
  ] as const;

describe('which fee can be charged', () => {
  it('matches the server for every one of its examples', () => {
    for (const c of feeCases.cases) {
      const found = ruleFeeCase(...ruleOf(c));
      if (c.reason) expect(found, c.name).toEqual({ kind: 'chargeable', reason: c.reason });
      else expect(found, c.name).toEqual({ kind: 'refused', message: c.refusal });
    }
  });

  it('matches the server at every moment of its examples: after the end, and within 7 days', () => {
    expect(FEE_DEADLINE_DAYS).toBe(feeCases.deadline.days);
    expect(FEE_DEADLINE_MESSAGE).toBe(feeCases.deadline.message);
    expect(NOT_ENDED_MESSAGE).toBe(feeCases.notEnded);
    for (const c of feeCases.clock) {
      const found = ruleFeeCaseAt(
        {
          status: c.status as OwnerAppointment['status'],
          cancelledBy: c.cancelledBy as OwnerAppointment['cancelledBy'],
          start: new Date(c.start),
          end: new Date(c.end),
          createdAt: new Date(c.createdAt),
          customerCancelledAt: c.customerCancelledAt ? new Date(c.customerCancelledAt) : null,
          lateCancelWindowMinutes: c.lateCancelWindowMinutes,
        },
        new Date(c.now),
      );
      if (c.reason) expect(found, c.name).toEqual({ kind: 'chargeable', reason: c.reason });
      else expect(found, c.name).toEqual({ kind: 'refused', message: c.refusal });
    }
  });

  it('keeps the 7 days to the second, like the server', () => {
    const start = new Date('2026-11-03T18:00:00Z');
    expect(feeDeadline(start).toISOString()).toBe('2026-11-10T18:00:00.000Z');
    expect(pastFeeDeadline(start, new Date('2026-11-10T18:00:00Z'))).toBe(false);
    expect(pastFeeDeadline(start, new Date('2026-11-10T18:00:01Z'))).toBe(true);
  });

  it('charges a no-show only once the appointment has ended, and never without a card', () => {
    const noShow = booked({ status: 'noShow' });
    // Flowxbori's 10 AM haircut ends at 10:45.
    expect(feeCase(noShow, new Date('2026-11-03T18:00:00Z'))).toEqual({ kind: 'refused', message: NOT_ENDED_MESSAGE });
    expect(feeCase(noShow, new Date('2026-11-03T18:44:59Z'))).toEqual({ kind: 'refused', message: NOT_ENDED_MESSAGE });
    expect(chargeableFee(noShow, new Date('2026-11-03T18:44:59Z'))).toBeNull();
    expect(chargeableFee(noShow, new Date('2026-11-03T18:45:00Z'))).toBe('noShow');
    expect(chargeableFee({ ...noShow, card: null }, new Date('2026-11-03T19:00:00Z'))).toBeNull();
    // Charged already: nothing more to charge.
    expect(chargeableFee(charged, new Date('2026-11-03T19:00:00Z'))).toBeNull();
  });

  it('charges nothing more than 7 days after the appointment, but still checks a try that was sent', () => {
    const noShow = booked({ status: 'noShow' });
    expect(chargeableFee(noShow, new Date('2026-11-10T18:00:00Z'))).toBe('noShow');
    expect(chargeableFee(noShow, new Date('2026-11-10T18:01:00Z'))).toBeNull();
    expect(feeCase(noShow, new Date('2026-11-10T18:01:00Z'))).toEqual({ kind: 'refused', message: FEE_DEADLINE_MESSAGE });
    expect(chargeableFee(declined, new Date('2026-11-10T19:01:00Z'))).toBeNull();
    // A try whose answer never came is looked up whatever the time: Stripe may have charged it.
    const pending = { ...noShow, noShowFee: { ...noShow.noShowFee!, status: 'pending' as const, reason: 'noShow' as const } };
    expect(chargeableFee(pending, new Date('2026-11-20T18:00:00Z'))).toBe('noShow');
  });

  it('never charges a completed visit', () => {
    expect(feeCase(booked({ status: 'completed' }), new Date('2026-11-03T19:00:00Z'))).toEqual({
      kind: 'refused',
      message: "The appointment is marked completed, so there's no fee to charge.",
    });
  });

  it('offers "Mark no-show" for a booking with a card on file only once it has ended, and for any other once it has started', () => {
    const withCard = booked();
    expect(canMarkNoShow(withCard, new Date('2026-11-03T18:00:00Z'))).toBe(false);
    expect(canMarkNoShow(withCard, new Date('2026-11-03T18:44:59Z'))).toBe(false);
    expect(canMarkNoShow(withCard, new Date('2026-11-03T18:45:00Z'))).toBe(true);
    const withoutCard = booked({ card: null, noShowFee: null });
    expect(canMarkNoShow(withoutCard, new Date('2026-11-03T17:59:59Z'))).toBe(false);
    expect(canMarkNoShow(withoutCard, new Date('2026-11-03T18:00:00Z'))).toBe(true);
    expect(canMarkNoShow({ ...withoutCard, status: 'completed' }, new Date('2026-11-03T19:00:00Z'))).toBe(false);
    expect(canMarkNoShow({ ...withCard, status: 'completed' }, new Date('2026-11-03T19:00:00Z'))).toBe(false);
  });

  it('says when "Mark no-show" shows', () => {
    expect(noShowHint(booked({ card: null, noShowFee: null }), new Date('2026-11-03T17:00:00Z'), ZONE)).toBe(
      times('You can mark a no-show once the appointment starts at 10 AM.'),
    );
    expect(noShowHint(booked(), new Date('2026-11-02T17:00:00Z'), ZONE)).toBe(
      times('You can mark a no-show once the appointment ends on Tue, Nov 3 at 10:45 AM. Until it starts, the client can still cancel in the app.'),
    );
    expect(noShowHint(booked(), new Date('2026-11-03T18:10:00Z'), ZONE)).toBe(
      times("You can mark a no-show once the appointment ends at 10:45 AM. A client who comes before then isn't a no-show."),
    );
    expect(noShowHint(booked(), new Date('2026-11-03T18:45:00Z'), ZONE)).toBeNull();
  });

  it('words what the server answers when a no-show can’t be marked, as it does', () => {
    expect(NO_SHOW_BEFORE_END_MESSAGE).toBe(notStarted.error.message);
    expect(COMPLETED_NO_SHOW_MESSAGE).toBe(alreadyCompleted.error.message);
  });
});

describe('the card on file in the details', () => {
  it('asks before charging, naming the card and the amount', () => {
    // After the end (10:45): a no-show can be charged.
    const panel = feePanel(booked({ status: 'noShow' }), new Date('2026-11-03T18:50:00Z'), ZONE)!;
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
    expect(panel.footer).toBe(
      times(
        'Nothing is charged until you confirm, and a fee is only ever charged once. It can be charged until Tue, Nov 10 at 10 AM, 7 days after the appointment.',
      ),
    );
  });

  it('offers no charge before the end, and says how it can be charged then', () => {
    const panel = feePanel(booked({ status: 'noShow' }), new Date('2026-11-03T18:30:00Z'), ZONE)!;
    expect(panel.action).toBeNull();
    expect(panel.status).toEqual({ kind: 'notCharged', note: NOT_ENDED_MESSAGE });
    expect(feePanel(booked(), new Date('2026-11-03T18:30:00Z'), ZONE)!.status).toEqual({
      kind: 'notCharged',
      note: "If the client doesn't come, you can mark a no-show once the appointment has ended. Then you can charge the fee.",
    });
    expect(feePanel(booked(), new Date('2026-11-03T18:50:00Z'), ZONE)!.status).toEqual({
      kind: 'notCharged',
      note: "If the client didn't come, mark a no-show. Then you can charge the fee.",
    });
  });

  it('offers no charge after the 7 days, and says why in a plain line', () => {
    for (const appointment of [booked({ status: 'noShow' }), booked()]) {
      const panel = feePanel(appointment, new Date('2026-11-10T18:01:00Z'), ZONE)!;
      expect(panel.action).toBeNull();
      expect(panel.status).toEqual({ kind: 'notCharged', note: "It's more than 7 days after the appointment, so the fee can't be charged." });
      expect(panel.footer).toBeNull();
    }
    const late = { ...lateCharged, noShowFee: { ...lateCharged.noShowFee!, status: 'none' as const, chargedAt: null } };
    expect(feePanel(late, new Date('2026-11-10T21:01:00Z'), ZONE)!.action).toBeNull();
    // A declined card can't be tried again then either.
    const again = feePanel(declined, new Date('2026-11-10T19:01:00Z'), ZONE)!;
    expect(again.action).toBeNull();
    expect(again.footer).toBe(FEE_DEADLINE_MESSAGE);
  });

  it('says a charged fee was charged, and that refunds are made in Stripe', () => {
    const panel = feePanel(charged, new Date('2026-11-03T19:00:00Z'), ZONE)!;
    expect(panel.status).toEqual({ kind: 'charged', title: 'No-show fee charged', detail: times('$35 to Visa •••• 4242, Tue, Nov 3 at 10:50 AM.') });
    expect(panel.action).toBeNull();
    expect(panel.footer).toBe("Refunds are made in the Stripe Dashboard. Reopening the appointment doesn't refund the fee.");
  });

  it('offers to charge a declined fee again, until the 7 days are over', () => {
    const panel = feePanel(declined, new Date('2026-11-03T20:00:00Z'), ZONE)!;
    expect(panel.status).toEqual({ kind: 'declined', detail: "The card was declined: there isn't enough money on it." });
    expect(panel.action?.title).toBe('Charge again ($25)');
    expect(panel.footer).toBe(
      times('You can try the card again until Tue, Nov 10 at 11 AM, 7 days after the appointment, or ask the client to pay at the shop.'),
    );
  });

  it('checks a try whose answer never came even after the 7 days, without sending a new one', () => {
    const pending = booked({ status: 'noShow', noShowFee: { ...charged.noShowFee!, status: 'pending', chargedAt: null, reason: 'noShow' } });
    const before = feePanel(pending, new Date('2026-11-03T19:00:00Z'), ZONE)!;
    expect(before.action).toEqual({ title: 'Check again', confirmation: null });
    expect(before.status.kind === 'pending' && before.status.detail).toContain("if Stripe never got it, it's sent now");
    const after = feePanel(pending, new Date('2026-11-11T19:00:00Z'), ZONE)!;
    expect(after.action).toEqual({ title: 'Check again', confirmation: null });
    expect(after.status.kind === 'pending' && after.status.detail).toContain('if not, nothing is charged');
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

  it('says a completed visit can’t become a no-show, even reopened', () => {
    expect(reopenWarning(booked({ status: 'completed' }), new Date('2026-11-03T19:00:00Z'))).toBe(
      "It was marked done, so even once it's reopened, it can't be marked a no-show or charged a no-show fee: the client came.",
    );
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
    // Cancelled within 15 minutes of booking: not late, whatever the window.
    const changedMind = {
      ...lateCharged,
      createdAt: '2026-11-03T20:20:00Z',
      noShowFee: { ...lateCharged.noShowFee!, status: 'none' as const, chargedAt: null, reason: null },
    };
    expect(appointmentBadges(changedMind).map((b) => b.text)).toEqual(['Cancelled', 'Card on file · Visa •••• 4242']);
    expect(feePanel(changedMind, new Date('2026-11-03T20:40:00Z'), ZONE)!.status).toEqual({
      kind: 'notCharged',
      note: "The client cancelled within 15 minutes of booking, so there's no fee.",
    });
  });

  it('says "Paid $60 · Cash" for a checkout, and keeps a charged fee apart from the service', () => {
    expect(paidLabel(checkedOut)).toBe('Paid $96 · Cash');
    // With thousands commas, like every total.
    expect(paidLabel({ ...checkedOut, sale: { ...checkedOut.sale!, totalCents: 125000 } })).toBe('Paid $1,250 · Cash');
    expect(paymentSummary(checkedOut)).toEqual({ title: 'Paid', value: '$96 · Cash', feeNote: null });
    expect(paymentSummary(charged)).toEqual({ title: 'Service not paid', value: '$35', feeNote: 'The $35 no-show fee was charged to the card on file.' });
  });
});
