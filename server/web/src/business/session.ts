// This computer's sign-in to Izzy Clipz Business: the session token the shop's server
// gave for the code from the app (never the owner key), kept in localStorage under one
// key, with what Settings shows of it (the computer's name, signed in since). A session
// the server no longer knows (signed out from the iPhone, or 30 days old) drops back to
// sign-in with a friendly line. Other tabs follow: signing out in one signs out all.
//
// The demo keeps its own sign-in under a key of its own, so the real site, should it
// ever open at the demo's address, never sends the demo's token to the shop's server.
//
// The barber picked last at checkout (lib/ticket.ts) goes with the sign-in: signing out
// (here, from the iPhone or from another computer) removes both, as the Privacy Policy says.

import { useSyncExternalStore } from 'react';
import { isDemo } from '../demo/mode';
import { BUSINESS_LAST_BARBER_KEY, BUSINESS_SESSION_KEY, DEMO_BUSINESS_SESSION_KEY, readJSON, removeKey, writeJSON } from '../lib/storage';
import type { SignedIn } from './types';

export const SESSION_KEY = BUSINESS_SESSION_KEY;
export const DEMO_SESSION_KEY = DEMO_BUSINESS_SESSION_KEY;

export interface StoredSession {
  token: string;
  /** The session's id on the server ("this computer" in the list of computers). */
  id: string;
  /** "Chrome on Mac". */
  name: string;
  createdAt: string;
  expiresAt: string;
}

/** Why the sign-in page shows: never signed in, signed out here, or the server ended the session. */
export type SignedOutReason = 'none' | 'signedOut' | 'expired';

export interface SessionState {
  session: StoredSession | null;
  reason: SignedOutReason;
  /** Anything more the sign-in page should say about signing out (the server couldn't be told, say). */
  note: string | null;
}

function key(): string {
  return isDemo() ? DEMO_SESSION_KEY : SESSION_KEY;
}

function isStoredSession(value: unknown): value is StoredSession {
  if (typeof value !== 'object' || value === null) return false;
  const v = value as Record<string, unknown>;
  return (
    typeof v.token === 'string' &&
    v.token.length >= 16 &&
    typeof v.id === 'string' &&
    typeof v.name === 'string' &&
    typeof v.createdAt === 'string' &&
    typeof v.expiresAt === 'string'
  );
}

/** This computer's sign-in has ended: it goes, and the barber picked last at checkout with it. */
function forgetSignIn(): void {
  removeKey('local', key());
  removeKey('local', BUSINESS_LAST_BARBER_KEY);
}

/** The session kept here, or null; `expired` when one was kept but its 30 days have run out. */
function load(): { session: StoredSession | null; expired: boolean } {
  const stored = readJSON('local', key());
  if (!isStoredSession(stored)) return { session: null, expired: false };
  // One that ran out is gone (the server would say so on the first call anyway), and the
  // sign-in page says why, as it does when the server turns a session down.
  if (Date.parse(stored.expiresAt) <= Date.now()) {
    forgetSignIn();
    return { session: null, expired: true };
  }
  return { session: stored, expired: false };
}

let state: SessionState = { session: null, reason: 'none', note: null };
let loaded = false;
const listeners = new Set<() => void>();

function ensureLoaded(): void {
  if (loaded) return;
  loaded = true;
  const { session, expired } = load();
  state = { session, reason: expired ? 'expired' : 'none', note: null };
}

function set(next: SessionState): void {
  state = next;
  for (const listener of listeners) listener();
}

/** Another tab signed in or out: this one follows. */
function onStorage(event: StorageEvent): void {
  if (event.key !== null && event.key !== key()) return;
  const { session, expired } = load();
  if (session?.token === state.session?.token) return;
  set({ session, reason: session ? 'none' : expired ? 'expired' : 'signedOut', note: null });
}

export const session = {
  /** The token to send, or null when signed out. */
  token(): string | null {
    ensureLoaded();
    return state.session?.token ?? null;
  },

  current(): SessionState {
    ensureLoaded();
    return state;
  },

  /** Signed in with a code (or the demo): keeps the token, and this computer's name. */
  signIn(signedIn: SignedIn): void {
    const stored: StoredSession = {
      token: signedIn.token,
      id: signedIn.session.id,
      name: signedIn.session.name,
      createdAt: signedIn.session.createdAt,
      expiresAt: signedIn.session.expiresAt,
    };
    writeJSON('local', key(), stored);
    loaded = true;
    set({ session: stored, reason: 'none', note: null });
  },

  /** Signed out on this computer ("Sign out"), with anything more to say about it. The barber picked last goes too. */
  signOut(note: string | null = null): void {
    forgetSignIn();
    loaded = true;
    set({ session: null, reason: 'signedOut', note });
  },

  /**
   * The server turned this token down (401): signed out from the iPhone, signed out of every
   * computer, or 30 days old. Only the token that was turned down: a newer sign-in stays.
   */
  expire(token: string): void {
    ensureLoaded();
    if (state.session?.token !== token) return;
    forgetSignIn();
    set({ session: null, reason: 'expired', note: null });
  },

  subscribe(listener: () => void): () => void {
    if (listeners.size === 0 && typeof window !== 'undefined') window.addEventListener('storage', onStorage);
    listeners.add(listener);
    return () => {
      listeners.delete(listener);
      if (listeners.size === 0 && typeof window !== 'undefined') window.removeEventListener('storage', onStorage);
    };
  },

  /** For tests: as if the page had just opened. */
  reset(): void {
    loaded = false;
    state = { session: null, reason: 'none', note: null };
  },
};

export function useSession(): SessionState {
  return useSyncExternalStore(session.subscribe, session.current, session.current);
}
