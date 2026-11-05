import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { times, visibleText } from '../test/text';
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
import { canTryAgain } from './CardReturnPage';
import { EMPTY_DRAFT, loadDraft, saveDraft, type BookingDraft } from './flow';
import { bookNote, CANT_KEEP_BOOKING } from './ReviewStep';
import { ApiError } from '../api/client';

// Stripe's card page is another site: the test only sees where the page would go.
vi.mock('../lib/leave', () => ({ leaveTo: vi.fn() }));

const START = '2026-11-03T18:00:00Z'; // Tuesday 10 AM in the shop
const PHONE = '+14425550123';
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
    expect(loadPendingCheckout()).toEqual({ token, remember: false, sessionId: cardCheckout.sessionId, phone: PHONE });
    expect(loadDraft()).toMatchObject({ start: START, choice: { kind: 'offering', offeringId: FLOW45 } });
  });

  it('is kept when Stripe sends the client back, and the booking goes with it', async () => {
    const token = newToken();
    keptBooking();
    savePendingCheckout({ token, remember: false, sessionId: cardCheckout.sessionId, phone: PHONE });
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
    // Not "remember me": kept until this tab closes, not on the computer, with the number of who added it.
    expect(localStorage.getItem(CARD_KEY)).toBeNull();
    expect(loadCard()).toEqual({ token, card: cardSaved.card, phone: PHONE });

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
    // The booking is done: the next one starts fresh, without Ana's details.
    expect(loadDraft()).toEqual(EMPTY_DRAFT);
    // "Remember me" was off: the card goes once it's booked, like the app.
    expect(loadCard()).toBeNull();
  });

  it('says so when the client came back without adding one', async () => {
    keptBooking();
    savePendingCheckout({ token: newToken(), remember: false, sessionId: cardCheckout.sessionId, phone: PHONE });
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
    savePendingCheckout({ token, remember: true, sessionId: cardCheckout.sessionId, phone: PHONE });
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
    expect(JSON.parse(localStorage.getItem(CARD_KEY)!)).toEqual({ token, card: cardSaved.card, phone: PHONE });
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
    expect((await screen.findByTestId('time-notice')).textContent).toBe(times('Someone just booked 10 AM. Pick another time.'));
    expect(screen.getByRole('heading', { level: 1 }).textContent).toBe('Pick a day and time');
    expect(loadDraft()).toMatchObject({ start: null, notice: times('Someone just booked 10 AM. Pick another time.'), details });
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
    storeCard({ token: newToken(), card: cardSaved.card, phone: PHONE }, true);
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
    storeCard({ token: newToken(), card: cardSaved.card, phone: PHONE }, true);
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

describe('on a shared computer', () => {
  it('doesn’t offer a card someone else added here', async () => {
    // Alex added a card and asked to be remembered; now Ana, with her own number, books.
    storeCard({ token: newToken(), card: cardSaved.card, phone: '+17605550161' }, true);
    mockApi([['GET /api/no-show-policy', { body: policy35 }]]);
    keptBooking();
    renderApp('/book/review');

    const section = await screen.findByTestId('card-section');
    expect(within(section).queryByTestId('card-label')).toBeNull();
    expect(within(section).getByRole('button', { name: 'Add a card' })).toBeTruthy();
    expect(bookButton().disabled).toBe(true);
  });

  it('books with the card the same client added, and keeps it when they asked to be remembered', async () => {
    const token = newToken();
    storeCard({ token, card: cardSaved.card, phone: PHONE }, true);
    const api = mockApi([
      ['GET /api/no-show-policy', { body: policy35 }],
      ['POST /api/appointments', { status: 201, body: created }],
    ]);
    keptBooking({ details: { ...details, remember: true } });
    renderApp('/book/review');

    expect((await screen.findByTestId('card-label')).textContent).toContain('Visa •••• 4242');
    await waitFor(() => expect(bookButton().disabled).toBe(false));
    await userEvent.click(bookButton());
    await screen.findByTestId('booked-title');
    expect(postsTo(api.calls, '/api/appointments')[0]!.headers['x-card-token']).toBe(token);
    expect(JSON.parse(localStorage.getItem(CARD_KEY)!)).toEqual({ token, card: cardSaved.card, phone: PHONE });
  });
});

describe('when the shop needs a card after all', () => {
  it('checks the policy again and asks for one, keeping a card that wasn’t sent', async () => {
    const token = newToken();
    storeCard({ token, card: cardSaved.card, phone: PHONE }, true);
    const api = mockApi([
      ['GET /api/no-show-policy', { body: policy35 }],
      ['POST /api/appointments', apiError(cardRequired.error.code, cardRequired.error.message, 400)],
    ]);
    // Review opened while the shop's protection was off for this booking.
    api.once('GET /api/no-show-policy', { body: policyNotRequired });
    keptBooking();
    renderApp('/book/review');

    await waitFor(() => expect(bookButton().disabled).toBe(false));
    expect(screen.queryByTestId('card-section')).toBeNull();
    await userEvent.click(bookButton());

    // The policy as it is now: the card section, the server's words, and Ana's own card, still there.
    const section = await screen.findByTestId('card-section');
    expect(section.textContent).toContain(cardRequired.error.message);
    expect(within(section).getByTestId('card-label').textContent).toContain('Visa •••• 4242');
    expect(api.calls.filter((c) => c.path === '/api/no-show-policy')).toHaveLength(2);
    expect(postsTo(api.calls, '/api/appointments')[0]!.headers['x-card-token']).toBeUndefined();
    expect(loadCard()).toMatchObject({ token, phone: PHONE });
    await waitFor(() => expect(bookButton().disabled).toBe(false));
  });

  it('says why when the policy still shows no card is needed', async () => {
    mockApi([
      ['GET /api/no-show-policy', { body: policyNotRequired }],
      ['POST /api/appointments', apiError(cardRequired.error.code, cardRequired.error.message, 400)],
    ]);
    keptBooking();
    renderApp('/book/review');

    await waitFor(() => expect(bookButton().disabled).toBe(false));
    await userEvent.click(bookButton());
    expect((await screen.findByTestId('card-message')).textContent).toContain(cardRequired.error.message);
  });

  it('checks the policy again when cards can’t be taken online, and books without one when none is needed now', async () => {
    const api = mockApi([
      ['GET /api/no-show-policy', { body: policyNotRequired }],
      ['POST /api/cards/checkout', apiError('stripe_not_configured', "Card payments aren't set up on the server.", 503)],
      ['POST /api/appointments', { status: 201, body: created }],
    ]);
    api.once('GET /api/no-show-policy', { body: policy35 });
    keptBooking();
    renderApp('/book/review');

    const section = await screen.findByTestId('card-section');
    await userEvent.click(within(section).getByRole('button', { name: 'Add a card' }));
    await waitFor(() => expect(screen.queryByTestId('card-section')).toBeNull());
    await waitFor(() => expect(bookButton().disabled).toBe(false));
    expect(leaveTo).not.toHaveBeenCalled();
    await userEvent.click(bookButton());
    await screen.findByTestId('booked-title');
  });

  it('stays on Review, saying why, when this browser can’t keep the booking for the way back', async () => {
    mockApi([
      ['GET /api/no-show-policy', { body: policy35 }],
      ['POST /api/cards/checkout', { body: cardCheckout }],
    ]);
    keptBooking();
    renderApp('/book/review');
    const section = await screen.findByTestId('card-section');

    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new DOMException('Storage is off', 'SecurityError');
    });
    await userEvent.click(within(section).getByRole('button', { name: 'Add a card' }));
    await waitFor(() => expect(section.textContent).toContain(CANT_KEEP_BOOKING));
    expect(leaveTo).not.toHaveBeenCalled();
    expect(within(section).getByRole('button', { name: 'Add a card' })).toBeTruthy();
  });
});

describe('the line under Book appointment', () => {
  const card = { token: newToken(), card: cardSaved.card, phone: PHONE };
  const LA = 'America/Los_Angeles';

  it('says "any time" only when cancelling is free until the start', () => {
    const at8 = new Date('2026-11-03T16:00:00Z');
    expect(bookNote(policyNotRequired, null, START, at8, LA)).toBe('You can cancel online any time before your appointment starts.');
    expect(bookNote(policy35, null, START, at8, LA)).toBe('Add a card first to book this time.');
    expect(bookNote({ ...policy35, lateCancelWindowMinutes: null }, card, START, at8, LA)).toBe(
      'Nothing is charged now. You can cancel online any time before your appointment starts.',
    );
  });

  it('says until when cancelling is free, with the day when it’s another day', () => {
    expect(bookNote(policy35, card, START, new Date('2026-11-03T16:00:00Z'), LA)).toBe(
      times('Nothing is charged now. Cancelling online is free until 9 AM (1 hour before).'),
    );
    // Exactly the window before is still free, like the server.
    expect(bookNote(policy35, card, START, new Date('2026-11-03T17:00:00Z'), LA)).toBe(
      times('Nothing is charged now. Cancelling online is free until 9 AM (1 hour before).'),
    );
    expect(bookNote({ ...policy35, lateCancelWindowMinutes: 1440 }, card, START, new Date('2026-11-01T16:00:00Z'), LA)).toBe(
      times('Nothing is charged now. Cancelling online is free until Mon, Nov 2 at 10 AM (24 hours before).'),
    );
  });

  it('says so when the time is already inside the window', () => {
    expect(bookNote(policy35, card, START, new Date('2026-11-03T17:30:00Z'), LA)).toBe(
      'Nothing is charged now. This time is less than 1 hour away, so cancelling it may be charged $35.',
    );
  });

  it('shows under the button on Review, which has no second summary', async () => {
    storeCard(card, false);
    mockApi([['GET /api/no-show-policy', { body: policy35 }]]);
    keptBooking();
    renderApp('/book/review');

    await waitFor(() =>
      expect(screen.getByTestId('book-note').textContent).toBe(times('Nothing is charged now. Cancelling online is free until 9 AM (1 hour before).')),
    );
    // Review lists everything once: no "Your appointment" card, and "No payment now" said once outside the policy.
    expect(screen.queryByTestId('summary-card')).toBeNull();
    expect(screen.getAllByText(/No payment now/).filter((el) => !el.closest('[data-testid="card-section"]'))).toHaveLength(1);
    const header = screen.getByRole('heading', { level: 1, name: 'Review and book' }).closest('.step-header') as HTMLElement;
    expect(within(header).getByRole('link', { name: '(442) 341-3053' }).getAttribute('href')).toBe('tel:+14423413053');
    // The shop's words are written for the app too: the website says its own cancelling is the same.
    expect(screen.getByTestId('fee-warning').textContent).toContain('Cancelling on this website, under My appointments, works the same as cancelling in the app.');
    // The whole policy, from the notice, in a new tab.
    expect(within(screen.getByTestId('fee-warning')).getByRole('link', { name: /^Read the Cancellation & No-Show Policy/ }).getAttribute('href')).toBe('/cancellation-policy');
  });
});

describe('what booking agrees to', () => {
  const card = { token: newToken(), card: cardSaved.card, phone: PHONE };

  /** The line right above "Book appointment", and the button after it. */
  function consent() {
    const line = screen.getByTestId('book-consent');
    expect(line.nextElementSibling).toBe(screen.getByTestId('book-button'));
    return line;
  }

  it('is right above Book appointment with a card on file, the policies in a new tab', async () => {
    storeCard(card, false);
    mockApi([['GET /api/no-show-policy', { body: policy35 }]]);
    keptBooking();
    renderApp('/book/review');
    await waitFor(() => expect(screen.getByTestId('book-button')).toHaveProperty('disabled', false));
    const line = consent();
    expect(visibleText(line)).toBe('By booking, you agree to our Terms of Service and Cancellation & No-Show Policy.');
    const links = within(line).getAllByRole('link');
    expect(links.map((a) => [a.textContent, a.getAttribute('href'), a.getAttribute('target'), a.getAttribute('rel')])).toEqual([
      ['Terms of Service (opens in a new tab)', '/terms', '_blank', 'noopener'],
      ['Cancellation & No-Show Policy (opens in a new tab)', '/cancellation-policy', '_blank', 'noopener'],
    ]);
  });

  it('is there without a card too', async () => {
    mockApi([['GET /api/no-show-policy', { body: policyNotRequired }]]);
    keptBooking();
    renderApp('/book/review');
    await waitFor(() => expect(screen.getByTestId('book-button')).toHaveProperty('disabled', false));
    expect(screen.queryByTestId('card-section')).toBeNull();
    expect(visibleText(consent())).toBe('By booking, you agree to our Terms of Service and Cancellation & No-Show Policy.');
  });
});

describe('coming back from Stripe’s card page', () => {
  it('doesn’t save an older card page’s card, and says what to do', async () => {
    keptBooking();
    savePendingCheckout({ token: newToken(), remember: false, sessionId: 'cs_test_newerSession', phone: PHONE });
    const api = mockApi([
      ['POST /api/cards', { body: cardSaved }],
      ['GET /api/no-show-policy', { body: policy35 }],
    ]);
    renderApp('/book/card-return?status=saved&session_id=cs_test_olderSession');

    expect(await screen.findByText('That was an older card page. Go back to your booking and add your card again.')).toBeTruthy();
    expect(screen.queryByRole('button', { name: 'Try again' })).toBeNull();
    expect(postsTo(api.calls, '/api/cards')).toHaveLength(0);
    await userEvent.click(button('Back to your booking'));
    expect(await screen.findByTestId('card-section')).toBeTruthy();
  });

  it('offers Try again only when trying again can work', async () => {
    keptBooking();
    savePendingCheckout({ token: newToken(), remember: false, sessionId: cardCheckout.sessionId, phone: PHONE });
    mockApi([
      ['POST /api/cards', apiError('not_found', "We couldn't find that card. Add it again.", 404)],
      ['GET /api/no-show-policy', { body: policy35 }],
    ]);
    renderApp(`/book/card-return?status=saved&session_id=${cardCheckout.sessionId}`);

    expect(await screen.findByText("We couldn't find that card. Add it again.")).toBeTruthy();
    expect(screen.queryByRole('button', { name: 'Try again' })).toBeNull();
    // Nothing more can come of that card page.
    expect(loadPendingCheckout()).toBeNull();
  });

  it('knows which answers are worth trying again', () => {
    expect(canTryAgain(new ApiError('offline', 'x', 0))).toBe(true);
    expect(canTryAgain(new ApiError('server_error', 'x', 500))).toBe(true);
    expect(canTryAgain(new ApiError('stripe_unavailable', 'x', 503))).toBe(true);
    expect(canTryAgain(new ApiError('rate_limited', 'x', 429))).toBe(true);
    expect(canTryAgain(new ApiError('not_found', 'x', 404))).toBe(false);
    expect(canTryAgain(new ApiError('invalid_request', 'x', 400))).toBe(false);
  });
});
