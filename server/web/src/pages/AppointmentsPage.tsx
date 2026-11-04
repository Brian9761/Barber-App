import { useCallback, useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api, ErrorCode, errorMessage, isApiError } from '../api/client';
import type { Catalog } from '../api/types';
import { clearDraft } from '../booking/flow';
import { forgetLastBooked } from '../booking/lastBooked';
import { CatalogGate } from '../components/CatalogGate';
import { Dialog } from '../components/Dialog';
import { useNow } from '../components/hooks';
import { Icon } from '../components/Icon';
import { CallLink, Notice, PreferToCall } from '../components/ui';
import { usePageMeta } from '../components/usePageMeta';
import { cardLabel, durationLabel } from '../lib/format';
import { useOnline } from '../pwa/connection';
import { appointmentEvent, downloadIcs, icsFile } from '../lib/ics';
import { isCancellable, lateCancelWarning } from '../lib/lateCancel';
import { dateTimeLabel, longDateTimeLabel } from '../lib/shopTime';
import {
  forgetAppointments,
  forgetClient,
  loadAppointments,
  loadCard,
  loadRememberedDetails,
  removeAppointment,
  updateAppointment,
  type ListedAppointment,
  type SavedAppointment,
} from '../lib/storage';

export function AppointmentsPage() {
  usePageMeta('My appointments', 'The appointments you booked on this computer at Izzy Clipz Barbershop: check them, add them to your calendar, or cancel.');
  return (
    <>
      <header className="page-header container">
        <h1>My appointments</h1>
        <p className="lead secondary">The appointments booked on this computer. Check them, add them to your calendar, or cancel.</p>
        <PreferToCall className="page-header__call" />
      </header>
      <CatalogGate>{(catalog) => <AppointmentList catalog={catalog} />}</CatalogGate>
    </>
  );
}

/** Up to a day after it ended, an appointment is still checked with the shop (it may be marked done). */
const CHECK_AFTER_END_MS = 24 * 60 * 60_000;

/** Whether this computer keeps anything of the client's: appointments, their details or a card. */
function remembersAnything(saved: SavedAppointment[]): boolean {
  return saved.length > 0 || loadRememberedDetails() !== null || loadCard() !== null;
}

/**
 * "Forget me on this computer": the name, number and email, the card, the booking in
 * progress and the appointments listed here. The appointments stay booked with the shop.
 */
function forgetThisComputer(): void {
  forgetClient();
  forgetAppointments();
  clearDraft();
  forgetLastBooked();
}

function AppointmentList({ catalog }: { catalog: Catalog }) {
  const now = useNow();
  const [saved, setSaved] = useState<SavedAppointment[]>(() => loadAppointments());
  const [refreshError, setRefreshError] = useState<string | null>(null);
  const [forgotten, setForgotten] = useState(false);
  const online = useOnline();
  // Offline, the page doesn't show what it last heard from the shop: it could have changed since.
  const [offline, setOffline] = useState(() => !online);
  const [attempt, setAttempt] = useState(0);
  const reload = useCallback(() => setSaved(loadAppointments()), []);
  const forget = () => {
    forgetThisComputer();
    setForgotten(true);
    reload();
  };
  const forgottenNotice = forgotten ? (
    <Notice tone="success" role="status" testId="forgotten-notice">
      <p>Done. This computer no longer keeps your details, card or appointments. Your appointments are still booked with the shop.</p>
    </Notice>
  ) : null;

  // Check each one with the shop: it may have been cancelled by the shop, or completed. With no
  // connection, the page says so instead, and checks again once the connection is back.
  useEffect(() => {
    if (!online) {
      setOffline(true);
      return;
    }
    let live = true;
    (async () => {
      const current = loadAppointments();
      let failure: string | null = null;
      let unreachable = false;
      for (const item of current) {
        if (item.notFound || new Date(item.appointment.end).getTime() < Date.now() - CHECK_AFTER_END_MS) continue;
        try {
          const fresh = await api.appointment(item.id, item.manageToken);
          updateAppointment(item.id, (s) => ({ ...s, appointment: fresh, checkedAt: new Date().toISOString() }));
        } catch (error) {
          if (isApiError(error) && (error.code === ErrorCode.notFound || error.code === ErrorCode.unauthorized)) {
            updateAppointment(item.id, (s) => ({ ...s, notFound: true }));
          } else {
            failure = errorMessage(error);
            if (isApiError(error) && error.isOffline) {
              unreachable = true;
              break;
            }
          }
        }
      }
      if (live) {
        setOffline(unreachable);
        setRefreshError(unreachable ? null : failure);
        reload();
      }
    })();
    return () => {
      live = false;
    };
  }, [reload, online, attempt]);

  const upcoming = saved.filter((s) => new Date(s.appointment.end) > now);
  const past = saved.filter((s) => new Date(s.appointment.end) <= now).reverse();
  const next = upcoming.find((s) => s.appointment.status === 'booked');

  if (offline && saved.length > 0) {
    return (
      <div className="container container--narrow appointments">
        <div className="status-message card card--gray" role="status" data-testid="appointments-offline">
          <h2>You're offline.</h2>
          <p className="lead secondary">Your appointments show here again once you're back online and they're checked with the shop.</p>
          <p className="secondary">
            To check or change one now, call the shop at <CallLink className="inline-link nowrap" />.
          </p>
          <button type="button" className="button button--primary" onClick={() => setAttempt((n) => n + 1)}>
            Try again
          </button>
        </div>
        <ForgetComputer catalog={catalog} onForget={forget} />
      </div>
    );
  }

  if (saved.length === 0) {
    return (
      <div className="container container--narrow appointments">
        {forgottenNotice}
        <div className="status-message card card--gray">
          <h2>No appointments booked on this computer yet.</h2>
          <p className="lead secondary">When you book here, your appointment shows up on this page, so you can check it or cancel it.</p>
          <Link className="button button--primary button--large" to="/book">
            Book an appointment
          </Link>
          <p className="secondary">
            Booked in the Izzy Clipz app or by phone? Check it in the app, or call the shop at <CallLink className="inline-link nowrap" />.
          </p>
        </div>
        {remembersAnything(saved) ? <ForgetComputer catalog={catalog} onForget={forget} /> : null}
      </div>
    );
  }

  return (
    <div className="container container--narrow appointments">
      {refreshError ? (
        <Notice tone="info" role="status">
          <p>Couldn't check for changes. {refreshError}</p>
        </Notice>
      ) : null}
      <section aria-labelledby="upcoming-title" className="appointments__section">
        <h2 id="upcoming-title" className="appointments__heading">
          Upcoming
        </h2>
        {upcoming.length === 0 ? <p className="lead secondary">Nothing booked right now.</p> : null}
        <ul className="appointment-list">
          {upcoming.map((item) => (
            <li key={item.id}>
              <AppointmentCard catalog={catalog} item={item} isNext={item.id === next?.id} now={now} onChange={reload} />
            </li>
          ))}
        </ul>
      </section>
      {past.length > 0 ? (
        <section aria-labelledby="past-title" className="appointments__section">
          <h2 id="past-title" className="appointments__heading">
            Past
          </h2>
          <ul className="appointment-list">
            {past.map((item) => (
              <li key={item.id}>
                <AppointmentCard catalog={catalog} item={item} isNext={false} now={now} onChange={reload} />
              </li>
            ))}
          </ul>
        </section>
      ) : null}
      <div className="appointments__footer">
        <Link className="button button--secondary" to="/book">
          Book another appointment
        </Link>
      </div>
      <ForgetComputer catalog={catalog} onForget={forget} />
    </div>
  );
}

/** For a shared computer: forget the client here, after asking (and saying the appointments stay booked). */
function ForgetComputer({ catalog, onForget }: { catalog: Catalog; onForget: () => void }) {
  const [asking, setAsking] = useState(false);
  return (
    <section className="forget-computer" aria-labelledby="forget-title" data-testid="forget-computer">
      <h2 id="forget-title" className="forget-computer__title">
        Not you, or on a shared computer?
      </h2>
      <p className="secondary">
        This computer can forget your name, number, saved card and the appointments listed here. They stay booked with the shop.
      </p>
      <div>
        <button type="button" className="button button--secondary" onClick={() => setAsking(true)}>
          Forget me on this computer
        </button>
      </div>
      <Dialog
        open={asking}
        title="Forget me on this computer?"
        onClose={() => setAsking(false)}
        testId="forget-dialog"
        actions={
          <>
            <button type="button" className="button button--secondary" onClick={() => setAsking(false)} autoFocus>
              Keep everything
            </button>
            <button
              type="button"
              className="button button--primary"
              data-testid="confirm-forget"
              onClick={() => {
                setAsking(false);
                onForget();
              }}
            >
              Forget me
            </button>
          </>
        }
      >
        <p>This computer will forget your name and number, your saved card, and the appointments listed here.</p>
        <p>
          Your appointments stay booked. To change one later, call the shop at <span className="nowrap">{catalog.shop.phone.display}</span>.
        </p>
      </Dialog>
    </section>
  );
}

/** "Next appointment", "Booked", "Cancelled by the shop", "Completed", "Missed"… in words, with a dot. */
function statusText(a: ListedAppointment, isNext: boolean, now: Date): { text: string; tone: 'go' | 'stop' | 'done' | 'muted' } {
  const ended = new Date(a.end) <= now;
  switch (a.status) {
    case 'booked':
      if (ended) return { text: 'Finished', tone: 'muted' };
      if (new Date(a.start) <= now) return { text: 'Happening now', tone: 'go' };
      return { text: isNext ? 'Next appointment' : 'Booked', tone: 'go' };
    case 'cancelled':
      return { text: a.cancelledBy === 'shop' ? 'Cancelled by the shop' : 'Cancelled', tone: 'stop' };
    case 'completed':
      return { text: 'Completed', tone: 'done' };
    case 'noShow':
      return { text: 'Missed', tone: 'muted' };
  }
}

type CancelStep = { warning: string | null; fromServer: boolean } | null;

function AppointmentCard({
  catalog,
  item,
  isNext,
  now,
  onChange,
}: {
  catalog: Catalog;
  item: SavedAppointment;
  isNext: boolean;
  now: Date;
  onChange: () => void;
}) {
  const a = item.appointment;
  const zone = catalog.timeZone;
  const status = statusText(a, isNext, now);
  const isOn = a.status === 'booked' && new Date(a.end) > now;
  const canCancel = !item.notFound && isCancellable(a, now);
  const [confirm, setConfirm] = useState<CancelStep>(null);
  const [cancelling, setCancelling] = useState(false);
  const [problem, setProblem] = useState<string | null>(null);
  const [done, setDone] = useState(false);
  const title = `${a.serviceName} with ${a.barberName}`;

  const askToCancel = () => {
    setProblem(null);
    setConfirm({ warning: lateCancelWarning(a, new Date()), fromServer: false });
  };

  const cancel = async (accepted: boolean) => {
    setConfirm(null);
    setCancelling(true);
    try {
      const fresh = await api.cancel(item.id, item.manageToken, accepted);
      updateAppointment(item.id, (s) => ({ ...s, appointment: fresh, checkedAt: new Date().toISOString() }));
      setDone(true);
      onChange();
    } catch (error) {
      if (isApiError(error) && error.code === ErrorCode.lateCancelFee) {
        // The shop's clock says it's inside the window now: say so, and ask again.
        setConfirm({ warning: error.message, fromServer: true });
      } else if (isApiError(error) && (error.code === ErrorCode.notFound || error.code === ErrorCode.unauthorized)) {
        updateAppointment(item.id, (s) => ({ ...s, notFound: true }));
        setProblem(`This computer can't change this appointment anymore. Call the shop at ${catalog.shop.phone.display} to cancel it.`);
        onChange();
      } else if (isApiError(error) && error.code === ErrorCode.notCancellable) {
        // It changed at the shop (or has started): show how it is now.
        try {
          const latest = await api.appointment(item.id, item.manageToken);
          updateAppointment(item.id, (s) => ({ ...s, appointment: latest, checkedAt: new Date().toISOString() }));
          onChange();
          if (latest.status === 'cancelled' && latest.cancelledBy === 'customer') {
            setDone(true);
            return;
          }
        } catch {
          // Shown below as it was.
        }
        setProblem(error.message);
      } else {
        setProblem(errorMessage(error));
      }
    } finally {
      setCancelling(false);
    }
  };

  const note = item.notFound
    ? "This computer can't check this appointment with the shop anymore. Call the shop if anything changed."
    : a.status === 'cancelled' && a.cancelledBy === 'shop'
      ? 'The shop cancelled this appointment. Book another time, or call the shop.'
      : null;

  return (
    <article className="appointment card" aria-labelledby={`appointment-${item.id}`} data-testid="appointment-card">
      <p className={`appointment__status appointment__status--${status.tone}`} data-testid="appointment-status">
        <span className="appointment__dot" aria-hidden="true" />
        {status.text}
      </p>
      <h3 id={`appointment-${item.id}`} className={`appointment__when${a.status === 'cancelled' ? ' is-cancelled' : ''}`}>
        {dateTimeLabel(new Date(a.start), zone)}
      </h3>
      <p className="appointment__what">{title}</p>
      <p className="secondary">
        {a.priceLabel} · {durationLabel(a.durationMinutes)}
        {isOn ? ' · Pay at the shop' : ''}
      </p>
      {a.card ? (
        <p className="appointment__card">
          <Icon name="card" className="inline-icon" /> Card on file: {cardLabel(a.card)}
        </p>
      ) : null}
      {note ? <p className="appointment__note">{note}</p> : null}
      {done ? (
        <Notice tone="success" role="status">
          <p>Appointment cancelled. The shop sees it right away.</p>
        </Notice>
      ) : null}
      {problem ? (
        <Notice tone="error" role="alert" title="Couldn't cancel">
          <p>{problem}</p>
        </Notice>
      ) : null}

      <div className="appointment__actions">
        {isOn ? (
          <>
            <button
              type="button"
              className="button button--secondary"
              onClick={() => downloadIcs('izzy-clipz-appointment.ics', icsFile(appointmentEvent(a, catalog.shop, window.location.origin)))}
            >
              <Icon name="calendar" className="button__icon" /> Add to calendar
            </button>
            <Link className="button button--secondary" to="/visit">
              <Icon name="pin" className="button__icon" /> Directions
            </Link>
            {canCancel ? (
              <button type="button" className="text-button text-button--danger appointment__cancel" onClick={askToCancel} disabled={cancelling}>
                {cancelling ? 'Cancelling…' : 'Cancel appointment'}
              </button>
            ) : (
              <CallLink className="button button--secondary">
                <Icon name="phone" className="button__icon" /> Call the shop to change it
              </CallLink>
            )}
          </>
        ) : (
          <>
            {a.status === 'cancelled' && a.cancelledBy === 'shop' && new Date(a.end) > now ? (
              <Link className="button button--primary" to={`/book?service=${encodeURIComponent(a.serviceId)}`}>
                Book another time
              </Link>
            ) : null}
            <button
              type="button"
              className="text-button"
              onClick={() => {
                removeAppointment(item.id);
                onChange();
              }}
            >
              Remove from this list
            </button>
          </>
        )}
      </div>

      <Dialog
        open={confirm !== null}
        title="Cancel this appointment?"
        onClose={() => setConfirm(null)}
        testId="cancel-dialog"
        actions={
          <>
            <button type="button" className="button button--secondary" onClick={() => setConfirm(null)} autoFocus>
              Keep appointment
            </button>
            <button
              type="button"
              className="button button--danger"
              data-testid="confirm-cancel"
              onClick={() => {
                // The fee is accepted only when the warning was shown. If the minute turned while the
                // question was open, the server says so (409 late_cancel_fee) and the warning shows then.
                void cancel(confirm?.warning != null);
              }}
            >
              Cancel appointment
            </button>
          </>
        }
      >
        {confirm?.warning ? (
          <p className="dialog__warning" data-testid="late-cancel-warning">
            <Icon name="warning" className="inline-icon" /> {confirm.warning}
          </p>
        ) : null}
        <p>
          {title}, {longDateTimeLabel(new Date(a.start), zone)}. The shop sees it right away.
        </p>
      </Dialog>
    </article>
  );
}
