import { useSyncExternalStore } from 'react';

// Chrome and Edge (on Android and computers) offer to install a site that can be installed
// with a `beforeinstallprompt` event. The page keeps it for its own "Install Izzy Clipz"
// button, instead of the browser's own little bar, and shows the browser's question when
// that button is tapped.

/** The browser's offer to install the site (not in TypeScript's own types yet). */
export interface BeforeInstallPromptEvent extends Event {
  prompt(): Promise<unknown>;
  readonly userChoice: Promise<{ outcome: 'accepted' | 'dismissed'; platform?: string }>;
}

export interface InstallState {
  /** The browser offered to install it: the Install button can show its question. */
  canInstall: boolean;
  /** It was installed during this visit. */
  installed: boolean;
}

let offer: BeforeInstallPromptEvent | null = null;
let state: InstallState = { canInstall: false, installed: false };
const listeners = new Set<() => void>();

function changed(next: Partial<InstallState>): void {
  state = { ...state, ...next };
  for (const listener of listeners) listener();
}

/** Keeps the browser's install offer for the page's own Install button. Called once, as the page starts. */
export function listenForInstallPrompt(target: Window = window): () => void {
  const onOffer = (event: Event) => {
    // Not the browser's own bar: the page shows its own button, on Get the app.
    event.preventDefault();
    offer = event as BeforeInstallPromptEvent;
    changed({ canInstall: true });
  };
  const onInstalled = () => {
    offer = null;
    changed({ canInstall: false, installed: true });
  };
  target.addEventListener('beforeinstallprompt', onOffer);
  target.addEventListener('appinstalled', onInstalled);
  return () => {
    target.removeEventListener('beforeinstallprompt', onOffer);
    target.removeEventListener('appinstalled', onInstalled);
  };
}

/**
 * Shows the browser's "Install app?" question. Each offer can be shown once; the browser makes
 * a new one if the visitor said no. "unavailable": the browser hasn't offered (Safari, Firefox,
 * or it's installed already), so the page shows the steps instead.
 */
export async function promptInstall(): Promise<'accepted' | 'dismissed' | 'unavailable'> {
  const event = offer;
  if (!event) return 'unavailable';
  offer = null;
  changed({ canInstall: false });
  try {
    await event.prompt();
    const choice = await event.userChoice;
    if (choice.outcome === 'accepted') changed({ installed: true });
    return choice.outcome;
  } catch {
    return 'unavailable';
  }
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

export function useInstallPrompt(): InstallState {
  return useSyncExternalStore(
    subscribe,
    () => state,
    () => state,
  );
}

/** For tests: as if the page had just opened. */
export function forgetInstallPrompt(): void {
  offer = null;
  changed({ canInstall: false, installed: false });
}
