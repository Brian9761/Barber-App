import { describe, expect, it } from 'vitest';
import { hashManageToken, isNewManageToken, newManageToken } from '../src/auth.js';
import { RESPONSES } from './helpers/contract.js';
import { useHarness, type CallOptions } from './helpers/harness.js';

// POST /api/appointments with the app's own X-Manage-Token: the token doubles as
// the booking's idempotency key, so a retry after a lost answer gets the booking
// that went through instead of `slot_taken` for the client's own appointment.

// Monday Nov 2 2026, 9:00 AM PST. Tuesday Nov 3 opens at 10:00 PST = 18:00Z.
const h = useHarness({ now: '2026-11-02T17:00:00Z' });

const FLOW45 = 'flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a';
const CRISTIAN45 = 'cristian-ceja/bbb0c294-87a6-465d-9f55-6f579dcb399a';
const TUE10 = '2026-11-03T18:00:00Z';
const TUE11 = '2026-11-03T19:00:00Z';

const customer = { name: 'Retry Client', phone: '(442) 555-0123' };
const booking = { offeringId: FLOW45, start: TUE10, customer, note: 'Skin fade, please.' };

function post(body: Record<string, unknown>, token: string | undefined, options: CallOptions = {}) {
  return h.call('POST', '/api/appointments', {
    ...options,
    body,
    headers: { ...options.headers, ...(token === undefined ? {} : { 'x-manage-token': token }) },
  });
}

async function count(where = 'true'): Promise<number> {
  const { rows } = await h.database.pool.query(`SELECT count(*)::int AS n FROM appointments WHERE ${where}`);
  return rows[0].n;
}

async function attemptsCounted(): Promise<number> {
  const { rows } = await h.database.pool.query(`SELECT coalesce(sum(count), 0)::int AS n FROM rate_limits`);
  return rows[0].n;
}

describe('X-Manage-Token on POST /api/appointments', () => {
  it('books with the app’s own token: only its hash is stored, and it manages the appointment', async () => {
    const token = newManageToken();
    const res = await post(booking, token);
    expect(res.status).toBe(201);
    expect(res.body.manageToken).toBe(token);
    const id = res.body.appointment.id;
    const { rows } = await h.database.pool.query('SELECT manage_token_hash FROM appointments WHERE id = $1', [id]);
    expect(rows[0].manage_token_hash).toBe(hashManageToken(token));
    expect(JSON.stringify((await h.database.pool.query('SELECT * FROM appointments')).rows)).not.toContain(token);

    const read = await h.call('GET', `/api/appointments/${id}`, { headers: { 'x-manage-token': token } });
    expect(read.status).toBe(200);
    const cancel = await h.call('POST', `/api/appointments/${id}/cancel`, { headers: { 'x-manage-token': token } });
    expect(cancel.body.appointment.status).toBe('cancelled');
  });

  it('a retry after a lost answer gets 200 with the same appointment and token, and books nothing more', async () => {
    const token = newManageToken();
    const first = await post(booking, token);
    expect(first.status).toBe(201);
    h.advance(2);
    const retry = await post(booking, token);
    expect(retry.status).toBe(200);
    expect(retry.headers.get('cache-control')).toBe('no-store');
    expect(retry.body).toEqual(first.body);
    // Same shape as a fresh booking, so the apps decode it the same way.
    expect(RESPONSES['appointment-created'].safeParse(retry.body).success).toBe(true);
    expect(await count()).toBe(1);
    // And again, still the same.
    expect((await post(booking, token)).body.appointment.id).toBe(first.body.appointment.id);
    expect(await count()).toBe(1);
  });

  it('matches on the target, start and phone: the name, the note and how the number is typed may differ', async () => {
    const token = newManageToken();
    const first = await post(booking, token);
    const retry = await post(
      { ...booking, start: '2026-11-03T10:00:00.000-08:00', customer: { name: 'Someone Else', phone: '+1 442 555 0123' }, note: 'Changed' },
      token,
    );
    expect(retry.status).toBe(200);
    // The appointment as it was booked.
    expect(retry.body.appointment).toEqual(first.body.appointment);
    expect(retry.body.appointment.note).toBe('Skin fade, please.');
  });

  it('any barber: a retry gets the barber the shop picked, even once nobody else is free', async () => {
    const token = newManageToken();
    const any = { serviceId: 'haircut', barberId: 'any', start: TUE10, customer };
    const first = await post(any, token);
    expect(first.status).toBe(201);
    // The other two barbers get booked at that time too.
    for (const phone of ['4425550131', '4425550132']) {
      expect((await post({ ...any, customer: { name: 'Other', phone } }, undefined, { ip: '198.51.100.20' })).status).toBe(201);
    }
    expect((await post({ ...any, customer: { name: 'Late', phone: '4425550133' } }, undefined, { ip: '198.51.100.21' })).status).toBe(409);

    const retry = await post(any, token);
    expect(retry.status).toBe(200);
    expect(retry.body.appointment).toEqual(first.body.appointment);
    // Naming the barber it got isn't the same request.
    expect((await post({ ...booking, offeringId: first.body.appointment.offeringId }, token)).status).toBe(400);
    expect(await count()).toBe(3);
  });

  it('the same token for a different booking is a 400 and books nothing', async () => {
    const token = newManageToken();
    expect((await post(booking, token)).status).toBe(201);
    const different = [
      { ...booking, start: TUE11 },
      { ...booking, offeringId: CRISTIAN45 },
      { ...booking, customer: { ...customer, phone: '(442) 555-0124' } },
      { serviceId: 'haircut', barberId: 'any', start: TUE10, customer },
      { serviceId: 'military-haircut', barberId: 'any', start: TUE10, customer },
      { ...booking, serviceId: 'military-haircut' },
    ];
    for (const body of different) {
      const res = await post(body, token);
      expect(res.status, JSON.stringify(body)).toBe(400);
      expect(res.body.error).toEqual({ code: 'invalid_request', message: 'That booking token was already used.' });
    }
    expect(await count()).toBe(1);
  });

  it('a malformed token is a 400, books nothing and counts no attempt', async () => {
    const canonical = newManageToken();
    const malformed = [
      '',
      '   ',
      'short',
      canonical.slice(0, 42),
      `${canonical}A`,
      `${canonical.slice(0, 42)}+`,
      `${canonical.slice(0, 42)}=`,
      `${canonical.slice(0, 21)} ${canonical.slice(22)}`,
      // 43 base64url characters, but not what 32 bytes encode to: the last one has unused bits set.
      `${'A'.repeat(42)}B`,
      'fixture-manage-token-0001xxxxxxxxxxxxxxxxx',
    ];
    for (const token of malformed) {
      const res = await post(booking, token);
      expect(res.status, JSON.stringify(token)).toBe(400);
      expect(res.body.error.code).toBe('invalid_request');
      expect(res.body.error.message).toBe('X-Manage-Token must be 32 random bytes in base64url (43 characters).');
    }
    expect(await count()).toBe(0);
    expect(await attemptsCounted()).toBe(0);
    // Surrounding spaces are fine.
    expect((await post(booking, ` ${canonical} `)).body.manageToken).toBe(canonical);
  });

  it('only accepts exactly what newManageToken makes', () => {
    for (let i = 0; i < 200; i++) expect(isNewManageToken(newManageToken())).toBe(true);
    expect(isNewManageToken(`${'A'.repeat(42)}A`)).toBe(true);
    expect(isNewManageToken(`${'A'.repeat(42)}E`)).toBe(true);
    expect(isNewManageToken(`${'A'.repeat(42)}C`)).toBe(false);
  });

  it('a retry works after the lead time has passed, when a new booking for that time would be too soon', async () => {
    const token = newManageToken();
    const first = await post(booking, token);
    h.setNow('2026-11-03T17:45:00Z'); // 15 minutes before
    const retry = await post(booking, token);
    expect(retry.status).toBe(200);
    expect(retry.body.appointment.id).toBe(first.body.appointment.id);
    h.setNow('2026-11-03T18:10:00Z'); // it has started
    expect((await post(booking, token)).status).toBe(200);
    expect((await post({ ...booking, offeringId: CRISTIAN45 }, newManageToken())).body.error.code).toBe('too_soon');
  });

  it('a retry after someone else took the slot still returns the customer’s own appointment', async () => {
    const token = newManageToken();
    const first = await post(booking, token);
    const other = { ...booking, customer: { name: 'Other Client', phone: '4425550140' } };
    const clash = await post(other, newManageToken(), { ip: '198.51.100.30' });
    expect(clash.status).toBe(409);
    expect(clash.body.error.code).toBe('slot_taken');

    const retry = await post(booking, token);
    expect(retry.status).toBe(200);
    expect(retry.body.appointment).toEqual(first.body.appointment);
  });

  it('a retry returns the appointment as it is now, even cancelled by the shop and the time rebooked', async () => {
    const token = newManageToken();
    const first = await post(booking, token);
    const id = first.body.appointment.id;
    h.advance(5);
    await h.call('PATCH', `/api/owner/appointments/${id}`, { owner: true, body: { status: 'cancelled' } });
    const other = { ...booking, customer: { name: 'Other Client', phone: '4425550141' } };
    expect((await post(other, newManageToken(), { ip: '198.51.100.31' })).status).toBe(201);

    const retry = await post(booking, token);
    expect(retry.status).toBe(200);
    expect(retry.body.manageToken).toBe(token);
    expect(retry.body.appointment).toMatchObject({ id, status: 'cancelled', cancelledBy: 'shop' });
    expect(await count(`status = 'booked'`)).toBe(1);
  });

  it('retries never count as attempts against the IP limit, and still work once it is used up', async () => {
    const ip = '203.0.113.90';
    const token = newManageToken();
    expect((await post(booking, token, { ip })).status).toBe(201);
    for (let i = 0; i < 10; i++) expect((await post(booking, token, { ip })).status).toBe(200);
    expect(await attemptsCounted()).toBe(1);

    // Four more bookings fill the hour's five attempts; the sixth is turned down.
    for (let i = 1; i <= 4; i++) {
      const start = new Date(Date.UTC(2026, 10, 3, 18 + i)).toISOString().replace('.000Z', 'Z');
      const res = await post({ ...booking, start, customer: { ...customer, phone: `44255502${i}0` } }, newManageToken(), { ip });
      expect(res.status).toBe(201);
    }
    const sixth = await post({ ...booking, start: '2026-11-03T23:00:00Z', customer: { ...customer, phone: '4425550290' } }, newManageToken(), { ip });
    expect(sixth.status).toBe(429);

    const retry = await post(booking, token, { ip });
    expect(retry.status).toBe(200);
    expect(retry.body.manageToken).toBe(token);
  });

  it('a retry works for a number that already has its 3 upcoming appointments', async () => {
    const tokens = [newManageToken(), newManageToken(), newManageToken()];
    const starts = [TUE10, TUE11, '2026-11-03T20:00:00Z'];
    for (const [i, token] of tokens.entries()) {
      expect((await post({ ...booking, start: starts[i] }, token, { ip: `192.0.2.${i + 1}` })).status).toBe(201);
    }
    expect((await post({ ...booking, start: '2026-11-03T21:00:00Z' }, newManageToken(), { ip: '192.0.2.9' })).status).toBe(429);
    expect((await post({ ...booking, start: starts[2] }, tokens[2])).status).toBe(200);
  });

  it('two copies of one request at once make exactly one appointment', async () => {
    const token = newManageToken();
    const results = await Promise.all([post(booking, token), post(booking, token)]);
    expect(results.map((r) => r.status).sort()).toEqual([200, 201]);
    expect(results[0].body).toEqual(results[1].body);
    expect(results[0].body.manageToken).toBe(token);
    expect(await count()).toBe(1);
  });

  it('two copies of an any-barber request at once book one barber, not two', async () => {
    const token = newManageToken();
    const any = { serviceId: 'haircut', barberId: 'any', start: TUE10, customer };
    const results = await Promise.all([post(any, token), post(any, token)]);
    expect(results.map((r) => r.status).sort()).toEqual([200, 201]);
    expect(results[0].body.appointment).toEqual(results[1].body.appointment);
    expect(await count()).toBe(1);
  });

  it('ten copies at once (from different networks): one appointment, every answer the same', async () => {
    const token = newManageToken();
    const results = await Promise.all(
      Array.from({ length: 10 }, (_, i) => post(booking, token, { ip: `192.0.2.${100 + i}` })),
    );
    expect(results.filter((r) => r.status === 201)).toHaveLength(1);
    expect(results.filter((r) => r.status === 200)).toHaveLength(9);
    const ids = new Set(results.map((r) => r.body.appointment.id));
    expect(ids.size).toBe(1);
    expect(await count()).toBe(1);
  });

  it('a failed booking keeps nothing: the same token books once the time is free', async () => {
    const other = await post({ ...booking, customer: { name: 'First', phone: '4425550150' } }, undefined, { ip: '198.51.100.40' });
    expect(other.status).toBe(201);
    const token = newManageToken();
    expect((await post(booking, token)).status).toBe(409);
    await h.call('POST', `/api/appointments/${other.body.appointment.id}/cancel`, {
      headers: { 'x-manage-token': other.body.manageToken },
    });
    const retry = await post(booking, token);
    expect(retry.status).toBe(201);
    expect(retry.body.manageToken).toBe(token);
  });

  it('without the header the server makes the token, as before', async () => {
    const res = await post(booking, undefined);
    expect(res.status).toBe(201);
    expect(res.body.manageToken).toMatch(/^fixture-manage-token-0001/);
  });

  it("the shop's bookings ignore it", async () => {
    const res = await h.call('POST', '/api/owner/appointments', {
      owner: true,
      body: { offeringId: FLOW45, start: TUE10, customer: { name: 'Walk-in' } },
      headers: { 'x-manage-token': newManageToken() },
    });
    expect(res.status).toBe(201);
    expect(Object.keys(res.body)).toEqual(['appointment']);
    expect(await count('manage_token_hash IS NULL')).toBe(1);
  });

  it('the database itself allows one appointment per token hash, and any number without one', async () => {
    const insert = (id: string, start: string, end: string, hash: string | null) =>
      h.database.pool.query(
        `INSERT INTO appointments (id, offering_id, service_id, barber_id, service_name, barber_name, price_label, price_cents,
           price_kind, start_at, end_at, status, booked_by, customer_name, manage_token_hash, created_at, updated_at)
         VALUES ($1, 'x', 'haircut', 'flowxbori', 'Haircut', 'Flowxbori', '$35', 3500, 'fixed', $2, $3, 'booked',
           'customer', 'Client', $4, now(), now())`,
        [id, start, end, hash],
      );
    const hash = hashManageToken(newManageToken());
    await insert('20000000-0000-4000-8000-000000000001', '2026-11-03T18:00:00Z', '2026-11-03T18:45:00Z', hash);
    await expect(insert('20000000-0000-4000-8000-000000000002', '2026-11-03T20:00:00Z', '2026-11-03T20:45:00Z', hash)).rejects.toMatchObject({
      code: '23505',
      constraint: 'appointments_manage_token_hash_key',
    });
    await insert('20000000-0000-4000-8000-000000000003', '2026-11-03T21:00:00Z', '2026-11-03T21:45:00Z', null);
    await insert('20000000-0000-4000-8000-000000000004', '2026-11-03T22:00:00Z', '2026-11-03T22:45:00Z', null);
  });
});

// POST /api/owner/appointments with the owner app's Idempotency-Key: Book again
// after a lost answer gets the walk-in that went through instead of a second
// barber's chair, or slot_taken for the shop's own booking.

describe('Idempotency-Key on POST /api/owner/appointments', () => {
  const walkIn = { serviceId: 'haircut', barberId: 'any', start: TUE10, customer: { name: 'Walk-in Client' } };
  const KEY_USED = { code: 'invalid_request', message: 'That booking key was already used for another booking.' };

  function book(body: Record<string, unknown>, key: string | undefined) {
    return h.call('POST', '/api/owner/appointments', {
      owner: true,
      body,
      headers: key === undefined ? {} : { 'idempotency-key': key },
    });
  }

  it('without a key, the same walk-in sent twice takes two barbers’ chairs', async () => {
    const first = await book(walkIn, undefined);
    const second = await book(walkIn, undefined);
    expect([first.status, second.status]).toEqual([201, 201]);
    expect(second.body.appointment.barberId).not.toBe(first.body.appointment.barberId);
  });

  it('Book again after a lost answer gets 200 with the same appointment, and books nothing more', async () => {
    const key = newManageToken();
    const first = await book(walkIn, key);
    expect(first.status).toBe(201);
    expect(Object.keys(first.body)).toEqual(['appointment']);
    h.advance(1);
    const again = await book(walkIn, key);
    expect(again.status).toBe(200);
    expect(again.headers.get('cache-control')).toBe('no-store');
    expect(again.body).toEqual(first.body);
    expect(RESPONSES['owner-appointment-created'].safeParse(again.body).success).toBe(true);
    expect((await book(walkIn, key)).body).toEqual(first.body);
    expect(await count()).toBe(1);
    // Only the key's hash is stored, and it isn't a manage token.
    const { rows } = await h.database.pool.query('SELECT idempotency_key_hash, manage_token_hash FROM appointments');
    expect(rows).toEqual([{ idempotency_key_hash: hashManageToken(key), manage_token_hash: null }]);
    expect(JSON.stringify((await h.database.pool.query('SELECT * FROM appointments')).rows)).not.toContain(key);
  });

  it('a specific barber: Book again gets the appointment, not slot_taken for the shop’s own booking', async () => {
    const key = newManageToken();
    const phoneBooking = { offeringId: FLOW45, start: TUE11, customer: { name: 'Phone Client', phone: '(442) 555-0177' }, note: 'Beard too' };
    const first = await book(phoneBooking, key);
    expect(first.status).toBe(201);
    const again = await book(phoneBooking, key);
    expect(again.status).toBe(200);
    expect(again.body.appointment).toEqual(first.body.appointment);
    // A new key for that time is someone else's booking: the time is taken.
    expect((await book(phoneBooking, newManageToken())).body.error.code).toBe('slot_taken');
    expect(await count()).toBe(1);
  });

  it('matches on the target, the start to the minute, the name and the phone: the note, email and how the number is typed may differ', async () => {
    const key = newManageToken();
    const first = await book({ ...walkIn, customer: { name: 'Walk-in Client', phone: '4425550178' }, note: 'First' }, key);
    expect(first.status).toBe(201);
    const again = await book(
      {
        ...walkIn,
        start: '2026-11-03T10:00:42-08:00',
        customer: { name: '  Walk-in Client ', phone: '+1 (442) 555-0178', email: 'client@example.com' },
        note: 'Changed',
      },
      key,
    );
    expect(again.status).toBe(200);
    expect(again.body.appointment).toEqual(first.body.appointment);
    expect(again.body.appointment.note).toBe('First');
  });

  it('the same key for a different booking is a 400 and books nothing', async () => {
    const key = newManageToken();
    expect((await book(walkIn, key)).status).toBe(201);
    const different = [
      { ...walkIn, start: TUE11 },
      { ...walkIn, start: '2026-11-03T18:01:00Z' },
      { ...walkIn, serviceId: 'military-haircut' },
      { offeringId: FLOW45, start: TUE10, customer: walkIn.customer },
      { ...walkIn, customer: { name: 'Another Client' } },
      { ...walkIn, customer: { name: 'Walk-in Client', phone: '4425550179' } },
    ];
    for (const body of different) {
      const res = await book(body, key);
      expect(res.status, JSON.stringify(body)).toBe(400);
      expect(res.body.error).toEqual(KEY_USED);
    }
    expect(await count()).toBe(1);
  });

  it('a phone booking’s key isn’t the same booking without the phone', async () => {
    const key = newManageToken();
    const withPhone = { ...walkIn, customer: { name: 'Walk-in Client', phone: '4425550180' } };
    expect((await book(withPhone, key)).status).toBe(201);
    expect((await book(walkIn, key)).body.error).toEqual(KEY_USED);
    expect((await book({ ...walkIn, customer: { name: 'Walk-in Client', phone: '' } }, key)).body.error).toEqual(KEY_USED);
  });

  it('a malformed key is a 400 and books nothing', async () => {
    const canonical = newManageToken();
    for (const key of ['', '   ', 'short', canonical.slice(0, 42), `${canonical}A`, `${'A'.repeat(42)}B`, `${canonical.slice(0, 42)}=`]) {
      const res = await book(walkIn, key);
      expect(res.status, JSON.stringify(key)).toBe(400);
      expect(res.body.error).toEqual({ code: 'invalid_request', message: 'Idempotency-Key must be 32 random bytes in base64url (43 characters).' });
    }
    expect(await count()).toBe(0);
    // Surrounding spaces are fine, and the owner key still comes first.
    expect((await book(walkIn, ` ${canonical} `)).status).toBe(201);
    const unsigned = await h.call('POST', '/api/owner/appointments', { body: walkIn, headers: { 'idempotency-key': 'short' } });
    expect(unsigned.status).toBe(401);
  });

  it('Book again returns the appointment as it is now, even cancelled since, and works once the time has passed', async () => {
    const key = newManageToken();
    const first = await book(walkIn, key);
    const id = first.body.appointment.id;
    await h.call('PATCH', `/api/owner/appointments/${id}`, { owner: true, body: { status: 'cancelled' } });
    h.setNow('2026-11-04T17:00:00Z'); // the next day: a new booking for Tuesday would be turned down
    const again = await book(walkIn, key);
    expect(again.status).toBe(200);
    expect(again.body.appointment).toMatchObject({ id, status: 'cancelled', cancelledBy: 'shop' });
    expect((await book(walkIn, newManageToken())).body.error.code).toBe('too_soon');
    expect(await count()).toBe(1);
  });

  it('a failed booking keeps nothing: the same key books once the time is free', async () => {
    const taken = await book({ offeringId: FLOW45, start: TUE10, customer: { name: 'First Client' } }, undefined);
    const key = newManageToken();
    const walkInWithFlow = { offeringId: FLOW45, start: TUE10, customer: { name: 'Walk-in Client' } };
    expect((await book(walkInWithFlow, key)).status).toBe(409);
    await h.call('PATCH', `/api/owner/appointments/${taken.body.appointment.id}`, { owner: true, body: { status: 'cancelled' } });
    expect((await book(walkInWithFlow, key)).status).toBe(201);
    expect((await book(walkInWithFlow, key)).status).toBe(200);
  });

  it('two copies at once make one appointment, for any barber and for a specific one', async () => {
    const anyKey = newManageToken();
    const anyResults = await Promise.all([book(walkIn, anyKey), book(walkIn, anyKey)]);
    expect(anyResults.map((r) => r.status).sort()).toEqual([200, 201]);
    expect(anyResults[0].body).toEqual(anyResults[1].body);
    const oneKey = newManageToken();
    const one = { offeringId: CRISTIAN45, start: TUE11, customer: { name: 'Phone Client' } };
    const oneResults = await Promise.all([book(one, oneKey), book(one, oneKey), book(one, oneKey)]);
    expect(oneResults.map((r) => r.status).sort()).toEqual([200, 200, 201]);
    expect(new Set(oneResults.map((r) => r.body.appointment.id)).size).toBe(1);
    expect(await count()).toBe(2);
  });

  it('a customer’s manage token and a walk-in’s key never meet, even with the same value', async () => {
    const value = newManageToken();
    const online = await post(booking, value);
    expect(online.status).toBe(201);
    const shop = await book({ ...walkIn, start: TUE11 }, value);
    expect(shop.status).toBe(201);
    expect((await book({ ...walkIn, start: TUE11 }, value)).status).toBe(200);
    expect((await post(booking, value)).status).toBe(200);
    expect(await count()).toBe(2);
    // The customer endpoint doesn't take Idempotency-Key as a manage token.
    const res = await h.call('POST', '/api/appointments', {
      body: { ...booking, start: '2026-11-03T20:00:00Z', customer: { ...customer, phone: '4425550181' } },
      headers: { 'idempotency-key': newManageToken() },
    });
    expect(res.status).toBe(201);
    expect(res.body.manageToken).toMatch(/^fixture-manage-token-/);
  });

  it('the database itself allows one appointment per key hash, and any number without one', async () => {
    const insert = (id: string, start: string, end: string, hash: string | null) =>
      h.database.pool.query(
        `INSERT INTO appointments (id, offering_id, service_id, barber_id, service_name, barber_name, price_label, price_cents,
           price_kind, start_at, end_at, status, booked_by, customer_name, idempotency_key_hash, created_at, updated_at)
         VALUES ($1, 'x', 'haircut', 'flowxbori', 'Haircut', 'Flowxbori', '$35', 3500, 'fixed', $2, $3, 'booked',
           'shop', 'Client', $4, now(), now())`,
        [id, start, end, hash],
      );
    const hash = hashManageToken(newManageToken());
    await insert('30000000-0000-4000-8000-000000000001', '2026-11-03T18:00:00Z', '2026-11-03T18:45:00Z', hash);
    await expect(insert('30000000-0000-4000-8000-000000000002', '2026-11-03T20:00:00Z', '2026-11-03T20:45:00Z', hash)).rejects.toMatchObject({
      code: '23505',
      constraint: 'appointments_idempotency_key_hash_key',
    });
    await insert('30000000-0000-4000-8000-000000000003', '2026-11-03T21:00:00Z', '2026-11-03T21:45:00Z', null);
    await insert('30000000-0000-4000-8000-000000000004', '2026-11-03T22:00:00Z', '2026-11-03T22:45:00Z', null);
    await expect(insert('30000000-0000-4000-8000-000000000005', '2026-11-03T23:00:00Z', '2026-11-03T23:45:00Z', 'not-a-hash')).rejects.toMatchObject({
      code: '23514',
    });
  });
});
