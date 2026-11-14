import { useEffect, useState } from 'react';
import { api, errorMessage } from '../api/client';
import type { Reviews } from '../api/types';

// Reviews come live from Google through the server (the site only links to Yelp's,
// and never shows any the server sends). Like the app, they're kept only in memory
// (Google's terms don't allow storing them), and asked for at most once every five
// minutes per visit, since every answer from Google counts against the server's
// daily limit.

const MAX_AGE_MS = 5 * 60_000;

let cached: { reviews: Reviews; at: number } | null = null;
let inFlight: Promise<Reviews> | null = null;

export type ReviewsState =
  | { status: 'loading' }
  | { status: 'ready'; reviews: Reviews }
  | { status: 'error'; message: string };

export function loadReviews(now = Date.now()): Promise<Reviews> {
  if (cached && now - cached.at < MAX_AGE_MS) return Promise.resolve(cached.reviews);
  inFlight ??= api
    .reviews()
    .then((reviews) => {
      cached = { reviews, at: Date.now() };
      return reviews;
    })
    .finally(() => {
      inFlight = null;
    });
  return inFlight;
}

/** For tests: forget what was loaded. */
export function forgetReviews(): void {
  cached = null;
  inFlight = null;
}

/** The reviews, loaded when `enabled` turns true (Home waits until its tile is near the screen). */
export function useReviews(enabled = true): ReviewsState & { retry: () => void } {
  const [state, setState] = useState<ReviewsState>(cached ? { status: 'ready', reviews: cached.reviews } : { status: 'loading' });
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    if (!enabled) return;
    let live = true;
    loadReviews()
      .then((reviews) => live && setState({ status: 'ready', reviews }))
      .catch((error: unknown) => live && setState({ status: 'error', message: errorMessage(error) }));
    return () => {
      live = false;
    };
  }, [enabled, attempt]);

  return {
    ...state,
    retry: () => {
      forgetReviews();
      setState({ status: 'loading' });
      setAttempt((n) => n + 1);
    },
  };
}
