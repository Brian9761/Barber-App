import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import created from '../../../test/fixtures/contract/appointment-created.json';
import cardCheckout from '../../../test/fixtures/contract/card-checkout.json';
import cardSaved from '../../../test/fixtures/contract/card-saved.json';
import cardRequired from '../../../test/fixtures/contract/errors/card_required.json';
import policyChanged from '../../../test/fixtures/contract/errors/policy_changed.json';
import rateLimited from '../../../test/fixtures/contract/errors/rate_limited.json';
import slotTaken from '../../../test/fixtures/contract/errors/slot_taken.json';
import { leaveTo } from '../lib/leave';
import { CARD_KEY, loadAppointments, loadCard, loadPendingCheckout, savePendingCheckout, storeCard } from '../lib/storage';
import { isToken, newToken } from '../lib/tokens';
import { apiError, availability, FLOW45, mockApi, policy35, policyNotRequired, renderApp, type ApiCall } from '../test/api';
import { EMPTY_DRAFT, loadDraft, saveDraft, type BookingDraft } from './flow';

// Stripe's card page is another site: the test only sees where the page would go.
vi.mock('../lib/leave', () => ({ leaveTo: vi.fn() }));

const START = '2026-11-03T18:00:00Z'; // Tuesday 10 AM in the shop
const details = { name: 'Ana Flores', phone: '(442) 555-0123', email: '', note: '', remember: false };

/** A booking taken to Review with Flowxbori's $35 haircut, as this tab kept it. */
function keptBooking(changes: Partial<BookingDraft> = {}) {
  saveDraft({ ...EMPTY_DRAFT, serviceId: 'haircut', choice: { kind: 'offering', offeringId: FLOW45 }, start: START, details, ...changes });
}

const button = (name: string | RegExp) => screen.getByRole('button', { name }) as HTMLButtonElement;
const bookButton = () => screen.getByTestId('book-button') as HTMLButtonElement;
const postsTo = (calls: ApiCall[], path: string) => calls.filter((c) => c.method === 'POST' && c.path === path);

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(new Date('2026-11-03T16:00:00Z')); // 8 AM, two hours before
});

afterEach(() => {
  vi.useRealTimers();
});

describe('a card on file, on Stripe’s page', () => {
  it('is asked for before booking when the shop needs one, and opens Stripe’s page coming back to the website', async () => {
    const api = mockApi([
      ['GET /api/no-show-policy', { body: policy35 }],
      ['POST /api/cards/checkout', { body: cardCheckout }],
    ]);
    keptBooking();
    renderApp('/book/review');

    const section = await screen.findByTestId('card-section');
    expect(section.textContent).toContain('This time needs a card on file to hold it. Nothing is charged now.');
    expect(section.textContent).toContain(policy35.policyText);
    expect(bookButton().disabled).toBe(true);
    expect(screen.getByText('Add a card first to book this time.')).toBeTruthy();

    await userEvent.click(within(section).getByRole('button', { name: 'Add a card' }));
    await waitFor(() => expect(leaveTo).toHaveBeenCalledWith(cardCheckout.url));

    const [checkout] = postsTo(api.calls, '/api/cards/checkout');
    expect(checkout!.body).toEqual({ offeringId: FLOW45, returnTo: 'web' });
    const token = checkout!.headers['x-card-token']!;
    expect(isToken(token)).toBe(true);
    // Kept in this tab for the way back: the card token, and the booking itself.
    expect(loadPendingCheckout()).toEqual({ token, remember: false, sessionId: cardCheckout.sessionId });
    expect(loadDraft()).toMatchObject({ start: START, choice: { kind: 'offering', offeringId: FLOW45 } });
  });

  it('is kept when Stripe sends the client back, and the booking goes with it', async () => {
    const token = newToken();
    keptBooking();
    savePendingCheckout({ token, remember: false, sessionId: cardCheckout.sessionId });
    const api = mockApi([
      ['POST /api/cards', { body: cardSaved }],
      ['GET /api/no-show-policy', { body: policy35 }],
      ['POST /api/appointments', { status: 201, body: created }],
    ]);
    renderApp(`/book/card-return?status=saved&session_id=${cardCheckout.sessionId}`);

    // Back at Review, with the card.
    expect((await screen.findByTestId('card-label')).textContent).toContain('Visa •••• 4242');
    const [save] = postsTo(api.calls, '/api/cards');
    expect(save!.body).toEqual({ sessionId: cardCheckout.sessionId });
    expect(save!.headers['x-card-token']).toBe(token);
    expect(loadPendingCheckout()).toBeNull();
    // Not "remember me": kept until this tab closes, not on the computer.
    expect(localStorage.getItem(CARD_KEY)).toBeNull();
    expect(loadCard()).toEqual({ token, card: cardSaved.card });

    await waitFor(() => expect(bookButton().disabled).toBe(false));
    await userEvent.click(bookButton());
    expect((await screen.findByTestId('booked-title')).textContent).toContain("You're booked");

    const [booking] = postsTo(api.calls, '/api/appointments');
    expect(booking!.body).toEqual({
      offeringId: FLOW45,
      start: START,
      customer: { name: 'Ana Flores', phone: '+14425550123' },
      noShowPolicy: policy35.policyText,
    });
    expect(booking!.headers['x-card-token']).toBe(token);
    expect(isToken(booking!.headers['x-manage-token'])).toBe(true);
    expect(loadAppointments().map((s) => [s.id, s.manageToken])).toEqual([[created.appointment.id, created.manageToken]]);
    // The booking is done: the next one starts fresh.
    expect(loadDraft()).toMatchObject({ serviceId: null, start: null, pending: null });
  });

  it('says so when the client came back without adding one', async () => {
    keptBooking();
    savePendingCheckout({ token: newToken(), remember: false, sessionId: cardCheckout.sessionId });
    mockApi([['GET /api/no-show-policy', { body: policy35 }]]);
    renderApp('/book/card-return?status=cancelled');

    const section = await screen.findByTestId('card-section');
    expect(section.textContent).toContain("Your card wasn't added. Add a card to book this time.");
    expect(loadPendingCheckout()).toBeNull();
    expect(bookButton().disabled).toBe(true);
  });

  it('offers to try again when the card couldn’t be saved', async () => {
    const token = newToken();
    keptBooking();
    savePendingCheckout({ token, remember: true, sessionId: cardCheckout.sessionId });
    const api = mockApi([
      ['POST /api/cards', { body: cardSaved }],
      ['GET /api/no-show-policy', { body: policy35 }],
    ]);
    api.once('POST /api/cards', 'offline');
    renderApp(`/book/card-return?status=saved&session_id=${cardCheckout.sessionId}`);

    expect((await screen.findByRole('heading', { level: 1 })).textContent).toBe("Your card wasn't added");
    expect(screen.getByText("We couldn't reach the shop. Check your internet connection and try again.")).toBeTruthy();
    await userEvent.click(button('Try again'));
    expect((await screen.findByTestId('card-label')).textContent).toContain('Visa •••• 4242');
    // "Remember me": kept on this computer.
    expect(JSON.parse(localStorage.getItem(CARD_KEY)!)).toEqual({ token, card: cardSaved.card });
  });

  it('isn’t asked for when the shop doesn’t need one', async () => {
    const api = mockApi([
      ['GET /api/no-show-policy', { body: policyNotRequired }],
      ['POST /api/appointments', { status: 201, body: created }],
    ]);
    keptBooking();
    renderApp('/book/review');

    await waitFor(() => expect(bookButton().disabled).toBe(false));
    expect(screen.queryByTestId('card-section')).toBeNull();
    await userEvent.click(bookButton());
    await screen.findByTestId('booked-title');
    const [booking] = postsTo(api.calls, '/api/appointments');
    expect(booking!.headers['x-card-token']).toBeUndefined();
    expect(booking!.body).not.toHaveProperty('noShowPolicy');
  });
});

describe('when booking doesn’t go through', () => {
  it('goes back to the times with a note when someone just booked it', async () => {
    mockApi([
      ['GET /api/no-show-policy', { body: policyNotRequired }],
      ['GET /api/availability', { body: availability }],
      ['POST /api/appointments', apiError(slotTaken.error.code, slotTaken.error.message, 409)],
    ]);
    keptBooking();
    renderApp('/book/review');

    await waitFor(() => expect(bookButton().disabled).toBe(false));
    await userEvent.click(bookButton());
    expect((await screen.findByTestId('time-notice')).textContent).toBe('Someone just booked 10 AM. Pick another time.');
    expect(screen.getByRole('heading', { level: 1 }).textContent).toBe('Pick a day and time');
    expect(loadDraft()).toMatchObject({ start: null, notice: 'Someone just booked 10 AM. Pick another time.', details });
  });

  it('says "Not confirmed yet" when the answer was lost, and trying again can’t book twice', async () => {
    const api = mockApi([
      ['GET /api/no-show-policy', { body: policyNotRequired }],
      ['POST /api/appointments', 'offline'],
    ]);
    keptBooking();
    renderApp('/book/review');

    await waitFor(() => expect(bookButton().disabled).toBe(false));
    await userEvent.click(bookButton());
    const failure = await screen.findByTestId('booking-failure');
    expect(failure.textContent).toContain('Not confirmed yet');
    expect(failure.textContent).toContain("Trying again won't book it twice.");
    // Tried once more on its own already.
    expect(postsTo(api.calls, '/api/appointments')).toHaveLength(2);

    api.once('POST /api/appointments', { status: 201, body: created });
    await userEvent.click(within(failure).getByRole('button', { name: 'Try again' }));
    await screen.findByTestId('booked-title');
    const tokens = postsTo(api.calls, '/api/appointments').map((c) => c.headers['x-manage-token']);
    expect(tokens).toHaveLength(3);
    expect(new Set(tokens).size).toBe(1);
  });

  it('keeps the same token for the same booking after a reload, and a new one for another time', async () => {
    const api = mockApi([
      ['GET /api/no-show-policy', { body: policyNotRequired }],
      ['POST /api/appointments', 'offline'],
    ]);
    keptBooking();
    const first = renderApp('/book/review');
    await waitFor(() => expect(bookButton().disabled).toBe(false));
    await userEvent.click(bookButton());
    await screen.findByTestId('booking-failure');
    const token = postsTo(api.calls, '/api/appointments')[0]!.headers['x-manage-token'];
    first.unmount();

    // The tab reloaded: the booking, and its token, come back from this tab's storage.
    renderApp('/book/review');
    await waitFor(() => expect(bookButton().disabled).toBe(false));
    await userEvent.click(bookButton());
    await screen.findByTestId('booking-failure');
    expect(postsTo(api.calls, '/api/appointments').map((c) => c.headers['x-manage-token'])).toEqual([token, token, token, token]);
  });

  it('forgets a card the server can’t use and asks for another', async () => {
    storeCard({ token: newToken(), card: cardSaved.card }, true);
    mockApi([
      ['GET /api/no-show-policy', { body: policy35 }],
      ['POST /api/appointments', apiError(cardRequired.error.code, cardRequired.error.message, 409)],
    ]);
    keptBooking();
    renderApp('/book/review');

    await waitFor(() => expect(bookButton().disabled).toBe(false));
    await userEvent.click(bookButton());
    const section = screen.getByTestId('card-section');
    await waitFor(() => expect(section.textContent).toContain(cardRequired.error.message));
    expect(within(section).getByRole('button', { name: 'Add a card' })).toBeTruthy();
    expect(loadCard()).toBeNull();
    expect(bookButton().disabled).toBe(true);
  });

  it('shows a policy the shop just changed, and books with the new one', async () => {
    const newPolicy = { ...policy35, policyText: policy35.policyText!.replace('$35', '$40'), minFeeCents: 4000, maxFeeCents: 4000 };
    storeCard({ token: newToken(), card: cardSaved.card }, true);
    const api = mockApi([
      ['GET /api/no-show-policy', { body: newPolicy }],
      ['POST /api/appointments', { status: 201, body: created }],
    ]);
    api.once('GET /api/no-show-policy', { body: policy35 });
    api.once('POST /api/appointments', apiError(policyChanged.error.code, policyChanged.error.message, 409));
    keptBooking();
    renderApp('/book/review');

    await waitFor(() => expect(bookButton().disabled).toBe(false));
    await userEvent.click(bookButton());
    expect((await screen.findByText(policyChanged.error.message)).closest('[role="alert"]')?.textContent).toContain(
      'The shop just changed its policy',
    );
    await waitFor(() => expect(screen.getByTestId('card-section').textContent).toContain(newPolicy.policyText));
    await waitFor(() => expect(bookButton().disabled).toBe(false));
    await userEvent.click(bookButton());
    await screen.findByTestId('booked-title');
    expect(postsTo(api.calls, '/api/appointments').map((c) => (c.body as { noShowPolicy: string }).noShowPolicy)).toEqual([
      policy35.policyText,
      newPolicy.policyText,
    ]);
  });

  it('says which limit it hit, in the server’s words', async () => {
    mockApi([
      ['GET /api/no-show-policy', { body: policyNotRequired }],
      ['POST /api/appointments', apiError(rateLimited.error.code, rateLimited.error.message, 429)],
    ]);
    keptBooking();
    renderApp('/book/review');

    await waitFor(() => expect(bookButton().disabled).toBe(false));
    await userEvent.click(bookButton());
    const failure = await screen.findByTestId('booking-failure');
    expect(failure.textContent).toContain('Not booked yet');
    expect(failure.textContent).toContain(rateLimited.error.message);
    expect(within(failure).getByRole('link', { name: /Call the shop/ })).toBeTruthy();
  });
});
