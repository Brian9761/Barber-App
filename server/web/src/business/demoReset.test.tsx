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
});
