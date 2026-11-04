import { useSyncExternalStore } from 'react';

// A new version of the app, ready once someone taps Reload: what the service worker's
// registration (./register.ts) tells the update bar (./UpdateBar.tsx).

type Apply = () => void;

let ready: Apply | null = null;
const listeners = new Set<() => void>();

/** A new version is ready: `apply` takes it (null: none, or no longer). */
export function offerUpdate(apply: Apply | null): void {
  ready = apply;
  for (const listener of listeners) listener();
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

/** How to take the new version, while one is ready. */
export function useUpdate(): Apply | null {
  return useSyncExternalStore(
    subscribe,
    () => ready,
    () => null,
  );
}
