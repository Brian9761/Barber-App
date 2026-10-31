import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import { apiPath } from '../src/http.js';
import { VERSION } from '../src/version.js';
import api from '../api/index.js';
import { CRON_SECRET, useHarness } from './helpers/harness.js';

const h = useHarness({ now: '2026-11-02T19:10:00Z' });
const pkg = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));

describe('router', () => {
  it('GET /api/health → { ok: true, version } from package.json', async () => {
    const res = await h.call('GET', '/api/health');
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ ok: true, version: pkg.version });
    expect(VERSION).toBe(pkg.version);
  });

  it('404 not_found for unknown paths, in the error shape', async () => {
    for (const path of ['/api/nope', '/api', '/api/appointments/x/y/z', '/', '/api/owner']) {
      const res = await h.call('GET', path);
      expect(res.status, path).toBe(404);
      expect(res.body).toEqual({ error: { code: 'not_found', message: "There's nothing here." } });
    }
  });

  it('405 with an Allow header for a known path and the wrong method', async () => {
    const res = await h.call('DELETE', '/api/health');
    expect(res.status).toBe(405);
    expect(res.headers.get('allow')).toBe('GET');
    expect(res.body.error).toEqual({ code: 'invalid_request', message: "This endpoint doesn't support DELETE. Use GET." });
    const both = await h.call('PUT', '/api/owner/appointments');
    expect(both.headers.get('allow')).toBe('GET, POST');
    expect((await h.call('GET', '/api/stripe/webhook')).status).toBe(405);
  });

  it('routes the rewritten form Vercel may pass (/api?path=…) and ignores trailing or doubled slashes', async () => {
    expect((await h.call('GET', '/api?path=health')).body.ok).toBe(true);
    expect((await h.call('GET', '/api/?path=/health')).body.ok).toBe(true);
    expect((await h.call('GET', '/api/health/')).body.ok).toBe(true);
    expect((await h.call('GET', '/api//health')).body.ok).toBe(true);
    const offering = encodeURIComponent('flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a');
    const rewritten = await h.call('GET', `/api?path=availability&offeringId=${offering}&from=2026-11-03&days=1`);
    expect(rewritten.status).toBe(200);
    expect(apiPath(new URL('https://x.test/api?path=owner/appointments/123'))).toBe('/api/owner/appointments/123');
  });

  it('decodes path parameters and treats bad encodings as not found', async () => {
    expect((await h.call('GET', '/api/appointments/%E0%A4%A', { headers: { 'x-manage-token': 'x'.repeat(43) } })).status).toBe(404);
  });

  it('hides unexpected errors behind a plain 500 and logs them', async () => {
    const broken = createApp({
      ...h.deps,
      db: {
        query: async () => {
          throw Object.assign(new Error('connection refused'), { code: 'ECONNREFUSED' });
        },
        transaction: async () => {
          throw new Error('connection refused');
        },
      },
    });
    const res = await broken.fetch(new Request('https://x.test/api/products'));
    expect(res.status).toBe(500);
    expect(await res.json()).toEqual({ error: { code: 'server_error', message: 'Something went wrong on our side. Please try again.' } });
    expect(h.logs.at(-1)).toMatchObject({ level: 'error', message: 'Unhandled error', details: { path: '/api/products', code: 'ECONNREFUSED' } });
  });

  it('sends JSON with no-store everywhere, and no CORS headers', async () => {
    for (const path of ['/api/health', '/api/products', '/api/nope']) {
      const res = await h.call('GET', path);
      expect(res.headers.get('content-type')).toBe('application/json; charset=utf-8');
      expect(res.headers.get('cache-control')).toBe('no-store');
      expect(res.headers.get('access-control-allow-origin')).toBeNull();
    }
  });

  it('the Vercel entry point exports { fetch } and answers health without a database', async () => {
    expect(typeof api.fetch).toBe('function');
    const res = await api.fetch(new Request('https://izzy-clipz-api.vercel.app/api/health'));
    expect(await res.json()).toEqual({ ok: true, version: VERSION });
  });
});

describe('GET /api/cron/daily', () => {
  it('401 without the cron secret, or when none is configured', async () => {
    expect((await h.call('GET', '/api/cron/daily')).status).toBe(401);
    expect((await h.call('GET', '/api/cron/daily', { headers: { authorization: 'Bearer wrong' } })).status).toBe(401);
    h.config.cronSecret = undefined;
    expect((await h.call('GET', '/api/cron/daily', { headers: { authorization: 'Bearer ' } })).status).toBe(401);
    expect((await h.call('GET', '/api/cron/daily', { headers: { authorization: `Bearer ${CRON_SECRET}` } })).status).toBe(401);
  });

  it('cleans up old rate-limit windows and usage counters, idempotently', async () => {
    const pool = h.database.pool;
    await pool.query(`INSERT INTO rate_limits (key, window_start, count) VALUES ('old', '2026-10-30T00:00:00Z', 3), ('new', '2026-11-02T19:00:00Z', 1)`);
    await pool.query(`INSERT INTO api_usage (day, counter, count) VALUES ('2026-07-01', 'google_places_details', 9), ('2026-11-01', 'google_places_details', 2)`);
    const auth = { headers: { authorization: `Bearer ${CRON_SECRET}` } };
    const first = await h.call('GET', '/api/cron/daily', auth);
    expect(first.status).toBe(200);
    expect(first.body).toEqual({ ok: true, deleted: { rateLimits: 1, apiUsage: 1, yelpCache: 0 } });
    const second = await h.call('GET', '/api/cron/daily', auth);
    expect(second.body.deleted).toEqual({ rateLimits: 0, apiUsage: 0, yelpCache: 0 });
    expect((await pool.query('SELECT key FROM rate_limits')).rows).toEqual([{ key: 'new' }]);
  });
});
