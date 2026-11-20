import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter, useLocation, useNavigate, type Location, type NavigateFunction } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import created from '../../../test/fixtures/contract/appointment-created.json';
import { App, ROUTER_FUTURE } from '../App';
import { CatalogProvider } from '../data/catalog';
import { loadAppointments, type ListedAppointment } from '../lib/storage';
import { catalog, FLOW45, mockApi, policyNotRequired } from '../test/api';
import { EMPTY_DRAFT, saveDraft } from './flow';
import { forgetLastBooked, lastBooked, rememberLastBooked } from './lastBooked';

// "You're booked" shows the appointment from what this browser keeps (the list of appointments,
// which "Forget me" clears), never from the browser's history: the booking's own answer has the
// client's name, number, email and note, and the history keeps whatever a page puts in it out of
// "Forget me"'s reach. So after "Forget me", Back or a reload doesn't show the booking.

const START = '2026-11-03T18:00:00Z'; // Tuesday 10 AM in the shop
const details = { name: 'Ana Flores', phone: '(442) 555-0123', email: 'ana@example.com', note: 'Low fade, please.', remember: false };

/** The site at `path`, with the router's location and navigate at hand, as the browser's Back button would use them. */
function renderSite(path: string): { location: () => Location; navigate: () => NavigateFunction } {
  let location: Location | null = null;
  let navigate: NavigateFunction | null = null;
  function Probe() {
    location = useLocation();
    navigate = useNavigate();
    return null;
  }
  render(
    <MemoryRouter initialEntries={[path]} future={ROUTER_FUTURE}>
      <CatalogProvider initial={catalog}>
        <App />
        <Probe />
      </CatalogProvider>
    </MemoryRouter>,
  );
  return { location: () => location!, navigate: () => navigate! };
}

/** Everything in the router's state (what the browser's history keeps for this page), as text. */
function historyText(location: Location): string {
  return JSON.stringify(location.state ?? null);
}

async function book(): Promise<{ location: () => Location; navigate: () => NavigateFunction }> {
  saveDraft({ ...EMPTY_DRAFT, serviceId: 'haircut', choice: { kind: 'offering', offeringId: FLOW45 }, start: START, details });
  const site = renderSite('/book/review');
  await waitFor(() => expect((screen.getByTestId('book-button') as HTMLButtonElement).disabled).toBe(false));
  await userEvent.click(screen.getByTestId('book-button'));
  expect((await screen.findByTestId('booked-title')).textContent).toBe("You're booked");
  return site;
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(new Date('2026-11-03T16:00:00Z')); // 8 AM, two hours before
});

afterEach(() => {
  vi.useRealTimers();
  vi.restoreAllMocks();
  forgetLastBooked();
});

describe('“You’re booked”', () => {
  it('shows the booking from what this browser keeps, and puts nothing of the client’s in the browser’s history', async () => {
    mockApi([
      ['GET /api/no-show-policy', { body: policyNotRequired }],
      ['POST /api/appointments', { status: 201, body: { ...created, appointment: { ...created.appointment, customer: { name: 'Ana Flores', phone: '+14425550123', email: 'ana@example.com' }, note: 'Low fade, please.' } } }],
    ]);
    const { location } = await book();
    expect(location().pathname).toBe('/book/confirmed');
    // Nothing in the history: not the appointment, and none of Ana's details.
    expect(location().state ?? null).toBeNull();
    for (const personal of ['Ana Flores', '4425550123', 'ana@example.com', 'Low fade']) expect(historyText(location())).not.toContain(personal);
    // The booking, from the list this browser keeps (without her details either).
    const summary = within(screen.getByTestId('booked-summary'));
    expect(summary.getByText(created.appointment.serviceName)).toBeTruthy();
    expect(summary.getByText(created.appointment.barberName)).toBeTruthy();
    expect(loadAppointments().map((s) => s.id)).toEqual([created.appointment.id]);
    expect(JSON.stringify(loadAppointments())).not.toContain('Ana Flores');
    expect(lastBooked()).toMatchObject({ saved: true, appointment: { id: created.appointment.id } });
    expect(screen.queryByText('Write this one down')).toBeNull();
  });

  it('isn’t shown again after “Forget me”: Back and a reload open My appointments', async () => {
    mockApi([
      ['GET /api/no-show-policy', { body: policyNotRequired }],
      ['POST /api/appointments', { status: 201, body: created }],
      ['GET /api/appointments/*', { body: { appointment: created.appointment } }],
    ]);
    const { location, navigate } = await book();
    // Manage or cancel, then "Forget me on this computer".
    await userEvent.click(screen.getByRole('link', { name: 'Manage or cancel' }));
    await screen.findByTestId('appointment-card');
    await userEvent.click(screen.getByRole('button', { name: 'Forget me on this computer' }));
    await userEvent.click(within(screen.getByTestId('forget-dialog')).getByRole('button', { name: 'Forget me' }));
    await screen.findByTestId('forgotten-notice');
    expect(lastBooked()).toBeNull();

    // Back, to where "You're booked" was: My appointments instead, and nothing of the booking.
    navigate()(-1);
    await waitFor(() => expect(location().pathname).toBe('/appointments'));
    expect(screen.queryByTestId('booked-title')).toBeNull();
    expect(screen.queryByTestId('booked-summary')).toBeNull();
  });

  it('isn’t shown after a reload once “Forget me” has cleared what the tab kept', async () => {
    mockApi([
      ['GET /api/no-show-policy', { body: policyNotRequired }],
      ['POST /api/appointments', { status: 201, body: created }],
      ['GET /api/appointments/*', { body: { appointment: created.appointment } }],
    ]);
    await book();
    // A reload before: the same booking, from what this browser keeps.
    document.body.innerHTML = '';
    renderSite('/book/confirmed');
    expect((await screen.findByTestId('booked-title')).textContent).toBe("You're booked");
    // "Forget me" (what My appointments' button clears), then a reload: My appointments.
    localStorage.clear();
    forgetLastBooked();
    document.body.innerHTML = '';
    const reloaded = renderSite('/book/confirmed');
    await waitFor(() => expect(reloaded.location().pathname).toBe('/appointments'));
    expect(screen.queryByTestId('booked-title')).toBeNull();
  });

  it('shows a booking this browser couldn’t keep from this page only, says to write it down, and forgets it with “Forget me”', async () => {
    // The list of appointments won't save (this browser blocks the site's storage for it).
    const setItem = Storage.prototype.setItem;
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(function (this: Storage, key: string, value: string) {
      if (key === 'izzy.appointments.v1') throw new DOMException('Full', 'QuotaExceededError');
      setItem.call(this, key, value);
    });
    mockApi([
      ['GET /api/no-show-policy', { body: policyNotRequired }],
      ['POST /api/appointments', { status: 201, body: created }],
    ]);
    const { location } = await book();
    expect(screen.getByText('Write this one down')).toBeTruthy();
    expect(within(screen.getByTestId('booked-summary')).getByText(created.appointment.serviceName)).toBeTruthy();
    expect(location().state ?? null).toBeNull();
    expect(lastBooked()).toMatchObject({ saved: false, appointment: { id: created.appointment.id } });
    // Held without the client's own details.
    expect(lastBooked()!.appointment).not.toHaveProperty('customer');
    expect(lastBooked()!.appointment).not.toHaveProperty('note');

    // "Forget me" forgets it here too.
    forgetLastBooked();
    expect(lastBooked()).toBeNull();
    document.body.innerHTML = '';
    const again = renderSite('/book/confirmed');
    await waitFor(() => expect(again.location().pathname).toBe('/appointments'));
  });

  it('holds a booking in this page only when this browser couldn’t keep it, never one it kept', () => {
    rememberLastBooked(created.appointment.id);
    // Kept nowhere: nothing to show.
    expect(lastBooked()).toBeNull();
    rememberLastBooked(created.appointment.id, created.appointment as unknown as ListedAppointment);
    expect(lastBooked()).toMatchObject({ saved: false });
    // Another booking since: not that one.
    rememberLastBooked('00000000-0000-4000-8000-00000000ffff');
    expect(lastBooked()).toBeNull();
  });
});
