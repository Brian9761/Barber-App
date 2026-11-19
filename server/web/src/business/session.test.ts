import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import sessionFixture from '../../../test/fixtures/contract/computer-session-created.json';
import { BUSINESS_LAST_BARBER_KEY } from '../lib/storage';
import { lastBarber, rememberBarber } from './lib/ticket';
import { DEMO_SESSION_KEY, SESSION_KEY, session } from './session';

// This computer's sign-in: the session token under one localStorage key (the demo's under
// its own), signing out, a session the server ended, and other tabs following along.

beforeEach(() => session.reset());
afterEach(() => {
  session.reset();
  vi.unstubAllEnvs();
});

describe('this computer’s session', () => {
  it('keeps the token and what Settings shows under one key, never anything else', () => {
    session.signIn(sessionFixture as never);
    expect(Object.keys(localStorage)).toEqual([SESSION_KEY]);
    expect(JSON.parse(localStorage.getItem(SESSION_KEY)!)).toEqual({
      token: sessionFixture.token,
      id: sessionFixture.session.id,
      name: 'Chrome on Mac',
      createdAt: '2026-11-02T18:00:00Z',
      expiresAt: '2026-12-02T18:00:00Z',
    });
    expect(session.token()).toBe(sessionFixture.token);
  });

  it('signs out, saying why, and forgets the token', () => {
    session.signIn(sessionFixture as never);
    session.signOut('A note');
    expect(session.current()).toEqual({ session: null, reason: 'signedOut', note: 'A note' });
    expect(localStorage.getItem(SESSION_KEY)).toBeNull();
  });

  it('forgets the barber picked last at checkout when staff sign out, as the Privacy Policy says', () => {
    session.signIn(sessionFixture as never);
    rememberBarber('carlos-rafael');
    expect(lastBarber()).toBe('carlos-rafael');
    session.signOut();
    expect(lastBarber()).toBeNull();
    expect(localStorage.getItem(BUSINESS_LAST_BARBER_KEY)).toBeNull();
    expect(Object.keys(localStorage)).toEqual([]);
  });

  it('forgets the barber picked last when the server ends the session (signed out from the iPhone), or its 30 days run out', () => {
    session.signIn(sessionFixture as never);
    rememberBarber('carlos-rafael');
    session.expire('some-older-token');
    expect(lastBarber()).toBe('carlos-rafael');
    session.expire(sessionFixture.token);
    expect(lastBarber()).toBeNull();

    session.reset();
    localStorage.setItem(
      SESSION_KEY,
      JSON.stringify({ token: 'x'.repeat(43), id: 'a', name: 'Old', createdAt: '2020-01-01T00:00:00Z', expiresAt: '2020-01-31T00:00:00Z' }),
    );
    rememberBarber('carlos-rafael');
    expect(session.current().reason).toBe('expired');
    expect(lastBarber()).toBeNull();
  });

  it('forgets a barber picked last that was left with no sign-in, and a sign-in it can’t read, when a Business page opens', () => {
    // Left behind with no sign-in (a sign-out from before signing out removed it, say).
    rememberBarber('carlos-rafael');
    expect(session.current()).toEqual({ session: null, reason: 'none', note: null });
    expect(lastBarber()).toBeNull();
    expect(Object.keys(localStorage)).toEqual([]);

    // Something under the sign-in's key that isn't one (a short token): it goes, and the barber with it.
    session.reset();
    localStorage.setItem(
      SESSION_KEY,
      JSON.stringify({ token: 'short', id: 'a', name: 'Old', createdAt: '2026-11-01T00:00:00Z', expiresAt: '2099-01-01T00:00:00Z' }),
    );
    rememberBarber('julian-ramos');
    expect(session.token()).toBeNull();
    expect(Object.keys(localStorage)).toEqual([]);

    // Not JSON at all.
    session.reset();
    localStorage.setItem(SESSION_KEY, '{not json');
    rememberBarber('julian-ramos');
    expect(session.current().session).toBeNull();
    expect(Object.keys(localStorage)).toEqual([]);

    // The demo's page, with the demo's own key, does the same.
    session.reset();
    vi.stubEnv('VITE_DEMO_MODE', '1');
    localStorage.setItem(DEMO_SESSION_KEY, JSON.stringify({ token: 42 }));
    rememberBarber('flowxbori');
    expect(session.current()).toEqual({ session: null, reason: 'none', note: null });
    expect(Object.keys(localStorage)).toEqual([]);
  });

  it('keeps the barber picked last while signed in, after the page opens again', () => {
    // A sign-in with days left, kept from before (the fixture's own dates would run out one day).
    const kept = { token: 'x'.repeat(43), id: 'a', name: 'Chrome on Mac', createdAt: '2026-11-02T18:00:00Z', expiresAt: '2099-01-01T00:00:00Z' };
    localStorage.setItem(SESSION_KEY, JSON.stringify(kept));
    rememberBarber('carlos-rafael');
    // As if the page had just opened, with this computer still signed in.
    expect(session.token()).toBe(kept.token);
    expect(lastBarber()).toBe('carlos-rafael');
    expect(Object.keys(localStorage).sort()).toEqual([BUSINESS_LAST_BARBER_KEY, SESSION_KEY].sort());
  });

  it('keeps the barber picked last while signed in, and the demo’s sign out forgets it too', () => {
    vi.stubEnv('VITE_DEMO_MODE', '1');
    session.signIn(sessionFixture as never);
    rememberBarber('carlos-rafael');
    expect(session.token()).toBe(sessionFixture.token);
    expect(lastBarber()).toBe('carlos-rafael');
    session.signOut();
    expect(Object.keys(localStorage)).toEqual([]);
  });

  it('ends only the session the server turned down, not one signed in since', () => {
    session.signIn(sessionFixture as never);
    session.expire('some-older-token');
    expect(session.current().session).not.toBeNull();
    session.expire(sessionFixture.token);
    expect(session.current()).toMatchObject({ session: null, reason: 'expired' });
  });

  it('forgets a session whose 30 days have run out, and says why on the sign-in page', () => {
    localStorage.setItem(
      SESSION_KEY,
      JSON.stringify({ token: 'x'.repeat(43), id: 'a', name: 'Old', createdAt: '2020-01-01T00:00:00Z', expiresAt: '2020-01-31T00:00:00Z' }),
    );
    expect(session.current()).toEqual({ session: null, reason: 'expired', note: null });
    expect(localStorage.getItem(SESSION_KEY)).toBeNull();
  });

  it('opens on plain sign-in when this computer never signed in', () => {
    expect(session.current()).toEqual({ session: null, reason: 'none', note: null });
  });

  it('follows another tab signing out', () => {
    session.signIn(sessionFixture as never);
    const listener = vi.fn();
    const unsubscribe = session.subscribe(listener);
    localStorage.removeItem(SESSION_KEY);
    window.dispatchEvent(new StorageEvent('storage', { key: SESSION_KEY }));
    expect(listener).toHaveBeenCalled();
    expect(session.current()).toMatchObject({ session: null, reason: 'signedOut' });
    unsubscribe();
  });

  it('keeps the demo’s sign-in under a key of its own', () => {
    vi.stubEnv('VITE_DEMO_MODE', '1');
    session.signIn(sessionFixture as never);
    expect(Object.keys(localStorage)).toEqual([DEMO_SESSION_KEY]);
  });
});
