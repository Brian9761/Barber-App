// One appointment, as the owner app's details show it: the client (tap to call), what and
// when, the note, the card on file and its fee, the payment or sale, and what the owner
// can do now: Check out (cash or other), Mark done, No-show once it has started, Cancel or
// Reopen as the app allows, and charge the agreed fee to the card on file (asking first,
// naming the card). A checked-out appointment changes only once its sale is voided.

import { useEffect, useRef, useState } from 'react';
import { errorMessage } from '../../../api/errors';
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
  /** Void the appointment's sale (Today's sales does the asking). */
  onVoidSale: (saleId: string) => void;
}) {
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [confirmCancel, setConfirmCancel] = useState(false);
  const [confirmReopen, setConfirmReopen] = useState<string | null>(null);
  const [confirmFee, setConfirmFee] = useState<FeeConfirmation | null>(null);

  const outcome = useRef<HTMLDivElement>(null);
  const [showOutcome, setShowOutcome] = useState(false);

  /** Makes the change; false when it didn't go through (the error shows at the top). */
  const run = async (label: string, change: () => Promise<OwnerAppointment>): Promise<boolean> => {
    setBusy(label);
    setError(null);
    try {
      onChanged(await change());
      return true;
    } catch (caught) {
      setError(errorMessage(caught));
      return false;
    } finally {
      setBusy(null);
    }
  };
  const setStatus = (status: Status) => run(status, () => ownerApi.setStatus(appointment.id, status));
  const chargeFee = async () => {
    if (await run('fee', () => ownerApi.chargeFee(appointment.id))) setShowOutcome(true);
  };

  // After a charge the button is gone: the outcome (charged, declined, waiting on the client)
  // takes the focus, so it's read out, and comes into view.
  useEffect(() => {
    if (!showOutcome || !outcome.current) return;
    setShowOutcome(false);
    outcome.current.focus({ preventScroll: true });
    // (Optional: jsdom, where the unit tests run, has no scrolling.)
    outcome.current.scrollIntoView?.({ block: 'nearest' });
  }, [showOutcome, appointment]);

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
            <button type="button" className="button button--secondary" onClick={() => onVoidSale(appointment.sale!.id)}>
              Void sale
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
          {panel.action ? (
            <button
              type="button"
              className="button button--secondary"
              disabled={busy !== null}
              onClick={() => (panel.action!.confirmation ? setConfirmFee(panel.action!.confirmation) : void chargeFee())}
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
