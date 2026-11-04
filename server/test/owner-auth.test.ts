import { describe, expect, it } from 'vitest';
import { createRouter } from '../src/app.js';
import { hashManageToken, newSessionToken } from '../src/auth.js';
import { fixtureUuid, OWNER_KEY, useHarness } from './helpers/harness.js';

// Monday Nov 2 2026, 11:10 AM PST.
const h = useHarness({ now: '2026-11-02T19:10:00Z' });

const OWNER_ROUTES: [string, string][] = [
  ['GET', '/api/owner/me'],
  ['GET', '/api/owner/availability?offeringId=x'],
  ['GET', '/api/owner/appointments?date=2026-11-02'],
  ['POST', '/api/owner/appointments'],
  ['PATCH', '/api/owner/appointments/00000000-0000-4000-8000-000000000001'],
  ['GET', '/api/owner/time-off'],
  ['POST', '/api/owner/time-off'],
  ['DELETE', '/api/owner/time-off/00000000-0000-4000-8000-000000000001'],
  ['GET', '/api/owner/products'],
  ['POST', '/api/owner/products'],
  ['PATCH', '/api/owner/products/00000000-0000-4000-8000-000000000001'],
  ['DELETE', '/api/owner/products/00000000-0000-4000-8000-000000000001'],
  ['POST', '/api/owner/products/00000000-0000-4000-8000-000000000001/photo'],
  ['POST', '/api/owner/terminal/connection-token'],
  ['POST', '/api/owner/payments'],
  ['POST', '/api/owner/payments/pi_123/complete'],
  ['GET', '/api/owner/payments?date=2026-11-02'],
  ['POST', '/api/owner/appointments/00000000-0000-4000-8000-000000000001/no-show-fee'],
  ['GET', '/api/owner/no-show-settings'],
  ['PATCH', '/api/owner/no-show-settings'],
];

describe('owner auth', () => {
  for (const [method, path] of OWNER_ROUTES) {
    it(`${method} ${path}: 401 without the key, 401 with a wrong one`, async () => {
      const withBody = method === 'POST' || method === 'PATCH' ? { body: {} } : {};
      const none = await h.call(method, path, withBody);
      expect(none.status).toBe(401);
      expect(none.body.error.code).toBe('unauthorized');
      expect(none.headers.get('www-authenticate')).toBe('Bearer');
      const wrong = await h.call(method, path, { ...withBody, headers: { authorization: `Bearer ${OWNER_KEY}x` } });
      expect(wrong.status).toBe(401);
      const basic = await h.call(method, path, { ...withBody, headers: { authorization: `Basic ${OWNER_KEY}` } });
      expect(basic.status).toBe(401);
    });
  }

  it('503 owner_not_configured when OWNER_KEY is missing or shorter than 32 characters', async () => {
    h.config.ownerKey = undefined;
    const missing = await h.call('GET', '/api/owner/me', { owner: true });
    expect(missing.status).toBe(503);
    expect(missing.body.error.code).toBe('owner_not_configured');
    h.config.ownerKey = 'short-key';
    const short = await h.call('GET', '/api/owner/me', { headers: { authorization: 'Bearer short-key' } });
    expect(short.status).toBe(503);
  });

  it('accepts the right key, case-insensitive scheme', async () => {
    const res = await h.call('GET', '/api/owner/me', { headers: { authorization: `bearer ${OWNER_KEY}` } });
    expect(res.status).toBe(200);
  });
});

describe('GET /api/owner/me', () => {
  it('reports Stripe as not configured, test or live', async () => {
    expect((await h.call('GET', '/api/owner/me', { owner: true })).body).toEqual({
      ok: true,
      stripe: { configured: false, mode: null, locationId: null },
      connection: { mode: 'off', status: 'off', businessName: null },
    });
    h.config.stripeSecretKey = 'sk_test_fixture';
    expect((await h.call('GET', '/api/owner/me', { owner: true })).body.stripe).toEqual({ configured: true, mode: 'test', locationId: null });
    h.config.stripeSecretKey = 'rk_live_fixture';
    expect((await h.call('GET', '/api/owner/me', { owner: true })).body.stripe).toEqual({ configured: true, mode: 'live', locationId: null });
  });
});

describe('owner auth for every owner route (the router’s own list)', () => {
  /** The routes only the Business app on the owner's iPhone may use (with the owner key). */
  const KEY_ONLY = new Set([
    'POST /api/owner/computer-codes',
    'DELETE /api/owner/stripe/connect',
    'POST /api/owner/terminal/connection-token',
    'POST /api/owner/payments',
  ]);
  const ownerRoutes = createRouter()
    .list()
    .filter((r) => r.path.startsWith('/api/owner/'));

  /** A computer session written straight to the database (no code needed), with its token. */
  let tokens = 0;
  async function insertSession(state: 'live' | 'revoked' | 'expired' = 'live'): Promise<string> {
    tokens += 1;
    const token = newSessionToken(OWNER_KEY, Buffer.alloc(16, tokens));
    const now = h.now.getTime();
    await h.database.pool.query(
      `INSERT INTO computer_sessions (id, token_hash, name, created_at, last_used_at, expires_at, revoked_at)
       VALUES (gen_random_uuid(), $1, 'Test computer', $2, $2, $3, $4)`,
      [
        hashManageToken(token),
        new Date(now - 60_000),
        new Date(state === 'expired' ? now - 1000 : now + 86_400_000),
        state === 'revoked' ? new Date(now - 1000) : null,
      ],
    );
    return token;
  }
  const request = (method: string, path: string, authorization?: string) =>
    h.call(method, path.replace(/:[a-z]+/g, fixtureUuid(1)), {
      ...(method === 'POST' || method === 'PATCH' ? { body: {} } : {}),
      ...(authorization ? { headers: { authorization } } : {}),
    });

  it('lists every owner route there is, including the key-only ones', () => {
    const listed = ownerRoutes.map((r) => `${r.method} ${r.path}`);
    // The 20 routes above, and the 8 for Stripe Connect and computers.
    expect(listed.length).toBeGreaterThanOrEqual(28);
    for (const [method, path] of OWNER_ROUTES) expect(listed).toContain(`${method} ${path.split('?')[0]!.replace(/[0-9a-f-]{36}|pi_123/, ':id')}`);
    for (const route of KEY_ONLY) expect(listed).toContain(route);
  });

  for (const { method, path } of ownerRoutes) {
    it(`${method} ${path}: 401 without the key or with a signed-out or expired computer`, async () => {
      const none = await request(method, path);
      expect(none.status, none.text).toBe(401);
      expect(none.body.error).toEqual({ code: 'unauthorized', message: "That owner key isn't right. Check it and sign in again." });
      expect(none.headers.get('www-authenticate')).toBe('Bearer');
      expect((await request(method, path, `Bearer ${OWNER_KEY}x`)).status).toBe(401);
      expect((await request(method, path, `Bearer ${await insertSession('revoked')}`)).status).toBe(401);
      expect((await request(method, path, `Bearer ${await insertSession('expired')}`)).status).toBe(401);
    });

    const keyOnly = KEY_ONLY.has(`${method} ${path}`);
    it(`${method} ${path}: a signed-in computer is ${keyOnly ? 'turned down (the owner key only)' : 'let in'}`, async () => {
      const res = await request(method, path, `Bearer ${await insertSession()}`);
      if (keyOnly) {
        expect(res.status, res.text).toBe(403);
        expect(res.body.error).toEqual({ code: 'forbidden', message: 'This can only be done in the Izzy Clipz Business app on your iPhone.' });
      } else {
        expect([401, 403], res.text).not.toContain(res.status);
      }
    });
  }

  it('503 owner_not_configured comes first, for a computer too', async () => {
    const token = await insertSession();
    h.config.ownerKey = undefined;
    const res = await request('GET', '/api/owner/me', `Bearer ${token}`);
    expect(res.status).toBe(503);
    expect(res.body.error).toEqual({ code: 'owner_not_configured', message: "The shop's owner key isn't set up on the server yet." });
  });
});
