import { act, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import analyticsFixture from '../../../test/fixtures/contract/analytics.json';
import codeSession from '../../../test/fixtures/contract/computer-session-created.json';
import computersFixture from '../../../test/fixtures/contract/computer-sessions.json';
import codeFixture from '../../../test/fixtures/contract/computer-code.json';
import alreadyCompleted from '../../../test/fixtures/contract/errors/already_completed.json';
import feeCharged from '../../../test/fixtures/contract/no-show-fee-charged.json';
import noShowSettings from '../../../test/fixtures/contract/no-show-settings.json';
import ownerAppointments from '../../../test/fixtures/contract/owner-appointments-with-sale.json';
import ownerProducts from '../../../test/fixtures/contract/owner-products.json';
import saleCreated from '../../../test/fixtures/contract/sale-created.json';
import saleVoided from '../../../test/fixtures/contract/sale-voided.json';
import salesDay from '../../../test/fixtures/contract/sales-day.json';
import stripeActive from '../../../test/fixtures/contract/stripe-connection-active.json';
import stripeLink from '../../../test/fixtures/contract/stripe-connect-link.json';
import stripeNotConnected from '../../../test/fixtures/contract/stripe-connection-not-connected.json';
import stripeOff from '../../../test/fixtures/contract/stripe-connection-off.json';
import { leaveTo } from '../lib/leave';
import { apiError, mockApi, renderApp, type ApiCall } from '../test/api';
import { times } from '../test/text';
import { session } from './session';

vi.mock('../lib/leave', () => ({ leaveTo: vi.fn() }));

// Izzy Clipz Business against the server's own contract fixtures: signing in with a code
// (or the owner key), Today with its checkout and Void, Analytics, Products and Settings,
// and a session signed out from the iPhone dropping back to sign-in.

const TODAY_ROUTES: Parameters<typeof mockApi>[0] = [
  ['GET /api/owner/appointments', { body: ownerAppointments }],
  ['GET /api/owner/time-off', { body: { timeOff: [] } }],
  ['GET /api/owner/sales', { body: salesDay }],
];

function signedIn() {
  session.signIn(codeSession as never);
}

const main = () => within(screen.getByRole('main'));

beforeEach(() => {
  session.reset();
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(new Date('2026-11-02T20:00:00Z')); // Monday at noon at the shop
});

afterEach(() => {
  vi.useRealTimers();
  session.reset();
});

describe('signing in', () => {
  it('takes the 6-digit code from the app, spaces and all, and opens Today', async () => {
    const api = mockApi([['POST /api/computer-sessions', { status: 201, body: codeSession }], ...TODAY_ROUTES]);
    renderApp('/business');
    expect(await screen.findByRole('heading', { level: 1, name: 'Izzy Clipz Business on your computer' })).toBeTruthy();
    const steps = main().getByRole('list');
    expect(
      within(steps)
        .getAllByRole('listitem')
        .map((li) => li.textContent),
    ).toEqual(['1Open Izzy Clipz Business on your iPhone.', '2Tap Settings → Use on a computer.', '3Type the 6-digit code.']);
    await userEvent.type(screen.getByLabelText('6-digit code'), '483 920');
    await userEvent.click(screen.getByRole('button', { name: 'Sign in' }));
    expect(await screen.findByText(times("Your shop's day: appointments, checkout and today's sales."))).toBeTruthy();
    expect(api.calls[0]).toMatchObject({ path: '/api/computer-sessions', body: { code: '483920' } });
    expect(session.current().session?.token).toBe(codeSession.token);
    // Signed in: the local nav, with Sign out.
    const nav = screen.getByRole('navigation', { name: 'Izzy Clipz Business' });
    expect(
      within(nav)
        .getAllByRole('link')
        .map((a) => a.textContent),
    ).toEqual(['Today', 'Analytics', 'Products', 'Settings']);
    expect(within(nav).getByRole('button', { name: 'Sign out' })).toBeTruthy();
  });

  it('says what to do when the code is wrong, and checks the code has 6 digits first', async () => {
    const api = mockApi([['POST /api/computer-sessions', apiError('wrong_code', "That code isn't right or has run out.", 400)]]);
    renderApp('/business');
    const field = await screen.findByLabelText('6-digit code');
    await userEvent.type(field, '4839');
    await userEvent.click(screen.getByRole('button', { name: 'Sign in' }));
    expect(screen.getByRole('alert').textContent).toBe('Type the 6 digits of the code, like 483 920.');
    expect(api.calls).toHaveLength(0);
    await userEvent.type(field, '20');
    await userEvent.click(screen.getByRole('button', { name: 'Sign in' }));
    expect((await screen.findByRole('alert')).textContent).toBe(
      "That code isn't right or has run out. Get a new one in the app: Settings → Use on a computer.",
    );
    expect(field.getAttribute('aria-invalid')).toBe('true');
  });

  it('can use the owner key instead, which is never kept', async () => {
    const api = mockApi([
      ['POST /api/owner/computer-codes', { status: 201, body: codeFixture }],
      ['POST /api/computer-sessions', { status: 201, body: codeSession }],
      ...TODAY_ROUTES,
    ]);
    renderApp('/business/today');
    await userEvent.click(await screen.findByRole('button', { name: 'Use the owner key instead' }));
    await userEvent.type(screen.getByLabelText('Owner key'), 'the-owner-key-for-this-test');
    await userEvent.click(screen.getByRole('button', { name: 'Sign in with the key' }));
    expect(await screen.findByText(times("Your shop's day: appointments, checkout and today's sales."))).toBeTruthy();
    expect(api.calls.slice(0, 2).map((c) => c.path)).toEqual(['/api/owner/computer-codes', '/api/computer-sessions']);
    expect(JSON.stringify(localStorage)).not.toContain('the-owner-key-for-this-test');
  });

  it('never offers the owner key to the browser’s password manager to keep', async () => {
    mockApi([]);
    renderApp('/business/today');
    await userEvent.click(await screen.findByRole('button', { name: 'Use the owner key instead' }));
    const key = screen.getByLabelText('Owner key');
    // A text field (dotted out by its style), not a password field: browsers offer to save, and
    // sync, what's typed in a password field. Every "don't keep this" they and password managers read.
    expect(key.getAttribute('type')).toBe('text');
    expect(key.getAttribute('autocomplete')).toBe('off');
    expect(key.className).toContain('biz-key-input');
    for (const name of ['data-1p-ignore', 'data-lpignore', 'data-bwignore']) expect(key.getAttribute(name)).toBe('true');
    expect(key.getAttribute('data-form-type')).toBe('other');
    expect(screen.getByText(/doesn't keep it\. Don't save it in this computer's password manager\./)).toBeTruthy();
    // Nowhere on the sign-in page is there a field a browser would treat as a password.
    const fields = Array.from(document.querySelectorAll('input'));
    expect(fields.filter((field) => field.type === 'password' || /password/.test(field.autocomplete))).toEqual([]);
  });

  it('says this computer was signed out when its 30 days ran out while the page was closed', async () => {
    localStorage.setItem(
      'izzy.business.session.v1',
      JSON.stringify({ token: 'x'.repeat(43), id: 'a', name: 'Chrome on Mac', createdAt: '2026-09-01T18:00:00Z', expiresAt: '2026-10-01T18:00:00Z' }),
    );
    const api = mockApi([]);
    renderApp('/business/analytics');
    expect((await screen.findByTestId('signed-out-line')).textContent).toContain('This computer was signed out.');
    expect(screen.getByLabelText('6-digit code')).toBeTruthy();
    expect(api.calls).toHaveLength(0);
  });

  it('drops back to sign-in with a friendly line when the session was signed out from the iPhone', async () => {
    signedIn();
    mockApi([['GET /api/owner/*', apiError('unauthorized', "That owner key isn't right. Check it and sign in again.", 401)]]);
    renderApp('/business/analytics');
    expect(await screen.findByText('This computer was signed out.')).toBeTruthy();
    expect(screen.getByRole('heading', { level: 1, name: 'Izzy Clipz Business on your computer' })).toBeTruthy();
    // Never the server's words about a key, which the owner didn't type.
    expect(screen.queryByText(/owner key isn't right/)).toBeNull();
  });
});

describe('Today', () => {
  it('lists the day’s appointments and sales, and checks an appointment out in cash with a product', async () => {
    signedIn();
    const api = mockApi([...TODAY_ROUTES, ['GET /api/owner/products', { body: ownerProducts }], ['POST /api/owner/sales', { status: 201, body: saleCreated }]]);
    renderApp('/business/today');
    const cards = await screen.findAllByTestId('appointment');
    const chris = cards.find((card) => card.textContent?.includes('Chris'))!;
    expect(chris.textContent).toContain('Booked');
    expect(cards.find((card) => card.textContent?.includes('Andre'))!.textContent).toContain('Paid $96 · Cash');
    expect(screen.getByTestId('sales-totals').textContent).toBe('3 sales · $184');

    await userEvent.click(chris);
    const panel = screen.getByTestId('side-panel');
    expect(within(panel).getByRole('heading', { name: 'Chris' })).toBeTruthy();
    await userEvent.click(within(panel).getByRole('button', { name: 'Check out' }));
    // The appointment's service at its booked price, Sold by its barber.
    expect(within(panel).getByText('Haircut')).toBeTruthy();
    expect((within(panel).getByRole('radio', { name: 'Carlos' }) as HTMLInputElement).checked).toBe(true);
    expect(within(panel).getByTestId('ticket-total').textContent).toBe('$45');
    await userEvent.click(within(panel).getByRole('button', { name: '+ Product' }));
    await userEvent.click(await within(panel).findByRole('button', { name: /Matte pomade/ }));
    expect(within(panel).getByTestId('ticket-total').textContent).toBe('$63');
    await userEvent.click(within(panel).getByRole('button', { name: 'Cash' }));
    const confirm = screen.getByTestId('confirm-sale');
    expect(within(confirm).getByRole('heading').textContent).toBe('Record a $63 cash sale for Carlos?');
    await userEvent.click(within(confirm).getByRole('button', { name: 'Record sale' }));
    // The receipt says what the server recorded.
    expect((await within(panel).findByTestId('receipt')).textContent).toContain('Sold $96 · Cash · Flowxbori');

    const sale = api.calls.find((c) => c.method === 'POST' && c.path === '/api/owner/sales')!;
    expect(sale.body).toEqual({
      barberId: 'carlos-rafael',
      appointmentId: '00000000-0000-4000-8000-000000000003',
      customerName: null,
      method: 'cash',
      items: [
        { kind: 'service', serviceId: 'haircut', unitCents: 4500, quantity: 1 },
        { kind: 'product', productId: '00000000-0000-4000-8000-000000000001', unitCents: 1800, quantity: 1 },
      ],
    });
    expect(sale.headers['idempotency-key']).toMatch(/^[A-Za-z0-9_-]{43}$/);
  });

  it('asks before voiding, and tells to refund a card sale in Stripe', async () => {
    signedIn();
    const api = mockApi([...TODAY_ROUTES, ['POST /api/owner/sales/*', { body: saleVoided }]]);
    renderApp('/business/today');
    await screen.findByTestId('sales-totals');
    await userEvent.click(await screen.findByRole('button', { name: 'Void the $63 sale to Chris' }));
    const dialog = screen.getByTestId('confirm-void');
    expect(within(dialog).getByRole('heading').textContent).toBe('Void this $63 sale?');
    expect(dialog.textContent).toContain("Refund the card in your Stripe Dashboard: voiding doesn't refund it.");
    await userEvent.type(within(dialog).getByLabelText(/Reason/), 'Rang up twice');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Void sale' }));
    expect((await screen.findByTestId('void-message')).textContent).toBe('The sale was voided, so it no longer counts in your sales.');
    const card = salesDay.sales.find((s) => s.method === 'card')!;
    expect(api.calls.find((c) => c.method === 'POST')).toMatchObject({ path: `/api/owner/sales/${card.id}/void`, body: { reason: 'Rang up twice' } });
  });

  it('charges the agreed no-show fee after asking, naming the card, and then shows what happened', async () => {
    signedIn();
    // This morning's no-show, the fee not charged yet; the server answers with it charged.
    const when = { start: '2026-11-02T17:00:00Z', end: '2026-11-02T17:45:00Z' };
    const noShow = { ...feeCharged.appointment, ...when, noShowFee: { ...feeCharged.appointment.noShowFee, status: 'none', chargedAt: null } };
    const charged = { ...feeCharged.appointment, ...when };
    let fee: typeof noShow | typeof charged = noShow;
    const api = mockApi([
      ['GET /api/owner/appointments', () => ({ body: { appointments: [fee] } })],
      ['GET /api/owner/time-off', { body: { timeOff: [] } }],
      ['GET /api/owner/sales', { body: { date: '2026-11-02', sales: [], totals: { totalCents: 0, count: 0 } } }],
      ['POST /api/owner/appointments/*', () => ((fee = charged), { body: { appointment: charged } })],
    ]);
    renderApp('/business/today');
    await userEvent.click(await screen.findByTestId('appointment'));
    const panel = screen.getByTestId('side-panel');
    await userEvent.click(within(panel).getByRole('button', { name: 'Charge no-show fee ($35)' }));
    const dialog = screen.getByTestId('confirm-fee');
    expect(within(dialog).getByRole('heading').textContent).toBe("Charge $35 to Fixture Client's Visa •••• 4242?");
    await userEvent.click(within(dialog).getByRole('button', { name: 'Charge $35' }));
    // The button is gone: what happened takes the focus, so it's read out.
    const outcome = await within(panel).findByText('No-show fee charged');
    await waitFor(() => expect(document.activeElement).toBe(within(panel).getByTestId('fee-status')));
    expect(outcome).toBeTruthy();
    expect(within(panel).queryByRole('button', { name: /Charge no-show fee/ })).toBeNull();
    expect(api.calls.find((c) => c.method === 'POST')).toMatchObject({ path: `/api/owner/appointments/${noShow.id}/no-show-fee` });
  });

  it('says why a fee wasn’t charged next to its button, with the way to Settings when Stripe isn’t connected', async () => {
    signedIn();
    const when = { start: '2026-11-02T17:00:00Z', end: '2026-11-02T17:45:00Z' };
    const noShow = { ...feeCharged.appointment, ...when, noShowFee: { ...feeCharged.appointment.noShowFee, status: 'none', chargedAt: null } };
    mockApi([
      ['GET /api/owner/appointments', { body: { appointments: [noShow] } }],
      ['GET /api/owner/time-off', { body: { timeOff: [] } }],
      ['GET /api/owner/sales', { body: { date: '2026-11-02', sales: [], totals: { totalCents: 0, count: 0 } } }],
      ['POST /api/owner/appointments/*', apiError('stripe_not_configured', 'Connect Stripe in Settings to take card payments.', 503)],
    ]);
    renderApp('/business/today');
    await userEvent.click(await screen.findByTestId('appointment'));
    const panel = screen.getByTestId('side-panel');
    await userEvent.click(within(panel).getByRole('button', { name: 'Charge no-show fee ($35)' }));
    await userEvent.click(within(screen.getByTestId('confirm-fee')).getByRole('button', { name: 'Charge $35' }));
    const error = await within(panel).findByTestId('fee-error');
    expect(error.textContent).toContain('Connect Stripe in Settings to take card payments.');
    expect(within(error).getByRole('link', { name: 'Go to Settings' }).getAttribute('href')).toBe('/business/settings');
    // In the fee's section, next to its button, with the focus, so it's read out where the owner is.
    expect(within(screen.getByTestId('fee-panel')).getByTestId('fee-error')).toBe(error);
    await waitFor(() => expect(document.activeElement).toBe(error));
  });

  it('offers no charge more than 7 days after the appointment, and says why in a plain line', async () => {
    signedIn();
    // A no-show eight days ago (Sunday, October 25 at 10 AM), its fee never charged.
    const when = { start: '2026-10-25T17:00:00Z', end: '2026-10-25T17:45:00Z', createdAt: '2026-10-20T17:00:00Z' };
    const noShow = { ...feeCharged.appointment, ...when, noShowFee: { ...feeCharged.appointment.noShowFee, status: 'none', chargedAt: null } };
    const api = mockApi([
      ['GET /api/owner/appointments', { body: { appointments: [noShow] } }],
      ['GET /api/owner/time-off', { body: { timeOff: [] } }],
      ['GET /api/owner/sales', { body: { date: '2026-10-25', sales: [], totals: { totalCents: 0, count: 0 } } }],
    ]);
    renderApp('/business/today?date=2026-10-25');
    await userEvent.click(await screen.findByTestId('appointment'));
    const fee = within(screen.getByTestId('side-panel')).getByTestId('fee-panel');
    expect(within(fee).getByTestId('fee-status').textContent).toBe("It's more than 7 days after the appointment, so the fee can't be charged.");
    expect(within(fee).queryByRole('button')).toBeNull();
    expect(api.calls.filter((c) => c.method === 'POST')).toEqual([]);
  });

  it('says until when a fee can be charged, 7 days after the appointment', async () => {
    signedIn();
    const when = { start: '2026-11-02T17:00:00Z', end: '2026-11-02T17:45:00Z' };
    const noShow = { ...feeCharged.appointment, ...when, noShowFee: { ...feeCharged.appointment.noShowFee, status: 'none', chargedAt: null } };
    mockApi([
      ['GET /api/owner/appointments', { body: { appointments: [noShow] } }],
      ['GET /api/owner/time-off', { body: { timeOff: [] } }],
      ['GET /api/owner/sales', { body: { date: '2026-11-02', sales: [], totals: { totalCents: 0, count: 0 } } }],
    ]);
    renderApp('/business/today');
    await userEvent.click(await screen.findByTestId('appointment'));
    const fee = within(screen.getByTestId('side-panel')).getByTestId('fee-panel');
    expect(within(fee).getByRole('button', { name: 'Charge no-show fee ($35)' })).toBeTruthy();
    expect(fee.textContent).toContain(times('It can be charged until Mon, Nov 9 at 9 AM, 7 days after the appointment.'));
  });

  it('offers "Mark no-show" for a booking with a card on file only once it has ended, and says when', async () => {
    signedIn();
    // 11:30 AM to 12:15 PM, with a card on file; it's noon.
    const when = { start: '2026-11-02T19:30:00Z', end: '2026-11-02T20:15:00Z' };
    const booked = { ...feeCharged.appointment, ...when, status: 'booked', noShowFee: { ...feeCharged.appointment.noShowFee, status: 'none', chargedAt: null, reason: null } };
    mockApi([
      ['GET /api/owner/appointments', { body: { appointments: [booked] } }],
      ['GET /api/owner/time-off', { body: { timeOff: [] } }],
      ['GET /api/owner/sales', { body: { date: '2026-11-02', sales: [], totals: { totalCents: 0, count: 0 } } }],
    ]);
    renderApp('/business/today');
    await userEvent.click(await screen.findByTestId('appointment'));
    const panel = screen.getByTestId('side-panel');
    expect(within(panel).queryByRole('button', { name: 'Mark no-show' })).toBeNull();
    expect(within(panel).getByTestId('status-hint').textContent).toBe(
      times("Cancelling frees the time for other clients. You can mark a no-show once the appointment ends at 12:15 PM. A client who comes before then isn't a no-show."),
    );
    expect(within(panel).getByTestId('fee-status').textContent).toBe(
      "If the client doesn't come, you can mark a no-show once the appointment has ended. Then you can charge the fee.",
    );
  });

  it('shows the server’s answer when a visit that was completed is marked a no-show after being reopened', async () => {
    signedIn();
    // Reopened after it was marked done: only the server remembers that it was.
    const when = { start: '2026-11-02T17:00:00Z', end: '2026-11-02T17:45:00Z' };
    const reopened = { ...feeCharged.appointment, ...when, status: 'booked', noShowFee: { ...feeCharged.appointment.noShowFee, status: 'none', chargedAt: null, reason: null } };
    mockApi([
      ['GET /api/owner/appointments', { body: { appointments: [reopened] } }],
      ['GET /api/owner/time-off', { body: { timeOff: [] } }],
      ['GET /api/owner/sales', { body: { date: '2026-11-02', sales: [], totals: { totalCents: 0, count: 0 } } }],
      ['PATCH /api/owner/appointments/*', apiError(alreadyCompleted.error.code, alreadyCompleted.error.message, 409)],
    ]);
    renderApp('/business/today');
    await userEvent.click(await screen.findByTestId('appointment'));
    const panel = screen.getByTestId('side-panel');
    await userEvent.click(within(panel).getByRole('button', { name: 'Mark no-show' }));
    expect((await within(panel).findByRole('alert')).textContent).toBe("This appointment was marked completed, so it can't become a no-show.");
  });

  it('says first that reopening a completed visit with a card on file won’t make it a no-show', async () => {
    signedIn();
    const when = { start: '2026-11-02T17:00:00Z', end: '2026-11-02T17:45:00Z' };
    const done = { ...feeCharged.appointment, ...when, status: 'completed', noShowFee: { ...feeCharged.appointment.noShowFee, status: 'none', chargedAt: null, reason: null } };
    mockApi([
      ['GET /api/owner/appointments', { body: { appointments: [done] } }],
      ['GET /api/owner/time-off', { body: { timeOff: [] } }],
      ['GET /api/owner/sales', { body: { date: '2026-11-02', sales: [], totals: { totalCents: 0, count: 0 } } }],
    ]);
    renderApp('/business/today');
    await userEvent.click(await screen.findByTestId('appointment'));
    await userEvent.click(within(screen.getByTestId('side-panel')).getByRole('button', { name: 'Reopen' }));
    expect(screen.getByTestId('confirm-reopen').textContent).toContain(
      "It was marked done, so even once it's reopened, it can't be marked a no-show or charged a no-show fee: the client came.",
    );
  });

  it('says what a status change did, and gives it the focus the pressed button had', async () => {
    signedIn();
    const chris = ownerAppointments.appointments.find((a) => a.customer.name === 'Chris')!;
    mockApi([...TODAY_ROUTES, ['PATCH /api/owner/appointments/*', { body: { appointment: { ...chris, status: 'completed' } } }]]);
    renderApp('/business/today');
    const card = (await screen.findAllByTestId('appointment')).find((c) => c.textContent?.includes('Chris'))!;
    await userEvent.click(card);
    const panel = screen.getByTestId('side-panel');
    await userEvent.click(within(panel).getByRole('button', { name: 'Mark done' }));
    const changed = await within(panel).findByTestId('status-changed');
    expect(changed.textContent).toBe('Marked done.');
    await waitFor(() => expect(document.activeElement).toBe(changed));
  });

  it('voids a sale checked out on another day with that day’s own sale, and never makes one up', async () => {
    signedIn();
    // Andre's appointment on Tuesday, checked out (and paid) on Monday.
    const andre = { ...ownerAppointments.appointments.find((a) => a.customer.name === 'Andre')!, start: '2026-11-03T18:20:00Z', end: '2026-11-03T19:05:00Z' };
    const empty = { date: '2026-11-03', sales: [], totals: { totalCents: 0, count: 0 } };
    const api = mockApi([
      ['GET /api/owner/appointments', { body: { appointments: [andre] } }],
      ['GET /api/owner/time-off', { body: { timeOff: [] } }],
      ['GET /api/owner/sales', ({ search }: ApiCall) => ({ body: search.includes('2026-11-02') ? salesDay : empty })],
    ]);
    renderApp('/business/today?date=2026-11-03');
    await userEvent.click(await screen.findByTestId('appointment'));
    const panel = screen.getByTestId('side-panel');
    await userEvent.click(within(panel).getByRole('button', { name: 'Void sale' }));
    await waitFor(() =>
      expect(screen.getByTestId('confirm-void').textContent).toMatch(/Andre: Haircut, 2 × Matte pomade, Gift card, sold by Flowxbori on Mon, Nov 2 at 11:05\sAM\./),
    );
    expect(api.calls.some((c) => c.path === '/api/owner/sales' && c.search === '?date=2026-11-02')).toBe(true);
    await userEvent.click(within(screen.getByTestId('confirm-void')).getByRole('button', { name: 'Keep the sale' }));

    // That day's sales can't be read: the question names only the amount and how it was paid.
    api.once('GET /api/owner/sales', 'offline');
    await userEvent.click(within(panel).getByRole('button', { name: 'Void sale' }));
    await waitFor(() => expect(screen.getByTestId('confirm-void').textContent).toContain('Andre: a $96 cash sale.'));
    expect(screen.getByTestId('confirm-void').textContent).not.toContain('sold by');
  });

  it('says the products didn’t load, with Try again, instead of saying there are none', async () => {
    signedIn();
    const api = mockApi([...TODAY_ROUTES, ['GET /api/owner/products', { body: ownerProducts }]]);
    api.once('GET /api/owner/products', 'offline');
    renderApp('/business/today');
    await userEvent.click(await screen.findByRole('button', { name: 'New sale' }));
    const panel = screen.getByTestId('side-panel');
    await userEvent.click(within(panel).getByRole('button', { name: '+ Product' }));
    const failed = await within(panel).findByTestId('products-failed');
    expect(failed.textContent).toContain("The products didn't load.");
    expect(within(panel).queryByText(/No products yet/)).toBeNull();
    await userEvent.click(within(failed).getByRole('button', { name: 'Try again' }));
    expect(await within(panel).findByRole('button', { name: /Matte pomade/ })).toBeTruthy();
  });

  it('never records a walk-in twice after a lost answer, even when the ticket was closed and rung up again', async () => {
    signedIn();
    const api = mockApi([...TODAY_ROUTES, ['GET /api/owner/products', { body: ownerProducts }], ['POST /api/owner/sales', { status: 201, body: saleCreated }]]);
    renderApp('/business/today');
    const ringUp = async () => {
      await userEvent.click(await screen.findByRole('button', { name: 'New sale' }));
      const panel = screen.getByTestId('side-panel');
      await userEvent.click(within(panel).getByRole('radio', { name: 'Carlos' }));
      await userEvent.click(within(panel).getByRole('button', { name: '+ Amount' }));
      await userEvent.type(within(panel).getByLabelText(/Name/), 'Review twice');
      await userEvent.type(within(panel).getByLabelText('Amount'), '12');
      await userEvent.click(within(panel).getByRole('button', { name: 'Add the amount' }));
      // The list closed: the focus is back on the button that opened it.
      expect(document.activeElement).toBe(within(panel).getByRole('button', { name: '+ Amount' }));
      await userEvent.click(within(panel).getByRole('button', { name: 'Cash' }));
      await userEvent.click(within(screen.getByTestId('confirm-sale')).getByRole('button', { name: 'Record sale' }));
      return panel;
    };
    api.once('POST /api/owner/sales', 'offline');
    const panel = await ringUp();
    expect((await within(panel).findByTestId('ticket-failed')).textContent).toContain("Trying again is safe: the same sale can't be recorded twice.");
    await userEvent.click(within(panel).getByRole('button', { name: 'Close' }));
    await ringUp();
    await within(panel).findByTestId('receipt');
    const sent = api.calls.filter((c) => c.method === 'POST' && c.path === '/api/owner/sales');
    expect(sent).toHaveLength(2);
    expect(sent[1]!.headers['idempotency-key']).toBe(sent[0]!.headers['idempotency-key']);
  });

  it('records a sale again as a new one when its earlier, lost answer was voided since', async () => {
    signedIn();
    const api = mockApi([...TODAY_ROUTES, ['GET /api/owner/products', { body: ownerProducts }], ['POST /api/owner/sales', { status: 201, body: saleCreated }]]);
    renderApp('/business/today');
    // The key's earlier sale comes back voided (rung up after a lost answer, then voided).
    api.once('POST /api/owner/sales', { status: 200, body: { sale: { ...saleCreated.sale, voidedAt: '2026-11-02T19:00:00Z', voidReason: 'Twice' } } });
    await userEvent.click(await screen.findByRole('button', { name: 'New sale' }));
    const panel = screen.getByTestId('side-panel');
    await userEvent.click(within(panel).getByRole('radio', { name: 'Julian' }));
    await userEvent.click(within(panel).getByRole('button', { name: '+ Amount' }));
    await userEvent.type(within(panel).getByLabelText('Amount'), '20');
    await userEvent.click(within(panel).getByRole('button', { name: 'Add the amount' }));
    await userEvent.click(within(panel).getByRole('button', { name: 'Cash' }));
    await userEvent.click(within(screen.getByTestId('confirm-sale')).getByRole('button', { name: 'Record sale' }));
    expect((await within(panel).findByTestId('receipt')).textContent).toContain('Sold $96 · Cash');
    const sent = api.calls.filter((c) => c.method === 'POST' && c.path === '/api/owner/sales');
    expect(sent).toHaveLength(2);
    expect(sent[1]!.headers['idempotency-key']).not.toBe(sent[0]!.headers['idempotency-key']);
  });

  it('says the sales couldn’t load when the day didn’t, instead of loading forever', async () => {
    signedIn();
    mockApi([
      ['GET /api/owner/appointments', apiError('server_error', 'Something went wrong on our side. Try again in a moment.', 500)],
      ['GET /api/owner/time-off', { body: { timeOff: [] } }],
      ['GET /api/owner/sales', { body: salesDay }],
    ]);
    renderApp('/business/today');
    expect(await screen.findByText("Couldn't load the day")).toBeTruthy();
    expect(screen.getByTestId('sales-totals').textContent).toBe("Couldn't load the sales.");
    expect(main().queryByText('Loading…')).toBeNull();
  });

  it('shows a voided sale struck through, with its reason', async () => {
    signedIn();
    mockApi([...TODAY_ROUTES]);
    renderApp('/business/today');
    const rows = await screen.findAllByTestId('sale-row');
    const voided = rows.find((row) => row.textContent?.includes('Voided'))!;
    expect(voided.className).toContain('is-voided');
    expect(voided.querySelector('.biz-struck')?.textContent).toBe('$35');
  });

  it('says how to fill an empty day', async () => {
    signedIn();
    mockApi([
      ['GET /api/owner/appointments', { body: { appointments: [] } }],
      ['GET /api/owner/time-off', { body: { timeOff: [] } }],
      ['GET /api/owner/sales', { body: { date: '2026-11-02', sales: [], totals: { totalCents: 0, count: 0 } } }],
    ]);
    renderApp('/business/today');
    expect((await screen.findByTestId('day-empty')).textContent).toContain('Walk-ins can still be checked out with New sale.');
    expect(screen.getByTestId('sales-totals').textContent).toBe('No sales yet. They show here as you check clients out.');
  });

  it('says voided sales don’t count when the only sales were voided', async () => {
    signedIn();
    mockApi([
      ['GET /api/owner/appointments', { body: { appointments: [] } }],
      ['GET /api/owner/time-off', { body: { timeOff: [] } }],
      ['GET /api/owner/sales', { body: { date: '2026-11-02', sales: [saleVoided.sale], totals: { totalCents: 0, count: 0 } } }],
    ]);
    renderApp('/business/today');
    expect(await screen.findByText("No sales yet. Voided sales don't count.")).toBeTruthy();
    expect(screen.getByTestId('sale-row').textContent).toContain('Voided: Rang up twice');
  });
});

describe('Analytics', () => {
  it('shows the totals, the change, the top barber, the leaderboard and productivity', async () => {
    signedIn();
    const api = mockApi([['GET /api/owner/analytics', { body: analyticsFixture }]]);
    renderApp('/business/analytics?period=custom&from=2026-11-01&to=2026-11-07');
    expect((await screen.findByTestId('total-sales-value')).textContent).toBe('$724');
    // $724 against $120 the week before, named by its days, and what that is a click away.
    expect(screen.getByTestId('total-sales-change').textContent).toBe('▲ Up 503% from Oct 25 – Oct 31');
    await userEvent.click(screen.getByRole('button', { name: 'What the change compares with' }));
    expect(screen.getByTestId('total-sales').textContent).toContain('Sales for the same number of days just before this period (Oct 25 – Oct 31)');
    expect(api.calls[0]!.search).toBe('?from=2026-11-01&to=2026-11-07');
    expect(screen.getByTestId('top-barber').textContent).toContain('Izzy$2153 services · 2 products');
    const live = screen.getByTestId('live').textContent ?? '';
    expect(live).toMatch(/^Live · Updated \d{1,2}(:\d{2})?\u00a0(AM|PM)$/);

    const leaderboard = screen.getByTestId('leaderboard');
    const names = () =>
      within(leaderboard)
        .getAllByTestId('leaderboard-row')
        .map((row) => row.querySelector('.biz-rank__name')?.textContent);
    expect(names()).toEqual(['Izzy', 'Carlos', 'Flowxbori', 'Julian', 'Cristian']);
    await userEvent.click(within(leaderboard).getByRole('radio', { name: 'Products' }));
    expect(names()).toEqual(['Carlos', 'Flowxbori', 'Izzy', 'Cristian', 'Julian']);
    expect(
      within(leaderboard)
        .getAllByRole('img', { name: /place/ })
        .map((img) => img.getAttribute('aria-label')),
    ).toEqual(['First place', 'Second place', 'Second place']);

    // Each tile explains itself.
    const chair = screen.getByTestId('tile-chair');
    expect(chair.textContent).toContain('4%of open hours had a client');
    await userEvent.click(within(chair).getByRole('button', { name: 'What chair time booked means' }));
    expect(chair.textContent).toContain('Booked time divided by open hours.');
    expect(screen.getByTestId('tile-attach').textContent).toContain('60%of sales included a product');
    // Late cancellations as docs/analytics.md defines them: within 15 minutes of booking is never late.
    const late = screen.getByTestId('tile-late');
    await userEvent.click(within(late).getByRole('button', { name: 'What late cancellations means' }));
    expect(late.textContent).toContain('and more than 15 minutes after booking: cancelling within 15 minutes of booking is always free.');

    // The chart's table.
    await userEvent.click(screen.getByRole('button', { name: 'Show daily sales as a table' }));
    const table = within(screen.getByTestId('daily-sales')).getByRole('table');
    expect(within(table).getAllByRole('row')).toHaveLength(8);
    expect(within(table).getByRole('rowheader', { name: 'Sun, Nov 1' })).toBeTruthy();
  });

  it('asks for one barber’s numbers, and says the top barber is the whole shop’s', async () => {
    signedIn();
    const api = mockApi([
      ['GET /api/owner/analytics', ({ search }: ApiCall) => ({ body: { ...analyticsFixture, barberId: search.includes('barberId') ? 'flowxbori' : null } })],
    ]);
    renderApp('/business/analytics');
    await screen.findByTestId('total-sales-value');
    await userEvent.click(screen.getByRole('radio', { name: 'Flowxbori' }));
    await waitFor(() => expect(api.calls.at(-1)!.search).toBe('?from=2026-11-02&to=2026-11-02&barberId=flowxbori'));
    expect((await screen.findByTestId('top-barber')).textContent).toContain('Top sales barber (whole shop)');
    expect(screen.getByTestId('period-line').textContent).toBe('Today: Mon, Nov 2 · Flowxbori');
  });

  it('keeps the last numbers and offers Try again when a refresh fails', async () => {
    signedIn();
    const api = mockApi([['GET /api/owner/analytics', { body: analyticsFixture }]]);
    renderApp('/business/analytics?period=week');
    await screen.findByTestId('total-sales-value');
    api.once('GET /api/owner/analytics', 'offline');
    await userEvent.click(screen.getByRole('radio', { name: 'Month' }));
    expect(await screen.findByText("Couldn't load the numbers")).toBeTruthy();
    // Another period that never loaded isn't "Live" with the last period's time.
    expect(screen.getByTestId('live').textContent).toBe('Not loaded yet');
    await userEvent.click(screen.getByRole('button', { name: 'Try again' }));
    expect((await screen.findByTestId('total-sales-value')).textContent).toBe('$724');
  });

  it('stops saying Live while refreshes fail, and says when the numbers are from', async () => {
    signedIn();
    const api = mockApi([['GET /api/owner/analytics', { body: analyticsFixture }]]);
    renderApp('/business/analytics?period=week');
    await screen.findByTestId('total-sales-value');
    expect(screen.getByTestId('live').textContent).toMatch(/^Live · Updated /);
    // The page comes back on screen, and the refresh it makes fails.
    const visibility = (state: 'hidden' | 'visible') => {
      Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => state });
      document.dispatchEvent(new Event('visibilitychange'));
    };
    try {
      api.once('GET /api/owner/analytics', 'offline');
      act(() => visibility('hidden'));
      act(() => visibility('visible'));
      expect(await screen.findByText("Couldn't refresh")).toBeTruthy();
      expect(screen.getByTestId('live').textContent).toMatch(/^Last updated /);
      expect(screen.getByTestId('live').querySelector('.biz-live__dot')?.className).toContain('is-waiting');
      // The numbers from before stay.
      expect(screen.getByTestId('total-sales-value').textContent).toBe('$724');
    } finally {
      delete (document as unknown as { visibilityState?: string }).visibilityState;
    }
  });
});

describe('Products', () => {
  it('lists the products, and adds one after checking its fields', async () => {
    signedIn();
    const created = {
      id: '00000000-0000-4000-8000-000000000009',
      name: 'Hair clay',
      description: 'Strong hold.',
      priceCents: 2000,
      imageUrl: null,
      visible: true,
    };
    const api = mockApi([
      ['GET /api/owner/products', { body: ownerProducts }],
      ['POST /api/owner/products', { status: 201, body: { product: created } }],
    ]);
    renderApp('/business/products');
    const cards = await screen.findAllByTestId('product');
    expect(cards.map((c) => c.querySelector('h2')?.textContent)).toEqual(['Matte pomade', 'Beard oil', 'Hair tonic']);
    expect(cards[2]!.textContent).toContain('No price');
    expect(cards[2]!.textContent).toContain('Hidden from clients');

    await userEvent.click(screen.getByRole('button', { name: 'Add a product' }));
    const editor = screen.getByTestId('product-editor');
    await userEvent.click(within(editor).getByRole('button', { name: 'Add product' }));
    expect(within(editor).getByRole('alert').textContent).toBe('Give the product a name.');
    // Under the Name field, which is marked, described by it, and has the focus.
    const name = within(editor).getByLabelText('Name');
    expect(name.getAttribute('aria-invalid')).toBe('true');
    expect(document.getElementById(name.getAttribute('aria-describedby')!)?.textContent).toBe('Give the product a name.');
    expect(document.activeElement).toBe(name);
    await userEvent.type(within(editor).getByLabelText('Name'), 'Hair clay');
    await userEvent.type(within(editor).getByLabelText(/Description/), 'Strong hold.');
    await userEvent.click(within(editor).getByRole('button', { name: 'Add product' }));
    expect(within(editor).getByRole('alert').textContent).toBe('Type the price, like 18 or 17.50. Or tick "No price" to type it at checkout.');
    await userEvent.type(within(editor).getByLabelText('Price'), '20');
    await userEvent.click(within(editor).getByRole('button', { name: 'Add product' }));
    expect((await screen.findByTestId('products-message')).textContent).toBe('Saved Hair clay.');
    expect(api.calls.find((c) => c.method === 'POST')!.body).toEqual({ name: 'Hair clay', description: 'Strong hold.', priceCents: 2000, visible: true });
  });
});

describe('Settings', () => {
  it('connects Stripe on Stripe’s own page, coming back to Settings here', async () => {
    signedIn();
    const api = mockApi([
      ['GET /api/owner/stripe', { body: stripeNotConnected }],
      ['POST /api/owner/stripe/connect', { body: stripeLink }],
      ['GET /api/owner/no-show-settings', { body: noShowSettings }],
      ['GET /api/owner/computer-sessions', { body: computersFixture }],
    ]);
    renderApp('/business/settings');
    expect((await screen.findByTestId('stripe-status')).textContent).toContain('Not connected');
    expect(screen.getByText('Payments go straight to your own Stripe account. Stripe charges its fees there.')).toBeTruthy();
    await userEvent.click(screen.getByRole('button', { name: 'Connect Stripe' }));
    await waitFor(() => expect(leaveTo).toHaveBeenCalledWith(stripeLink.url));
    expect(api.calls.find((c) => c.method === 'POST')!.body).toEqual({ returnTo: 'web' });
  });

  it('says what happened once Stripe sends the owner back, and that disconnecting is on the iPhone', async () => {
    signedIn();
    mockApi([
      ['GET /api/owner/stripe', { body: stripeActive }],
      ['GET /api/owner/no-show-settings', { body: noShowSettings }],
      ['GET /api/owner/computer-sessions', { body: computersFixture }],
    ]);
    renderApp('/business/settings?stripe=active');
    expect((await screen.findByTestId('stripe-result')).textContent).toBe("You're connected. You can take card payments now.");
    expect((await screen.findByTestId('stripe-status')).textContent).toContain('Connected · Izzy Clipz Barbershop');
    expect(screen.getByText('To disconnect, use the iPhone app.')).toBeTruthy();
    expect(screen.getByRole('link', { name: /Open Stripe Dashboard/ }).getAttribute('href')).toBe('https://dashboard.stripe.com/');
  });

  it('says where things stand once the status is checked again, never naming a button that isn’t there', async () => {
    signedIn();
    // Back with ?stripe=notConnected, on a server whose Stripe isn't set up at all: no Connect Stripe to click.
    mockApi([
      ['GET /api/owner/stripe', { body: stripeOff }],
      ['GET /api/owner/no-show-settings', { body: noShowSettings }],
      ['GET /api/owner/computer-sessions', { body: computersFixture }],
    ]);
    renderApp('/business/settings?stripe=notConnected');
    expect((await screen.findByTestId('stripe-status')).textContent).toContain('Not set up on the server');
    await waitFor(() => expect(screen.getByTestId('stripe-result').textContent).toBe("Stripe isn't set up on the server, so it can't be connected yet."));
    expect(screen.queryByRole('button', { name: /Connect Stripe|Finish setting up/ })).toBeNull();
  });

  it('saves no-show protection, sending only what changed', async () => {
    signedIn();
    const api = mockApi([
      ['GET /api/owner/stripe', { body: stripeActive }],
      ['GET /api/owner/no-show-settings', { body: noShowSettings }],
      ['PATCH /api/owner/no-show-settings', ({ body }: ApiCall) => ({ body: { noShowSettings: { ...noShowSettings.noShowSettings, ...(body as object) } } })],
      ['GET /api/owner/computer-sessions', { body: computersFixture }],
    ]);
    renderApp('/business/settings');
    const section = await screen.findByTestId('no-show-settings');
    await userEvent.click(await within(section).findByRole('checkbox', { name: 'No-show protection' }));
    await userEvent.click(within(section).getByRole('radio', { name: 'Flat amount' }));
    const flat = within(section).getByLabelText('Flat fee');
    await userEvent.clear(flat);
    await userEvent.type(flat, '25');
    await userEvent.click(within(section).getByRole('button', { name: 'Save' }));
    expect((await within(section).findByTestId('no-show-saved')).textContent).toBe('Saved. New bookings use these settings.');
    expect(api.calls.find((c) => c.method === 'PATCH')!.body).toEqual({ enabled: true, feeMode: 'flat', flatCents: 2500 });
  });

  it('lists this computer and the others, and signs them all out', async () => {
    signedIn();
    const api = mockApi([
      ['GET /api/owner/stripe', { body: stripeActive }],
      ['GET /api/owner/no-show-settings', { body: noShowSettings }],
      ['GET /api/owner/computer-sessions', { body: computersFixture }],
      ['DELETE /api/owner/computer-sessions', { status: 200, body: {} }],
    ]);
    renderApp('/business/settings');
    expect((await screen.findByTestId('this-computer')).textContent).toContain('Chrome on Mac');
    expect((await screen.findAllByTestId('computer')).map((c) => c.querySelector('.biz-computer__name')?.textContent)).toEqual(['Edge on Windows']);
    await userEvent.click(screen.getByRole('button', { name: 'Sign out all computers' }));
    const dialog = screen.getByTestId('confirm-sign-out-computer');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Sign out all' }));
    expect(await screen.findByText('Every computer was signed out, this one too. Each needs a new code from the app to sign in again.')).toBeTruthy();
    expect(api.calls.some((c) => c.method === 'DELETE' && c.path === '/api/owner/computer-sessions')).toBe(true);
    expect(main().getByRole('heading', { level: 1 }).textContent).toBe('Izzy Clipz Business on your computer');
  });
});

describe('the shop’s policies', () => {
  it('are linked from every Business page, sign-in included, small and in a new tab', async () => {
    mockApi(TODAY_ROUTES);
    renderApp('/business');
    await screen.findByRole('heading', { level: 1, name: 'Izzy Clipz Business on your computer' });
    const policies = () => within(screen.getByRole('contentinfo')).getByRole('navigation', { name: 'Legal' });
    const expected = [
      ['Privacy Policy (opens in a new tab)', '/privacy'],
      ['Terms of Service (opens in a new tab)', '/terms'],
      ['Cancellation & No-Show Policy (opens in a new tab)', '/cancellation-policy'],
      ['Accessibility (opens in a new tab)', '/accessibility'],
    ];
    const links = () => within(policies()).getAllByRole('link');
    expect(links().map((a) => [a.textContent, a.getAttribute('href')])).toEqual(expected);
    expect(links().every((a) => a.getAttribute('target') === '_blank' && a.getAttribute('rel') === 'noopener')).toBe(true);

    signedIn();
    renderApp('/business/today');
    await screen.findAllByRole('navigation', { name: 'Legal' });
    const all = screen.getAllByRole('navigation', { name: 'Legal' });
    expect(within(all[all.length - 1]!).getAllByRole('link').map((a) => a.getAttribute('href'))).toEqual(expected.map(([, href]) => href));
  });
});
