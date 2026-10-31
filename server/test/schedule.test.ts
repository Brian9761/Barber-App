import { describe, expect, it } from 'vitest';
import { useHarness } from './helpers/harness.js';

// Monday Nov 2 2026, 11:10 AM PST.
const h = useHarness({ now: '2026-11-02T19:10:00Z' });

const FLOW45 = 'flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a';
const JULIAN45 = 'julian-ramos/bbb0c294-87a6-465d-9f55-6f579dcb399a';

let ipCounter = 0;
async function customerBooking(start: string, offeringId = FLOW45, phone = '4425550123') {
  ipCounter += 1;
  const res = await h.call('POST', '/api/appointments', {
    body: { offeringId, start, customer: { name: 'Online Client', phone } },
    ip: `192.0.2.${ipCounter % 250}`,
  });
  expect(res.status).toBe(201);
  return res.body.appointment;
}

describe('owner appointments', () => {
  it('lists a shop-local day, every status, in time order', async () => {
    const late = await customerBooking('2026-11-02T23:00:00Z');
    const early = await customerBooking('2026-11-02T21:00:00Z', JULIAN45);
    const cancelled = await customerBooking('2026-11-02T22:00:00Z', JULIAN45, '4425550124');
    await h.call('PATCH', `/api/owner/appointments/${cancelled.id}`, { owner: true, body: { status: 'cancelled' } });
    await customerBooking('2026-11-03T18:00:00Z');
    const res = await h.call('GET', '/api/owner/appointments?date=2026-11-02', { owner: true });
    expect(res.status).toBe(200);
    expect(res.body.appointments.map((a: { id: string }) => a.id)).toEqual([early.id, cancelled.id, late.id]);
    expect(res.body.appointments[1].status).toBe('cancelled');
    const range = await h.call('GET', '/api/owner/appointments?from=2026-11-02&to=2026-11-03', { owner: true });
    expect(range.body.appointments).toHaveLength(4);
    const today = await h.call('GET', '/api/owner/appointments', { owner: true });
    expect(today.body.appointments).toHaveLength(3);
  });

  it('uses shop-local days across the fall-back change (Nov 1 is 25 hours long)', async () => {
    const insert = (id: string, start: string) =>
      h.database.pool.query(
        `INSERT INTO appointments (id, offering_id, service_id, barber_id, service_name, barber_name, price_label, price_cents,
           price_kind, start_at, end_at, status, booked_by, customer_name, created_at, updated_at)
         VALUES ($1, 'x', 'haircut', 'flowxbori', 'Haircut', 'Flowxbori', '$35', 3500, 'fixed', $2,
           $2::timestamptz + interval '15 minutes', 'booked', 'shop', 'Walk-in', now(), now())`,
        [id, start],
      );
    await insert('20000000-0000-4000-8000-000000000001', '2026-11-01T07:15:00Z'); // Nov 1 00:15 PDT
    await insert('20000000-0000-4000-8000-000000000002', '2026-11-02T07:30:00Z'); // Nov 1 23:30 PST
    await insert('20000000-0000-4000-8000-000000000003', '2026-11-02T08:00:00Z'); // Nov 2 00:00 PST
    const nov1 = await h.call('GET', '/api/owner/appointments?date=2026-11-01', { owner: true });
    expect(nov1.body.appointments.map((a: { id: string }) => a.id)).toEqual([
      '20000000-0000-4000-8000-000000000001',
      '20000000-0000-4000-8000-000000000002',
    ]);
  });

  it('validates the dates', async () => {
    for (const q of ['date=2026-02-30', 'date=11/02/2026', 'from=2026-11-05&to=2026-11-01', 'from=2026-01-01&to=2026-12-31', 'date=2026-11-02&from=2026-11-01']) {
      const res = await h.call('GET', `/api/owner/appointments?${q}`, { owner: true });
      expect(res.status, q).toBe(400);
      expect(res.body.error.code).toBe('invalid_request');
    }
  });

  it('books a walk-in "now", off the grid and inside the lead time, with or without a phone', async () => {
    const res = await h.call('POST', '/api/owner/appointments', {
      owner: true,
      body: { offeringId: FLOW45, start: '2026-11-02T19:10:42Z', customer: { name: 'Walk-in' } },
    });
    expect(res.status).toBe(201);
    expect(Object.keys(res.body)).toEqual(['appointment']);
    expect(res.body.appointment).toMatchObject({
      start: '2026-11-02T19:10:00Z',
      end: '2026-11-02T19:55:00Z',
      customer: { name: 'Walk-in', phone: null, email: null },
      status: 'booked',
    });
    const withPhone = await h.call('POST', '/api/owner/appointments', {
      owner: true,
      body: { serviceId: 'haircut', barberId: 'any', start: '2026-11-02T19:10:00Z', customer: { name: 'Phone booking', phone: '442 555 0100' } },
    });
    expect(withPhone.status).toBe(201);
    expect(withPhone.body.appointment.barberId).toBe('cristian-ceja');
    expect(withPhone.body.appointment.customer.phone).toBe('+14425550100');
    // Earlier today (already started) is allowed for the shop; it's how a walk-in gets recorded late.
    const earlier = await h.call('POST', '/api/owner/appointments', {
      owner: true,
      body: { offeringId: JULIAN45, start: '2026-11-02T18:00:00Z', customer: { name: 'Earlier walk-in', phone: '' } },
    });
    expect(earlier.status).toBe(201);
    const { rows } = await h.database.pool.query('SELECT booked_by, manage_token_hash FROM appointments');
    expect(rows.every((r: { booked_by: string; manage_token_hash: null }) => r.booked_by === 'shop' && r.manage_token_hash === null)).toBe(true);
  });

  it('still enforces opening hours, the window and overlaps', async () => {
    const post = (start: string, offeringId = FLOW45) =>
      h.call('POST', '/api/owner/appointments', { owner: true, body: { offeringId, start, customer: { name: 'Walk-in' } } });
    expect((await post('2026-11-02T17:30:00Z')).body.error.code).toBe('outside_hours'); // 9:30 AM
    expect((await post('2026-11-03T02:30:00Z')).body.error.code).toBe('outside_hours'); // 6:30 PM + 45 > 7 PM
    expect((await post('2026-11-01T20:00:00Z')).body.error.code).toBe('too_soon'); // yesterday
    expect((await post('2027-01-02T18:00:00Z')).body.error.code).toBe('too_far');
    expect((await post('2026-11-02T20:00:00Z')).status).toBe(201);
    const clash = await post('2026-11-02T20:30:00Z');
    expect(clash.status).toBe(409);
    expect(clash.body.error.code).toBe('slot_taken');
    const bad = await h.call('POST', '/api/owner/appointments', {
      owner: true,
      body: { offeringId: FLOW45, start: '2026-11-02T21:00:00Z', customer: { name: 'Walk-in', phone: '12345' } },
    });
    expect(bad.status).toBe(400);
  });

  it('changes status: completed, no-show (frees the time), cancelled by the shop, and back to booked', async () => {
    const a = await customerBooking('2026-11-03T18:00:00Z');
    const patch = (status: string) => h.call('PATCH', `/api/owner/appointments/${a.id}`, { owner: true, body: { status } });
    h.advance(5);
    const done = await patch('completed');
    expect(done.status).toBe(200);
    expect(done.body.appointment).toMatchObject({ status: 'completed', cancelledBy: null });

    const noShow = await patch('noShow');
    expect(noShow.body.appointment.status).toBe('noShow');
    const slots = await h.call('GET', `/api/availability?offeringId=${encodeURIComponent(FLOW45)}&from=2026-11-03&days=1`);
    expect(slots.body.days[0].slots[0].start).toBe('2026-11-03T18:00:00Z');

    const cancelled = await patch('cancelled');
    expect(cancelled.body.appointment).toMatchObject({ status: 'cancelled', cancelledBy: 'shop' });
    const restored = await patch('booked');
    expect(restored.body.appointment).toMatchObject({ status: 'booked', cancelledBy: null });
  });

  it("keeps 'cancelled by customer' when the shop marks it cancelled again", async () => {
    const res = await h.call('POST', '/api/appointments', {
      body: { offeringId: FLOW45, start: '2026-11-03T18:00:00Z', customer: { name: 'A', phone: '4425550123' } },
    });
    await h.call('POST', `/api/appointments/${res.body.appointment.id}/cancel`, { headers: { 'x-manage-token': res.body.manageToken } });
    const again = await h.call('PATCH', `/api/owner/appointments/${res.body.appointment.id}`, { owner: true, body: { status: 'cancelled' } });
    expect(again.body.appointment.cancelledBy).toBe('customer');
  });

  it("can't restore an appointment into time that's been rebooked", async () => {
    const a = await customerBooking('2026-11-03T18:00:00Z');
    await h.call('PATCH', `/api/owner/appointments/${a.id}`, { owner: true, body: { status: 'cancelled' } });
    await customerBooking('2026-11-03T18:00:00Z', FLOW45, '4425550999');
    const res = await h.call('PATCH', `/api/owner/appointments/${a.id}`, { owner: true, body: { status: 'booked' } });
    expect(res.status).toBe(409);
    expect(res.body.error.code).toBe('slot_taken');
    // The connection is still healthy afterwards.
    expect((await h.call('GET', '/api/owner/appointments?date=2026-11-03', { owner: true })).body.appointments).toHaveLength(2);
  });

  it('404 for unknown ids, 400 for unknown statuses', async () => {
    const unknown = await h.call('PATCH', '/api/owner/appointments/00000000-0000-4000-8000-0000000000aa', { owner: true, body: { status: 'completed' } });
    expect(unknown.status).toBe(404);
    expect((await h.call('PATCH', '/api/owner/appointments/nope', { owner: true, body: { status: 'completed' } })).status).toBe(404);
    const a = await customerBooking('2026-11-03T18:00:00Z');
    for (const status of ['no_show', 'done', '', null]) {
      const res = await h.call('PATCH', `/api/owner/appointments/${a.id}`, { owner: true, body: { status } });
      expect(res.status).toBe(400);
      expect(res.body.error.message).toBe('status must be completed, noShow, cancelled or booked.');
    }
  });
});

describe('owner time off', () => {
  it('creates, lists by overlapping days, and deletes blocks', async () => {
    const shop = await h.call('POST', '/api/owner/time-off', {
      owner: true,
      body: { barberId: null, start: '2026-11-26T18:00:00Z', end: '2026-11-27T03:00:00Z', reason: 'Thanksgiving' },
    });
    expect(shop.status).toBe(201);
    expect(shop.body.timeOff).toEqual({
      id: expect.any(String),
      barberId: null,
      start: '2026-11-26T18:00:00Z',
      end: '2026-11-27T03:00:00Z',
      reason: 'Thanksgiving',
    });
    const barber = await h.call('POST', '/api/owner/time-off', {
      owner: true,
      body: { barberId: 'julian-ramos', start: '2026-11-03T20:00:30Z', end: '2026-11-03T22:00:00Z' },
    });
    expect(barber.body.timeOff).toMatchObject({ barberId: 'julian-ramos', start: '2026-11-03T20:00:00Z', reason: null });

    const list = await h.call('GET', '/api/owner/time-off?from=2026-11-01&to=2026-11-30', { owner: true });
    expect(list.body.timeOff.map((t: { reason: string | null }) => t.reason)).toEqual([null, 'Thanksgiving']);
    const one = await h.call('GET', '/api/owner/time-off?from=2026-11-27&to=2026-11-27', { owner: true });
    expect(one.body.timeOff).toHaveLength(0); // it ends at 7 PM PST on the 26th
    const thanksgiving = await h.call('GET', '/api/owner/time-off?from=2026-11-26&to=2026-11-26', { owner: true });
    expect(thanksgiving.body.timeOff).toHaveLength(1);

    const del = await h.call('DELETE', `/api/owner/time-off/${shop.body.timeOff.id}`, { owner: true });
    expect(del.status).toBe(204);
    expect(del.text).toBe('');
    expect((await h.call('DELETE', `/api/owner/time-off/${shop.body.timeOff.id}`, { owner: true })).status).toBe(404);
    expect((await h.call('DELETE', '/api/owner/time-off/not-a-uuid', { owner: true })).status).toBe(404);
  });

  it('lists up to a year of blocks at a time', async () => {
    expect((await h.call('GET', '/api/owner/time-off?from=2026-11-02&to=2027-11-02', { owner: true })).status).toBe(200);
    expect((await h.call('GET', '/api/owner/time-off?from=2026-11-02&to=2027-11-03', { owner: true })).status).toBe(400);
    expect((await h.call('GET', '/api/owner/appointments?from=2026-11-02&to=2027-01-02', { owner: true })).status).toBe(200); // 62 days
    expect((await h.call('GET', '/api/owner/appointments?from=2026-11-02&to=2027-01-03', { owner: true })).status).toBe(400);
  });

  it('validates the block', async () => {
    const post = (body: unknown) => h.call('POST', '/api/owner/time-off', { owner: true, body });
    expect((await post({ barberId: 'nobody', start: '2026-11-03T18:00:00Z', end: '2026-11-03T19:00:00Z' })).body.error.message).toBe(
      "That barber isn't on the team.",
    );
    expect((await post({ barberId: null, start: '2026-11-03T19:00:00Z', end: '2026-11-03T18:00:00Z' })).body.error.message).toBe(
      'The end has to be after the start.',
    );
    expect((await post({ barberId: null, start: '2026-11-03T19:00:00Z', end: '2026-11-03T19:00:20Z' })).status).toBe(400);
    expect((await post({ barberId: null, start: '2026-11-03T19:00:00Z', end: '2028-11-03T19:00:00Z' })).status).toBe(400);
    expect((await post({ barberId: null, start: 'soon', end: '2026-11-03T19:00:00Z' })).status).toBe(400);
    expect((await post({ barberId: null, start: '2026-11-03T18:00:00Z', end: '2026-11-03T19:00:00Z', reason: 'r'.repeat(201) })).status).toBe(400);
    // barberId may be left out for the whole shop.
    expect((await post({ start: '2026-11-03T18:00:00Z', end: '2026-11-03T19:00:00Z' })).body.timeOff.barberId).toBeNull();
  });

  it('a block over an existing appointment keeps the appointment but stops new ones', async () => {
    const a = await customerBooking('2026-11-03T18:00:00Z');
    await h.call('POST', '/api/owner/time-off', { owner: true, body: { barberId: 'flowxbori', start: '2026-11-03T18:00:00Z', end: '2026-11-04T03:00:00Z' } });
    const list = await h.call('GET', '/api/owner/appointments?date=2026-11-03', { owner: true });
    expect(list.body.appointments[0]).toMatchObject({ id: a.id, status: 'booked' });
    const slots = await h.call('GET', `/api/availability?offeringId=${encodeURIComponent(FLOW45)}&from=2026-11-03&days=1`);
    expect(slots.body.days[0].slots).toEqual([]);
  });
});
