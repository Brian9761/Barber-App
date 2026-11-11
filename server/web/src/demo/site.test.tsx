import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { api } from '../api/client';
import { DEMO_STORE_KEY, loadAppointments, saveAppointment } from '../lib/storage';
import { newToken } from '../lib/tokens';
import { FLOW45, renderApp } from '../test/api';

/** What the demo's "Forget me" says it did, as the Privacy Policy puts it: what it kept about the visitor goes; its offline copies of the site stay. */
const DEMO_FORGOTTEN = "Done. This computer no longer keeps your details, the demo's bookings or Izzy Clipz Business's sample shop. The copies of the site's own pages stay, so it still works offline.";

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
  it('says it’s the demo above its bookings, and that cancelling one sends the shop nothing', async () => {
    await bookInDemo();
    renderApp('/appointments');
    const card = await screen.findByTestId('appointment-card');
    const notice = screen.getByTestId('demo-notice');
    expect(notice.textContent).toBe("Demo version: bookings aren't sent to the shop. To book for real, call (442) 341-3053.");
    expect(notice.compareDocumentPosition(card) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();

    await userEvent.click(within(card).getByRole('button', { name: 'Cancel appointment' }));
    const dialog = screen.getByTestId('cancel-dialog');
    expect(dialog.textContent).toContain('This is the demo: nothing was sent to the shop.');
    expect(dialog.textContent).not.toContain('The shop sees it right away');
    await userEvent.click(within(dialog).getByTestId('confirm-cancel'));
    expect((await within(card).findByTestId('cancelled-notice')).textContent).toBe('Appointment cancelled. This is the demo: nothing was sent to the shop.');
    expect(within(card).getByTestId('appointment-status').textContent).toBe('Cancelled');
    expect(card.textContent).not.toContain('The shop sees it right away');
  });

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
    expect(screen.getByTestId('forget-computer').textContent).toContain("This computer can forget your details, the bookings made in the demo and Izzy Clipz Business's sample shop.");

    await userEvent.click(screen.getByRole('button', { name: 'Forget me on this computer' }));
    const dialog = screen.getByTestId('forget-dialog');
    expect(dialog.textContent).toContain(
      "This computer will forget your details, the bookings made in the demo and Izzy Clipz Business's sample shop. The copies of the site's own pages stay, so it still works offline.",
    );
    expect(dialog.textContent).not.toContain('stay booked');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Forget me' }));
    expect((await screen.findByTestId('forgotten-notice')).textContent).toBe(DEMO_FORGOTTEN);
    // Where the focus goes: the button that asked is gone.
    expect(document.activeElement).toBe(screen.getByTestId('forget-status'));
    expect(loadAppointments()).toEqual([]);
    expect(localStorage.getItem(DEMO_STORE_KEY)).toBeNull();
    // Nothing of the client's anywhere in this browser's storage.
    const everything = JSON.stringify({ ...localStorage }) + JSON.stringify({ ...sessionStorage }) + document.cookie;
    for (const detail of ['Private Person', '7605558271', 'private.person', 'gate code']) expect(everything, detail).not.toContain(detail);
  });

  it('asks its own stand-in to delete a card key this browser holds, with no request, and forgets it', async () => {
    // The demo never saves a card; should this browser hold a key anyway (say, from the real site
    // at this address), "Forget me" asks the demo's stand-in, which has no card behind it.
    const { CARD_KEY, loadCard } = await import('../lib/storage');
    localStorage.setItem(CARD_KEY, JSON.stringify({ token: newToken(), card: { brand: 'visa', last4: '4242', expMonth: 12, expYear: 2030 }, phone: '+17605558271' }));
    const deleteCard = vi.spyOn(api, 'deleteCard');
    renderApp('/appointments');
    await userEvent.click(screen.getByRole('button', { name: 'Forget me on this computer' }));
    await userEvent.click(within(screen.getByTestId('forget-dialog')).getByRole('button', { name: 'Forget me' }));
    expect((await screen.findByTestId('forgotten-notice')).textContent).toBe(DEMO_FORGOTTEN);
    expect(loadCard()).toBeNull();
    await vi.waitFor(() => expect(deleteCard).toHaveBeenCalledTimes(1));
    await expect(deleteCard.mock.results[0]!.value).rejects.toMatchObject({ code: 'not_found', status: 404 });
    // Nothing more to say: there was no card to delete.
    expect(screen.queryByTestId('card-removal')).toBeNull();
  });

  it('leaves nothing of the visit behind with “Forget me”: the Add to Home Screen bar’s count goes too', async () => {
    await bookInDemo();
    localStorage.setItem('izzy.visits.v1', '3');
    localStorage.setItem('izzy.installHint.v1', JSON.stringify({ dismissed: true, at: '2026-11-04T20:00:00Z' }));
    sessionStorage.setItem('izzy.visitCounted.v1', 'true');
    sessionStorage.setItem('izzy.lastBooked.v1', JSON.stringify('x'));
    localStorage.setItem('izzy.details.v1', JSON.stringify({ name: 'Private Person', phone: '(760) 555-8271', email: '' }));
    renderApp('/appointments');
    await screen.findByTestId('appointment-card');
    await userEvent.click(screen.getByRole('button', { name: 'Forget me on this computer' }));
    await userEvent.click(within(screen.getByTestId('forget-dialog')).getByRole('button', { name: 'Forget me' }));
    await screen.findByTestId('forgotten-notice');
    // What the client side of the demo kept is all gone ("Reset the demo" does the same for Izzy Clipz Business).
    expect(Object.keys(localStorage).filter((key) => key.startsWith('izzy.'))).toEqual([]);
    expect(Object.keys(sessionStorage).filter((key) => key.startsWith('izzy.'))).toEqual([]);
    expect(document.cookie).toBe('');
  });

  it('clears Izzy Clipz Business’s sample shop, its sign-in and the barber picked last too, and is offered after only looking around', async () => {
    // Someone who only opened the Business demo and looked around: no booking, no details.
    localStorage.setItem('izzy.demo.business.v1', JSON.stringify({ version: 1 }));
    localStorage.setItem('izzy.demo.business.session.v1', JSON.stringify({ token: 'x'.repeat(43), id: 'a', name: 'Chrome on Linux' }));
    localStorage.setItem('izzy.business.lastBarber.v1', JSON.stringify('carlos-rafael'));
    localStorage.setItem('izzy.visits.v1', '1');
    renderApp('/appointments');
    expect(await screen.findByText('No appointments booked on this computer yet.')).toBeTruthy();
    expect(screen.getByTestId('forget-computer').textContent).toContain("Izzy Clipz Business's sample shop");
    await userEvent.click(screen.getByRole('button', { name: 'Forget me on this computer' }));
    await userEvent.click(within(screen.getByTestId('forget-dialog')).getByRole('button', { name: 'Forget me' }));
    expect((await screen.findByTestId('forgotten-notice')).textContent).toBe(DEMO_FORGOTTEN);
    expect(Object.keys(localStorage).filter((key) => key.startsWith('izzy.'))).toEqual([]);
    expect(Object.keys(sessionStorage).filter((key) => key.startsWith('izzy.'))).toEqual([]);
    // Nothing left, so nothing more to forget.
    expect(screen.queryByTestId('forget-computer')).toBeNull();
  });
});

describe('Your details in the demo', () => {
  it('says the details stay on this device and go nowhere, and Remember me says nothing of a card', async () => {
    const { EMPTY_DRAFT, saveDraft } = await import('../booking/flow');
    const { days } = await api.availability({ offeringId: FLOW45 }, '2026-11-06', 1);
    saveDraft({ ...EMPTY_DRAFT, serviceId: 'haircut', choice: { kind: 'offering', offeringId: FLOW45 }, start: days[0]!.slots[0]!.start });
    renderApp('/book/details');
    await screen.findByRole('heading', { level: 1, name: 'Your details' });
    expect(screen.getByText("This is the demo: your details stay on this computer and aren't sent anywhere.")).toBeTruthy();
    expect(screen.getByTestId('details-privacy').textContent).toBe(
      'Demo version: your name and number stay on this computer. Nothing is sent to Izzy Clipz or anywhere else.',
    );
    const remember = screen.getByRole('checkbox', { name: 'Remember me on this computer' });
    const hint = document.getElementById(remember.getAttribute('aria-describedby')!)!;
    expect(hint.textContent).toBe('Your name, number and email fill in next time you book here. Leave it off on a shared computer.');
    expect(document.body.textContent).not.toMatch(/card you add|sent only to/);
    // The number's hint doesn't say the shop will reach them: nothing reaches the shop.
    expect(screen.getByText('A US number, like (442) 555-0123.')).toBeTruthy();
    expect(document.body.textContent).not.toMatch(/so the shop can reach you/);
  });

  it('forgets the remembered client without mentioning a saved card, which the demo never keeps', async () => {
    const { EMPTY_DRAFT, saveDraft } = await import('../booking/flow');
    const { rememberDetails } = await import('../lib/storage');
    rememberDetails({ name: 'Demo Person', phone: '(442) 555-0123', email: '' });
    const { days } = await api.availability({ offeringId: FLOW45 }, '2026-11-06', 1);
    saveDraft({ ...EMPTY_DRAFT, serviceId: 'haircut', choice: { kind: 'offering', offeringId: FLOW45 }, start: days[0]!.slots[0]!.start });
    renderApp('/book/details');
    await userEvent.click(await screen.findByRole('button', { name: 'Not you? Forget me on this computer' }));
    expect(screen.getByText('Done. This computer no longer keeps those details.')).toBeTruthy();
    expect(document.body.textContent).not.toMatch(/saved card/);
  });
});
