import { describe, expect, it } from 'vitest';
import { useHarness } from './helpers/harness.js';

const h = useHarness({ now: '2026-11-02T17:00:00Z' });

const FLOW45 = 'flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a';
const CRISTIAN45 = 'cristian-ceja/bbb0c294-87a6-465d-9f55-6f579dcb399a';
// Tuesday Nov 3, from 10 AM PST (18:00Z), one per hour; i = 0…8.
const slot = (i: number) => new Date(Date.UTC(2026, 10, 3, 18 + i)).toISOString().replace('.000Z', 'Z');

function book(i: number, opts: { ip?: string; phone?: string; offeringId?: string } = {}) {
  return h.call('POST', '/api/appointments', {
    body: {
      offeringId: opts.offeringId ?? FLOW45,
      start: slot(i),
      customer: { name: `Client ${i}`, phone: opts.phone ?? `44255501${String(i).padStart(2, '0')}` },
    },
    ip: opts.ip ?? '203.0.113.50',
  });
}

describe('POST /api/appointments rate limits', () => {
  it('allows 5 booking attempts per IP per hour, then 429 with Retry-After', async () => {
    for (let i = 0; i < 5; i++) expect((await book(i)).status).toBe(201);
    const sixth = await book(5);
    expect(sixth.status).toBe(429);
    expect(sixth.body.error.code).toBe('rate_limited');
    expect(sixth.headers.get('retry-after')).toBe('3600');
    // Another network is unaffected.
    expect((await book(5, { ip: '198.51.100.9' })).status).toBe(201);
  });

  it('opens up again after an hour', async () => {
    for (let i = 0; i < 5; i++) await book(i);
    expect((await book(5)).status).toBe(429);
    h.advance(50);
    expect((await book(6)).status).toBe(429);
    h.advance(15);
    expect((await book(6)).status).toBe(201);
  });

  it('counts attempts that reach booking, including taken slots, but not invalid requests', async () => {
    for (let i = 0; i < 10; i++) {
      const bad = await h.call('POST', '/api/appointments', { body: { offeringId: FLOW45, start: slot(0) }, ip: '203.0.113.50' });
      expect(bad.status).toBe(400);
    }
    expect((await book(0)).status).toBe(201);
    for (let i = 1; i < 5; i++) expect((await book(0, { phone: `44255502${i}0` })).status).toBe(409);
    expect((await book(1)).status).toBe(429);
  });

  it('never stores the raw IP address', async () => {
    await book(0, { ip: '203.0.113.77' });
    const { rows } = await h.database.pool.query('SELECT key FROM rate_limits');
    expect(rows).toHaveLength(1);
    expect(rows[0].key).toMatch(/^book:ip:[0-9a-f]{32}$/);
    expect(rows[0].key).not.toContain('203.0.113.77');
  });

  it('allows at most 3 upcoming booked appointments per phone number, however it is typed', async () => {
    const phones = ['(442) 555-0177', '442.555.0177', '+1 442 555 0177'];
    for (const [i, phone] of phones.entries()) expect((await book(i, { phone, ip: `192.0.2.${i}` })).status).toBe(201);
    const fourth = await book(3, { phone: '1-442-555-0177', ip: '192.0.2.9' });
    expect(fourth.status).toBe(429);
    expect(fourth.body.error).toEqual({
      code: 'rate_limited',
      message: 'This number already has 3 upcoming appointments. Cancel one, or call the shop to book more.',
    });
  });

  it('frees a place when one is cancelled, or once one is in the past', async () => {
    const first = await book(0, { phone: '4425550188', ip: '192.0.2.1' });
    await book(1, { phone: '4425550188', ip: '192.0.2.2' });
    await book(2, { phone: '4425550188', ip: '192.0.2.3' });
    expect((await book(3, { phone: '4425550188', ip: '192.0.2.4' })).status).toBe(429);
    await h.call('POST', `/api/appointments/${first.body.appointment.id}/cancel`, {
      headers: { 'x-manage-token': first.body.manageToken },
    });
    expect((await book(3, { phone: '4425550188', ip: '192.0.2.4' })).status).toBe(201);
    expect((await book(4, { phone: '4425550188', ip: '192.0.2.5' })).status).toBe(429);
    // Tuesday 11:01 AM PST: the 11 AM appointment has started, so it no longer counts.
    h.setNow('2026-11-03T19:01:00Z');
    expect((await book(5, { phone: '4425550188', ip: '192.0.2.6' })).status).toBe(201);
  });

  it('two bookings for one number at once cannot both squeeze under the limit', async () => {
    await book(0, { phone: '4425550199', ip: '192.0.2.1' });
    await book(1, { phone: '4425550199', ip: '192.0.2.2' });
    const results = await Promise.all([
      book(2, { phone: '4425550199', ip: '192.0.2.3' }),
      book(3, { phone: '4425550199', ip: '192.0.2.4', offeringId: CRISTIAN45 }),
    ]);
    expect(results.map((r) => r.status).sort()).toEqual([201, 429]);
  });

  it("doesn't limit the shop's own bookings", async () => {
    for (let i = 0; i < 7; i++) {
      const res = await h.call('POST', '/api/owner/appointments', {
        owner: true,
        body: { offeringId: FLOW45, start: slot(i), customer: { name: `Walk-in ${i}`, phone: '4425550111' } },
        ip: '203.0.113.50',
      });
      expect(res.status).toBe(201);
    }
  });
});
