import { describe, expect, it } from 'vitest';
import { hashManageToken } from '../src/auth.js';
import { useHarness } from './helpers/harness.js';

// Monday Nov 2 2026, 9:00 AM PST. Tuesday Nov 3 opens at 10:00 PST = 18:00Z.
const h = useHarness({ now: '2026-11-02T17:00:00Z' });

export const FLOW45 = 'flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a';
export const FLOW60 = 'flowxbori/0d069a9e-c5ea-4cca-ae34-3f38bf668940';
export const CRISTIAN45 = 'cristian-ceja/bbb0c294-87a6-465d-9f55-6f579dcb399a';
export const JULIAN45 = 'julian-ramos/bbb0c294-87a6-465d-9f55-6f579dcb399a';
export const IZZY_VIP = 'israel-flores/9a33be59-43eb-445c-9c18-6435125b1f75';

const customer = { name: 'Test Client', phone: '(442) 555-0123' };

function book(body: Record<string, unknown>, ip?: string) {
  return h.call('POST', '/api/appointments', { body: { customer, ...body }, ...(ip ? { ip } : {}) });
}

let phoneCounter = 0;
/** A different phone each time, so the 3-per-phone limit stays out of the way. */
function freshCustomer() {
  phoneCounter += 1;
  return { name: 'Test Client', phone: `442555${String(1000 + phoneCounter).slice(-4)}` };
}

function bookFresh(body: Record<string, unknown>) {
  return h.call('POST', '/api/appointments', { body: { customer: freshCustomer(), ...body }, ip: `198.51.100.${phoneCounter % 250}` });
}

describe('POST /api/appointments', () => {
  it('books a specific barber and returns the appointment and a manage token', async () => {
    const res = await book({ offeringId: FLOW45, start: '2026-11-03T18:00:00Z', note: '  Skin fade please  ' });
    expect(res.status).toBe(201);
    expect(res.headers.get('content-type')).toMatch(/^application\/json/);
    expect(res.headers.get('cache-control')).toBe('no-store');
    const a = res.body.appointment;
    expect(a).toMatchObject({
      offeringId: FLOW45,
      serviceId: 'haircut',
      serviceName: 'Haircut',
      barberId: 'flowxbori',
      barberName: 'Flowxbori',
      start: '2026-11-03T18:00:00Z',
      end: '2026-11-03T18:45:00Z',
      durationMinutes: 45,
      priceLabel: '$35',
      status: 'booked',
      cancelledBy: null,
      payment: { status: 'unpaid', amountCents: null, paidAt: null },
      customer: { name: 'Test Client', phone: '+14425550123', email: null },
      note: 'Skin fade please',
      createdAt: '2026-11-02T17:00:00Z',
    });
    expect(res.body.manageToken).toMatch(/^[A-Za-z0-9_-]{43}$/);
    // Only the token's SHA-256 is stored.
    const { rows } = await h.database.pool.query('SELECT manage_token_hash FROM appointments WHERE id = $1', [a.id]);
    expect(rows[0].manage_token_hash).toBe(hashManageToken(res.body.manageToken));
    const dump = JSON.stringify((await h.database.pool.query('SELECT * FROM appointments')).rows);
    expect(dump).not.toContain(res.body.manageToken);
  });

  it('rejects an overlapping booking for the same barber with 409 from the exclusion constraint', async () => {
    expect((await bookFresh({ offeringId: FLOW45, start: '2026-11-03T18:00:00Z' })).status).toBe(201);
    const clash = await bookFresh({ offeringId: FLOW45, start: '2026-11-03T18:30:00Z' });
    expect(clash.status).toBe(409);
    expect(clash.body).toEqual({ error: { code: 'slot_taken', message: 'Someone just booked that time. Pick another.' } });
    // The same start for another barber is fine.
    expect((await bookFresh({ offeringId: CRISTIAN45, start: '2026-11-03T18:30:00Z' })).status).toBe(201);
  });

  it('the constraint itself rejects overlaps and allows back-to-back rows', async () => {
    const insert = (id: string, start: string, end: string, status = 'booked') =>
      h.database.pool.query(
        `INSERT INTO appointments (id, offering_id, service_id, barber_id, service_name, barber_name, price_label, price_cents,
           price_kind, start_at, end_at, status, cancelled_by, booked_by, customer_name, created_at, updated_at)
         VALUES ($1, 'x', 'haircut', 'flowxbori', 'Haircut', 'Flowxbori', '$35', 3500, 'fixed', $2, $3, $4,
           CASE WHEN $4 = 'cancelled' THEN 'shop' END, 'shop', 'Walk-in', now(), now())`,
        [id, start, end, status],
      );
    await insert('10000000-0000-4000-8000-000000000001', '2026-11-03T18:00:00Z', '2026-11-03T19:00:00Z');
    await insert('10000000-0000-4000-8000-000000000002', '2026-11-03T19:00:00Z', '2026-11-03T19:45:00Z');
    await expect(insert('10000000-0000-4000-8000-000000000003', '2026-11-03T18:59:00Z', '2026-11-03T19:10:00Z')).rejects.toMatchObject({
      code: '23P01',
      constraint: 'appointments_no_overlap',
    });
    // Cancelled and no-show rows don't hold the time.
    await insert('10000000-0000-4000-8000-000000000004', '2026-11-03T18:00:00Z', '2026-11-03T19:00:00Z', 'cancelled');
    await insert('10000000-0000-4000-8000-000000000005', '2026-11-03T18:00:00Z', '2026-11-03T19:00:00Z', 'no_show');
  });

  it('allows back-to-back appointments for one barber', async () => {
    expect((await bookFresh({ offeringId: FLOW60, start: '2026-11-03T18:00:00Z' })).status).toBe(201);
    const next = await bookFresh({ offeringId: FLOW45, start: '2026-11-03T19:00:00Z' });
    expect(next.status).toBe(201);
    expect(next.body.appointment.start).toBe('2026-11-03T19:00:00Z');
  });

  it('takes the slot out of availability, and a cancellation puts it back', async () => {
    const slots = async () =>
      (await h.call('GET', `/api/availability?offeringId=${encodeURIComponent(FLOW45)}&from=2026-11-03&days=1`)).body.days[0].slots.map(
        (s: { start: string }) => s.start,
      );
    expect(await slots()).toContain('2026-11-03T18:30:00Z');
    const res = await book({ offeringId: FLOW45, start: '2026-11-03T18:30:00Z' });
    const after = await slots();
    // 18:00 would end at 18:45 and 18:30 and 19:00 overlap 18:30–19:15.
    expect(after).not.toContain('2026-11-03T18:00:00Z');
    expect(after).not.toContain('2026-11-03T18:30:00Z');
    expect(after).not.toContain('2026-11-03T19:00:00Z');
    expect(after).toContain('2026-11-03T19:30:00Z');

    const cancel = await h.call('POST', `/api/appointments/${res.body.appointment.id}/cancel`, {
      headers: { 'x-manage-token': res.body.manageToken },
    });
    expect(cancel.status).toBe(200);
    expect(cancel.body.appointment).toMatchObject({ status: 'cancelled', cancelledBy: 'customer' });
    expect(await slots()).toContain('2026-11-03T18:30:00Z');
    expect((await bookFresh({ offeringId: FLOW45, start: '2026-11-03T18:30:00Z' })).status).toBe(201);
  });

  it('books on the fall-back DST day at 10 AM PST', async () => {
    h.setNow('2026-10-31T17:05:00Z');
    const res = await bookFresh({ offeringId: FLOW45, start: '2026-11-01T18:00:00Z' });
    expect(res.status).toBe(201);
    // 17:00Z would be 9 AM PST, before opening.
    const early = await bookFresh({ offeringId: FLOW45, start: '2026-11-01T17:00:00Z' });
    expect(early.status).toBe(422);
    expect(early.body.error.code).toBe('outside_hours');
  });

  it('books on the spring-forward DST day at 10 AM PDT', async () => {
    h.setNow('2026-03-07T18:00:00Z');
    expect((await bookFresh({ offeringId: FLOW45, start: '2026-03-08T17:00:00Z' })).status).toBe(201);
    const closing = await bookFresh({ offeringId: FLOW45, start: '2026-03-09T00:30:00Z' }); // 5:30 PM PDT Sunday, ends 6:15
    expect(closing.body.error.code).toBe('outside_hours');
  });
});

describe('time rules', () => {
  it('too soon: inside the 30-minute lead time, or in the past', async () => {
    h.setNow('2026-11-03T18:05:00Z'); // Tue 10:05 AM
    const soon = await bookFresh({ offeringId: FLOW45, start: '2026-11-03T18:30:00Z' });
    expect(soon.status).toBe(422);
    expect(soon.body.error).toEqual({ code: 'too_soon', message: "That's too soon. Pick a time at least 30 minutes from now." });
    const past = await bookFresh({ offeringId: FLOW45, start: '2026-11-03T18:00:00Z' });
    expect(past.body.error).toEqual({ code: 'too_soon', message: 'That time has already passed. Pick another.' });
    expect((await bookFresh({ offeringId: FLOW45, start: '2026-11-03T19:00:00Z' })).status).toBe(201);
  });

  it('too far: day 61 is out, day 60 is in', async () => {
    // Today is Nov 2 → the last bookable day is Jan 1 2027.
    const far = await bookFresh({ offeringId: FLOW45, start: '2027-01-02T18:00:00Z' });
    expect(far.status).toBe(422);
    expect(far.body.error.code).toBe('too_far');
    expect((await bookFresh({ offeringId: FLOW45, start: '2027-01-01T18:00:00Z' })).status).toBe(201);
  });

  it("uses the shop's date, not UTC's, for today and the 60-day window", async () => {
    h.setNow('2026-11-03T07:30:00Z'); // Mon Nov 2, 11:30 PM PST; already Nov 3 in UTC
    const today = await h.call('GET', `/api/availability?offeringId=${encodeURIComponent(FLOW45)}`);
    expect(today.body.days).toEqual([{ date: '2026-11-02', slots: [] }]);
    // Last bookable day: Nov 2 + 60 = Jan 1 (UTC's date would wrongly allow Jan 2).
    expect((await bookFresh({ offeringId: FLOW45, start: '2027-01-02T18:00:00Z' })).body.error.code).toBe('too_far');
    expect((await bookFresh({ offeringId: FLOW45, start: '2027-01-01T18:00:00Z' })).status).toBe(201);
    expect((await bookFresh({ offeringId: FLOW45, start: '2026-11-03T18:00:00Z' })).status).toBe(201);
  });

  it('outside hours: off the 30-minute grid, or running past closing', async () => {
    const offGrid = await bookFresh({ offeringId: FLOW45, start: '2026-11-03T18:15:00Z' });
    expect(offGrid.body.error).toEqual({ code: 'outside_hours', message: "That isn't one of our booking times. Pick a time from the list." });
    // Tue closes 7 PM PST = 03:00Z. 6:30 PM + 45 min runs past it; 6:00 PM fits.
    expect((await bookFresh({ offeringId: FLOW45, start: '2026-11-04T02:30:00Z' })).body.error.code).toBe('outside_hours');
    expect((await bookFresh({ offeringId: FLOW45, start: '2026-11-04T02:00:00Z' })).status).toBe(201);
    // Sunday closes at 6 PM: the 75-minute VIP can't start at 5 PM.
    expect((await bookFresh({ offeringId: IZZY_VIP, start: '2026-11-09T01:00:00Z' })).body.error.code).toBe('outside_hours');
    expect((await bookFresh({ offeringId: IZZY_VIP, start: '2026-11-09T00:30:00Z' })).status).toBe(201);
    // Before opening.
    expect((await bookFresh({ offeringId: FLOW45, start: '2026-11-03T17:30:00Z' })).body.error.code).toBe('outside_hours');
  });

  it('accepts the start with an offset or fractional zero seconds, and echoes it in UTC', async () => {
    const res = await bookFresh({ offeringId: FLOW45, start: '2026-11-03T10:00:00.000-08:00' });
    expect(res.status).toBe(201);
    expect(res.body.appointment.start).toBe('2026-11-03T18:00:00Z');
  });
});

describe('any barber', () => {
  it('assigns the free barber with the fewest bookings that day, ties in team order', async () => {
    const any = (start: string) => bookFresh({ serviceId: 'haircut', barberId: 'any', start });
    const order: string[] = [];
    for (const start of ['2026-11-03T18:00:00Z', '2026-11-03T19:00:00Z', '2026-11-03T20:00:00Z', '2026-11-03T21:00:00Z']) {
      const res = await any(start);
      expect(res.status).toBe(201);
      expect(res.body.appointment.offeringId).toMatch(/\/bbb0c294-87a6-465d-9f55-6f579dcb399a$/);
      order.push(res.body.appointment.barberId);
    }
    expect(order).toEqual(['flowxbori', 'cristian-ceja', 'julian-ramos', 'flowxbori']);
  });

  it('counts only that day, and only live bookings', async () => {
    // Flowxbori: two bookings on another day and a cancelled one today. None of them count,
    // so Flowxbori still wins today's tie on team order.
    await bookFresh({ offeringId: FLOW45, start: '2026-11-04T18:00:00Z' });
    await bookFresh({ offeringId: FLOW45, start: '2026-11-04T19:00:00Z' });
    const cancelled = await bookFresh({ offeringId: FLOW45, start: '2026-11-03T22:00:00Z' });
    await h.call('POST', `/api/appointments/${cancelled.body.appointment.id}/cancel`, { headers: { 'x-manage-token': cancelled.body.manageToken } });
    const res = await bookFresh({ serviceId: 'haircut', barberId: 'any', start: '2026-11-03T18:00:00Z' });
    expect(res.body.appointment.barberId).toBe('flowxbori');
  });

  it('skips barbers who are busy or off, and says slot_taken when nobody is free', async () => {
    await bookFresh({ offeringId: FLOW45, start: '2026-11-03T18:00:00Z' });
    await h.call('POST', '/api/owner/time-off', {
      owner: true,
      body: { barberId: 'cristian-ceja', start: '2026-11-03T17:00:00Z', end: '2026-11-03T20:00:00Z', reason: 'Dentist' },
    });
    const res = await bookFresh({ serviceId: 'haircut', barberId: 'any', start: '2026-11-03T18:00:00Z' });
    expect(res.body.appointment.barberId).toBe('julian-ramos');
    const avail = await h.call('GET', '/api/availability?serviceId=haircut&barberId=any&from=2026-11-03&days=1');
    expect(avail.body.days[0].slots.find((s: { start: string }) => s.start === '2026-11-03T18:00:00Z')).toBeUndefined();
    expect(avail.body.days[0].slots.find((s: { start: string }) => s.start === '2026-11-03T19:00:00Z')).toEqual({
      start: '2026-11-03T19:00:00Z',
      barberIds: ['flowxbori', 'julian-ramos'],
    });
    const none = await bookFresh({ serviceId: 'haircut', barberId: 'any', start: '2026-11-03T18:00:00Z' });
    expect(none.status).toBe(409);
    expect(none.body.error.code).toBe('slot_taken');
  });

  it('ends by closing for each service length', async () => {
    const lastStart = async (serviceId: string) =>
      (await h.call('GET', `/api/availability?serviceId=${serviceId}&barberId=any&from=2026-11-03&days=1`)).body.days[0].slots.at(-1).start;
    // Tuesday closes at 7 PM PST (03:00Z).
    expect(await lastStart('hot-towel-shave')).toBe('2026-11-04T02:30:00Z'); // 30 min
    expect(await lastStart('haircut')).toBe('2026-11-04T02:00:00Z'); // 45 min
    expect(await lastStart('haircut-and-beard')).toBe('2026-11-04T02:00:00Z'); // 60 min
  });

  it('rejects any-barber requests a service cannot take', async () => {
    const vip = await bookFresh({ serviceId: 'vip', barberId: 'any', start: '2026-11-03T18:00:00Z' });
    expect(vip.status).toBe(400);
    expect(vip.body.error.message).toBe('This service needs a specific barber. Pick one to see their times.');
    const specific = await bookFresh({ serviceId: 'haircut', barberId: 'flowxbori', start: '2026-11-03T18:00:00Z' });
    expect(specific.status).toBe(400);
    const unknown = await bookFresh({ serviceId: 'massage', barberId: 'any', start: '2026-11-03T18:00:00Z' });
    expect(unknown.status).toBe(400);
  });
});

describe('time off', () => {
  it('blocks the barber’s bookings and availability, and shop-wide blocks block everyone', async () => {
    const off = await h.call('POST', '/api/owner/time-off', {
      owner: true,
      body: { barberId: 'flowxbori', start: '2026-11-03T18:00:00Z', end: '2026-11-03T20:00:00Z' },
    });
    expect(off.status).toBe(201);
    const blocked = await bookFresh({ offeringId: FLOW45, start: '2026-11-03T19:00:00Z' });
    expect(blocked.status).toBe(409);
    expect(blocked.body.error.code).toBe('slot_taken');
    // Ends at 20:00, so a 19:30 start (ending 20:15) overlaps; 20:00 is fine.
    expect((await bookFresh({ offeringId: FLOW45, start: '2026-11-03T19:30:00Z' })).status).toBe(409);
    expect((await bookFresh({ offeringId: FLOW45, start: '2026-11-03T20:00:00Z' })).status).toBe(201);
    expect((await bookFresh({ offeringId: CRISTIAN45, start: '2026-11-03T19:00:00Z' })).status).toBe(201);

    await h.call('POST', '/api/owner/time-off', {
      owner: true,
      body: { barberId: null, start: '2026-11-04T18:00:00Z', end: '2026-11-05T03:00:00Z', reason: 'Closed for the holiday' },
    });
    expect((await bookFresh({ offeringId: JULIAN45, start: '2026-11-04T20:00:00Z' })).status).toBe(409);
    const day = await h.call('GET', '/api/availability?serviceId=haircut&barberId=any&from=2026-11-04&days=1');
    expect(day.body.days[0].slots).toEqual([]);
  });
});

describe('validation', () => {
  const start = '2026-11-03T18:00:00Z';
  const cases: [string, Record<string, unknown>, string][] = [
    ['missing name', { offeringId: FLOW45, start, customer: { phone: '4425550123' } }, 'Enter your name.'],
    ['blank name', { offeringId: FLOW45, start, customer: { name: '   ', phone: '4425550123' } }, 'Enter your name.'],
    ['61-character name', { offeringId: FLOW45, start, customer: { name: 'a'.repeat(61), phone: '4425550123' } }, 'Keep the name to 60 characters or fewer.'],
    ['name with a line break', { offeringId: FLOW45, start, customer: { name: 'A\nB', phone: '4425550123' } }, 'The name has characters we can’t use.'],
    ['missing phone', { offeringId: FLOW45, start, customer: { name: 'A' } }, 'Enter a US mobile number.'],
    ['short phone', { offeringId: FLOW45, start, customer: { name: 'A', phone: '555-0123' } }, 'Enter a US mobile number, like (442) 341-3053.'],
    ['UK phone', { offeringId: FLOW45, start, customer: { name: 'A', phone: '+44 20 7946 0958' } }, 'Enter a US mobile number, like (442) 341-3053.'],
    ['301-character note', { offeringId: FLOW45, start, customer, note: 'n'.repeat(301) }, 'Keep the note to 300 characters or fewer.'],
    ['bad email', { offeringId: FLOW45, start, customer: { ...customer, email: 'not-an-email' } }, 'Enter a valid email address.'],
    ['bad start', { offeringId: FLOW45, start: 'tomorrow at 10', customer }, 'Times must be ISO 8601, like 2026-11-02T18:00:00Z.'],
    ['start without a zone', { offeringId: FLOW45, start: '2026-11-03T10:00:00', customer }, 'Times must be ISO 8601, like 2026-11-02T18:00:00Z.'],
    ['no customer', { offeringId: FLOW45, start }, 'Add your name and mobile number.'],
    ['unknown offering', { offeringId: 'nobody/123', start, customer }, "That service isn't on the menu any more. Pick another."],
    ['no service at all', { start, customer }, 'Choose a service: send offeringId, or serviceId with barberId "any".'],
    ['offering and a different barber', { offeringId: FLOW45, barberId: 'julian-ramos', start, customer }, "The barber doesn't match the menu item."],
  ];
  for (const [name, body, message] of cases) {
    it(`400 for ${name}`, async () => {
      const res = await h.call('POST', '/api/appointments', { body });
      expect(res.status).toBe(400);
      expect(res.body).toEqual({ error: { code: 'invalid_request', message } });
    });
  }

  it('300-character notes, 60-character names and emoji count as people count them', async () => {
    const res = await bookFresh({
      offeringId: FLOW45,
      start,
      customer: { name: '✂️'.repeat(30), phone: '+1 (442) 555-0199', email: ' client@example.com ' },
      note: '💈'.repeat(300),
    });
    expect(res.status).toBe(201);
    expect(res.body.appointment.customer).toEqual({ name: '✂️'.repeat(30), phone: '+14425550199', email: 'client@example.com' });
  });

  it('rejects bodies that are not JSON objects', async () => {
    for (const rawBody of ['', 'not json', '[1,2]', 'null']) {
      const res = await h.call('POST', '/api/appointments', { rawBody, headers: { 'content-type': 'application/json' } });
      expect(res.status).toBe(400);
      expect(res.body.error.code).toBe('invalid_request');
    }
  });

  it('rejects oversized bodies with 413', async () => {
    const res = await h.call('POST', '/api/appointments', { rawBody: JSON.stringify({ note: 'x'.repeat(20_000) }) });
    expect(res.status).toBe(413);
    expect(res.body.error.code).toBe('invalid_request');
  });
});

describe('manage token', () => {
  async function booked() {
    const res = await bookFresh({ offeringId: FLOW45, start: '2026-11-03T18:00:00Z' });
    return { id: res.body.appointment.id as string, token: res.body.manageToken as string };
  }

  it('reads the appointment with the right token', async () => {
    const { id, token } = await booked();
    const res = await h.call('GET', `/api/appointments/${id}`, { headers: { 'x-manage-token': token } });
    expect(res.status).toBe(200);
    expect(res.body.appointment.id).toBe(id);
    expect(Object.keys(res.body)).toEqual(['appointment']);
  });

  it('401 without a token; 404 for a wrong token, an unknown id or a malformed id', async () => {
    const { id, token } = await booked();
    expect((await h.call('GET', `/api/appointments/${id}`)).status).toBe(401);
    const wrong = token.slice(0, -1) + (token.endsWith('A') ? 'B' : 'A');
    const r1 = await h.call('GET', `/api/appointments/${id}`, { headers: { 'x-manage-token': wrong } });
    expect(r1.status).toBe(404);
    expect(r1.body.error.code).toBe('not_found');
    expect((await h.call('GET', '/api/appointments/00000000-0000-4000-8000-0000000000ff', { headers: { 'x-manage-token': token } })).status).toBe(404);
    expect((await h.call('GET', '/api/appointments/not-a-uuid', { headers: { 'x-manage-token': token } })).status).toBe(404);
    expect((await h.call('GET', `/api/appointments/${id}`, { headers: { 'x-manage-token': 'short' } })).status).toBe(404);
    expect((await h.call('POST', `/api/appointments/${id}/cancel`, { headers: { 'x-manage-token': wrong } })).status).toBe(404);
  });

  it("one appointment's token doesn't open another", async () => {
    const a = await booked();
    const b = await bookFresh({ offeringId: CRISTIAN45, start: '2026-11-03T18:00:00Z' });
    expect((await h.call('GET', `/api/appointments/${b.body.appointment.id}`, { headers: { 'x-manage-token': a.token } })).status).toBe(404);
  });

  it('cannot cancel twice, after it started, or once completed', async () => {
    const { id, token } = await booked();
    const headers = { 'x-manage-token': token };
    expect((await h.call('POST', `/api/appointments/${id}/cancel`, { headers })).status).toBe(200);
    const again = await h.call('POST', `/api/appointments/${id}/cancel`, { headers });
    expect(again.status).toBe(409);
    expect(again.body.error).toEqual({ code: 'not_cancellable', message: 'This appointment is already cancelled.' });

    const second = await bookFresh({ offeringId: FLOW45, start: '2026-11-03T20:00:00Z' });
    h.setNow('2026-11-03T20:00:00Z');
    const started = await h.call('POST', `/api/appointments/${second.body.appointment.id}/cancel`, {
      headers: { 'x-manage-token': second.body.manageToken },
    });
    expect(started.status).toBe(409);
    expect(started.body.error.code).toBe('not_cancellable');

    h.setNow('2026-11-02T17:00:00Z');
    const third = await bookFresh({ offeringId: JULIAN45, start: '2026-11-03T20:00:00Z' });
    await h.call('PATCH', `/api/owner/appointments/${third.body.appointment.id}`, { owner: true, body: { status: 'completed' } });
    const done = await h.call('POST', `/api/appointments/${third.body.appointment.id}/cancel`, {
      headers: { 'x-manage-token': third.body.manageToken },
    });
    expect(done.body.error).toEqual({ code: 'not_cancellable', message: "This appointment can't be cancelled any more." });
  });

  it('shows a shop cancellation to the customer', async () => {
    const { id, token } = await booked();
    await h.call('PATCH', `/api/owner/appointments/${id}`, { owner: true, body: { status: 'cancelled' } });
    const res = await h.call('GET', `/api/appointments/${id}`, { headers: { 'x-manage-token': token } });
    expect(res.body.appointment).toMatchObject({ status: 'cancelled', cancelledBy: 'shop' });
  });
});

describe('concurrency', () => {
  it('two bookings for the same barber and time at once: exactly one 201 and one 409', async () => {
    const body = (n: number) => ({
      offeringId: FLOW45,
      start: '2026-11-03T18:00:00Z',
      customer: { name: `Racer ${n}`, phone: `442555010${n}` },
    });
    const results = await Promise.all([
      h.call('POST', '/api/appointments', { body: body(1), ip: '192.0.2.1' }),
      h.call('POST', '/api/appointments', { body: body(2), ip: '192.0.2.2' }),
    ]);
    expect(results.map((r) => r.status).sort()).toEqual([201, 409]);
    expect(results.find((r) => r.status === 409)!.body.error.code).toBe('slot_taken');
    const { rows } = await h.database.pool.query(`SELECT count(*)::int AS n FROM appointments WHERE status = 'booked'`);
    expect(rows[0].n).toBe(1);
  });

  it('ten at once for one slot: one wins', async () => {
    const results = await Promise.all(
      Array.from({ length: 10 }, (_, i) =>
        h.call('POST', '/api/appointments', {
          body: { offeringId: FLOW45, start: '2026-11-03T18:00:00Z', customer: { name: `Racer ${i}`, phone: `44255502${String(i).padStart(2, '0')}` } },
          ip: `192.0.2.${i + 10}`,
        }),
      ),
    );
    expect(results.filter((r) => r.status === 201)).toHaveLength(1);
    expect(results.filter((r) => r.status === 409)).toHaveLength(9);
  });

  it('two any-barber bookings at once get two different barbers', async () => {
    const results = await Promise.all(
      [1, 2].map((n) =>
        h.call('POST', '/api/appointments', {
          body: { serviceId: 'haircut', barberId: 'any', start: '2026-11-03T18:00:00Z', customer: { name: `Any ${n}`, phone: `442555030${n}` } },
          ip: `192.0.2.${n + 40}`,
        }),
      ),
    );
    expect(results.map((r) => r.status)).toEqual([201, 201]);
    const barbers = results.map((r) => r.body.appointment.barberId);
    expect(new Set(barbers).size).toBe(2);
  });
});
