import { describe, expect, it } from 'vitest';
import { OWNER_KEY, useHarness } from './helpers/harness.js';

// Monday Nov 2 2026, 11:10 AM PST.
const h = useHarness({ now: '2026-11-02T19:10:00Z' });

const OWNER_ROUTES: [string, string][] = [
  ['GET', '/api/owner/me'],
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
    expect((await h.call('GET', '/api/owner/me', { owner: true })).body).toEqual({ ok: true, stripe: { configured: false, mode: null } });
    h.config.stripeSecretKey = 'sk_test_fixture';
    expect((await h.call('GET', '/api/owner/me', { owner: true })).body.stripe).toEqual({ configured: true, mode: 'test' });
    h.config.stripeSecretKey = 'rk_live_fixture';
    expect((await h.call('GET', '/api/owner/me', { owner: true })).body.stripe).toEqual({ configured: true, mode: 'live' });
  });
});
