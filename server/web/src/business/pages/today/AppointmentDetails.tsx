// One appointment, as the owner app's details show it: the client (tap to call), what and
// when, the note, the card on file and its fee, the payment or sale, and what the owner
// can do now: Check out (cash or other), Mark done, No-show (once it has ended with a card
// on file, once it has started without), Cancel or Reopen as the app allows, and charge the
// agreed fee to the card on file (asking first, naming the card) within 7 days of the
// appointment, as the server allows. A checked-out appointment changes only once its sale is
// voided.
//
// After a change, what happened ("Marked done.") takes the focus where the button was, so
// it's read out and Tab goes on to what can be done now; a fee that couldn't be charged says
// why next to its button, in sight, and offers Settings when Stripe isn't connected.

import { useEffect, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { errorMessage, isApiError } from '../../../api/errors';
import { Dialog } from '../../../components/Dialog';
import { Icon } from '../../../components/Icon';
import { durationLabel } from '../../../lib/format';
import { displayPhone } from '../../../lib/phone';
import { dateTimeLabel, shortDateLabel, localDate, timeLabel } from '../../../lib/shopTime';
import { ownerApi } from '../../api/client';
import { Badges, Row } from '../../components/common';
import {
  appointmentBadges,
  canMarkNoShow,
  feePanel,
  noShowHint,
  paidLabel,
  paymentSummary,
  reopenWarning,
  shopCancelNote,
  type FeeConfirmation,
} from '../../lib/fees';
import type { OwnerAppointment } from '../../types';

type Status = 'booked' | 'completed' | 'noShow' | 'cancelled';

/** What a status change did, in a few words. */
const CHANGED: Record<Status, string> = {
  completed: 'Marked done.',
  noShow: 'Marked a no-show.',
  cancelled: 'Cancelled. The time is open for other clients.',
  booked: 'Reopened: it’s booked again.',
};

/** "10:00 – 10:45 AM" on the shop's clock. */
export function timeRange(appointment: Pick<OwnerAppointment, 'start' | 'end'>, zone: string): string {
  const start = timeLabel(new Date(appointment.start), zone);
  const end = timeLabel(new Date(appointment.end), zone);
  const [startTime, startHalf] = start.split(' ');
  const [, endHalf] = end.split(' ');
  return startHalf === endHalf ? `${startTime} – ${end}` : `${start} – ${end}`;
}

/** Whether the appointment can be checked out here: booked or completed, with no sale yet. */
export function canCheckOut(appointment: OwnerAppointment): boolean {
  return (appointment.status === 'booked' || appointment.status === 'completed') && appointment.sale === null;
}

export function AppointmentDetails({
  appointment,
  zone,
  now,
  onChanged,
  onCheckOut,
  onVoidSale,
}: {
  appointment: OwnerAppointment;
  zone: string;
  now: Date;
  /** The server's answer after a change: shown right away, and the day loads again. */
  onChanged: (appointment: OwnerAppointment) => void;
  onCheckOut: () => void;
  /** Void the appointment's sale (Today's sales does the asking, once it has the sale). */
  onVoidSale: (saleId: string) => void | Promise<void>;
}) {
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [feeError, setFeeError] = useState<{ message: string; settings: boolean } | null>(null);
  const [changed, setChanged] = useState<string | null>(null);
  const [confirmCancel, setConfirmCancel] = useState(false);
  const [confirmReopen, setConfirmReopen] = useState<string | null>(null);
  const [confirmFee, setConfirmFee] = useState<FeeConfirmation | null>(null);

  const outcome = useRef<HTMLDivElement>(null);
  const changedLine = useRef<HTMLParagraphElement>(null);
  const feeErrorLine = useRef<HTMLDivElement>(null);
  /** What takes the focus once the panel shows the change: the fee's outcome, what changed, or why the fee wasn't charged. */
  const [focusNext, setFocusNext] = useState<'outcome' | 'changed' | 'feeError' | null>(null);

  const setStatus = async (status: Status) => {
    setBusy(status);
    setError(null);
    setFeeError(null);
    setChanged(null);
    try {
      onChanged(await ownerApi.setStatus(appointment.id, status));
      setChanged(CHANGED[status]);
      setFocusNext('changed');
    } catch (caught) {
      // Shown at the top of what can be done, where the buttons are.
      setError(errorMessage(caught));
    } finally {
      setBusy(null);
    }
  };

  const chargeFee = async () => {
    setBusy('fee');
    setError(null);
    setFeeError(null);
    setChanged(null);
    try {
      onChanged(await ownerApi.chargeFee(appointment.id));
      setFocusNext('outcome');
    } catch (caught) {
      // Next to the fee's button, where the owner is: Stripe not connected offers Settings.
      setFeeError({ message: errorMessage(caught), settings: isApiError(caught) && caught.code === 'stripe_not_configured' });
      setFocusNext('feeError');
    } finally {
      setBusy(null);
    }
  };

  const voidSale = async (saleId: string) => {
    setBusy('void');
    try {
      await onVoidSale(saleId);
    } finally {
      setBusy(null);
    }
  };

  // After a change the button pressed may be gone: what happened takes the focus, so it's read
  // out (the fee's outcome: charged, declined, waiting on the client; or why it wasn't charged),
  // and comes into view.
  useEffect(() => {
    if (focusNext === null) return;
    const target = focusNext === 'outcome' ? outcome.current : focusNext === 'changed' ? changedLine.current : feeErrorLine.current;
    if (!target) return;
    setFocusNext(null);
    target.focus({ preventScroll: true });
    // (Optional: jsdom, where the unit tests run, has no scrolling.)
    target.scrollIntoView?.({ block: 'nearest' });
  }, [focusNext, appointment, feeError, changed]);

  const start = new Date(appointment.start);
  const panel = feePanel(appointment, now, zone);
  const payment = paymentSummary(appointment);
  const paid = paidLabel(appointment);
  const phone = appointment.customer.phone;
  const hint = noShowHint(appointment, now, zone);

  const reopen = () => {
    const warning = reopenWarning(appointment, now);
    if (warning) setConfirmReopen(warning);
    else void setStatus('booked');
  };

  return (
    <div className="biz-details" data-testid="appointment-details">
      <p className="biz-details__what">
        {appointment.serviceName} with {appointment.barberName}
      </p>
      <p className="biz-details__when">
        {shortDateLabel(localDate(start, zone))}, {timeRange(appointment, zone)}
      </p>
      <Badges badges={appointmentBadges(appointment)} testId="detail-badges" />

      {error ? (
        <p className="field__error biz-details__error" role="alert">
          <Icon name="error" />
          <span>{error}</span>
        </p>
      ) : null}

      <section className="biz-details__actions" aria-label="What you can do">
        {changed ? (
          <p className="biz-success biz-details__changed" role="status" tabIndex={-1} ref={changedLine} data-testid="status-changed">
            <Icon name="check" className="biz-success__icon" />
            <span>{changed}</span>
          </p>
        ) : null}
        {canCheckOut(appointment) ? (
          <div className="biz-checkout-call">
            <button type="button" className="button button--primary button--large button--block" onClick={onCheckOut} disabled={busy !== null}>
              Check out
            </button>
            <p className="secondary small">Cash or other payments. Card payments happen on the iPhone with Tap to Pay.</p>
          </div>
        ) : null}
        {appointment.sale ? (
          <div className="biz-paid" data-testid="detail-paid">
            <p className="biz-paid__title">
              <Icon name="check" className="biz-paid__icon" />
              {paid}
            </p>
            <p className="secondary small">To change this appointment (reopen, cancel or mark a no-show), void its sale first.</p>
            <button type="button" className="button button--secondary" onClick={() => void voidSale(appointment.sale!.id)} disabled={busy !== null}>
              {busy === 'void' ? 'Opening…' : 'Void sale'}
            </button>
          </div>
        ) : (
          <div className="biz-status-actions">
            {appointment.status === 'booked' ? (
              <>
                <button type="button" className="button button--secondary" onClick={() => void setStatus('completed')} disabled={busy !== null}>
                  {busy === 'completed' ? 'Marking…' : 'Mark done'}
                </button>
                {canMarkNoShow(appointment, now) ? (
                  <button type="button" className="button button--secondary" onClick={() => void setStatus('noShow')} disabled={busy !== null}>
                    {busy === 'noShow' ? 'Marking…' : 'Mark no-show'}
                  </button>
                ) : null}
                <button type="button" className="text-button text-button--danger" onClick={() => setConfirmCancel(true)} disabled={busy !== null}>
                  Cancel appointment
                </button>
              </>
            ) : (
              <button type="button" className="button button--secondary" onClick={reopen} disabled={busy !== null}>
                {busy === 'booked' ? 'Reopening…' : 'Reopen'}
              </button>
            )}
          </div>
        )}
        {!appointment.sale ? (
          <p className="secondary small biz-details__hint" data-testid="status-hint">
            {appointment.status === 'booked'
              ? `Cancelling frees the time for other clients.${hint ? ` ${hint}` : ''}`
              : appointment.status === 'cancelled'
                ? 'Reopening books the time again, if nobody else has taken it.'
                : 'Reopening sets it back to booked.'}
          </p>
        ) : null}
      </section>

      <dl className="biz-rows">
        <Row label="Client">{appointment.customer.name}</Row>
        <Row label="Phone">
          {phone ? (
            <a className="biz-call" href={`tel:${phone}`}>
              <Icon name="phone" className="biz-call__icon" />
              <span>
                Call <span className="nowrap">{displayPhone(phone)}</span>
              </span>
            </a>
          ) : (
            <span className="secondary">No phone number (booked at the shop).</span>
          )}
        </Row>
        {appointment.customer.email ? <Row label="Email">{appointment.customer.email}</Row> : null}
        <Row label="Service">{appointment.serviceName}</Row>
        <Row label="Price">{appointment.priceLabel}</Row>
        <Row label="Length">{durationLabel(appointment.durationMinutes)}</Row>
        {appointment.note ? (
          <Row label="Note" testId="detail-note">
            {appointment.note}
          </Row>
        ) : null}
        {appointment.status === 'cancelled' ? <Row label="Cancelled by">{appointment.cancelledBy === 'customer' ? 'The client' : 'The shop'}</Row> : null}
        {appointment.noShowFee?.customerCancelledAt ? (
          <Row label="Client cancelled in the app">{dateTimeLabel(new Date(appointment.noShowFee.customerCancelledAt), zone)}</Row>
        ) : null}
        <Row label={payment.title} testId="detail-payment">
          {payment.value}
        </Row>
      </dl>
      {payment.feeNote ? <p className="secondary small">{payment.feeNote}</p> : null}

      {panel ? (
        <section className="biz-fee" aria-labelledby="fee-title" data-testid="fee-panel">
          <h3 id="fee-title" className="biz-section-title">
            Card on file
          </h3>
          <dl className="biz-rows">
            <Row label="Card">{panel.cardLabel}</Row>
            <Row label="Fee agreed at booking">{panel.feeLabel}</Row>
          </dl>
          <p className="secondary small">{panel.agreement}</p>
          {panel.status.kind === 'notCharged' ? (
            panel.status.note ? (
              <p className="biz-fee__note" data-testid="fee-status">
                {panel.status.note}
              </p>
            ) : null
          ) : (
            <div ref={outcome} tabIndex={-1} className={`biz-fee__outcome biz-fee__outcome--${panel.status.kind}`} data-testid="fee-status">
              <p className="biz-fee__outcome-title">
                {panel.status.kind === 'charged'
                  ? panel.status.title
                  : panel.status.kind === 'declined'
                    ? 'Declined'
                    : panel.status.kind === 'needsClient'
                      ? 'The card needs the client to approve it'
                      : 'Not confirmed yet'}
              </p>
              <p>{panel.status.detail}</p>
            </div>
          )}
          {feeError ? (
            <div className="field__error biz-fee__error" role="alert" tabIndex={-1} ref={feeErrorLine} data-testid="fee-error">
              <Icon name="error" />
              <div>
                <p>{feeError.message}</p>
                {feeError.settings ? (
                  <Link className="button button--secondary biz-fee__settings" to="/business/settings">
                    Go to Settings
                  </Link>
                ) : null}
              </div>
            </div>
          ) : null}
          {panel.action ? (
            <button
              type="button"
              className="button button--secondary"
              // Not disabled while busy, only marked so: focus comes back to it when the question closes.
              aria-disabled={busy !== null || undefined}
              onClick={() => {
                if (busy !== null) return;
                if (panel.action!.confirmation) setConfirmFee(panel.action!.confirmation);
                else void chargeFee();
              }}
            >
              {busy === 'fee' ? (panel.action.confirmation ? 'Charging…' : 'Checking…') : panel.action.title}
            </button>
          ) : null}
          {panel.footer ? <p className="secondary small">{panel.footer}</p> : null}
        </section>
      ) : null}

      <Dialog
        open={confirmCancel}
        title={`Cancel ${appointment.customer.name}'s appointment?`}
        onClose={() => setConfirmCancel(false)}
        testId="confirm-cancel"
        actions={
          <>
            <button type="button" className="button button--secondary" onClick={() => setConfirmCancel(false)}>
              Keep it
            </button>
            <button
              type="button"
              className="button button--danger"
              onClick={() => {
                setConfirmCancel(false);
                void setStatus('cancelled');
              }}
            >
              Cancel appointment
            </button>
          </>
        }
      >
        <p>
          {timeLabel(start, zone)} with {appointment.barberName}. The time opens up for other clients. Izzy Clipz Business doesn't message the client, so let
          them know.{shopCancelNote(appointment) ? ` ${shopCancelNote(appointment)}` : ''}
        </p>
      </Dialog>

      <Dialog
        open={confirmReopen !== null}
        title={`Reopen ${appointment.customer.name}'s appointment?`}
        onClose={() => setConfirmReopen(null)}
        testId="confirm-reopen"
        actions={
          <>
            <button type="button" className="button button--secondary" onClick={() => setConfirmReopen(null)}>
              Keep it as it is
            </button>
            <button
              type="button"
              className="button button--primary"
              onClick={() => {
                setConfirmReopen(null);
                void setStatus('booked');
              }}
            >
              Reopen
            </button>
          </>
        }
      >
        <p>{confirmReopen}</p>
      </Dialog>

      <Dialog
        open={confirmFee !== null}
        title={confirmFee?.title ?? ''}
        onClose={() => setConfirmFee(null)}
        testId="confirm-fee"
        actions={
          <>
            <button type="button" className="button button--secondary" onClick={() => setConfirmFee(null)}>
              Don't charge
            </button>
            <button
              type="button"
              className="button button--primary"
              onClick={() => {
                setConfirmFee(null);
                void chargeFee();
              }}
            >
              {confirmFee?.button}
            </button>
          </>
        }
      >
        <p>{confirmFee?.message}</p>
      </Dialog>
    </div>
  );
}
