import { useEffect, useRef, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { api, errorMessage } from '../api/client';
import { Loading, Notice, PreferToCall } from '../components/ui';
import { usePageMeta } from '../components/usePageMeta';
import { clearPendingCheckout, loadPendingCheckout, storeCard } from '../lib/storage';
import { useBooking } from './BookingContext';
import { firstOpenStep, STEP_PATHS } from './flow';
import type { ReviewLocationState } from './ReviewStep';

const SESSION_ID_RE = /^cs_(test|live)_[A-Za-z0-9]{1,200}$/;

/**
 * Where Stripe's card page sends the client back to (through the server):
 * /book/card-return?status=saved&session_id=cs_… or ?status=cancelled. A saved card
 * is kept with the card token made before leaving (POST /api/cards), then the
 * booking picks up where it was, from this tab's sessionStorage.
 */
export function CardReturnPage() {
  usePageMeta('Adding your card', 'Saving the card for your Izzy Clipz appointment.');
  const [params] = useSearchParams();
  const navigate = useNavigate();
  const { draft } = useBooking();
  const [problem, setProblem] = useState<string | null>(null);
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
      setProblem('Something went wrong on the way back from the card page. Go back to your booking and add your card again.');
      return;
    }
    if (!pending) {
      setProblem("This browser lost track of the card you were adding. Go back to your booking and add it again.");
      return;
    }
    setProblem(null);
    api
      .saveCard(sessionId, pending.token)
      .then((card) => {
        storeCard({ token: pending.token, card }, pending.remember);
        clearPendingCheckout();
        navigate(backTo, { replace: true });
      })
      .catch((error: unknown) => setProblem(errorMessage(error)));
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
              {status === 'saved' && loadPendingCheckout() ? (
                <button type="button" className="button button--primary" onClick={() => setAttempt((n) => n + 1)}>
                  Try again
                </button>
              ) : null}
              <button type="button" className="button button--secondary" onClick={() => navigate(backTo, { replace: true })}>
                Back to your booking
              </button>
            </>
          }
        >
          <p>{problem}</p>
        </Notice>
      ) : (
        <Loading text="One moment while we save your card with the shop…" />
      )}
      <PreferToCall />
    </section>
  );
}
