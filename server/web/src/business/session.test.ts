import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import sessionFixture from '../../../test/fixtures/contract/computer-session-created.json';
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

  it('ends only the session the server turned down, not one signed in since', () => {
    session.signIn(sessionFixture as never);
    session.expire('some-older-token');
    expect(session.current().session).not.toBeNull();
    session.expire(sessionFixture.token);
    expect(session.current()).toMatchObject({ session: null, reason: 'expired' });
  });

  it('forgets a session whose 30 days have run out', () => {
    localStorage.setItem(SESSION_KEY, JSON.stringify({ token: 'x'.repeat(43), id: 'a', name: 'Old', createdAt: '2020-01-01T00:00:00Z', expiresAt: '2020-01-31T00:00:00Z' }));
    expect(session.current().session).toBeNull();
    expect(localStorage.getItem(SESSION_KEY)).toBeNull();
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
