import { describe, expect, it } from 'vitest';
import feeCases from '../../../../test/fixtures/fee-cases.json';
import declinedFixture from '../../../../test/fixtures/contract/no-show-fee-declined.json';
import chargedFixture from '../../../../test/fixtures/contract/no-show-fee-charged.json';
import lateChargedFixture from '../../../../test/fixtures/contract/late-cancel-fee-charged.json';
import unsentFixture from '../../../../test/fixtures/contract/no-show-fee-charged-no-receipt.json';
import ownerAppointments from '../../../../test/fixtures/contract/owner-appointments-with-sale.json';
import alreadyCompleted from '../../../../test/fixtures/contract/errors/already_completed.json';
import notStarted from '../../../../test/fixtures/contract/errors/not_started.json';
import shopCancelledError from '../../../../test/fixtures/contract/errors/shop_cancelled.json';
import { times } from '../../test/text';
import type { OwnerAppointment } from '../types';
import {
  appointmentBadges,
  canMarkNoShow,
  chargeableFee,
  completedBefore,
  COMPLETED_NO_SHOW_MESSAGE,
  FEE_DEADLINE_DAYS,
  FEE_DEADLINE_MESSAGE,
  feeCase,
  feeDeadline,
  feePanel,
  LATE_CANCEL_NOT_ENDED_MESSAGE,
  NO_SHOW_BEFORE_END_MESSAGE,
  noShowHint,
  NOT_ENDED_MESSAGE,
  paidLabel,
  pastFeeDeadline,
  paymentSummary,
  receiptNote,
  REOPEN_SHOP_CANCELLED_WARNING,
  reopenWarning,
  ruleFeeCase,
  ruleFeeCaseAt,
  SHOP_CANCELLED_MESSAGE,
  SHOP_CANCELLED_NO_SHOW_MESSAGE,
  shopCancelledBefore,
  shopCancelNote,
  TIME_TAKEN_MESSAGE,
  timeTaken,
  TURNED_DOWN_FOOTER,
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

/** A fixture case as the rule reads it, with its booking time and when the shop cancelled it, if it did. */
const ruleOf = (c: FeeCaseFixture) =>
  [
    c.status as OwnerAppointment['status'],
    c.cancelledBy as OwnerAppointment['cancelledBy'],
    new Date(c.start),
    c.customerCancelledAt ? new Date(c.customerCancelledAt) : null,
    c.lateCancelWindowMinutes,
    new Date(c.createdAt),
    c.shopCancelledAt ? new Date(c.shopCancelledAt) : null,
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
    expect(LATE_CANCEL_NOT_ENDED_MESSAGE).toBe(feeCases.lateCancelNotEnded);
    expect(SHOP_CANCELLED_MESSAGE).toBe(feeCases.shopCancelled);
    expect(TIME_TAKEN_MESSAGE).toBe(feeCases.timeTaken);
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
          shopCancelledAt: c.shopCancelledAt ? new Date(c.shopCancelledAt) : null,
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

  it('charges a late cancellation only once the appointment has ended too, saying so before', () => {
    const late = { ...lateCharged, noShowFee: { ...lateCharged.noShowFee!, status: 'none' as const, chargedAt: null } };
    // The server's own late cancellation: the 1 PM haircut, cancelled at 12:30 PM, ends at 1:45 PM.
    expect(late.end).toBe('2026-11-03T21:45:00Z');
    for (const now of ['2026-11-03T20:31:00Z', '2026-11-03T21:00:00Z', '2026-11-03T21:44:59Z']) {
      expect(feeCase(late, new Date(now)), now).toEqual({ kind: 'refused', message: LATE_CANCEL_NOT_ENDED_MESSAGE });
      expect(chargeableFee(late, new Date(now)), now).toBeNull();
      const panel = feePanel(late, new Date(now), ZONE)!;
      expect(panel.status, now).toEqual({ kind: 'notCharged', note: LATE_CANCEL_NOT_ENDED_MESSAGE });
      expect(panel.action, now).toBeNull();
      expect(panel.footer, now).toBeNull();
    }
    expect(LATE_CANCEL_NOT_ENDED_MESSAGE).toBe(
      "The appointment hasn't ended yet. You can charge the late-cancellation fee once it has, if no other client took the time.",
    );
    expect(chargeableFee(late, new Date('2026-11-03T21:45:00Z'))).toBe('lateCancel');
    expect(feePanel(late, new Date('2026-11-03T21:45:00Z'), ZONE)!.action?.title).toBe('Charge late cancellation fee ($25)');
    // Still the case it is ("Cancelled late"), whatever the time.
    expect(appointmentBadges(late)[0]!.text).toBe('Cancelled late');
  });

  it('never charges a booking the shop cancelled, even reopened, and never makes it a no-show, as the server answers', () => {
    expect(SHOP_CANCELLED_NO_SHOW_MESSAGE).toBe(shopCancelledError.error.message);
    expect(shopCancelledError.error.code).toBe('shop_cancelled');
    // Cancelled by the shop the day before, then reopened.
    const reopened = booked({ shopCancelledAt: '2026-11-02T18:00:00Z' });
    expect(shopCancelledBefore(reopened)).toBe(true);
    for (const now of ['2026-11-03T17:00:00Z', '2026-11-03T18:50:00Z', '2026-11-11T18:00:00Z']) {
      expect(feeCase(reopened, new Date(now)), now).toEqual({ kind: 'refused', message: SHOP_CANCELLED_MESSAGE });
      expect(canMarkNoShow(reopened, new Date(now)), now).toBe(false);
      expect(noShowHint(reopened, new Date(now), ZONE), now).toBe(SHOP_CANCELLED_NO_SHOW_MESSAGE);
      const panel = feePanel(reopened, new Date(now), ZONE)!;
      expect(panel.status, now).toEqual({ kind: 'notCharged', note: SHOP_CANCELLED_MESSAGE });
      expect(panel.action, now).toBeNull();
    }
    // Then a no-show (an older server let it be marked), or cancelled late by the client: no fee either.
    expect(chargeableFee({ ...reopened, status: 'noShow' }, new Date('2026-11-03T18:50:00Z'))).toBeNull();
    const lateAfter = {
      ...reopened,
      status: 'cancelled' as const,
      cancelledBy: 'customer' as const,
      noShowFee: { ...reopened.noShowFee!, customerCancelledAt: '2026-11-03T17:30:00Z' },
    };
    expect(feeCase(lateAfter, new Date('2026-11-03T18:50:00Z'))).toEqual({ kind: 'refused', message: SHOP_CANCELLED_MESSAGE });
    expect(feePanel(lateAfter, new Date('2026-11-03T18:50:00Z'), ZONE)!.status).toEqual({ kind: 'notCharged', note: SHOP_CANCELLED_MESSAGE });
    // Still cancelled by the shop (also from a server from before `shopCancelledAt`).
    const cancelled = booked({ status: 'cancelled', cancelledBy: 'shop', shopCancelledAt: null });
    expect(shopCancelledBefore(cancelled)).toBe(true);
    expect(feeCase(cancelled, new Date('2026-11-03T18:50:00Z'))).toEqual({ kind: 'refused', message: SHOP_CANCELLED_MESSAGE });
    // Without a card there's no fee, so nothing changes; a booking the client cancelled isn't the shop's.
    expect(shopCancelledBefore(booked({ card: null, noShowFee: null, shopCancelledAt: '2026-11-02T18:00:00Z' }))).toBe(false);
    expect(canMarkNoShow(booked({ card: null, noShowFee: null, shopCancelledAt: '2026-11-02T18:00:00Z' }), new Date('2026-11-03T18:50:00Z'))).toBe(true);
    expect(shopCancelledBefore({ ...lateAfter, shopCancelledAt: null })).toBe(false);
    // Never cancelled by the shop: as before.
    expect(canMarkNoShow(booked({ shopCancelledAt: null }), new Date('2026-11-03T18:50:00Z'))).toBe(true);
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

  it('never offers "Mark no-show" for a booking with a card on file that was completed and reopened, and says why as the server does', () => {
    // Marked done at 10:30 AM, then reopened: the server keeps when it was first completed, and refuses a no-show.
    const reopened = booked({ completedAt: '2026-11-03T18:30:00Z' });
    expect(completedBefore(reopened)).toBe(true);
    for (const now of ['2026-11-03T18:10:00Z', '2026-11-03T18:50:00Z', '2026-11-04T18:00:00Z']) {
      expect(canMarkNoShow(reopened, new Date(now)), now).toBe(false);
      expect(noShowHint(reopened, new Date(now), ZONE), now).toBe(alreadyCompleted.error.message);
      const panel = feePanel(reopened, new Date(now), ZONE)!;
      expect(panel.status, now).toEqual({ kind: 'notCharged', note: alreadyCompleted.error.message });
      expect(panel.action, now).toBeNull();
      expect(panel.footer, now).toBeNull();
    }
    // Once the 7 days are over, that's what it says, as for any other booking.
    expect(feePanel(reopened, new Date('2026-11-10T18:01:00Z'), ZONE)!.status).toEqual({ kind: 'notCharged', note: FEE_DEADLINE_MESSAGE });
    // The server's own owner view of a checked-out visit says when (owner-appointments-with-sale.json): with a card, voided and reopened, the same.
    expect(checkedOut.completedAt).toBe('2026-11-02T19:05:00Z');
    const voidedAndReopened: OwnerAppointment = { ...checkedOut, status: 'booked', sale: null, card: { brand: 'visa', last4: '4242' } };
    expect(canMarkNoShow(voidedAndReopened, new Date('2026-11-03T19:00:00Z'))).toBe(false);
    // Without a card there's no fee, so it can still be marked as before.
    const noCard = booked({ card: null, noShowFee: null, completedAt: '2026-11-03T18:30:00Z' });
    expect(completedBefore(noCard)).toBe(false);
    expect(canMarkNoShow(noCard, new Date('2026-11-03T18:50:00Z'))).toBe(true);
    expect(noShowHint(noCard, new Date('2026-11-03T18:50:00Z'), ZONE)).toBeNull();
    // Never completed: as before. And a server from before `completedAt` doesn't say, so only its answer does.
    expect(canMarkNoShow(booked({ completedAt: null }), new Date('2026-11-03T18:50:00Z'))).toBe(true);
    const { completedAt: _completedAt, ...older } = booked();
    expect(canMarkNoShow(older as OwnerAppointment, new Date('2026-11-03T18:50:00Z'))).toBe(true);
    expect(noShowHint(older as OwnerAppointment, new Date('2026-11-03T18:50:00Z'), ZONE)).toBeNull();
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
    // A declined card isn't tried again then either.
    const again = feePanel(declined, new Date('2026-11-10T19:01:00Z'), ZONE)!;
    expect(again.action).toBeNull();
    expect(again.footer).toBe(TURNED_DOWN_FOOTER);
  });

  it('says a charged fee was charged, and that refunds are made in Stripe', () => {
    const panel = feePanel(charged, new Date('2026-11-03T19:00:00Z'), ZONE)!;
    expect(panel.status).toEqual({ kind: 'charged', title: 'No-show fee charged', detail: times('$35 to Visa •••• 4242, Tue, Nov 3 at 10:50 AM.') });
    expect(panel.action).toBeNull();
    expect(panel.footer).toBe("Refunds are made in the Stripe Dashboard. Reopening the appointment doesn't refund the fee.");
    // Stripe emailed the receipt (the server's own answer says so): nothing more to say.
    expect(charged.noShowFee?.receipt).toBe('sent');
    expect(panel.receiptNote).toBeNull();
  });

  it('says when a charged fee’s receipt didn’t go out, and how to send one, in the app’s words', () => {
    // The server's own answer for a fee whose card page kept no email.
    const unsent = unsentFixture.appointment as unknown as OwnerAppointment;
    expect(unsent.noShowFee).toMatchObject({ status: 'charged', receipt: 'noEmail' });
    const panel = feePanel(unsent, new Date('2026-11-05T19:00:00Z'), ZONE)!;
    expect(panel.status.kind).toBe('charged');
    expect(panel.receiptNote).toBe(
      'No receipt was sent: Stripe has no email address for this client. Ask them for one, and send the receipt from the Stripe Dashboard.',
    );
    expect(receiptNote('failed')).toBe("The receipt couldn't be sent. Send it to the client from the Stripe Dashboard.");
    expect(receiptNote('sent')).toBeNull();
    expect(receiptNote(null)).toBeNull();
    // A server from before it said nothing: nothing is said here either.
    expect(receiptNote(undefined)).toBeNull();
    // Only a charged fee has a receipt to speak of.
    expect(feePanel({ ...declined, noShowFee: { ...declined.noShowFee!, receipt: 'noEmail' } }, new Date('2026-11-03T20:00:00Z'), ZONE)!.receiptNote).toBeNull();
  });

  it('never charges a declined card again: it says to tell the client and give them 7 days to pay another way', () => {
    const panel = feePanel(declined, new Date('2026-11-03T20:00:00Z'), ZONE)!;
    expect(panel.status).toEqual({ kind: 'declined', detail: "The card was declined: there isn't enough money on it." });
    expect(panel.action).toBeNull();
    expect(panel.footer).toBe(
      "The card isn't charged again. Tell the client in writing (a text, or an email if they gave one), and give them at least 7 days to pay the fee another way, for example at the shop.",
    );
    expect(chargeableFee(declined, new Date('2026-11-03T20:00:00Z'))).toBeNull();
    // The same when the bank wants the client to approve the charge.
    const needsClient = { ...declined, noShowFee: { ...declined.noShowFee!, status: 'needsAction' as const } };
    expect(feePanel(needsClient, new Date('2026-11-03T20:00:00Z'), ZONE)).toMatchObject({ action: null, footer: TURNED_DOWN_FOOTER });
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
      'Late cancellation fee for Haircut with Flowxbori, Tue, Nov 3 at 1 PM: the client cancelled at 12:30 PM, less than 1 hour before. They agreed to it when booking. ' +
        "Don't charge it if another client, such as a walk-in, took this time.",
    );
  });

  it('offers no late-cancellation fee once another client was booked into that time (the policy’s promise)', () => {
    const late = { ...lateCharged, noShowFee: { ...lateCharged.noShowFee!, status: 'none' as const, chargedAt: null } };
    const now = new Date('2026-11-03T22:00:00Z');
    const walkIn = { ...late, id: 'walk-in', card: null, noShowFee: null, status: 'booked' as const };
    const panel = feePanel(late, now, ZONE, [late, walkIn])!;
    expect(panel.action).toBeNull();
    expect(panel.status).toEqual({ kind: 'notCharged', note: TIME_TAKEN_MESSAGE });
    expect(timeTaken(late, [walkIn])).toBe(true);
    // Another barber at the same time, one right after, or one booked before the client cancelled
    // (11:55 AM) and cancelled doesn't take it: that one freed the time.
    expect(timeTaken(late, [{ ...walkIn, barberId: 'someone-else' }])).toBe(false);
    expect(timeTaken(late, [{ ...walkIn, start: late.end, end: new Date(Date.parse(late.end) + 30 * 60_000).toISOString() }])).toBe(false);
    expect(timeTaken(late, [{ ...walkIn, status: 'cancelled' as const }])).toBe(false);
    expect(feePanel(late, now, ZONE, [late, { ...walkIn, status: 'cancelled' as const }])!.action?.title).toBe('Charge late cancellation fee ($25)');
  });

  it('counts a client booked into the time after the cancellation, whatever became of them: one fee for the time at most', () => {
    const late = { ...lateCharged, noShowFee: { ...lateCharged.noShowFee!, status: 'none' as const, chargedAt: null } };
    const now = new Date('2026-11-03T22:00:00Z');
    // Booked at 12:30 PM, the second the client cancelled, then marked a no-show or cancelled.
    const cancelledAt = late.noShowFee.customerCancelledAt!;
    expect(cancelledAt).toBe('2026-11-03T20:30:00Z');
    const bookedSince = { ...late, id: 'booked-since', card: null, noShowFee: null, createdAt: cancelledAt };
    for (const status of ['cancelled', 'noShow'] as const) {
      expect(timeTaken(late, [{ ...bookedSince, status }]), status).toBe(true);
      const panel = feePanel(late, now, ZONE, [late, { ...bookedSince, status }])!;
      expect(panel.action, status).toBeNull();
      expect(panel.status, status).toEqual({ kind: 'notCharged', note: TIME_TAKEN_MESSAGE });
    }
    // A second before the client cancelled, a cancelled booking had freed the time instead.
    const secondBefore = '2026-11-03T20:29:59Z';
    expect(timeTaken(late, [{ ...bookedSince, createdAt: secondBefore, status: 'cancelled' }])).toBe(false);
    // A no-show counts whenever it was booked: the shop may have reopened it into the time since.
    expect(timeTaken(late, [{ ...bookedSince, createdAt: secondBefore, status: 'noShow' }])).toBe(true);
    // Without the cancel time (not a late cancellation), only what holds the time counts.
    const noCancelTime = { ...late, noShowFee: { ...late.noShowFee, customerCancelledAt: null } };
    expect(timeTaken(noCancelTime, [{ ...bookedSince, status: 'cancelled' }])).toBe(false);
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

  it("says a late cancellation can't be charged once it's reopened, before the end too", () => {
    const late = { ...lateCharged, noShowFee: { ...lateCharged.noShowFee!, status: 'none' as const, chargedAt: null } };
    expect(reopenWarning(late, new Date('2026-11-03T22:00:00Z'))).toContain("the $25 late cancellation fee can't be charged any more");
    // Before the 1:45 PM end it can't be charged yet, but reopening still loses it.
    expect(reopenWarning(late, new Date('2026-11-03T20:40:00Z'))).toBe(reopenWarning(late, new Date('2026-11-03T22:00:00Z')));
  });

  it('says first that a booking the shop cancelled can’t be charged a fee once it’s reopened', () => {
    expect(REOPEN_SHOP_CANCELLED_WARNING).toBe(
      "The shop cancelled this booking, so once it's reopened, it can't be charged a fee. To keep a fee, ask the client to book again in the app instead.",
    );
    const cancelled = booked({ status: 'cancelled', cancelledBy: 'shop', shopCancelledAt: '2026-11-02T18:00:00Z' });
    expect(reopenWarning(cancelled, new Date('2026-11-03T17:00:00Z'))).toBe(REOPEN_SHOP_CANCELLED_WARNING);
    // Also once the client cancelled it after the shop had reopened it.
    const clientAfter = booked({
      status: 'cancelled',
      cancelledBy: 'customer',
      shopCancelledAt: '2026-11-02T18:00:00Z',
      noShowFee: { ...charged.noShowFee!, status: 'none', chargedAt: null, reason: null, customerCancelledAt: '2026-11-03T17:30:00Z' },
    });
    expect(reopenWarning(clientAfter, new Date('2026-11-03T18:00:00Z'))).toBe(REOPEN_SHOP_CANCELLED_WARNING);
    // A fee already charged says that first; one with no card says nothing.
    expect(reopenWarning({ ...cancelled, noShowFee: { ...charged.noShowFee! } }, new Date('2026-11-03T19:00:00Z'))).toContain('stays charged');
    expect(reopenWarning({ ...cancelled, card: null, noShowFee: null }, new Date('2026-11-03T19:00:00Z'))).toBeNull();
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
