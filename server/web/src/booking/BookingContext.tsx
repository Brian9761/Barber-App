import { createContext, useCallback, useContext, useEffect, useReducer, type Dispatch, type ReactNode } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { bookingReducer, EMPTY_DRAFT, loadDraft, previousStep, saveDraft, STEP_PATHS, type BookingAction, type BookingDraft, type Step } from './flow';

interface BookingContextValue {
  draft: BookingDraft;
  dispatch: Dispatch<BookingAction>;
}

const BookingContext = createContext<BookingContextValue | null>(null);

/** The booking in progress, kept in this tab so a reload or Stripe's card page doesn't lose it. */
export function BookingProvider({ children, initial }: { children: ReactNode; initial?: BookingDraft }) {
  const [draft, dispatch] = useReducer(bookingReducer, initial, (given) => given ?? loadDraft() ?? EMPTY_DRAFT);
  useEffect(() => {
    saveDraft(draft);
  }, [draft]);
  return <BookingContext.Provider value={{ draft, dispatch }}>{children}</BookingContext.Provider>;
}

export function useBooking(): BookingContextValue {
  const value = useContext(BookingContext);
  if (!value) throw new Error('useBooking needs a BookingProvider');
  return value;
}

interface FlowState {
  /** The step path this page was opened from, going forward. */
  from?: string;
}

/**
 * Moving between steps. Forward pushes the next step, so the browser's Back button
 * goes back a step; the page's own Back does the same (it goes back in history when
 * that's the step before, and otherwise opens the step before).
 */
export function useStepNavigation(step: Step) {
  const navigate = useNavigate();
  const location = useLocation();
  const from = (location.state as FlowState | null)?.from;

  const goTo = useCallback(
    (next: Step, options: { replace?: boolean } = {}) => {
      navigate(STEP_PATHS[next], { state: { from: STEP_PATHS[step] } satisfies FlowState, replace: options.replace ?? false });
    },
    [navigate, step],
  );

  const back = useCallback(() => {
    const previous = previousStep(step);
    if (!previous) {
      // Step 1: back to wherever the client came from on this site, or Home.
      const index = (window.history.state as { idx?: number } | null)?.idx ?? 0;
      if (index > 0) navigate(-1);
      else navigate('/');
      return;
    }
    if (from === STEP_PATHS[previous]) navigate(-1);
    else navigate(STEP_PATHS[previous], { state: { from: STEP_PATHS[step] } satisfies FlowState });
  }, [from, navigate, step]);

  return { goTo, back };
}
