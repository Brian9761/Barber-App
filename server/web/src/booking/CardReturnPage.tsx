import { useEffect, useRef, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { api, ErrorCode, errorMessage, isApiError } from '../api/client';
import { Loading, Notice, PreferToCall } from '../components/ui';
import { usePageMeta } from '../components/usePageMeta';
import { deleteSavedCardQuietly } from '../lib/cardRemoval';
import { clearPendingCheckout, loadCard, loadPendingCheckout, storeCard } from '../lib/storage';
import { useBooking } from './BookingContext';
import { firstOpenStep, STEP_PATHS } from './flow';
import type { ReviewLocationState } from './ReviewStep';

const SESSION_ID_RE = /^cs_(test|live)_[A-Za-z0-9]{1,200}$/;

/** Whether saving the card again can work: the shop wasn't reached, had a problem, or asked to wait. */
export function canTryAgain(error: unknown): boolean {
  if (!isApiError(error)) return true;
  return error.isOffline || error.status >= 500 || error.code === ErrorCode.rateLimited;
}

interface Problem {
  message: string;
  /** "Try again" can save it (the shop wasn't reached, say); otherwise only "Back to your booking". */
  retry: boolean;
}

/**
 * Where Stripe's card page sends the client back to (through the server):
 * /book/card-return?status=saved&session_id=cs_… or ?status=cancelled. A saved card
 * is kept with the card token made before leaving (POST /api/cards), then the
 * booking picks up where it was, from this tab's sessionStorage.
 *
 * Only the card page this tab opened last can be saved: its token is the one kept
 * here, and the server checks that the two belong together. An older card page
 * (left open, or reached through the browser's history) says so instead.
 */
export function CardReturnPage() {
  usePageMeta('Adding your card', 'Saving the card for your Izzy Clipz appointment.');
  const [params] = useSearchParams();
  const navigate = useNavigate();
  const { draft } = useBooking();
  const [problem, setProblem] = useState<Problem | null>(null);
  const [attempt, setAttempt] = useState(0);
  const started = useRef(-1);

  const status = params.get('status');
  const sessionId = params.get('session_id') ?? '';
  const backTo = STEP_PATHS[firstOpenStep(draft)];

  useEffect(() => {
    if (started.current === attempt) return;
    started.current = attempt;
    const pending = loadPendingCheckout();
    if (status === 'cancelled') {
      clearPendingCheckout();
      navigate(backTo, { replace: true, state: { cardNotice: "Your card wasn't added. Add a card to book this time." } satisfies ReviewLocationState });
      return;
    }
    if (status !== 'saved' || !SESSION_ID_RE.test(sessionId)) {
      setProblem({ message: 'Something went wrong on the way back from the card page. Go back to your booking and add your card again.', retry: false });
      return;
    }
    if (!pending) {
      setProblem({ message: 'This browser lost track of the card you were adding. Go back to your booking and add it again.', retry: false });
      return;
    }
    if (pending.sessionId !== sessionId) {
      // A card page from before the one this tab opened last: its card can't be matched any more.
      setProblem({ message: 'That was an older card page. Go back to your booking and add your card again.', retry: false });
      return;
    }
    setProblem(null);
    api
      .saveCard(pending.sessionId, pending.token)
      .then((card) => {
        // The new card takes the place of any card this browser kept ("Change card", or another
        // client's): that one's key is gone from here, so the shop deletes it.
        const replaced = loadCard();
        storeCard({ token: pending.token, card, phone: pending.phone }, pending.remember);
        clearPendingCheckout();
        if (replaced && replaced.token !== pending.token) deleteSavedCardQuietly(replaced.token);
        navigate(backTo, { replace: true });
      })
      .catch((error: unknown) => {
        const retry = canTryAgain(error);
        // Nothing more can come of this card page: the next try starts with a new one.
        if (!retry) clearPendingCheckout();
        setProblem({ message: errorMessage(error), retry });
      });
  }, [attempt, backTo, navigate, sessionId, status]);

  return (
    <section className="container container--narrow card-return" aria-labelledby="card-return-title">
      <h1 id="card-return-title" className="card-return__title">
        {problem ? "Your card wasn't added" : 'Saving your card…'}
      </h1>
      {problem ? (
        <Notice
          tone="error"
          role="alert"
          actions={
            <>
              {problem.retry ? (
                <button type="button" className="button button--primary" onClick={() => setAttempt((n) => n + 1)}>
                  Try again
                </button>
              ) : null}
              <button
                type="button"
                className={`button ${problem.retry ? 'button--secondary' : 'button--primary'}`}
                onClick={() => navigate(backTo, { replace: true })}
              >
                Back to your booking
              </button>
            </>
          }
        >
          <p>{problem.message}</p>
        </Notice>
      ) : (
        <Loading text="One moment while we save your card with the shop…" />
      )}
      <PreferToCall />
    </section>
  );
}
