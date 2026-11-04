import { useState, type ReactNode } from 'react';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import { api, ErrorCode, isApiError, errorMessage } from '../api/client';
import type { BookingTarget, Catalog, NoShowPolicy } from '../api/types';
import { useNow } from '../components/hooks';
import { Icon } from '../components/Icon';
import { CallLink, Loading, Notice } from '../components/ui';
import { cardLabel, list } from '../lib/format';
import { leaveTo } from '../lib/leave';
import { parseUSPhone, toE164 } from '../lib/phone';
import { dateTimeLabel, localDate } from '../lib/shopTime';
import {
  cardValidOn,
  forgetCard,
  loadAppointments,
  loadCard,
  saveAppointment,
  savePendingCheckout,
  type StoredCard,
} from '../lib/storage';
import { newToken } from '../lib/tokens';
import { useBooking } from './BookingContext';
import { bookingFailure, failureTitle, noLongerBooked, summarize, type BookingFailure } from './describe';
import { retryKey, saveDraft, STEP_PATHS, targetOf, type BookingDraft, type Step } from './flow';
import { rememberLastBooked } from './lastBooked';
import { BookingLayout, StepHeader } from './StepChrome';
import { FeeWarning } from './TimeStep';
import { useNoShowPolicy } from './usePolicy';

/** Where Stripe's card page sends the client back to, through the server. */
export interface ReviewLocationState {
  from?: string;
  /** Set by the card return page: why there's no card ("Your card wasn't added."). */
  cardNotice?: string;
}

/**
 * Step 5: everything on one card (each part with "Change"), the fee notice when the
 * shop's policy needs a card, "No payment now", the card on file, and "Book
 * appointment". If booking fails, it says why in plain words and offers the way
 * forward, like the app: a taken time goes back to the times, a problem with the
 * details goes back to them, a lost answer offers "Try again" (which can't book
 * twice), and a limit says which one.
 */
export function ReviewStep({ catalog }: { catalog: Catalog }) {
  const { draft } = useBooking();
  const target = targetOf(draft);
  if (!target || !draft.start || !draft.details) return null;
  return <Review catalog={catalog} draft={draft} target={target} start={draft.start} />;
}

function Review({ catalog, draft, target, start }: { catalog: Catalog; draft: BookingDraft; target: BookingTarget; start: string }) {
  const { dispatch } = useBooking();
  const navigate = useNavigate();
  const location = useLocation();
  const details = draft.details!;
  const zone = catalog.timeZone;
  const now = useNow();
  const summary = summarize(catalog, draft);
  const { state: policyState, reload: reloadPolicy } = useNoShowPolicy(target);
  const [card, setCard] = useState<StoredCard | null>(() => loadCard());
  const [booking, setBooking] = useState(false);
  const [failure, setFailure] = useState<BookingFailure | null>(null);
  const [cardMessage, setCardMessage] = useState<string | null>((location.state as ReviewLocationState | null)?.cardNotice ?? null);
  const [addingCard, setAddingCard] = useState(false);
  const [policyNote, setPolicyNote] = useState<string | null>(null);

  const policy = policyState.status === 'ready' ? policyState.policy : null;
  const needsCard = policy?.required === true;
  const appointmentDay = localDate(new Date(start), zone);
  const usableCard = card && cardValidOn(card.card, appointmentDay) ? card : null;
  const expiredCard = card && !usableCard ? card : null;
  const canBook = policy !== null && (!needsCard || usableCard !== null) && !booking;

  const change = (step: Step) => navigate(STEP_PATHS[step], { state: { from: STEP_PATHS.review } });

  async function addCard() {
    setAddingCard(true);
    setCardMessage(null);
    const token = newToken();
    try {
      const checkout = await api.startCardCheckout(target, token);
      savePendingCheckout({ token, remember: details.remember, sessionId: checkout.sessionId });
      saveDraft(draft);
      leaveTo(checkout.url);
    } catch (error) {
      setAddingCard(false);
      if (isApiError(error) && error.code === ErrorCode.invalidRequest) reloadPolicy();
      setCardMessage(
        isApiError(error) && error.code === ErrorCode.stripeNotConfigured
          ? "The shop can't take cards online right now. Call the shop to book this time."
          : errorMessage(error),
      );
    }
  }

  async function book() {
    if (!policy || booking) return;
    const digits = parseUSPhone(details.phone);
    if (!digits) {
      setFailure({ kind: 'details', message: 'Enter a 10-digit US number, like (442) 341-3053.' });
      return;
    }
    setBooking(true);
    setFailure(null);
    setPolicyNote(null);
    const phone = toE164(digits);
    // The same booking tried again (after a lost answer) goes with the same token, so it can't book twice.
    const key = retryKey(target, start, phone);
    let token = draft.pending?.key === key ? draft.pending.token : null;
    if (!token) {
      token = newToken();
      dispatch({ type: 'pending', key, token });
      saveDraft({ ...draft, pending: { key, token } });
    }
    try {
      const confirmation = await api.book(
        {
          target,
          start,
          customer: { name: details.name, phone, ...(details.email ? { email: details.email } : {}) },
          ...(details.note ? { note: details.note } : {}),
          ...(needsCard && policy.policyText ? { noShowPolicy: policy.policyText } : {}),
        },
        token,
        needsCard ? usableCard?.token : undefined,
      );
      const saved = saveAppointment(confirmation.appointment, confirmation.manageToken);
      if (confirmation.appointment.status !== 'booked') {
        // A retry found the booking an earlier try made, but it isn't on any more.
        dispatch({ type: 'timeGone', message: noLongerBooked(confirmation.appointment, zone) });
        navigate(STEP_PATHS.time, { state: { from: STEP_PATHS.review } });
        return;
      }
      rememberLastBooked(confirmation.appointment.id);
      dispatch({ type: 'booked' });
      navigate('/book/confirmed', { replace: true, state: { appointment: confirmation.appointment, saved } });
    } catch (error) {
      setBooking(false);
      const found = bookingFailure(error, new Date(start), zone);
      switch (found.kind) {
        case 'timeGone':
          // Back to the times, checked again, saying what happened.
          dispatch({ type: 'timeGone', message: found.message });
          navigate(STEP_PATHS.time, { state: { from: STEP_PATHS.review } });
          return;
        case 'card':
          // The card can't hold this booking (unknown, or it expires too soon): add one.
          forgetCard();
          setCard(null);
          setCardMessage(found.message);
          return;
        case 'policy':
          // The shop just changed its policy: show the new one, then book again.
          reloadPolicy();
          setPolicyNote(found.message);
          return;
        default:
          setFailure(found);
      }
    }
  }

  return (
    <BookingLayout catalog={catalog}>
      <StepHeader step="review" title="Review and book" />

      <dl className="review-summary card">
        <ReviewRow label="Service" value={summary.serviceName ?? ''} detail={`${summary.priceLabel} · ${summary.durationLabel}`} onChange={() => change('service')} changeLabel="Change service" />
        <ReviewRow label="Barber" value={summary.barberName ?? ''} detail={summary.barberDetail} onChange={() => change('barber')} changeLabel="Change barber" />
        <ReviewRow label="Day and time" value={dateTimeLabel(new Date(start), zone)} onChange={() => change('time')} changeLabel="Change day and time" />
        <ReviewRow
          label="Your details"
          value={details.name}
          detail={[details.phone, details.email].filter(Boolean).join(' · ')}
          onChange={() => change('details')}
          changeLabel="Change your details"
        />
        {details.note ? <ReviewRow label="Note for your barber" value={details.note} onChange={() => change('details')} changeLabel="Change the note" /> : null}
      </dl>

      {policyNote ? (
        <Notice tone="info" role="alert" title="The shop just changed its policy">
          <p>{policyNote}</p>
        </Notice>
      ) : null}
      {policy ? <FeeWarning policy={policy} start={start} now={now} /> : null}

      <Notice tone="success" title="No payment now. You'll pay at the shop.">
        <p>Pay at the shop with a {list(catalog.shop.paymentMethods.map((m) => m.toLowerCase()))}.</p>
      </Notice>

      {policyState.status === 'loading' ? <Loading text="Checking the booking rules…" /> : null}
      {policyState.status === 'error' ? (
        <Notice
          tone="error"
          role="alert"
          title="Couldn't check the booking rules"
          actions={
            <button type="button" className="button button--primary" onClick={reloadPolicy}>
              Try again
            </button>
          }
        >
          <p>{policyState.message}</p>
        </Notice>
      ) : null}

      {policy && needsCard ? (
        <CardSection
          policy={policy}
          card={usableCard}
          expired={expiredCard !== null}
          adding={addingCard}
          message={cardMessage}
          onAdd={() => void addCard()}
        />
      ) : null}

      {failure ? <FailureNotice failure={failure} retrying={booking} onRetry={() => void book()} onEditDetails={() => change('details')} /> : null}

      <div className="step-actions">
        <button type="button" className="button button--primary button--large step-actions__continue" disabled={!canBook} onClick={() => void book()} data-testid="book-button">
          {booking ? 'Booking…' : 'Book appointment'}
        </button>
        <p className="step-actions__note" aria-live="polite">
          {needsCard && !usableCard ? 'Add a card first to book this time.' : 'No payment now. You can cancel online any time before your appointment starts.'}
        </p>
      </div>
    </BookingLayout>
  );
}

function ReviewRow({
  label,
  value,
  detail,
  onChange,
  changeLabel,
}: {
  label: string;
  value: string;
  detail?: string | null;
  onChange: () => void;
  changeLabel: string;
}) {
  return (
    <div className="summary-row">
      <dt className="summary-row__label">{label}</dt>
      <dd className="summary-row__value">{value}</dd>
      {detail ? <dd className="summary-row__detail">{detail}</dd> : null}
      <dd className="summary-row__action">
        <button type="button" className="text-button" onClick={onChange} aria-label={changeLabel}>
          Change
        </button>
      </dd>
    </div>
  );
}

/** The card on file: "Visa •••• 4242 · Change", or "Add a card" (Stripe's own page). */
function CardSection({
  policy,
  card,
  expired,
  adding,
  message,
  onAdd,
}: {
  policy: NoShowPolicy;
  card: StoredCard | null;
  expired: boolean;
  adding: boolean;
  message: string | null;
  onAdd: () => void;
}) {
  return (
    <section className="card card-section" aria-labelledby="card-title" data-testid="card-section">
      <h2 id="card-title" className="card-section__title">
        Card on file
      </h2>
      {card ? (
        <p className="card-on-file">
          <span className="card-on-file__label" data-testid="card-label">
            <Icon name="card" /> {cardLabel(card.card)}
          </span>
          <span aria-hidden="true">·</span>
          <button type="button" className="text-button" onClick={onAdd} disabled={adding} aria-label="Change card">
            {adding ? 'Opening Stripe…' : 'Change'}
          </button>
        </p>
      ) : (
        <>
          <p>
            {expired
              ? 'Your saved card expires before this appointment. Add another card to hold it.'
              : "This time needs a card on file to hold it. Nothing is charged now."}
          </p>
          <div>
            <button type="button" className="button button--primary" onClick={onAdd} disabled={adding}>
              {adding ? 'Opening Stripe…' : 'Add a card'}
            </button>
          </div>
          <p className="secondary">You'll add it on Stripe's secure page, then come right back here. The shop never sees your card number.</p>
        </>
      )}
      {policy.policyText ? (
        <div className="card-section__policy">
          <p className="card-section__policy-label">What you agree to by booking</p>
          <p>{policy.policyText}</p>
        </div>
      ) : null}
      {message ? (
        <Notice tone="error" role="alert">
          <p>{message}</p>
        </Notice>
      ) : null}
    </section>
  );
}

function FailureNotice({
  failure,
  retrying,
  onRetry,
  onEditDetails,
}: {
  failure: BookingFailure;
  retrying: boolean;
  onRetry: () => void;
  onEditDetails: () => void;
}) {
  const hasAppointments = loadAppointments().length > 0;
  let action: ReactNode = null;
  if (failure.kind === 'offline' || failure.kind === 'other') {
    action = (
      <button type="button" className="button button--primary" onClick={onRetry} disabled={retrying}>
        {retrying ? 'Trying again…' : 'Try again'}
      </button>
    );
  } else if (failure.kind === 'details') {
    action = (
      <button type="button" className="button button--primary" onClick={onEditDetails}>
        Edit your details
      </button>
    );
  } else if (failure.kind === 'rateLimited' && hasAppointments) {
    action = (
      <Link className="button button--primary" to="/appointments">
        See your appointments
      </Link>
    );
  }
  return (
    <Notice
      tone="error"
      role="alert"
      title={failureTitle(failure)}
      testId="booking-failure"
      actions={
        <>
          {action}
          <CallLink className="button button--secondary">Call the shop</CallLink>
        </>
      }
    >
      <p>{failure.message}</p>
      {failure.kind === 'offline' ? <p>Trying again won't book it twice.</p> : null}
    </Notice>
  );
}
