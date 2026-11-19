import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { renderApp } from '../test/api';
import { session } from './session';

// Izzy Clipz Business as the demo build has it: every call answered in the browser by the demo's
// stand-in for the shop (vite.config.ts swaps src/business/api/backend.ts for src/demo/owner/backend.ts).
vi.mock('./api/backend', async () => {
  const { createDemoOwnerApi } = await import('../demo/owner/api');
  return { backend: createDemoOwnerApi({ latencyMs: 0 }) };
});

beforeEach(() => {
  vi.stubEnv('VITE_DEMO_MODE', '1');
  session.reset();
  vi.stubGlobal('fetch', vi.fn(() => Promise.reject(new Error('The demo made a network request'))));
});

afterEach(() => {
  session.reset();
});

describe('Reset the demo', () => {
  it('clears what Izzy Clipz Business kept on this computer in the demo: the sample shop as changed, and the barber picked last', async () => {
    renderApp('/business');
    await userEvent.click(await screen.findByRole('button', { name: 'Open the Business demo' }));
    await screen.findByTestId('today-page');
    localStorage.setItem('izzy.business.lastBarber.v1', JSON.stringify('carlos-rafael'));
    renderApp('/business/settings');
    const demo = await screen.findAllByTestId('demo-settings');
    await userEvent.click(within(demo[demo.length - 1]!).getByRole('button', { name: 'Reset the demo' }));
    const dialogs = screen.getAllByTestId('confirm-reset-demo');
    await userEvent.click(within(dialogs[dialogs.length - 1]!).getByRole('button', { name: 'Reset the demo' }));
    expect((await screen.findAllByTestId('demo-reset')).length).toBeGreaterThan(0);
    expect(localStorage.getItem('izzy.business.lastBarber.v1')).toBeNull();
  });

  it('brings back the sample computer signed out in Settings, as its message says the demo is back as it started', async () => {
    renderApp('/business');
    await userEvent.click(await screen.findByRole('button', { name: 'Open the Business demo' }));
    await screen.findByTestId('today-page');
    renderApp('/business/settings');
    const others = async () => {
      const lists = await screen.findAllByTestId('other-computers');
      return lists[lists.length - 1]!;
    };
    const sampleButton = { name: 'Sign out Safari on iPad (sample)' };
    await userEvent.click(await within(await others()).findByRole('button', sampleButton));
    const confirms = screen.getAllByTestId('confirm-sign-out-computer');
    await userEvent.click(within(confirms[confirms.length - 1]!).getByRole('button', { name: 'Sign out' }));
    expect(await within(await others()).findByText('Signed out Safari on iPad (sample).')).toBeTruthy();
    expect(within(await others()).queryByRole('button', sampleButton)).toBeNull();

    const demo = screen.getAllByTestId('demo-settings');
    await userEvent.click(within(demo[demo.length - 1]!).getByRole('button', { name: 'Reset the demo' }));
    const dialogs = screen.getAllByTestId('confirm-reset-demo');
    await userEvent.click(within(dialogs[dialogs.length - 1]!).getByRole('button', { name: 'Reset the demo' }));
    const done = await screen.findAllByTestId('demo-reset');
    expect(done[done.length - 1]!.textContent).toBe('The demo is back as it started: the sample shop, Stripe not connected.');
    // Back in the list, once, with its own Sign out.
    expect(await within(await others()).findAllByRole('button', sampleButton)).toHaveLength(1);
  });
});

describe('No-show protection in the demo', () => {
  it('says plainly that client bookings in the demo never ask for a card, so the notice doesn’t show there', async () => {
    renderApp('/business');
    await userEvent.click(await screen.findByRole('button', { name: 'Open the Business demo' }));
    await screen.findByTestId('today-page');
    renderApp('/business/settings');
    const sections = await screen.findAllByTestId('no-show-settings');
    const section = sections[sections.length - 1]!;
    // Before Stripe is connected, connecting it isn't what makes clients get asked for a card: nothing does, in the demo.
    expect((await within(section).findByTestId('no-show-stripe-note')).textContent).toBe(
      "In the demo, client bookings never ask for a card, with Stripe connected or not, so the fee notice doesn't show there.",
    );
    await userEvent.click(within(section).getByRole('checkbox', { name: 'No-show protection' }));
    expect(within(section).getByTestId('client-view-note').textContent).toBe(
      "For the example haircut. On the real site, the notice shows while clients pick a day and time and on Review, and they agree to the policy before booking. In the demo, client bookings never ask for a card, so it doesn't show there.",
    );
    await userEvent.click(within(section).getByRole('button', { name: 'Save' }));
    expect((await within(section).findByTestId('no-show-saved')).textContent).toBe(
      "Saved. In the demo, client bookings never ask for a card, so the fee notice doesn't show there.",
    );
    expect(section.textContent).not.toContain('New bookings use these settings');
  });
});
