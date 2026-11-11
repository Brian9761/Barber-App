import { useState, type ReactNode } from 'react';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import { api, ErrorCode, isApiError, errorMessage } from '../api/client';
import type { BookingTarget, Catalog, NoShowPolicy } from '../api/types';
import { useNow } from '../components/hooks';
import { Icon } from '../components/Icon';
import { CallLink, Loading, NewTabLink, Notice } from '../components/ui';
import { DemoNotice } from '../demo/DemoNotice';
import { deleteSavedCardQuietly } from '../lib/cardRemoval';
import { cardLabel, list, windowLabel } from '../lib/format';
import { cancelledLate, cutoffOf, feeLabel, lateCancelNoticeText } from '../lib/lateCancel';
import { leaveTo } from '../lib/leave';
import { parseUSPhone, toE164 } from '../lib/phone';
import { dateTimeLabel, localDate, timeLabel } from '../lib/shopTime';
import {
  cardValidOn,
  clearPendingCheckout,
  forgetCard,
  loadAppointments,
  loadCard,
  loadCardFor,
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

const BAD_NUMBER = 'Enter a 10-digit US number, like (442) 341-3053.';

/** Without this tab's storage the booking would be lost on Stripe's page, so the client doesn't go. */
export const CANT_KEEP_BOOKING =
  "This browser won't keep your booking while you add a card (it may be blocking this site's data), so it would be lost on the way back. Try another browser, or call the shop to book.";

/**
 * Step 5: everything on one card (each part with "Change"), the fee notice when the
 * shop's policy needs a card, "No payment now", the card on file, and "Book
 * appointment". If booking fails, it says why in plain words and offers the way
 * forward, like the app: a taken time goes back to the times, a problem with the
 * details goes back to them, a lost answer offers "Try again" (which can't book
 * twice), and a limit says which one.
 *
 * The card on file is only ever the one this client (this number) added: on a
 * shared computer nobody books with someone else's card.
 */
export function ReviewStep({ catalog }: { catalog: Catalog }) {
  const { draft } = useBooking();
  const target = targetOf(draft);
  if (!target || !draft.start || !draft.details) return null;
  return <Review catalog={catalog} draft={draft} target={target} start={draft.start} />;
}

/** "+14425550123" for the number on the details step, or null when it isn't a US number. */
function phoneOf(display: string): string | null {
  const digits = parseUSPhone(display);
  return digits ? toE164(digits) : null;
}

function Review({ catalog, draft, target, start }: { catalog: Catalog; draft: BookingDraft; target: BookingTarget; start: string }) {
  const { dispatch } = useBooking();
  const navigate = useNavigate();
  const location = useLocation();
  const details = draft.details!;
  const phone = phoneOf(details.phone);
  const zone = catalog.timeZone;
  const summary = summarize(catalog, draft);
  const { state: policyState, reload: reloadPolicy } = useNoShowPolicy(target);
  // The notices below change the moment this time is inside its free-cancellation cutoff.
  const now = useNow(60_000, policyState.status === 'ready' ? cutoffOf(policyState.policy, start) : null);
  const [card, setCard] = useState<StoredCard | null>(() => (phone ? loadCardFor(phone) : null));
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
    if (!phone) {
      setFailure({ kind: 'details', message: BAD_NUMBER });
      return;
    }
    setAddingCard(true);
    setCardMessage(null);
    const token = newToken();
    try {
      const checkout = await api.startCardCheckout(target, token);
      // What the way back from Stripe's page needs: without it the card couldn't be saved.
      const kept = savePendingCheckout({ token, remember: details.remember, sessionId: checkout.sessionId, phone }) && saveDraft(draft);
      if (!kept) {
        setAddingCard(false);
        setCardMessage(CANT_KEEP_BOOKING);
        return;
      }
      leaveTo(checkout.url);
    } catch (error) {
      setAddingCard(false);
      const code = isApiError(error) ? error.code : null;
      // No card needed any more (a 400), or Stripe isn't set up: the policy says what's true now, like the app.
      if (code === ErrorCode.invalidRequest || code === ErrorCode.stripeNotConfigured) reloadPolicy();
      setCardMessage(
        code === ErrorCode.stripeNotConfigured ? "The shop can't take cards online right now. Call the shop to book this time." : errorMessage(error),
      );
    }
  }

  async function book() {
    if (!policy || booking) return;
    if (!phone) {
      setFailure({ kind: 'details', message: BAD_NUMBER });
      return;
    }
    setBooking(true);
    setFailure(null);
    setPolicyNote(null);
    setCardMessage(null);
    // The same booking tried again (after a lost answer) goes with the same token, so it can't book twice.
    const key = retryKey(target, start, phone);
    let token = draft.pending?.key === key ? draft.pending.token : null;
    if (!token) {
      token = newToken();
      dispatch({ type: 'pending', key, token });
      saveDraft({ ...draft, pending: { key, token } });
    }
    const sentCard = needsCard ? usableCard : null;
    try {
      const confirmation = await api.book(
        {
          target,
          start,
          customer: { name: details.name, phone, ...(details.email ? { email: details.email } : {}) },
          ...(details.note ? { note: details.note } : {}),
          ...(needsCard && policy.policyText ? { noShowPolicy: policy.policyText } : {}),
          // "Remember me" off: the booking itself tells the shop the card is for this booking only,
          // so it's marked for deletion with it, even if the connection drops right after.
          ...(sentCard && !details.remember ? { keepCard: false as const } : {}),
        },
        token,
        sentCard?.token,
      );
      const saved = saveAppointment(confirmation.appointment, confirmation.manageToken);
      if (confirmation.appointment.status !== 'booked') {
        // A retry found the booking an earlier try made, but it isn't on any more.
        dispatch({ type: 'timeGone', message: noLongerBooked(confirmation.appointment, zone) });
        navigate(STEP_PATHS.time, { state: { from: STEP_PATHS.review } });
        return;
      }
      // Booked. With "Remember me" off the card goes too, like the name and number (the app does the same);
      // and so does anything kept for coming back from Stripe's card page. The booking already told the
      // shop the card it was made with is for it only (keepCard: false, above): the shop keeps it only
      // while this booking can still be charged, then deletes it, which is how "without Remember me, the
      // card is used only for the booking you saved it for" stays true. The shop is also asked to delete
      // the card here (DELETE /api/cards), which covers one kept here but not sent with the booking (no
      // card was needed after all); sent even as the page moves on, and tried again once if the
      // connection drops. The key isn't kept here either way.
      if (!details.remember) {
        const kept = loadCard();
        forgetCard();
        if (kept) deleteSavedCardQuietly(kept.token, { keepalive: true });
      }
      clearPendingCheckout();
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
          // Like the app: a card that was sent can't hold this booking (the server doesn't know
          // it, or it expires too soon), so only that one is forgotten; and the policy is checked
          // again, since a card may be needed now when it wasn't a moment ago.
          if (sentCard) {
            forgetCard(sentCard.token);
            setCard(null);
            // Its key is gone from here, so nobody could use it again: the shop deletes it (if it has it).
            deleteSavedCardQuietly(sentCard.token);
          }
          reloadPolicy();
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
    <BookingLayout catalog={catalog} summary={false}>
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
      <DemoNotice />

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
      {policy && !needsCard && cardMessage ? (
        // Why the card couldn't be added, or the server asking for one this page didn't know was needed.
        <Notice tone="error" role="alert" title="Not booked yet" testId="card-message">
          <p>{cardMessage}</p>
        </Notice>
      ) : null}

      {failure ? <FailureNotice failure={failure} retrying={booking} onRetry={() => void book()} onEditDetails={() => change('details')} /> : null}

      <div className="step-actions">
        {/* What booking agrees to, right above the button, with or without a card: the policies open in a new tab, so the booking stays here. */}
        <p className="step-actions__consent" data-testid="book-consent">
          By booking, you agree to our <NewTabLink href="/terms">Terms of Service</NewTabLink> and{' '}
          <NewTabLink href="/cancellation-policy">Cancellation & No-Show Policy</NewTabLink>.
        </p>
        <button type="button" className="button button--primary button--large step-actions__continue" disabled={!canBook} onClick={() => void book()} data-testid="book-button">
          {booking ? 'Booking…' : 'Book appointment'}
        </button>
        <p className="step-actions__note" aria-live="polite" data-testid="book-note">
          {policy ? bookNote(policy, usableCard, start, now, zone) : null}
        </p>
      </div>
    </BookingLayout>
  );
}

/**
 * The line under "Book appointment": what booking now means for cancelling. With a card
 * on file and a late-cancellation window it says until when cancelling is free, so it
 * never says "any time" when it isn't.
 */
export function bookNote(policy: NoShowPolicy, card: StoredCard | null, start: string, now: Date, zone: string): string {
  if (!policy.required) return 'You can cancel online any time before your appointment starts.';
  if (!card) return 'Add a card first to book this time.';
  const window = policy.lateCancelWindowMinutes;
  if (window === null) return 'Nothing is charged now. You can cancel online any time before your appointment starts.';
  const startsAt = new Date(start);
  if (cancelledLate(startsAt, now, window)) return `Nothing is charged now. ${lateCancelNoticeText(window, feeLabel(policy) ?? 'a fee')}`;
  const freeUntil = new Date(startsAt.getTime() - window * 60_000);
  const when = localDate(freeUntil, zone) === localDate(startsAt, zone) ? timeLabel(freeUntil, zone) : dateTimeLabel(freeUntil, zone);
  return `Nothing is charged now. Cancelling online is free until ${when} (${windowLabel(window)} before).`;
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
