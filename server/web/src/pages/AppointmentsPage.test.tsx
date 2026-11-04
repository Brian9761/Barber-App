import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, it, vi } from 'vitest';
import cancelledLate from '../../../test/fixtures/contract/appointment-cancelled-late.json';
import cancelledFixture from '../../../test/fixtures/contract/appointment-cancelled.json';
import lateCancelFee from '../../../test/fixtures/contract/errors/late_cancel_fee.json';
import notCancellable from '../../../test/fixtures/contract/errors/not_cancellable.json';
import type { Appointment } from '../api/types';
import cardSaved from '../../../test/fixtures/contract/card-saved.json';
import {
  APPOINTMENTS_KEY,
  carriedAppointments,
  loadAppointments,
  loadCard,
  loadRememberedDetails,
  rememberDetails,
  saveAppointment,
  storeCard,
} from '../lib/storage';
import { newToken } from '../lib/tokens';
import { apiError, fixtureAppointment, mockApi, renderApp } from '../test/api';
import { USER_AGENTS } from '../test/pwa';
import { times } from '../test/text';

// Flowxbori's haircut at 10 AM on Tuesday, November 3, 2026 ($35, Visa on file, 1-hour window).
const MANAGE = 'fixture-manage-token-0001xxxxxxxxxxxxxxxxxx';
const CANCEL_PATH = `/api/appointments/${fixtureAppointment.id}/cancel`;
const cancelledByClient = (at: string): Appointment => ({
  ...fixtureAppointment,
  status: 'cancelled',
  cancelledBy: 'customer',
  noShowFee: { ...fixtureAppointment.noShowFee!, customerCancelledAt: at },
});

function at(iso: string) {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(new Date(iso));
}

afterEach(() => {
  vi.useRealTimers();
});

async function openCancel() {
  await userEvent.click(await screen.findByRole('button', { name: 'Cancel appointment' }));
  return screen.getByTestId('cancel-dialog');
}

describe('My appointments', () => {
  it('lists what was booked on this computer, checked with the shop', async () => {
    at('2026-11-02T17:00:00Z');
    saveAppointment(fixtureAppointment, MANAGE);
    const api = mockApi([['GET /api/appointments/*', { body: { appointment: fixtureAppointment } }]]);
    renderApp('/appointments');

    const card = await screen.findByTestId('appointment-card');
    expect(within(card).getByTestId('appointment-status').textContent).toBe('Next appointment');
    expect(within(card).getByRole('heading', { level: 3 }).textContent).toBe(times('Tue, Nov 3 at 10 AM'));
    expect(card.textContent).toContain('Haircut with Flowxbori');
    expect(card.textContent).toContain('$35 · 45 min · Pay at the shop');
    expect(card.textContent).toContain('Card on file: Visa •••• 4242');
    // The demo's notice is the demo's alone.
    expect(screen.queryByTestId('demo-notice')).toBeNull();
    await waitFor(() => expect(api.calls).toHaveLength(1));
    expect(api.calls[0]).toMatchObject({ method: 'GET', path: `/api/appointments/${fixtureAppointment.id}`, headers: { 'x-manage-token': MANAGE } });
  });

  it('shows when the shop cancelled it, with a way to book another time', async () => {
    at('2026-11-02T17:00:00Z');
    saveAppointment(fixtureAppointment, MANAGE);
    const byShop = { ...cancelledFixture.appointment, id: fixtureAppointment.id, cancelledBy: 'shop' } as Appointment;
    mockApi([['GET /api/appointments/*', { body: { appointment: byShop } }]]);
    renderApp('/appointments');

    await waitFor(() => expect(screen.getByTestId('appointment-status').textContent).toBe('Cancelled by the shop'));
    expect(screen.getByText('The shop cancelled this appointment. Book another time, or call the shop.')).toBeTruthy();
    expect(screen.getByRole('link', { name: 'Book another time' }).getAttribute('href')).toBe('/book?service=haircut');
  });

  it('names the device it’s on: this phone, this computer', async () => {
    vi.spyOn(navigator, 'userAgent', 'get').mockReturnValue(USER_AGENTS.iphoneSafari);
    mockApi([]);
    renderApp('/appointments');
    expect(screen.getByText('The appointments booked on this phone. Check them, add them to your calendar, or cancel.')).toBeTruthy();
    expect(screen.getByRole('heading', { name: 'No appointments booked on this phone yet.' })).toBeTruthy();
  });

  it('says there’s nothing yet, and how to book', async () => {
    mockApi([]);
    renderApp('/appointments');
    expect(screen.getByRole('heading', { level: 1 }).textContent).toBe('My appointments');
    await waitFor(() => expect(document.title).toBe('My appointments · Izzy Clipz Barbershop'));
    expect(screen.getByRole('heading', { name: 'No appointments booked on this computer yet.' })).toBeTruthy();
    expect(within(screen.getByRole('main')).getByRole('link', { name: 'Book an appointment' }).getAttribute('href')).toBe('/book');
  });
});

describe('cancelling', () => {
  it('is free more than an hour before: one question, no fee', async () => {
    at('2026-11-03T16:00:00Z');
    saveAppointment(fixtureAppointment, MANAGE);
    const api = mockApi([
      ['GET /api/appointments/*', { body: { appointment: fixtureAppointment } }],
      ['POST /api/appointments/*', { body: { appointment: cancelledByClient('2026-11-03T16:00:00Z') } }],
    ]);
    renderApp('/appointments');

    const dialog = await openCancel();
    expect(within(dialog).getByRole('heading').textContent).toBe('Cancel this appointment?');
    expect(within(dialog).queryByTestId('late-cancel-warning')).toBeNull();
    expect(dialog.textContent).toContain(times('Haircut with Flowxbori, Tuesday, November 3 at 10 AM. The shop sees it right away.'));
    // The safe answer comes first.
    expect(within(dialog).getAllByRole('button').map((b) => b.textContent)).toEqual(['Keep appointment', 'Cancel appointment']);

    await userEvent.click(within(dialog).getByTestId('confirm-cancel'));
    expect((await screen.findByTestId('cancelled-notice')).textContent).toBe('Appointment cancelled. The shop sees it right away.');
    const [cancel] = api.calls.filter((c) => c.method === 'POST');
    expect(cancel).toMatchObject({ path: CANCEL_PATH, headers: { 'x-manage-token': MANAGE }, body: undefined });
    expect(screen.getByTestId('appointment-status').textContent).toBe('Cancelled');
    expect(loadAppointments()[0]!.appointment.status).toBe('cancelled');
  });

  it('warns about the fee inside the window, and accepts it only after the client saw it', async () => {
    at('2026-11-03T17:30:00Z');
    saveAppointment(fixtureAppointment, MANAGE);
    const api = mockApi([
      ['GET /api/appointments/*', { body: { appointment: fixtureAppointment } }],
      ['POST /api/appointments/*', { body: { appointment: cancelledByClient('2026-11-03T17:30:00Z') } }],
    ]);
    renderApp('/appointments');

    const dialog = await openCancel();
    expect(within(dialog).getByTestId('late-cancel-warning').textContent?.trim()).toBe(lateCancelFee.error.message);
    await userEvent.click(within(dialog).getByTestId('confirm-cancel'));
    await screen.findByText('Appointment cancelled. The shop sees it right away.');
    const [cancel] = api.calls.filter((c) => c.method === 'POST');
    expect(cancel).toMatchObject({ path: CANCEL_PATH, body: { acceptLateCancelFee: true } });
  });

  it('asks again with the shop’s warning when the shop’s clock says it’s late', async () => {
    at('2026-11-03T17:00:00Z'); // exactly an hour before: free here, but the minute turns
    saveAppointment(fixtureAppointment, MANAGE);
    const api = mockApi([
      ['GET /api/appointments/*', { body: { appointment: fixtureAppointment } }],
      ['POST /api/appointments/*', { body: { appointment: cancelledLate.appointment } }],
    ]);
    api.once('POST /api/appointments/*', apiError(lateCancelFee.error.code, lateCancelFee.error.message, 409));
    renderApp('/appointments');

    let dialog = await openCancel();
    expect(within(dialog).queryByTestId('late-cancel-warning')).toBeNull();
    await userEvent.click(within(dialog).getByTestId('confirm-cancel'));

    dialog = await screen.findByTestId('cancel-dialog');
    await waitFor(() => expect(within(dialog).getByTestId('late-cancel-warning').textContent?.trim()).toBe(lateCancelFee.error.message));
    await userEvent.click(within(dialog).getByTestId('confirm-cancel'));
    await screen.findByText('Appointment cancelled. The shop sees it right away.');
    expect(api.calls.filter((c) => c.method === 'POST').map((c) => c.body)).toEqual([undefined, { acceptLateCancelFee: true }]);
  });

  it('keeps the appointment when the client says so', async () => {
    at('2026-11-03T17:30:00Z');
    saveAppointment(fixtureAppointment, MANAGE);
    const api = mockApi([['GET /api/appointments/*', { body: { appointment: fixtureAppointment } }]]);
    renderApp('/appointments');

    const dialog = await openCancel();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Keep appointment' }));
    expect(within(dialog).queryByRole('heading')).toBeNull();
    expect(api.calls.filter((c) => c.method === 'POST')).toEqual([]);
    expect(screen.getByTestId('appointment-status').textContent).toBe('Next appointment');
  });

  it('shows how it is now when it changed at the shop', async () => {
    at('2026-11-03T16:00:00Z');
    saveAppointment(fixtureAppointment, MANAGE);
    const api = mockApi([
      ['GET /api/appointments/*', { body: { appointment: fixtureAppointment } }],
      ['POST /api/appointments/*', apiError(notCancellable.error.code, notCancellable.error.message, 409)],
    ]);
    renderApp('/appointments');
    await waitFor(() => expect(api.calls).toHaveLength(1));
    api.once('GET /api/appointments/*', { body: { appointment: { ...fixtureAppointment, status: 'cancelled', cancelledBy: 'shop' } } });

    await userEvent.click(within(await openCancel()).getByTestId('confirm-cancel'));
    expect((await screen.findByRole('alert')).textContent).toContain(notCancellable.error.message);
    expect(screen.getByTestId('appointment-status').textContent).toBe('Cancelled by the shop');
  });
});

describe('on a shared computer', () => {
  it('keeps no name, number, email or note with the appointments', () => {
    const booked: Appointment = { ...fixtureAppointment, note: 'Low fade, keep the top long' };
    saveAppointment(booked, MANAGE);
    const [stored] = JSON.parse(localStorage.getItem(APPOINTMENTS_KEY)!) as { appointment: Record<string, unknown> }[];
    expect(stored!.appointment).not.toHaveProperty('customer');
    expect(stored!.appointment).not.toHaveProperty('note');
    expect(stored!.appointment).toMatchObject({ id: fixtureAppointment.id, serviceName: 'Haircut', barberName: 'Flowxbori' });
  });

  it('forgets the client here when asked, after saying the appointments stay booked', async () => {
    at('2026-11-02T17:00:00Z');
    saveAppointment(fixtureAppointment, MANAGE);
    rememberDetails({ name: 'Ana Flores', phone: '(442) 555-0123', email: '' });
    storeCard({ token: newToken(), card: cardSaved.card, phone: '+14425550123' }, true);
    const api = mockApi([['GET /api/appointments/*', { body: { appointment: fixtureAppointment } }]]);
    renderApp('/appointments');
    await screen.findByTestId('appointment-card');

    await userEvent.click(screen.getByRole('button', { name: 'Forget me on this computer' }));
    const dialog = screen.getByTestId('forget-dialog');
    expect(dialog.textContent).toContain('Your appointments stay booked. To change one later, call the shop at (442) 341-3053.');
    // The safe answer comes first.
    await userEvent.click(within(dialog).getByRole('button', { name: 'Keep everything' }));
    expect(loadAppointments()).toHaveLength(1);

    await userEvent.click(screen.getByRole('button', { name: 'Forget me on this computer' }));
    await userEvent.click(within(screen.getByTestId('forget-dialog')).getByRole('button', { name: 'Forget me' }));
    expect((await screen.findByTestId('forgotten-notice')).textContent).toContain('Your appointments are still booked with the shop.');
    expect(screen.getByText('No appointments booked on this computer yet.')).toBeTruthy();
    expect(loadAppointments()).toEqual([]);
    expect(loadRememberedDetails()).toBeNull();
    expect(loadCard()).toBeNull();
    expect(carriedAppointments()).toEqual([]);
    // Nothing was cancelled.
    expect(api.calls.filter((c) => c.method === 'POST')).toEqual([]);
  });

  it('doesn’t offer to forget anything when nothing is kept', () => {
    renderApp('/appointments');
    expect(screen.getByText('No appointments booked on this computer yet.')).toBeTruthy();
    expect(screen.queryByTestId('forget-computer')).toBeNull();
  });
});

describe('in the app added to the Home Screen', () => {
  // On an iPhone the app has website data of its own, with only the cookies copied from Safari.
  it('brings in the appointments booked in the browser before, checked with the shop', async () => {
    at('2026-11-02T17:00:00Z');
    saveAppointment(fixtureAppointment, MANAGE);
    localStorage.clear();
    const api = mockApi([['GET /api/appointments/*', { body: { appointment: fixtureAppointment } }]]);
    renderApp('/appointments');

    const card = await screen.findByTestId('appointment-card');
    expect(within(card).getByTestId('appointment-status').textContent).toBe('Next appointment');
    expect(card.textContent).toContain('Haircut with Flowxbori');
    expect(loadAppointments().map((s) => [s.id, s.manageToken])).toEqual([[fixtureAppointment.id, MANAGE]]);
    // Looked up once, with its own token.
    await waitFor(() => expect(api.calls).toHaveLength(1));
    expect(api.calls[0]).toMatchObject({ path: `/api/appointments/${fixtureAppointment.id}`, headers: { 'x-manage-token': MANAGE } });
  });

  it('lets go of one the shop doesn’t know any more', async () => {
    at('2026-11-02T17:00:00Z');
    saveAppointment(fixtureAppointment, MANAGE);
    localStorage.clear();
    mockApi([['GET /api/appointments/*', apiError('not_found', "We couldn't find that appointment.", 404)]]);
    renderApp('/appointments');
    await waitFor(() => expect(carriedAppointments()).toEqual([]));
    expect(screen.getByText('No appointments booked on this computer yet.')).toBeTruthy();
    expect(loadAppointments()).toEqual([]);
  });

  it('says it’s offline when the ones on their way in can’t be checked yet', async () => {
    at('2026-11-02T17:00:00Z');
    saveAppointment(fixtureAppointment, MANAGE);
    localStorage.clear();
    vi.spyOn(navigator, 'onLine', 'get').mockReturnValue(false);
    mockApi([]);
    renderApp('/appointments');
    expect(await screen.findByTestId('appointments-offline')).toBeTruthy();
    expect(carriedAppointments()).toHaveLength(1);
  });
});

describe('offline', () => {
  it('shows nothing it can’t check with the shop, says so, and checks once the connection is back', async () => {
    at('2026-11-02T17:00:00Z');
    saveAppointment(fixtureAppointment, MANAGE);
    const onLine = vi.spyOn(navigator, 'onLine', 'get').mockReturnValue(false);
    const api = mockApi([['GET /api/appointments/*', { body: { appointment: cancelledByClient('2026-11-02T16:00:00Z') } }]]);
    renderApp('/appointments');

    const offline = await screen.findByTestId('appointments-offline');
    expect(offline.textContent).toContain("You're offline.");
    expect(within(offline).getByRole('link', { name: '(442) 341-3053' }).getAttribute('href')).toBe('tel:+14423413053');
    expect(screen.queryByTestId('appointment-card')).toBeNull();
    expect(api.calls).toHaveLength(0);

    onLine.mockReturnValue(true);
    window.dispatchEvent(new Event('online'));
    const card = await screen.findByTestId('appointment-card');
    expect(within(card).getByTestId('appointment-status').textContent).toBe('Cancelled');
    expect(screen.queryByTestId('appointments-offline')).toBeNull();
  });

  it('says so too when the shop can’t be reached, without the status it last heard', async () => {
    at('2026-11-02T17:00:00Z');
    saveAppointment(fixtureAppointment, MANAGE);
    const api = mockApi([['GET /api/appointments/*', 'offline']]);
    renderApp('/appointments');
    expect(await screen.findByTestId('appointments-offline')).toBeTruthy();
    expect(screen.queryByTestId('appointment-card')).toBeNull();

    // Try again, and the shop answers this time.
    api.once('GET /api/appointments/*', { body: { appointment: fixtureAppointment } });
    await userEvent.click(screen.getByRole('button', { name: 'Try again' }));
    expect(within(await screen.findByTestId('appointment-card')).getByTestId('appointment-status').textContent).toBe('Next appointment');
  });
});
