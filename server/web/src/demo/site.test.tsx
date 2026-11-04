import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { api } from '../api/client';
import { DEMO_STORE_KEY, loadAppointments, saveAppointment } from '../lib/storage';
import { newToken } from '../lib/tokens';
import { FLOW45, renderApp } from '../test/api';

// The site as the demo build has it: every API call answered in the browser by the demo's
// stand-in for the shop (vite.config.ts swaps src/api/backend.ts for src/demo/backend.ts).
vi.mock('../api/backend', async () => {
  const { createDemoApi } = await import('./api');
  return { backend: createDemoApi({ latencyMs: 0 }) };
});

let fetchMock: ReturnType<typeof vi.fn>;
beforeEach(() => {
  vi.stubEnv('VITE_DEMO_MODE', '1');
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(new Date('2026-11-04T20:10:00Z')); // Wednesday, 12:10 PM at the shop
  // Nothing goes on the network.
  fetchMock = vi.fn(() => Promise.reject(new Error('The demo made a network request')));
  vi.stubGlobal('fetch', fetchMock);
});

afterEach(() => {
  vi.useRealTimers();
  expect(fetchMock).not.toHaveBeenCalled();
});

/** A booking in the demo, as the Review step makes it: kept by the stand-in, listed on My appointments. */
async function bookInDemo(customer = { name: 'Private Person', phone: '(760) 555-8271', email: 'private.person@example.com' }) {
  const { days } = await api.availability({ offeringId: FLOW45 }, '2026-11-06', 1);
  const token = newToken();
  const { appointment } = await api.book({ target: { offeringId: FLOW45 }, start: days[0]!.slots[0]!.start, customer, note: 'gate code 4321' }, token);
  saveAppointment(appointment, token);
  return appointment;
}

describe('My appointments in the demo', () => {
  it('still lists the bookings made in it offline: they live in this browser', async () => {
    await bookInDemo();
    vi.spyOn(navigator, 'onLine', 'get').mockReturnValue(false);
    renderApp('/appointments');
    const card = await screen.findByTestId('appointment-card');
    expect(within(card).getByTestId('appointment-status').textContent).toBe('Next appointment');
    expect(screen.queryByTestId('appointments-offline')).toBeNull();
  });

  it('forgets every booking made in it with “Forget me”, the client’s details with them', async () => {
    await bookInDemo();
    expect(localStorage.getItem(DEMO_STORE_KEY)).not.toBeNull();
    renderApp('/appointments');
    await screen.findByTestId('appointment-card');
    expect(screen.getByTestId('forget-computer').textContent).toContain('the bookings made in the demo');

    await userEvent.click(screen.getByRole('button', { name: 'Forget me on this computer' }));
    const dialog = screen.getByTestId('forget-dialog');
    expect(dialog.textContent).toContain('This computer will forget your name and number, and the bookings made in the demo.');
    expect(dialog.textContent).not.toContain('stay booked');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Forget me' }));
    expect((await screen.findByTestId('forgotten-notice')).textContent).toBe('Done. This computer no longer keeps your details or the bookings made in the demo.');
    expect(loadAppointments()).toEqual([]);
    expect(localStorage.getItem(DEMO_STORE_KEY)).toBeNull();
    // Nothing of the client's anywhere in this browser's storage.
    const everything = JSON.stringify({ ...localStorage }) + JSON.stringify({ ...sessionStorage }) + document.cookie;
    for (const detail of ['Private Person', '7605558271', 'private.person', 'gate code']) expect(everything, detail).not.toContain(detail);
  });
});
