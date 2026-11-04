import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, it, vi } from 'vitest';
import cancelledLate from '../../../test/fixtures/contract/appointment-cancelled-late.json';
import cancelledFixture from '../../../test/fixtures/contract/appointment-cancelled.json';
import lateCancelFee from '../../../test/fixtures/contract/errors/late_cancel_fee.json';
import notCancellable from '../../../test/fixtures/contract/errors/not_cancellable.json';
import type { Appointment } from '../api/types';
import { loadAppointments, saveAppointment } from '../lib/storage';
import { apiError, fixtureAppointment, mockApi, renderApp } from '../test/api';

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
    expect(within(card).getByRole('heading', { level: 3 }).textContent).toBe('Tue, Nov 3 at 10 AM');
    expect(card.textContent).toContain('Haircut with Flowxbori');
    expect(card.textContent).toContain('$35 · 45 min · Pay at the shop');
    expect(card.textContent).toContain('Card on file: Visa •••• 4242');
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
    expect(dialog.textContent).toContain('Haircut with Flowxbori, Tuesday, November 3 at 10 AM. The shop sees it right away.');
    // The safe answer comes first.
    expect(within(dialog).getAllByRole('button').map((b) => b.textContent)).toEqual(['Keep appointment', 'Cancel appointment']);

    await userEvent.click(within(dialog).getByTestId('confirm-cancel'));
    expect(await screen.findByText('Appointment cancelled. The shop sees it right away.')).toBeTruthy();
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
