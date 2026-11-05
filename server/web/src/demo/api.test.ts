import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import catalogFixture from '../../../test/fixtures/contract/catalog.json';
import { ApiError } from '../api/errors';
import type { Api } from '../api/http';
import type { Appointment, Catalog, Slot } from '../api/types';
import { clockMinutes, localDate, wallClock, weekdayOf } from '../lib/shopTime';
import { newToken } from '../lib/tokens';
import { fixtureAppointment, FLOW45 } from '../test/api';
import { createDemoApi, DEMO_CATALOG, DEMO_STORE_KEY, gridStarts, phoneCode, sampleBookings, type DemoBooking } from './api';

// The demo's stand-in for the shop's server: the shop's real catalog, open times from its
// hours, lead time, window and time zone, bookings and cancellations kept in this browser,
// and never a request on the network.

const LA = 'America/Los_Angeles';
/** Wednesday, November 4, 2026, 12:10 PM at the shop (Pacific Standard Time). */
const NOON_ISH = new Date('2026-11-04T20:10:00Z');

function demo(now: Date = NOON_ISH): Api {
  return createDemoApi({ now: () => now, latencyMs: 0 });
}

const iso = (date: Date) => date.toISOString();
const starts = (slots: Slot[]) => slots.map((s) => s.start);

async function failure(promise: Promise<unknown>): Promise<ApiError> {
  try {
    await promise;
  } catch (error) {
    if (error instanceof ApiError) return error;
    throw error;
  }
  throw new Error('It was expected to fail');
}

const client = { name: 'Demo Client', phone: '(760) 555-0123' };

/** An appointment as the demo answers it later: it never keeps the client's name, number, email or note. */
const later = (appointment: Appointment): Appointment => ({ ...appointment, customer: { name: '', phone: '', email: null }, note: null });

let fetchMock: ReturnType<typeof vi.fn>;
beforeEach(() => {
  // The demo never touches the network: any request would fail the test below.
  fetchMock = vi.fn(() => Promise.reject(new Error('The demo made a network request')));
  vi.stubGlobal('fetch', fetchMock);
});
afterEach(() => {
  expect(fetchMock).not.toHaveBeenCalled();
});

describe('the catalog', () => {
  it('is the shop’s real catalog, exactly what the server’s GET /api/catalog answers', async () => {
    // data/catalog.json lists none of the shop's accessibility features until the owner has
    // checked them (docs/legal/research.md §18, item 17), and neither does the contract fixture.
    expect(DEMO_CATALOG.shop.accessibility).toEqual([]);
    expect(await demo().catalog()).toEqual(catalogFixture);
    expect(DEMO_CATALOG.timeZone).toBe(LA);
  });
});

describe('open times, from the shop’s hours, lead time and window, on its clock', () => {
  it('starts every half hour from opening, ends by closing, and starts at least 30 minutes from now', () => {
    // 12:10 PM: 12:30 is too soon (less than 30 minutes away); 1 PM is the first, 6 PM the last a 45-minute cut can take.
    const today = gridStarts(DEMO_CATALOG, '2026-11-04', 45, NOON_ISH).map(iso);
    expect(today[0]).toBe('2026-11-04T21:00:00.000Z');
    expect(today.at(-1)).toBe('2026-11-05T02:00:00.000Z');
    expect(today).toHaveLength(11);
    // Tomorrow, 10 AM to 6 PM; on Sunday the shop closes at 6, so 5 PM is the last 45-minute start.
    expect(gridStarts(DEMO_CATALOG, '2026-11-05', 45, NOON_ISH).map(iso)).toHaveLength(17);
    expect(gridStarts(DEMO_CATALOG, '2026-11-08', 45, NOON_ISH).map(iso).at(-1)).toBe('2026-11-09T01:00:00.000Z');
  });

  it('opens bookings from today through 60 days ahead, never before', () => {
    expect(gridStarts(DEMO_CATALOG, '2026-11-03', 45, NOON_ISH)).toEqual([]);
    expect(gridStarts(DEMO_CATALOG, '2027-01-03', 45, NOON_ISH)).not.toEqual([]);
    expect(gridStarts(DEMO_CATALOG, '2027-01-04', 45, NOON_ISH)).toEqual([]);
  });

  it('follows daylight saving time: 10 AM is 17:00 UTC in summer time, 18:00 in winter', () => {
    const fallBack = new Date('2026-10-25T17:00:00Z');
    expect(iso(gridStarts(DEMO_CATALOG, '2026-10-31', 30, fallBack)[0]!)).toBe('2026-10-31T17:00:00.000Z');
    expect(iso(gridStarts(DEMO_CATALOG, '2026-11-01', 30, fallBack)[0]!)).toBe('2026-11-01T18:00:00.000Z');
    const springForward = new Date('2026-03-01T18:00:00Z');
    expect(iso(gridStarts(DEMO_CATALOG, '2026-03-07', 30, springForward)[0]!)).toBe('2026-03-07T18:00:00.000Z');
    expect(iso(gridStarts(DEMO_CATALOG, '2026-03-08', 30, springForward)[0]!)).toBe('2026-03-08T17:00:00.000Z');
  });

  it('lists every day asked for, each open time on the grid, inside the hours and past the lead time', async () => {
    const { timeZone, days } = await demo().availability({ offeringId: FLOW45 }, '2026-11-03', 14);
    expect(timeZone).toBe(LA);
    expect(days.map((d) => d.date)).toEqual(Array.from({ length: 14 }, (_, i) => `2026-11-${String(3 + i).padStart(2, '0')}`));
    expect(days[0]!.slots).toEqual([]); // yesterday
    for (const { date, slots } of days.slice(1)) {
      expect(slots.length, date).toBeGreaterThan(0);
      const hours = DEMO_CATALOG.hours[String(weekdayOf(date))]!;
      for (const slot of slots) {
        const start = new Date(slot.start);
        const clock = wallClock(start, LA);
        const minutes = clock.hour * 60 + clock.minute;
        expect(clock.date, slot.start).toBe(date);
        expect((minutes - clockMinutes(hours.opens)) % 30, slot.start).toBe(0);
        expect(minutes, slot.start).toBeGreaterThanOrEqual(clockMinutes(hours.opens));
        expect(minutes + 45, slot.start).toBeLessThanOrEqual(clockMinutes(hours.closes));
        expect(start.getTime() - NOON_ISH.getTime(), slot.start).toBeGreaterThanOrEqual(30 * 60_000);
        expect(slot.barberIds).toEqual(['flowxbori']);
      }
    }
  });

  it('has a few times already taken by sample bookings each day, the same every time', async () => {
    const api = demo();
    const { days } = await api.availability({ offeringId: FLOW45 }, '2026-11-05', 7);
    for (const { date, slots } of days) {
      const grid = gridStarts(DEMO_CATALOG, date, 45, NOON_ISH).map(iso).map((s) => s.replace('.000Z', 'Z'));
      const samples = sampleBookings(DEMO_CATALOG, date).filter((b) => b.barberId === 'flowxbori');
      expect(samples.length, date).toBeGreaterThanOrEqual(2);
      expect(samples.length, date).toBeLessThanOrEqual(3);
      // Each start that isn't offered overlaps one of Flowxbori's sample bookings, and only those.
      const taken = grid.filter((s) => !starts(slots).includes(s));
      expect(taken.length, date).toBeGreaterThan(0);
      for (const start of grid) {
        const begins = Date.parse(start);
        const overlaps = samples.some((b) => b.start < begins + 45 * 60_000 && b.end > begins);
        expect(taken.includes(start), `${date} ${start}`).toBe(overlaps);
      }
    }
    expect(await api.availability({ offeringId: FLOW45 }, '2026-11-05', 7)).toEqual({ timeZone: LA, days });
  });

  it('offers "Any barber" times with every barber free then, in team order', async () => {
    const { days } = await demo().availability({ serviceId: 'haircut', barberId: 'any' }, '2026-11-05', 1);
    const team = DEMO_CATALOG.barbers.map((b) => b.id);
    const sharing = DEMO_CATALOG.firstAvailable.find((f) => f.serviceId === 'haircut')!.offeringIds.map((id) => id.split('/')[0]);
    expect(days[0]!.slots.length).toBeGreaterThan(0);
    for (const slot of days[0]!.slots) {
      expect(slot.barberIds.length).toBeGreaterThan(0);
      expect(slot.barberIds.every((id) => sharing.includes(id))).toBe(true);
      expect([...slot.barberIds].sort((a, b) => team.indexOf(a) - team.indexOf(b))).toEqual(slot.barberIds);
    }
  });

  it('turns down what the server turns down, in its words', async () => {
    const api = demo();
    expect(await failure(api.availability({ offeringId: 'nobody/nothing' }, '2026-11-05', 1))).toMatchObject({
      code: 'invalid_request',
      message: "That service isn't on the menu any more. Pick another.",
    });
    expect((await failure(api.availability({ offeringId: FLOW45 }, '2026-11-05', 32))).message).toBe('days must be a whole number from 1 to 31.');
    expect((await failure(api.availability({ serviceId: 'perm', barberId: 'any' }, '2026-11-05', 1))).message).toBe(
      'This service needs a specific barber. Pick one to see their times.',
    );
  });

  it('keeps a day the shop is closed empty', async () => {
    const { '1': _sunday, ...weekdays } = DEMO_CATALOG.hours;
    const closedSundays: Catalog = { ...DEMO_CATALOG, hours: weekdays };
    const api = createDemoApi({ now: () => NOON_ISH, latencyMs: 0, catalog: closedSundays });
    const { days } = await api.availability({ offeringId: FLOW45 }, '2026-11-07', 2);
    expect(days.map((d) => [d.date, d.slots.length > 0])).toEqual([
      ['2026-11-07', true],
      ['2026-11-08', false],
    ]);
  });
});

describe('booking and cancelling', () => {
  async function firstSlot(api: Api, date = '2026-11-05'): Promise<Slot> {
    const { days } = await api.availability({ offeringId: FLOW45 }, date, 1);
    return days[0]!.slots[0]!;
  }

  it('books a free time, which then isn’t offered, and cancelling gives it back', async () => {
    const api = demo();
    const slot = await firstSlot(api);
    const token = newToken();
    const { appointment, manageToken } = await api.book({ target: { offeringId: FLOW45 }, start: slot.start, customer: client }, token);
    expect(manageToken).toBe(token);
    expect(appointment).toMatchObject({
      offeringId: FLOW45,
      serviceId: 'haircut',
      serviceName: 'Haircut',
      barberId: 'flowxbori',
      barberName: 'Flowxbori',
      start: slot.start,
      end: new Date(Date.parse(slot.start) + 45 * 60_000).toISOString().replace('.000Z', 'Z'),
      durationMinutes: 45,
      priceLabel: '$35',
      status: 'booked',
      cancelledBy: null,
      payment: { status: 'unpaid', amountCents: null, paidAt: null },
      customer: { name: 'Demo Client', phone: '+17605550123', email: null },
      note: null,
      createdAt: '2026-11-04T20:10:00Z',
      card: null,
      noShowFee: null,
    });
    expect(appointment.id).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
    expect(await firstSlot(api)).not.toEqual(slot);
    expect(await api.appointment(appointment.id, token)).toEqual(later(appointment));

    const cancelled = await api.cancel(appointment.id, token);
    expect(cancelled).toMatchObject({ id: appointment.id, status: 'cancelled', cancelledBy: 'customer' });
    expect(await firstSlot(api)).toEqual(slot);
    expect(await failure(api.cancel(appointment.id, token))).toMatchObject({
      code: 'not_cancellable',
      message: 'This appointment is already cancelled.',
    });
  });

  it('books "Any barber" with a barber free then, and remembers it was any barber for a retry', async () => {
    const api = demo();
    const { days } = await api.availability({ serviceId: 'haircut', barberId: 'any' }, '2026-11-05', 1);
    const slot = days[0]!.slots.find((s) => s.barberIds.length > 1) ?? days[0]!.slots[0]!;
    const token = newToken();
    const booking = { target: { serviceId: 'haircut', barberId: 'any' as const }, start: slot.start, customer: client };
    const { appointment } = await api.book(booking, token);
    expect(slot.barberIds).toContain(appointment.barberId);
    expect((await api.book(booking, token)).appointment).toEqual(later(appointment));
    // The same token for the barber's own item isn't the same booking.
    expect((await failure(api.book({ ...booking, target: { offeringId: appointment.offeringId } }, token))).message).toBe(
      'That booking token was already used.',
    );
  });

  it('answers a retry with the same token with the same appointment, as it is now', async () => {
    const api = demo();
    const slot = await firstSlot(api);
    const token = newToken();
    const booking = { target: { offeringId: FLOW45 }, start: slot.start, customer: client };
    const first = await api.book(booking, token);
    expect(await api.book({ ...booking, customer: { ...client, name: 'Another name' } }, token)).toEqual({ ...first, appointment: later(first.appointment) });
    // Another number with the same token isn't the same booking.
    expect((await failure(api.book({ ...booking, customer: { ...client, phone: '(760) 555-0199' } }, token))).message).toBe(
      'That booking token was already used.',
    );
    await api.cancel(first.appointment.id, token);
    expect((await api.book(booking, token)).appointment.status).toBe('cancelled');
  });

  it('says a time is taken when someone has it, and why other times can’t be booked', async () => {
    const api = demo();
    const slot = await firstSlot(api);
    await api.book({ target: { offeringId: FLOW45 }, start: slot.start, customer: client }, newToken());
    const again = (start: string) => api.book({ target: { offeringId: FLOW45 }, start, customer: { ...client, phone: '(760) 555-0199' } }, newToken());
    expect(await failure(again(slot.start))).toMatchObject({ code: 'slot_taken', status: 409 });
    expect(await failure(again('2026-11-04T20:00:00Z'))).toMatchObject({ code: 'too_soon', message: 'That time has already passed. Pick another.' });
    expect(await failure(again('2026-11-04T20:30:00Z'))).toMatchObject({
      code: 'too_soon',
      message: "That's too soon. Pick a time at least 30 minutes from now.",
    });
    expect(await failure(again('2026-11-05T18:10:00Z'))).toMatchObject({ code: 'outside_hours' });
    expect(await failure(again('2027-01-05T18:00:00Z'))).toMatchObject({
      code: 'too_far',
      message: 'We take bookings up to 60 days ahead. Pick an earlier day.',
    });
  });

  it('checks the details like the server, and keeps a number to 3 upcoming appointments', async () => {
    const api = demo();
    const book = (customer: { name: string; phone: string; email?: string }, start: string, token = newToken()) =>
      api.book({ target: { offeringId: FLOW45 }, start, customer }, token);
    // One time on each of four days, so no two of them overlap.
    const { days } = await api.availability({ offeringId: FLOW45 }, '2026-11-05', 4);
    const [a, b, c, d] = days.map((day) => day.slots[0]!.start);
    expect((await failure(book({ name: '  ', phone: client.phone }, a!))).message).toBe('Enter your name.');
    expect((await failure(book({ name: 'X', phone: '555-0123' }, a!))).message).toBe('Enter a US mobile number, like (442) 341-3053.');
    expect((await failure(book({ ...client, email: 'not an email' }, a!))).message).toBe('Enter a valid email address.');
    expect((await failure(api.book({ target: { offeringId: FLOW45 }, start: a!, customer: client }, 'not-a-token'))).code).toBe('invalid_request');
    await book(client, a!);
    await book(client, b!);
    await book(client, c!);
    expect(await failure(book(client, d!))).toMatchObject({
      code: 'rate_limited',
      status: 429,
      message: 'This number already has 3 upcoming appointments. Cancel one, or call the shop to book more.',
    });
  });

  it('finds an appointment only with its own token, and can’t cancel one that has started', async () => {
    const api = demo();
    const slot = await firstSlot(api, '2026-11-04');
    const token = newToken();
    const { appointment } = await api.book({ target: { offeringId: FLOW45 }, start: slot.start, customer: client }, token);
    expect(await failure(api.appointment(appointment.id, newToken()))).toMatchObject({ code: 'not_found', status: 404 });
    const later = createDemoApi({ now: () => new Date(Date.parse(slot.start) + 60_000), latencyMs: 0 });
    expect(await failure(later.cancel(appointment.id, token))).toMatchObject({
      code: 'not_cancellable',
      message: 'This appointment has already started. Call the shop if you need help.',
    });
  });

  it('asks first inside the late-cancellation window of a booking with a card on file', async () => {
    const token = newToken();
    const start = new Date(NOON_ISH.getTime() + 40 * 60_000);
    const held: DemoBooking = {
      manageToken: token,
      anyBarber: false,
      phoneCode: phoneCode('+17605550123'),
      appointment: {
        ...fixtureAppointment,
        id: '00000000-0000-4000-8000-0000000000aa',
        start: start.toISOString(),
        end: new Date(start.getTime() + 45 * 60_000).toISOString(),
        status: 'booked',
      } satisfies Appointment,
    };
    localStorage.setItem(DEMO_STORE_KEY, JSON.stringify({ version: 2, bookings: [held] }));
    const api = demo();
    expect(await failure(api.cancel(held.appointment.id, token))).toMatchObject({
      code: 'late_cancel_fee',
      status: 409,
      message: 'Cancelling now, less than 1 hour before your appointment, may be charged $35, the full service price.',
    });
    expect((await api.appointment(held.appointment.id, token)).status).toBe('booked');
    const cancelled = await api.cancel(held.appointment.id, token, true);
    expect(cancelled.status).toBe('cancelled');
    expect(cancelled.noShowFee).toMatchObject({ customerCancelledAt: '2026-11-04T20:10:00Z', reason: 'lateCancel' });
  });
});

describe('what the browser keeps', () => {
  it('keeps bookings and cancellations after the page reloads', async () => {
    const first = demo();
    const { days } = await first.availability({ offeringId: FLOW45 }, '2026-11-06', 1);
    const slot = days[0]!.slots[0]!;
    const token = newToken();
    const { appointment } = await first.book({ target: { offeringId: FLOW45 }, start: slot.start, customer: client }, token);

    // A new page: a new stand-in, the same browser storage.
    const reloaded = demo();
    expect(await reloaded.appointment(appointment.id, token)).toEqual(later(appointment));
    const after = await reloaded.availability({ offeringId: FLOW45 }, '2026-11-06', 1);
    expect(starts(after.days[0]!.slots)).not.toContain(slot.start);
    await reloaded.cancel(appointment.id, token);
    expect((await demo().appointment(appointment.id, token)).status).toBe('cancelled');
    expect(JSON.parse(localStorage.getItem(DEMO_STORE_KEY)!)).toMatchObject({ version: 2, bookings: [{ manageToken: token }] });
  });

  it('keeps no name, number, email or note: only a scrambled code of the number, for the 3-per-number rule', async () => {
    const api = demo();
    const { days } = await api.availability({ offeringId: FLOW45 }, '2026-11-06', 1);
    const customer = { name: 'Private Person', phone: '(760) 555-8271', email: 'private.person@example.com' };
    const { appointment } = await api.book({ target: { offeringId: FLOW45 }, start: days[0]!.slots[0]!.start, customer, note: 'gate code 4321' }, newToken());
    // The answer to the booking itself has them, as the shop's would.
    expect(appointment).toMatchObject({ customer: { name: 'Private Person', phone: '+17605558271', email: 'private.person@example.com' }, note: 'gate code 4321' });

    const kept = localStorage.getItem(DEMO_STORE_KEY)!;
    for (const detail of ['Private Person', '7605558271', '555-8271', 'private.person', 'gate code']) expect(kept, detail).not.toContain(detail);
    const [booking] = (JSON.parse(kept) as { bookings: Record<string, unknown>[] }).bookings;
    expect(booking!.phoneCode).toBe(phoneCode('+17605558271'));
    expect(booking!.appointment).not.toHaveProperty('customer');
    expect(booking!.appointment).not.toHaveProperty('note');
  });

  it('forgets every booking made in it when asked (Forget me on My appointments)', async () => {
    const api = demo();
    const { days } = await api.availability({ offeringId: FLOW45 }, '2026-11-06', 1);
    const token = newToken();
    const { appointment } = await api.book({ target: { offeringId: FLOW45 }, start: days[0]!.slots[0]!.start, customer: client }, token);
    api.forgetHere();
    expect(localStorage.getItem(DEMO_STORE_KEY)).toBeNull();
    expect(await failure(demo().appointment(appointment.id, token))).toMatchObject({ code: 'not_found' });
    expect(await failure(api.appointment(appointment.id, token))).toMatchObject({ code: 'not_found' });
  });

  it('drops what an earlier demo kept with the client’s details (version 1)', async () => {
    const old = { version: 1, bookings: [{ manageToken: newToken(), anyBarber: false, appointment: { ...fixtureAppointment } }] };
    localStorage.setItem(DEMO_STORE_KEY, JSON.stringify(old));
    const api = demo();
    expect(await failure(api.appointment(fixtureAppointment.id, old.bookings[0]!.manageToken))).toMatchObject({ code: 'not_found' });
    const { days } = await api.availability({ offeringId: FLOW45 }, '2026-11-06', 1);
    await api.book({ target: { offeringId: FLOW45 }, start: days[0]!.slots[0]!.start, customer: client }, newToken());
    const kept = JSON.parse(localStorage.getItem(DEMO_STORE_KEY)!) as { version: number; bookings: unknown[] };
    expect(kept.version).toBe(2);
    expect(kept.bookings).toHaveLength(1);
    expect(JSON.stringify(kept)).not.toContain(fixtureAppointment.customer.name);
  });

  it('still works for this visit where the browser keeps no site data', async () => {
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new DOMException('The quota has been exceeded.', 'QuotaExceededError');
    });
    const api = demo();
    const { days } = await api.availability({ offeringId: FLOW45 }, '2026-11-05', 1);
    const token = newToken();
    const { appointment } = await api.book({ target: { offeringId: FLOW45 }, start: days[0]!.slots[0]!.start, customer: client }, token);
    expect((await api.cancel(appointment.id, token)).status).toBe('cancelled');
  });

  it('forgets bookings that ended more than 60 days ago', async () => {
    const api = demo(new Date('2026-11-05T19:00:00Z'));
    const { days } = await api.availability({ offeringId: FLOW45 }, '2026-11-05', 1);
    const token = newToken();
    const { appointment } = await api.book({ target: { offeringId: FLOW45 }, start: days[0]!.slots[0]!.start, customer: client }, token);
    expect(await failure(demo(new Date('2027-01-20T19:00:00Z')).appointment(appointment.id, token))).toMatchObject({ code: 'not_found' });
  });
});

describe('no card, no Stripe, and sample reviews', () => {
  it('never needs a card: no-show protection is off, as the shop’s server starts', async () => {
    const api = demo();
    expect(await api.noShowPolicy({ offeringId: FLOW45 })).toEqual({
      required: false,
      minFeeCents: null,
      maxFeeCents: null,
      policyText: null,
      lateCancelWindowMinutes: null,
      warning: null,
    });
    expect(await failure(api.startCardCheckout({ offeringId: FLOW45 }, newToken()))).toMatchObject({
      code: 'invalid_request',
      message: "This booking doesn't need a card. Go ahead and book.",
    });
    expect((await failure(api.saveCard('cs_test_demo', newToken()))).code).toBe('not_found');
  });

  it('shows sample reviews that say they’re samples, and no made-up rating', async () => {
    const { google, yelp } = await demo().reviews();
    expect(google.available).toBe(true);
    expect(google.rating).toBeNull();
    expect(google.count).toBeNull();
    expect(google.url).toBe(DEMO_CATALOG.shop.googleMapsUrl);
    expect(google.reviews.map((r) => r.author)).toEqual(['Sample reviewer A', 'Sample reviewer B']);
    expect(google.reviews.every((r) => r.url === null && r.authorUrl === null && /sample/i.test(r.text))).toBe(true);
    expect(yelp.available).toBe(false);
  });

  it('stops when the page no longer wants the answer', async () => {
    const api = createDemoApi({ now: () => NOON_ISH, latencyMs: 50 });
    const controller = new AbortController();
    const pending = api.catalog(controller.signal);
    controller.abort();
    await expect(pending).rejects.toMatchObject({ name: 'AbortError' });
  });
});

describe('the shop’s day', () => {
  it('is the shop’s, whatever the visitor’s computer says', () => {
    // Late Wednesday evening at the shop is already Thursday in UTC.
    expect(localDate(new Date('2026-11-05T06:30:00Z'), LA)).toBe('2026-11-04');
  });
});
