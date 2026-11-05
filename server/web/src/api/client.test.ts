import { describe, expect, it } from 'vitest';
import cardDeleted from '../../../test/fixtures/contract/card-deletion.json';
import cardScheduled from '../../../test/fixtures/contract/card-deletion-scheduled.json';
import { apiError, FLOW45, mockApi } from '../test/api';
import { api, ApiError, defaultMessage, errorFromResponse, OFFLINE_MESSAGE } from './client';
import { CARD_DELETED_MESSAGE, CARD_SCHEDULED_MESSAGE, cardDeletionOf } from './http';

const TOKEN = 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE';

describe('the API client', () => {
  it('sends JSON as application/json, with the headers it was given', async () => {
    const mock = mockApi([['POST /api/cards', { status: 201, body: { card: { brand: 'visa', last4: '4242', expMonth: 12, expYear: 2030 } } }]]);
    const card = await api.saveCard('cs_test_Fixture000002', TOKEN);
    expect(card).toEqual({ brand: 'visa', last4: '4242', expMonth: 12, expYear: 2030 });
    expect(mock.calls[0]).toMatchObject({
      method: 'POST',
      path: '/api/cards',
      headers: { 'content-type': 'application/json', 'x-card-token': TOKEN, accept: 'application/json' },
      body: { sessionId: 'cs_test_Fixture000002' },
    });
  });

  it("turns the contract's error envelope into an ApiError with the server's words", async () => {
    mockApi([['GET /api/appointments/*', apiError('not_found', "We couldn't find that appointment.", 404)]]);
    const error = await api.appointment('00000000-0000-4000-8000-000000000005', TOKEN).catch((e: unknown) => e);
    expect(error).toBeInstanceOf(ApiError);
    expect(error).toMatchObject({ code: 'not_found', status: 404, message: "We couldn't find that appointment." });
  });

  it('gives a friendly sentence when the answer has no envelope (a proxy error page)', async () => {
    const error = await errorFromResponse(new Response('<html>Bad gateway</html>', { status: 502 }));
    expect(error).toMatchObject({ code: 'server_error', status: 502, message: 'Something went wrong on our side. Try again in a moment, or call the shop.' });
    const empty = await errorFromResponse(new Response(JSON.stringify({ error: { code: 'rate_limited' } }), { status: 429 }));
    expect(empty.message).toBe("That's a lot of tries in a short time. Wait a little and try again, or call the shop.");
    expect((await errorFromResponse(new Response('', { status: 404 }))).code).toBe('not_found');
  });

  it('says the shop could not be reached when the request never got an answer', async () => {
    mockApi([['GET /api/catalog', 'offline']]);
    const error = await api.catalog().catch((e: unknown) => e);
    expect(error).toMatchObject({ code: 'offline', status: 0, message: OFFLINE_MESSAGE });
    expect((error as ApiError).isOffline).toBe(true);
  });

  it('has a plain sentence for every code the site handles', () => {
    expect(defaultMessage('slot_taken', 409)).toBe('Someone just booked that time. Pick another one.');
    expect(defaultMessage('card_required', 400)).toBe("Add a card to book this time. You won't be charged now.");
    expect(defaultMessage('policy_changed', 409)).toBe('The no-show policy for this booking just changed. Check it and book again.');
    expect(defaultMessage('something_new', 500)).toBe('Something went wrong on our side. Try again in a moment, or call the shop.');
  });

  it('books with the manage token, and tries once more with the same token when the answer is lost', async () => {
    const mock = mockApi([['POST /api/appointments', { status: 201, body: { appointment: { id: 'a1' }, manageToken: TOKEN } }]]);
    mock.once('POST /api/appointments', 'offline');
    const booking = { target: { offeringId: FLOW45 }, start: '2026-11-03T18:00:00Z', customer: { name: 'Ana', phone: '+14425550123' } };
    const confirmation = await api.book(booking, TOKEN);
    expect(confirmation.manageToken).toBe(TOKEN);
    expect(mock.calls).toHaveLength(2);
    expect(mock.calls.map((c) => c.headers['x-manage-token'])).toEqual([TOKEN, TOKEN]);
    expect(mock.calls[1]!.body).toEqual({ offeringId: FLOW45, start: '2026-11-03T18:00:00Z', customer: { name: 'Ana', phone: '+14425550123' } });
  });

  it('tries only once more, and never after an answer', async () => {
    const offline = mockApi([['POST /api/appointments', 'offline']]);
    const booking = { target: { serviceId: 'haircut', barberId: 'any' as const }, start: '2026-11-03T18:00:00Z', customer: { name: 'Ana', phone: '+14425550123' } };
    await expect(api.book(booking, TOKEN)).rejects.toMatchObject({ code: 'offline' });
    expect(offline.calls).toHaveLength(2);
    expect(offline.calls[0]!.body).toMatchObject({ serviceId: 'haircut', barberId: 'any' });

    const taken = mockApi([['POST /api/appointments', apiError('slot_taken', 'Someone just booked that time. Pick another.', 409)]]);
    await expect(api.book(booking, TOKEN)).rejects.toMatchObject({ code: 'slot_taken' });
    expect(taken.calls).toHaveLength(1);
  });

  it('sends the card token and the policy the client agreed to with a protected booking', async () => {
    const mock = mockApi([['POST /api/appointments', { status: 201, body: { appointment: {}, manageToken: TOKEN } }]]);
    await api.book(
      { target: { offeringId: FLOW45 }, start: '2026-11-03T18:00:00Z', customer: { name: 'Ana', phone: '+14425550123', email: 'ana@example.com' }, note: 'Fade', noShowPolicy: 'The policy.' },
      TOKEN,
      'BgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgY',
    );
    expect(mock.calls[0]!.headers['x-card-token']).toBe('BgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgY');
    expect(mock.calls[0]!.body).toMatchObject({ note: 'Fade', noShowPolicy: 'The policy.', customer: { email: 'ana@example.com' } });
  });

  it('asks the shop to delete a saved card with its token, and reads what the shop did', async () => {
    const mock = mockApi([['DELETE /api/cards', { body: cardScheduled }]]);
    expect(await api.deleteCard(TOKEN)).toEqual(cardScheduled.cardDeletion);
    expect(mock.calls[0]).toMatchObject({ method: 'DELETE', path: '/api/cards', headers: { 'x-card-token': TOKEN }, body: undefined, keepalive: false });
    mock.once('DELETE /api/cards', { body: cardDeleted });
    expect(await api.deleteCard(TOKEN, { keepalive: true })).toEqual(cardDeleted.cardDeletion);
    expect(mock.calls[1]).toMatchObject({ method: 'DELETE', keepalive: true });
  });

  it('reads an answer it doesn’t know as scheduled, never as deleted, in the server’s words', () => {
    expect(CARD_DELETED_MESSAGE).toBe(cardDeleted.cardDeletion.message);
    expect(CARD_SCHEDULED_MESSAGE).toBe(cardScheduled.cardDeletion.message);
    expect(cardDeletionOf({ cardDeletion: { status: 'later', message: 'Soon.' } })).toEqual({ status: 'scheduled', message: 'Soon.' });
    expect(cardDeletionOf({ cardDeletion: { status: 'deleted' } })).toEqual(cardDeleted.cardDeletion);
    expect(cardDeletionOf({})).toEqual(cardScheduled.cardDeletion);
  });

  it('starts Stripe’s card page coming back to the website', async () => {
    const mock = mockApi([['POST /api/cards/checkout', { status: 201, body: { url: 'https://checkout.stripe.com/c/pay/cs_test_x', sessionId: 'cs_test_x' } }]]);
    await api.startCardCheckout({ serviceId: 'haircut', barberId: 'any' }, TOKEN);
    expect(mock.calls[0]).toMatchObject({
      headers: { 'x-card-token': TOKEN },
      body: { serviceId: 'haircut', barberId: 'any', returnTo: 'web' },
    });
  });

  it('cancels without a body, or accepting the late-cancellation fee once the client was told', async () => {
    const mock = mockApi([['POST /api/appointments/*', { body: { appointment: { id: 'a1', status: 'cancelled' } } }]]);
    await api.cancel('a1', TOKEN);
    await api.cancel('a1', TOKEN, true);
    expect(mock.calls[0]).toMatchObject({ path: '/api/appointments/a1/cancel', body: undefined });
    expect(mock.calls[0]!.headers['content-type']).toBeUndefined();
    expect(mock.calls[1]).toMatchObject({ body: { acceptLateCancelFee: true }, headers: { 'content-type': 'application/json' } });
  });

  it('asks for availability and the policy by the booking target', async () => {
    const mock = mockApi([
      ['GET /api/availability', { body: { timeZone: 'America/Los_Angeles', days: [] } }],
      ['GET /api/no-show-policy', { body: { required: false } }],
    ]);
    await api.availability({ serviceId: 'haircut', barberId: 'any' }, '2026-11-03', 14);
    await api.noShowPolicy({ offeringId: FLOW45 });
    expect(mock.calls[0]!.search).toBe('?serviceId=haircut&barberId=any&from=2026-11-03&days=14');
    expect(mock.calls[1]!.search).toBe(`?offeringId=${encodeURIComponent(FLOW45)}`);
  });
});
