import { Link, Navigate, useLocation } from 'react-router-dom';
import type { Appointment, Catalog } from '../api/types';
import { Icon } from '../components/Icon';
import { MoreLink, Notice, PreferToCall } from '../components/ui';
import { usePageMeta } from '../components/usePageMeta';
import { DemoNotice } from '../demo/DemoNotice';
import { isDemo } from '../demo/mode';
import { cardLabel, durationLabel, list } from '../lib/format';
import { appointmentEvent, downloadIcs, icsFile } from '../lib/ics';
import { longDateTimeLabel } from '../lib/shopTime';
import { loadAppointments, type ListedAppointment } from '../lib/storage';
import { thisDevice } from '../pwa/platform';
import { lastBookedId } from './lastBooked';

interface ConfirmationState {
  appointment?: Appointment;
  /** False when this browser couldn't keep the appointment and its token. */
  saved?: boolean;
}

/**
 * "You're booked": the appointment as the shop booked it (with the barber it
 * picked for "Any barber"), Add to calendar, Manage or cancel, Book another, and
 * the pay-at-the-shop line. It replaces the review step, so going back can't book
 * the same time twice.
 *
 * In the demo it's "Demo booking made", with the demo notice right under it, on
 * the first screen of a phone: nobody should leave thinking the shop has it. Its
 * calendar file says so too, and has no reminder.
 */
export function ConfirmationPage({ catalog }: { catalog: Catalog }) {
  const demo = isDemo();
  usePageMeta(
    demo ? 'Demo booking made' : "You're booked",
    demo
      ? "A booking made in the demo version of the Izzy Clipz website. It isn't sent to the shop."
      : 'Your appointment at Izzy Clipz Barbershop is booked. No payment now: you pay at the shop.',
  );
  const device = thisDevice();
  const location = useLocation();
  const state = (location.state as ConfirmationState | null) ?? {};
  const fromStorage = loadAppointments().find((s) => s.id === lastBookedId())?.appointment;
  const appointment: ListedAppointment | undefined = state.appointment ?? fromStorage;
  if (!appointment) return <Navigate to="/appointments" replace />;
  const saved = state.saved ?? true;
  const shop = catalog.shop;

  const addToCalendar = () => {
    downloadIcs('izzy-clipz-appointment.ics', icsFile(appointmentEvent(appointment, shop, window.location.origin)));
  };

  return (
    <section className="container container--narrow confirmation" aria-labelledby="booked-title">
      <div className="confirmation__header">
        <Icon name="check" className="confirmation__icon" />
        <h1 id="booked-title" data-testid="booked-title">
          {demo ? 'Demo booking made' : "You're booked"}
        </h1>
        {demo ? <DemoNotice /> : null}
        <p className="lead secondary">
          {demo
            ? `It's saved in My appointments on this ${device}, where you can cancel it too.`
            : `See you at ${shop.name}. It's saved in My appointments on this ${device}.`}
        </p>
      </div>

      <dl className="review-summary card" data-testid="booked-summary">
        <ConfirmationRow label="When" value={longDateTimeLabel(new Date(appointment.start), catalog.timeZone)} />
        <ConfirmationRow label="Service" value={appointment.serviceName} detail={`${appointment.priceLabel} · ${durationLabel(appointment.durationMinutes)}`} />
        <ConfirmationRow label="Barber" value={appointment.barberName} />
        <ConfirmationRow label="Where" value={shop.address.lines[0] ?? ''} detail={shop.address.lines.slice(1).join(', ')} />
        {appointment.card ? <ConfirmationRow label="Card on file" value={cardLabel(appointment.card)} detail="Nothing is charged now." /> : null}
      </dl>

      <Notice tone="success" title="No payment now. You'll pay at the shop.">
        <p>Pay at the shop with a {list(shop.paymentMethods.map((m) => m.toLowerCase()))}.</p>
      </Notice>

      {!saved ? (
        <Notice tone="warning" title="Write this one down">
          <p>
            This browser couldn't save your appointment, so you can't change or cancel it here later. To change or cancel it, call the shop at{' '}
            <a href={`tel:${shop.phone.e164}`}>{shop.phone.display}</a>.
          </p>
        </Notice>
      ) : null}

      <div className="actions confirmation__actions">
        <button type="button" className="button button--primary button--large" onClick={addToCalendar}>
          <Icon name="calendar" className="button__icon" /> Add to calendar
        </button>
        <Link className="button button--secondary button--large" to="/appointments">
          Manage or cancel
        </Link>
        <MoreLink to="/book">Book another</MoreLink>
      </div>
      <PreferToCall />
    </section>
  );
}

function ConfirmationRow({ label, value, detail }: { label: string; value: string; detail?: string }) {
  return (
    <div className="summary-row">
      <dt className="summary-row__label">{label}</dt>
      <dd className="summary-row__value">{value}</dd>
      {detail ? <dd className="summary-row__detail">{detail}</dd> : null}
    </div>
  );
}
