import { useCallback, useEffect, useState } from 'react';
import { api, errorMessage } from '../api/client';
import type { BookingTarget, NoShowPolicy } from '../api/types';

export type PolicyState =
  | { status: 'loading' }
  | { status: 'ready'; policy: NoShowPolicy }
  | { status: 'error'; message: string };

/** The no-show policy for this booking: whether a card is needed, and the notice to show. */
export function useNoShowPolicy(target: BookingTarget | null) {
  const key = target ? JSON.stringify(target) : '';
  const [state, setState] = useState<PolicyState>({ status: 'loading' });
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    if (!key) return;
    const controller = new AbortController();
    setState({ status: 'loading' });
    api
      .noShowPolicy(JSON.parse(key) as BookingTarget, controller.signal)
      .then((policy) => setState({ status: 'ready', policy }))
      .catch((error: unknown) => {
        if (!controller.signal.aborted) setState({ status: 'error', message: errorMessage(error) });
      });
    return () => controller.abort();
  }, [key, attempt]);

  const reload = useCallback(() => setAttempt((n) => n + 1), []);
  return { state, reload };
}
